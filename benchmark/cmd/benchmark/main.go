// Package main provides the entry point for the Temporal benchmark runner.
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"go.temporal.io/sdk/client"

	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/config"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/metrics"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/runner"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigCh
		log.Printf("Received signal %v, initiating graceful shutdown...", sig)
		cancel()
	}()

	if err := run(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	log.Println("Temporal Benchmark Runner starting...")

	// Parse configuration from environment variables
	cfg, err := config.LoadFromEnv()
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}

	// Validate configuration
	if err := cfg.Validate(); err != nil {
		return fmt.Errorf("invalid configuration: %w", err)
	}

	log.Printf("Configuration loaded:")
	log.Printf("  Workflow Type: %s", cfg.WorkflowType)
	log.Printf("  Target Rate: %.2f workflows/sec", cfg.TargetRate)
	log.Printf("  Duration: %v", cfg.Duration)
	log.Printf("  Ramp-up: %v", cfg.RampUpDuration)
	log.Printf("  Worker Count: %d", cfg.WorkerCount)
	log.Printf("  Iterations: %d", cfg.Iterations)
	log.Printf("  Temporal Address: %s", cfg.TemporalAddress)

	// Check for early cancellation before connecting
	select {
	case <-ctx.Done():
		log.Println("Shutdown requested before initialization completed")
		return nil
	default:
	}

	// Create metrics handler with SDK metrics integration
	metricsHandler := metrics.NewHandler()

	// Create Temporal client with SDK metrics
	log.Printf("Connecting to Temporal at %s...", cfg.TemporalAddress)
	temporalClient, err := client.Dial(client.Options{
		HostPort:       cfg.TemporalAddress,
		MetricsHandler: metrics.SDKMetricsHandler(metricsHandler.Registry()),
	})
	if err != nil {
		return fmt.Errorf("failed to connect to Temporal cluster at %s: %w (cluster may be unhealthy)", cfg.TemporalAddress, err)
	}
	defer temporalClient.Close()

	// Verify cluster health by checking system info
	log.Println("Verifying Temporal cluster health...")
	_, err = temporalClient.CheckHealth(ctx, nil)
	if err != nil {
		return fmt.Errorf("Temporal cluster health check failed: %w", err)
	}
	log.Println("Temporal cluster is healthy")

	// Check for cancellation after health check
	select {
	case <-ctx.Done():
		log.Println("Shutdown requested after health check")
		return nil
	default:
	}

	// Create benchmark runner with metrics handler and host port
	benchmarkRunner := runner.NewRunner(
		temporalClient,
		runner.WithMetricsHandler(metricsHandler),
		runner.WithHostPort(cfg.TemporalAddress),
	)

	// Run the benchmark
	log.Println("Starting benchmark execution...")
	result, err := benchmarkRunner.Run(ctx, cfg)
	if err != nil {
		// Check if it was a cancellation
		if ctx.Err() != nil {
			log.Println("Benchmark was cancelled")
			return nil
		}
		return fmt.Errorf("benchmark execution failed: %w", err)
	}

	// Get the namespace used for cleanup
	namespace := benchmarkRunner.GetNamespace()

	// Output results
	if err := runner.OutputResults(result, cfg, namespace); err != nil {
		log.Printf("Warning: failed to output results: %v", err)
	}

	// Cleanup benchmark workflows
	log.Println("Cleaning up benchmark workflows...")
	if err := benchmarkRunner.Cleanup(ctx, namespace); err != nil {
		log.Printf("Warning: cleanup failed: %v", err)
		log.Printf("Manual cleanup may be required for namespace: %s", namespace)
	} else {
		log.Println("Cleanup completed successfully")
	}

	log.Println("Benchmark runner completed")
	return nil
}
