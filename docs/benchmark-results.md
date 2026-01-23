# Temporal DSQL Benchmark Results

## Test Configuration

### Infrastructure
- **Main Cluster**: 10 × m8g.4xlarge (160 vCPU)
- **Benchmark Cluster**: 13 × m8g.4xlarge (208 vCPU)
- **Total**: 368 vCPU (384 quota, 12 vCPU headroom)

### Service Configuration (400 WPS)

| Service | Replicas | CPU | Memory | Total vCPU |
|---------|----------|-----|--------|------------|
| History | 16 | 4 vCPU | 8 GiB | 64 |
| Matching | 16 | 1 vCPU | 2 GiB | 16 |
| Frontend | 9 | 2 vCPU | 4 GiB | 18 |
| Worker | 3 | 0.5 vCPU | 1 GiB | 1.5 |
| UI | 1 | 0.25 vCPU | 512 MiB | 0.25 |
| Grafana | 1 | 0.25 vCPU | 512 MiB | 0.25 |
| ADOT | 1 | 0.5 vCPU | 1 GiB | 0.5 |

### Benchmark Workers

| Setting | Value |
|---------|-------|
| Workers | 51 |
| CPU per worker | 4 vCPU |
| Memory per worker | 4 GiB |
| MaxConcurrentWorkflowTaskPollers | 32 |
| MaxConcurrentActivityTaskPollers | 32 |
| MaxConcurrentWorkflowTaskExecutionSize | 200 |
| MaxConcurrentActivityExecutionSize | 200 |
| Total pollers | 1,632 |

### DSQL Connection Pool

| Setting | Value |
|---------|-------|
| MaxConns | 500 |
| MaxIdleConns | 500 |
| MaxConnLifetime | 55m |
| MaxConnIdleTime | 0 (disabled) |

## Benchmark Profile

| Parameter | Value |
|-----------|-------|
| Workflow Type | StateTransitionWorkflow |
| State Transitions per Workflow | 15 |
| Target Rate | 400 WPS |
| Duration | 5 minutes |
| Namespace | benchmark |

## Results (2026-01-23)

### Summary

| Metric | Value |
|--------|-------|
| Workflows Started | 111,696 |
| Workflows Completed | 111,692 |
| Success Rate | 99.996% |
| Start Rate | 372 WPS (93% of target) |
| Peak Completion Rate | 323 WPS |
| Peak State Transitions | 10,600 st/s |

### Throughput (15:05 - 15:15 UTC)

| Time | Completion Rate | State Transitions |
|------|-----------------|-------------------|
| 15:05:30 | 84 WPS | 4,100 st/s |
| 15:06:30 | 315 WPS | 10,600 st/s |
| 15:07:00 | 318 WPS | 10,500 st/s |
| 15:07:40 | **323 WPS** | 10,200 st/s |
| 15:08:00 | 294 WPS | 9,800 st/s |
| 15:09:00 | 128 WPS | 2,800 st/s |

### Server Metrics

| Metric | Value |
|--------|-------|
| History Pool Max In-Use | 336 / 500 |
| History Pool Waits | 122,442 total |
| AddWorkflowTask Errors | ~150-200/s sustained |

## Analysis

### What Worked
- **Workers not the bottleneck**: 51 workers with 1,632 pollers had spare capacity
- **Near-perfect completion**: 99.996% of workflows completed successfully
- **Stable throughput**: Sustained 300+ WPS for several minutes

### Bottlenecks Identified
1. **AddWorkflowTask errors**: ~150-200/s indicates server-side contention
2. **History pool waits**: 122k waits despite pool not being exhausted (336/500)
3. **Start rate limited**: Generator achieved 372 WPS vs 400 target due to backpressure

### Key Observations
- Pool wasn't exhausted but still had significant wait times
- Uneven shard distribution may be causing hot spots on some history replicas
- The gap between start rate (372) and peak completion rate (323) indicates processing lag

## Next Steps

1. **Investigate AddWorkflowTask errors**: Root cause of ~150-200/s error rate
2. **Shard distribution analysis**: Check if load is evenly distributed across history replicas
3. **Pool wait analysis**: Understand why waits occur when pool isn't exhausted
4. **Test with higher history replica count**: May help distribute shard load
5. **DSQL query analysis**: Profile slow queries during peak load


## Daily Cost Estimate (24hr)

All prices are On-Demand for eu-west-1.

### Compute (EC2)

| Resource | Instances | $/hr | Daily Cost |
|----------|-----------|------|------------|
| m8g.4xlarge (main cluster) | 10 | $0.80 | $192.08 |
| m8g.4xlarge (benchmark cluster) | 13 | $0.80 | $249.70 |
| **EC2 Total** | **23** | | **$441.78** |

### Networking

| Resource | Units | $/unit | Daily Cost |
|----------|-------|--------|------------|
| NAT Gateway | 1 | $0.048/hr | $1.15 |
| NAT Gateway Data | ~10 GB/day | $0.048/GB | $0.48 |
| **Networking Total** | | | **$1.63** |

### Database & Search

| Resource | Units | $/unit | Daily Cost |
|----------|-------|--------|------------|
| Aurora DSQL (DPU) | Variable | $0.0000095/DPU | ~$5-20* |
| Aurora DSQL Storage | ~10 GB | $0.36/GB-mo | $0.12 |
| OpenSearch (m6g.large.search) | 3 nodes | $0.143/hr | $10.30 |
| **Database Total** | | | **~$15-30** |

*DSQL cost varies with query volume. Estimate based on benchmark load.

### Observability

| Resource | Units | $/unit | Daily Cost |
|----------|-------|--------|------------|
| Amazon Managed Prometheus | ~100M samples/day | $0.90/10M | $9.00 |
| AMP Storage | ~1 GB | $0.03/GB-mo | $0.03 |
| CloudWatch Logs | ~5 GB/day | $0.57/GB | $2.85 |
| **Observability Total** | | | **$11.88** |

### Summary

| Category | Daily Cost |
|----------|------------|
| EC2 Compute | $441.78 |
| Networking | $1.63 |
| Database & Search | ~$20.00 |
| Observability | $11.88 |
| **Total** | **~$475/day** |

**Notes:**
- Costs assume 24hr operation at full scale (23 instances)
- DSQL costs are usage-based and vary with benchmark activity
- Scale down benchmark cluster when not testing to save ~$250/day
- Consider Reserved Instances for sustained workloads (30-40% savings)


## Raw Metrics Data (15:05-15:15 UTC)

Captured from Amazon Managed Prometheus before teardown.

Query parameters: `start=1769180700&end=1769181300&step=30s`

### Workflow Completion Rate (WPS)
```promql
sum(rate(workflow_success_total{namespace="benchmark"}[1m]))
```
```json
[[1769180700,"0"],[1769180730,"83.53"],[1769180760,"141.25"],[1769180790,"109.12"],[1769180820,"247.14"],[1769180850,"314.96"],[1769180880,"317.80"],[1769180910,"255.54"],[1769180940,"266.07"],[1769180970,"245.13"],[1769181000,"294.00"],[1769181030,"242.54"],[1769181060,"323.17"],[1769181090,"294.58"],[1769181120,"277.44"],[1769181150,"128.42"],[1769181180,"34.67"],[1769181210,"16.87"],[1769181240,"13.64"],[1769181270,"20.89"],[1769181300,"41.97"]]
```

### State Transitions (st/s)
```promql
sum(rate(state_transition_count_count{namespace="benchmark"}[1m]))
```
```json
[[1769180700,"1000"],[1769180730,"4110"],[1769180760,"6604"],[1769180790,"4998"],[1769180820,"8975"],[1769180850,"10602"],[1769180880,"10485"],[1769180910,"9773"],[1769180940,"9885"],[1769180970,"9171"],[1769181000,"9375"],[1769181030,"9285"],[1769181060,"10156"],[1769181090,"9765"],[1769181120,"6496"],[1769181150,"2762"],[1769181180,"889"],[1769181210,"649"],[1769181240,"604"],[1769181270,"606"],[1769181300,"504"]]
```

### History Pool In-Use (max across replicas)
```promql
max(dsql_pool_in_use{service_name=~"history.*"})
```
```json
[[1769180700,"209"],[1769180730,"55"],[1769180760,"153"],[1769180790,"151"],[1769180820,"48"],[1769180850,"46"],[1769180880,"106"],[1769180910,"188"],[1769180940,"199"],[1769180970,"205"],[1769181000,"336"],[1769181030,"212"],[1769181060,"183"],[1769181090,"221"],[1769181120,"70"],[1769181150,"47"],[1769181180,"31"],[1769181210,"39"],[1769181240,"22"],[1769181270,"98"],[1769181300,"12"]]
```

### History Pool Wait Total (cumulative)
```promql
sum(dsql_pool_wait_total{service_name=~"history.*"})
```
```json
[[1769180700,"64844"],[1769180730,"81773"],[1769180760,"81773"],[1769180790,"122442"],[1769180820,"122442"],[1769180850,"122442"],[1769180880,"122442"],[1769180910,"122442"],[1769180940,"122442"],[1769180970,"122442"],[1769181000,"122442"],[1769181030,"122442"],[1769181060,"122442"],[1769181090,"122442"],[1769181120,"122442"],[1769181150,"122442"],[1769181180,"122442"],[1769181210,"122442"],[1769181240,"122442"],[1769181270,"122442"],[1769181300,"122442"]]
```

### AddWorkflowTask Errors (rate/s)
```promql
sum(rate(service_errors_total{namespace="benchmark",operation="AddWorkflowTask"}[1m]))
```
```json
[[1769180700,"723"],[1769180730,"499"],[1769180760,"126"],[1769180790,"104"],[1769180820,"46"],[1769180850,"60"],[1769180880,"70"],[1769180910,"120"],[1769180940,"162"],[1769180970,"202"],[1769181000,"178"],[1769181030,"187"],[1769181060,"122"],[1769181090,"163"],[1769181120,"189"],[1769181150,"160"],[1769181180,"155"],[1769181210,"160"],[1769181240,"180"],[1769181270,"181"],[1769181300,"95"]]
```

### Totals
```promql
sum(workflow_success_total{namespace="benchmark"})
```
- **workflow_success_total**: 111,692
- **Test period**: 2026-01-23 15:05:00 - 15:15:00 UTC
- **Timestamps**: Unix epoch (1769180700 = 15:05:00 UTC)
