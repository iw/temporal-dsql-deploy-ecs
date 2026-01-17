# Design Document: Temporal DSQL Benchmark

## Overview

This design describes a benchmarking system for Temporal deployed on ECS with Aurora DSQL persistence. The benchmark system consists of a Go-based benchmark runner that executes configurable workflow patterns, collects metrics, and reports results. It runs on dedicated EC2 nodes to ensure isolation from Temporal services.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TEMPORAL BENCHMARK ARCHITECTURE                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    BENCHMARK NODES (Node D)                          │   │
│  │                    workload=benchmark                                │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │   │
│  │  │ Benchmark Runner│  │ Benchmark Runner│  │ Benchmark Runner│      │   │
│  │  │   (Worker 1)    │  │   (Worker 2)    │  │   (Worker N)    │      │   │
│  │  │   :9090 metrics │  │   :9090 metrics │  │   :9090 metrics │      │   │
│  │  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘      │   │
│  │           │                    │                    │               │   │
│  │           └────────────────────┼────────────────────┘               │   │
│  │                                │                                    │   │
│  └────────────────────────────────┼────────────────────────────────────┘   │
│                                   │ Service Connect                        │
│                                   ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    TEMPORAL SERVICES                                 │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌────────────────┐ │   │
│  │  │  Frontend   │ │   History   │ │  Matching   │ │     Worker     │ │   │
│  │  │   :7233     │ │    :7234    │ │    :7235    │ │     :7239      │ │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └────────────────┘ │   │
│  └─────────────────────────────────┬───────────────────────────────────┘   │
│                                    │                                       │
│         ┌──────────────────────────┼──────────────────────────┐            │
│         │                          │                          │            │
│         ▼                          ▼                          ▼            │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────┐    │
│  │  Aurora DSQL    │    │   OpenSearch    │    │  Amazon Managed     │    │
│  │  (Persistence)  │    │  (Visibility)   │    │    Prometheus       │    │
│  └─────────────────┘    └─────────────────┘    └─────────────────────┘    │
│                                                         ▲                  │
│                                                         │                  │
│  ┌─────────────────────────────────────────────────────┼───────────────┐  │
│  │                    ADOT Collector                    │               │  │
│  │  Scrapes metrics from:                               │               │  │
│  │  - Temporal services (:9090)                         │               │  │
│  │  - Benchmark runners (:9090)                         │               │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. Benchmark Runner (Go Application)

The benchmark runner is a Go application that uses the Temporal Go SDK to execute workflows and collect metrics.

```go
// BenchmarkConfig defines the benchmark parameters
type BenchmarkConfig struct {
    // Workflow configuration
    WorkflowType     string        // "simple", "multi-activity", "timer", "child-workflow"
    ActivityCount    int           // Number of activities (for multi-activity type)
    TimerDuration    time.Duration // Timer duration (for timer type)
    ChildCount       int           // Number of child workflows (for child-workflow type)
    
    // Load configuration
    TargetRate       float64       // Workflows per second
    Duration         time.Duration // Test duration
    RampUpDuration   time.Duration // Ramp-up period
    WorkerCount      int           // Number of parallel workers
    
    // Execution configuration
    Namespace        string        // Benchmark namespace (auto-generated if empty)
    Iterations       int           // Number of test iterations
    
    // Thresholds for pass/fail
    MaxP99Latency    time.Duration // Maximum acceptable p99 latency
    MinThroughput    float64       // Minimum acceptable throughput
}

// BenchmarkResult contains the benchmark results
type BenchmarkResult struct {
    // Timing
    StartTime        time.Time
    EndTime          time.Time
    Duration         time.Duration
    
    // Throughput
    WorkflowsStarted   int64
    WorkflowsCompleted int64
    WorkflowsFailed    int64
    ActualRate         float64
    
    // Latency (in milliseconds)
    LatencyP50       float64
    LatencyP95       float64
    LatencyP99       float64
    LatencyMax       float64
    
    // System info
    InstanceType     string
    ServiceCounts    map[string]int
    HistoryShards    int
    
    // Pass/Fail
    Passed           bool
    FailureReasons   []string
}

// BenchmarkRunner orchestrates benchmark execution
type BenchmarkRunner interface {
    // Run executes the benchmark with the given configuration
    Run(ctx context.Context, config BenchmarkConfig) (*BenchmarkResult, error)
    
    // Cleanup terminates workflows and cleans up resources
    Cleanup(ctx context.Context, namespace string) error
}
```

### 2. Workflow Generator

```go
// WorkflowGenerator creates and submits workflows
type WorkflowGenerator interface {
    // Start begins generating workflows at the configured rate
    Start(ctx context.Context) error
    
    // Stop halts workflow generation
    Stop() error
    
    // Stats returns current generation statistics
    Stats() GeneratorStats
}

type GeneratorStats struct {
    WorkflowsStarted   int64
    WorkflowsCompleted int64
    WorkflowsFailed    int64
    CurrentRate        float64
    TargetRate         float64
}
```

### 3. Metrics Handler

```go
// MetricsHandler exposes Prometheus metrics
type MetricsHandler interface {
    // ServeHTTP handles Prometheus scrape requests
    ServeHTTP(w http.ResponseWriter, r *http.Request)
    
    // RecordWorkflowLatency records a workflow completion latency
    RecordWorkflowLatency(duration time.Duration)
    
    // RecordWorkflowResult records a workflow completion (success/failure)
    RecordWorkflowResult(success bool)
}
```

### 4. Benchmark Workflows

```go
// SimpleWorkflow completes immediately
func SimpleWorkflow(ctx workflow.Context) error {
    return nil
}

// MultiActivityWorkflow executes N activities sequentially
func MultiActivityWorkflow(ctx workflow.Context, activityCount int) error {
    ao := workflow.ActivityOptions{
        StartToCloseTimeout: time.Minute,
    }
    ctx = workflow.WithActivityOptions(ctx, ao)
    
    for i := 0; i < activityCount; i++ {
        err := workflow.ExecuteActivity(ctx, NoOpActivity).Get(ctx, nil)
        if err != nil {
            return err
        }
    }
    return nil
}

// TimerWorkflow waits for a configurable duration
func TimerWorkflow(ctx workflow.Context, duration time.Duration) error {
    return workflow.Sleep(ctx, duration)
}

// ChildWorkflow spawns N child workflows
func ChildWorkflow(ctx workflow.Context, childCount int) error {
    var futures []workflow.ChildWorkflowFuture
    for i := 0; i < childCount; i++ {
        future := workflow.ExecuteChildWorkflow(ctx, SimpleWorkflow)
        futures = append(futures, future)
    }
    for _, f := range futures {
        if err := f.Get(ctx, nil); err != nil {
            return err
        }
    }
    return nil
}

// NoOpActivity is a minimal activity for testing
func NoOpActivity(ctx context.Context) error {
    return nil
}
```

## Data Models

### Benchmark Configuration (Environment Variables)

| Variable | Description | Default |
|----------|-------------|---------|
| `BENCHMARK_WORKFLOW_TYPE` | Workflow type: simple, multi-activity, timer, child-workflow | simple |
| `BENCHMARK_ACTIVITY_COUNT` | Number of activities for multi-activity workflow | 5 |
| `BENCHMARK_TIMER_DURATION` | Timer duration for timer workflow | 1s |
| `BENCHMARK_CHILD_COUNT` | Number of child workflows | 3 |
| `BENCHMARK_TARGET_RATE` | Target workflows per second | 100 |
| `BENCHMARK_DURATION` | Test duration | 5m |
| `BENCHMARK_RAMP_UP` | Ramp-up period | 30s |
| `BENCHMARK_WORKER_COUNT` | Number of parallel workers | 4 |
| `BENCHMARK_ITERATIONS` | Number of test iterations | 1 |
| `BENCHMARK_MAX_P99_LATENCY` | Maximum acceptable p99 latency | 5s |
| `BENCHMARK_MIN_THROUGHPUT` | Minimum acceptable throughput | 50 |
| `TEMPORAL_ADDRESS` | Temporal frontend address | temporal-frontend:7233 |

### Results JSON Schema

```json
{
  "timestamp": "2026-01-13T20:00:00Z",
  "config": {
    "workflowType": "simple",
    "targetRate": 100,
    "duration": "5m",
    "workerCount": 4
  },
  "results": {
    "workflowsStarted": 30000,
    "workflowsCompleted": 29950,
    "workflowsFailed": 50,
    "actualRate": 99.83,
    "latency": {
      "p50": 45.2,
      "p95": 120.5,
      "p99": 250.3,
      "max": 1250.0
    }
  },
  "system": {
    "instanceType": "m7g.large",
    "historyShards": 4,
    "services": {
      "frontend": 1,
      "history": 1,
      "matching": 1,
      "worker": 1
    }
  },
  "passed": true,
  "failureReasons": []
}
```

## Infrastructure Components

### Terraform Resources

1. **ASG for Benchmark Nodes**
```hcl
resource "aws_autoscaling_group" "benchmark" {
  name                = "${var.project_name}-benchmark"
  min_size            = 0
  max_size            = 4
  desired_capacity    = 0  # Scale from zero
  
  launch_template {
    id      = aws_launch_template.benchmark.id
    version = "$Latest"
  }
  
  tag {
    key                 = "workload"
    value               = "benchmark"
    propagate_at_launch = true
  }
}
```

2. **ECS Capacity Provider**
```hcl
resource "aws_ecs_capacity_provider" "benchmark" {
  name = "${var.project_name}-benchmark"
  
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.benchmark.arn
    managed_termination_protection = "DISABLED"
    
    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 4
    }
  }
}
```

3. **Benchmark Task Definition**
```hcl
resource "aws_ecs_task_definition" "benchmark" {
  family                   = "${var.project_name}-benchmark"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  
  container_definitions = jsonencode([{
    name      = "benchmark"
    image     = var.benchmark_image
    essential = true
    
    portMappings = [{
      containerPort = 9090
      protocol      = "tcp"
      name          = "metrics"
    }]
    
    environment = [
      { name = "TEMPORAL_ADDRESS", value = "temporal-frontend:7233" },
      { name = "BENCHMARK_WORKFLOW_TYPE", value = "simple" },
      { name = "BENCHMARK_TARGET_RATE", value = "100" },
      { name = "BENCHMARK_DURATION", value = "5m" }
    ]
  }])
}
```

### Run Script

```bash
#!/bin/bash
# scripts/run-benchmark.sh

# Default values
WORKFLOW_TYPE=${1:-simple}
TARGET_RATE=${2:-100}
DURATION=${3:-5m}

# Run benchmark task
aws ecs run-task \
  --cluster temporal-dev-cluster \
  --task-definition temporal-dev-benchmark \
  --capacity-provider-strategy capacityProvider=temporal-dev-benchmark,weight=1 \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_IDS}],securityGroups=[${SG_ID}]}" \
  --overrides '{
    "containerOverrides": [{
      "name": "benchmark",
      "environment": [
        {"name": "BENCHMARK_WORKFLOW_TYPE", "value": "'${WORKFLOW_TYPE}'"},
        {"name": "BENCHMARK_TARGET_RATE", "value": "'${TARGET_RATE}'"},
        {"name": "BENCHMARK_DURATION", "value": "'${DURATION}'"}
      ]
    }]
  }' \
  --enable-execute-command
```



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Workflow Parameter Respect

*For any* workflow configuration with activity count N (1-100) or timer duration D, the executed workflow SHALL complete with exactly N activities executed or take approximately D time (±10% tolerance).

**Validates: Requirements 1.2, 1.3**

### Property 2: Workflow Type Isolation

*For any* benchmark run with a selected workflow type T, all workflows executed during that run SHALL be of type T and no other type.

**Validates: Requirements 1.5**

### Property 3: Rate Achievement Within Tolerance

*For any* configured target rate R (1-1000 WPS), the actual achieved rate SHALL be within 90% of R when system resources are not saturated, or the actual rate SHALL be logged when target cannot be sustained.

**Validates: Requirements 2.1, 2.4**

### Property 4: Duration Accuracy

*For any* configured test duration D (1-60 minutes), the actual test duration SHALL be within 5% of D.

**Validates: Requirements 2.2**

### Property 5: Ramp-Up Monotonicity

*For any* benchmark with ramp-up period R, the workflow submission rate SHALL monotonically increase during the ramp-up period until reaching the target rate.

**Validates: Requirements 2.3**

### Property 6: Load Distribution Fairness

*For any* benchmark with W workers, each worker SHALL handle between (1/W - 0.2) and (1/W + 0.2) of the total load (within 20% of fair share).

**Validates: Requirements 2.5**

### Property 7: Percentile Correctness

*For any* set of latency measurements, the reported p50 SHALL be less than or equal to p95, which SHALL be less than or equal to p99, which SHALL be less than or equal to max.

**Validates: Requirements 3.1**

### Property 8: Throughput Calculation Accuracy

*For any* benchmark run, the reported throughput SHALL equal (completed workflows / duration) within 1% tolerance.

**Validates: Requirements 3.2**

### Property 9: Results JSON Validity

*For any* benchmark completion, the output SHALL be valid JSON containing all required fields: timestamp, config, results, system, passed, and failureReasons.

**Validates: Requirements 6.1, 6.3, 6.5**

### Property 10: Threshold Comparison Correctness

*For any* benchmark result with latency L and throughput T, and thresholds maxLatency M and minThroughput N:
- If L > M OR T < N, then passed SHALL be false
- If L <= M AND T >= N, then passed SHALL be true

**Validates: Requirements 6.4**

### Property 11: Namespace Isolation

*For any* benchmark run, all created workflows SHALL exist in a namespace prefixed with "benchmark-", and workflows in other namespaces SHALL remain unaffected (count unchanged).

**Validates: Requirements 8.1, 8.3**

### Property 12: Cleanup Completeness

*For any* benchmark completion with cleanup enabled, the count of running workflows in the benchmark namespace SHALL be zero after cleanup.

**Validates: Requirements 8.2**

## Error Handling

### Connection Errors

| Error | Handling |
|-------|----------|
| Temporal Frontend unreachable | Fail fast with clear error message, exit code 1 |
| Namespace creation fails | Retry 3 times with exponential backoff, then fail |
| Workflow start fails | Log error, continue with remaining workflows, track failure count |
| Metrics endpoint unavailable | Log warning, continue benchmark without metrics export |

### Resource Errors

| Error | Handling |
|-------|----------|
| Rate limit exceeded | Log actual achieved rate, continue at sustainable rate |
| Memory pressure | Reduce batch size, log warning |
| Worker timeout | Restart worker, log incident |

### Cleanup Errors

| Error | Handling |
|-------|----------|
| Workflow termination fails | Log failure, provide manual cleanup command |
| Namespace deletion fails | Log warning (namespace can be reused) |

## Testing Strategy

### Unit Tests

Unit tests verify individual components in isolation:

1. **Config Parsing**: Verify environment variables are correctly parsed into BenchmarkConfig
2. **Rate Limiter**: Verify rate limiting achieves target rate within tolerance
3. **Percentile Calculator**: Verify p50/p95/p99 calculations are mathematically correct
4. **JSON Serialization**: Verify BenchmarkResult serializes to valid JSON with all fields
5. **Threshold Comparison**: Verify pass/fail logic is correct for various threshold combinations

### Property-Based Tests

Property-based tests verify universal properties across many generated inputs:

1. **Property 7 (Percentile Correctness)**: Generate random latency distributions, verify p50 ≤ p95 ≤ p99 ≤ max
2. **Property 8 (Throughput Calculation)**: Generate random completion counts and durations, verify throughput formula
3. **Property 9 (JSON Validity)**: Generate random BenchmarkResults, verify JSON output is valid and complete
4. **Property 10 (Threshold Comparison)**: Generate random results and thresholds, verify pass/fail logic

### Integration Tests

Integration tests verify end-to-end behavior:

1. **Simple Workflow Benchmark**: Run 1-minute benchmark with simple workflows, verify results
2. **Multi-Activity Benchmark**: Run benchmark with multi-activity workflows, verify activity count
3. **Cleanup Verification**: Run benchmark, verify cleanup terminates all workflows
4. **Metrics Export**: Run benchmark, verify Prometheus metrics are exposed

### Test Configuration

- Property-based tests: Minimum 100 iterations per property
- Integration tests: Run against local Temporal (docker-compose) or test cluster
- All tests tagged with feature and property reference

```go
// Example property test annotation
// Feature: temporal-benchmark, Property 7: Percentile Correctness
func TestPercentileOrdering(t *testing.T) {
    rapid.Check(t, func(t *rapid.T) {
        // Generate random latencies
        latencies := rapid.SliceOfN(rapid.Float64Range(0, 10000), 10, 1000).Draw(t, "latencies")
        
        result := calculatePercentiles(latencies)
        
        // Verify ordering
        require.LessOrEqual(t, result.P50, result.P95)
        require.LessOrEqual(t, result.P95, result.P99)
        require.LessOrEqual(t, result.P99, result.Max)
    })
}
```
