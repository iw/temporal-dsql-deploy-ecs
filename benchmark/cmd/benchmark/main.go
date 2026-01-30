// Package main provides the entry point for the Temporal benchmark runner.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/worker"

	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/config"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/metrics"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/runner"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/workflows"
)

func main() {
	// Setup structured JSON logging
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigCh
		slog.Info("Received shutdown signal", "signal", sig.String())
		cancel()
	}()

	if err := run(ctx); err != nil {
		slog.Error("Benchmark failed", "error", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	slog.Info("Temporal Benchmark Runner starting")

	// Parse configuration from environment variables
	cfg, err := config.LoadFromEnv()
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}

	// Validate configuration
	if err := cfg.Validate(); err != nil {
		return fmt.Errorf("invalid configuration: %w", err)
	}

	// Determine mode
	mode := "full"
	if cfg.GeneratorOnly {
		mode = "generator-only"
	} else if cfg.WorkerOnly {
		mode = "worker-only"
	}

	slog.Info("Configuration loaded",
		"mode", mode,
		"workflow_type", cfg.WorkflowType,
		"target_rate", cfg.TargetRate,
		"duration", cfg.Duration.String(),
		"ramp_up", cfg.RampUpDuration.String(),
		"worker_count", cfg.WorkerCount,
		"iterations", cfg.Iterations,
		"temporal_address", cfg.TemporalAddress,
	)

	// Check for early cancellation before connecting
	select {
	case <-ctx.Done():
		slog.Info("Shutdown requested before initialization completed")
		return nil
	default:
	}

	// Create metrics handler with SDK metrics integration
	metricsHandler := metrics.NewHandler()

	// Create SDK metrics handler once - will be reused for all clients
	sdkMetricsHandler := metrics.SDKMetricsHandler(metricsHandler.Registry())

	// Create Temporal client with SDK metrics and retry logic
	slog.Info("Connecting to Temporal", "address", cfg.TemporalAddress)

	var temporalClient client.Client
	maxRetries := 30
	retryDelay := 2 * time.Second

	for i := 0; i < maxRetries; i++ {
		// Check for cancellation before each retry
		select {
		case <-ctx.Done():
			return fmt.Errorf("shutdown requested during connection retry")
		default:
		}

		temporalClient, err = client.Dial(client.Options{
			HostPort:       cfg.TemporalAddress,
			MetricsHandler: sdkMetricsHandler,
		})
		if err == nil {
			break
		}

		if i < maxRetries-1 {
			slog.Warn("Connection attempt failed",
				"attempt", i+1,
				"max_retries", maxRetries,
				"error", err,
				"retry_delay", retryDelay.String(),
			)
			time.Sleep(retryDelay)
		}
	}

	if err != nil {
		return fmt.Errorf("failed to connect to Temporal cluster at %s after %d attempts: %w", cfg.TemporalAddress, maxRetries, err)
	}
	defer temporalClient.Close()

	// Verify cluster health by checking system info
	slog.Info("Verifying Temporal cluster health")
	_, err = temporalClient.CheckHealth(ctx, nil)
	if err != nil {
		return fmt.Errorf("Temporal cluster health check failed: %w", err)
	}
	slog.Info("Temporal cluster is healthy")

	// Check for cancellation after health check
	select {
	case <-ctx.Done():
		slog.Info("Shutdown requested after health check")
		return nil
	default:
	}

	// Worker-only mode: just run workers, no benchmark execution
	if cfg.WorkerOnly {
		return runWorkerOnly(ctx, cfg, temporalClient, metricsHandler, sdkMetricsHandler)
	}

	// Create benchmark runner with metrics handler and host port
	benchmarkRunner := runner.NewRunner(
		temporalClient,
		runner.WithMetricsHandler(metricsHandler),
		runner.WithHostPort(cfg.TemporalAddress),
	)

	// Run the benchmark
	slog.Info("Starting benchmark execution")
	result, err := benchmarkRunner.Run(ctx, cfg)
	if err != nil {
		// Check if it was a cancellation
		if ctx.Err() != nil {
			slog.Info("Benchmark was cancelled")
			return nil
		}
		return fmt.Errorf("benchmark execution failed: %w", err)
	}

	// Get the namespace used for cleanup
	namespace := benchmarkRunner.GetNamespace()

	// Output results
	if err := runner.OutputResults(result, cfg, namespace); err != nil {
		slog.Warn("Failed to output results", "error", err)
	}

	// Cleanup benchmark workflows
	slog.Info("Cleaning up benchmark workflows")
	if err := benchmarkRunner.Cleanup(ctx, namespace); err != nil {
		slog.Warn("Cleanup failed", "error", err, "namespace", namespace)
	} else {
		slog.Info("Cleanup completed successfully")
	}

	slog.Info("Benchmark runner completed")
	return nil
}

// runWorkerOnly runs only the worker without generating workflows.
// This is used when running separate worker services to process benchmark workflows.
func runWorkerOnly(ctx context.Context, cfg config.BenchmarkConfig, temporalClient client.Client, metricsHandler metrics.MetricsHandler, sdkMetricsHandler client.MetricsHandler) error {
	namespace := cfg.Namespace
	if namespace == "" {
		namespace = "benchmark"
	}

	slog.Info("Starting worker-only mode",
		"namespace", namespace,
		"task_queue", runner.DefaultTaskQueue,
	)

	// Start metrics server for worker metrics
	if err := metricsHandler.StartServer(ctx, runner.MetricsPort); err != nil {
		return fmt.Errorf("failed to start metrics server: %w", err)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := metricsHandler.StopServer(shutdownCtx); err != nil {
			slog.Warn("Failed to stop metrics server", "error", err)
		}
	}()

	// Create namespace-specific client (reuse the SDK metrics handler)
	nsClient, err := client.Dial(client.Options{
		HostPort:       cfg.TemporalAddress,
		Namespace:      namespace,
		MetricsHandler: sdkMetricsHandler, // Reuse the same metrics handler
	})
	if err != nil {
		return fmt.Errorf("failed to create namespace client: %w", err)
	}
	defer nsClient.Close()

	// Create worker with high-throughput settings
	// Increased pollers from 16 to 32 to address workflow task processing bottleneck
	// observed in 6k st/s benchmark (server adding ~350 tasks/sec but only ~70/sec processed)
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

	w := worker.New(nsClient, runner.DefaultTaskQueue, workerOptions)
	workflows.RegisterAll(w)

	// Start the worker
	if err := w.Start(); err != nil {
		return fmt.Errorf("failed to start worker: %w", err)
	}
	slog.Info("Worker started, waiting for tasks")

	// Wait for shutdown signal
	<-ctx.Done()
	slog.Info("Shutdown signal received, stopping worker")

	w.Stop()
	slog.Info("Worker stopped")

	return nil
}
