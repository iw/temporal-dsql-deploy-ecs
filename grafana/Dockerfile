# Custom Grafana image with pre-configured datasources and dashboards
# for Temporal DSQL ECS deployment
#
# Build: docker build -t temporal-grafana:latest grafana/
# 
# Environment variables (set in ECS task definition):
#   AMP_ENDPOINT - Amazon Managed Prometheus query endpoint
#   AWS_REGION - AWS region for SigV4 auth and CloudWatch

FROM grafana/grafana-oss:latest

# Copy provisioning configuration
COPY provisioning/ /etc/grafana/provisioning/

# Copy dashboards
COPY server/ /var/lib/grafana/dashboards/server/
COPY dsql/ /var/lib/grafana/dashboards/dsql/
COPY bench/ /var/lib/grafana/dashboards/bench/
COPY workers/ /var/lib/grafana/dashboards/workers/

# Copy entrypoint script for environment variable substitution
COPY entrypoint.sh /entrypoint.sh

# Set ownership and permissions
USER root
RUN chown -R grafana:root /etc/grafana/provisioning /var/lib/grafana/dashboards && \
    chmod +x /entrypoint.sh
USER grafana

ENTRYPOINT ["/entrypoint.sh"]
