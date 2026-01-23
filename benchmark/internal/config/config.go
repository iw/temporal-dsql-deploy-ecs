// Package config provides configuration parsing for the benchmark runner.
package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

// Valid workflow types
const (
	WorkflowTypeSimple           = "simple"
	WorkflowTypeMultiActivity    = "multi-activity"
	WorkflowTypeTimer            = "timer"
	WorkflowTypeChildWorkflow    = "child-workflow"
	WorkflowTypeStateTransitions = "state-transitions"
)

// Configuration limits
const (
	MinActivityCount = 1
	MaxActivityCount = 100
	MinTargetRate    = 1
	MaxTargetRate    = 1000
	MinDuration      = 1 * time.Minute
	MaxDuration      = 60 * time.Minute
	MinWorkerCount   = 1
	MaxWorkerCount   = 100
	MinIterations    = 1
	MaxIterations    = 100
	MinChildCount    = 1
	MaxChildCount    = 100
)

// BenchmarkConfig defines the benchmark parameters.
type BenchmarkConfig struct {
	// Workflow configuration
	WorkflowType  string        // "simple", "multi-activity", "timer", "child-workflow"
	ActivityCount int           // Number of activities (for multi-activity type)
	TimerDuration time.Duration // Timer duration (for timer type)
	ChildCount    int           // Number of child workflows (for child-workflow type)

	// Load configuration
	TargetRate     float64       // Workflows per second
	Duration       time.Duration // Test duration
	RampUpDuration time.Duration // Ramp-up period
	WorkerCount    int           // Number of parallel workers

	// Execution configuration
	Namespace         string        // Benchmark namespace (auto-generated if empty)
	Iterations        int           // Number of test iterations
	CompletionTimeout time.Duration // Timeout for waiting for workflows to complete after test ends
	GeneratorOnly     bool          // If true, only generate workflows (no embedded worker)
	WorkerOnly        bool          // If true, only run worker (no workflow generation)

	// Thresholds for pass/fail
	MaxP99Latency time.Duration // Maximum acceptable p99 latency
	MinThroughput float64       // Minimum acceptable throughput

	// Temporal connection
	TemporalAddress string // Temporal frontend address
}

// DefaultConfig returns a BenchmarkConfig with default values.
func DefaultConfig() BenchmarkConfig {
	return BenchmarkConfig{
		WorkflowType:      WorkflowTypeSimple,
		ActivityCount:     5,
		TimerDuration:     time.Second,
		ChildCount:        3,
		TargetRate:        100,
		Duration:          5 * time.Minute,
		RampUpDuration:    30 * time.Second,
		WorkerCount:       4,
		Iterations:        1,
		CompletionTimeout: 0, // 0 means auto-calculate based on rate and duration
		MaxP99Latency:     5 * time.Second,
		MinThroughput:     50,
		TemporalAddress:   "temporal-frontend:7233",
	}
}

// LoadFromEnv loads configuration from environment variables.
// It starts with default values and overrides with any set environment variables.
func LoadFromEnv() (BenchmarkConfig, error) {
	cfg := DefaultConfig()

	// Workflow configuration
	if v := os.Getenv("BENCHMARK_WORKFLOW_TYPE"); v != "" {
		cfg.WorkflowType = v
	}

	if v := os.Getenv("BENCHMARK_ACTIVITY_COUNT"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_ACTIVITY_COUNT: %w", err)
		}
		cfg.ActivityCount = n
	}

	if v := os.Getenv("BENCHMARK_TIMER_DURATION"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_TIMER_DURATION: %w", err)
		}
		cfg.TimerDuration = d
	}

	if v := os.Getenv("BENCHMARK_CHILD_COUNT"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_CHILD_COUNT: %w", err)
		}
		cfg.ChildCount = n
	}

	// Load configuration
	if v := os.Getenv("BENCHMARK_TARGET_RATE"); v != "" {
		f, err := strconv.ParseFloat(v, 64)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_TARGET_RATE: %w", err)
		}
		cfg.TargetRate = f
	}

	if v := os.Getenv("BENCHMARK_DURATION"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_DURATION: %w", err)
		}
		cfg.Duration = d
	}

	if v := os.Getenv("BENCHMARK_RAMP_UP"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_RAMP_UP: %w", err)
		}
		cfg.RampUpDuration = d
	}

	if v := os.Getenv("BENCHMARK_WORKER_COUNT"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_WORKER_COUNT: %w", err)
		}
		cfg.WorkerCount = n
	}

	// Execution configuration
	if v := os.Getenv("BENCHMARK_NAMESPACE"); v != "" {
		cfg.Namespace = v
	}

	if v := os.Getenv("BENCHMARK_ITERATIONS"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_ITERATIONS: %w", err)
		}
		cfg.Iterations = n
	}

	// Completion timeout
	if v := os.Getenv("BENCHMARK_COMPLETION_TIMEOUT"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_COMPLETION_TIMEOUT: %w", err)
		}
		cfg.CompletionTimeout = d
	}

	// Mode configuration
	if v := os.Getenv("BENCHMARK_GENERATOR_ONLY"); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_GENERATOR_ONLY: %w", err)
		}
		cfg.GeneratorOnly = b
	}

	if v := os.Getenv("BENCHMARK_WORKER_ONLY"); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_WORKER_ONLY: %w", err)
		}
		cfg.WorkerOnly = b
	}

	// Thresholds
	if v := os.Getenv("BENCHMARK_MAX_P99_LATENCY"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_MAX_P99_LATENCY: %w", err)
		}
		cfg.MaxP99Latency = d
	}

	if v := os.Getenv("BENCHMARK_MIN_THROUGHPUT"); v != "" {
		f, err := strconv.ParseFloat(v, 64)
		if err != nil {
			return cfg, fmt.Errorf("invalid BENCHMARK_MIN_THROUGHPUT: %w", err)
		}
		cfg.MinThroughput = f
	}

	// Temporal connection
	if v := os.Getenv("TEMPORAL_ADDRESS"); v != "" {
		cfg.TemporalAddress = v
	}

	return cfg, nil
}

// Validate checks that the configuration values are within acceptable ranges.
func (c *BenchmarkConfig) Validate() error {
	// Validate workflow type
	switch c.WorkflowType {
	case WorkflowTypeSimple, WorkflowTypeMultiActivity, WorkflowTypeTimer, WorkflowTypeChildWorkflow, WorkflowTypeStateTransitions:
		// valid
	default:
		return fmt.Errorf("invalid workflow type %q: must be one of: simple, multi-activity, timer, child-workflow, state-transitions", c.WorkflowType)
	}

	// Validate activity count
	if c.ActivityCount < MinActivityCount || c.ActivityCount > MaxActivityCount {
		return fmt.Errorf("activity count %d out of range [%d, %d]", c.ActivityCount, MinActivityCount, MaxActivityCount)
	}

	// Validate child count
	if c.ChildCount < MinChildCount || c.ChildCount > MaxChildCount {
		return fmt.Errorf("child count %d out of range [%d, %d]", c.ChildCount, MinChildCount, MaxChildCount)
	}

	// Validate timer duration (must be positive)
	if c.TimerDuration <= 0 {
		return fmt.Errorf("timer duration must be positive, got %v", c.TimerDuration)
	}

	// Validate target rate
	if c.TargetRate < MinTargetRate || c.TargetRate > MaxTargetRate {
		return fmt.Errorf("target rate %.2f out of range [%d, %d]", c.TargetRate, MinTargetRate, MaxTargetRate)
	}

	// Validate duration
	if c.Duration < MinDuration || c.Duration > MaxDuration {
		return fmt.Errorf("duration %v out of range [%v, %v]", c.Duration, MinDuration, MaxDuration)
	}

	// Validate ramp-up duration (must be non-negative and less than total duration)
	if c.RampUpDuration < 0 {
		return fmt.Errorf("ramp-up duration must be non-negative, got %v", c.RampUpDuration)
	}
	if c.RampUpDuration >= c.Duration {
		return fmt.Errorf("ramp-up duration %v must be less than total duration %v", c.RampUpDuration, c.Duration)
	}

	// Validate worker count
	if c.WorkerCount < MinWorkerCount || c.WorkerCount > MaxWorkerCount {
		return fmt.Errorf("worker count %d out of range [%d, %d]", c.WorkerCount, MinWorkerCount, MaxWorkerCount)
	}

	// Validate iterations
	if c.Iterations < MinIterations || c.Iterations > MaxIterations {
		return fmt.Errorf("iterations %d out of range [%d, %d]", c.Iterations, MinIterations, MaxIterations)
	}

	// Validate completion timeout (must be non-negative, 0 means auto-calculate)
	if c.CompletionTimeout < 0 {
		return fmt.Errorf("completion timeout must be non-negative, got %v", c.CompletionTimeout)
	}

	// Validate thresholds (must be positive)
	if c.MaxP99Latency <= 0 {
		return fmt.Errorf("max p99 latency must be positive, got %v", c.MaxP99Latency)
	}
	if c.MinThroughput <= 0 {
		return fmt.Errorf("min throughput must be positive, got %.2f", c.MinThroughput)
	}

	// Validate Temporal address (must not be empty)
	if c.TemporalAddress == "" {
		return fmt.Errorf("temporal address must not be empty")
	}

	return nil
}

// ValidWorkflowTypes returns a list of valid workflow types.
func ValidWorkflowTypes() []string {
	return []string{
		WorkflowTypeSimple,
		WorkflowTypeMultiActivity,
		WorkflowTypeTimer,
		WorkflowTypeChildWorkflow,
		WorkflowTypeStateTransitions,
	}
}
