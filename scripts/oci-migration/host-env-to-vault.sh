#!/usr/bin/env bash
# Rebuilds an Ansible Vault file from the env files a host is running with
# (/opt/reqsai/.env and api.env). Use it only if the vault on your machine is
# lost or out of date: normally ansible/group_vars/reqsai/vault.yml already
# holds every secret and moves to OCI unchanged.
#
# The values travel ssh -> python -> ansible-vault through pipes. They are never
# printed and never written unencrypted; stderr lists only key names.
#
# Usage: OLD_HOST=reqsai-aws scripts/oci-migration/host-env-to-vault.sh
#   OLD_HOST             ssh destination of the running host (required)
#   APP_DIR              Compose project dir on the host (default /opt/reqsai)
#   VAULT_PASSWORD_FILE  vault password file (default .vault-pass)
#   OUT                  encrypted output (default dist/migration/vault.from-host.yml, ignored by git)
#   SSH_OPTS             extra ssh options
set -euo pipefail
umask 077

OLD_HOST="${OLD_HOST:?set OLD_HOST to the ssh destination of the running host}"
APP_DIR="${APP_DIR:-/opt/reqsai}"
VAULT_PASSWORD_FILE="${VAULT_PASSWORD_FILE:-.vault-pass}"
OUT="${OUT:-dist/migration/vault.from-host.yml}"
SSH_OPTS="${SSH_OPTS:-}"

[[ "${APP_DIR}" =~ ^/[A-Za-z0-9/._-]+$ ]] || { echo "Unsupported APP_DIR: ${APP_DIR}" >&2; exit 1; }
[[ -s "${VAULT_PASSWORD_FILE}" ]] || { echo "Vault password file not found: ${VAULT_PASSWORD_FILE}" >&2; exit 1; }
[[ ! -e "${OUT}" ]] || { echo "${OUT} already exists; move it away first" >&2; exit 1; }
mkdir -p "$(dirname "${OUT}")"

# shellcheck disable=SC2086 # SSH_OPTS is a list of options
ssh -o BatchMode=yes ${SSH_OPTS} "${OLD_HOST}" \
  "sudo sh -c 'cd ${APP_DIR} && for f in .env api.env; do echo \"### \$f\"; cat \"\$f\"; done'" < /dev/null \
  | python3 -I -c '
import json, sys, textwrap

env = {}
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\x27\"":
        value = value[1:-1]
    env[key] = value

def pem(body, kind):
    if not body:
        return ""
    return "-----BEGIN %s-----\n%s\n-----END %s-----\n" % (kind, "\n".join(textwrap.wrap(body, 64)), kind)

vault = {
    "vault_postgres_password": env.get("POSTGRES_PASSWORD") or env.get("DB_PASSWORD", ""),
    "vault_registry_password": "",
    "vault_git_token": "",
    "vault_jwt_private_key_pem": pem(env.get("JWT_PRIVATE_KEY_PEM", ""), "PRIVATE KEY"),
    "vault_jwt_public_key_pem": pem(env.get("JWT_PUBLIC_KEY_PEM", ""), "PUBLIC KEY"),
    "vault_integrations_encryption_key": env.get("INTEGRATIONS_ENCRYPTION_KEY", ""),
    "vault_assemblyai_api_key": env.get("ASSEMBLYAI_API_KEY", ""),
    "vault_gemini_api_key": env.get("GEMINI_API_KEY", ""),
    "vault_deepgram_api_key": env.get("DEEPGRAM_API_KEY", ""),
    "vault_openai_api_key": env.get("OPENAI_API_KEY", ""),
    "vault_mail_username": env.get("MAIL_USERNAME", ""),
    "vault_mail_password": env.get("MAIL_PASSWORD", ""),
    "vault_stripe_api_key": env.get("STRIPE_API_KEY", ""),
    "vault_stripe_webhook_secret": env.get("STRIPE_WEBHOOK_SECRET", ""),
    "vault_jira_oauth_client_id": env.get("JIRA_OAUTH_CLIENT_ID", ""),
    "vault_jira_oauth_client_secret": env.get("JIRA_OAUTH_CLIENT_SECRET", ""),
    "vault_jira_oauth_state_secret": env.get("JIRA_OAUTH_STATE_SECRET", ""),
    "vault_backup_s3_access_key_id": "",
    "vault_backup_s3_secret_access_key": "",
}
if not env:
    sys.exit("No variables read from the host")
for key, value in vault.items():
    if value.startswith("-----BEGIN"):
        sys.stdout.write("%s: |\n%s" % (key, textwrap.indent(value, "  ")))
    else:
        sys.stdout.write("%s: %s\n" % (key, json.dumps(value)))
    sys.stderr.write("%-36s %s\n" % (key, "filled" if value else "EMPTY"))
' \
  | ansible-vault encrypt --vault-password-file "${VAULT_PASSWORD_FILE}" --output "${OUT}"

echo "Wrote ${OUT} (encrypted). Compare it with: ansible-vault view ${OUT} | less" >&2
echo "The registry password and git token are not in the env files; copy them from the current vault if you use them." >&2
