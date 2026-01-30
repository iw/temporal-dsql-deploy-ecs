# Temporal on AWS ECS (EC2)

Terraform module for deploying Temporal workflow engine on AWS ECS with EC2 instances (Graviton) and Aurora DSQL persistence.

## Features

- **Multi-service architecture**: Separate ECS services for History, Matching, Frontend, Worker, and UI
- **ECS Service Connect**: Modern service mesh with Envoy sidecar for fast failover
- **ECS on EC2 with Graviton**: m8g.4xlarge ARM64 instances with ECS managed placement (configurable)
- **Aurora DSQL**: Serverless PostgreSQL-compatible persistence with IAM authentication
- **OpenSearch Provisioned**: 3-node m6g.large.search cluster for visibility
- **Amazon Managed Prometheus**: Metrics collection and storage
- **Grafana Alloy**: Prometheus metrics scraping and log collection to Loki
- **Loki on ECS**: Centralized log aggregation with S3 backend
- **Grafana on ECS**: Dashboards and visualization
- **Private-only networking**: No public endpoints, VPC endpoints for AWS services
- **Stable IPs**: EC2 instances provide stable IPs for Temporal's ringpop cluster membership
- **ECS Exec**: Interactive shell access to containers via SSM

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              VPC (Private Only)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    ECS Cluster with Service Connect                 │    │
│  │                                                                     │    │
│  │  Main Cluster: 10 × m8g.4xlarge (160 vCPU)                         │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │    │
│  │  │ History  │ │ Matching │ │ Frontend │ │  Worker  │ │ UI/Graf  │  │    │
│  │  │  ×16     │ │  ×16     │ │  ×9      │ │  ×3      │ │          │  │    │
│  │  │ 4vCPU ea │ │ 1vCPU ea │ │ 2vCPU ea │ │ 0.5vCPU  │ │          │  │    │
│  │  │ +Alloy   │ │ +Alloy   │ │ +Alloy   │ │          │ │          │  │    │
│  │  │ sidecar  │ │ sidecar  │ │ sidecar  │ │          │ │          │  │    │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘  │    │
│  │                                                                     │    │
│  │  Benchmark Cluster: 13 × m8g.4xlarge (208 vCPU, scale-from-zero)   │    │
│  │  ┌──────────────────────────────────┐ ┌──────────────────────────┐ │    │
│  │  │ Benchmark Workers ×51 (4vCPU ea) │ │ Generator ×1 (4vCPU)     │ │    │
│  │  │ +Alloy sidecar                   │ │ +Alloy sidecar           │ │    │
│  │  └──────────────────────────────────┘ └──────────────────────────┘ │    │
│  │                                                                     │    │
│  │  Service Connect (Envoy Mesh) for inter-service communication      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌─────────────────┐  ┌───────────────┐  ┌─────────────────┐               │
│  │   OpenSearch    │  │  VPC Endpts   │  │   NAT Gateway   │               │
│  │  3×m6g.large    │  │  (AWS Servcs) │  │  (Outbound)     │               │
│  └─────────────────┘  └───────────────┘  └─────────────────┘               │
└───────────────────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────┼───────────────┐
                    │           │               │
              ┌─────▼─────┐  ┌──▼───────────┐  ┌─────▼─────┐
              │   DSQL    │  │ Prometheus   │  │  Secrets  │
              │ (External)│  │   (AMP)      │  │  Manager  │
              └───────────┘  └──────────────┘  └───────────┘
```

### Production Configuration

**400 WPS Configuration** (23x m8g.4xlarge = 368 vCPUs):

Main Cluster (10 instances, 160 vCPU):

| Service | Replicas | CPU | Memory | Notes |
|---------|----------|-----|--------|-------|
| History | 16 | 4 vCPU | 8 GiB | 4096 shards, +Alloy sidecar |
| Matching | 16 | 1 vCPU | 2 GiB | Task queue management, +Alloy sidecar |
| Frontend | 9 | 2 vCPU | 4 GiB | gRPC API gateway, +Alloy sidecar |
| Worker | 3 | 0.5 vCPU | 1 GiB | System workflows |
| UI | 1 | 0.25 vCPU | 512 MiB | Web interface |
| Grafana | 1 | 0.25 vCPU | 512 MiB | Dashboards |

Benchmark Cluster (13 instances, 208 vCPU):

| Service | Replicas | CPU | Memory | Notes |
|---------|----------|-----|--------|-------|
| Benchmark Workers | 51 | 4 vCPU | 4 GiB | Workflow processing |
| Generator | 1 | 4 vCPU | 8 GiB | Workflow submission |

## Prerequisites

- AWS CLI v2 configured with appropriate permissions
- Terraform >= 1.14.0
- Docker with buildx support (for ARM64 builds)
- awscurl (for querying Amazon Managed Prometheus)
- Aurora DSQL cluster (created separately)
- AWS Session Manager plugin (for remote access)
- [temporal-dsql](https://github.com/iw/temporal) - Custom Temporal fork with DSQL persistence support

### Install Session Manager Plugin

See [AWS documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-macos-overview.html) for full details.

```bash
# macOS (Apple Silicon / arm64)
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin
rm -rf sessionmanager-bundle sessionmanager-bundle.zip

# Linux (Debian/Ubuntu - 64-bit)
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
rm session-manager-plugin.deb

# Verify installation
session-manager-plugin --version
```

## Quick Start

### 1. Create Grafana Admin Secret

Before deploying, create the Grafana admin credentials in Secrets Manager:

```bash
# Run the setup script (generates password and creates secret)
./scripts/setup-grafana-secret.sh

# Or specify a custom region/secret name:
./scripts/setup-grafana-secret.sh --region us-east-1 --name myproject/grafana/admin

# The script will display the generated password - save it for Grafana login!
```

The script is idempotent - if the secret already exists, it will show you how to retrieve the existing password.

### 2. Build and Push Custom Temporal Image

Build the ARM64 Temporal DSQL images and push to ECR. The script is self-contained and will create ECR repositories if they don't exist:

```bash
# Prerequisites:
# - Go 1.22+ installed
# - Docker with buildx support
# - AWS CLI configured with ECR permissions

# Build binaries and push images to ECR
# This builds: temporal-server, temporal-cassandra-tool, temporal-sql-tool,
#              temporal-elasticsearch-tool, temporal-dsql-tool, tdbg for ARM64
./scripts/build-and-push-ecr.sh /path/to/temporal-dsql

# Or specify a different region:
./scripts/build-and-push-ecr.sh /path/to/temporal-dsql us-east-1

# The script creates three images:
# - temporal-dsql:latest (base server image)
# - temporal-dsql-admin-tools:latest (tools image with schema files)
# - temporal-dsql-runtime:latest (runtime image for ECS services)
```

The build process:
1. Creates ECR repositories if they don't exist (with lifecycle policies)
2. Compiles Go binaries for `linux/arm64` using the Makefile targets
3. Builds Docker images using the official Dockerfiles from `temporal-dsql/docker/targets/`
4. Builds the runtime image that extends the base server with config rendering
5. Pushes to ECR with `latest` and timestamp-based version tags

The runtime image (`temporal-dsql-runtime`) is what you should use for `temporal_image` in your Terraform configuration. It includes:
- The base `temporal-server` binary
- Config template rendering via `envsubst`
- DSQL + OpenSearch persistence configuration templates
- An entrypoint script that renders config from environment variables

### 3. Build Custom Grafana Image

Build a custom Grafana image with pre-configured dashboards and datasources:

```bash
# Build and push custom Grafana image to ECR (defaults to eu-west-1)
./scripts/build-grafana.sh

# Or specify a different region
./scripts/build-grafana.sh us-east-1
```

This creates a Grafana image with:
- Amazon Managed Prometheus datasource (SigV4 auth)
- CloudWatch datasource for DSQL metrics
- Pre-loaded Temporal Server and DSQL Persistence dashboards

Note the image URI for use in `terraform.tfvars`.

### 4. Create Aurora DSQL Cluster

Create an Aurora DSQL cluster (the cluster is managed separately from this Terraform module):

```bash
# Create DSQL cluster
aws dsql create-cluster \
    --deletion-protection-enabled \
    --tags Key=Name,Value=temporal-dsql \
    --region eu-west-1

# Note the cluster identifier from the output, then get the endpoint:
aws dsql get-cluster --identifier <cluster-id> --region eu-west-1

# The output will show:
#   "endpoint": "xxxxx.dsql.eu-west-1.on.aws"
#   "arn": "arn:aws:dsql:eu-west-1:123456789012:cluster/xxxxx"
```

The cluster takes a few minutes to become ACTIVE. Check status with:
```bash
aws dsql get-cluster --identifier <cluster-id> --region eu-west-1 --query 'status'
```

### 5. Setup DSQL Schema

Setup the Temporal schema in Aurora DSQL (requires the cluster to be ACTIVE):

```bash
# Using environment (reads endpoint from Terraform outputs)
./scripts/setup-schema.sh dev

# Or specify endpoint directly
./scripts/setup-schema.sh --endpoint xxxxx.dsql.eu-west-1.on.aws

# With custom options
./scripts/setup-schema.sh dev --overwrite

# To reset schema (drop and recreate)
./scripts/setup-schema.sh --endpoint xxxxx.dsql.eu-west-1.on.aws --overwrite
```

### 6. Configure Terraform Variables

```bash
# Navigate to your environment directory
cd terraform/envs/dev  # or bench, prod

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

Required variables:
- `temporal_image`: ECR repository URL for the runtime image (`temporal-dsql-runtime:latest` from step 2)
- `temporal_admin_tools_image`: ECR repository URL for admin tools image (`temporal-dsql-admin-tools:latest` from step 2)
- `grafana_image`: ECR repository URL for Grafana image (`temporal-grafana:latest` from step 3)
- `dsql_cluster_endpoint`: Aurora DSQL cluster endpoint (from step 4)
- `dsql_cluster_arn`: Aurora DSQL cluster ARN (from step 4)

### 7. Deploy Infrastructure

```bash
cd terraform/envs/dev  # or bench, prod

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
# Note: Services deploy with 0 replicas by default
terraform apply
```

### 8. Setup OpenSearch Schema

After deployment, run the one-time OpenSearch schema setup. This task runs on Fargate and doesn't require EC2 instances:

```bash
# Run the OpenSearch setup task (runs on Fargate inside VPC)
cd terraform/envs/dev
terraform output -raw opensearch_setup_command | bash

# Monitor the setup task logs
aws logs tail /ecs/temporal-dev/opensearch-setup --follow --region eu-west-1
```

Alternative: If you have network access to OpenSearch (e.g., via VPN or Direct Connect), you can use the local script with `awscurl`:

```bash
# Requires: pip install awscurl
# Set the OpenSearch endpoint
cd terraform/envs/dev
export TEMPORAL_OPENSEARCH_HOST=$(terraform output -raw opensearch_endpoint)
./scripts/setup-opensearch.sh
```

### 9. Wait for EC2 Instances

Wait for the 6 EC2 instances to register with the ECS cluster:

```bash
./scripts/cluster-management.sh dev wait-ec2
```

This waits for all 6 instances to be registered before proceeding.

### 10. Scale Up Services

After schema setup is complete, scale up the Temporal services:

```bash
# Scale all services to production counts
./scripts/scale-services.sh dev up

# Or specify cluster directly
./scripts/scale-services.sh dev up --cluster temporal-dev-cluster --region eu-west-1

# To scale down (e.g., for cost savings)
./scripts/scale-services.sh dev down
```

## Remote Access

All services run in private subnets with no public endpoints. Access is via SSM Session Manager port forwarding.

### Access Temporal UI

```bash
# Get the port forwarding command
terraform output -raw temporal_ui_port_forward_command

# Or manually:
# 1. Get the task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster temporal-dev-cluster \
  --service-name temporal-dev-temporal-ui \
  --query 'taskArns[0]' \
  --output text \
  --region eu-west-1)

# 2. Get task ID and runtime ID
TASK_ID=$(echo $TASK_ARN | cut -d'/' -f3)
RUNTIME_ID=$(aws ecs describe-tasks \
  --cluster temporal-dev-cluster \
  --tasks $TASK_ARN \
  --query 'tasks[0].containers[?name==`temporal-ui`].runtimeId' \
  --output text \
  --region eu-west-1)

# 3. Start port forwarding
aws ssm start-session \
  --target ecs:temporal-dev-cluster_${TASK_ID}_${RUNTIME_ID} \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}' \
  --region eu-west-1

# 4. Open browser to http://localhost:8080
```

### Access Grafana

```bash
# Get the port forwarding command
terraform output -raw grafana_port_forward_command

# Or manually (similar to above, but with port 3000)
# ...

# Open browser to http://localhost:3000
# Login: admin / <password from Secrets Manager>
```

### ECS Exec (Shell Access)

Access any container directly:

```bash
# Get the ECS Exec command for a service
terraform output -raw temporal_frontend_ecs_exec_command

# Example: Access Frontend container
TASK_ARN=$(aws ecs list-tasks \
  --cluster temporal-dev-cluster \
  --service-name temporal-dev-temporal-frontend \
  --query 'taskArns[0]' \
  --output text \
  --region eu-west-1)

aws ecs execute-command \
  --cluster temporal-dev-cluster \
  --task $TASK_ARN \
  --container temporal-frontend \
  --interactive \
  --command "/bin/sh" \
  --region eu-west-1
```

## Grafana Dashboards

The deployment includes pre-configured Grafana dashboards for monitoring Temporal and DSQL:

### Available Dashboards

1. **Temporal Server Dashboard** (`grafana/server/server.json`)
   - Service request rates and latencies (Frontend, History, Matching)
   - Workflow execution outcomes
   - History task processing
   - Persistence latency by operation
   - Client metrics (History, Matching clients)

2. **DSQL Persistence Dashboard** (`grafana/dsql/persistence.json`)
   - Connection pool utilization (max_open, open, in_use, idle)
   - Transaction conflicts and retries (OCC metrics)
   - CloudWatch metrics for DSQL cluster health
   - DPU usage and commit latency

3. **Benchmark Dashboard** (`grafana/bench/bench.json`)
   - Workflow completion rate (WPS)
   - State transitions per second
   - Workflow latency percentiles
   - Generator and worker metrics

4. **Workers Dashboard** (`grafana/workers/workers.json`)
   - Worker task processing rates
   - Activity and workflow task latencies
   - Poller utilization
   - Worker slot availability

### Building Custom Grafana Image

The dashboards are baked into a custom Grafana image with pre-configured datasources:

```bash
# Build and push custom Grafana image to ECR (defaults to eu-west-1)
./scripts/build-grafana.sh

# Or specify a different region
./scripts/build-grafana.sh us-east-1

# Or use Terraform outputs for region (after initial deploy)
./scripts/build-grafana.sh dev

# Update terraform.tfvars with the new image
# grafana_image = "<account>.dkr.ecr.<region>.amazonaws.com/temporal-grafana:latest"
```

The custom image includes:
- Amazon Managed Prometheus datasource with SigV4 authentication
- CloudWatch datasource for DSQL metrics
- Pre-loaded dashboards in organized folders

### Datasources

| Datasource | Type | Purpose |
|------------|------|---------|
| Prometheus | Amazon Managed Prometheus | Temporal server metrics (via Alloy) |
| CloudWatch | AWS CloudWatch | Aurora DSQL service metrics |

### DSQL Plugin Metrics

The custom DSQL plugin emits these metrics (requires `framework: opentelemetry` in Temporal config):

| Metric | Type | Description |
|--------|------|-------------|
| `dsql_pool_max_open` | Gauge | Maximum configured connections |
| `dsql_pool_open` | Gauge | Currently open connections |
| `dsql_pool_in_use` | Gauge | Connections actively in use |
| `dsql_pool_idle` | Gauge | Idle connections in pool |
| `dsql_pool_wait_total` | Counter | Requests that waited for a connection |
| `dsql_pool_wait_duration` | Histogram | Time spent waiting for connections |
| `dsql_tx_conflict_total` | Counter | Transaction serialization conflicts |
| `dsql_tx_retry_total` | Counter | Transaction retry attempts |
| `dsql_tx_exhausted_total` | Counter | Retries exhausted (failures) |
| `dsql_tx_latency` | Histogram | Transaction latency including retries |

## Benchmarking

The deployment includes a benchmarking system for measuring Temporal performance with DSQL persistence. The benchmark runner is a Go application that executes configurable workflow patterns, collects metrics, and reports results.

### Benchmark Infrastructure

- **Dedicated EC2 nodes**: Scale-from-zero ASG with `workload=benchmark` attribute
- **Capacity provider**: ECS managed scaling provisions instances on demand
- **Metrics collection**: Prometheus metrics exposed on port 9090, scraped by Alloy

### Build Benchmark Image

```bash
# Build and push benchmark image to ECR
./scripts/build-benchmark.sh

# The script builds for ARM64 and pushes to:
# <account>.dkr.ecr.<region>.amazonaws.com/temporal-benchmark:latest
```

### Run a Benchmark

```bash
# Run with default configuration (100 WPS, 5 minutes, simple workflow)
./scripts/run-benchmark.sh bench --wait

# Run with custom parameters
./scripts/run-benchmark.sh bench \
  --namespace benchmark \
  --workflow-type simple \
  --rate 50 \
  --duration 2m \
  --wait

# Available workflow types:
# - simple: Single workflow that completes immediately
# - multi-activity: Workflow with configurable number of activities
# - timer: Workflow with configurable timer duration
# - child-workflow: Workflow that spawns child workflows
```

### Benchmark Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--namespace` | Namespace for benchmark workflows | `benchmark` |
| `--workflow-type` | Workflow pattern to execute | `simple` |
| `--rate` | Target workflows per second | `100` |
| `--duration` | Test duration | `5m` |
| `--ramp-up` | Ramp-up period | `30s` |
| `--workers` | Number of parallel workers | `4` |
| `--iterations` | Number of test iterations | `1` |
| `--max-p99-latency` | Maximum acceptable p99 latency | `5s` |
| `--min-throughput` | Minimum acceptable throughput | `50` |

### Get Benchmark Results

```bash
# Get results from the most recent benchmark run
./scripts/get-benchmark-results.sh bench

# Get results from a specific task
./scripts/get-benchmark-results.sh bench --task-id <task-id>
```

### Recommended Starting Parameters

For initial testing with the production configuration (4 history, 3 matching, 2 frontend):

```bash
# Start with a low rate to establish baseline
./scripts/run-benchmark.sh bench --rate 25 --duration 2m --wait

# Gradually increase rate
./scripts/run-benchmark.sh bench --rate 50 --duration 2m --wait
./scripts/run-benchmark.sh bench --rate 100 --duration 5m --wait
```

### Benchmark Results (January 2026)

Results from 400 WPS benchmark with 16 History, 16 Matching, 9 Frontend, 3 Worker, 51 Benchmark Worker replicas:

| Metric | Value |
|--------|-------|
| Target Rate | 400 WPS |
| Start Rate | 372 WPS |
| Peak Completion Rate | 323 WPS |
| Workflows Started | 111,696 |
| Workflows Completed | 111,692 (99.996%) |
| Peak State Transitions | 10,600 st/s |

Key findings:
- **99.996% workflow completion** - Near-perfect success rate
- **323 WPS peak throughput** - 81% of target rate achieved
- **10,600 st/s peak** - High state transition throughput
- **Workers not bottleneck** - 51 workers with 1,632 pollers had spare capacity

See [Benchmark Results](docs/benchmark-results.md) for detailed metrics and analysis.

### Viewing Benchmark Metrics

Benchmark metrics are scraped by Alloy and sent to Amazon Managed Prometheus. View them in Grafana:

1. Port forward to Grafana: `terraform output -raw grafana_port_forward_command`
2. Open http://localhost:3000
3. Query metrics like:
   - `benchmark_workflow_latency_seconds` - Workflow completion latency
   - `benchmark_workflows_started_total` - Total workflows started
   - `benchmark_workflows_completed_total` - Total workflows completed

## Cost Estimate

Estimated costs for eu-west-1 region (January 2026):

| Resource | Configuration | Hourly Cost |
|----------|--------------|-------------|
| EC2 (23 instances) | m8g.4xlarge (16 vCPU, 64 GB each) | $18.47 |
| NAT Gateway | Single AZ | $0.048 |
| NAT Gateway Data | ~2 GB/hr estimate | $0.096 |
| OpenSearch (3 nodes) | m6g.large.search, 100GB gp3 each | $0.42 |
| VPC Endpoints (8 interface) | Per endpoint/AZ | $0.088 |
| CloudWatch Logs | ~200 MB/hr | $0.012 |
| Secrets Manager | 1 secret | $0.0004 |
| Amazon Managed Prometheus | Workspace + ingestion | $0.02 |
| DynamoDB | On-demand, rate limiter table | ~$0.001 |
| **Total Hourly** | | **~$19.80** |

### Daily/Monthly Estimates

| Usage Pattern | Cost |
|--------------|------|
| 8-hour development day | ~$158 |
| Monthly (8 hrs/day, 22 days) | ~$3,500 |
| 24/7 operation | ~$14,400/month |

See [Benchmark Results](docs/benchmark-results.md) for detailed cost breakdown including DSQL DPU costs.

### Cost Optimization Tips

1. **Stop EC2 instances outside work hours**: Use ASG scheduled scaling or manual stop
2. **NAT Gateway**: Consider NAT instances for dev (~$0.01/hr vs $0.048/hr)
3. **VPC Endpoints**: Fixed cost regardless of usage
4. **Graviton**: Already provides 20-40% savings over x86
5. **DSQL**: Uses IAM auth, no Secrets Manager costs for DB credentials
6. **EC2 vs Fargate**: EC2 provides better cost efficiency for sustained workloads

## Troubleshooting

### "ECS Service Linked Role is not ready"

If you see this error during `terraform apply`:
```
Error: creating ECS Cluster: Failed to create Namespace ECS Service Linked Role is not ready
```

The ECS service-linked role doesn't exist in your AWS account. Create it manually:

```bash
aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com

# Then re-run apply
terraform apply
```

This is a one-time setup per AWS account. The role is created automatically when you first use ECS through the console, but needs to be created manually when using Terraform in a fresh account.

### "Session Manager plugin not found"

Install the Session Manager plugin for your OS (see Prerequisites).

### "Unable to start session" or "Access denied"

Check IAM permissions:
```json
{
  "Effect": "Allow",
  "Action": [
    "ecs:ExecuteCommand",
    "ecs:DescribeTasks",
    "ssm:StartSession"
  ],
  "Resource": "*"
}
```

### "Task not found"

Tasks may have been replaced. Re-run `list-tasks` to get current task ID:
```bash
aws ecs list-tasks --cluster temporal-dev-cluster --service-name <service-name>
```

### Services not starting

Check CloudWatch Logs for each service:
```bash
aws logs tail /ecs/temporal-dev/temporal-frontend --follow --region eu-west-1
```

### OpenSearch connection issues

1. Verify OpenSearch domain is active:
   ```bash
   aws opensearch describe-domain --domain-name temporal-dev-visibility
   ```

2. Check security group rules allow traffic from Temporal services

3. Verify IAM role has `es:ESHttp*` permissions

### DSQL connection issues

1. Verify DSQL cluster is active:
   ```bash
   aws dsql get-cluster --identifier <cluster-id>
   ```

2. Check IAM role has `dsql:DbConnect` and `dsql:DbConnectAdmin` permissions

3. Verify security group allows outbound to DSQL endpoint

### Alloy metrics not appearing in AMP

1. Check Alloy sidecar logs:
   ```bash
   aws logs tail /ecs/temporal-dev/temporal-history --follow --region eu-west-1
   ```

2. Verify Alloy can reach Temporal services:
   - Check security groups allow traffic on port 9090
   - Verify Service Connect DNS names resolve correctly

3. Check IAM role has `aps:RemoteWrite` permissions

### Crash Loop Recovery (Ringpop Issues)

If services are stuck in crash loops due to stale cluster membership (common after infrastructure changes):

```bash
# Full recovery: scale down, clean membership, scale up
./scripts/cluster-management.sh dev recover

# Or run steps individually:
./scripts/cluster-management.sh dev scale-down
./scripts/cluster-management.sh dev clean-membership  # Prompts to DELETE FROM cluster_membership
./scripts/cluster-management.sh dev scale-up
```

### After Image Updates

After pushing new images to ECR, force new deployments:

```bash
./scripts/cluster-management.sh dev force-deploy
```

### Check Cluster Status

View EC2 instances and service status:

```bash
./scripts/cluster-management.sh dev status
```

## Alloy Sidecar for Metrics and Logs

Each Temporal service task includes a Grafana Alloy sidecar container for observability:

- **Prometheus Scraping**: Scrapes metrics from localhost:9090 within the same task
- **AMP Remote Write**: Sends metrics to Amazon Managed Prometheus using SigV4 authentication
- **Log Collection**: Collects container logs and sends to Loki
- **Per-Task Collection**: Each service replica has its own Alloy sidecar for reliable metrics

The sidecar approach provides better reliability than a centralized collector - if a service task fails, its metrics are still collected up until failure. Configuration is embedded in the task definition.

### Viewing Metrics

Access metrics through Grafana (port forward to localhost:3000) or query AMP directly:

```bash
# Get Prometheus query endpoint
terraform output -raw prometheus_query_endpoint

# Example: Query Temporal workflow metrics
curl -G --data-urlencode 'query=temporal_workflow_completed_total' \
  "$(terraform output -raw prometheus_query_endpoint)/api/v1/query"
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| project_name | Project name for resource naming | string | "temporal-dev" | no |
| region | AWS region | string | "eu-west-1" | no |
| vpc_cidr | VPC CIDR block | string | "10.0.0.0/16" | no |
| availability_zones | List of AZs | list(string) | ["eu-west-1a", "eu-west-1b"] | no |
| temporal_image | Custom Temporal Docker image URI | string | - | yes |
| temporal_admin_tools_image | Admin tools Docker image URI | string | - | yes |
| dsql_cluster_endpoint | Aurora DSQL cluster endpoint | string | - | yes |
| dsql_cluster_arn | Aurora DSQL cluster ARN | string | - | yes |
| ec2_instance_type | EC2 instance type (ARM64) | string | "m7g.2xlarge" | no |
| ec2_instance_count | Number of EC2 instances | number | 10 | no |
| temporal_history_cpu | History service CPU units | number | 4096 | no |
| temporal_history_memory | History service memory MB | number | 8192 | no |
| temporal_history_count | History service task count | number | 0 | no |
| temporal_history_shards | Number of history shards | number | 4096 | no |
| temporal_matching_cpu | Matching service CPU units | number | 1024 | no |
| temporal_matching_memory | Matching service memory MB | number | 2048 | no |
| temporal_matching_count | Matching service task count | number | 0 | no |
| temporal_frontend_cpu | Frontend service CPU units | number | 2048 | no |
| temporal_frontend_memory | Frontend service memory MB | number | 4096 | no |
| temporal_frontend_count | Frontend service task count | number | 0 | no |
| temporal_worker_cpu | Worker service CPU units | number | 512 | no |
| temporal_worker_memory | Worker service memory MB | number | 1024 | no |
| temporal_worker_count | Worker service task count | number | 0 | no |
| temporal_ui_cpu | UI service CPU units | number | 256 | no |
| temporal_ui_memory | UI service memory MB | number | 512 | no |
| temporal_ui_count | UI service task count | number | 0 | no |
| grafana_cpu | Grafana CPU units | number | 256 | no |
| grafana_memory | Grafana memory MB | number | 512 | no |
| grafana_admin_secret_name | Secrets Manager secret name | string | "grafana/admin" | no |
| alloy_cpu | Alloy sidecar CPU units | number | 256 | no |
| alloy_memory | Alloy sidecar memory MB | number | 512 | no |
| log_retention_days | CloudWatch Logs retention | number | 7 | no |

## Outputs

| Name | Description |
|------|-------------|
| ecs_cluster_arn | ARN of the ECS cluster |
| ecs_cluster_name | Name of the ECS cluster |
| all_service_names | Map of all ECS service names |
| opensearch_endpoint | OpenSearch domain endpoint |
| prometheus_remote_write_endpoint | Prometheus remote write URL |
| prometheus_query_endpoint | Prometheus query URL |
| loki_endpoint | Loki endpoint for log queries |
| temporal_ui_port_forward_command | Command to port forward Temporal UI |
| grafana_port_forward_command | Command to port forward Grafana |
| temporal_*_ecs_exec_command | ECS Exec commands for each service |
| deployment_summary | Summary of deployment with access commands |

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

This project was developed with significant assistance from [Kiro](https://kiro.dev), an AI-powered IDE. The `.kiro/specs/` directory contains the structured specifications that guided the implementation, including requirements, design documents, and task tracking.
