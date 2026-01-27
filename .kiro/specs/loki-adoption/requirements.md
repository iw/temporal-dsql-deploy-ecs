# Requirements Document

## Introduction

This spec captures the design and implementation of Grafana Loki as a replacement for CloudWatch Logs in the Temporal ECS deployment. The goal is to significantly reduce logging costs during development and testing while maintaining good log querying capabilities through the existing Grafana setup.

## Problem Statement

CloudWatch Logs costs are high during testing and development. The current setup sends all container logs to CloudWatch Logs, which charges for:
- **Ingestion**: $0.50 per GB ingested
- **Storage**: $0.03 per GB per month
- **Queries**: $0.005 per GB scanned

For a Temporal cluster with 20+ containers generating verbose logs during benchmarks, this adds up quickly. A self-hosted alternative using S3 for storage would reduce costs to:
- **S3 Storage**: ~$0.023 per GB per month (Standard)
- **S3 Requests**: ~$0.0004 per 1,000 PUT requests
- **No query charges**: Loki queries are free

## Glossary

- **Loki**: Grafana Loki, a horizontally-scalable, highly-available log aggregation system inspired by Prometheus
- **LogQL**: Loki's query language, similar to PromQL but for logs
- **Fluent_Bit**: Lightweight log processor and forwarder
- **Alloy**: Grafana Alloy, the OpenTelemetry Collector distribution from Grafana Labs (successor to Grafana Agent)
- **Chunk**: A compressed block of log data stored in object storage
- **Index**: Metadata about chunks stored in a key-value store (BoltDB, DynamoDB, or S3)
- **Single_Store_Mode**: Loki configuration where both index and chunks are stored in S3 (TSDB + S3)
- **FireLens**: AWS ECS log router that can forward container logs to various destinations

## Current Architecture

The existing logging setup:
- **CloudWatch Logs**: All ECS container logs via `awslogs` driver
- **Log Groups**: One per service (`/ecs/{project}/temporal-history`, etc.)
- **Retention**: Configurable via `log_retention_days` variable (default: 7 days)
- **VPC Endpoint**: CloudWatch Logs endpoint exists for private connectivity

## Proposed Architecture

Replace CloudWatch Logs with Grafana Loki:
- **Loki**: Single-binary deployment on ECS for simplicity
- **Log Collection**: Fluent Bit sidecar or FireLens for log forwarding
- **Storage**: S3 for chunks, S3 for index (single-store mode with TSDB)
- **Querying**: Grafana with Loki datasource (already deployed)

## Requirements

### Requirement 1: Loki Service Deployment

**User Story:** As an operator, I want Loki deployed as an ECS service, so that I can aggregate and query logs from all Temporal services.

#### Acceptance Criteria

1. THE Loki_Service SHALL be deployed as an ECS service on EC2 capacity
2. THE Loki_Service SHALL use ARM64 (Graviton) architecture for cost efficiency
3. THE Loki_Service SHALL expose port 3100 for HTTP API and log ingestion
4. THE Loki_Service SHALL be accessible via Service Connect DNS name `loki`
5. THE Loki_Service SHALL have a health check endpoint at `/ready`
6. THE Loki_Service SHALL run in single-binary mode (monolithic deployment)
7. THE Loki_Service SHALL be configurable via environment variables and config file

### Requirement 2: S3 Storage Backend

**User Story:** As an operator, I want Loki to store logs in S3, so that storage costs are minimized and data is durable.

#### Acceptance Criteria

1. THE Loki_Service SHALL use S3 for chunk storage
2. THE Loki_Service SHALL use S3 for index storage (TSDB single-store mode)
3. THE S3_Bucket SHALL be created with appropriate lifecycle policies
4. THE S3_Bucket SHALL use server-side encryption (SSE-S3 or SSE-KMS)
5. THE S3_Bucket SHALL have versioning disabled (logs are append-only)
6. THE Loki_Task_Role SHALL have permissions to read/write to the S3 bucket
7. THE S3_Gateway_Endpoint SHALL be used for private connectivity (already exists)

### Requirement 3: Log Collection via Grafana Alloy

**User Story:** As an operator, I want container logs forwarded to Loki via Grafana Alloy, so that all service logs are aggregated in one place with a unified observability stack.

**Design Decision: Why Alloy over Fluent Bit or FireLens**

We evaluated three log collection options:

| Aspect | Alloy | Fluent Bit | FireLens |
|--------|-------|------------|----------|
| **Grafana ecosystem** | ✅ Native | ❌ Third-party | ❌ AWS-native |
| **Loki integration** | ✅ First-class `loki.write` | ⚠️ Plugin required | ⚠️ Fluent Bit under hood |
| **Unified metrics+logs** | ✅ Single sidecar | ❌ Logs only | ❌ Logs only |
| **Configuration style** | OpenTelemetry-like | Custom DSL | Fluent Bit config |
| **ARM64 support** | ✅ Yes | ✅ Yes | ✅ Yes |

**Alloy was chosen because:**

1. **Unified collector**: Alloy can replace ADOT for metrics AND collect logs. This means one sidecar instead of two, reducing resource overhead and operational complexity.

2. **Native Loki support**: Alloy has first-class `loki.write` and `loki.source.*` components - no plugins or external dependencies needed.

3. **Grafana ecosystem alignment**: Same vendor as Loki and Grafana ensures guaranteed compatibility, consistent updates, and unified documentation.

4. **Similar configuration**: The current ADOT config uses OpenTelemetry patterns; Alloy uses similar concepts (`receivers`, `processors`, `exporters`), making migration straightforward.

5. **Future-proof**: Grafana is investing heavily in Alloy as their unified telemetry collector, replacing both Grafana Agent and Promtail.

**Why NOT Fluent Bit:**
- Adds another tool to the stack (different vendor, different config language)
- No metrics capability - would still need ADOT sidecars
- Plugin-based Loki integration is less robust than native support

**Why NOT FireLens:**
- AWS-specific, reduces portability
- Uses Fluent Bit under the hood anyway (same limitations)
- More complex ECS task definition changes required
- No unified metrics+logs capability

#### Acceptance Criteria

1. THE Log_Collection SHALL use Grafana Alloy as a sidecar container in each task
2. THE Alloy_Sidecar SHALL replace the existing ADOT sidecar (unified metrics + logs)
3. THE Alloy_Sidecar SHALL collect logs by tailing Docker JSON log files via `loki.source.docker`
4. THE Alloy_Sidecar SHALL mount `/var/lib/docker/containers` to access container logs
5. THE Alloy_Sidecar SHALL forward logs to Loki via `loki.write` component
6. THE Alloy_Sidecar SHALL forward metrics to AMP via `prometheus.remote_write` component
7. THE Alloy_Sidecar SHALL preserve JSON structured logging format
8. THE Alloy_Sidecar SHALL add labels for service name, task ID, and container name
9. THE Alloy_Sidecar SHALL use ARM64 image for Graviton compatibility
10. THE Alloy_Sidecar SHALL buffer logs locally to handle Loki unavailability
11. THE Alloy_Sidecar SHALL be non-essential (task continues if sidecar fails)
12. THE Alloy_Configuration SHALL be stored in SSM Parameter Store (similar to current ADOT config)

### Requirement 4: Grafana Integration

**User Story:** As an operator, I want to query Loki logs from Grafana, so that I have a unified observability interface.

#### Acceptance Criteria

1. THE Grafana_Service SHALL have Loki configured as a datasource
2. THE Loki_Datasource SHALL use Service Connect DNS name for connectivity
3. THE Grafana_Provisioning SHALL include the Loki datasource configuration
4. THE Grafana_Image SHALL be updated to include Loki datasource provisioning
5. THE Operator SHALL be able to query logs using LogQL in Grafana Explore

### Requirement 5: Log Retention and Lifecycle

**User Story:** As an operator, I want configurable log retention, so that I can balance storage costs with debugging needs.

#### Acceptance Criteria

1. THE Loki_Service SHALL support configurable retention period
2. THE Retention_Period SHALL be configurable via environment variable (default: 7 days)
3. THE Loki_Compactor SHALL run to enforce retention and compact chunks
4. THE S3_Lifecycle_Policy SHALL delete objects older than retention period as backup
5. THE Retention_Configuration SHALL match the existing CloudWatch retention variable

### Requirement 6: Security and Network Isolation

**User Story:** As an operator, I want Loki to run in private subnets with no public access, so that logs are secure.

#### Acceptance Criteria

1. THE Loki_Service SHALL run in private subnets only
2. THE Loki_Service SHALL NOT have a public IP address
3. THE Loki_Security_Group SHALL only allow ingress from ECS instances
4. THE Loki_Security_Group SHALL allow ingress from Grafana security group
5. THE S3_Access SHALL use the existing S3 gateway endpoint (no internet)
6. THE Loki_Service SHALL use IAM roles for S3 access (no static credentials)

### Requirement 7: High Availability (Optional)

**User Story:** As an operator, I want the option to run Loki in HA mode, so that log ingestion continues during failures.

#### Acceptance Criteria

1. THE Loki_Service SHALL support single-replica mode for development (default)
2. THE Loki_Service SHALL support multi-replica mode for production (optional)
3. WHEN running multiple replicas, THE Loki_Service SHALL use memberlist for coordination
4. WHEN running multiple replicas, THE Loki_Service SHALL use shared S3 storage
5. THE HA_Mode SHALL be configurable via Terraform variable

### Requirement 8: Migration Path

**User Story:** As an operator, I want a clear migration path from CloudWatch Logs to Loki, so that I can transition without losing logs.

#### Acceptance Criteria

1. THE Migration SHALL support running both CloudWatch and Loki in parallel
2. THE Migration SHALL allow gradual rollout (one service at a time)
3. THE CloudWatch_Log_Groups SHALL remain until migration is complete
4. THE Migration_Documentation SHALL include rollback procedures
5. THE Implementation SHALL NOT remove CloudWatch Logs resources automatically

### Requirement 9: Observability for Loki

**User Story:** As an operator, I want metrics for Loki operations, so that I can monitor log ingestion health.

#### Acceptance Criteria

1. THE Loki_Service SHALL expose Prometheus metrics on port 3100 at `/metrics`
2. THE ADOT_Sidecar SHALL scrape Loki metrics and send to AMP
3. THE Metrics SHALL include ingestion rate, query latency, and storage usage
4. THE Grafana_Dashboard SHALL include a Loki health panel (optional)

### Requirement 10: Cost Optimization

**User Story:** As an operator, I want to minimize Loki operational costs, so that the solution is cheaper than CloudWatch.

#### Acceptance Criteria

1. THE Loki_Service SHALL use minimal resources (256 CPU, 512 MB memory for dev)
2. THE S3_Bucket SHALL use Intelligent-Tiering or Standard storage class
3. THE Loki_Configuration SHALL use appropriate chunk sizes to minimize S3 requests
4. THE Implementation SHALL NOT require DynamoDB (use S3-only TSDB mode)
5. THE Cost_Comparison SHALL show >50% savings vs CloudWatch Logs

## Non-Functional Requirements

### Performance

1. THE Loki_Service SHALL handle log ingestion from 20+ containers
2. THE Log_Latency SHALL be under 5 seconds from generation to queryable
3. THE Query_Performance SHALL return results in under 10 seconds for 7-day range

### Reliability

1. THE Fluent_Bit_Sidecar SHALL buffer logs during Loki unavailability
2. THE Loki_Service SHALL recover gracefully after restarts
3. THE S3_Storage SHALL provide 99.999999999% durability

### Scalability

1. THE Loki_Service SHALL handle 10 MB/s log ingestion rate
2. THE S3_Storage SHALL scale automatically with log volume
3. THE Solution SHALL support future migration to microservices mode if needed

## Cost Analysis

### Current CloudWatch Logs Costs (Estimated)

| Component | Volume | Unit Cost | Monthly Cost |
|-----------|--------|-----------|--------------|
| Ingestion | 50 GB/month | $0.50/GB | $25.00 |
| Storage | 50 GB × 7 days avg | $0.03/GB | $1.50 |
| Queries | 100 GB scanned | $0.005/GB | $0.50 |
| **Total** | | | **~$27/month** |

### Proposed Loki + S3 Costs (Estimated)

| Component | Volume | Unit Cost | Monthly Cost |
|-----------|--------|-----------|--------------|
| S3 Storage | 50 GB/month | $0.023/GB | $1.15 |
| S3 PUT Requests | 500K requests | $0.005/1K | $2.50 |
| S3 GET Requests | 100K requests | $0.0004/1K | $0.04 |
| ECS Task (Loki) | 256 CPU, 512 MB | ~$5/month | $5.00 |
| **Total** | | | **~$9/month** |

### Savings

- **Monthly Savings**: ~$18/month (67% reduction)
- **At Scale**: Savings increase with log volume (CloudWatch scales linearly, S3 is cheaper)

## Open Questions

1. ~~**Log Format**: Should logs be stored as JSON or plain text?~~ **Resolved: JSON structured logging**

2. ~~**Retention Alignment**: Should Loki retention match CloudWatch retention exactly?~~ **Resolved: Not a major concern for benchmarking use case**

3. ~~**HA Requirements**: Is single-replica Loki acceptable for development?~~ **Resolved: Single-replica is acceptable**

4. ~~**Existing Logs**: Should we migrate existing CloudWatch logs to Loki?~~ **Resolved: No migration needed, start fresh**

5. ~~**ADOT Migration Timing**: Should we migrate ADOT to Alloy immediately?~~ **Resolved: Immediate migration, deployment expected first week of Feb**

6. ~~**Log Collection Method**: Should Alloy use Docker log driver integration or file tailing?~~ **Resolved: Docker log driver tailing (Option A)**
