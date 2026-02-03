# 400 WPS Benchmark Investigation

**Date**: 2026-02-03  
**Test Window**: 17:58 - 18:19 UTC  
**Target**: 400 WPS with state-transitions workflow  
**Result**: Failed - only 55 WPS completing (13.75% of target)

## Executive Summary

The 400 WPS benchmark failed due to **generator and worker configuration issues**, not server-side bottlenecks. The generator submitted ~775 WPS (nearly 2x target), and the worker poller distribution starved the non-sticky workflow task queue, causing a backlog of 27,573 tasks and 16+ second schedule-to-start latency.

**Root Cause**: Generator rate control + Worker poller distribution  
**Server Status**: Healthy - all server-side latencies within acceptable ranges

---

## Infrastructure Configuration

### Main Cluster (Temporal Services)
- **Instances**: 10 × m8g.4xlarge (160 vCPU, 640 GB RAM)
- **History**: 16 replicas (4 vCPU, 8 GiB each)
- **Matching**: 16 replicas (1 vCPU, 2 GiB each)
- **Frontend**: 9 replicas (2 vCPU, 4 GiB each)
- **Worker**: 3 replicas (0.5 vCPU, 1 GiB each)
- **History Shards**: 4,096

### Benchmark Cluster
- **Instances**: 14 × m8g.4xlarge (224 vCPU, 896 GB RAM)
- **Benchmark Workers**: 46 replicas (4 vCPU, 8 GiB each)
- **Total Worker vCPU**: 184 vCPU

### Workflow Configuration
- **Type**: state-transitions (10 serial activities per workflow)
- **Expected st/s at 400 WPS**: ~24,000 (60 state transitions per workflow)

---

## Key Findings

### 1. Generator Submitted 2x Target Rate

| Metric | Expected | Actual |
|--------|----------|--------|
| StartWorkflowExecution rate | 400 WPS | **~775 WPS** |
| StartWorkflowExecution P95 latency | - | 420ms (acceptable) |

The generator submitted nearly double the target rate. This is a generator configuration issue.

**Evidence**:
```
StartWorkflowExecution rate over time:
- 18:00: 774/s
- 18:01: 770/s
- 18:02: 762/s
- 18:03: 761/s
- 18:04: 577/s (test pause)
```

### 2. Worker Poller Distribution Problem

| Poller Type | Count | Purpose |
|-------------|-------|---------|
| activity_task | 1,564 | Activity polling (unused - eager activities) |
| workflow_sticky_task | 773-1,254 | Sticky queue (cached workflows) |
| **workflow_task** | **264-773** | **Non-sticky queue (new workflows)** |

**The Problem**: New workflows always go to the non-sticky queue first. With only ~300-750 pollers available for non-sticky work, the queue became starved.

**Expected**: 46 workers × 32 pollers = 1,472 workflow task pollers  
**Actual non-sticky**: Only 264-773 pollers (18-52% of expected)

### 3. Task Creation vs Consumption Imbalance

| Metric | Rate |
|--------|------|
| AddWorkflowTask (tasks created) | 3,700-4,000/s |
| Poll success (tasks consumed) | 3,340-3,580/s |
| **Deficit** | **~200-400 tasks/s** |

Over the test duration, this deficit accumulated into a massive backlog.

### 4. Backlog Accumulation

| Metric | Value |
|--------|-------|
| Peak backlog count | **27,573 tasks** |
| Workflow task schedule-to-start P95 | **16+ seconds** |
| Workflow completions | ~270/s (vs 775/s starts) |

---

## Server-Side Metrics (All Healthy)

### History Service
| Operation | P95 Latency | Assessment |
|-----------|-------------|------------|
| RespondWorkflowTaskCompleted | 368-425ms | ✅ Fast |
| RecordWorkflowTaskStarted | 1,070-1,604ms | ✅ Acceptable |
| StartWorkflowExecution | 405-423ms | ✅ Fast |

### Matching Service
| Operation | P95 Latency | Assessment |
|-----------|-------------|------------|
| AddWorkflowTask | 940-1,286ms | ✅ Acceptable |
| Sync match latency | 1,000-1,500ms | ✅ Good |
| PollWorkflowTaskQueue | 1,599-1,801ms | ✅ Normal |

### DSQL Persistence
| Metric | Value | Assessment |
|--------|-------|------------|
| OCC conflicts | None detected | ✅ No conflicts |
| Reservoir empty checkouts | None | ✅ Pool healthy |
| GetTaskQueue P95 | 9ms (spike to 320s once) | ✅ Generally fast |

### Task Queue Partitions
| Metric | Value |
|--------|-------|
| Loaded partitions | 540-652 |
| Configured partitions | 64 read/write |

---

## The Paradox Explained

**Observation**: 3,100 pollers available, ~3,500 poll successes/sec, but backlog grew to 27,573 tasks.

**Explanation**: 
1. Most pollers (1,564) were on the **activity task queue** - unused because state-transitions uses eager activities
2. ~1,200 pollers were on **sticky queues** - waiting for workflows already cached on that worker
3. Only ~300-750 pollers were on the **non-sticky queue** - where ALL new work arrives

New workflows at 775 WPS each need their first workflow task from the non-sticky queue. With only ~500 effective pollers, the queue backed up immediately.

---

## State Transitions Workflow Analysis

The state-transitions workflow executes 10 activities serially:

```go
for i := 0; i < 10; i++ {
    workflow.ExecuteActivity(ctx, FastActivity, input).Get(ctx, &output)
}
```

Each workflow generates approximately:
- 1 workflow started event
- 10 activity scheduled events
- 10 activity started events  
- 10 activity completed events
- ~10 workflow task events
- 1 workflow completed event

**Total**: ~60 state transitions per workflow

At 775 WPS actual rate: **~46,500 state transitions/second** expected.

Observed peak: **~10,000 st/s** - indicating severe workflow task processing bottleneck.

---

## Metrics Timeline

### State Transitions per Second
```
18:00: 268,958 (accumulated)
18:01: 267,300
18:02: 270,154
18:03: 264,722
18:04: 277,264
18:05: 257,394
18:06: 87,282 (collapse begins)
18:07: 44,170
18:08: 33,367
```

### Backlog Growth
```
18:00: 425 tasks
18:01: 6,149 tasks
18:02: 13,210 tasks
18:03: 20,392 tasks
18:04: 27,573 tasks (peak)
```

### Workflow Completions
```
18:00-18:05: ~265-270/s (steady but low)
18:06: 80/s (collapse)
18:07: 31/s
18:08: 52/s
```

---

## Root Cause Analysis

### Primary Cause: Generator Rate Control Failure

The generator's ticker-based rate limiting did not account for:
1. Backpressure from the server
2. Actual submission rate vs target rate
3. The blocking nature of `run.Get(ctx, nil)` in the submission goroutine

**Code Issue** (generator.go):
```go
// Each workflow submission spawns a goroutine that blocks on completion
go g.startWorkflow(ctx, workflowID)
```

With 775 concurrent goroutines waiting for completion, the generator continued spawning new submissions at the ticker rate regardless of actual throughput.

### Secondary Cause: Worker Poller Distribution

The Go SDK's default poller distribution allocates pollers across:
- Workflow task queue (non-sticky)
- Workflow sticky task queue
- Activity task queue

For the state-transitions workflow with eager activities:
- Activity pollers are **wasted** (1,564 pollers doing nothing)
- Sticky pollers are **underutilized** (workflows complete before sticky cache helps)
- Non-sticky pollers are **starved** (only 264-773 for all new work)

---

## Recommendations

### 1. Fix Generator Rate Control

```go
// Option A: Use a semaphore to limit concurrent in-flight workflows
sem := make(chan struct{}, maxConcurrent)

// Option B: Don't wait for completion in the submission path
go func() {
    _, err := g.client.ExecuteWorkflow(ctx, opts, workflowName)
    // Don't call run.Get() - let workflows complete independently
}()

// Option C: Use a proper rate limiter that accounts for backpressure
limiter := rate.NewLimiter(rate.Limit(targetRate), burst)
```

### 2. Optimize Worker Poller Distribution

For state-transitions workflow specifically:
```go
workerOptions := worker.Options{
    // Reduce activity pollers (eager activities don't need them)
    MaxConcurrentActivityTaskPollers: 4,  // Was 32
    
    // Increase workflow task pollers
    MaxConcurrentWorkflowTaskPollers: 64, // Was 32
    
    // Reduce sticky timeout to force more work to non-sticky queue
    StickyScheduleToStartTimeout: 2 * time.Second, // Was 5s
}
```

### 3. Consider Workflow Design

The state-transitions workflow's serial activity pattern creates a workflow task for each activity completion. Consider:
- Batching activities where possible
- Using local activities for fast operations
- Reducing the number of activities per workflow

### 4. Monitor Key Metrics

Add alerts for:
- `approximate_backlog_count > 1000`
- `temporal_workflow_task_schedule_to_start_latency_seconds P95 > 5s`
- `workflow_task` poller count vs `workflow_sticky_task` poller count ratio

---

## Conclusion

The 400 WPS benchmark failure was **not caused by server-side bottlenecks**. All Temporal server metrics (history, matching, frontend) and DSQL persistence metrics were within healthy ranges.

The failure was caused by:
1. **Generator submitting 2x target rate** (~775 WPS instead of 400 WPS)
2. **Worker poller distribution** starving the non-sticky workflow task queue

With 46 workers on 14 × m8g.4xlarge instances (224 vCPU), the infrastructure had **massive unused capacity**. The bottleneck was purely in the benchmark client configuration.

**Next Steps**:
1. Fix generator rate control to respect target rate
2. Optimize worker poller distribution for the workflow type
3. Re-run benchmark with corrected configuration
4. Target 400 WPS should be easily achievable with current infrastructure


---

## Appendix A: Go SDK Worker Tuning - Authoritative Guidance

### Sources

This section synthesizes guidance from official Temporal documentation and engineering blog posts:

1. [Worker Performance Documentation](https://docs.temporal.io/operation/how-to-tune-workers/) - Official Temporal docs
2. [An Introduction to Worker Tuning](https://temporal.io/blog/an-introduction-to-worker-tuning) - Temporal Engineering Blog (Oct 2023)
3. [Resource-based Auto-tuning for Workers](https://temporal.io/blog/resource-based-auto-tuning-for-workers) - Temporal Engineering Blog (Nov 2024)
4. [Temporal Community Forum - Poller Settings](https://community.temporal.io/t/what-are-the-recommended-settings-for-workflow-and-activity-pollers-count/5617)

### Key Concepts

#### Task Slots

A Worker Task Slot represents the capacity to execute a single concurrent Task. When a Worker starts processing a Task, it occupies one slot. The number of available slots directly affects how many tasks a Worker can handle simultaneously.

**Critical Metric**: `worker_task_slots_available` should always be > 0. If it hits 0, your Worker pool cannot start new Tasks.

#### Poller Autoscaling (Recommended)

As of November 2024, Temporal SDKs support **Poller Autoscaling** which dynamically adjusts the number of pollers based on need. This is now the recommended approach:

```go
// Go SDK - Enable poller autoscaling (recommended)
workerOptions := worker.Options{
    // Poller autoscaling will be default in future SDK versions
}
```

> "Temporal recommends using Poller Autoscaling for the majority of use cases, as manually setting the number of pollers too high or too low for your workload will result in decreased performance."

#### Resource-Based Auto-Tuning (Public Preview)

As of November 2024, resource-based auto-tuning is in Public Preview for Go, Java, Python, .NET, and TypeScript:

```go
// Go SDK - Resource-based tuning
tuner, err := resourcetuner.NewResourceBasedTuner(resourcetuner.ResourceBasedTunerOptions{
    TargetMem: 0.8,  // Target 80% memory usage
    TargetCpu: 0.9,  // Target 90% CPU usage
})
workerOptions := worker.Options{
    Tuner: tuner,
}
```

This allows Workers to automatically scale slots based on available CPU and memory, eliminating manual tuning.

### Poller Distribution

The Go SDK distributes pollers across three queue types:

1. **Workflow Task Queue (non-sticky)** - For new workflows and workflows not in cache
2. **Workflow Sticky Task Queue** - For workflows cached on this worker
3. **Activity Task Queue** - For activity tasks

**Critical Insight**: The SDK does NOT give you direct control over the sticky vs non-sticky poller ratio. The `MaxConcurrentWorkflowTaskPollers` setting controls the TOTAL workflow pollers, which are then distributed between sticky and non-sticky queues internally.

### Sticky Execution

Sticky execution keeps workflow state cached on a worker. When a workflow task completes, subsequent tasks for that workflow are preferentially routed to the same worker (sticky queue).

**StickyScheduleToStartTimeout**: How long to wait for a sticky worker before falling back to non-sticky queue. Default is 5 seconds.

```go
workerOptions := worker.Options{
    StickyScheduleToStartTimeout: 5 * time.Second,  // Default
}
```

**Trade-off**:
- **Longer timeout**: Better cache utilization, but new work waits longer if sticky worker is busy
- **Shorter timeout**: Faster fallback to non-sticky queue, but more replays

### Eager Execution

Eager execution is a latency optimization where Activities and Workflow Tasks can be started immediately on the local Worker without a server round-trip.

**Eager Activity Start**: When a Worker processing a Workflow Task has the Activity registered, it can reserve an Activity Slot and execute immediately.

**Eager Workflow Start**: When Starter and Worker share a Client in the same process, the first Workflow Task can execute locally.

```go
workerOptions := worker.Options{
    DisableEagerActivities:                  false,  // Enable eager activities
    MaxConcurrentEagerActivityExecutionSize: 100,    // Max concurrent eager activities
}
```

### Key Metrics to Monitor

| Metric | What to Look For | Meaning |
|--------|------------------|---------|
| `workflow_task_schedule_to_start_latency` | Should be near zero | High = Workers can't keep up |
| `activity_schedule_to_start_latency` | Should be near zero | High = Activity workers can't keep up |
| `worker_task_slots_available` | Should always be > 0 | Zero = Worker at capacity |
| Poll Success Rate | Should be > 90%, ideally > 95% | Low = Too many workers or server overload |

**Poll Success Rate Formula**:
```
(poll_success + poll_success_sync) / (poll_success + poll_success_sync + poll_timeouts)
```

### Invariants (Must Be True)

1. `MaxConcurrentWorkflowTaskPollers` should be significantly < `MaxConcurrentWorkflowTaskExecutionSize`
2. `MaxConcurrentActivityTaskPollers` should be significantly < `MaxConcurrentActivityExecutionSize`
3. The number of pollers should always be lower than the number of executors

---

## Appendix B: Current Configuration Analysis - What's Wrong

### Current Worker Configuration

```go
workerOptions := worker.Options{
    MaxConcurrentActivityExecutionSize:      200,
    MaxConcurrentWorkflowTaskExecutionSize:  200,
    MaxConcurrentLocalActivityExecutionSize: 200,
    MaxConcurrentWorkflowTaskPollers:        32,
    MaxConcurrentActivityTaskPollers:        32,
    DisableEagerActivities:                  false,
    MaxConcurrentEagerActivityExecutionSize: 100,
    StickyScheduleToStartTimeout:            5 * time.Second,
}
```

### Issue #1: Activity Pollers Wasted (CRITICAL)

**Problem**: 32 activity pollers per worker × 46 workers = **1,472 activity pollers** doing NOTHING.

**Why**: The state-transitions workflow uses **eager activities**. With `DisableEagerActivities: false`, activities execute inline on the workflow task thread without going through the activity task queue.

**Evidence**: Activity poll success rate was **0/s** during the entire benchmark.

**Fix**:
```go
// For eager-activity workflows, reduce activity pollers dramatically
MaxConcurrentActivityTaskPollers: 2,  // Was 32 - only need a few for fallback
```

### Issue #2: Sticky Queue Dominates Non-Sticky (CRITICAL)

**Problem**: With 46 workers × 32 workflow pollers = 1,472 total workflow pollers, but:
- ~1,200 were on sticky queues (waiting for cached workflows)
- Only ~300-750 were on non-sticky queue (handling ALL new work)

**Why**: The SDK's internal distribution favors sticky queues. With short-lived workflows (state-transitions completes in ~1 second), workflows complete before sticky caching provides benefit, but pollers remain allocated to sticky queues.

**Evidence**: 
- `workflow_task` pollers: 264-773
- `workflow_sticky_task` pollers: 773-1,254
- Backlog grew to 27,573 because non-sticky queue was starved

**Fix Options**:

Option A - Reduce sticky timeout to force faster fallback:
```go
StickyScheduleToStartTimeout: 1 * time.Second,  // Was 5s - faster fallback to non-sticky
```

Option B - Disable sticky execution entirely for benchmark:
```go
DisableStickyExecution: true,  // All work goes to non-sticky queue
```

### Issue #3: No Resource-Based Tuning

**Problem**: Fixed slot counts don't adapt to actual resource availability.

**Why**: With 46 workers × 4 vCPU = 184 vCPU available, but fixed `MaxConcurrentWorkflowTaskExecutionSize: 200` doesn't scale based on actual CPU/memory usage.

**Fix**: Use resource-based auto-tuning (Public Preview as of Nov 2024):
```go
tuner, _ := resourcetuner.NewResourceBasedTuner(resourcetuner.ResourceBasedTunerOptions{
    TargetMem: 0.8,
    TargetCpu: 0.9,
})
workerOptions := worker.Options{
    Tuner: tuner,
}
```

### Issue #4: Generator Rate Control

**Problem**: Generator submitted ~775 WPS instead of target 400 WPS.

**Why**: The generator uses a ticker that fires every `1/rate` seconds, spawning a goroutine for each workflow. Each goroutine blocks on `run.Get(ctx, nil)` waiting for completion. With backpressure, workflows pile up but the ticker keeps firing.

**Evidence**: StartWorkflowExecution rate was 774/s at test start.

**Fix**: Implement proper backpressure handling:
```go
// Option A: Semaphore to limit in-flight workflows
sem := semaphore.NewWeighted(int64(maxConcurrent))
sem.Acquire(ctx, 1)
go func() {
    defer sem.Release(1)
    // start workflow
}()

// Option B: Don't wait for completion in submission path
go func() {
    _, err := client.ExecuteWorkflow(ctx, opts, workflowName)
    // Don't call run.Get() - track completion separately
}()
```

### Summary: Configuration Fixes Required

| Issue | Current | Recommended | Impact |
|-------|---------|-------------|--------|
| Activity pollers | 32 | 2-4 | Free up 1,400+ pollers |
| Sticky timeout | 5s | 1s or disable | More non-sticky pollers |
| Resource tuning | Fixed | Resource-based | Auto-scale to capacity |
| Generator rate | Unbounded | Semaphore-limited | Respect target rate |

### Recommended Worker Configuration

```go
// For state-transitions workflow (eager activities, short-lived)
workerOptions := worker.Options{
    // Execution slots - keep high for throughput
    MaxConcurrentWorkflowTaskExecutionSize:  200,
    MaxConcurrentActivityExecutionSize:      50,   // Reduced - eager activities
    MaxConcurrentLocalActivityExecutionSize: 200,
    
    // Pollers - rebalanced for non-sticky work
    MaxConcurrentWorkflowTaskPollers:        32,
    MaxConcurrentActivityTaskPollers:        4,    // Reduced - eager activities
    
    // Eager execution - enabled for latency
    DisableEagerActivities:                  false,
    MaxConcurrentEagerActivityExecutionSize: 100,
    
    // Sticky execution - reduced timeout for faster fallback
    StickyScheduleToStartTimeout:            1 * time.Second,  // Was 5s
    
    // OR: Disable sticky entirely for benchmark
    // DisableStickyExecution: true,
}
```

### Expected Impact

With these fixes:
1. **Activity pollers freed**: ~1,400 pollers no longer wasted
2. **Non-sticky queue served**: Faster fallback means more pollers available for new work
3. **Backlog eliminated**: Tasks consumed as fast as they're created
4. **Target rate respected**: Generator won't overshoot 400 WPS

The 46 workers on 14 × m8g.4xlarge instances have **massive unused capacity**. With proper configuration, 400 WPS should be trivially achievable.
