# Custom Grafana image with pre-configured datasources and dashboards
# for Temporal DSQL ECS deployment
#
# Build: docker build -t temporal-grafana:latest grafana/
# The datasources.yaml uses environment variable substitution at runtime

FROM grafana/grafana-oss:latest

# Copy provisioning configuration
COPY provisioning/ /etc/grafana/provisioning/

# Copy dashboards
COPY server/ /var/lib/grafana/dashboards/server/
COPY dsql/ /var/lib/grafana/dashboards/dsql/

# Set ownership
USER root
RUN chown -R grafana:root /etc/grafana/provisioning /var/lib/grafana/dashboards
USER grafana
