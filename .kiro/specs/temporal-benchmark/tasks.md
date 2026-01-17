# Implementation Plan: Temporal DSQL Benchmark

## Overview

This implementation plan creates a benchmarking system for Temporal on ECS with DSQL. The benchmark runner is a Go application that executes configurable workflow patterns, collects metrics, and reports results. Infrastructure is provisioned via Terraform with dedicated benchmark nodes that scale from zero.

## Tasks

- [x] 1. Create benchmark Go module and project structure
  - Create `benchmark/` directory with Go module
  - Set up project structure: `cmd/`, `internal/`, `workflows/`
  - Add dependencies: Temporal Go SDK, Prometheus client, rapid (PBT)
  - _Requirements: 1.1, 5.1_

- [x] 2. Implement benchmark workflows
  - [x] 2.1 Implement SimpleWorkflow that completes immediately
    - Create `workflows/simple.go`
    - Register workflow with Temporal worker
    - _Requirements: 1.1_
  - [x] 2.2 Implement MultiActivityWorkflow with configurable activity count
    - Create `workflows/multi_activity.go`
    - Implement NoOpActivity
    - Accept activityCount parameter (1-100)
    - _Requirements: 1.2_
  - [x] 2.3 Implement TimerWorkflow with configurable duration
    - Create `workflows/timer.go`
    - Accept duration parameter
    - Use workflow.Sleep for timer
    - _Requirements: 1.3_
  - [x] 2.4 Implement ChildWorkflow that spawns child workflows
    - Create `workflows/child.go`
    - Accept childCount parameter
    - Execute SimpleWorkflow as children
    - _Requirements: 1.4_
  - [ ]* 2.5 Write property test for workflow parameter respect
    - **Property 1: Workflow Parameter Respect**
    - **Validates: Requirements 1.2, 1.3**

- [x] 3. Implement configuration and CLI
  - [x] 3.1 Create BenchmarkConfig struct and parser
    - Create `internal/config/config.go`
    - Parse environment variables
    - Validate configuration ranges
    - _Requirements: 5.2_
  - [x] 3.2 Implement CLI entry point
    - Create `cmd/benchmark/main.go`
    - Parse config, initialize components
    - Handle graceful shutdown
    - _Requirements: 5.2, 5.6_
  - [ ]* 3.3 Write unit tests for config parsing
    - Test environment variable parsing
    - Test validation of ranges
    - _Requirements: 5.2_

- [x] 4. Implement workflow generator with rate limiting
  - [x] 4.1 Create WorkflowGenerator interface and implementation
    - Create `internal/generator/generator.go`
    - Implement rate-limited workflow submission
    - Track started/completed/failed counts
    - _Requirements: 2.1, 2.4_
  - [x] 4.2 Implement ramp-up logic
    - Gradually increase rate during ramp-up period
    - Ensure monotonic rate increase
    - _Requirements: 2.3_
  - [ ]* 4.3 Write property test for rate achievement
    - **Property 3: Rate Achievement Within Tolerance**
    - **Validates: Requirements 2.1, 2.4**
  - [ ]* 4.4 Write property test for ramp-up monotonicity
    - **Property 5: Ramp-Up Monotonicity**
    - **Validates: Requirements 2.3**

- [x] 5. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Implement metrics collection
  - [x] 6.1 Create MetricsHandler with Prometheus registry
    - Create `internal/metrics/metrics.go`
    - Register workflow latency histogram
    - Register throughput counter
    - Expose on port 9090
    - _Requirements: 3.1, 3.2, 3.1.1_
  - [x] 6.2 Implement latency percentile calculation
    - Calculate p50, p95, p99, max from histogram
    - Store in BenchmarkResult
    - _Requirements: 3.1_
  - [x] 6.3 Implement SDK metrics integration
    - Configure Temporal SDK metrics handler
    - Expose SDK metrics on same endpoint
    - _Requirements: 3.1.2, 3.1.3, 3.1.4, 3.1.5, 3.1.6, 3.1.7_
  - [ ]* 6.4 Write property test for percentile correctness
    - **Property 7: Percentile Correctness**
    - **Validates: Requirements 3.1**
  - [ ]* 6.5 Write property test for throughput calculation
    - **Property 8: Throughput Calculation Accuracy**
    - **Validates: Requirements 3.2**

- [x] 7. Implement benchmark runner orchestration
  - [x] 7.1 Create BenchmarkRunner implementation
    - Create `internal/runner/runner.go`
    - Orchestrate generator, metrics, worker
    - Handle test duration and iterations
    - _Requirements: 5.1, 5.5_
  - [x] 7.2 Implement namespace management
    - Create benchmark namespace with prefix
    - Verify namespace creation before starting
    - _Requirements: 5.3, 8.1_
  - [x] 7.3 Implement health check and fail-fast
    - Check Temporal cluster health before starting
    - Fail fast with clear error if unhealthy
    - _Requirements: 5.6_
  - [ ]* 7.4 Write property test for namespace isolation
    - **Property 11: Namespace Isolation**
    - **Validates: Requirements 8.1, 8.3**

- [x] 8. Implement results reporting
  - [x] 8.1 Create BenchmarkResult struct and JSON serialization
    - Create `internal/results/results.go`
    - Include all required fields
    - Implement JSON marshaling
    - _Requirements: 6.1, 6.3, 6.5_
  - [x] 8.2 Implement threshold comparison and pass/fail logic
    - Compare latency against maxP99Latency
    - Compare throughput against minThroughput
    - Set passed flag and failureReasons
    - _Requirements: 6.4_
  - [x] 8.3 Implement human-readable summary output
    - Print summary to stdout
    - Include key metrics and pass/fail status
    - _Requirements: 6.2_
  - [ ]* 8.4 Write property test for JSON validity
    - **Property 9: Results JSON Validity**
    - **Validates: Requirements 6.1, 6.3, 6.5**
  - [ ]* 8.5 Write property test for threshold comparison
    - **Property 10: Threshold Comparison Correctness**
    - **Validates: Requirements 6.4**

- [x] 9. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Implement cleanup functionality
  - [x] 10.1 Implement workflow termination on completion
    - List all workflows in benchmark namespace
    - Terminate running workflows
    - Log cleanup progress
    - _Requirements: 8.2_
  - [x] 10.2 Implement cleanup error handling
    - Catch termination failures
    - Log manual cleanup instructions
    - _Requirements: 8.4_
  - [ ]* 10.3 Write property test for cleanup completeness
    - **Property 12: Cleanup Completeness**
    - **Validates: Requirements 8.2**

- [x] 11. Create Docker image for benchmark runner
  - [x] 11.1 Create Dockerfile for benchmark
    - Multi-stage build for ARM64
    - Include benchmark binary
    - Set entrypoint
    - _Requirements: 4.4, 5.1_
  - [x] 11.2 Add build script for benchmark image
    - Create `scripts/build-benchmark.sh`
    - Build and push to ECR
    - _Requirements: 5.1_

- [x] 12. Create Terraform infrastructure for benchmark nodes
  - [x] 12.1 Create ASG for benchmark nodes
    - Create `terraform/benchmark-ec2.tf`
    - Configure scale-from-zero ASG
    - Set workload=benchmark attribute
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  - [x] 12.2 Create ECS capacity provider for benchmark
    - Configure managed scaling
    - Link to benchmark ASG
    - _Requirements: 4.2_
  - [x] 12.3 Create benchmark task definition
    - Create `terraform/benchmark.tf`
    - Configure ARM64, awsvpc networking
    - Set Service Connect client mode
    - _Requirements: 4.6, 5.1, 5.7_
  - [x] 12.4 Create benchmark security group
    - Allow metrics scraping from ADOT
    - Allow outbound to Temporal services
    - _Requirements: 4.6_

- [x] 13. Update ADOT configuration for benchmark metrics
  - [x] 13.1 Add benchmark scrape target to ADOT config
    - Update `terraform/templates/adot-config.yaml`
    - Add benchmark service discovery
    - _Requirements: 3.1.8_

- [x] 14. Create run-benchmark script
  - [x] 14.1 Create benchmark execution script
    - Create `scripts/run-benchmark.sh`
    - Accept workflow type, rate, duration parameters
    - Run ECS task with overrides
    - _Requirements: 5.1, 5.2_
  - [x] 14.2 Create benchmark results retrieval script
    - Create `scripts/get-benchmark-results.sh`
    - Fetch CloudWatch logs for task
    - Extract JSON results
    - _Requirements: 6.1, 6.2_

- [x] 15. Final checkpoint - Integration testing
  - Run end-to-end benchmark test
  - Verify metrics appear in Prometheus/Grafana
  - Verify cleanup works correctly
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
- Go module should be created in `temporal-dsql-deploy-ecs/benchmark/`

---

## Implementation Status: COMPLETE ✅

**Completed: January 2026**

All benchmark infrastructure and runner components have been implemented:

- ✅ Benchmark Go module with workflow types (Simple, MultiActivity, Timer, Child)
- ✅ Rate-limited workflow generator with ramp-up support
- ✅ Prometheus metrics collection (latency histograms, throughput counters)
- ✅ Temporal SDK metrics integration
- ✅ Benchmark runner orchestration with namespace management
- ✅ JSON and human-readable results reporting
- ✅ Workflow cleanup on completion
- ✅ Docker image for ARM64 (Graviton)
- ✅ Terraform infrastructure (dedicated ASG, capacity provider, task definition)
- ✅ ADOT scraping configuration for benchmark metrics
- ✅ Run and results retrieval scripts

**Benchmark Results (January 2026):**
- 10 WPS: ✅ PASSED - 1,125 workflows, 100% success
- 50 WPS: ✅ PASSED - 14,071 workflows, 100% success, ~117k DSQL transactions
- 100 WPS: ❌ ResourceExhausted - Temporal rate limiting bottleneck (not DSQL)
- DSQL performed flawlessly with <5 OCC conflicts across 200k+ transactions

**Key Finding:** DSQL is NOT the bottleneck. Temporal's internal rate limiting needs tuning for higher throughput. Dynamic config updates have been applied for 75+ WPS target.
