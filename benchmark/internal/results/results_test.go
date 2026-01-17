// Package results provides result reporting and serialization.
package results

import (
	"bytes"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/temporalio/temporal-dsql-deploy-ecs/benchmark/internal/config"
)

func TestBenchmarkResultJSON_ToJSON(t *testing.T) {
	result := &BenchmarkResultJSON{
		Timestamp: time.Date(2026, 1, 13, 20, 0, 0, 0, time.UTC),
		Config: ResultConfig{
			WorkflowType: "simple",
			TargetRate:   100,
			Duration:     "5m0s",
			WorkerCount:  4,
			Iterations:   1,
		},
		Results: ResultMetrics{
			WorkflowsStarted:   30000,
			WorkflowsCompleted: 29950,
			WorkflowsFailed:    50,
			ActualRate:         99.83,
			Latency: ResultLatency{
				P50: 45.2,
				P95: 120.5,
				P99: 250.3,
				Max: 1250.0,
			},
		},
		System: ResultSystem{
			InstanceType:  "m7g.large",
			HistoryShards: 4,
			Services:      map[string]int{"frontend": 1, "history": 1, "matching": 1, "worker": 1},
		},
		Thresholds: ResultThresholds{
			MaxP99LatencyMs: 5000,
			MinThroughput:   50,
		},
		Passed:         true,
		FailureReasons: []string{},
	}

	jsonBytes, err := result.ToJSON()
	require.NoError(t, err)
	require.NotEmpty(t, jsonBytes)

	// Verify it's valid JSON
	var parsed map[string]interface{}
	err = json.Unmarshal(jsonBytes, &parsed)
	require.NoError(t, err)

	// Verify required fields exist
	require.Contains(t, parsed, "timestamp")
	require.Contains(t, parsed, "config")
	require.Contains(t, parsed, "results")
	require.Contains(t, parsed, "system")
	require.Contains(t, parsed, "passed")
	require.Contains(t, parsed, "failureReasons")
	require.Contains(t, parsed, "thresholds")
}

func TestBenchmarkResultJSON_WriteJSON(t *testing.T) {
	result := &BenchmarkResultJSON{
		Timestamp: time.Date(2026, 1, 13, 20, 0, 0, 0, time.UTC),
		Config: ResultConfig{
			WorkflowType: "simple",
			TargetRate:   100,
			Duration:     "5m0s",
			WorkerCount:  4,
			Iterations:   1,
		},
		Results: ResultMetrics{
			WorkflowsStarted:   1000,
			WorkflowsCompleted: 1000,
			WorkflowsFailed:    0,
			ActualRate:         100.0,
			Latency: ResultLatency{
				P50: 10.0,
				P95: 50.0,
				P99: 100.0,
				Max: 200.0,
			},
		},
		System: ResultSystem{
			InstanceType:  "m7g.large",
			HistoryShards: 4,
			Services:      map[string]int{"frontend": 1, "history": 1},
		},
		Thresholds: ResultThresholds{
			MaxP99LatencyMs: 5000,
			MinThroughput:   50,
		},
		Passed:         true,
		FailureReasons: []string{},
	}

	var buf bytes.Buffer
	err := result.WriteJSON(&buf)
	require.NoError(t, err)
	require.NotEmpty(t, buf.String())

	// Verify it's valid JSON
	var parsed BenchmarkResultJSON
	err = json.Unmarshal(buf.Bytes(), &parsed)
	require.NoError(t, err)
	require.Equal(t, result.Config.WorkflowType, parsed.Config.WorkflowType)
}

func TestFromJSON(t *testing.T) {
	jsonStr := `{
		"timestamp": "2026-01-13T20:00:00Z",
		"config": {
			"workflowType": "simple",
			"targetRate": 100,
			"duration": "5m0s",
			"workerCount": 4,
			"iterations": 1
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
			"services": {"frontend": 1, "history": 1}
		},
		"thresholds": {
			"maxP99LatencyMs": 5000,
			"minThroughput": 50
		},
		"passed": true,
		"failureReasons": []
	}`

	result, err := FromJSON([]byte(jsonStr))
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, "simple", result.Config.WorkflowType)
	require.Equal(t, float64(100), result.Config.TargetRate)
	require.Equal(t, int64(30000), result.Results.WorkflowsStarted)
	require.Equal(t, 45.2, result.Results.Latency.P50)
	require.True(t, result.Passed)
}

func TestNewBenchmarkResultJSON(t *testing.T) {
	cfg := config.BenchmarkConfig{
		WorkflowType:   config.WorkflowTypeMultiActivity,
		ActivityCount:  10,
		TargetRate:     100,
		Duration:       5 * time.Minute,
		RampUpDuration: 30 * time.Second,
		WorkerCount:    4,
		Iterations:     1,
		MaxP99Latency:  5 * time.Second,
		MinThroughput:  50,
	}

	internalResult := &BenchmarkResult{
		StartTime:          time.Date(2026, 1, 13, 20, 0, 0, 0, time.UTC),
		EndTime:            time.Date(2026, 1, 13, 20, 5, 0, 0, time.UTC),
		Duration:           5 * time.Minute,
		WorkflowsStarted:   30000,
		WorkflowsCompleted: 29950,
		WorkflowsFailed:    50,
		ActualRate:         99.83,
		LatencyP50:         45.2,
		LatencyP95:         120.5,
		LatencyP99:         250.3,
		LatencyMax:         1250.0,
		InstanceType:       "m7g.large",
		ServiceCounts:      map[string]int{"frontend": 1, "history": 1, "matching": 1, "worker": 1},
		HistoryShards:      4,
		Passed:             true,
		FailureReasons:     []string{},
	}

	jsonResult := NewBenchmarkResultJSON(internalResult, cfg, "benchmark-123")

	require.Equal(t, "multi-activity", jsonResult.Config.WorkflowType)
	require.Equal(t, 10, jsonResult.Config.ActivityCount)
	require.Equal(t, "5m0s", jsonResult.Config.Duration)
	require.Equal(t, "benchmark-123", jsonResult.Config.Namespace)
	require.Equal(t, int64(30000), jsonResult.Results.WorkflowsStarted)
	require.Equal(t, 45.2, jsonResult.Results.Latency.P50)
	require.Equal(t, "m7g.large", jsonResult.System.InstanceType)
	require.Equal(t, float64(5000), jsonResult.Thresholds.MaxP99LatencyMs)
	require.True(t, jsonResult.Passed)
}

func TestNewBenchmarkResultJSON_TimerWorkflow(t *testing.T) {
	cfg := config.BenchmarkConfig{
		WorkflowType:   config.WorkflowTypeTimer,
		TimerDuration:  2 * time.Second,
		TargetRate:     50,
		Duration:       1 * time.Minute,
		RampUpDuration: 10 * time.Second,
		WorkerCount:    2,
		Iterations:     1,
		MaxP99Latency:  10 * time.Second,
		MinThroughput:  25,
	}

	internalResult := &BenchmarkResult{
		StartTime:          time.Now(),
		EndTime:            time.Now().Add(time.Minute),
		Duration:           time.Minute,
		WorkflowsStarted:   3000,
		WorkflowsCompleted: 3000,
		WorkflowsFailed:    0,
		ActualRate:         50.0,
		LatencyP50:         2100.0,
		LatencyP95:         2200.0,
		LatencyP99:         2300.0,
		LatencyMax:         2500.0,
		InstanceType:       "m7g.large",
		ServiceCounts:      map[string]int{"frontend": 1, "history": 1},
		HistoryShards:      4,
		Passed:             true,
		FailureReasons:     []string{},
	}

	jsonResult := NewBenchmarkResultJSON(internalResult, cfg, "benchmark-timer")

	require.Equal(t, "timer", jsonResult.Config.WorkflowType)
	require.Equal(t, "2s", jsonResult.Config.TimerDuration)
	require.Equal(t, 0, jsonResult.Config.ActivityCount) // Should be zero for timer workflow
}

func TestNewBenchmarkResultJSON_ChildWorkflow(t *testing.T) {
	cfg := config.BenchmarkConfig{
		WorkflowType:   config.WorkflowTypeChildWorkflow,
		ChildCount:     5,
		TargetRate:     20,
		Duration:       1 * time.Minute,
		RampUpDuration: 10 * time.Second,
		WorkerCount:    2,
		Iterations:     1,
		MaxP99Latency:  10 * time.Second,
		MinThroughput:  10,
	}

	internalResult := &BenchmarkResult{
		StartTime:          time.Now(),
		EndTime:            time.Now().Add(time.Minute),
		Duration:           time.Minute,
		WorkflowsStarted:   1200,
		WorkflowsCompleted: 1200,
		WorkflowsFailed:    0,
		ActualRate:         20.0,
		LatencyP50:         500.0,
		LatencyP95:         800.0,
		LatencyP99:         1000.0,
		LatencyMax:         1500.0,
		InstanceType:       "m7g.large",
		ServiceCounts:      map[string]int{"frontend": 1, "history": 1},
		HistoryShards:      4,
		Passed:             true,
		FailureReasons:     []string{},
	}

	jsonResult := NewBenchmarkResultJSON(internalResult, cfg, "benchmark-child")

	require.Equal(t, "child-workflow", jsonResult.Config.WorkflowType)
	require.Equal(t, 5, jsonResult.Config.ChildCount)
	require.Equal(t, 0, jsonResult.Config.ActivityCount) // Should be zero for child workflow
}

func TestBenchmarkResultJSON_Validate(t *testing.T) {
	tests := []struct {
		name    string
		result  *BenchmarkResultJSON
		wantErr bool
		errMsg  string
	}{
		{
			name: "valid result",
			result: &BenchmarkResultJSON{
				Timestamp: time.Now(),
				Config: ResultConfig{
					WorkflowType: "simple",
					Duration:     "5m0s",
				},
				System: ResultSystem{
					InstanceType: "m7g.large",
					Services:     map[string]int{"frontend": 1},
				},
				FailureReasons: []string{},
			},
			wantErr: false,
		},
		{
			name: "missing timestamp",
			result: &BenchmarkResultJSON{
				Config: ResultConfig{
					WorkflowType: "simple",
					Duration:     "5m0s",
				},
				System: ResultSystem{
					InstanceType: "m7g.large",
					Services:     map[string]int{"frontend": 1},
				},
				FailureReasons: []string{},
			},
			wantErr: true,
			errMsg:  "timestamp is required",
		},
		{
			name: "missing workflow type",
			result: &BenchmarkResultJSON{
				Timestamp: time.Now(),
				Config: ResultConfig{
					Duration: "5m0s",
				},
				System: ResultSystem{
					InstanceType: "m7g.large",
					Services:     map[string]int{"frontend": 1},
				},
				FailureReasons: []string{},
			},
			wantErr: true,
			errMsg:  "config.workflowType is required",
		},
		{
			name: "missing duration",
			result: &BenchmarkResultJSON{
				Timestamp: time.Now(),
				Config: ResultConfig{
					WorkflowType: "simple",
				},
				System: ResultSystem{
					InstanceType: "m7g.large",
					Services:     map[string]int{"frontend": 1},
				},
				FailureReasons: []string{},
			},
			wantErr: true,
			errMsg:  "config.duration is required",
		},
		{
			name: "missing instance type",
			result: &BenchmarkResultJSON{
				Timestamp: time.Now(),
				Config: ResultConfig{
					WorkflowType: "simple",
					Duration:     "5m0s",
				},
				System: ResultSystem{
					Services: map[string]int{"frontend": 1},
				},
				FailureReasons: []string{},
			},
			wantErr: true,
			errMsg:  "system.instanceType is required",
		},
		{
			name: "nil services",
			result: &BenchmarkResultJSON{
				Timestamp: time.Now(),
				Config: ResultConfig{
					WorkflowType: "simple",
					Duration:     "5m0s",
				},
				System: ResultSystem{
					InstanceType: "m7g.large",
				},
				FailureReasons: []string{},
			},
			wantErr: true,
			errMsg:  "system.services is required",
		},
		{
			name: "nil failure reasons",
			result: &BenchmarkResultJSON{
				Timestamp: time.Now(),
				Config: ResultConfig{
					WorkflowType: "simple",
					Duration:     "5m0s",
				},
				System: ResultSystem{
					InstanceType: "m7g.large",
					Services:     map[string]int{"frontend": 1},
				},
				FailureReasons: nil,
			},
			wantErr: true,
			errMsg:  "failureReasons must not be nil",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.result.Validate()
			if tt.wantErr {
				require.Error(t, err)
				require.Contains(t, err.Error(), tt.errMsg)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestFromJSON_InvalidJSON(t *testing.T) {
	_, err := FromJSON([]byte("invalid json"))
	require.Error(t, err)
	require.Contains(t, err.Error(), "failed to unmarshal")
}

func TestNewBenchmarkResultJSON_NilServiceCounts(t *testing.T) {
	cfg := config.BenchmarkConfig{
		WorkflowType:   config.WorkflowTypeSimple,
		TargetRate:     100,
		Duration:       5 * time.Minute,
		RampUpDuration: 30 * time.Second,
		WorkerCount:    4,
		Iterations:     1,
		MaxP99Latency:  5 * time.Second,
		MinThroughput:  50,
	}

	internalResult := &BenchmarkResult{
		StartTime:          time.Now(),
		EndTime:            time.Now().Add(5 * time.Minute),
		Duration:           5 * time.Minute,
		WorkflowsStarted:   30000,
		WorkflowsCompleted: 30000,
		WorkflowsFailed:    0,
		ActualRate:         100.0,
		LatencyP50:         45.2,
		LatencyP95:         120.5,
		LatencyP99:         250.3,
		LatencyMax:         1250.0,
		InstanceType:       "m7g.large",
		ServiceCounts:      nil, // nil service counts
		HistoryShards:      4,
		Passed:             true,
		FailureReasons:     []string{},
	}

	jsonResult := NewBenchmarkResultJSON(internalResult, cfg, "benchmark-123")

	// Should have default service counts
	require.NotNil(t, jsonResult.System.Services)
	require.Equal(t, 1, jsonResult.System.Services["frontend"])
	require.Equal(t, 1, jsonResult.System.Services["history"])
	require.Equal(t, 1, jsonResult.System.Services["matching"])
	require.Equal(t, 1, jsonResult.System.Services["worker"])
}

func TestEvaluateThresholds_Pass(t *testing.T) {
	result := &BenchmarkResult{
		LatencyP99: 100.0, // 100ms
		ActualRate: 100.0, // 100 workflows/s
	}

	// Thresholds: max p99 = 200ms, min throughput = 50/s
	EvaluateThresholds(result, 200.0, 50.0)

	require.True(t, result.Passed)
	require.Empty(t, result.FailureReasons)
}

func TestEvaluateThresholds_FailLatency(t *testing.T) {
	result := &BenchmarkResult{
		LatencyP99: 300.0, // 300ms - exceeds threshold
		ActualRate: 100.0, // 100 workflows/s - meets threshold
	}

	// Thresholds: max p99 = 200ms, min throughput = 50/s
	EvaluateThresholds(result, 200.0, 50.0)

	require.False(t, result.Passed)
	require.Len(t, result.FailureReasons, 1)
	require.Contains(t, result.FailureReasons[0], "p99 latency")
	require.Contains(t, result.FailureReasons[0], "exceeds threshold")
}

func TestEvaluateThresholds_FailThroughput(t *testing.T) {
	result := &BenchmarkResult{
		LatencyP99: 100.0, // 100ms - meets threshold
		ActualRate: 30.0,  // 30 workflows/s - below threshold
	}

	// Thresholds: max p99 = 200ms, min throughput = 50/s
	EvaluateThresholds(result, 200.0, 50.0)

	require.False(t, result.Passed)
	require.Len(t, result.FailureReasons, 1)
	require.Contains(t, result.FailureReasons[0], "throughput")
	require.Contains(t, result.FailureReasons[0], "below threshold")
}

func TestEvaluateThresholds_FailBoth(t *testing.T) {
	result := &BenchmarkResult{
		LatencyP99: 300.0, // 300ms - exceeds threshold
		ActualRate: 30.0,  // 30 workflows/s - below threshold
	}

	// Thresholds: max p99 = 200ms, min throughput = 50/s
	EvaluateThresholds(result, 200.0, 50.0)

	require.False(t, result.Passed)
	require.Len(t, result.FailureReasons, 2)
	require.Contains(t, result.FailureReasons[0], "p99 latency")
	require.Contains(t, result.FailureReasons[1], "throughput")
}

func TestEvaluateThresholds_ExactlyAtThreshold(t *testing.T) {
	result := &BenchmarkResult{
		LatencyP99: 200.0, // Exactly at threshold
		ActualRate: 50.0,  // Exactly at threshold
	}

	// Thresholds: max p99 = 200ms, min throughput = 50/s
	EvaluateThresholds(result, 200.0, 50.0)

	// At threshold should pass (not exceed, not below)
	require.True(t, result.Passed)
	require.Empty(t, result.FailureReasons)
}

func TestEvaluateThresholdsWithConfig(t *testing.T) {
	cfg := config.BenchmarkConfig{
		MaxP99Latency: 5 * time.Second, // 5000ms
		MinThroughput: 50.0,
	}

	result := &BenchmarkResult{
		LatencyP99: 4000.0, // 4000ms - within threshold
		ActualRate: 60.0,   // 60/s - above threshold
	}

	EvaluateThresholdsWithConfig(result, cfg)

	require.True(t, result.Passed)
	require.Empty(t, result.FailureReasons)
}

func TestCheckThresholds_Pass(t *testing.T) {
	passed, reasons := CheckThresholds(100.0, 100.0, 200.0, 50.0)
	require.True(t, passed)
	require.Empty(t, reasons)
}

func TestCheckThresholds_FailLatency(t *testing.T) {
	passed, reasons := CheckThresholds(300.0, 100.0, 200.0, 50.0)
	require.False(t, passed)
	require.Len(t, reasons, 1)
	require.Contains(t, reasons[0], "p99 latency")
}

func TestCheckThresholds_FailThroughput(t *testing.T) {
	passed, reasons := CheckThresholds(100.0, 30.0, 200.0, 50.0)
	require.False(t, passed)
	require.Len(t, reasons, 1)
	require.Contains(t, reasons[0], "throughput")
}

func TestCheckThresholds_FailBoth(t *testing.T) {
	passed, reasons := CheckThresholds(300.0, 30.0, 200.0, 50.0)
	require.False(t, passed)
	require.Len(t, reasons, 2)
}

func TestPrintSummary_Passed(t *testing.T) {
	result := &BenchmarkResultJSON{
		Timestamp: time.Date(2026, 1, 13, 20, 0, 0, 0, time.UTC),
		Config: ResultConfig{
			WorkflowType: "simple",
			TargetRate:   100,
			Duration:     "5m0s",
			WorkerCount:  4,
			Iterations:   1,
			Namespace:    "benchmark-123",
		},
		Results: ResultMetrics{
			WorkflowsStarted:   30000,
			WorkflowsCompleted: 29950,
			WorkflowsFailed:    50,
			ActualRate:         99.83,
			Latency: ResultLatency{
				P50: 45.2,
				P95: 120.5,
				P99: 250.3,
				Max: 1250.0,
			},
		},
		System: ResultSystem{
			InstanceType:  "m7g.large",
			HistoryShards: 4,
			Services:      map[string]int{"frontend": 1, "history": 1, "matching": 1, "worker": 1},
		},
		Thresholds: ResultThresholds{
			MaxP99LatencyMs: 5000,
			MinThroughput:   50,
		},
		Passed:         true,
		FailureReasons: []string{},
	}

	var buf bytes.Buffer
	result.PrintSummary(&buf)
	summary := buf.String()

	// Verify key sections are present
	require.Contains(t, summary, "BENCHMARK RESULTS SUMMARY")
	require.Contains(t, summary, "CONFIGURATION")
	require.Contains(t, summary, "RESULTS")
	require.Contains(t, summary, "LATENCY")
	require.Contains(t, summary, "THRESHOLDS")
	require.Contains(t, summary, "SYSTEM")

	// Verify key values are present
	require.Contains(t, summary, "simple")
	require.Contains(t, summary, "100.00 workflows/s")
	require.Contains(t, summary, "5m0s")
	require.Contains(t, summary, "30000")
	require.Contains(t, summary, "29950")
	require.Contains(t, summary, "99.83")
	require.Contains(t, summary, "45.20")
	require.Contains(t, summary, "250.30")
	require.Contains(t, summary, "m7g.large")
	require.Contains(t, summary, "benchmark-123")

	// Verify pass status
	require.Contains(t, summary, "PASSED")
	require.NotContains(t, summary, "FAILED")
}

func TestPrintSummary_Failed(t *testing.T) {
	result := &BenchmarkResultJSON{
		Timestamp: time.Date(2026, 1, 13, 20, 0, 0, 0, time.UTC),
		Config: ResultConfig{
			WorkflowType: "simple",
			TargetRate:   100,
			Duration:     "5m0s",
			WorkerCount:  4,
			Iterations:   1,
		},
		Results: ResultMetrics{
			WorkflowsStarted:   30000,
			WorkflowsCompleted: 29950,
			WorkflowsFailed:    50,
			ActualRate:         40.0, // Below threshold
			Latency: ResultLatency{
				P50: 45.2,
				P95: 120.5,
				P99: 6000.0, // Above threshold
				Max: 10000.0,
			},
		},
		System: ResultSystem{
			InstanceType:  "m7g.large",
			HistoryShards: 4,
			Services:      map[string]int{"frontend": 1, "history": 1},
		},
		Thresholds: ResultThresholds{
			MaxP99LatencyMs: 5000,
			MinThroughput:   50,
		},
		Passed: false,
		FailureReasons: []string{
			"p99 latency 6000.00ms exceeds threshold 5000.00ms",
			"throughput 40.00/s below threshold 50.00/s",
		},
	}

	var buf bytes.Buffer
	result.PrintSummary(&buf)
	summary := buf.String()

	// Verify fail status
	require.Contains(t, summary, "FAILED")
	require.Contains(t, summary, "Failure Reasons")
	require.Contains(t, summary, "p99 latency 6000.00ms exceeds threshold 5000.00ms")
	require.Contains(t, summary, "throughput 40.00/s below threshold 50.00/s")
}

func TestPrintSummary_MultiActivity(t *testing.T) {
	result := &BenchmarkResultJSON{
		Timestamp: time.Now(),
		Config: ResultConfig{
			WorkflowType:  "multi-activity",
			ActivityCount: 10,
			TargetRate:    50,
			Duration:      "1m0s",
			WorkerCount:   2,
			Iterations:    1,
		},
		Results: ResultMetrics{
			WorkflowsStarted:   3000,
			WorkflowsCompleted: 3000,
			WorkflowsFailed:    0,
			ActualRate:         50.0,
			Latency: ResultLatency{
				P50: 100.0,
				P95: 200.0,
				P99: 300.0,
				Max: 500.0,
			},
		},
		System: ResultSystem{
			InstanceType:  "m7g.large",
			HistoryShards: 4,
			Services:      map[string]int{"frontend": 1, "history": 1},
		},
		Thresholds: ResultThresholds{
			MaxP99LatencyMs: 5000,
			MinThroughput:   25,
		},
		Passed:         true,
		FailureReasons: []string{},
	}

	var buf bytes.Buffer
	result.PrintSummary(&buf)
	summary := buf.String()

	require.Contains(t, summary, "multi-activity")
	require.Contains(t, summary, "Activity Count:   10")
}

func TestPrintSummary_Timer(t *testing.T) {
	result := &BenchmarkResultJSON{
		Timestamp: time.Now(),
		Config: ResultConfig{
			WorkflowType:  "timer",
			TimerDuration: "2s",
			TargetRate:    20,
			Duration:      "1m0s",
			WorkerCount:   2,
			Iterations:    1,
		},
		Results: ResultMetrics{
			WorkflowsStarted:   1200,
			WorkflowsCompleted: 1200,
			WorkflowsFailed:    0,
			ActualRate:         20.0,
			Latency: ResultLatency{
				P50: 2100.0,
				P95: 2200.0,
				P99: 2300.0,
				Max: 2500.0,
			},
		},
		System: ResultSystem{
			InstanceType:  "m7g.large",
			HistoryShards: 4,
			Services:      map[string]int{"frontend": 1, "history": 1},
		},
		Thresholds: ResultThresholds{
			MaxP99LatencyMs: 5000,
			MinThroughput:   10,
		},
		Passed:         true,
		FailureReasons: []string{},
	}

	var buf bytes.Buffer
	result.PrintSummary(&buf)
	summary := buf.String()

	require.Contains(t, summary, "timer")
	require.Contains(t, summary, "Timer Duration:   2s")
}

func TestPrintSummary_ChildWorkflow(t *testing.T) {
	result := &BenchmarkResultJSON{
		Timestamp: time.Now(),
		Config: ResultConfig{
			WorkflowType: "child-workflow",
			ChildCount:   5,
			TargetRate:   10,
			Duration:     "1m0s",
			WorkerCount:  2,
			Iterations:   1,
		},
		Results: ResultMetrics{
			WorkflowsStarted:   600,
			WorkflowsCompleted: 600,
			WorkflowsFailed:    0,
			ActualRate:         10.0,
			Latency: ResultLatency{
				P50: 500.0,
				P95: 800.0,
				P99: 1000.0,
				Max: 1500.0,
			},
		},
		System: ResultSystem{
			InstanceType:  "m7g.large",
			HistoryShards: 4,
			Services:      map[string]int{"frontend": 1, "history": 1},
		},
		Thresholds: ResultThresholds{
			MaxP99LatencyMs: 5000,
			MinThroughput:   5,
		},
		Passed:         true,
		FailureReasons: []string{},
	}

	var buf bytes.Buffer
	result.PrintSummary(&buf)
	summary := buf.String()

	require.Contains(t, summary, "child-workflow")
	require.Contains(t, summary, "Child Count:      5")
}

func TestFormatSummary(t *testing.T) {
	result := &BenchmarkResultJSON{
		Timestamp: time.Date(2026, 1, 13, 20, 0, 0, 0, time.UTC),
		Config: ResultConfig{
			WorkflowType: "simple",
			TargetRate:   100,
			Duration:     "5m0s",
			WorkerCount:  4,
			Iterations:   1,
		},
		Results: ResultMetrics{
			WorkflowsStarted:   30000,
			WorkflowsCompleted: 30000,
			WorkflowsFailed:    0,
			ActualRate:         100.0,
			Latency: ResultLatency{
				P50: 45.2,
				P95: 120.5,
				P99: 250.3,
				Max: 1250.0,
			},
		},
		System: ResultSystem{
			InstanceType:  "m7g.large",
			HistoryShards: 4,
			Services:      map[string]int{"frontend": 1, "history": 1},
		},
		Thresholds: ResultThresholds{
			MaxP99LatencyMs: 5000,
			MinThroughput:   50,
		},
		Passed:         true,
		FailureReasons: []string{},
	}

	summary := result.FormatSummary()
	require.NotEmpty(t, summary)
	require.Contains(t, summary, "BENCHMARK RESULTS SUMMARY")
	require.Contains(t, summary, "PASSED")
}
