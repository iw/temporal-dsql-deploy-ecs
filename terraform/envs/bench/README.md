# Bench Environment

Benchmarking environment for Temporal on ECS with Aurora DSQL persistence. This environment uses larger resources for load testing and performance validation, with the benchmark module enabled by default.

## Prerequisites

Before deploying this environment, ensure you have:

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.14.0 installed
3. **Aurora DSQL cluster** created and accessible
4. **Grafana admin secret** created in Secrets Manager (see setup below)
5. **Temporal Docker images** built and pushed to ECR
6. **Benchmark Docker image** built and pushed to ECR

## Backend Configuration

This environment supports remote state storage using S3 with native S3 state locking. Create a `backend.hcl` file:

```hcl
bucket       = "your-terraform-state-bucket"
key          = "temporal-dsql/bench/terraform.tfstate"
region       = "eu-west-1"
encrypt      = true
use_lockfile = true
```

> **Note**: S3 native state locking (via `use_lockfile`) is used by default. See [S3 Backend Documentation](https://developer.hashicorp.com/terraform/language/backend/s3) for details.

Initialize with the backend configuration:

```bash
terraform init -backend-config=backend.hcl
```

For local development without remote state, simply run:

```bash
terraform init
```

## Configuration

The `terraform.tfvars.example` file is the source of truth for environment configuration. Copy it to create your `terraform.tfvars`:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then update the required values (DSQL endpoint, cluster ARN, and image URIs). The example file contains representative defaults for a WPS 200 benchmark environment with full documentation of each setting.

Key required values:

```hcl
# Required - DSQL Configuration
dsql_cluster_endpoint      = "your-cluster-id.dsql.eu-west-1.on.aws"
dsql_cluster_arn           = "arn:aws:dsql:eu-west-1:123456789012:cluster/your-cluster-id"

# Required - Temporal Images (build with ./scripts/build-and-push-ecr.sh)
temporal_image             = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/temporal-dsql-runtime:latest"
temporal_admin_tools_image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/temporal-dsql-admin-tools:latest"

# Required - Benchmark Image (build with ./scripts/build-benchmark.sh)
benchmark_image            = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/temporal-benchmark:latest"

# Required - Grafana Image (build with ./scripts/build-grafana.sh)
grafana_image              = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/temporal-grafana:latest"
```

## Deployment Steps

### 1. Create Grafana Admin Secret

Before deploying, create the Grafana admin secret in Secrets Manager:

```bash
aws secretsmanager create-secret \
  --name grafana/admin \
  --secret-string '{"admin_user":"admin","admin_password":"your-secure-password"}' \
  --region eu-west-1
```

### 2. Initialize Terraform

```bash
cd terraform/envs/bench
terraform init -backend-config=backend.hcl
```

### 3. Review the Plan

```bash
terraform plan -out=plan.tfplan
```

### 4. Apply Infrastructure

```bash
terraform apply plan.tfplan
```

### 5. Setup DSQL Schema

After infrastructure is deployed, setup the DSQL schema:

```bash
# From the project root
./scripts/setup-schema.sh --from-terraform
```

### 6. Setup OpenSearch Index

Run the OpenSearch setup task:

```bash
terraform output -raw opensearch_setup_command | bash
```

### 7. Scale Up Services

Services deploy with `desired_count = 0` by default. Scale them up after schema setup:

```bash
# From the project root
./scripts/scale-services.sh bench up
```

## Running Benchmarks

### 1. Scale Up Benchmark Workers

Before running benchmarks, scale up the benchmark workers:

```bash
# Scale to 30 workers for 100 WPS testing
terraform output -raw scale_benchmark_workers_command | bash
```

### 2. Run Benchmark

Run a benchmark test:

```bash
terraform output -raw run_benchmark_command | bash
```

Or use the script with custom parameters:

```bash
# From the project root
./scripts/run-benchmark.sh --from-terraform --namespace benchmark --rate 100 --duration 5m --wait
```

### 3. Get Results

Retrieve benchmark results from CloudWatch logs:

```bash
# From the project root
./scripts/get-benchmark-results.sh --from-terraform
```

### 4. Scale Down Workers

After benchmarking, scale down workers to save costs:

```bash
aws ecs update-service \
  --cluster temporal-bench \
  --service benchmark-worker \
  --desired-count 0 \
  --region eu-west-1
```

## Accessing Services

### Temporal UI

Port forward to access the Temporal UI:

```bash
terraform output -raw temporal_ui_port_forward_command | bash
# Then open http://localhost:8080
```

### Grafana

Port forward to access Grafana dashboards:

```bash
terraform output -raw grafana_port_forward_command | bash
# Then open http://localhost:3000
```

### ECS Exec

Access container shells for debugging:

```bash
# Temporal Frontend
terraform output -raw temporal_frontend_ecs_exec_command | bash

# Temporal History
terraform output -raw temporal_history_ecs_exec_command | bash
```

## Resource Defaults

The bench environment uses larger resources for load testing:

| Resource | Default Value | Notes |
|----------|---------------|-------|
| EC2 Instance Type | m8g.4xlarge | 16 vCPU, 64 GB RAM per instance |
| EC2 Instance Count | 10 | 160 vCPU, 640 GB RAM total |
| History Replicas | 16 | 4096 CPU, 8192 MB each |
| History Shards | 4096 | |
| Matching Replicas | 16 | 1024 CPU, 2048 MB each |
| Frontend Replicas | 9 | 2048 CPU, 4096 MB each |
| Worker Replicas | 3 | 512 CPU, 1024 MB each |
| UI Replicas | 1 | 256 CPU, 512 MB |
| OpenSearch Instance Type | m6g.large.search | |
| OpenSearch Instance Count | 3 | |
| Loki | 1 replica | 512 CPU, 1024 MB, 14 day retention |
| Grafana | 1 replica | 256 CPU, 512 MB |
| Alloy Sidecars | Per service | Metrics + logs collection |
| Log Retention | 14 days | CloudWatch logs for observability |
| Benchmark Enabled | true | |
| Benchmark Max Instances | 13 | |

## Benchmark Scaling Recommendations

| Target WPS | Workers | EC2 Instances | Notes |
|------------|---------|---------------|-------|
| 100 | 30 | 4 | Conservative |
| 200 | 40 | 6 | Moderate |
| 400 | 51 | 8 | Max with default quota |

## Scaling Services

To scale services up or down:

```bash
# Scale all services up (production-like replicas)
./scripts/scale-services.sh bench up

# Scale all services down (0 replicas)
./scripts/scale-services.sh bench down

# Custom scaling via Terraform
terraform apply -var="temporal_history_count=8" -var="temporal_matching_count=6"
```

## Cleanup

To destroy all resources:

```bash
# Scale down services first
./scripts/scale-services.sh bench down

# Scale down benchmark workers
aws ecs update-service --cluster temporal-bench --service benchmark-worker --desired-count 0 --region eu-west-1

# Destroy infrastructure
terraform destroy
```

## Troubleshooting

### Services Not Starting

1. Query Loki logs: `./scripts/query-loki-logs.sh bench frontend`
2. Verify DSQL schema is setup: `./scripts/setup-schema.sh --from-terraform`
3. Verify OpenSearch index exists: Run the setup task

### Viewing Logs

Logs are collected by Alloy sidecars and sent to Loki. Query them using:

```bash
# Query frontend logs (last 10 minutes, default)
./scripts/query-loki-logs.sh bench frontend

# Query history logs with custom time range
./scripts/query-loki-logs.sh bench history -t 2h

# Query matching logs with filter
./scripts/query-loki-logs.sh bench matching -f "error"

# Query benchmark logs
./scripts/query-loki-logs.sh bench benchmark -t 30m
```

Or use Grafana's Logs Drilldown UI after port forwarding.

### Benchmark Not Running

1. Verify benchmark image is pushed to ECR
2. Query benchmark logs: `./scripts/query-loki-logs.sh bench benchmark`
3. Ensure benchmark workers are scaled up
4. Verify Service Connect can resolve `temporal-frontend`

### Connection Issues

1. Verify VPC endpoints are healthy
2. Check security group rules allow required traffic
3. Verify IAM roles have correct permissions

### ECS Exec Not Working

1. Ensure SSM Session Manager plugin is installed
2. Verify SSM Messages VPC endpoint exists
3. Check task has `initProcessEnabled = true`

## Related Documentation

- [Project README](../../../README.md)
- [Module Documentation](../../modules/)
- [Migration Guide](../../MIGRATION.md)
- [Benchmark Documentation](../../../benchmark/README.md)
