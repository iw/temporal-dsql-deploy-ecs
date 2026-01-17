# -----------------------------------------------------------------------------
# Secrets Manager
# -----------------------------------------------------------------------------
# This file references externally-created secrets in AWS Secrets Manager.
# Requirements: 13.1, 13.2, 13.4
#
# IMPORTANT: The Grafana admin secret must be created BEFORE running Terraform.
# See README.md for instructions on creating the secret.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Grafana Admin Credentials Secret (External)
# -----------------------------------------------------------------------------
# References an externally-created secret containing Grafana admin credentials.
# The secret should be created once using AWS CLI:
#
#   PW="$(aws secretsmanager get-random-password \
#     --password-length 32 \
#     --exclude-punctuation \
#     --require-each-included-type \
#     --query RandomPassword \
#     --output text)"
#
#   aws secretsmanager create-secret \
#     --name grafana/admin \
#     --secret-string "{\"admin_user\":\"admin\",\"admin_password\":\"$PW\"}"
#
# The secret JSON structure:
# {
#   "admin_user": "admin",
#   "admin_password": "<generated-password>"
# }

data "aws_secretsmanager_secret" "grafana_admin" {
  name = var.grafana_admin_secret_name
}

data "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id = data.aws_secretsmanager_secret.grafana_admin.id
}
