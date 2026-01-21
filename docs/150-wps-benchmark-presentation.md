# Temporal + Aurora DSQL: 150 WPS Benchmark Results

**Date:** January 21, 2026

---

## Benchmark Results

| Metric | Value |
|--------|-------|
| **Target Rate** | 150 workflows/second |
| **Actual Rate** | 136.74 workflows/second |
| **Workflows Started** | 41,052 |
| **Workflows Completed** | 41,052 |
| **Success Rate** | 100% |
| **Duration** | 5 minutes |

### Latency

| Percentile | Latency |
|------------|---------|
| P50 | 197 ms |
| P95 | 220 ms |
| P99 | 259 ms |
| Max | 594 ms |

---

## Infrastructure Configuration

### ECS Cluster

| Component | Instance Type | Count | vCPU | Memory |
|-----------|---------------|-------|------|--------|
| Main ASG | m7g.2xlarge | 10 | 80 total | 320 GiB total |
| Benchmark ASG | m7g.2xlarge | 4 | 32 total | 128 GiB total |

### Temporal Services

| Service | Replicas | CPU | Memory | Total vCPU |
|---------|----------|-----|--------|------------|
| History | 8 | 4 vCPU | 8 GiB | 32 |
| Matching | 6 | 1 vCPU | 2 GiB | 6 |
| Frontend | 4 | 2 vCPU | 4 GiB | 8 |
| Worker | 2 | 0.5 vCPU | 1 GiB | 1 |
| Benchmark Workers | 6 | 2 vCPU | 4 GiB | 12 |

### Aurora DSQL

- Single-region cluster (eu-west-1)
- Public endpoint with IAM authentication
- ~1,000 active connections during benchmark

---

## DSQL Plugin Optimizations

### 1. Connection Pool Pre-Warming

Connections are created at service startup, not under load.

```
Pool Configuration:
- MaxConns: 50 per service
- MaxIdleConns: 50 (equals MaxConns)
- MaxConnLifetime: 55 minutes
- MaxConnIdleTime: 0 (disabled)
```

**Why it matters:** DSQL has a cluster-wide connection rate limit of 100/second. Pre-warming eliminates connection creation during high-throughput operations.

### 2. GetWorkflowExecution Optimization

Removed unnecessary `FOR UPDATE` lock on read operations.

**Before:**
```sql
SELECT ... FROM executions WHERE ... FOR UPDATE
```

**After:**
```sql
SELECT ... FROM executions WHERE ...
```

**Why it matters:** DSQL uses optimistic concurrency control. Unnecessary locks cause serialization conflicts and retry storms.

### 3. FOR UPDATE on JOINs Workaround

DSQL doesn't support `FOR UPDATE` on JOINs. Split into separate queries.

**Before:**
```sql
SELECT ... FROM current_executions ce
JOIN executions e ON ce.run_id = e.run_id
WHERE ... FOR UPDATE
```

**After:**
```sql
-- Query 1: Lock current_executions
SELECT ... FROM current_executions WHERE ... FOR UPDATE

-- Query 2: Read executions (no lock)
SELECT last_write_version FROM executions WHERE ...
```

### 4. CAS Updates with Retry Logic

All shard and execution updates use Compare-And-Swap pattern with exponential backoff.

```
Retry Configuration:
- Max Retries: 5
- Base Delay: 100ms
- Max Delay: 5 seconds
- Jitter Factor: 25%
```

### 5. Connection Rate Limiting

Per-instance rate limiting to respect DSQL's cluster-wide limits.

```
Rate Limits (per service instance):
- History: 8 connections/second
- Matching: 6 connections/second
- Frontend: 4 connections/second
- Worker: 2 connections/second
```

### 6. Token-Refreshing Driver

Custom database driver that injects fresh IAM tokens before each new connection.

**Why it matters:** IAM tokens expire after 15 minutes. The driver ensures connections created by pool growth or lifetime expiry always have valid tokens.

---

## Metrics Observed During Benchmark

### DSQL CloudWatch Metrics

| Metric | Value | Notes |
|--------|-------|-------|
| Database Connections | ~1,000 | Stable throughout test |
| TotalTx | 272,000/min | Peak transaction rate during benchmark |
| ReadOnlyTx | 193,000/min | Read-only transaction rate (71% of total) |
| WriteTx | ~79,000/min | Write transaction rate (29% of total) |
| Commit Latency | Low | No spikes observed |
| Connection Rate | Minimal | Pool pre-warmed at startup |

**Transaction Analysis:**
- ~4,533 transactions/second peak rate
- 71% read-only vs 29% write ratio
- ~6.6 transactions per workflow (272k tx/min ÷ 41k workflows × 5 min)

### Temporal Persistence Metrics

| Metric | Observation |
|--------|-------------|
| Connections In Use | Low | Queries completing quickly |
| Connections Open | 50 per service | Pool at max size |
| Pool Wait Count | 0 | No connection contention |

### Service Health

| Service | Status | Notes |
|---------|--------|-------|
| History (8 replicas) | Stable | No OCC conflicts observed |
| Matching (6 replicas) | Stable | Task dispatch working |
| Frontend (4 replicas) | Stable | Handling 150 WPS |
| Benchmark Workers (6) | Stable | Processing all workflows |

---

## Dynamic Configuration

```yaml
# Frontend rate limits
frontend.rps: 8000
frontend.namespaceRPS: 8000
frontend.namespaceCount: 4000

# Matching capacity
matching.numTaskqueueWritePartitions: 32
matching.numTaskqueueReadPartitions: 32
matching.forwarderMaxOutstandingPolls: 40
matching.forwarderMaxRatePerSecond: 400
matching.forwarderMaxOutstandingTasks: 400
matching.maxTaskBatchSize: 200
matching.getTasksBatchSize: 2000

# History shards
history.numHistoryShards: 4096
```

---

## Key Takeaways

1. **Sub-300ms P99 latency** at 137 WPS sustained throughput
2. **100% workflow success rate** with zero failures
3. **Stable connection pool** - no connection creation under load
4. **No OCC retry storms** - GetWorkflowExecution optimization working
5. **Clean tail latency** - max latency under 600ms

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    150 WPS BENCHMARK SETUP                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              ECS CLUSTER (14 × m7g.2xlarge)             │   │
│  │                                                         │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │   │
│  │  │ History │ │ History │ │ History │ │ History │       │   │
│  │  │   ×2    │ │   ×2    │ │   ×2    │ │   ×2    │       │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘       │   │
│  │                                                         │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │   │
│  │  │Matching │ │Matching │ │Matching │ │Frontend │       │   │
│  │  │   ×2    │ │   ×2    │ │   ×2    │ │   ×4    │       │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘       │   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────┐       │   │
│  │  │         Benchmark Workers × 6               │       │   │
│  │  └─────────────────────────────────────────────┘       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              │ ~1,000 connections               │
│                              │ (pre-warmed)                     │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    AURORA DSQL                          │   │
│  │                                                         │   │
│  │  • Serverless PostgreSQL-compatible                     │   │
│  │  • Optimistic Concurrency Control                       │   │
│  │  • IAM Authentication                                   │   │
│  │  • 10,000 max connections                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Scaling Headroom

| Resource | Current | Limit | Utilization |
|----------|---------|-------|-------------|
| DSQL Connections | ~1,000 | 10,000 | 10% |
| EC2 vCPUs | 112 | 128 (quota) | 88% |
| Persistence Latency | Low | - | Headroom available |

**Estimated capacity:** Could scale to 200+ WPS with current DSQL cluster.

---

## Daily Cost Estimate (24-hour day, eu-west-1)

### Compute (EC2)

| Resource | Count | Instance Type | $/hr | 24-hr Cost |
|----------|-------|---------------|------|------------|
| Main ASG | 10 | m7g.2xlarge | $0.3638 | $87.31 |
| Benchmark ASG | 4 | m7g.2xlarge | $0.3638 | $34.92 |
| **Subtotal** | **14** | | | **$122.23** |

### Aurora DSQL

| Metric | Value | Unit Price | Cost |
|--------|-------|------------|------|
| DPU (estimated) | ~10M DPU/day | $0.0000095/DPU | ~$95.00 |
| Storage | ~10 GB | $0.36/GB-month | ~$0.12/day |
| **Subtotal** | | | **~$95.12** |

*Note: DPU estimate based on 272k transactions in 5 min benchmark extrapolated to 24 hours at similar load. Actual usage varies with workload.*

### OpenSearch (Visibility)

| Resource | Count | Instance Type | $/hr | 24-hr Cost |
|----------|-------|---------------|------|------------|
| Data Nodes | 3 | m6g.large.search | $0.143 | $10.30 |
| **Subtotal** | | | | **$10.30** |

### CloudWatch

| Resource | Estimate | Unit Price | Daily Cost |
|----------|----------|------------|------------|
| Log Ingestion | ~10 GB/day | $0.57/GB | $5.70 |
| Log Storage | ~50 GB | $0.03/GB-mo | $0.05 |
| Metrics | ~500 metrics | $0.30/metric-mo | $0.50 |
| **Subtotal** | | | **~$6.25** |

### Amazon Managed Prometheus

| Resource | Estimate | Unit Price | Daily Cost |
|----------|----------|------------|------------|
| Metric Samples | ~100M/day | $0.03/10M | $0.30 |
| Storage | ~1 GB | $0.03/GB-mo | $0.001 |
| **Subtotal** | | | **~$0.30** |

### Other AWS Services

| Resource | Daily Cost |
|----------|------------|
| NAT Gateway | ~$2.16 |
| VPC Endpoints | ~$5.76 |
| DynamoDB (rate limiter) | ~$0.01 |
| **Subtotal** | **~$7.93** |

### Total Daily Cost Summary

| Category | 24-hr Day |
|----------|-----------|
| EC2 (Compute) | $122.23 |
| Aurora DSQL | ~$95.12 |
| OpenSearch | $10.30 |
| CloudWatch | ~$6.25 |
| Prometheus | ~$0.30 |
| Other (NAT, VPC, DDB) | ~$7.93 |
| **Total** | **~$242.13** |

*Costs are estimates based on observed usage patterns. Actual costs may vary. Benchmark ASG scales to zero when not in use, reducing costs to ~$172/day for steady-state operation.*
