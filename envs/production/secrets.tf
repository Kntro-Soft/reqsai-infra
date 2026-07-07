# Secret containers only — no aws_secretsmanager_secret_version here on
# purpose. The actual values are never typed into Terraform code, tfvars,
# or state; they're set out-of-band with `aws secretsmanager put-secret-value`
# (see docs in this repo's README) so they never touch this repository or
# this chat.

resource "aws_secretsmanager_secret" "jwt" {
  name        = "reqsai/${var.environment}/jwt"
  description = "JWT RS256 signing keys for reqsai-api (private_key_pem, public_key_pem)."
}

resource "aws_secretsmanager_secret" "smtp" {
  name        = "reqsai/${var.environment}/smtp"
  description = "SMTP credentials for reqsai-api transactional email (username, password)."
}

resource "aws_secretsmanager_secret" "ai" {
  name        = "reqsai/${var.environment}/ai"
  description = "Third-party AI API keys for reqsai-api (deepgram_api_key, openai_api_key)."
}
