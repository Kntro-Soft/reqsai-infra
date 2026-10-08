#!/usr/bin/env bash
# Moves the ReqsAI stack (Postgres data, Caddy certificates, images, config
# check) from the old host to the new one over SSH. Run it from the operator's
# machine; nothing is uploaded to public storage and no secret is printed.
#
# Usage: scripts/oci-migration/migrate.sh <command>
# Commands, in cutover order (see docs/oci-migration.md):
#   preflight     versions, sizes, free disk and running images on both hosts
#   config-diff   compare .env / api.env key by key (salted hashes, never values)
#   images        copy the reqsai-*:archive images from the old host to the new one
#   caddy-data    copy Caddy's /data (ACME account and certificates)
#   freeze        stop the API on the old host (no more writes)
#   dump          pg_dump -Fc on the old host, SHA-256 and per-table row counts
#   transfer      stream the dump old -> new over SSH and check the SHA-256
#   restore       recreate the database on the new host from the dump
#   verify        compare per-table row counts old vs new
#   start         start the whole stack on the new host and wait for health
#   smoke         HTTPS checks against the new IP with the production hostname
#   unfreeze      start the API again on the old host (rollback)
#
# Environment:
#   OLD_HOST, NEW_HOST   ssh destinations (aliases from ~/.ssh/config are best),
#                        or "local" to run on this machine (rehearsal only)
#   OLD_APP_DIR, NEW_APP_DIR   Compose project dirs (default /opt/reqsai)
#   OLD_WORK_DIR, NEW_WORK_DIR dump dirs on each host (default /var/backups/reqsai/migration)
#   LOCAL_DIR            local dir for state, counts and logs (default dist/migration)
#   KEEP_LOCAL_COPY=1    also keep a copy of the dump in LOCAL_DIR during transfer
#   SUDO                 privilege prefix on the hosts (default sudo; empty for local)
#   SSH_OPTS             extra ssh options, e.g. "-i ~/.ssh/id_ed25519"
#   APP_HOSTNAME, NEW_IP for smoke (production hostname resolved to the new IP)
#   ALLOW_LIVE_DUMP=1    let dump run while the old API is still up (rehearsals)
#   CHECKSUMS=1          dump/verify also compare an MD5 of every table's rows
#                        (reads every row; fine for the MVP database size)
#   IMAGES               images copied by "images" (default reqsai-api:archive reqsai-web:archive)
set -euo pipefail
umask 077

OLD_HOST="${OLD_HOST:-}"
NEW_HOST="${NEW_HOST:-}"
OLD_APP_DIR="${OLD_APP_DIR:-/opt/reqsai}"
NEW_APP_DIR="${NEW_APP_DIR:-/opt/reqsai}"
OLD_WORK_DIR="${OLD_WORK_DIR:-/var/backups/reqsai/migration}"
NEW_WORK_DIR="${NEW_WORK_DIR:-/var/backups/reqsai/migration}"
LOCAL_DIR="${LOCAL_DIR:-dist/migration}"
KEEP_LOCAL_COPY="${KEEP_LOCAL_COPY:-0}"
SUDO="${SUDO-sudo}"
SSH_OPTS="${SSH_OPTS:-}"
ALLOW_LIVE_DUMP="${ALLOW_LIVE_DUMP:-0}"
CHECKSUMS="${CHECKSUMS:-0}"
IMAGES="${IMAGES:-reqsai-api:archive reqsai-web:archive}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-900}"
STATE_FILE="${LOCAL_DIR}/state.env"

log() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

host_of() {
  case "$1" in
    old) [[ -n "${OLD_HOST}" ]] || die "OLD_HOST is not set"; printf '%s' "${OLD_HOST}" ;;
    new) [[ -n "${NEW_HOST}" ]] || die "NEW_HOST is not set"; printf '%s' "${NEW_HOST}" ;;
  esac
}

# exec_on <old|new> <command>: run a shell command on a host, stdin/stdout passed through.
exec_on() {
  local host
  host="$(host_of "$1")"
  if [[ "${host}" == local ]]; then
    bash -c "$2"
  else
    # shellcheck disable=SC2086 # SSH_OPTS is a list of options
    ssh -o BatchMode=yes ${SSH_OPTS} "${host}" "$2"
  fi
}

# on <old|new> [VAR=value ...] < script: run a bash script as root inside the
# Compose project dir of that host. The script travels base64-encoded in the
# command line, so the commands inside it never read it from stdin; stdin is
# /dev/null.
on() {
  local side="$1" dir work assignment script encoded
  shift
  if [[ "${side}" == old ]]; then dir="${OLD_APP_DIR}" work="${OLD_WORK_DIR}"; else dir="${NEW_APP_DIR}" work="${NEW_WORK_DIR}"; fi
  script="$(
    printf 'set -euo pipefail\numask 077\n'
    printf 'APP_DIR=%q\nWORK_DIR=%q\n' "${dir}" "${work}"
    for assignment in "$@"; do
      printf '%s=%q\n' "${assignment%%=*}" "${assignment#*=}"
    done
    # shellcheck disable=SC2016 # expanded on the host
    printf 'cd "${APP_DIR}"\n'
    cat
  )"
  if [[ "$(host_of "${side}")" == local ]]; then
    ${SUDO} bash -c "${script}" < /dev/null
  else
    encoded="$(printf '%s' "${script}" | base64 | tr -d '\n')"
    exec_on "${side}" "${SUDO:+${SUDO} }bash -c \"\$(printf %s '${encoded}' | base64 -d)\"" < /dev/null
  fi
}

save_state() {
  mkdir -p "${LOCAL_DIR}"
  printf 'DUMP_NAME=%q\nDUMP_SHA256=%q\nCHECKSUMS=%q\n' "$1" "$2" "${CHECKSUMS}" > "${STATE_FILE}"
}

load_state() {
  [[ -f "${STATE_FILE}" ]] || die "No ${STATE_FILE}; run dump first"
  # shellcheck disable=SC1090
  . "${STATE_FILE}"
  [[ "${DUMP_NAME:-}" =~ ^reqsai-migration-[0-9]{8}T[0-9]{6}Z\.dump$ ]] || die "Unexpected dump name in ${STATE_FILE}"
}

# Exact row count of every table outside the system schemas, one
# "schema.table count [md5]" per line. With CHECKSUMS=1 the third column is an
# MD5 of the table's rows rendered as text and sorted.
COUNT_ROWS_SQL="SELECT format('%s.%s', table_schema, table_name),
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text
       __CHECKSUM__
FROM information_schema.tables
WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY 1;"
CHECKSUM_SQL=", (xpath('/row/m/text()', query_to_xml(format('SELECT md5(coalesce(string_agg(t::text, %L ORDER BY t::text), %L)) AS m FROM %I.%I t', ',', '', table_schema, table_name), false, true, '')))[1]::text"

count_rows() {
  local sql="${COUNT_ROWS_SQL/__CHECKSUM__/}"
  if [[ "${CHECKSUMS}" == 1 ]]; then sql="${COUNT_ROWS_SQL/__CHECKSUM__/${CHECKSUM_SQL}}"; fi
  on "$1" SQL="${sql}" <<'EOF'
printf '%s\n' "${SQL}" | docker compose exec -T db sh -c 'psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --no-psqlrc -v ON_ERROR_STOP=1 -At -F " "'
EOF
}

cmd_preflight() {
  local side
  for side in old new; do
    log "== ${side} ($(host_of "${side}"))"
    on "${side}" IMAGES="${IMAGES}" <<'EOF'
docker compose ps --format '{{.Service}} {{.State}} {{.Status}}'
docker compose exec -T db sh -c 'psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --no-psqlrc -At -F " " -c "SHOW server_version" -c "SELECT pg_size_pretty(pg_database_size(current_database()))" -c "SELECT extname, extversion FROM pg_extension ORDER BY 1"' | sed 's/^/postgres: /'
docker image inspect ${IMAGES} \
  --format '{{ index .RepoTags 0 }} {{ index .Config.Labels "org.opencontainers.image.revision" }} {{ .Id }}' 2>/dev/null \
  | sed 's/^/image: /' || echo "image: missing (${IMAGES})"
mkdir -p "${WORK_DIR}"
df -h "${WORK_DIR}" | tail -n 1 | awk '{print "free disk in work dir: " $4}'
EOF
  done
}

cmd_freeze() {
  log "Stopping the API on the old host; the site keeps serving the web app but every /api call fails until cutover"
  on old <<'EOF'
docker compose stop api
docker compose ps --format '{{.Service}} {{.State}}'
EOF
}

cmd_unfreeze() {
  log "Starting the API again on the old host"
  on old <<'EOF'
docker compose start api
docker compose ps --format '{{.Service}} {{.State}}'
EOF
}

cmd_dump() {
  local stamp name output sha
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  name="reqsai-migration-${stamp}.dump"
  log "Dumping the old database to ${OLD_WORK_DIR}/${name}"
  output="$(on old NAME="${name}" ALLOW_LIVE_DUMP="${ALLOW_LIVE_DUMP}" <<'EOF'
if docker compose ps --status running --services | grep -qx api && [ "${ALLOW_LIVE_DUMP}" != 1 ]; then
  echo "The API is still running on this host; run freeze first (or ALLOW_LIVE_DUMP=1 for a rehearsal)" >&2
  exit 1
fi
mkdir -p "${WORK_DIR}"
docker compose exec -T db sh -c 'pg_dump --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --format=custom --compress=6' > "${WORK_DIR}/${NAME}.partial"
mv "${WORK_DIR}/${NAME}.partial" "${WORK_DIR}/${NAME}"
(cd "${WORK_DIR}" && sha256sum "${NAME}" > "${NAME}.sha256")
echo "size $(du -h "${WORK_DIR}/${NAME}" | cut -f1)"
echo "sha256 $(cut -d' ' -f1 "${WORK_DIR}/${NAME}.sha256")"
EOF
)"
  printf '%s\n' "${output}" >&2
  sha="$(printf '%s\n' "${output}" | awk '$1 == "sha256" {print $2}')"
  [[ "${sha}" =~ ^[0-9a-f]{64}$ ]] || die "Could not read the dump checksum"
  save_state "${name}" "${sha}"
  log "Counting rows on the old host"
  count_rows old > "${LOCAL_DIR}/counts-old.txt"
  log "$(wc -l < "${LOCAL_DIR}/counts-old.txt" | tr -d ' ') tables counted -> ${LOCAL_DIR}/counts-old.txt"
}

cmd_transfer() {
  local sha
  load_state
  log "Streaming ${DUMP_NAME} old -> new over SSH"
  if [[ "${KEEP_LOCAL_COPY}" == 1 ]]; then
    mkdir -p "${LOCAL_DIR}"
    exec_on old "${SUDO:+${SUDO} }cat '${OLD_WORK_DIR}/${DUMP_NAME}'" < /dev/null \
      | tee "${LOCAL_DIR}/${DUMP_NAME}" \
      | exec_on new "${SUDO:+${SUDO} }sh -c 'umask 077 && mkdir -p ${NEW_WORK_DIR} && cat > ${NEW_WORK_DIR}/${DUMP_NAME}.partial'"
    log "Local copy kept at ${LOCAL_DIR}/${DUMP_NAME} (contains personal data: delete it after the rollback window)"
  else
    exec_on old "${SUDO:+${SUDO} }cat '${OLD_WORK_DIR}/${DUMP_NAME}'" < /dev/null \
      | exec_on new "${SUDO:+${SUDO} }sh -c 'umask 077 && mkdir -p ${NEW_WORK_DIR} && cat > ${NEW_WORK_DIR}/${DUMP_NAME}.partial'"
  fi
  sha="$(on new NAME="${DUMP_NAME}" <<'EOF'
mv "${WORK_DIR}/${NAME}.partial" "${WORK_DIR}/${NAME}"
sha256sum "${WORK_DIR}/${NAME}" | cut -d' ' -f1
EOF
)"
  [[ "${sha}" == "${DUMP_SHA256}" ]] || die "Checksum mismatch: old ${DUMP_SHA256}, new ${sha}"
  log "Checksum OK on the new host: ${sha}"
}

cmd_restore() {
  load_state
  log "Restoring ${DUMP_NAME} on the new host (the new database is dropped and recreated)"
  on new NAME="${DUMP_NAME}" SHA="${DUMP_SHA256}" <<'EOF'
[ "$(sha256sum "${WORK_DIR}/${NAME}" | cut -d' ' -f1)" = "${SHA}" ] || { echo "Checksum mismatch before restore" >&2; exit 1; }
docker compose stop api
docker compose exec -T db sh -c 'dropdb --username="$POSTGRES_USER" --if-exists --force "$POSTGRES_DB" && createdb --username="$POSTGRES_USER" "$POSTGRES_DB"'
docker compose exec -T db sh -c 'pg_restore --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --no-owner --no-privileges --exit-on-error' < "${WORK_DIR}/${NAME}"
docker compose exec -T db sh -c 'vacuumdb --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --analyze-only --quiet'
echo "restored ${NAME}"
EOF
}

cmd_verify() {
  load_state
  [[ -s "${LOCAL_DIR}/counts-old.txt" ]] || die "No ${LOCAL_DIR}/counts-old.txt; run dump first"
  log "Counting rows on the new host"
  count_rows new > "${LOCAL_DIR}/counts-new.txt"
  if diff -u "${LOCAL_DIR}/counts-old.txt" "${LOCAL_DIR}/counts-new.txt" > "${LOCAL_DIR}/counts.diff"; then
    log "Row counts match on $(wc -l < "${LOCAL_DIR}/counts-new.txt" | tr -d ' ') tables, $(awk '{s += $2} END {print s}' "${LOCAL_DIR}/counts-new.txt") rows"
  else
    cat "${LOCAL_DIR}/counts.diff" >&2
    die "Row counts differ (${LOCAL_DIR}/counts.diff)"
  fi
}

cmd_caddy_data() {
  log "Copying Caddy /data (ACME account and certificates) old -> new"
  exec_on old "cd '${OLD_APP_DIR}' && ${SUDO:+${SUDO} }docker compose run --rm --no-deps -T --entrypoint tar caddy -C /data -czf - ." < /dev/null \
    | exec_on new "cd '${NEW_APP_DIR}' && ${SUDO:+${SUDO} }docker compose run --rm --no-deps -T --entrypoint sh caddy -c 'tar -C /data -xzf - && rm -rf /data/caddy/locks'"
  on new <<'EOF'
if docker compose ps --status running --services | grep -qx caddy; then docker compose restart caddy; fi
docker compose run --rm --no-deps -T --entrypoint sh caddy -c 'find /data/caddy/certificates -name "*.crt" 2>/dev/null | sed "s#^/data/caddy/certificates/##"' | sed 's/^/certificate: /'
EOF
}

cmd_images() {
  [[ "${IMAGES}" =~ ^[A-Za-z0-9._/:@\ -]+$ ]] || die "Unsupported IMAGES: ${IMAGES}"
  log "Copying ${IMAGES} old -> new"
  exec_on old "${SUDO:+${SUDO} }docker save ${IMAGES} | gzip -1" < /dev/null \
    | exec_on new "gunzip | ${SUDO:+${SUDO} }docker load"
}

cmd_start() {
  log "Starting the stack on the new host"
  on new HEALTH_TIMEOUT="${HEALTH_TIMEOUT}" <<'EOF'
docker compose up -d --wait --wait-timeout "${HEALTH_TIMEOUT}"
docker compose ps --format '{{.Service}} {{.State}} {{.Status}}'
EOF
}

cmd_smoke() {
  [[ -n "${APP_HOSTNAME:-}" && -n "${NEW_IP:-}" ]] || die "Set APP_HOSTNAME (e.g. reqsai.tech) and NEW_IP"
  local base="https://${APP_HOSTNAME}" resolve="${APP_HOSTNAME}:443:${NEW_IP}" status policy
  status="$(curl -fsS --max-time 15 --resolve "${resolve}" "${base}/actuator/health" | tr -d '\n')"
  log "health: ${status}"
  [[ "${status}" == *'"UP"'* ]] || die "${base}/actuator/health is not UP on ${NEW_IP}"
  policy="$(curl -fsS --max-time 15 --resolve "${resolve}" -o /dev/null -D - "${base}/" | tr -d '\r' | awk -F': ' 'tolower($1) == "permissions-policy" {print $2}')"
  log "permissions-policy: ${policy}"
  [[ "${policy}" == *'microphone=(self)'* ]] || die "The web app does not allow the microphone"
  log "Certificate served by ${NEW_IP}:"
  curl -sS --max-time 15 --resolve "${resolve}" -o /dev/null -w '  verify_result=%{ssl_verify_result} http=%{http_code}\n' "${base}/" >&2
}

cmd_config_diff() {
  local salt side
  salt="$(openssl rand -hex 16)"
  for side in old new; do
    on "${side}" SALT="${salt}" > "${LOCAL_DIR}/config-${side}.txt" <<'EOF'
for file in .env api.env; do
  [ -f "${file}" ] || continue
  SALT="${SALT}" python3 -c '
import hashlib, hmac, os, sys
salt = os.environ["SALT"].encode()
path = sys.argv[1]
for line in open(path, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\x27\"":
        value = value[1:-1]
    print(path, key, hmac.new(salt, value.encode(), hashlib.sha256).hexdigest()[:16])
' "${file}"
done
EOF
  done
  python3 - "${LOCAL_DIR}/config-old.txt" "${LOCAL_DIR}/config-new.txt" <<'PY'
import sys
def load(path):
    out = {}
    for line in open(path):
        f, k, h = line.split()
        out[(f, k)] = h
    return out
old, new = load(sys.argv[1]), load(sys.argv[2])
for key in sorted(set(old) | set(new)):
    if key not in new:
        state = "missing on new"
    elif key not in old:
        state = "only on new"
    else:
        state = "same" if old[key] == new[key] else "DIFFERENT"
    print(f"{key[0]:8} {key[1]:36} {state}")
PY
}

main() {
  local path
  for path in "${OLD_APP_DIR}" "${NEW_APP_DIR}" "${OLD_WORK_DIR}" "${NEW_WORK_DIR}"; do
    [[ "${path}" =~ ^/[A-Za-z0-9/._-]+$ ]] || die "Unsupported path: ${path}"
  done
  mkdir -p "${LOCAL_DIR}"
  case "${1:-}" in
    preflight) cmd_preflight ;;
    config-diff) cmd_config_diff ;;
    images) cmd_images ;;
    caddy-data) cmd_caddy_data ;;
    freeze) cmd_freeze ;;
    dump) cmd_dump ;;
    transfer) cmd_transfer ;;
    restore) cmd_restore ;;
    verify) cmd_verify ;;
    start) cmd_start ;;
    smoke) cmd_smoke ;;
    unfreeze) cmd_unfreeze ;;
    *) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 2 ;;
  esac
}

main "$@"
