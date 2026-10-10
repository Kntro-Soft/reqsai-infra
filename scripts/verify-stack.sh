#!/usr/bin/env bash
# Verifies a release candidate of reqsai-infra without touching the MVP host: it starts compose/compose.yaml and
# the Caddyfile of this commit with the given application images (PostgreSQL + API + web + Caddy over plain HTTP),
# checks the routes the host serves, then runs the rendered backup and restore scripts of the backup role
# against that database and checks the API again. There is no second EC2 for a staging environment; this
# ephemeral run replaces it. Everything is removed at the end.
#
# Usage: scripts/verify-stack.sh <api-image> <web-image>
# Needs docker with compose, curl, jq, openssl and ansible (to render the backup role templates).
set -euo pipefail

api_image="${1:?usage: verify-stack.sh <api-image> <web-image>}"
web_image="${2:?usage: verify-stack.sh <api-image> <web-image>}"
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
stack="$work/stack"
base=http://localhost
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
passed=false
# A project name of its own, so the run never touches another "reqsai" Compose project on the same machine.
# The rendered backup and restore scripts inherit it.
export COMPOSE_PROJECT_NAME="reqsai-verify-$$"

compose() { docker compose --file "$stack/compose.yaml" --project-directory "$stack" "$@"; }

cleanup() {
  if [[ "$passed" != true ]]; then
    echo "::group::Stack logs"
    compose ps --all 2>&1 || true
    compose logs --no-color --tail 80 2>&1 || true
    echo "::endgroup::"
  fi
  compose down --volumes >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

check() {
  echo "| $1 | $2 |" >>"$summary"
  echo "ok: $1 ($2)"
}

fail() {
  echo "| $1 | **failed**: $2 |" >>"$summary"
  echo "::error::$1: $2"
  exit 1
}

wait_ready() {
  local status=""
  for _ in $(seq 1 90); do
    status=$(curl -fsS --max-time 5 "$base/actuator/health/readiness" 2>/dev/null | jq -r '.status // empty' || true)
    [[ "$status" == UP ]] && return 0
    sleep 5
  done
  fail "$1" "/actuator/health/readiness through Caddy is '${status:-unreachable}'"
}

cp -R "$root/compose" "$stack"

# Throwaway secrets: a fresh RSA key pair for the JWTs, a random encryption key and database password, and
# placeholder AI keys (the clients need a value to start; no AI call is made).
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/private.pem" 2>/dev/null
openssl pkey -in "$work/private.pem" -pubout -out "$work/public.pem"
pem_body() { grep -v -- '-----' "$1" | tr -d '\n'; }
db_password=$(openssl rand -hex 16)

# The same variables Ansible renders on the host (roles/app/vars/main.yml, memory profile "small"), over HTTP.
cat >"$stack/.env" <<EOF
APP_HOSTNAME=http://localhost
ACME_EMAIL=verify@reqsai.test
API_IMAGE=$api_image
WEB_IMAGE=$web_image
POSTGRES_IMAGE=pgvector/pgvector:0.8.7-pg16
CADDY_IMAGE=caddy:2.11-alpine
POSTGRES_DB=reqsai
POSTGRES_USER=reqsai
POSTGRES_PASSWORD=$db_password
POSTGRES_SHARED_BUFFERS=128MB
POSTGRES_EFFECTIVE_CACHE_SIZE=512MB
POSTGRES_WORK_MEM=4MB
POSTGRES_MAINTENANCE_WORK_MEM=64MB
POSTGRES_MAX_CONNECTIONS=40
DB_MEM_LIMIT=512m
API_MEM_LIMIT=1024m
WEB_MEM_LIMIT=64m
CADDY_MEM_LIMIT=128m
API_JAVA_OPTS=-Xms256m -Xmx512m -XX:MaxMetaspaceSize=256m -XX:ReservedCodeCacheSize=64m -Xss512k -XX:+UseSerialGC -XX:+ExitOnOutOfMemoryError
EOF

cat >"$stack/api.env" <<EOF
SPRING_PROFILES_ACTIVE=prod
SERVER_FORWARD_HEADERS_STRATEGY=native
APP_URL=$base
FRONTEND_URL=$base
WEB_APP_URL=$base
CORS_ALLOWED_ORIGINS=$base
DB_HOST=db
DB_PORT=5432
DB_NAME=reqsai
DB_USERNAME=reqsai
DB_PASSWORD=$db_password
DB_POOL_SIZE=10
JWT_ISSUER=reqsai
JWT_PRIVATE_KEY_PEM=$(pem_body "$work/private.pem")
JWT_PUBLIC_KEY_PEM=$(pem_body "$work/public.pem")
INTEGRATIONS_ENCRYPTION_KEY=$(openssl rand -base64 32)
GEMINI_API_KEY=verification-placeholder
ASSEMBLYAI_API_KEY=verification-placeholder
BILLING_PAYMENT_PROVIDER=fake
SPRINGDOC_API_DOCS_ENABLED=false
SPRINGDOC_SWAGGER_UI_ENABLED=false
EOF

{
  echo "### Verification of the stack"
  echo
  echo "- API: \`$api_image\`"
  echo "- Web: \`$web_image\`"
  echo
  echo "| Check | Result |"
  echo "| --- | --- |"
} >>"$summary"

compose config --quiet || fail "Compose file" "docker compose config rejected it"
check "Compose file" "valid"

compose up --detach --quiet-pull --wait --wait-timeout 900 || fail "Stack start" "a service did not become healthy"
check "Stack start (db, api, web, caddy healthy)" "up"

wait_ready "API through Caddy"
check "API readiness through Caddy" "UP"

code=$(curl -sS -o "$work/index.html" -D "$work/index.headers" -w '%{http_code}' "$base/")
[[ "$code" == 200 ]] || fail "Web through Caddy" "/ answered HTTP $code"
grep -q '<app-root' "$work/index.html" || fail "Web through Caddy" "/ is not the Angular shell"
grep -qi '^permissions-policy: .*microphone=(self)' "$work/index.headers" \
  || fail "Web through Caddy" "Caddy did not set microphone=(self)"
check "Web through Caddy (microphone policy)" "HTTP 200"

code=$(curl -sS -o /dev/null -D "$work/i18n.headers" -w '%{http_code}' "$base/i18n/es.json")
[[ "$code" == 200 ]] || fail "Translations" "/i18n/es.json answered HTTP $code"
grep -qi '^cache-control: .*no-cache' "$work/i18n.headers" || fail "Translations" "/i18n/* is cacheable"
check "Translations served with no-cache" "HTTP 200"

code=$(curl -sS -o /dev/null -w '%{http_code}' "$base/api/organizations")
[[ "$code" == 401 ]] || fail "API route" "/api/organizations without a token answered HTTP $code"
check "API route without a token" "HTTP 401"

# The backup role: render its scripts for this stack and run a dump and a restore, as a deploy and a rollback do.
mkdir -p "$work/backups" "$work/bin"
for script in reqsai-backup reqsai-restore; do
  ansible localhost --connection local --module-name ansible.builtin.template \
    --args "src=$root/ansible/roles/backup/templates/$script.j2 dest=$work/bin/$script mode=0755" \
    --extra-vars "backup_app_dir=$stack backup_dir=$work/backups backup_keep=7 backup_s3_bucket= backup_aws_region=us-east-1" \
    >/dev/null || fail "Backup role" "could not render $script"
done
"$work/bin/reqsai-backup" >/dev/null || fail "Backup" "reqsai-backup failed"
dump=$(find "$work/backups" -name 'reqsai-*.dump' -size +0 | head -n 1)
[[ -n "$dump" ]] || fail "Backup" "no dump written"
check "Backup (reqsai-backup)" "$(du -h "$dump" | cut -f1) dump"

"$work/bin/reqsai-restore" "$dump" >/dev/null || fail "Restore" "reqsai-restore failed"
wait_ready "API after the restore"
check "Restore (reqsai-restore) and API readiness" "UP"

passed=true
echo "Stack verified with $api_image and $web_image"
