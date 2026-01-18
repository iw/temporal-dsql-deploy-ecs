# AGENTS.md

This file provides context for AI coding assistants working on this project.

## Project Overview

Terraform infrastructure for deploying Temporal workflow engine on AWS ECS on EC2 with:

- **Multi-service architecture**: 5 separate Temporal services (History, Matching, Frontend, Worker, UI) + Grafana + ADOT Collector
- **ECS Service Connect**: Modern service mesh with Envoy sidecar for inter-service communication
- **ECS on EC2 with Graviton**: 6x m7g.xlarge instances with ECS managed placement for stable IPs and cluster membership
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
│   ├── benchmark.tf              # Benchmark task definition and security group
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
| `ec2-cluster.tf` | Launch template, single ASG with 6 EC2 instances, capacity provider |
| `benchmark.tf` | Benchmark task definition, IAM role, security group |
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

**Worker Configuration** (optimized for high throughput):
- `MaxConcurrentActivityExecutionSize`: 200
- `MaxConcurrentWorkflowTaskExecutionSize`: 200
- `MaxConcurrentLocalActivityExecutionSize`: 200
- `MaxConcurrentWorkflowTaskPollers`: 10
- `MaxConcurrentActivityTaskPollers`: 10

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

All ECS tasks run on Graviton-based m7g.xlarge EC2 instances:
- 20-40% cost savings over x86 instances
- Stable IPs for Temporal's ringpop cluster membership
- 6 instances provide capacity for production workloads
- Uses ECS-optimized Amazon Linux 2023 AMI for ARM64

### 5. ECS Managed Placement

Services are distributed across 6 EC2 instances using ECS spread placement:
- Spread across availability zones for high availability
- Spread across instances for even distribution
- No workload-specific placement constraints
- ECS automatically places tasks based on available resources

Production service counts:
- **History**: 4 replicas (2 vCPU, 8 GiB each, 4096 shards)
- **Matching**: 3 replicas (1 vCPU, 4 GiB each)
- **Frontend**: 2 replicas (1 vCPU, 4 GiB each)
- **Worker**: 2 replicas (1 vCPU, 4 GiB each)
- **UI**: 1 replica (0.25 vCPU, 512 MiB)
- **Grafana**: 1 replica (0.25 vCPU, 512 MiB)
- **ADOT**: 1 replica (0.5 vCPU, 1 GiB)

### 6. IAM Authentication for DSQL

Aurora DSQL uses IAM authentication exclusively:
- No database passwords stored in Secrets Manager
- Task role has `dsql:DbConnect` and `dsql:DbConnectAdmin` permissions
- Credentials generated automatically via IAM

### 6a. DSQL Connection Rate Limiting

DSQL has cluster-wide connection limits that must be respected across all service instances:
- **100 connections/sec** cluster-wide rate limit
- **1,000 connections** burst capacity
- **10,000 max connections** per cluster

The temporal-dsql plugin implements per-instance rate limiting via environment variables:
- `DSQL_CONNECTION_RATE_LIMIT`: Connections per second (default: 10)
- `DSQL_CONNECTION_BURST_LIMIT`: Burst capacity (default: 100)
- `DSQL_STAGGERED_STARTUP`: Enable random startup delay (default: true)
- `DSQL_STAGGERED_STARTUP_MAX_DELAY`: Max startup delay (default: 5s)

Service-specific limits are configured in each task definition to partition the cluster budget:

| Service | Replicas | Rate/Instance | Burst/Instance | Total Rate |
|---------|----------|---------------|----------------|------------|
| History | 4 | 15/sec | 150 | 60/sec |
| Matching | 3 | 8/sec | 80 | 24/sec |
| Frontend | 2 | 5/sec | 50 | 10/sec |
| Worker | 2 | 3/sec | 30 | 6/sec |
| **Total** | **11** | - | - | **~100/sec** |

This ensures the cluster-wide 100/sec limit is respected even during rolling deployments or scaling events. Staggered startup adds a random 0-5s delay on first connection to prevent thundering herd during service restarts.

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

## References

- [ECS Service Connect](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html)
- [ECS Exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)
- [Aurora DSQL](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/what-is.html)
- [Temporal Architecture](https://docs.temporal.io/clusters)
