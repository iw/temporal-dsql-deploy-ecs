#!/usr/bin/env sh
set -eu

# Substitute environment variables in datasources.yaml
# AMP_ENDPOINT - Amazon Managed Prometheus endpoint URL
# AWS_REGION - AWS region for SigV4 auth and CloudWatch

DATASOURCES_FILE="/etc/grafana/provisioning/datasources/datasources.yaml"

if [ -n "${AMP_ENDPOINT:-}" ]; then
    sed -i "s|\${AMP_ENDPOINT}|${AMP_ENDPOINT}|g" "$DATASOURCES_FILE"
fi

if [ -n "${AWS_REGION:-}" ]; then
    sed -i "s|\${AWS_REGION}|${AWS_REGION}|g" "$DATASOURCES_FILE"
fi

exec /run.sh
