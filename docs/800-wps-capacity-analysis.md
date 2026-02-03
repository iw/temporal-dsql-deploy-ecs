# 800 WPS Benchmark Configuration

**Date**: February 2, 2026  
**Constraint**: 384 vCPU quota (HARD LIMIT)  
**Target**: 800 workflows per second

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        BENCHMARK ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐      gRPC       ┌─────────────┐                       │
│  │  Benchmark  │ ───────────────▶│  Frontend   │                       │
│  │  Generator  │                 │  (9 tasks)  │                       │
│  └─────────────┘                 └──────┬──────┘                       │
│                                         │                               │
│  ┌─────────────┐      gRPC              │ gRPC                         │
│  │  Benchmark  │ ───────────────────────┤                               │
│  │  Workers    │                        │                               │
│  │  (30 tasks) │                        ▼                               │
│  └─────────────┘                 ┌─────────────┐      ┌─────────────┐  │
│                                  │   History   │─────▶│    DSQL     │  │
│  SDK Clients only!               │  Matching   │      │ (Persistence)│  │
│  NO DSQL connection              │   Worker    │      └─────────────┘  │
│                                  └─────────────┘                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key Point**: Benchmark generator and workers are Temporal SDK clients. They communicate ONLY with Frontend via gRPC. They do NOT connect to DSQL.

---

## Resource Summary

| Cluster | Instances | Instance vCPU | Task vCPU | DSQL Connections |
|---------|-----------|---------------|-----------|------------------|
| Main | 10 × m8g.4xlarge | 160 | 100.5 | 8,250 |
| Benchmark | 10 × m8g.4xlarge | 160 | 124 | 0* |
| **Total** | **20** | **320** | **224.5** | **8,250** |

*Benchmark workers connect via Temporal Frontend (gRPC), not directly to DSQL.

**Instance vCPU Utilization**: 320 / 384 = **83.3%** (16.7% headroom)

---

## Main Cluster Configuration

**Infrastructure**: 10 × m8g.4xlarge (160 vCPU, 640 GB RAM, 80 ENIs)

| Service | Replicas | CPU | Memory | Conns/Replica | Total Conns |
|---------|----------|-----|--------|---------------|-------------|
| History | 16 | 4096 | 8192 | 300 | 4,800 |
| Matching | 16 | 1024 | 2048 | 150 | 2,400 |
| Frontend | 9 | 2048 | 4096 | 100 | 900 |
| Worker | 3 | 512 | 1024 | 50 | 150 |
| UI | 1 | 256 | 512 | - | - |
| Grafana | 1 | 256 | 512 | - | - |
| Loki | 1 | 512 | 1024 | - | - |
| **Total** | **47** | **102,912** | **205,824** | - | **8,250** |

---

## Benchmark Cluster Configuration

**Infrastructure**: 10 × m8g.4xlarge (160 vCPU, 640 GB RAM, 80 ENIs)

| Service | Replicas | CPU | Memory | Concurrency |
|---------|----------|-----|--------|-------------|
| Generator | 1 | 4096 | 8192 | - |
| Workers | 30 | 4096 | 8192 | 600 WFT, 600 Activity |
| **Total** | **31** | **126,976** | **253,952** | - |

### Worker SDK Configuration

```go
MaxConcurrentWorkflowTaskExecutionSize: 600
MaxConcurrentActivityExecutionSize: 600
MaxConcurrentWorkflowTaskPollers: 64
MaxConcurrentActivityTaskPollers: 64
MaxConcurrentEagerActivityExecutionSize: 200
DisableEagerActivities: false
StickyScheduleToStartTimeout: 5s
```

---

## DSQL Connection Pool Configuration

**Total**: 8,250 connections (82.5% of 10,000 limit)

### Per-Service Settings

| Service | Replicas | Conns/Replica | Total | Rationale |
|---------|----------|---------------|-------|-----------|
| History | 16 | 300 | 4,800 | Primary persistence, OCC retries |
| Matching | 16 | 150 | 2,400 | Task queue operations |
| Frontend | 9 | 100 | 900 | API gateway (light DB usage) |
| Worker | 3 | 50 | 150 | System workflows |

### Environment Variables

```bash
# History Service
TEMPORAL_SQL_MAX_CONNS=300
TEMPORAL_SQL_MAX_IDLE_CONNS=300
DSQL_RESERVOIR_TARGET_READY=300

# Matching Service
TEMPORAL_SQL_MAX_CONNS=150
TEMPORAL_SQL_MAX_IDLE_CONNS=150
DSQL_RESERVOIR_TARGET_READY=150

# Frontend Service
TEMPORAL_SQL_MAX_CONNS=100
TEMPORAL_SQL_MAX_IDLE_CONNS=100
DSQL_RESERVOIR_TARGET_READY=100

# Worker Service
TEMPORAL_SQL_MAX_CONNS=50
TEMPORAL_SQL_MAX_IDLE_CONNS=50
DSQL_RESERVOIR_TARGET_READY=50
```

### Connection Lifecycle

- **Reservoir warmup**: ~83 seconds (staggered across services)
- **Connection lifetime**: 55 minutes (under DSQL 60-min limit)
- **Expiry rate**: ~2.5 connections/second (well under 100/sec limit)

---

## Temporal Server Tuning (Dynamic Config)

```yaml
# dynamicconfig/bench-800wps.yaml

# History - Increase batch sizes
history.transferTaskBatchSize: 200
history.timerTaskBatchSize: 200
history.replicationTaskBatchSize: 200

# Matching - Increase partitions
matching.numTaskqueueReadPartitions: 16
matching.numTaskqueueWritePartitions: 16
matching.forwarderMaxOutstandingPolls: 10
matching.forwarderMaxOutstandingTasks: 10

# Frontend - Increase RPS limits
frontend.rps: 10000
frontend.namespaceRPS: 5000

# Enable eager execution
system.enableActivityEagerExecution: true
system.enableEagerWorkflowStart: true
```

---

## Terraform Variables

```hcl
# terraform.tfvars

# Main Cluster
ec2_instance_type  = "m8g.4xlarge"
ec2_instance_count = 10

# Temporal Services
temporal_history_count  = 16
temporal_matching_count = 16
temporal_frontend_count = 9
temporal_worker_count   = 3

# Connection Pools
dsql_history_max_conns  = 300
dsql_matching_max_conns = 150
dsql_frontend_max_conns = 100
dsql_worker_max_conns   = 50

# Benchmark
benchmark_enabled       = true
benchmark_cpu           = 4096
benchmark_memory        = 8192
benchmark_worker_cpu    = 4096
benchmark_worker_memory = 8192
benchmark_max_instances = 10
```

---

## Pre-Benchmark Checklist

- [ ] Update dynamic config with 800 WPS tuning
- [ ] Rebuild benchmark image with high concurrency settings
- [ ] Verify DSQL cluster health
- [ ] Clear stale workflows from previous benchmarks
- [ ] Ensure Grafana dashboards accessible
- [ ] Wait 2 minutes after service startup for reservoir warmup

---

## Monitoring

Key metrics to watch during benchmark:

| Metric | Purpose |
|--------|---------|
| `temporal_state_transition_count` | Forward progress |
| `temporal_history_backlog_age_seconds` | Backlog health |
| `dsql_query_latency_seconds` p99 | Database latency |
| `dsql_tx_conflict_total` | OCC conflicts |
| `temporal_worker_task_slots_available` | Worker capacity |
| `dsql_pool_in_use` | Connection utilization |
| `dsql_reservoir_size` | Reservoir health |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| DSQL OCC conflicts | High | Medium | Tune retry backoff |
| History backlog | High | High | Monitor backlog age |
| Worker saturation | Medium | High | Monitor slots available |
| Frontend throttling | Medium | Medium | Increase RPS limits |
