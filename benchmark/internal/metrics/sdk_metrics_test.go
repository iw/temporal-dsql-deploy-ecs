package metrics

import (
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/stretchr/testify/require"
)

func TestSDKMetricsHandler(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)
	require.NotNil(t, handler)
}

func TestSDKMetricsHandler_WithTags(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)

	// Create handler with tags
	taggedHandler := handler.WithTags(map[string]string{
		"namespace": "test-namespace",
		"operation": "StartWorkflow",
	})
	require.NotNil(t, taggedHandler)

	// Verify it's a different handler instance
	require.NotSame(t, handler, taggedHandler)
}

func TestSDKMetricsHandler_Counter(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)

	// Get a counter
	counter := handler.Counter("temporal_request_failure")
	require.NotNil(t, counter)

	// Increment should not panic
	counter.Inc(1)
}

func TestSDKMetricsHandler_Timer(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)

	// Get a timer with tags
	taggedHandler := handler.WithTags(map[string]string{
		"namespace": "test-namespace",
		"operation": "StartWorkflow",
	})
	timer := taggedHandler.Timer("temporal_request_latency")
	require.NotNil(t, timer)

	// Record should not panic
	timer.Record(100 * time.Millisecond)
}

func TestSDKMetricsHandler_LongRequest(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)

	// Get a timer with tags
	taggedHandler := handler.WithTags(map[string]string{
		"namespace": "test-namespace",
		"operation": "StartWorkflow",
	})
	timer := taggedHandler.Timer("temporal_request_latency")

	// Record a long request (> 1 second)
	timer.Record(2 * time.Second)
}

func TestSDKMetricsHandler_Gauge(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)

	// Get a gauge with tags (simulating worker_task_slots)
	taggedHandler := handler.WithTags(map[string]string{
		"worker_type": "WorkflowWorker",
		"task_queue":  "benchmark-task-queue",
	})
	gauge := taggedHandler.Gauge("temporal_worker_task_slots_available")
	require.NotNil(t, gauge)

	// Update should not panic and should record the value
	gauge.Update(42.0)
}

func TestSDKMetricsHandler_GaugeMultipleUpdates(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)

	// Get a gauge with tags
	taggedHandler := handler.WithTags(map[string]string{
		"worker_type": "ActivityWorker",
		"task_queue":  "benchmark-task-queue",
	})
	gauge := taggedHandler.Gauge("temporal_worker_task_slots_used")
	require.NotNil(t, gauge)

	// Multiple updates should work
	gauge.Update(10.0)
	gauge.Update(20.0)
	gauge.Update(15.0)
}

func TestSDKMetricsHandler_WorkflowTaskLatency(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)

	taggedHandler := handler.WithTags(map[string]string{
		"namespace":  "test-namespace",
		"task_queue": "test-queue",
	})
	timer := taggedHandler.Timer("workflow_task_schedule_to_start_latency")

	// Record should not panic
	timer.Record(50 * time.Millisecond)
}

func TestSDKMetricsHandler_ActivityTaskLatency(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)

	taggedHandler := handler.WithTags(map[string]string{
		"namespace":  "test-namespace",
		"task_queue": "test-queue",
	})
	timer := taggedHandler.Timer("activity_task_schedule_to_start_latency")

	// Record should not panic
	timer.Record(75 * time.Millisecond)
}

func TestSDKMetricsHandler_WorkflowEndToEndLatency(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)

	taggedHandler := handler.WithTags(map[string]string{
		"namespace":     "test-namespace",
		"workflow_type": "SimpleWorkflow",
	})
	timer := taggedHandler.Timer("workflow_endtoend_latency")

	// Record should not panic
	timer.Record(500 * time.Millisecond)
}

func TestSDKMetricsHandler_RequestFailure(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := SDKMetricsHandler(registry)

	taggedHandler := handler.WithTags(map[string]string{
		"namespace":    "test-namespace",
		"operation":    "StartWorkflow",
		"failure_type": "timeout",
	})
	counter := taggedHandler.Counter("temporal_request_failure")

	// Increment should not panic
	counter.Inc(1)
}
