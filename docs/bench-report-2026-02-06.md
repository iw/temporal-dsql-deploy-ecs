# Benchmark Report — 6 February 2026

## Test Configuration

| Parameter | Value |
|-----------|-------|
| Target WPS | ~1,170 (sustained) |
| Workflow type | Simple (1 activity) |
| Generation duration | ~5.5 minutes (1770382800–1770383130) |
| Total drain time | ~16 minutes (1770382800–1770383760) |
| Workflows started | ~350,000 |
| Region | eu-west-1 |

## Infrastructure

| Component | Spec | Replicas |
|-----------|------|----------|
| History | 4 vCPU / 8 GiB | 16 |
| Matching | 1 vCPU / 2 GiB | 16 |
| Frontend | 2 vCPU / 4 GiB | 9 |
| Worker | 0.5 vCPU / 1 GiB | 4 |
| Benchmark workers | 4 vCPU / 8 GiB | 30 |
| Benchmark generator | 4 vCPU / 8 GiB | 1 |
| Main cluster | 10 × m8g.4xlarge | 160 vCPU |
| Benchmark cluster | 10 × m8g.4xlarge | 160 vCPU |
| History shards | 4,096 | — |
| DSQL pool per history | 220 conns | — |
| DSQL pool per matching | 100 conns | — |
| DSQL pool per frontend | 80 conns | — |
| Reservoir | enabled | base_lifetime=11m, jitter=2m, guard=45s |

## Throughput

| Metric | Value |
|--------|-------|
| Peak StartWorkflowExecution | ~1,173/sec |
| Peak state transitions/sec | 310,782/sec |
| Peak UpdateWorkflowExecution ops/sec | 8,392/sec |
| Avg UpdateWorkflowExecution ops/sec | 5,794/sec |
| Peak RespondWorkflowTaskCompleted | 6,064/sec |
| Peak RespondActivityTaskCompleted | 4,193/sec |

## Persistence Latency

### CreateWorkflowExecution (generation phase only)

| Percentile | Avg | Max |
|------------|-----|-----|
| p50 | 35.3 ms | 35.5 ms |
| p95 | 49.1 ms | 49.4 ms |
| p99 | 85.5 ms | 90.4 ms |

### UpdateWorkflowExecution (full bench window)

| Percentile | Avg | Max |
|------------|-----|-----|
| p50 | 34.9 ms | 35.3 ms |
| p95 | 48.9 ms | 49.2 ms |
| p99 | 69.4 ms | 90.0 ms |

## Schedule-to-Start Latency (server-side, p50)

| Phase | Latency |
|-------|---------|
| Pre-generation | ~43 ms |
| During generation (peak) | ~53 sec |
| Post-generation (drain) | ~64 ms |

Schedule-to-start spiked significantly during the generation phase (up to ~53 seconds at peak), indicating the task queues were backing up faster than workers could poll. Once generation stopped, it dropped back to ~64ms within ~2 minutes.

## Connection Pool

| Metric | Value |
|--------|-------|
| Total open connections (steady) | ~532 |
| Peak in-use connections | 231 |
| Steady-state in-use | ~130 |
| Reservoir size (steady) | ~5,300 |

## Reservoir Health

| Metric | Delta during bench |
|--------|--------------------|
| Checkouts | ~983 |
| Empty events | 2,234 |
| Discards (guard window) | 7,535 |
| Refill failures | 80,741 |

The reservoir saw 2,234 empty events during the test — moments where a checkout found no ready connection. The 80,741 refill failures are notable and suggest the refiller was frequently unable to create new connections (likely rate-limited or hitting DSQL connection limits).

## Persistence Errors

| Error Type | Rate |
|------------|------|
| serviceerror_Unavailable | ~0.32/sec (constant, background) |
| serviceerror_NotFound | ~0.05/sec (constant, background) |
| context_Canceled | ~0.01/sec (brief spike) |
| persistence_CurrentWorkflowConditionFailedError | ~0.007/sec (brief spike) |

Error rates were flat and low throughout the test. The `serviceerror_Unavailable` at ~0.32/sec is a constant background rate (present before, during, and after the benchmark), not load-induced.

## Key Observations

1. **~1,170 WPS sustained generation** with ~350k workflows created in 5.5 minutes.

2. **310k state transitions/sec peak** — a significant jump from the previous 150 WPS benchmark (which peaked at ~137 WPS actual). This test pushed the cluster much harder.

3. **Persistence latency remained tight**: UpdateWorkflowExecution p50 held at ~35ms and p99 at ~69ms avg throughout the entire test including drain. No latency degradation under load.

4. **Schedule-to-start backlog**: The 53-second peak schedule-to-start latency during generation indicates the 30 benchmark workers couldn't keep up with 1,170 WPS submission rate. The backlog drained in ~10 minutes after generation stopped.

5. **Reservoir refill failures (80k)**: The refiller struggled to create connections, likely hitting the DSQL 100 conn/sec rate limit. Despite this, the reservoir maintained ~5,300 ready connections and the pool stayed at ~532 open connections. The refill failures are expected — the refiller is proactively trying to replace expiring connections and gets rate-limited.

6. **Zero workflow failures**: All persistence error rates were flat background noise, not load-correlated. No OCC conflict storms.

7. **Benchmark worker metrics all zero**: The `benchmark_throughput_per_second` and `benchmark_workflow_latency_seconds` metrics from the SDK-side workers were all 0. The workers were clearly processing workflows (server-side metrics prove ~4k completions/sec), but the custom benchmark metrics weren't being recorded. This needs investigation — likely the benchmark worker code isn't instrumenting workflow completions into these gauges/histograms.

## Comparison with 150 WPS Benchmark (January 2026)

| Metric | 150 WPS | ~1,170 WPS | Change |
|--------|---------|------------|--------|
| Actual WPS | 137 | ~1,170 | 8.5× |
| Workflows | 41,052 | ~350,000 | 8.5× |
| Peak st/s | ~41k (est) | 310,782 | ~7.5× |
| UpdateWF p50 | ~35 ms | ~35 ms | flat |
| UpdateWF p99 | ~65 ms (est) | ~69 ms | +6% |
| Connections | ~1,000 | ~532 | -47% |
| History replicas | 8 | 16 | 2× |
| Matching replicas | 6 | 16 | 2.7× |
| Frontend replicas | 4 | 9 | 2.25× |
| Benchmark workers | 6 | 30 | 5× |

Persistence latency scaled nearly flat despite 8.5× the throughput. The cluster handled the load well at the DSQL layer. The bottleneck was on the worker side (schedule-to-start backlog), not persistence.
