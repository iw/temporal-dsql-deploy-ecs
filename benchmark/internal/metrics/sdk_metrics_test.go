package metrics

import (
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/stretchr/testify/require"
)

func TestNewPrometheusMetricsHandler(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := NewPrometheusMetricsHandler(registry)
	require.NotNil(t, handler)
}

func TestPrometheusMetricsHandler_WithTags(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := NewPrometheusMetricsHandler(registry)

	// Create handler with tags
	taggedHandler := handler.WithTags(map[string]string{
		"namespace": "test-namespace",
		"operation": "StartWorkflow",
	})
	require.NotNil(t, taggedHandler)

	// Verify it's a different handler instance
	require.NotSame(t, handler, taggedHandler)
}

func TestPrometheusMetricsHandler_Counter(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := NewPrometheusMetricsHandler(registry)

	// Get a counter
	counter := handler.Counter("temporal_request_failure")
	require.NotNil(t, counter)

	// Increment should not panic
	counter.Inc(1)
}

func TestPrometheusMetricsHandler_Timer(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := NewPrometheusMetricsHandler(registry)

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

func TestPrometheusMetricsHandler_LongRequest(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := NewPrometheusMetricsHandler(registry)

	// Get a timer with tags
	taggedHandler := handler.WithTags(map[string]string{
		"namespace": "test-namespace",
		"operation": "StartWorkflow",
	})
	timer := taggedHandler.Timer("temporal_request_latency")

	// Record a long request (> 1 second)
	timer.Record(2 * time.Second)

	// Verify long_request counter was incremented
	// (We can't easily verify the counter value without exposing internals,
	// but we can verify no panic occurred)
}

func TestPrometheusMetricsHandler_Gauge(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := NewPrometheusMetricsHandler(registry)

	// Get a gauge
	gauge := handler.Gauge("some_gauge")
	require.NotNil(t, gauge)

	// Update should not panic
	gauge.Update(42.0)
}

func TestPrometheusMetricsHandler_WorkflowTaskLatency(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := NewPrometheusMetricsHandler(registry)

	taggedHandler := handler.WithTags(map[string]string{
		"namespace":  "test-namespace",
		"task_queue": "test-queue",
	})
	timer := taggedHandler.Timer("workflow_task_schedule_to_start_latency")

	// Record should not panic
	timer.Record(50 * time.Millisecond)
}

func TestPrometheusMetricsHandler_ActivityTaskLatency(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := NewPrometheusMetricsHandler(registry)

	taggedHandler := handler.WithTags(map[string]string{
		"namespace":  "test-namespace",
		"task_queue": "test-queue",
	})
	timer := taggedHandler.Timer("activity_task_schedule_to_start_latency")

	// Record should not panic
	timer.Record(75 * time.Millisecond)
}

func TestPrometheusMetricsHandler_WorkflowEndToEndLatency(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := NewPrometheusMetricsHandler(registry)

	taggedHandler := handler.WithTags(map[string]string{
		"namespace":     "test-namespace",
		"workflow_type": "SimpleWorkflow",
	})
	timer := taggedHandler.Timer("workflow_endtoend_latency")

	// Record should not panic
	timer.Record(500 * time.Millisecond)
}

func TestPrometheusMetricsHandler_RequestFailure(t *testing.T) {
	registry := prometheus.NewRegistry()
	handler := NewPrometheusMetricsHandler(registry)

	taggedHandler := handler.WithTags(map[string]string{
		"namespace":    "test-namespace",
		"operation":    "StartWorkflow",
		"failure_type": "timeout",
	})
	counter := taggedHandler.Counter("temporal_request_failure")

	// Increment should not panic
	counter.Inc(1)
}
