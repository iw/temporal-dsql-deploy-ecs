# AGENTS.md

This file provides context for AI coding assistants working on this project.

## Project Overview

Terraform infrastructure for deploying Temporal workflow engine on AWS ECS on EC2 with:

- **Multi-service architecture**: 5 separate Temporal services (History, Matching, Frontend, Worker, UI) + Grafana + ADOT Collector
- **ECS Service Connect**: Modern service mesh with Envoy sidecar for inter-service communication
- **ECS on EC2 with Graviton**: 10x m7g.2xlarge instances with ECS managed placement for stable IPs and cluster membership
- **Private-only networking**: No public subnets, VPC endpoints for AWS services
- **Aurora DSQL**: Serverless PostgreSQL-compatible persistence with IAM authentication
- **OpenSearch Provisioned**: 3-node m6g.large.search cluster for visibility
- **Amazon Managed Prometheus**: Metrics collection with ADOT Collector for scraping
- **Benchmark Runner**: Go application for performance testing with configurable workflow patterns

## Project Structure

```
temporal-dsql-deploy-ecs/
├── terraform/                    # Terraform infrastructure code
│   ├── templates/                # Template files for configuration
│   │   └── adot-config.yaml      # ADOT collector configuration template
│   ├── main.tf                   # Provider configuration
│   ├── vpc.tf                    # VPC, subnets, NAT Gateway, route tables
│   ├── vpc-endpoints.tf          # VPC endpoints for AWS services
│   ├── ecs-cluster.tf            # ECS cluster with Service Connect namespace
│   ├── ec2-cluster.tf            # EC2 instances, ASGs, capacity providers, placement
│   ├── benchmark.tf              # Benchmark generator task definition and security group
│   ├── benchmark-worker.tf       # Benchmark worker service (processes workflows)
│   ├── benchmark-ec2.tf          # Benchmark EC2 ASG and capacity provider (scale-from-zero)
│   ├── temporal-history.tf       # History service task definition and ECS service
│   ├── temporal-matching.tf      # Matching service task definition and ECS service
│   ├── temporal-frontend.tf      # Frontend service task definition and ECS service
│   ├── temporal-worker.tf        # Worker service task definition and ECS service
│   ├── temporal-ui.tf            # UI service task definition and ECS service
│   ├── grafana.tf                # Grafana task definition and ECS service
│   ├── adot.tf                   # ADOT Collector for metrics scraping
│   ├── opensearch.tf             # OpenSearch Provisioned domain and setup task
│   ├── prometheus.tf             # Amazon Managed Prometheus workspace
│   ├── iam.tf                    # IAM roles and policies
│   ├── security-groups.tf        # Security group definitions
│   ├── secrets.tf                # Secrets Manager data source
│   ├── cloudwatch.tf             # CloudWatch Log Groups
│   ├── variables.tf              # Input variable definitions with validation
│   ├── outputs.tf                # Output definitions including ECS Exec commands
│   ├── terraform.tfvars.example  # Example configuration file
│   └── .gitignore                # Terraform-specific gitignore
├── benchmark/                    # Benchmark runner Go application
│   ├── cmd/benchmark/            # Main entry point
│   ├── internal/                 # Internal packages
│   │   ├── config/               # Configuration parsing
│   │   ├── generator/            # Workflow generator with rate limiting
│   │   ├── metrics/              # Prometheus metrics collection
│   │   ├── results/              # Results reporting and JSON output
│   │   ├── runner/               # Benchmark orchestration
│   │   └── cleanup/              # Workflow cleanup
│   ├── workflows/                # Benchmark workflow implementations
│   ├── Dockerfile                # Multi-stage ARM64 build
│   ├── go.mod                    # Go module definition
│   └── go.sum                    # Go dependencies
├── scripts/                      # Utility scripts
│   ├── build-and-push-ecr.sh     # Build ARM64 image and push to ECR
│   ├── build-benchmark.sh        # Build and push benchmark image to ECR
│   ├── run-benchmark.sh          # Run benchmark task with configurable parameters
│   ├── get-benchmark-results.sh  # Retrieve benchmark results from CloudWatch logs
│   ├── cluster-management.sh     # Cluster management (scale, recover, status)
│   ├── scale-services.sh         # Scale ECS services up/down
│   ├── setup-grafana-secret.sh   # Create Grafana admin secret in Secrets Manager
│   ├── setup-schema.sh           # Setup DSQL schema using temporal-dsql-tool
│   └── setup-opensearch.sh       # Setup OpenSearch visibility index
├── dynamicconfig/                # Temporal dynamic configuration
│   └── development-dsql.yaml     # DSQL-specific dynamic config
├── grafana/                      # Custom Grafana image with dashboards
│   ├── Dockerfile                # Grafana image with provisioned dashboards
│   ├── entrypoint.sh             # Environment variable substitution for datasources
│   ├── provisioning/             # Grafana provisioning configuration
│   │   ├── dashboards/           # Dashboard provider config
│   │   └── datasources/          # Datasource definitions (AMP, CloudWatch)
│   ├── server/                   # Temporal Server dashboard
│   │   └── server.json           # Service health, workflow outcomes, persistence
│   └── dsql/                     # DSQL Persistence dashboard
│       └── persistence.json      # Connection pool, OCC conflicts, CloudWatch metrics
├── .kiro/                        # Kiro spec files
│   └── specs/
│       ├── temporal-ecs-ec2/     # ECS deployment spec
│       │   ├── requirements.md   # EARS-format requirements
│       │   ├── design.md         # Technical design document
│       │   └── tasks.md          # Implementation task list
│       ├── temporal-benchmark/   # Benchmark spec
│       │   ├── requirements.md   # Benchmark requirements
│       │   ├── design.md         # Benchmark design
│       │   └── tasks.md          # Benchmark implementation tasks
│       ├── ringpop-behaviour/    # Ringpop membership investigation
│       │   ├── requirements.md   # Problem statement and requirements
│       │   ├── design.md         # Investigation findings
│       │   └── tasks.md          # Implementation status
│       └── dsql-auth-renewal/    # DSQL IAM auth investigation
│           ├── requirements.md   # Auth renewal requirements
│           ├── design.md         # Token caching design
│           └── tasks.md          # Implementation status
├── README.md                     # Project documentation
└── AGENTS.md                     # This file
```

## Key Files and Their Purposes

### Terraform Files

| File | Purpose |
|------|---------|
| `main.tf` | AWS provider configuration with region variable |
| `vpc.tf` | VPC with private subnets, NAT Gateway for outbound access |
| `vpc-endpoints.tf` | Interface endpoints (ECR, SSM, Logs, etc.) and S3 gateway endpoint |
| `ecs-cluster.tf` | ECS cluster with Container Insights, Service Connect namespace |
| `ec2-cluster.tf` | Launch template, single ASG with EC2 instances, capacity provider |
| `dynamodb.tf` | DynamoDB table for distributed DSQL connection rate limiting |
| `benchmark.tf` | Benchmark generator task definition, IAM role, security group |
| `benchmark-worker.tf` | Benchmark worker ECS service (processes benchmark workflows) |
| `benchmark-ec2.tf` | Benchmark ASG (scale-from-zero) and capacity provider |
| `temporal-*.tf` | Individual Temporal service task definitions and ECS services |
| `grafana.tf` | Grafana deployment with Secrets Manager integration |
| `adot.tf` | ADOT Collector for metrics scraping and remote write to AMP |
| `opensearch.tf` | OpenSearch domain and one-time schema setup task |
| `prometheus.tf` | Amazon Managed Prometheus workspace |
| `iam.tf` | Task execution role, task roles with least-privilege policies |
| `security-groups.tf` | Per-service security groups with inter-service rules |
| `secrets.tf` | Data source for externally-created Grafana secret |
| `cloudwatch.tf` | Log groups for each service and ECS Exec |
| `variables.tf` | All input variables with descriptions and validation |
| `outputs.tf` | Resource identifiers, endpoints, ECS Exec commands |

### Scripts

| Script | Purpose |
|--------|---------|
| `build-and-push-ecr.sh` | Build ARM64 Temporal binaries, create ECR repos if needed, build Docker images, push to ECR (self-contained, no Terraform dependency) |
| `build-grafana.sh` | Build and push custom Grafana image with dashboards to ECR (accepts region arg, defaults to eu-west-1) |
| `build-benchmark.sh` | Build and push benchmark runner image to ECR |
| `run-benchmark.sh` | Run benchmark task with configurable parameters (workflow type, rate, duration, namespace) |
| `get-benchmark-results.sh` | Retrieve benchmark results from CloudWatch logs |
| `cluster-management.sh` | Cluster management utilities: scale-down, scale-up, clean-membership, force-deploy, status, recover (for crash loop recovery) |
| `scale-services.sh` | Scale ECS services up/down (use after schema setup to start services) |
| `setup-grafana-secret.sh` | Generate Grafana admin password and create secret in Secrets Manager (one-time, idempotent) |
| `setup-schema.sh` | Initialize DSQL schema using temporal-dsql-tool (accepts --endpoint or --from-terraform) |
| `setup-opensearch.sh` | Create OpenSearch visibility index |
| `scale-benchmark-workers.sh` | Scale benchmark workers up/down (separate from main services) |

### Benchmark Runner

The benchmark runner (`benchmark/`) is a Go application for performance testing:

| Component | Purpose |
|-----------|---------|
| `cmd/benchmark/main.go` | Entry point, configuration loading, graceful shutdown |
| `internal/config/` | Environment variable parsing and validation |
| `internal/generator/` | Rate-limited workflow submission with ramp-up |
| `internal/metrics/` | Prometheus metrics collection and SDK integration |
| `internal/runner/` | Benchmark orchestration, namespace management |
| `internal/results/` | JSON output and threshold comparison |
| `internal/cleanup/` | Workflow termination after benchmark |
| `workflows/` | Benchmark workflow implementations (simple, multi-activity, timer, child) |

**Architecture:**
The benchmark system uses a separated generator/worker architecture:
- **Generator Task** (`benchmark.tf`): One-shot ECS task that submits workflows at the target rate
- **Worker Service** (`benchmark-worker.tf`): Long-running ECS service that processes benchmark workflows

This separation allows independent scaling of workers to handle high WPS loads without resource contention.

**Generator Task Resources:**
- **CPU**: 4096 (4 vCPU) - For workflow submission
- **Memory**: 8192 MB (8 GB)
- Runs as a one-shot task, exits after benchmark duration + completion timeout

**Worker Service Resources:**
- **CPU**: 4096 (4 vCPU) per worker
- **Memory**: 4096 MB (4 GB) per worker
- **Replicas**: Configurable via `benchmark_worker_count` (default: 0, scale up for benchmarks)
- **Max workers**: 51 (with 384 vCPU quota, 13 benchmark instances)
- Runs with `BENCHMARK_WORKER_ONLY=true` to only process workflows

**Resource Planning (384 vCPU quota, 380 usable):**

| Cluster | Instances | vCPU | Purpose |
|---------|-----------|------|---------|
| Main | 10 × m8g.4xlarge | 160 | Temporal services |
| Benchmark | 13 × m8g.4xlarge | 208 | 1 generator (4 vCPU) + 51 workers (204 vCPU) |
| **Total** | **23** | **368** | 12 vCPU headroom |

**Worker Scaling Recommendations:**

| Target WPS | Workers | Pollers | Notes |
|------------|---------|---------|-------|
| 100 | 30 | 960 | Conservative |
| 200 | 40 | 1,280 | Moderate |
| 400 | 51 | 1,632 | Max with current quota |

**Worker Configuration** (optimized for high throughput):
- `MaxConcurrentActivityExecutionSize`: 200
- `MaxConcurrentWorkflowTaskExecutionSize`: 200
- `MaxConcurrentLocalActivityExecutionSize`: 200
- `MaxConcurrentWorkflowTaskPollers`: 32 (increased from 16 to address workflow task bottleneck)
- `MaxConcurrentActivityTaskPollers`: 32 (increased from 16)
- `MaxConcurrentEagerActivityExecutionSize`: 100 (eager activities for lower latency)
- `DisableEagerActivities`: false (enabled for faster activity dispatch)
- `StickyScheduleToStartTimeout`: 5s (workflow state caching)

**Workflow Task Bottleneck (6k st/s benchmark finding):**
- Server adds ~350 workflow tasks/sec but workers only processed ~70/sec with 8 workers × 16 pollers
- Increased pollers to 32 per worker to improve workflow task throughput
- For 6k st/s turbo config: use 16 workers × 32 pollers = 512 total pollers

**Server-Side Requirements for Worker Optimizations:**
- `system.enableActivityEagerExecution: true` - Required for eager activities (default: false)
- `system.enableEagerWorkflowStart: true` - Enabled by default, allows inline first workflow task
- `system.enableStickyQuery: true` - Enabled by default, allows sticky execution caching

**Completion Timeout** (for high WPS benchmarks):
- At high WPS (e.g., 100 WPS over 5 minutes = 30,000 workflows), many workflows are still in-flight when the test duration ends
- The benchmark runner waits for workflows to complete before reporting results
- `BENCHMARK_COMPLETION_TIMEOUT`: Configurable timeout for waiting (default: auto-calculated)
- Auto-calculation: `max(60s, duration)`, capped at 10 minutes
- For 100 WPS × 5 min = 30,000 workflows: auto-calculates to 5 minutes drain time
- Use `--completion-timeout` flag in `run-benchmark.sh` to override

## Design Decisions

### 1. Multi-Service Architecture

Each Temporal component runs as a separate ECS service rather than a monolithic deployment:
- Enables independent scaling of each component
- Allows different resource allocations per service
- Facilitates rolling updates without full restart
- Matches Temporal's recommended production topology

### 2. ECS Service Connect

Uses Service Connect instead of Cloud Map DNS-based discovery:
- Faster failover (Envoy sidecar vs DNS TTL)
- Built-in load balancing and health checking
- Automatic Envoy proxy injection
- Service mesh capabilities without additional infrastructure

### 3. Private-Only Networking

No public subnets or internet-facing resources:
- All services in private subnets with `assign_public_ip = false`
- VPC endpoints for AWS service access (ECR, SSM, Logs, etc.)
- Single NAT Gateway for outbound internet (DSQL, external APIs)
- Access via SSM Session Manager port forwarding only

### 4. Graviton (ARM64) on EC2

All ECS tasks run on Graviton-based m7g.2xlarge EC2 instances:
- 20-40% cost savings over x86 instances
- Stable IPs for Temporal's ringpop cluster membership
- Default 10 instances for 150 WPS workloads (configurable)
- Uses ECS-optimized Amazon Linux 2023 AMI for ARM64

### 5. ECS Managed Placement

Services are distributed across EC2 instances using ECS spread placement:
- Spread across availability zones for high availability
- Spread across instances for even distribution
- No workload-specific placement constraints
- ECS automatically places tasks based on available resources

**150 WPS Configuration** (10x m7g.2xlarge = 80 vCPUs, 320 GiB RAM):
- **History**: 8 replicas (4 vCPU, 8 GiB each, 4096 shards)
- **Matching**: 6 replicas (1 vCPU, 2 GiB each)
- **Frontend**: 4 replicas (2 vCPU, 4 GiB each)
- **Worker**: 2 replicas (0.5 vCPU, 1 GiB each)
- **UI**: 1 replica (0.25 vCPU, 512 MiB)
- **Grafana**: 1 replica (0.25 vCPU, 512 MiB)
- **ADOT**: 1 replica (0.5 vCPU, 1 GiB)

**100 WPS Configuration** (6x m7g.2xlarge = 48 vCPUs, 192 GiB RAM):
- **History**: 6 replicas (2 vCPU, 8 GiB each)
- **Matching**: 4 replicas (1 vCPU, 4 GiB each)
- **Frontend**: 3 replicas (1 vCPU, 4 GiB each)
- **Worker**: 2 replicas (1 vCPU, 4 GiB each)

### 6. IAM Authentication for DSQL

Aurora DSQL uses IAM authentication exclusively:
- No database passwords stored in Secrets Manager
- Task role has `dsql:DbConnect` and `dsql:DbConnectAdmin` permissions
- Credentials generated automatically via IAM

### 6a. DSQL Connection Pool Configuration

**FUNDAMENTAL REQUIREMENT: The connection pool MUST always be at maximum size.**

**Why this matters - DSQL Connection Rate Limit:**
DSQL has a **cluster-wide connection rate limit of 100 connections/second**. If the pool decays and needs to grow under load:
- Multiple services compete for the 100/sec budget
- Requests queue waiting for connections
- Rate limit errors (`SQLSTATE 53400`) cause failures
- Cascade failures as services retry and consume more budget

By keeping the pool at max size at all times, we eliminate connection creation under load entirely.

**Requirements:**
1. **Pool must be pre-warmed to max size at startup**
2. **Pool must remain at max size indefinitely** (no idle timeout decay)
3. **Connections only replaced when they hit MaxConnLifetime** (one-by-one, rate-limited)

**Authoritative Defaults** (defined in `temporal-dsql/common/persistence/sql/sqlplugin/dsql/session/session.go`):

| Setting | Value | Rationale |
|---------|-------|-----------|
| `MaxConns` | 50 | Maximum open connections per pool |
| `MaxIdleConns` | 50 | **MUST equal MaxConns** - prevents idle connection closure |
| `MaxConnLifetime` | 55 minutes | Under DSQL's 60 minute limit |
| `MaxConnIdleTime` | **0 (disabled)** | **CRITICAL: Must be 0 to prevent pool decay** |

**Why MaxConnIdleTime must be 0:**
Go's `database/sql` closes connections that have been idle longer than `MaxConnIdleTime`. Even with `MaxIdleConns = MaxConns`, idle connections are still closed after this timeout. Setting it to 0 disables this behavior entirely, ensuring the pool stays at max size.

**Pool Pre-Warming** (defined in `temporal-dsql/common/persistence/sql/sqlplugin/dsql/pool_warmup.go`):

| Setting | Value | Rationale |
|---------|-------|-----------|
| `TargetConnections` | 50 | Matches MaxConns - pool starts fully warmed |
| `MaxRetries` | 5 | Retry failed connections |
| `RetryBackoff` | 200ms | Initial backoff with jitter |
| `MaxBackoff` | 5 seconds | Cap on exponential backoff |
| `ConnectionTimeout` | 10 seconds | Per-connection timeout |

Warmup creates connections **sequentially** (not in batches) for reliability:
- Each connection has its own 10-second timeout
- Failed connections retry with exponential backoff + jitter (50-150%)
- No overall timeout - completes all 50 connections reliably
- Prevents thundering herd during cluster-wide restarts

**Environment Variable Overrides** (set in Terraform task definitions):

```hcl
{ name = "TEMPORAL_SQL_MAX_CONNS", value = "50" },
{ name = "TEMPORAL_SQL_MAX_IDLE_CONNS", value = "50" },
{ name = "TEMPORAL_SQL_CONNECTION_TIMEOUT", value = "30s" },
{ name = "TEMPORAL_SQL_MAX_CONN_LIFETIME", value = "55m" },
```

**Connection Pool Lifecycle:**
1. **Startup**: Pool warmup creates 50 connections synchronously (rate-limited)
2. **Steady state**: All 50 connections remain open (no idle decay)
3. **After 55 minutes**: Connections are replaced one-by-one as they hit MaxConnLifetime
4. **Under load**: No new connections needed - pool is always ready

**Pool Warmup Logging:**
On startup, look for these log messages:
- `"Starting DSQL pool warmup"` with `target_connections=50`
- `"DSQL pool warmup complete"` with `connections_created=50`, `connections_failed=0`

If warmup logs are missing, the pool will grow on-demand causing rate limit pressure and latency spikes.

### 6b. DSQL Connection Rate Limiting

DSQL has cluster-wide connection limits that must be respected across all service instances:
- **100 connections/sec** cluster-wide rate limit
- **1,000 connections** burst capacity
- **10,000 max connections** per cluster

The temporal-dsql plugin implements per-instance rate limiting via environment variables:
- `DSQL_CONNECTION_RATE_LIMIT`: Connections per second (default: 10)
- `DSQL_CONNECTION_BURST_LIMIT`: Burst capacity (default: 100)
- `DSQL_STAGGERED_STARTUP`: Enable random startup delay (default: true)
- `DSQL_STAGGERED_STARTUP_MAX_DELAY`: Max startup delay (default: 5s)

**Rate Limiting Architecture:**
The rate limiter is integrated into the `tokenRefreshingDriver.Open()` method, ensuring that ALL connection attempts are rate-limited, including:
- Initial pool creation
- Pool growth under load (when `database/sql` internally creates new connections)
- Connection replacement after `MaxConnLifetime` expiry
- Reconnection after connection failures

This is critical because `database/sql` manages the connection pool internally and calls `driver.Open()` directly when growing the pool, bypassing any application-level rate limiting.

Service-specific limits are configured in each task definition to partition the cluster budget.

**100 WPS Configuration** (optimized for high throughput):

| Service | Replicas | Rate/Instance | Burst/Instance | Total Rate |
|---------|----------|---------------|----------------|------------|
| History | 6 | 8/sec | 40 | 48/sec |
| Matching | 4 | 6/sec | 30 | 24/sec |
| Frontend | 3 | 4/sec | 20 | 12/sec |
| Worker | 2 | 2/sec | 10 | 4/sec |
| **Total** | **15** | - | - | **~88/sec** |

This ensures the cluster-wide 100/sec limit is respected even during rolling deployments or scaling events. Staggered startup adds a random 0-5s delay on first connection to prevent thundering herd during service restarts.

### 6c. Distributed Rate Limiting (DynamoDB-backed)

For cluster-wide coordination of DSQL connection rate limiting across all service instances, a DynamoDB-backed distributed rate limiter is available:

- **DynamoDB Table**: `${project_name}-dsql-rate-limiter`
- **On-demand billing**: Pay-per-request, $0 when idle
- **TTL enabled**: Automatic cleanup of old rate limit entries (3 minutes)

**Environment Variables:**
- `DSQL_DISTRIBUTED_RATE_LIMITER_ENABLED`: Set to `true` to enable
- `DSQL_DISTRIBUTED_RATE_LIMITER_TABLE`: DynamoDB table name
- `DSQL_DISTRIBUTED_RATE_LIMITER_LIMIT`: Cluster-wide limit per second (default: 100)

**Table Schema:**
- Partition key: `pk` (String) - Format: `dsqlconnect#<endpoint>#<unix_second>`
- TTL attribute: `ttl_epoch` (Number) - Auto-cleanup after 3 minutes

This provides true cluster-wide coordination, ensuring the DSQL connection rate limit is respected regardless of how many service instances are running or how they're distributed.

### 7. External Secret Creation

Grafana admin secret is created externally before Terraform:
- Avoids storing sensitive values in Terraform state
- Uses data source to reference existing secret
- Secret contains JSON with `admin_user` and `admin_password` fields

### 8. ECS Exec for Access

All containers support ECS Exec for debugging:
- `enable_execute_command = true` on services
- `linuxParameters.initProcessEnabled = true` in task definitions
- SSM Messages VPC endpoint for connectivity
- CloudWatch Log Group for audit trail

### 9. Zero-Replica Initial Deployment

Services deploy with `desired_count = 0` by default:
- Prevents crash-loops when DSQL schema doesn't exist yet
- Allows infrastructure to be fully provisioned before services start
- Schema setup runs against DSQL before services attempt to connect
- Use `./scripts/scale-services.sh up` to start services after schema setup
- Cleaner deployment workflow without failed task attempts

### 10. ADOT Collector for Metrics

AWS Distro for OpenTelemetry (ADOT) runs as a dedicated ECS service:
- Scrapes Prometheus metrics from all Temporal services on port 9090
- Uses Service Connect DNS names for service discovery (temporal-frontend, temporal-history, etc.)
- Remote writes to Amazon Managed Prometheus using SigV4 authentication
- Configuration stored in SSM Parameter Store for easy updates
- Client-only Service Connect mode (consumes services, doesn't expose endpoints)

### 11. Benchmark Infrastructure

Dedicated benchmark infrastructure with scale-from-zero capability:
- Separate ASG with `workload=benchmark` attribute
- ECS capacity provider provisions instances on demand
- Benchmark task runs as standalone ECS task (not a service)
- Metrics scraped by ADOT and sent to Amazon Managed Prometheus
- Workflows created in dedicated `benchmark` namespace (configurable)

## Common Tasks

### Adding a New Environment Variable

1. Add variable to `variables.tf` with description and default
2. Add to container `environment` block in relevant `temporal-*.tf`
3. Update `terraform.tfvars.example` with example value

### Modifying Security Group Rules

1. Edit `security-groups.tf`
2. Add ingress/egress rules referencing specific security groups
3. Never use `0.0.0.0/0` for ingress

### Scaling a Service

1. Update `temporal_*_count` variable in `terraform.tfvars`
2. Run `terraform apply`
3. Or use AWS CLI: `aws ecs update-service --desired-count N`

### Running a Benchmark

1. Build and push benchmark image: `./scripts/build-benchmark.sh`
2. Run benchmark: `./scripts/run-benchmark.sh --from-terraform --namespace benchmark --rate 50 --duration 2m --wait`
3. Get results: `./scripts/get-benchmark-results.sh --from-terraform`

### Updating Container Image

1. Build new image: `./scripts/build-and-push-ecr.sh ../temporal-dsql`
2. Force new deployment: `./scripts/cluster-management.sh force-deploy`
3. Or update `temporal_image` in `terraform.tfvars` if using version tag and run `terraform apply`

## Testing

### Terraform Validation

```bash
cd terraform
terraform init
terraform validate
terraform fmt -check
```

### Plan Review

```bash
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json
# Review plan.json for correctness properties
```

### Integration Testing

After deployment:
1. Verify all services are running: `aws ecs list-services --cluster <cluster>`
2. Check service health: `aws ecs describe-services --services <service>`
3. Test ECS Exec: `terraform output -raw temporal_frontend_ecs_exec_command`
4. Test port forwarding: `terraform output -raw temporal_ui_port_forward_command`

## Troubleshooting

### Service Not Starting

1. Check CloudWatch Logs: `/ecs/<project>/temporal-<service>`
2. Verify IAM permissions in task role
3. Check security group allows required traffic
4. Verify VPC endpoints are healthy

### ECS Exec Not Working

1. Verify Session Manager plugin installed
2. Check IAM permissions for `ecs:ExecuteCommand` and `ssm:StartSession`
3. Verify SSM Messages VPC endpoint exists
4. Check task has `initProcessEnabled = true`

### Service Connect Issues

1. Verify namespace exists and is associated with cluster
2. Check service has correct `service_connect_configuration`
3. Verify port names match between task definition and service config
4. Check Envoy sidecar logs in CloudWatch

**Note:** The Service Connect sidecar (`ecs-service-connect-agent`) is injected at runtime by ECS, not defined in the task definition. You cannot use `dependsOn` to wait for it. Instead, applications must implement connection retry logic to handle the brief window where DNS resolution may fail during startup. The benchmark worker already has this retry logic in `benchmark/cmd/benchmark/main.go`.

### Crash Loop Recovery (Ringpop Issues)

When services are stuck in crash loops due to stale cluster membership:

1. Scale all services to 0: `./scripts/cluster-management.sh scale-down`
2. Clean cluster_membership table: `./scripts/cluster-management.sh clean-membership`
3. Scale up services in order: `./scripts/cluster-management.sh scale-up`

Or run all steps: `./scripts/cluster-management.sh recover`

### Inter-Service Communication Issues (Connection Reset)

If you see "connection reset by peer" errors between services, the issue is likely related to ringpop cluster membership. Temporal services use ringpop for cluster membership, which requires:

1. **Broadcast Address**: Each service must advertise its correct IP address to other services
2. **Bind Address**: Services must listen on all interfaces (0.0.0.0)

The runtime image (`temporal-dsql-runtime`) automatically detects the task IP from the ECS metadata endpoint and configures:
- `TEMPORAL_BROADCAST_ADDRESS`: The task's private IP (from ECS metadata)
- `BIND_ON_IP`: Set to 0.0.0.0 to listen on all interfaces

If services can't discover each other:
1. Check CloudWatch logs for "Detected ECS task IP from metadata" message
2. Verify the `cluster_membership` table has correct IPs
3. Ensure security groups allow traffic on membership ports (6933, 6934, 6935, 6939)

### After Image Update

After pushing new images to ECR, force new deployments:

```bash
./scripts/cluster-management.sh force-deploy
```

## Benchmark Results (January 2026)

### 150 WPS Benchmark

Configuration:
- **History**: 8 replicas (4 vCPU, 8 GiB each)
- **Matching**: 6 replicas (1 vCPU, 2 GiB each)
- **Frontend**: 4 replicas (2 vCPU, 4 GiB each)
- **Worker**: 2 replicas (0.5 vCPU, 1 GiB each)
- **Benchmark Workers**: 6 replicas (2 vCPU, 4 GiB each)
- **Infrastructure**: 10x m7g.2xlarge (main) + 4x m7g.2xlarge (benchmark)

Results:

| Metric | Value |
|--------|-------|
| Target Rate | 150 WPS |
| Actual Rate | 136.74 WPS |
| Workflows Started | 41,052 |
| Workflows Completed | 41,052 (100%) |
| P50 Latency | 197 ms |
| P95 Latency | 220 ms |
| P99 Latency | 259 ms |
| Max Latency | 594 ms |

### DSQL Metrics During Benchmark

| Metric | Value | Notes |
|--------|-------|-------|
| Database Connections | ~1,000 | Stable throughout test |
| TotalTx | 272,000/min | Peak transaction rate |
| ReadOnlyTx | 193,000/min | 71% of total |
| WriteTx | ~79,000/min | 29% of total |

### Key Findings

1. **100% Workflow Completion**: All 41,052 workflows completed successfully with zero failures.

2. **Sub-300ms P99 Latency**: Excellent tail latency under sustained 137 WPS load.

3. **Stable Connection Pool**: ~1,000 connections pre-warmed and maintained throughout test.

4. **No OCC Retry Storms**: GetWorkflowExecution optimization eliminated unnecessary FOR UPDATE locks.

5. **Clean Tail Latency**: Max latency under 600ms indicates no cascade failures.

## References

- [ECS Service Connect](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html)
- [ECS Exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)
- [Aurora DSQL](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/what-is.html)
- [Temporal Architecture](https://docs.temporal.io/clusters)
