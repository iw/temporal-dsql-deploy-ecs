// Package metrics provides Prometheus metrics collection for the benchmark.
package metrics

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"go.temporal.io/sdk/client"
)

// prometheusMetricsHandler implements client.MetricsHandler for Temporal SDK metrics.
// It exposes SDK metrics on the same Prometheus endpoint as benchmark metrics.
type prometheusMetricsHandler struct {
	registry *prometheus.Registry
	tags     map[string]string

	// SDK metrics - these match the Temporal SDK metric names
	// Requirement 3.1.2: temporal_request_latency
	requestLatency *prometheus.HistogramVec

	// Requirement 3.1.3: temporal_workflow_task_schedule_to_start_latency
	workflowTaskScheduleToStartLatency *prometheus.HistogramVec

	// Requirement 3.1.4: temporal_activity_task_schedule_to_start_latency
	activityTaskScheduleToStartLatency *prometheus.HistogramVec

	// Requirement 3.1.5: temporal_workflow_endtoend_latency
	workflowEndToEndLatency *prometheus.HistogramVec

	// Requirement 3.1.6: temporal_long_request
	longRequest *prometheus.CounterVec

	// Requirement 3.1.7: temporal_request_failure
	requestFailure *prometheus.CounterVec
}

// NewPrometheusMetricsHandler creates a new Temporal SDK metrics handler.
// It registers SDK metrics with the provided Prometheus registry.
func NewPrometheusMetricsHandler(registry *prometheus.Registry) client.MetricsHandler {
	h := &prometheusMetricsHandler{
		registry: registry,
		tags:     make(map[string]string),
	}

	// Requirement 3.1.2: temporal_request_latency for all Temporal API calls
	h.requestLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_request_latency_seconds",
		Help:    "Latency of Temporal API requests in seconds",
		Buckets: prometheus.ExponentialBuckets(0.001, 2, 15), // 1ms to ~16s
	}, []string{"operation", "namespace"})

	// Requirement 3.1.3: temporal_workflow_task_schedule_to_start_latency
	h.workflowTaskScheduleToStartLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_workflow_task_schedule_to_start_latency_seconds",
		Help:    "Time from workflow task scheduling to start in seconds",
		Buckets: prometheus.ExponentialBuckets(0.001, 2, 15),
	}, []string{"namespace", "task_queue"})

	// Requirement 3.1.4: temporal_activity_task_schedule_to_start_latency
	h.activityTaskScheduleToStartLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_activity_task_schedule_to_start_latency_seconds",
		Help:    "Time from activity task scheduling to start in seconds",
		Buckets: prometheus.ExponentialBuckets(0.001, 2, 15),
	}, []string{"namespace", "task_queue"})

	// Requirement 3.1.5: temporal_workflow_endtoend_latency
	h.workflowEndToEndLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_workflow_endtoend_latency_seconds",
		Help:    "End-to-end workflow execution latency in seconds",
		Buckets: prometheus.ExponentialBuckets(0.001, 2, 20), // 1ms to ~500s
	}, []string{"namespace", "workflow_type"})

	// Requirement 3.1.6: temporal_long_request for requests exceeding thresholds
	h.longRequest = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "temporal_long_request_total",
		Help: "Count of long-running Temporal requests",
	}, []string{"operation", "namespace"})

	// Requirement 3.1.7: temporal_request_failure with failure type labels
	h.requestFailure = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "temporal_request_failure_total",
		Help: "Count of failed Temporal requests by failure type",
	}, []string{"operation", "namespace", "failure_type"})

	// Register all metrics
	registry.MustRegister(h.requestLatency)
	registry.MustRegister(h.workflowTaskScheduleToStartLatency)
	registry.MustRegister(h.activityTaskScheduleToStartLatency)
	registry.MustRegister(h.workflowEndToEndLatency)
	registry.MustRegister(h.longRequest)
	registry.MustRegister(h.requestFailure)

	return h
}

// WithTags returns a new handler with the given tags.
// This is part of the client.MetricsHandler interface.
func (h *prometheusMetricsHandler) WithTags(tags map[string]string) client.MetricsHandler {
	// Create a new handler with merged tags
	newTags := make(map[string]string)
	for k, v := range h.tags {
		newTags[k] = v
	}
	for k, v := range tags {
		newTags[k] = v
	}

	return &prometheusMetricsHandler{
		registry:                           h.registry,
		tags:                               newTags,
		requestLatency:                     h.requestLatency,
		workflowTaskScheduleToStartLatency: h.workflowTaskScheduleToStartLatency,
		activityTaskScheduleToStartLatency: h.activityTaskScheduleToStartLatency,
		workflowEndToEndLatency:            h.workflowEndToEndLatency,
		longRequest:                        h.longRequest,
		requestFailure:                     h.requestFailure,
	}
}

// Counter returns a counter for the given name.
// This is part of the client.MetricsHandler interface.
func (h *prometheusMetricsHandler) Counter(name string) client.MetricsCounter {
	return &prometheusCounter{
		handler: h,
		name:    name,
		tags:    h.tags,
	}
}

// Gauge returns a gauge for the given name.
// This is part of the client.MetricsHandler interface.
func (h *prometheusMetricsHandler) Gauge(name string) client.MetricsGauge {
	return &prometheusGauge{
		handler: h,
		name:    name,
		tags:    h.tags,
	}
}

// Timer returns a timer for the given name.
// This is part of the client.MetricsHandler interface.
func (h *prometheusMetricsHandler) Timer(name string) client.MetricsTimer {
	return &prometheusTimer{
		handler: h,
		name:    name,
		tags:    h.tags,
	}
}

// prometheusCounter implements client.MetricsCounter.
type prometheusCounter struct {
	handler *prometheusMetricsHandler
	name    string
	tags    map[string]string
}

func (c *prometheusCounter) Inc(delta int64) {
	namespace := c.getTag("namespace", "default")
	operation := c.getTag("operation", "unknown")

	switch c.name {
	case "temporal_long_request":
		c.handler.longRequest.WithLabelValues(operation, namespace).Add(float64(delta))
	case "temporal_request_failure":
		failureType := c.getTag("failure_type", "unknown")
		c.handler.requestFailure.WithLabelValues(operation, namespace, failureType).Add(float64(delta))
	}
}

func (c *prometheusCounter) getTag(key, defaultValue string) string {
	if c.tags != nil {
		if v, ok := c.tags[key]; ok {
			return v
		}
	}
	return defaultValue
}

// prometheusGauge implements client.MetricsGauge.
type prometheusGauge struct {
	handler *prometheusMetricsHandler
	name    string
	tags    map[string]string
}

func (g *prometheusGauge) Update(value float64) {
	// SDK gauges are not currently used in our metrics
}

// prometheusTimer implements client.MetricsTimer.
type prometheusTimer struct {
	handler *prometheusMetricsHandler
	name    string
	tags    map[string]string
}

func (t *prometheusTimer) Record(duration time.Duration) {
	namespace := t.getTag("namespace", "default")
	operation := t.getTag("operation", "unknown")
	taskQueue := t.getTag("task_queue", "default")
	workflowType := t.getTag("workflow_type", "unknown")
	seconds := duration.Seconds()

	switch t.name {
	case "temporal_request_latency", "temporal_request":
		t.handler.requestLatency.WithLabelValues(operation, namespace).Observe(seconds)
		// Check for long requests (> 1 second threshold)
		if seconds > 1.0 {
			t.handler.longRequest.WithLabelValues(operation, namespace).Inc()
		}
	case "temporal_workflow_task_schedule_to_start_latency", "workflow_task_schedule_to_start_latency":
		t.handler.workflowTaskScheduleToStartLatency.WithLabelValues(namespace, taskQueue).Observe(seconds)
	case "temporal_activity_task_schedule_to_start_latency", "activity_task_schedule_to_start_latency":
		t.handler.activityTaskScheduleToStartLatency.WithLabelValues(namespace, taskQueue).Observe(seconds)
	case "temporal_workflow_endtoend_latency", "workflow_endtoend_latency":
		t.handler.workflowEndToEndLatency.WithLabelValues(namespace, workflowType).Observe(seconds)
	}
}

func (t *prometheusTimer) getTag(key, defaultValue string) string {
	if t.tags != nil {
		if v, ok := t.tags[key]; ok {
			return v
		}
	}
	return defaultValue
}
