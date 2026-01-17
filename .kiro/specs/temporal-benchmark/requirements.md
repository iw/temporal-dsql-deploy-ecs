# Requirements Document

## Introduction

This specification defines the requirements for a comprehensive benchmarking system for Temporal deployed on ECS with Aurora DSQL persistence and OpenSearch visibility. The benchmark will measure workflow throughput, latency, and system behavior under various load conditions to validate production readiness and establish performance baselines.

## Glossary

- **Benchmark_Runner**: The component that orchestrates benchmark execution, including workflow submission and metrics collection
- **Workflow_Generator**: The component that creates and submits test workflows to Temporal at configurable rates
- **Metrics_Collector**: The component that gathers performance metrics from Temporal services, DSQL, and OpenSearch
- **Load_Profile**: A configuration defining the rate, duration, and type of workflows to execute during a benchmark run
- **Throughput**: The number of workflow executions completed per second
- **Latency**: The time from workflow start to completion, measured at p50, p95, and p99 percentiles
- **DSQL_Conflict_Rate**: The percentage of database operations that encounter optimistic concurrency control conflicts

## Requirements

### Requirement 1: Benchmark Workflow Types

**User Story:** As a platform engineer, I want to benchmark different workflow patterns, so that I can understand system performance across various use cases.

#### Acceptance Criteria

1. THE Workflow_Generator SHALL support a simple "hello world" workflow that completes immediately
2. THE Workflow_Generator SHALL support a workflow with configurable activity count (1-100 activities)
3. THE Workflow_Generator SHALL support a workflow with configurable sleep/timer duration
4. THE Workflow_Generator SHALL support a workflow with child workflow spawning
5. WHEN a workflow type is selected, THE Benchmark_Runner SHALL execute only that workflow type for the duration of the test

### Requirement 2: Load Generation

**User Story:** As a platform engineer, I want to control the load profile, so that I can test the system under different conditions.

#### Acceptance Criteria

1. THE Workflow_Generator SHALL support configurable workflows-per-second rate (1-1000 WPS)
2. THE Workflow_Generator SHALL support configurable test duration (1-60 minutes)
3. THE Workflow_Generator SHALL support ramp-up periods to gradually increase load
4. WHEN the target rate cannot be sustained, THE Benchmark_Runner SHALL log the actual achieved rate
5. THE Workflow_Generator SHALL distribute load evenly across the configured number of worker instances

### Requirement 3: Metrics Collection

**User Story:** As a platform engineer, I want comprehensive metrics, so that I can analyze system performance and identify bottlenecks.

#### Acceptance Criteria

1. THE Metrics_Collector SHALL record workflow start-to-completion latency at p50, p95, and p99 percentiles
2. THE Metrics_Collector SHALL record workflow throughput (completions per second)
3. THE Metrics_Collector SHALL record activity execution latency
4. THE Metrics_Collector SHALL record task queue depth for workflow and activity task queues
5. THE Metrics_Collector SHALL record DSQL connection pool utilization
6. THE Metrics_Collector SHALL record DSQL query latency
7. THE Metrics_Collector SHALL record OpenSearch indexing latency
8. WHEN metrics are collected, THE Metrics_Collector SHALL export them in Prometheus format

### Requirement 3.1: Temporal SDK Client Metrics

**User Story:** As a platform engineer, I want client-side SDK metrics from benchmark workers, so that I can understand end-to-end performance from the client perspective.

#### Acceptance Criteria

1. THE Benchmark_Runner SHALL expose Temporal SDK metrics on a Prometheus endpoint (port 9090)
2. THE Benchmark_Runner SHALL emit `temporal_request_latency` metrics for all Temporal API calls
3. THE Benchmark_Runner SHALL emit `temporal_workflow_task_schedule_to_start_latency` metrics
4. THE Benchmark_Runner SHALL emit `temporal_activity_task_schedule_to_start_latency` metrics
5. THE Benchmark_Runner SHALL emit `temporal_workflow_endtoend_latency` metrics
6. THE Benchmark_Runner SHALL emit `temporal_long_request` metrics for requests exceeding thresholds
7. THE Benchmark_Runner SHALL emit `temporal_request_failure` metrics with failure type labels
8. WHEN ADOT is configured, THE Benchmark_Runner metrics SHALL be scraped and sent to Amazon Managed Prometheus

### Requirement 4: Benchmark Infrastructure

**User Story:** As a platform engineer, I want benchmark infrastructure isolated from Temporal services, so that benchmarks don't affect service performance and measurements are accurate.

#### Acceptance Criteria

1. THE Benchmark_Runner SHALL run on dedicated EC2 nodes separate from Temporal services
2. THE Benchmark infrastructure SHALL use a dedicated capacity provider with "workload=benchmark" attribute
3. THE Benchmark nodes SHALL be provisioned on-demand when benchmarks are run (scale from 0)
4. THE Benchmark nodes SHALL use the same instance type as Temporal nodes (m7g.large) for consistency
5. WHEN no benchmarks are running, THE Benchmark infrastructure SHALL scale to zero nodes to minimize cost
6. THE Benchmark_Runner SHALL connect to Temporal Frontend via Service Connect (temporal-frontend:7233)

### Requirement 5: Benchmark Execution

**User Story:** As a platform engineer, I want to run benchmarks easily, so that I can quickly validate system performance.

#### Acceptance Criteria

1. THE Benchmark_Runner SHALL be deployable as an ECS task in the existing Temporal cluster (temporal-dev-cluster)
2. THE Benchmark_Runner SHALL accept configuration via environment variables or command-line arguments
3. WHEN a benchmark starts, THE Benchmark_Runner SHALL create a dedicated namespace for test workflows
4. WHEN a benchmark completes, THE Benchmark_Runner SHALL output a summary report with key metrics
5. THE Benchmark_Runner SHALL support running multiple iterations and averaging results
6. IF the Temporal cluster is unhealthy, THEN THE Benchmark_Runner SHALL fail fast with a clear error message
7. THE Benchmark_Runner SHALL be implemented as a one-shot ECS task (not a long-running service)
8. THE Benchmark_Runner SHALL support running multiple worker instances in parallel for higher load generation

### Requirement 6: Results Reporting

**User Story:** As a platform engineer, I want clear benchmark results, so that I can make informed decisions about production readiness.

#### Acceptance Criteria

1. THE Benchmark_Runner SHALL output results in JSON format for programmatic consumption
2. THE Benchmark_Runner SHALL output a human-readable summary to stdout
3. THE Benchmark_Runner SHALL include system configuration in the results (instance types, service counts, shard count)
4. THE Benchmark_Runner SHALL compare results against configurable thresholds and report pass/fail
5. WHEN results are generated, THE Benchmark_Runner SHALL include timestamp and test parameters for reproducibility

### Requirement 7: DSQL-Specific Metrics

**User Story:** As a platform engineer, I want DSQL-specific metrics, so that I can understand how Aurora DSQL performs as the persistence layer.

#### Acceptance Criteria

1. THE Metrics_Collector SHALL record DSQL serialization conflict rate
2. THE Metrics_Collector SHALL record DSQL retry counts due to OCC conflicts
3. THE Metrics_Collector SHALL record DSQL transaction commit latency
4. WHEN conflict rates exceed 5%, THE Benchmark_Runner SHALL emit a warning
5. THE Metrics_Collector SHALL record connection establishment time for DSQL

### Requirement 8: Cleanup and Isolation

**User Story:** As a platform engineer, I want benchmarks to be isolated and clean up after themselves, so that they don't affect production workloads.

#### Acceptance Criteria

1. THE Benchmark_Runner SHALL use a dedicated namespace prefixed with "benchmark-"
2. WHEN a benchmark completes, THE Benchmark_Runner SHALL terminate all running workflows in the benchmark namespace
3. THE Benchmark_Runner SHALL NOT interfere with workflows in other namespaces
4. IF cleanup fails, THEN THE Benchmark_Runner SHALL log the failure and provide manual cleanup instructions
