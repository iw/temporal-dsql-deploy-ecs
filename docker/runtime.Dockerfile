# Runtime image for Temporal DSQL on ECS
# Extends the base server image with config rendering support
#
# This image:
# - Uses the base temporal-dsql server image
# - Adds gettext for envsubst (config template rendering)
# - Adds curl for ECS metadata endpoint queries
# - Includes persistence config templates for DSQL + OpenSearch
# - Includes environment-specific dynamic configs (dev, bench, prod)
# - Provides render-and-start.sh entrypoint

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

USER root

# Install gettext for envsubst and curl for ECS metadata queries
RUN apk add --no-cache gettext curl

# Create config directories with proper ownership
# The base image has /etc/temporal owned by temporal user
# We need to create subdirectories and ensure they're writable
RUN mkdir -p /etc/temporal/config/dynamicconfig && \
    chown -R temporal:temporal /etc/temporal

# Copy config templates and scripts
COPY --chown=temporal:temporal config/persistence-dsql.template.yaml /etc/temporal/config/persistence-dsql-opensearch.template.yaml

# Copy environment-specific dynamic configs
COPY --chown=temporal:temporal config/dynamicconfig-dev.yaml /etc/temporal/config/dynamicconfig/dev.yaml
COPY --chown=temporal:temporal config/dynamicconfig-bench.yaml /etc/temporal/config/dynamicconfig/bench.yaml
COPY --chown=temporal:temporal config/dynamicconfig-prod.yaml /etc/temporal/config/dynamicconfig/prod.yaml

# Create symlink for default (prod) - overridden at startup by DEPLOY_ENVIRONMENT
RUN ln -sf /etc/temporal/config/dynamicconfig/prod.yaml /etc/temporal/config/dynamicconfig/dynamicconfig.yaml

COPY --chown=temporal:temporal scripts/render-and-start.sh /usr/local/bin/render-and-start.sh

RUN chmod +x /usr/local/bin/render-and-start.sh

USER temporal

# Override entrypoint to render config before starting
ENTRYPOINT ["/usr/local/bin/render-and-start.sh"]
CMD []
