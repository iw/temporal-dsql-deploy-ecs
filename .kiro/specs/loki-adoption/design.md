# Design Document: Loki Adoption

## Overview

This document describes the technical design for replacing CloudWatch Logs with Grafana Loki in the Temporal ECS deployment. The solution uses Grafana Alloy as a unified collector for both metrics (to Amazon Managed Prometheus) and logs (to Loki), replacing the existing ADOT sidecars.

### Key Design Decisions

1. **Loki Single-Binary Mode**: Deploy Loki as a single ECS service for simplicity
2. **S3 TSDB Storage**: Use S3 for both chunks and index (no DynamoDB required)
3. **Grafana Alloy**: Replace ADOT sidecars with Alloy for unified metrics + logs
4. **Docker Log Tailing**: Alloy reads Docker JSON logs via `loki.source.docker`
5. **JSON Structured Logging**: Preserve JSON format for structured queries

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LOKI LOGGING ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    ECS TASK (e.g., temporal-history)                │   │
│  │  ┌─────────────────────┐    ┌─────────────────────────────────────┐ │   │
│  │  │   Main Container    │    │         Alloy Sidecar               │ │   │
│  │  │  (temporal-history) │    │                                     │ │   │
│  │  │                     │    │  ┌─────────────────────────────┐    │ │   │
│  │  │  stdout → Docker    │───▶│  │ loki.source.docker          │    │ │   │
│  │  │  JSON log driver    │    │  │ (reads Docker logs)         │    │ │   │
│  │  │                     │    │  └─────────────┬───────────────┘    │ │   │
│  │  │  :9090 metrics ─────│───▶│  ┌─────────────▼───────────────┐    │ │   │
│  │  │                     │    │  │ prometheus.scrape           │    │ │   │
│  │  └─────────────────────┘    │  │ (scrapes localhost:9090)    │    │ │   │
│  │                             │  └─────────────┬───────────────┘    │ │   │
│  │                             │                │                    │ │   │
│  │                             │  ┌─────────────▼───────────────┐    │ │   │
│  │                             │  │ loki.write                  │────│─│───┼──▶ Loki
│  │                             │  │ prometheus.remote_write     │────│─│───┼──▶ AMP
│  │                             │  └─────────────────────────────┘    │ │   │
│  │                             └─────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         LOKI SERVICE                                │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │                    Loki (Single Binary)                     │   │   │
│  │  │                                                             │   │   │
│  │  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌──────────┐ │   │   │
│  │  │  │ Ingester  │  │  Querier  │  │ Compactor │  │  Query   │ │   │   │
│  │  │  │           │  │           │  │           │  │ Frontend │ │   │   │
│  │  │  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └──────────┘ │   │   │
│  │  │        │              │              │                      │   │   │
│  │  │        └──────────────┼──────────────┘                      │   │   │
│  │  │                       ▼                                     │   │   │
│  │  │              ┌─────────────────┐                            │   │   │
│  │  │              │   S3 Bucket     │                            │   │   │
│  │  │              │  (chunks+index) │                            │   │   │
│  │  │              └─────────────────┘                            │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         GRAFANA                                     │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │  Datasources:                                               │   │   │
│  │  │  - Prometheus (AMP) ──────────────────────────▶ Metrics     │   │   │
│  │  │  - Loki ──────────────────────────────────────▶ Logs        │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. Loki Service

**Purpose**: Centralized log aggregation and querying

**Deployment**: Single ECS service with single-binary Loki

**Configuration**:
```yaml
# loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9095
  log_level: info

common:
  path_prefix: /loki
  storage:
    s3:
      bucketnames: ${S3_BUCKET_NAME}
      region: ${AWS_REGION}
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  tsdb_shipper:
    active_index_directory: /loki/tsdb-index
    cache_location: /loki/tsdb-cache

ingester:
  chunk_encoding: snappy
  chunk_idle_period: 5m
  chunk_target_size: 1536000
  max_chunk_age: 1h

compactor:
  working_directory: /loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: s3

limits_config:
  retention_period: 168h  # 7 days
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_streams_per_user: 10000
  max_entries_limit_per_query: 5000

query_range:
  parallelise_shardable_queries: true
```

**Resource Allocation**:
| Resource | Development | Production |
|----------|-------------|------------|
| CPU | 512 | 1024 |
| Memory | 1024 MB | 2048 MB |
| Replicas | 1 | 1-3 |

### 2. Grafana Alloy Sidecar

**Purpose**: Unified metrics and logs collection, replacing ADOT sidecars

**Deployment**: Sidecar container in each Temporal service task

**Configuration**:
```alloy
// alloy-config.alloy

// ============================================================================
// LOGGING PIPELINE
// ============================================================================

// Discover Docker containers on this host
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

// Read logs from Docker containers
loki.source.docker "docker_logs" {
  host    = "unix:///var/run/docker.sock"
  targets = discovery.docker.containers.targets
  
  forward_to = [loki.process.add_labels.receiver]
  
  labels = {
    job = "docker",
  }
}

// Process and add labels
loki.process "add_labels" {
  forward_to = [loki.write.loki.receiver]
  
  stage.static_labels {
    values = {
      service_name = env("SERVICE_NAME"),
      cluster      = env("ECS_CLUSTER"),
    }
  }
  
  // Parse JSON logs
  stage.json {
    expressions = {
      level   = "level",
      msg     = "msg",
      caller  = "caller",
    }
  }
  
  // Add parsed fields as labels
  stage.labels {
    values = {
      level = "",
    }
  }
}

// Write logs to Loki
loki.write "loki" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}

// ============================================================================
// METRICS PIPELINE
// ============================================================================

// Scrape Prometheus metrics from main container
prometheus.scrape "temporal" {
  targets = [
    {"__address__" = "localhost:9090"},
  ]
  
  forward_to = [prometheus.relabel.add_labels.receiver]
  
  scrape_interval = "15s"
  scrape_timeout  = "10s"
}

// Add service labels
prometheus.relabel "add_labels" {
  forward_to = [prometheus.remote_write.amp.receiver]
  
  rule {
    target_label = "service_name"
    replacement  = env("SERVICE_NAME")
  }
  
  rule {
    target_label = "task_id"
    replacement  = env("ECS_TASK_ID")
  }
}

// Write metrics to Amazon Managed Prometheus
prometheus.remote_write "amp" {
  endpoint {
    url = env("AMP_REMOTE_WRITE_ENDPOINT")
    
    sigv4 {
      region = env("AWS_REGION")
    }
  }
}
```

**Resource Allocation**:
| Resource | Value |
|----------|-------|
| CPU | 128 |
| Memory | 256 MB |

### 3. S3 Bucket

**Purpose**: Durable storage for log chunks and TSDB index

**Configuration**:
```hcl
resource "aws_s3_bucket" "loki" {
  bucket = "${var.project_name}-loki-logs"
  
  tags = {
    Name    = "${var.project_name}-loki-logs"
    Service = "loki"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    
    expiration {
      days = var.loki_retention_days + 1  # Buffer for compactor
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

### 4. Grafana Datasource

**Purpose**: Enable log querying via Grafana UI

**Configuration** (added to Grafana provisioning):
```yaml
# datasources/loki.yaml
apiVersion: 1

datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: false
    jsonData:
      maxLines: 1000
```

## Data Models

### Log Entry Structure

Logs are stored with the following label schema:

```
{
  // Stream labels (indexed)
  service_name: "history" | "matching" | "frontend" | "worker" | "ui",
  cluster: "temporal-dev",
  container_name: "temporal-history",
  task_id: "abc123...",
  level: "info" | "warn" | "error" | "debug",
  
  // Log line (not indexed)
  line: "{\"level\":\"info\",\"ts\":\"2024-01-15T10:30:00Z\",\"msg\":\"...\",\"caller\":\"...\"}"
}
```

### LogQL Query Examples

```logql
# All logs from history service
{service_name="history"}

# Error logs from all services
{cluster="temporal-dev"} |= "error"

# JSON parsed query for specific workflow
{service_name="history"} | json | WorkflowID="my-workflow-123"

# Rate of errors per service
sum by (service_name) (rate({cluster="temporal-dev"} |= "error" [5m]))
```


## Terraform Implementation

### New Files

| File | Purpose |
|------|---------|
| `loki.tf` | Loki ECS service, task definition, security group |
| `loki-s3.tf` | S3 bucket for Loki storage |
| `alloy-sidecar.tf` | Alloy sidecar configuration (replaces `adot-sidecar.tf`) |
| `templates/alloy-sidecar-config.alloy` | Alloy configuration template |
| `templates/loki-config.yaml` | Loki configuration template |

### Modified Files

| File | Changes |
|------|---------|
| `grafana.tf` | Add Loki datasource provisioning |
| `temporal-history.tf` | Replace ADOT sidecar with Alloy sidecar |
| `temporal-matching.tf` | Replace ADOT sidecar with Alloy sidecar |
| `temporal-frontend.tf` | Replace ADOT sidecar with Alloy sidecar |
| `temporal-worker.tf` | Replace ADOT sidecar with Alloy sidecar |
| `iam.tf` | Add Loki task role with S3 permissions |
| `security-groups.tf` | Add Loki security group |
| `variables.tf` | Add Loki configuration variables |
| `outputs.tf` | Add Loki endpoint output |

### Removed Files

| File | Reason |
|------|--------|
| `adot-sidecar.tf` | Replaced by `alloy-sidecar.tf` |
| `templates/adot-sidecar-config.yaml` | Replaced by Alloy config |

### Variable Additions

```hcl
# Loki Configuration
variable "loki_enabled" {
  description = "Enable Loki for log aggregation (replaces CloudWatch Logs)"
  type        = bool
  default     = true
}

variable "loki_cpu" {
  description = "CPU units for Loki service"
  type        = number
  default     = 512
}

variable "loki_memory" {
  description = "Memory in MB for Loki service"
  type        = number
  default     = 1024
}

variable "loki_count" {
  description = "Desired task count for Loki service"
  type        = number
  default     = 1
}

variable "loki_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 7
}

variable "loki_image" {
  description = "Loki Docker image"
  type        = string
  default     = "grafana/loki:3.0.0"
}

variable "alloy_image" {
  description = "Grafana Alloy Docker image"
  type        = string
  default     = "grafana/alloy:v1.4.0"
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

Based on the prework analysis, most acceptance criteria are configuration checks (testable as examples). The following properties represent universal behaviors that should hold across all inputs:

### Property 1: Log Ingestion Completeness

*For any* container log line written to stdout by a Temporal service, the log SHALL appear in Loki within 30 seconds and be queryable via LogQL.

**Validates: Requirements 3.3, 3.5**

### Property 2: Label Consistency

*For any* log entry ingested into Loki, the labels `service_name`, `cluster`, `container_name`, and `task_id` SHALL be present and correctly populated from ECS metadata.

**Validates: Requirements 3.8**

### Property 3: Metrics Pipeline Continuity

*For any* Prometheus metric scraped by Alloy from a Temporal service, the metric SHALL be written to AMP with the same labels and values as the previous ADOT configuration.

**Validates: Requirements 3.2, 3.6**

### Property 4: JSON Structure Preservation

*For any* JSON-formatted log line written by a Temporal service, the JSON structure SHALL be preserved in Loki and be parseable via LogQL's `| json` operator.

**Validates: Requirements 3.7**

### Property 5: Sidecar Resilience

*For any* Alloy sidecar failure (crash, OOM, restart), the main Temporal container SHALL continue running without interruption.

**Validates: Requirements 3.11**

### Property 6: Retention Enforcement

*For any* log entry older than the configured retention period, the entry SHALL be deleted by the Loki compactor and not returned in queries.

**Validates: Requirements 5.2, 5.3**

### Property 7: Network Isolation

*For any* network request from Loki to S3, the request SHALL traverse the S3 gateway endpoint without internet egress.

**Validates: Requirements 6.5, 6.6**

## Error Handling

### Loki Unavailability

**Scenario**: Loki service is down or unreachable

**Handling**:
1. Alloy buffers logs locally (up to configured limit)
2. Alloy retries with exponential backoff
3. If buffer fills, oldest logs are dropped (FIFO)
4. Main container continues unaffected (sidecar is non-essential)

**Configuration**:
```alloy
loki.write "loki" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
    
    // Retry configuration
    retry_on_http_429 = true
    min_backoff       = "500ms"
    max_backoff       = "5m"
    max_retries       = 10
  }
  
  // Local buffer
  external_labels = {}
}
```

### S3 Access Failures

**Scenario**: S3 bucket is inaccessible

**Handling**:
1. Loki queues writes in memory/local disk
2. Loki retries S3 operations with backoff
3. If persistent, Loki logs errors and continues accepting ingestion
4. Queries may fail for affected time ranges

### Alloy Sidecar Crash

**Scenario**: Alloy container crashes or OOMs

**Handling**:
1. ECS restarts the sidecar (restart policy)
2. Main container continues running (non-essential sidecar)
3. Logs during downtime are lost (acceptable for dev/test)
4. Metrics during downtime are lost (gaps in dashboards)

## Testing Strategy

### Unit Tests

1. **Terraform Validation**: `terraform validate` and `terraform fmt -check`
2. **Configuration Syntax**: Validate Loki and Alloy config files
3. **IAM Policy Validation**: Ensure S3 permissions are correct

### Integration Tests

1. **Log Ingestion Test**:
   - Deploy stack
   - Generate test logs from a container
   - Query Loki via LogQL
   - Verify logs appear with correct labels

2. **Metrics Continuity Test**:
   - Compare metrics in AMP before/after migration
   - Verify all expected metrics are present
   - Check label consistency

3. **Retention Test**:
   - Ingest logs with backdated timestamps
   - Wait for compactor to run
   - Verify old logs are deleted

### Performance Tests

1. **Ingestion Rate**: Verify Loki handles 10 MB/s ingestion
2. **Query Latency**: Verify queries return in <10s for 7-day range
3. **Resource Usage**: Monitor Loki CPU/memory under load

## Migration Plan

### Phase 1: Deploy Loki Infrastructure (Day 1)

1. Create S3 bucket for Loki storage
2. Deploy Loki ECS service
3. Add Loki datasource to Grafana
4. Verify Loki is healthy and queryable

### Phase 2: Deploy Alloy Sidecars (Day 1-2)

1. Create Alloy configuration templates
2. Update one service (e.g., temporal-worker) to use Alloy
3. Verify logs appear in Loki
4. Verify metrics continue flowing to AMP
5. Roll out to remaining services

### Phase 3: Validation (Day 2-3)

1. Run benchmark workload
2. Query logs in Grafana
3. Compare metrics dashboards
4. Verify no regressions

### Phase 4: Cleanup (Day 3+)

1. Remove ADOT sidecar configuration
2. Optionally disable CloudWatch Logs (keep log groups for rollback)
3. Update documentation

### Rollback Plan

If issues are encountered:

1. Revert task definitions to use ADOT sidecars
2. Re-enable CloudWatch Logs log driver
3. Loki and S3 bucket can remain (no data loss)
4. Investigate and fix issues before retry

## Cost Analysis

### Current CloudWatch Logs Costs

| Component | Volume | Unit Cost | Monthly Cost |
|-----------|--------|-----------|--------------|
| Ingestion | 50 GB/month | $0.50/GB | $25.00 |
| Storage | 50 GB × 7 days avg | $0.03/GB | $1.50 |
| Queries | 100 GB scanned | $0.005/GB | $0.50 |
| VPC Endpoint | 1 endpoint | ~$7.50/month | $7.50 |
| **Total** | | | **~$34.50/month** |

### Proposed Loki + S3 Costs

| Component | Volume | Unit Cost | Monthly Cost |
|-----------|--------|-----------|--------------|
| S3 Storage | 50 GB/month | $0.023/GB | $1.15 |
| S3 PUT Requests | 500K requests | $0.005/1K | $2.50 |
| S3 GET Requests | 100K requests | $0.0004/1K | $0.04 |
| ECS Task (Loki) | 512 CPU, 1024 MB | ~$8/month | $8.00 |
| ECS Task (Alloy delta) | ~0 (replaces ADOT) | $0 | $0.00 |
| **Total** | | | **~$11.69/month** |

### Savings Summary

| Metric | Value |
|--------|-------|
| Monthly Savings | ~$22.81 |
| Percentage Reduction | ~66% |
| Annual Savings | ~$274 |

*Note: Costs scale with log volume. At higher volumes, S3 savings increase proportionally.*

## Security Considerations

### IAM Permissions

Loki task role requires:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${bucket_name}",
        "arn:aws:s3:::${bucket_name}/*"
      ]
    }
  ]
}
```

Alloy sidecar requires (same as current ADOT):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "aps:RemoteWrite"
      ],
      "Resource": "*"
    }
  ]
}
```

### Network Security

- Loki runs in private subnets only
- No public IP assigned
- S3 access via gateway endpoint (no internet)
- Security group allows only ECS instances and Grafana

### Data Security

- S3 bucket encrypted with SSE-S3
- No sensitive data in log labels (only metadata)
- Log content may contain sensitive data (same as CloudWatch)
