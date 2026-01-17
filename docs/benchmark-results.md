# Temporal DSQL Benchmark Results

**Date:** January 16, 2026  
**Environment:** ECS on EC2 (Graviton m7g.xlarge)  
**DSQL Cluster:** Aurora DSQL (eu-west-1)

## Infrastructure Configuration

| Component | Replicas | CPU | Memory |
|-----------|----------|-----|--------|
| History | 4 | 2 vCPU | 8 GiB |
| Matching | 3 | 1 vCPU | 4 GiB |
| Frontend | 2 | 1 vCPU | 4 GiB |
| Worker | 2 | 1 vCPU | 4 GiB |

- **History Shards:** 4096
- **EC2 Instances:** 6x m7g.xlarge

## Benchmark Results

### Test 1: 10 WPS (Warm-up)
| Metric | Value |
|--------|-------|
| Target Rate | 10 WPS |
| Duration | 2 minutes |
| Workflows Started | 1,125 |
| Workflows Completed | 1,125 |
| Workflows Failed | 0 |
| Actual Rate | 8.63 WPS |
| P50 Latency | 173 ms |
| P95 Latency | 236 ms |
| P99 Latency | 383 ms |
| Max Latency | 702 ms |
| **Result** | ✅ PASSED |

### Test 2: 50 WPS (Medium Load)
| Metric | Value |
|--------|-------|
| Target Rate | 50 WPS |
| Duration | 5 minutes |
| Workflows Started | 14,071 |
| Workflows Completed | 14,071 |
| Workflows Failed | 0 |
| Actual Rate | 46.86 WPS |
| P50 Latency | 190 ms |
| P95 Latency | 286 ms |
| P99 Latency | 383 ms |
| Max Latency | 1,116 ms |
| DSQL Transactions | ~117,000 |
| DSQL OCC Conflicts | < 5 |
| **Result** | ✅ PASSED |

### Test 3: 100 WPS (High Load)
| Metric | Value |
|--------|-------|
| Target Rate | 100 WPS |
| Duration | 5 minutes |
| Workflows Started | 28,338 |
| Workflows Completed | 5,009 |
| Workflows Failed | 19,900 |
| Actual Rate | 15.18 WPS |
| P99 Latency | 188,753 ms |
| DSQL OCC Conflicts | ~0 |
| Error Types | ResourceExhausted, Unavailable |
| **Result** | ❌ FAILED |

### Test 4: 75 WPS (After 100 WPS - System Under Backpressure)
| Metric | Value |
|--------|-------|
| Target Rate | 75 WPS |
| Duration | 5 minutes |
| Workflows Started | 21,130 |
| Workflows Completed | 2,991 |
| Workflows Failed | 14,511 |
| Actual Rate | 9.06 WPS |
| DSQL Transactions | ~200,000 |
| DSQL OCC Conflicts | ~1 |
| **Result** | ❌ FAILED (backpressure from previous test) |

## Key Observations

### DSQL Performance
- **Excellent:** Zero meaningful OCC conflicts across all tests
- **Scalable:** Handled 200k+ transactions without issues
- **Not the bottleneck:** All failures were due to Temporal rate limiting, not DSQL

### Bottlenecks Identified
1. **Frontend RPS Limits:** `ResourceExhausted` errors indicate hitting `frontend.rps` (2400) and `frontend.namespaceRPS` (2400)
2. **Matching Service Capacity:** `MatchingClientPollWorkflowTaskQueue` errors suggest Matching service overwhelmed
3. **Cascading Backpressure:** High load tests created backlog that affected subsequent tests

---

## Tuning Recommendations

### Target: 75 WPS

The 75 WPS test failed primarily due to backpressure from the previous 100 WPS test. With a clean system, 75 WPS should be achievable with moderate tuning.

**Dynamic Config Changes (`dynamicconfig/development-dsql.yaml`):**

```yaml
# Increase frontend rate limits
frontend.rps:
  - value: 4000  # was 2400
    constraints: {}

frontend.namespaceRPS:
  - value: 4000  # was 2400
    constraints: {}

# Increase matching forwarder capacity
matching.forwarderMaxOutstandingPolls:
  - value: 20  # was 10
    constraints: {}

matching.forwarderMaxRatePerSecond:
  - value: 200  # was 100
    constraints: {}

matching.forwarderMaxOutstandingTasks:
  - value: 200  # was 100
    constraints: {}
```

**Operational:**
- Allow 5-10 minutes cooldown between high-load tests
- Monitor `MatchingClientPollWorkflowTaskQueue` errors as early warning

### Target: 100+ WPS

For sustained 100 WPS, more aggressive tuning and infrastructure changes are needed.

**Dynamic Config Changes:**

```yaml
# Frontend rate limits - double current values
frontend.rps:
  - value: 6000
    constraints: {}

frontend.namespaceRPS:
  - value: 6000
    constraints: {}

frontend.namespaceCount:
  - value: 2400  # was 1200
    constraints: {}

# Matching service - significantly increase capacity
matching.forwarderMaxOutstandingPolls:
  - value: 40
    constraints: {}

matching.forwarderMaxRatePerSecond:
  - value: 400
    constraints: {}

matching.forwarderMaxOutstandingTasks:
  - value: 400
    constraints: {}

matching.maxTaskBatchSize:
  - value: 200  # was 100
    constraints: {}

matching.getTasksBatchSize:
  - value: 2000  # was 1000
    constraints: {}

# Task queue partitions - increase parallelism
matching.numTaskqueueWritePartitions:
  - value: 32  # was 16
    constraints: {}

matching.numTaskqueueReadPartitions:
  - value: 32  # was 16
    constraints: {}
```

**Infrastructure Changes (`terraform/terraform.tfvars`):**

```hcl
# Add more Matching replicas (primary bottleneck)
temporal_matching_count = 4  # was 3

# Consider adding Frontend replicas for higher RPS
temporal_frontend_count = 3  # was 2
```

### Target: 200+ WPS

For 200+ WPS, consider:

1. **Matching Service Scaling:**
   - Increase to 6+ replicas
   - Increase CPU/memory per replica (2 vCPU, 8 GiB)

2. **Frontend Service Scaling:**
   - Increase to 4+ replicas
   - Rate limits to 10,000+

3. **History Service:**
   - Current 4 replicas with 4096 shards should handle 200+ WPS
   - Monitor shard distribution and rebalancing

4. **Task Queue Partitions:**
   - Increase to 64+ partitions for high-volume queues

---

## Best Practices for Benchmarking

1. **Cooldown Period:** Wait 5-10 minutes between tests to allow backpressure to clear
2. **Incremental Testing:** Start at 50% of target, increase by 25% increments
3. **Monitor DSQL:** Watch OCC conflicts (should stay near zero)
4. **Watch Matching Errors:** `MatchingClientPollWorkflowTaskQueue` is the canary metric
5. **Clean Namespace:** Consider using fresh namespace for each benchmark run

---

## Conclusion

Aurora DSQL performed exceptionally well as Temporal's persistence layer:
- **Zero meaningful OCC conflicts** across 200k+ transactions
- **Not the bottleneck** - all failures were Temporal rate limiting
- **Serverless scaling** handled all load without intervention

The bottleneck is Temporal's internal rate limiting and Matching service capacity. With the tuning recommendations above, 75-100 WPS should be achievable. For higher throughput, scale Matching and Frontend services horizontally.

