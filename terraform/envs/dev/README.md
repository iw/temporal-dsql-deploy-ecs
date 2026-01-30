# Dev Environment

Development environment for Temporal on ECS with Aurora DSQL persistence. This environment uses minimal resources for cost-effective development and testing.

## Prerequisites

Before deploying this environment, ensure you have:

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.14.0 installed
3. **Aurora DSQL cluster** created and accessible
4. **Grafana admin secret** created in Secrets Manager (see setup below)
5. **Temporal Docker images** built and pushed to ECR

## Backend Configuration

This environment supports remote state storage using S3 with native S3 state locking. Create a `backend.hcl` file:

```hcl
bucket       = "your-terraform-state-bucket"
key          = "temporal-dsql/dev/terraform.tfstate"
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

Then update the required values (DSQL endpoint, cluster ARN, and image URIs). The example file contains representative defaults for a WPS 50 development environment with full documentation of each setting.

Key required values:

```hcl
# Required - DSQL Configuration
dsql_cluster_endpoint      = "your-cluster-id.dsql.eu-west-1.on.aws"
dsql_cluster_arn           = "arn:aws:dsql:eu-west-1:123456789012:cluster/your-cluster-id"

# Required - Temporal Images (build with ./scripts/build-and-push-ecr.sh)
temporal_image             = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/temporal-dsql-runtime:latest"
temporal_admin_tools_image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/temporal-dsql-admin-tools:latest"

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
cd terraform/envs/dev
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

### 7. Verify Services

Services deploy with WPS 50 configuration by default. Verify they are running:

```bash
# Check service status
aws ecs describe-services \
  --cluster temporal-dev-cluster \
  --services temporal-dev-temporal-history temporal-dev-temporal-matching temporal-dev-temporal-frontend \
  --query 'services[].{name:serviceName,running:runningCount,desired:desiredCount}'
```

To scale to a different WPS configuration:

```bash
# From the project root
./scripts/scale-services.sh dev up --wps 100
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

The dev environment uses WPS 50 configuration for minimal development workloads:

| Resource | Default Value | Notes |
|----------|---------------|-------|
| EC2 Instance Type | m8g.xlarge | 4 vCPU, 16 GB RAM per instance |
| EC2 Instance Count | 4 | 16 vCPU, 64 GB RAM total |
| History Replicas | 3 | 1024 CPU, 4096 MB each |
| History Shards | 2048 | |
| Matching Replicas | 2 | 1024 CPU, 2048 MB each |
| Frontend Replicas | 2 | 512 CPU, 2048 MB each |
| Worker Replicas | 2 | 512 CPU, 1024 MB each |
| UI Replicas | 1 | 256 CPU, 512 MB |
| OpenSearch Instance Type | m6g.large.search | |
| OpenSearch Instance Count | 2 | |
| Loki | 1 replica | 512 CPU, 1024 MB, 7 day retention |
| Grafana | 1 replica | 256 CPU, 512 MB |
| Alloy Sidecars | Per service | Metrics + logs collection |
| Log Retention | 7 days | CloudWatch logs for observability |
| Benchmark | Enabled | Max 4 instances, WPS 25-50 |

### Resource Summary

- **Total Temporal Tasks**: 10 (history=3, matching=2, frontend=2, worker=2, ui=1)
- **Total Observability Tasks**: 2 (loki=1, grafana=1)
- **Total CPU**: ~6.5 vCPU
- **Total Memory**: ~15 GB
- **Headroom**: ~9 vCPU, ~49 GB RAM for scaling

## Scaling Services

Services are deployed with WPS 50 configuration by default. To scale:

```bash
# Scale to WPS 100 configuration
./scripts/scale-services.sh dev up --wps 100

# Scale to WPS 50 configuration (default)
./scripts/scale-services.sh dev up --wps 50

# Scale all services down (0 replicas)
./scripts/scale-services.sh dev down

# Custom scaling via Terraform
terraform apply -var="temporal_history_count=4" -var="temporal_matching_count=3"
```

## Cleanup

To destroy all resources:

```bash
# Scale down services first
./scripts/scale-services.sh dev down

# Destroy infrastructure
terraform destroy
```

## Troubleshooting

### Services Not Starting

1. Query Loki logs: `./scripts/query-loki-logs.sh dev frontend`
2. Verify DSQL schema is setup: `./scripts/setup-schema.sh --from-terraform`
3. Verify OpenSearch index exists: Run the setup task

### Viewing Logs

Logs are collected by Alloy sidecars and sent to Loki. Query them using:

```bash
# Query frontend logs (last 10 minutes, default)
./scripts/query-loki-logs.sh dev frontend

# Query history logs with custom time range
./scripts/query-loki-logs.sh dev history -t 2h

# Query matching logs with filter
./scripts/query-loki-logs.sh dev matching -f "error"

# Query benchmark logs
./scripts/query-loki-logs.sh dev benchmark -t 30m
```

Or use Grafana's Logs Drilldown UI after port forwarding.

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
