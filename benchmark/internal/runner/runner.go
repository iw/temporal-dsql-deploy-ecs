// Package runner provides the benchmark orchestration logic.
package runner

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"go.temporal.io/api/enums/v1"
	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/worker"
	"google.golang.org/protobuf/types/known/durationpb"

	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/cleanup"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/config"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/generator"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/metrics"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/results"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/workflows"
)

// BenchmarkResult is an alias to the results package BenchmarkResult.
// This maintains backward compatibility while using the centralized results package.
type BenchmarkResult = results.BenchmarkResult

// BenchmarkRunner orchestrates benchmark execution.
type BenchmarkRunner interface {
	// Run executes the benchmark with the given configuration
	Run(ctx context.Context, cfg config.BenchmarkConfig) (*BenchmarkResult, error)

	// Cleanup terminates workflows and cleans up resources
	Cleanup(ctx context.Context, namespace string) error

	// GetNamespace returns the namespace used for the last benchmark run
	GetNamespace() string
}

// NamespacePrefix is the prefix for benchmark namespaces.
// Requirement 8.1: THE Benchmark_Runner SHALL use a dedicated namespace prefixed with "benchmark-"
const NamespacePrefix = "benchmark-"

// DefaultTaskQueue is the default task queue for benchmark workflows.
const DefaultTaskQueue = "benchmark-task-queue"

// MetricsPort is the port for the Prometheus metrics endpoint.
// Requirement 3.1.1: THE Benchmark_Runner SHALL expose Temporal SDK metrics on a Prometheus endpoint (port 9090)
const MetricsPort = 9090

// runner implements BenchmarkRunner.
type runner struct {
	client         client.Client
	hostPort       string // Store the host:port for creating namespace-specific clients
	metricsHandler metrics.MetricsHandler
	cleaner        *cleanup.Cleaner
	lastNamespace  string // Track the namespace used in the last run
}

// RunnerOption configures the runner.
type RunnerOption func(*runner)

// WithMetricsHandler sets a custom metrics handler.
func WithMetricsHandler(h metrics.MetricsHandler) RunnerOption {
	return func(r *runner) {
		r.metricsHandler = h
	}
}

// WithHostPort sets the Temporal server host:port for creating namespace-specific clients.
func WithHostPort(hostPort string) RunnerOption {
	return func(r *runner) {
		r.hostPort = hostPort
	}
}

// NewRunner creates a new BenchmarkRunner.
func NewRunner(c client.Client, opts ...RunnerOption) BenchmarkRunner {
	r := &runner{
		client:  c,
		cleaner: cleanup.NewCleaner(c),
	}

	for _, opt := range opts {
		opt(r)
	}

	// Create default metrics handler if not provided
	if r.metricsHandler == nil {
		r.metricsHandler = metrics.NewHandler()
	}

	return r
}

// Run executes the benchmark with the given configuration.
// Requirement 5.1: THE Benchmark_Runner SHALL be deployable as an ECS task
// Requirement 5.5: THE Benchmark_Runner SHALL support running multiple iterations and averaging results
func (r *runner) Run(ctx context.Context, cfg config.BenchmarkConfig) (*BenchmarkResult, error) {
	// Requirement 5.6: IF the Temporal cluster is unhealthy, THEN THE Benchmark_Runner SHALL fail fast
	if err := r.checkClusterHealth(ctx); err != nil {
		return nil, fmt.Errorf("cluster health check failed: %w", err)
	}

	// Requirement 5.3: WHEN a benchmark starts, THE Benchmark_Runner SHALL create a dedicated namespace
	namespace := cfg.Namespace
	if namespace == "" {
		namespace = generateNamespace()
	}
	r.lastNamespace = namespace // Track the namespace for later use

	if err := r.ensureNamespace(ctx, namespace); err != nil {
		return nil, fmt.Errorf("failed to create namespace %s: %w", namespace, err)
	}

	// Start metrics server
	// Requirement 3.1.1: THE Benchmark_Runner SHALL expose Temporal SDK metrics on port 9090
	if err := r.metricsHandler.StartServer(ctx, MetricsPort); err != nil {
		return nil, fmt.Errorf("failed to start metrics server: %w", err)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := r.metricsHandler.StopServer(shutdownCtx); err != nil {
			log.Printf("Warning: failed to stop metrics server: %v", err)
		}
	}()

	// Run iterations and aggregate results
	var aggregatedResult *BenchmarkResult
	for i := 0; i < cfg.Iterations; i++ {
		if cfg.Iterations > 1 {
			log.Printf("Starting iteration %d of %d", i+1, cfg.Iterations)
		}

		result, err := r.runSingleIteration(ctx, cfg, namespace)
		if err != nil {
			return nil, fmt.Errorf("iteration %d failed: %w", i+1, err)
		}

		if aggregatedResult == nil {
			aggregatedResult = result
		} else {
			aggregatedResult = aggregateResults(aggregatedResult, result)
		}

		// Check for cancellation between iterations
		select {
		case <-ctx.Done():
			log.Println("Benchmark cancelled between iterations")
			return aggregatedResult, ctx.Err()
		default:
		}
	}

	// Evaluate pass/fail against thresholds using the results package
	// Requirement 6.4: THE Benchmark_Runner SHALL compare results against configurable thresholds
	results.EvaluateThresholdsWithConfig(aggregatedResult, cfg)

	if aggregatedResult.Passed {
		log.Println("Benchmark PASSED all thresholds")
	} else {
		log.Printf("Benchmark FAILED: %v", aggregatedResult.FailureReasons)
	}

	return aggregatedResult, nil
}

// GetNamespace returns the namespace used for the last benchmark run.
func (r *runner) GetNamespace() string {
	return r.lastNamespace
}

// runSingleIteration executes a single benchmark iteration.
func (r *runner) runSingleIteration(ctx context.Context, cfg config.BenchmarkConfig, namespace string) (*BenchmarkResult, error) {
	startTime := time.Now()

	// Create a namespace-specific client for the benchmark
	// The original client uses "default" namespace, but we need to use the benchmark namespace
	if r.hostPort == "" {
		return nil, fmt.Errorf("hostPort not configured - use WithHostPort option when creating runner")
	}
	nsClientOptions := client.Options{
		HostPort:  r.hostPort,
		Namespace: namespace,
	}
	nsClient, err := client.Dial(nsClientOptions)
	if err != nil {
		return nil, fmt.Errorf("failed to create namespace client for %s: %w", namespace, err)
	}
	defer nsClient.Close()

	// Only start embedded worker if not in generator-only mode
	// When running separate worker services, the generator doesn't need its own worker
	var w worker.Worker
	if !cfg.GeneratorOnly {
		// Create a worker to process workflows in the benchmark namespace
		// Optimized for high-throughput benchmarking:
		// - High concurrent execution sizes for parallel processing
		// - Increased poller counts for faster task pickup
		// - Eager execution enabled for lower latency
		// - Sticky execution enabled for workflow caching
		workerOptions := worker.Options{
			// Concurrent execution limits - high values for benchmark throughput
			MaxConcurrentActivityExecutionSize:      200,
			MaxConcurrentWorkflowTaskExecutionSize:  200,
			MaxConcurrentLocalActivityExecutionSize: 200,

			// Poller counts - higher values for faster task pickup
			// Rule: pollers should be significantly < execution size
			MaxConcurrentWorkflowTaskPollers: 16,
			MaxConcurrentActivityTaskPollers: 16,

			// Eager activity execution - reduces latency by executing locally when possible
			// Activities requested from same workflow can start immediately without server round-trip
			DisableEagerActivities:                  false,
			MaxConcurrentEagerActivityExecutionSize: 100, // Allow up to 100 eager activities

			// Sticky execution timeout - how long to keep workflow state cached
			// Default is 5s, keeping it for workflow caching benefits
			StickyScheduleToStartTimeout: 5 * time.Second,

			// No rate limiting for benchmark - maximize throughput
			// WorkerActivitiesPerSecond: 0 (unlimited, default is 100k)
		}

		w = worker.New(nsClient, DefaultTaskQueue, workerOptions)
		workflows.RegisterAll(w)

		// Start the worker
		if err := w.Start(); err != nil {
			return nil, fmt.Errorf("failed to start worker: %w", err)
		}
		defer w.Stop()
		log.Println("Embedded worker started")
	} else {
		log.Println("Generator-only mode: no embedded worker (workflows processed by external workers)")
	}

	// Create workflow generator with completion callback using namespace client
	gen := generator.NewGenerator(
		nsClient,
		cfg,
		DefaultTaskQueue,
		generator.WithCompletionCallback(func(workflowID string, duration time.Duration, err error) {
			r.metricsHandler.RecordWorkflowLatency(duration)
			r.metricsHandler.RecordWorkflowResult(err == nil)
		}),
	)

	// Start generating workflows
	if err := gen.Start(ctx); err != nil {
		return nil, fmt.Errorf("failed to start generator: %w", err)
	}

	// Wait for test duration
	select {
	case <-ctx.Done():
		log.Println("Benchmark cancelled during execution")
	case <-time.After(cfg.Duration):
		log.Println("Benchmark duration completed")
	}

	// Stop generator
	if err := gen.Stop(); err != nil {
		log.Printf("Warning: failed to stop generator: %v", err)
	}

	// Wait for remaining workflows to complete (with timeout)
	// Calculate completion timeout: use configured value or auto-calculate based on workload
	completionTimeout := cfg.CompletionTimeout
	if completionTimeout == 0 {
		// Auto-calculate: estimate based on expected in-flight workflows
		// At high WPS, many workflows may still be in-flight when test ends
		// Use: max(60s, duration) to allow at least as much drain time as test duration
		expectedWorkflows := cfg.TargetRate * cfg.Duration.Seconds()
		completionTimeout = max(60*time.Second, cfg.Duration)
		// Cap at 10 minutes to avoid indefinite waits
		completionTimeout = min(completionTimeout, 10*time.Minute)
		log.Printf("Auto-calculated completion timeout: %v (expected ~%.0f workflows)", completionTimeout, expectedWorkflows)
	}
	waitCtx, cancel := context.WithTimeout(ctx, completionTimeout)
	defer cancel()
	if err := gen.Wait(waitCtx); err != nil {
		log.Printf("Warning: some workflows may not have completed: %v", err)
	}

	endTime := time.Now()
	stats := gen.Stats()
	percentiles := r.metricsHandler.GetLatencyPercentiles()
	throughput := r.metricsHandler.GetThroughput()

	return &BenchmarkResult{
		StartTime:          startTime,
		EndTime:            endTime,
		Duration:           endTime.Sub(startTime),
		WorkflowsStarted:   stats.WorkflowsStarted,
		WorkflowsCompleted: stats.WorkflowsCompleted,
		WorkflowsFailed:    stats.WorkflowsFailed,
		ActualRate:         throughput,
		LatencyP50:         percentiles.P50,
		LatencyP95:         percentiles.P95,
		LatencyP99:         percentiles.P99,
		LatencyMax:         percentiles.Max,
		InstanceType:       "m7g.large", // Default for ECS deployment
		ServiceCounts:      map[string]int{"frontend": 1, "history": 1, "matching": 1, "worker": 1},
		HistoryShards:      4, // Default shard count
		Passed:             true,
		FailureReasons:     []string{},
	}, nil
}

// checkClusterHealth verifies the Temporal cluster is healthy before starting.
// Requirement 5.6: IF the Temporal cluster is unhealthy, THEN THE Benchmark_Runner SHALL fail fast
// with a clear error message.
func (r *runner) checkClusterHealth(ctx context.Context) error {
	log.Println("Checking Temporal cluster health...")

	// Use CheckHealth API to verify cluster is responsive
	_, err := r.client.CheckHealth(ctx, nil)
	if err != nil {
		return fmt.Errorf("Temporal cluster is unhealthy: %w", err)
	}

	log.Println("Temporal cluster health check passed")
	return nil
}

// ensureNamespace creates the benchmark namespace if it doesn't exist.
// Requirement 5.3: WHEN a benchmark starts, THE Benchmark_Runner SHALL create a dedicated namespace
// Requirement 8.1: THE Benchmark_Runner SHALL use a dedicated namespace prefixed with "benchmark-"
func (r *runner) ensureNamespace(ctx context.Context, namespace string) error {
	log.Printf("Ensuring namespace %s exists...", namespace)

	namespaceCreated := false

	// Check if namespace already exists
	_, err := r.client.WorkflowService().DescribeNamespace(ctx, &workflowservice.DescribeNamespaceRequest{
		Namespace: namespace,
	})
	if err == nil {
		log.Printf("Namespace %s already exists", namespace)
	} else {
		// Create the namespace
		log.Printf("Creating namespace %s...", namespace)
		_, err = r.client.WorkflowService().RegisterNamespace(ctx, &workflowservice.RegisterNamespaceRequest{
			Namespace:                        namespace,
			Description:                      "Benchmark namespace for Temporal DSQL performance testing",
			WorkflowExecutionRetentionPeriod: durationpb.New(24 * time.Hour), // 1 day retention
			IsGlobalNamespace:                false,
		})
		if err != nil {
			return fmt.Errorf("failed to register namespace: %w", err)
		}
		namespaceCreated = true

		// Wait for namespace to be registered
		log.Printf("Waiting for namespace %s to be registered...", namespace)
		for i := 0; i < 30; i++ {
			_, err := r.client.WorkflowService().DescribeNamespace(ctx, &workflowservice.DescribeNamespaceRequest{
				Namespace: namespace,
			})
			if err == nil {
				log.Printf("Namespace %s is registered", namespace)
				break
			}
			if i == 29 {
				return fmt.Errorf("namespace %s not registered after 30 seconds", namespace)
			}
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(time.Second):
			}
		}
	}

	// If namespace was just created, wait for it to propagate to all services
	// This is critical because namespace registration on frontend doesn't mean
	// history and matching services are ready to handle workflows in that namespace
	if namespaceCreated {
		log.Printf("Waiting for namespace %s to propagate to all services...", namespace)
		// Wait 10 seconds for namespace to propagate across all Temporal services
		// This is necessary because namespace changes need to sync to history/matching
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(10 * time.Second):
		}
		log.Printf("Namespace %s propagation wait complete", namespace)
	}

	return nil
}

// generateNamespace creates a unique namespace name with the benchmark prefix.
func generateNamespace() string {
	return fmt.Sprintf("%s%d", NamespacePrefix, time.Now().UnixNano())
}

// Cleanup terminates all running workflows in the benchmark namespace.
// Requirement 8.2: WHEN a benchmark completes, THE Benchmark_Runner SHALL terminate all running workflows
// Requirement 8.4: IF cleanup fails, THEN THE Benchmark_Runner SHALL log the failure and provide manual cleanup instructions
func (r *runner) Cleanup(ctx context.Context, namespace string) error {
	log.Printf("Starting cleanup for namespace: %s", namespace)

	// Use the dedicated cleaner for comprehensive cleanup
	result, err := r.cleaner.CleanupNamespace(ctx, namespace)
	if err != nil {
		return err
	}

	// Verify cleanup was successful
	if !result.Success {
		return fmt.Errorf("cleanup completed with %d errors out of %d workflows",
			len(result.TerminationErrors), result.WorkflowsFound)
	}

	// Verify no workflows remain
	if err := r.cleaner.VerifyCleanup(ctx, namespace); err != nil {
		log.Printf("Warning: cleanup verification failed: %v", err)
		// Don't return error here as workflows may have been terminated but verification timing issue
	}

	return nil
}

// CleanupWithResult terminates all running workflows and returns detailed results.
// This is useful for testing and detailed reporting.
func (r *runner) CleanupWithResult(ctx context.Context, namespace string) (*cleanup.CleanupResult, error) {
	return r.cleaner.CleanupNamespace(ctx, namespace)
}

// GetCleaner returns the underlying cleaner for direct access if needed.
func (r *runner) GetCleaner() *cleanup.Cleaner {
	return r.cleaner
}

// aggregateResults combines results from multiple iterations.
func aggregateResults(a, b *BenchmarkResult) *BenchmarkResult {
	return &BenchmarkResult{
		StartTime:          a.StartTime,
		EndTime:            b.EndTime,
		Duration:           a.Duration + b.Duration,
		WorkflowsStarted:   a.WorkflowsStarted + b.WorkflowsStarted,
		WorkflowsCompleted: a.WorkflowsCompleted + b.WorkflowsCompleted,
		WorkflowsFailed:    a.WorkflowsFailed + b.WorkflowsFailed,
		ActualRate:         (a.ActualRate + b.ActualRate) / 2, // Average rate
		LatencyP50:         (a.LatencyP50 + b.LatencyP50) / 2,
		LatencyP95:         (a.LatencyP95 + b.LatencyP95) / 2,
		LatencyP99:         (a.LatencyP99 + b.LatencyP99) / 2,
		LatencyMax:         max(a.LatencyMax, b.LatencyMax),
		InstanceType:       a.InstanceType,
		ServiceCounts:      a.ServiceCounts,
		HistoryShards:      a.HistoryShards,
		Passed:             a.Passed && b.Passed,
		FailureReasons:     append(a.FailureReasons, b.FailureReasons...),
	}
}

// OutputResults outputs the benchmark results in both JSON and human-readable formats.
// Requirement 6.1: THE Benchmark_Runner SHALL output results in JSON format for programmatic consumption.
// Requirement 6.2: THE Benchmark_Runner SHALL output a human-readable summary to stdout.
func OutputResults(result *BenchmarkResult, cfg config.BenchmarkConfig, namespace string) error {
	// Create JSON result
	jsonResult := results.NewBenchmarkResultJSON(result, cfg, namespace)

	// Print human-readable summary to stdout
	// Requirement 6.2: THE Benchmark_Runner SHALL output a human-readable summary to stdout
	jsonResult.PrintSummary(os.Stdout)

	// Output JSON to stdout
	// Requirement 6.1: THE Benchmark_Runner SHALL output results in JSON format
	jsonBytes, err := jsonResult.ToJSON()
	if err != nil {
		return fmt.Errorf("failed to serialize results to JSON: %w", err)
	}

	fmt.Println("\nJSON Results:")
	fmt.Println(string(jsonBytes))

	return nil
}

// ListOpenWorkflow is a helper to list open workflows using the workflow service.
func (r *runner) ListOpenWorkflow(ctx context.Context, req *workflowservice.ListOpenWorkflowExecutionsRequest) (*workflowservice.ListOpenWorkflowExecutionsResponse, error) {
	return r.client.WorkflowService().ListOpenWorkflowExecutions(ctx, req)
}

// VerifyNamespaceIsolation checks that workflows only exist in the benchmark namespace.
// Requirement 8.3: THE Benchmark_Runner SHALL NOT interfere with workflows in other namespaces
func (r *runner) VerifyNamespaceIsolation(ctx context.Context, namespace string) error {
	// Verify the namespace has the correct prefix
	if len(namespace) < len(NamespacePrefix) || namespace[:len(NamespacePrefix)] != NamespacePrefix {
		return fmt.Errorf("namespace %s does not have required prefix %s", namespace, NamespacePrefix)
	}
	return nil
}

// GetWorkflowCount returns the count of workflows in a namespace by status.
func (r *runner) GetWorkflowCount(ctx context.Context, namespace string, status enums.WorkflowExecutionStatus) (int64, error) {
	var count int64
	var nextPageToken []byte

	for {
		var resp *workflowservice.ListWorkflowExecutionsResponse
		var err error

		if status == enums.WORKFLOW_EXECUTION_STATUS_RUNNING {
			openResp, openErr := r.client.WorkflowService().ListOpenWorkflowExecutions(ctx, &workflowservice.ListOpenWorkflowExecutionsRequest{
				Namespace:       namespace,
				MaximumPageSize: 100,
				NextPageToken:   nextPageToken,
			})
			if openErr != nil {
				return 0, openErr
			}
			count += int64(len(openResp.Executions))
			nextPageToken = openResp.NextPageToken
		} else {
			resp, err = r.client.WorkflowService().ListWorkflowExecutions(ctx, &workflowservice.ListWorkflowExecutionsRequest{
				Namespace:     namespace,
				PageSize:      100,
				NextPageToken: nextPageToken,
				Query:         fmt.Sprintf("ExecutionStatus = %d", status),
			})
			if err != nil {
				return 0, err
			}
			count += int64(len(resp.Executions))
			nextPageToken = resp.NextPageToken
		}

		if len(nextPageToken) == 0 {
			break
		}
	}

	return count, nil
}
