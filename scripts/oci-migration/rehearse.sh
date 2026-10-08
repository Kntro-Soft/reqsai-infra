#!/usr/bin/env bash
# End-to-end rehearsal of migrate.sh against two throwaway Compose projects on
# the local Docker daemon, standing in for the old (AWS) and new (OCI) hosts.
# Never touches a real host: "ssh" and "sudo" are local stubs that run the
# exact command string migrate.sh would send. Fake data only.
#
# Usage: scripts/oci-migration/rehearse.sh            (KEEP=1 keeps the temp dir and containers)
set -euo pipefail

POSTGRES_IMAGE="${POSTGRES_IMAGE:-pgvector/pgvector:0.8.7-pg16}"
CADDY_IMAGE="${CADDY_IMAGE:-caddy:2.11-alpine}"
ROWS="${ROWS:-20000}"
KEEP="${KEEP:-0}"

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/reqsai-rehearsal.XXXXXX")"
pass=0

log() { printf '\n### %s\n' "$*"; }
ok() { pass=$((pass + 1)); printf 'PASS %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

compose() { docker compose --project-directory "${work}/$1/app" "${@:2}"; }

cleanup() {
  if [[ "${KEEP}" == 1 ]]; then
    echo "Kept ${work}"
    return
  fi
  for side in old new; do
    compose "${side}" down --volumes --remove-orphans >/dev/null 2>&1 || true
  done
  docker image rm reqsai-rehearsal-api:archive reqsai-rehearsal-web:archive >/dev/null 2>&1 || true
  rm -rf "${work}"
}
trap cleanup EXIT

# Stubs: "ssh [opts] <host> <command>" runs <command> through bash, like the
# remote login shell would; "sudo <cmd>" just runs <cmd>.
mkdir -p "${work}/bin"
cat > "${work}/bin/ssh" <<'EOF'
#!/usr/bin/env bash
exec bash -c "${@: -1}"
EOF
cat > "${work}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
chmod +x "${work}/bin/ssh" "${work}/bin/sudo"

for side in old new; do
  mkdir -p "${work}/${side}/app" "${work}/${side}/backups"
  cat > "${work}/${side}/app/compose.yaml" <<EOF
name: reqsai-rehearsal-${side}
services:
  db:
    image: ${POSTGRES_IMAGE}
    environment:
      POSTGRES_DB: reqsai
      POSTGRES_USER: reqsai
      POSTGRES_PASSWORD: rehearsal-only-password
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U reqsai -d reqsai"]
      interval: 2s
      retries: 30
  api:
    image: ${CADDY_IMAGE}
    entrypoint: ["sleep", "infinity"]
    depends_on:
      db:
        condition: service_healthy
  caddy:
    image: ${CADDY_IMAGE}
    entrypoint: ["sleep", "infinity"]
    volumes:
      - caddy-data:/data
volumes:
  db-data: {}
  caddy-data: {}
EOF
  printf "POSTGRES_PASSWORD='rehearsal-only-password'\nAPI_JAVA_OPTS='-Xmx512m'\n" > "${work}/${side}/app/.env"
  printf "GEMINI_API_KEY='fake-key-123'\nDB_PASSWORD='rehearsal-only-password'\nAPP_URL='https://reqsai.example'\n" > "${work}/${side}/app/api.env"
done
# The new host gets a different JVM option and lacks one key, like a new memory profile would.
printf "POSTGRES_PASSWORD='rehearsal-only-password'\nAPI_JAVA_OPTS='-Xmx1024m'\n" > "${work}/new/app/.env"
printf "GEMINI_API_KEY='fake-key-123'\nDB_PASSWORD='rehearsal-only-password'\n" > "${work}/new/app/api.env"

log "Starting both stacks (${POSTGRES_IMAGE})"
for side in old new; do compose "${side}" up -d --wait --quiet-pull >/dev/null 2>&1; done
ok "both stacks healthy"

log "Seeding ${ROWS} fake rows per tenant on the old host"
compose old exec -T db psql -U reqsai -d reqsai -v ON_ERROR_STOP=1 -q <<SQL
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE public.flyway_schema_history (installed_rank int PRIMARY KEY, version text, success boolean);
INSERT INTO public.flyway_schema_history SELECT g, '2026' || g, true FROM generate_series(1, 40) g;
CREATE TABLE public.users (id bigserial PRIMARY KEY, email text UNIQUE, avatar bytea, created_at timestamptz DEFAULT now());
INSERT INTO public.users (email, avatar) SELECT 'user' || g || '@example.test', decode(md5(g::text), 'hex') FROM generate_series(1, 500) g;
DO \$\$
DECLARE s text;
BEGIN
  FOREACH s IN ARRAY ARRAY['tenant_acme', 'tenant_beta'] LOOP
    EXECUTE format('CREATE SCHEMA %I', s);
    EXECUTE format('CREATE TABLE %I.segments (id bigserial PRIMARY KEY, body text, meta jsonb, embedding vector(3))', s);
    EXECUTE format('INSERT INTO %I.segments (body, meta, embedding) SELECT repeat(%L, 3) || g, jsonb_build_object(%L, g), ARRAY[g, g / 2.0, g / 3.0]::vector FROM generate_series(1, ${ROWS}) g', s, 'lorem ', 'n');
    EXECUTE format('CREATE INDEX ON %I.segments USING hnsw (embedding vector_l2_ops)', s);
    EXECUTE format('CREATE TABLE %I.empty_table (id int)', s);
  END LOOP;
END
\$\$;
SQL
ok "fake data seeded"

compose old run --rm --no-deps -T --quiet-pull --entrypoint sh caddy -c \
  'mkdir -p /data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/reqsai.example && echo fake-cert > /data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/reqsai.example/reqsai.example.crt && mkdir -p /data/caddy/locks && touch /data/caddy/locks/stale.lock' 2>/dev/null

docker image tag "${CADDY_IMAGE}" reqsai-rehearsal-api:archive
docker image tag "${CADDY_IMAGE}" reqsai-rehearsal-web:archive

export PATH="${work}/bin:${PATH}"
export OLD_HOST=rehearsal-old NEW_HOST=rehearsal-new SUDO=sudo
export OLD_APP_DIR="${work}/old/app" NEW_APP_DIR="${work}/new/app"
export OLD_WORK_DIR="${work}/old/backups" NEW_WORK_DIR="${work}/new/backups"
export LOCAL_DIR="${work}/local" CHECKSUMS=1
export IMAGES="reqsai-rehearsal-api:archive reqsai-rehearsal-web:archive"
migrate="${here}/migrate.sh"

log "preflight"
"${migrate}" preflight 2>&1 | tee "${work}/preflight.log"
grep -q 'postgres: 16' "${work}/preflight.log" || fail "preflight did not report Postgres 16"
grep -q 'postgres: vector 0.8' "${work}/preflight.log" || fail "preflight did not report pgvector"
ok "preflight reports versions on both hosts"

log "config-diff"
"${migrate}" config-diff | tee "${work}/config.log"
grep -Eq '^api.env +GEMINI_API_KEY +same$' "${work}/config.log" || fail "config-diff: GEMINI_API_KEY should be same"
grep -Eq '^.env +API_JAVA_OPTS +DIFFERENT$' "${work}/config.log" || fail "config-diff: API_JAVA_OPTS should differ"
grep -Eq '^api.env +APP_URL +missing on new$' "${work}/config.log" || fail "config-diff: APP_URL should be missing"
if grep -Rq 'fake-key-123\|rehearsal-only-password' "${work}/config.log" "${LOCAL_DIR}"; then fail "config-diff leaked a value"; fi
ok "config-diff compares keys without printing values"

log "images"
"${migrate}" images
ok "images streamed through docker save | docker load"

log "caddy-data"
"${migrate}" caddy-data | tee "${work}/caddy.log"
compose new run --rm --no-deps -T --entrypoint cat caddy \
  /data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/reqsai.example/reqsai.example.crt | grep -qx fake-cert \
  || fail "certificate not copied"
if compose new run --rm --no-deps -T --entrypoint ls caddy /data/caddy/locks >/dev/null 2>&1; then fail "stale locks were copied"; fi
ok "Caddy data copied without locks"

log "dump refuses to run while the old API is up"
if "${migrate}" dump 2>"${work}/dump-refused.log"; then fail "dump ran with the API up"; fi
grep -q 'run freeze first' "${work}/dump-refused.log" || fail "unexpected dump error"
ok "dump requires freeze"

log "freeze, dump, transfer, restore, verify"
"${migrate}" freeze
[[ -z "$(compose old ps --status running --services | grep -x api || true)" ]] || fail "api still running after freeze"
"${migrate}" dump
"${migrate}" transfer
"${migrate}" restore
"${migrate}" verify
ok "row counts and per-table MD5 match after restore"

log "verify catches a changed value with the same row count (CHECKSUMS=1)"
compose new exec -T db psql -U reqsai -d reqsai -q -c "UPDATE tenant_acme.segments SET body = 'tampered' WHERE id = 42"
if "${migrate}" verify 2>/dev/null; then fail "verify missed a changed value"; fi
ok "verify fails on a changed value"

log "verify catches a difference"
compose new exec -T db psql -U reqsai -d reqsai -q -c 'DELETE FROM tenant_beta.segments WHERE id = 7'
if "${migrate}" verify 2>/dev/null; then fail "verify missed a deleted row"; fi
ok "verify fails on a missing row"

log "restore rejects a corrupted dump"
# shellcheck disable=SC1091
. "${LOCAL_DIR}/state.env"
printf 'x' >> "${NEW_WORK_DIR}/${DUMP_NAME}"
if "${migrate}" restore 2>/dev/null; then fail "restore accepted a corrupted dump"; fi
ok "restore checks the SHA-256 first"

log "re-transfer and restore after the failures"
"${migrate}" transfer
"${migrate}" restore
"${migrate}" verify
ok "clean restore verified again"

log "pgvector index and query work on the new host"
compose new exec -T db psql -U reqsai -d reqsai -At -c \
  "SET enable_seqscan = off; SELECT id FROM tenant_acme.segments ORDER BY embedding <-> '[3,1.5,1]' LIMIT 1" | grep -qx 3 \
  || fail "vector query failed"
ok "vector similarity query returns the expected row"

log "start and unfreeze"
"${migrate}" start
"${migrate}" unfreeze
[[ -n "$(compose old ps --status running --services | grep -x api || true)" ]] || fail "api not running after unfreeze"
ok "start and rollback (unfreeze) work"

find "${OLD_WORK_DIR}" "${NEW_WORK_DIR}" -type f -name '*.dump' -perm -044 | grep -q . && fail "dump files are group/world readable"
ok "dump files are private (umask 077)"

printf '\nRehearsal passed: %d checks.\n' "${pass}"
