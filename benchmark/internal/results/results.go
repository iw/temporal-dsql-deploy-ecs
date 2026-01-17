// Package results provides result reporting and serialization.
package results

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"time"

	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/config"
)

// ResultConfig contains the configuration used for the benchmark.
// Requirement 6.5: WHEN results are generated, THE Benchmark_Runner SHALL include
// timestamp and test parameters for reproducibility.
type ResultConfig struct {
	WorkflowType   string  `json:"workflowType"`
	ActivityCount  int     `json:"activityCount,omitempty"`
	TimerDuration  string  `json:"timerDuration,omitempty"`
	ChildCount     int     `json:"childCount,omitempty"`
	TargetRate     float64 `json:"targetRate"`
	Duration       string  `json:"duration"`
	RampUpDuration string  `json:"rampUpDuration,omitempty"`
	WorkerCount    int     `json:"workerCount"`
	Iterations     int     `json:"iterations"`
	Namespace      string  `json:"namespace,omitempty"`
}

// ResultLatency contains latency percentiles in milliseconds.
type ResultLatency struct {
	P50 float64 `json:"p50"`
	P95 float64 `json:"p95"`
	P99 float64 `json:"p99"`
	Max float64 `json:"max"`
}

// ResultMetrics contains the benchmark metrics.
type ResultMetrics struct {
	WorkflowsStarted   int64         `json:"workflowsStarted"`
	WorkflowsCompleted int64         `json:"workflowsCompleted"`
	WorkflowsFailed    int64         `json:"workflowsFailed"`
	ActualRate         float64       `json:"actualRate"`
	Latency            ResultLatency `json:"latency"`
}

// ResultSystem contains system information.
// Requirement 6.3: THE Benchmark_Runner SHALL include system configuration in the results
// (instance types, service counts, shard count).
type ResultSystem struct {
	InstanceType  string         `json:"instanceType"`
	HistoryShards int            `json:"historyShards"`
	Services      map[string]int `json:"services"`
}

// ResultThresholds contains the threshold configuration used for pass/fail evaluation.
type ResultThresholds struct {
	MaxP99LatencyMs float64 `json:"maxP99LatencyMs"`
	MinThroughput   float64 `json:"minThroughput"`
}

// BenchmarkResultJSON is the JSON-serializable benchmark result.
// Requirement 6.1: THE Benchmark_Runner SHALL output results in JSON format for programmatic consumption.
// Requirement 6.5: WHEN results are generated, THE Benchmark_Runner SHALL include
// timestamp and test parameters for reproducibility.
type BenchmarkResultJSON struct {
	Timestamp      time.Time        `json:"timestamp"`
	Config         ResultConfig     `json:"config"`
	Results        ResultMetrics    `json:"results"`
	System         ResultSystem     `json:"system"`
	Thresholds     ResultThresholds `json:"thresholds"`
	Passed         bool             `json:"passed"`
	FailureReasons []string         `json:"failureReasons"`
}

// BenchmarkResult contains the internal benchmark results (used by runner).
type BenchmarkResult struct {
	// Timing
	StartTime time.Time
	EndTime   time.Time
	Duration  time.Duration

	// Throughput
	WorkflowsStarted   int64
	WorkflowsCompleted int64
	WorkflowsFailed    int64
	ActualRate         float64

	// Latency (in milliseconds)
	LatencyP50 float64
	LatencyP95 float64
	LatencyP99 float64
	LatencyMax float64

	// System info
	InstanceType  string
	ServiceCounts map[string]int
	HistoryShards int

	// Pass/Fail
	Passed         bool
	FailureReasons []string
}

// ToJSON serializes the result to JSON bytes.
func (r *BenchmarkResultJSON) ToJSON() ([]byte, error) {
	return json.MarshalIndent(r, "", "  ")
}

// FromJSON deserializes JSON bytes into a BenchmarkResultJSON.
func FromJSON(data []byte) (*BenchmarkResultJSON, error) {
	var result BenchmarkResultJSON
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("failed to unmarshal benchmark result: %w", err)
	}
	return &result, nil
}

// WriteJSON writes the result as JSON to the provided writer.
func (r *BenchmarkResultJSON) WriteJSON(w io.Writer) error {
	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	return encoder.Encode(r)
}

// NewBenchmarkResultJSON creates a JSON-serializable result from internal result and config.
// This converts the internal BenchmarkResult to the JSON format specified in the design document.
func NewBenchmarkResultJSON(result *BenchmarkResult, cfg config.BenchmarkConfig, namespace string) *BenchmarkResultJSON {
	// Build config section with all test parameters for reproducibility
	resultConfig := ResultConfig{
		WorkflowType:   cfg.WorkflowType,
		TargetRate:     cfg.TargetRate,
		Duration:       cfg.Duration.String(),
		WorkerCount:    cfg.WorkerCount,
		Iterations:     cfg.Iterations,
		RampUpDuration: cfg.RampUpDuration.String(),
		Namespace:      namespace,
	}

	// Include workflow-type-specific parameters
	switch cfg.WorkflowType {
	case config.WorkflowTypeMultiActivity:
		resultConfig.ActivityCount = cfg.ActivityCount
	case config.WorkflowTypeTimer:
		resultConfig.TimerDuration = cfg.TimerDuration.String()
	case config.WorkflowTypeChildWorkflow:
		resultConfig.ChildCount = cfg.ChildCount
	}

	// Build system info
	services := result.ServiceCounts
	if services == nil {
		services = map[string]int{
			"frontend": 1,
			"history":  1,
			"matching": 1,
			"worker":   1,
		}
	}

	return &BenchmarkResultJSON{
		Timestamp: result.StartTime,
		Config:    resultConfig,
		Results: ResultMetrics{
			WorkflowsStarted:   result.WorkflowsStarted,
			WorkflowsCompleted: result.WorkflowsCompleted,
			WorkflowsFailed:    result.WorkflowsFailed,
			ActualRate:         result.ActualRate,
			Latency: ResultLatency{
				P50: result.LatencyP50,
				P95: result.LatencyP95,
				P99: result.LatencyP99,
				Max: result.LatencyMax,
			},
		},
		System: ResultSystem{
			InstanceType:  result.InstanceType,
			HistoryShards: result.HistoryShards,
			Services:      services,
		},
		Thresholds: ResultThresholds{
			MaxP99LatencyMs: float64(cfg.MaxP99Latency.Milliseconds()),
			MinThroughput:   cfg.MinThroughput,
		},
		Passed:         result.Passed,
		FailureReasons: result.FailureReasons,
	}
}

// Validate checks that the result contains all required fields.
func (r *BenchmarkResultJSON) Validate() error {
	if r.Timestamp.IsZero() {
		return fmt.Errorf("timestamp is required")
	}
	if r.Config.WorkflowType == "" {
		return fmt.Errorf("config.workflowType is required")
	}
	if r.Config.Duration == "" {
		return fmt.Errorf("config.duration is required")
	}
	if r.System.InstanceType == "" {
		return fmt.Errorf("system.instanceType is required")
	}
	if r.System.Services == nil {
		return fmt.Errorf("system.services is required")
	}
	if r.FailureReasons == nil {
		return fmt.Errorf("failureReasons must not be nil (use empty slice)")
	}
	return nil
}

// EvaluateThresholds checks if the result meets the configured thresholds.
// Requirement 6.4: THE Benchmark_Runner SHALL compare results against configurable thresholds
// and report pass/fail.
//
// The logic is:
// - If latencyP99 > maxP99Latency OR actualRate < minThroughput, then passed = false
// - If latencyP99 <= maxP99Latency AND actualRate >= minThroughput, then passed = true
func EvaluateThresholds(result *BenchmarkResult, maxP99LatencyMs float64, minThroughput float64) {
	result.Passed = true
	result.FailureReasons = []string{}

	// Check p99 latency threshold
	// Property 10: If L > M OR T < N, then passed SHALL be false
	if result.LatencyP99 > maxP99LatencyMs {
		result.Passed = false
		result.FailureReasons = append(result.FailureReasons,
			fmt.Sprintf("p99 latency %.2fms exceeds threshold %.2fms", result.LatencyP99, maxP99LatencyMs))
	}

	// Check throughput threshold
	if result.ActualRate < minThroughput {
		result.Passed = false
		result.FailureReasons = append(result.FailureReasons,
			fmt.Sprintf("throughput %.2f/s below threshold %.2f/s", result.ActualRate, minThroughput))
	}
}

// EvaluateThresholdsWithConfig is a convenience function that extracts thresholds from config.
func EvaluateThresholdsWithConfig(result *BenchmarkResult, cfg config.BenchmarkConfig) {
	maxP99LatencyMs := float64(cfg.MaxP99Latency.Milliseconds())
	EvaluateThresholds(result, maxP99LatencyMs, cfg.MinThroughput)
}

// CheckThresholds evaluates thresholds and returns the pass/fail status and reasons.
// This is a pure function that doesn't modify the input, useful for testing.
func CheckThresholds(latencyP99Ms float64, actualRate float64, maxP99LatencyMs float64, minThroughput float64) (passed bool, failureReasons []string) {
	passed = true
	failureReasons = []string{}

	// Check p99 latency threshold
	if latencyP99Ms > maxP99LatencyMs {
		passed = false
		failureReasons = append(failureReasons,
			fmt.Sprintf("p99 latency %.2fms exceeds threshold %.2fms", latencyP99Ms, maxP99LatencyMs))
	}

	// Check throughput threshold
	if actualRate < minThroughput {
		passed = false
		failureReasons = append(failureReasons,
			fmt.Sprintf("throughput %.2f/s below threshold %.2f/s", actualRate, minThroughput))
	}

	return passed, failureReasons
}

// PrintSummary prints a human-readable summary of the benchmark results to the provided writer.
// Requirement 6.2: THE Benchmark_Runner SHALL output a human-readable summary to stdout.
func (r *BenchmarkResultJSON) PrintSummary(w io.Writer) {
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "═══════════════════════════════════════════════════════════════")
	fmt.Fprintln(w, "                    BENCHMARK RESULTS SUMMARY")
	fmt.Fprintln(w, "═══════════════════════════════════════════════════════════════")
	fmt.Fprintln(w, "")

	// Configuration section
	fmt.Fprintln(w, "CONFIGURATION")
	fmt.Fprintln(w, "─────────────────────────────────────────────────────────────────")
	fmt.Fprintf(w, "  Workflow Type:    %s\n", r.Config.WorkflowType)
	fmt.Fprintf(w, "  Target Rate:      %.2f workflows/s\n", r.Config.TargetRate)
	fmt.Fprintf(w, "  Duration:         %s\n", r.Config.Duration)
	fmt.Fprintf(w, "  Worker Count:     %d\n", r.Config.WorkerCount)
	if r.Config.Iterations > 1 {
		fmt.Fprintf(w, "  Iterations:       %d\n", r.Config.Iterations)
	}
	if r.Config.Namespace != "" {
		fmt.Fprintf(w, "  Namespace:        %s\n", r.Config.Namespace)
	}

	// Workflow-type specific config
	switch r.Config.WorkflowType {
	case "multi-activity":
		if r.Config.ActivityCount > 0 {
			fmt.Fprintf(w, "  Activity Count:   %d\n", r.Config.ActivityCount)
		}
	case "timer":
		if r.Config.TimerDuration != "" {
			fmt.Fprintf(w, "  Timer Duration:   %s\n", r.Config.TimerDuration)
		}
	case "child-workflow":
		if r.Config.ChildCount > 0 {
			fmt.Fprintf(w, "  Child Count:      %d\n", r.Config.ChildCount)
		}
	}
	fmt.Fprintln(w, "")

	// Results section
	fmt.Fprintln(w, "RESULTS")
	fmt.Fprintln(w, "─────────────────────────────────────────────────────────────────")
	fmt.Fprintf(w, "  Workflows Started:    %d\n", r.Results.WorkflowsStarted)
	fmt.Fprintf(w, "  Workflows Completed:  %d\n", r.Results.WorkflowsCompleted)
	fmt.Fprintf(w, "  Workflows Failed:     %d\n", r.Results.WorkflowsFailed)
	fmt.Fprintf(w, "  Actual Rate:          %.2f workflows/s\n", r.Results.ActualRate)
	fmt.Fprintln(w, "")

	// Latency section
	fmt.Fprintln(w, "LATENCY (milliseconds)")
	fmt.Fprintln(w, "─────────────────────────────────────────────────────────────────")
	fmt.Fprintf(w, "  P50:    %10.2f ms\n", r.Results.Latency.P50)
	fmt.Fprintf(w, "  P95:    %10.2f ms\n", r.Results.Latency.P95)
	fmt.Fprintf(w, "  P99:    %10.2f ms\n", r.Results.Latency.P99)
	fmt.Fprintf(w, "  Max:    %10.2f ms\n", r.Results.Latency.Max)
	fmt.Fprintln(w, "")

	// Thresholds section
	fmt.Fprintln(w, "THRESHOLDS")
	fmt.Fprintln(w, "─────────────────────────────────────────────────────────────────")
	fmt.Fprintf(w, "  Max P99 Latency:      %.2f ms\n", r.Thresholds.MaxP99LatencyMs)
	fmt.Fprintf(w, "  Min Throughput:       %.2f workflows/s\n", r.Thresholds.MinThroughput)
	fmt.Fprintln(w, "")

	// System info section
	fmt.Fprintln(w, "SYSTEM")
	fmt.Fprintln(w, "─────────────────────────────────────────────────────────────────")
	fmt.Fprintf(w, "  Instance Type:        %s\n", r.System.InstanceType)
	fmt.Fprintf(w, "  History Shards:       %d\n", r.System.HistoryShards)
	if len(r.System.Services) > 0 {
		fmt.Fprint(w, "  Services:             ")
		first := true
		for service, count := range r.System.Services {
			if !first {
				fmt.Fprint(w, ", ")
			}
			fmt.Fprintf(w, "%s=%d", service, count)
			first = false
		}
		fmt.Fprintln(w, "")
	}
	fmt.Fprintln(w, "")

	// Pass/Fail status
	fmt.Fprintln(w, "═══════════════════════════════════════════════════════════════")
	if r.Passed {
		fmt.Fprintln(w, "                         ✓ PASSED")
	} else {
		fmt.Fprintln(w, "                         ✗ FAILED")
		fmt.Fprintln(w, "")
		fmt.Fprintln(w, "  Failure Reasons:")
		for _, reason := range r.FailureReasons {
			fmt.Fprintf(w, "    • %s\n", reason)
		}
	}
	fmt.Fprintln(w, "═══════════════════════════════════════════════════════════════")
	fmt.Fprintln(w, "")
	fmt.Fprintf(w, "  Timestamp: %s\n", r.Timestamp.Format(time.RFC3339))
	fmt.Fprintln(w, "")
}

// FormatSummary returns the human-readable summary as a string.
func (r *BenchmarkResultJSON) FormatSummary() string {
	var buf bytes.Buffer
	r.PrintSummary(&buf)
	return buf.String()
}
