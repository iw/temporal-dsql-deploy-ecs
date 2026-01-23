// Package metrics provides Prometheus metrics collection for the benchmark.
package metrics

import (
	"sort"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"go.temporal.io/sdk/client"
)

// SDKMetricsHandler returns a Temporal SDK metrics handler that properly captures
// all SDK metrics including temporal_worker_task_slots_* gauges.
func SDKMetricsHandler(registry *prometheus.Registry) client.MetricsHandler {
	return newPrometheusMetricsHandler(registry)
}

// prometheusMetricsHandler implements client.MetricsHandler for Temporal SDK metrics.
// It exposes SDK metrics on the same Prometheus endpoint as benchmark metrics.
type prometheusMetricsHandler struct {
	registry *prometheus.Registry
	tags     map[string]string

	// Mutex for thread-safe gauge registration
	mu sync.RWMutex

	// Dynamic gauge registry - gauges are created on demand
	gauges map[string]*prometheus.GaugeVec

	// SDK metrics - these match the Temporal SDK metric names
	requestLatency                     *prometheus.HistogramVec
	workflowTaskScheduleToStartLatency *prometheus.HistogramVec
	activityTaskScheduleToStartLatency *prometheus.HistogramVec
	workflowEndToEndLatency            *prometheus.HistogramVec
	longRequest                        *prometheus.CounterVec
	requestFailure                     *prometheus.CounterVec
}

// newPrometheusMetricsHandler creates a new Temporal SDK metrics handler.
func newPrometheusMetricsHandler(registry *prometheus.Registry) client.MetricsHandler {
	h := &prometheusMetricsHandler{
		registry: registry,
		tags:     make(map[string]string),
		gauges:   make(map[string]*prometheus.GaugeVec),
	}

	h.requestLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_request_latency_seconds",
		Help:    "Latency of Temporal API requests in seconds",
		Buckets: prometheus.ExponentialBuckets(0.001, 2, 15),
	}, []string{"operation", "namespace"})

	h.workflowTaskScheduleToStartLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_workflow_task_schedule_to_start_latency_seconds",
		Help:    "Time from workflow task scheduling to start in seconds",
		Buckets: prometheus.ExponentialBuckets(0.001, 2, 15),
	}, []string{"namespace", "task_queue"})

	h.activityTaskScheduleToStartLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_activity_task_schedule_to_start_latency_seconds",
		Help:    "Time from activity task scheduling to start in seconds",
		Buckets: prometheus.ExponentialBuckets(0.001, 2, 15),
	}, []string{"namespace", "task_queue"})

	h.workflowEndToEndLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_workflow_endtoend_latency_seconds",
		Help:    "End-to-end workflow execution latency in seconds",
		Buckets: prometheus.ExponentialBuckets(0.001, 2, 20),
	}, []string{"namespace", "workflow_type"})

	h.longRequest = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "temporal_long_request_total",
		Help: "Count of long-running Temporal requests",
	}, []string{"operation", "namespace"})

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

// getOrCreateGauge returns an existing gauge or creates a new one.
func (h *prometheusMetricsHandler) getOrCreateGauge(name string, labelNames []string) *prometheus.GaugeVec {
	h.mu.RLock()
	if gauge, ok := h.gauges[name]; ok {
		h.mu.RUnlock()
		return gauge
	}
	h.mu.RUnlock()

	h.mu.Lock()
	defer h.mu.Unlock()

	// Double-check after acquiring write lock
	if gauge, ok := h.gauges[name]; ok {
		return gauge
	}

	gauge := prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: name,
		Help: "Temporal SDK gauge: " + name,
	}, labelNames)

	// Try to register, ignore if already registered
	if err := h.registry.Register(gauge); err != nil {
		if existing, ok := h.gauges[name]; ok {
			return existing
		}
	}

	h.gauges[name] = gauge
	return gauge
}

// WithTags returns a new handler with the given tags.
func (h *prometheusMetricsHandler) WithTags(tags map[string]string) client.MetricsHandler {
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
		gauges:                             h.gauges,
		mu:                                 sync.RWMutex{},
		requestLatency:                     h.requestLatency,
		workflowTaskScheduleToStartLatency: h.workflowTaskScheduleToStartLatency,
		activityTaskScheduleToStartLatency: h.activityTaskScheduleToStartLatency,
		workflowEndToEndLatency:            h.workflowEndToEndLatency,
		longRequest:                        h.longRequest,
		requestFailure:                     h.requestFailure,
	}
}

// Counter returns a counter for the given name.
func (h *prometheusMetricsHandler) Counter(name string) client.MetricsCounter {
	return &prometheusCounter{handler: h, name: name, tags: h.tags}
}

// Gauge returns a gauge for the given name.
func (h *prometheusMetricsHandler) Gauge(name string) client.MetricsGauge {
	return &prometheusGauge{handler: h, name: name, tags: h.tags}
}

// Timer returns a timer for the given name.
func (h *prometheusMetricsHandler) Timer(name string) client.MetricsTimer {
	return &prometheusTimer{handler: h, name: name, tags: h.tags}
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
	if v, ok := c.tags[key]; ok {
		return v
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
	// Build label names and values from tags
	labelNames := make([]string, 0, len(g.tags))
	for k := range g.tags {
		labelNames = append(labelNames, k)
	}
	sort.Strings(labelNames) // Consistent ordering

	labelValues := make([]string, 0, len(labelNames))
	for _, k := range labelNames {
		labelValues = append(labelValues, g.tags[k])
	}

	// Get or create the gauge with these labels
	gauge := g.handler.getOrCreateGauge(g.name, labelNames)
	if gauge != nil {
		if len(labelValues) > 0 {
			gauge.WithLabelValues(labelValues...).Set(value)
		} else {
			gauge.WithLabelValues().Set(value)
		}
	}
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
	if v, ok := t.tags[key]; ok {
		return v
	}
	return defaultValue
}
