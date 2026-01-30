# Docker Configuration Files

Configuration files baked into the Temporal DSQL runtime Docker image.

## Files

| File | Description |
|------|-------------|
| `persistence-dsql.template.yaml` | Persistence config template (DSQL + OpenSearch) |
| `dynamicconfig-dev.yaml` | Dynamic config for dev environment (WPS 50) |
| `dynamicconfig-bench.yaml` | Dynamic config for bench environment (WPS 200-400) |
| `dynamicconfig-prod.yaml` | Dynamic config for prod environment (WPS 100) |

## Persistence Template

The `persistence-dsql.template.yaml` is rendered at container startup using environment variables. It configures:
- DSQL as the persistence store (with IAM authentication)
- OpenSearch as the visibility store (with SigV4 signing)
- Service-specific gRPC and membership ports
- Prometheus metrics endpoint

## Dynamic Configuration

Environment-specific Temporal dynamic configuration for Aurora DSQL deployments.

### Key Differences by Environment

#### Persistence QPS

| Setting | Dev | Bench | Prod |
|---------|-----|-------|------|
| `history.persistenceMaxQPS` | 3,000 | 15,000 | 9,000 |
| `matching.persistenceMaxQPS` | 3,000 | 15,000 | 9,000 |
| `frontend.persistenceMaxQPS` | 3,000 | 15,000 | 9,000 |

#### History Cache

| Setting | Dev | Bench | Prod |
|---------|-----|-------|------|
| `history.hostLevelCacheMaxSizeBytes` | 512 MB | 2 GB | 1 GB |

#### Matching Partitions

| Setting | Dev | Bench | Prod |
|---------|-----|-------|------|
| `matching.numTaskqueueWritePartitions` | 8 | 64 | 32 |
| `matching.numTaskqueueReadPartitions` | 8 | 64 | 32 |

#### Frontend Rate Limits

| Setting | Dev | Bench | Prod |
|---------|-----|-------|------|
| `frontend.rps` | 5,000 | 30,000 | 15,000 |
| `frontend.namespaceRPS` | 5,000 | 30,000 | 15,000 |

### Common Settings (All Environments)

```yaml
# DSQL mode for optimistic concurrency control
persistence.enableDSQLMode: true

# DSQL transaction size limit (4MB)
persistence.transactionSizeLimit: 4000000

# Eager activity execution (reduces round-trips)
system.enableActivityEagerExecution: true

# Nexus disabled for DSQL compatibility
system.enableNexus: false
```

## How It Works

At container startup, `render-and-start.sh`:

1. Creates a symlink based on `TEMPORAL_ENVIRONMENT`:
   ```
   /etc/temporal/config/dynamicconfig/dynamicconfig.yaml -> {dev,bench,prod}.yaml
   ```

2. Renders `persistence-dsql.template.yaml` using environment variables

3. Starts the Temporal service with the rendered config

## Updating Configuration

1. Edit the appropriate file in this directory
2. Rebuild the Docker image: `./scripts/build-and-push-ecr.sh`
3. Force a new deployment: `./scripts/cluster-management.sh force-deploy`
