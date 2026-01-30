// Package metrics provides Prometheus metrics collection for the benchmark.
package metrics

import (
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"go.temporal.io/sdk/client"
)

// SDKMetricsHandler returns a Temporal SDK metrics handler that captures
// all essential SDK metrics for worker observability.
//
// Metrics included (from SDK v1.31.0):
//
// Counters:
//   - temporal_workflow_completed
//   - temporal_workflow_canceled
//   - temporal_workflow_failed
//   - temporal_workflow_continue_as_new
//   - temporal_workflow_task_execution_failed
//   - temporal_activity_execution_failed
//   - temporal_local_activity_total
//   - temporal_local_activity_execution_cancelled
//   - temporal_local_activity_execution_failed
//   - temporal_sticky_cache_hit
//   - temporal_sticky_cache_miss
//   - temporal_request
//   - temporal_request_failure
//   - temporal_long_request
//   - temporal_long_request_failure
//
// Histograms:
//   - temporal_request_latency
//   - temporal_long_request_latency
//   - temporal_workflow_endtoend_latency
//   - temporal_workflow_task_schedule_to_start_latency
//   - temporal_workflow_task_execution_latency
//   - temporal_workflow_task_replay_latency
//   - temporal_activity_schedule_to_start_latency
//   - temporal_activity_execution_latency
//   - temporal_activity_succeed_endtoend_latency
//   - temporal_local_activity_execution_latency
//   - temporal_local_activity_succeed_endtoend_latency
//
// Gauges (dynamic):
//   - temporal_worker_task_slots_available
//   - temporal_worker_task_slots_used
//   - temporal_num_pollers
//   - temporal_sticky_cache_size
func SDKMetricsHandler(registry *prometheus.Registry) client.MetricsHandler {
	return newPrometheusMetricsHandler(registry)
}

// prometheusMetricsHandler implements client.MetricsHandler for Temporal SDK metrics.
type prometheusMetricsHandler struct {
	registry *prometheus.Registry
	tags     map[string]string

	// Mutex for thread-safe gauge/counter registration
	mu sync.RWMutex

	// Dynamic gauge registry - gauges are created on demand
	gauges map[string]*prometheus.GaugeVec

	// Dynamic counter registry - counters are created on demand
	counters map[string]*prometheus.CounterVec

	// Pre-registered histograms for latency metrics
	requestLatency                      *prometheus.HistogramVec
	longRequestLatency                  *prometheus.HistogramVec
	workflowEndToEndLatency             *prometheus.HistogramVec
	workflowTaskScheduleToStartLatency  *prometheus.HistogramVec
	workflowTaskExecutionLatency        *prometheus.HistogramVec
	workflowTaskReplayLatency           *prometheus.HistogramVec
	activityScheduleToStartLatency      *prometheus.HistogramVec
	activityExecutionLatency            *prometheus.HistogramVec
	activitySucceedEndToEndLatency      *prometheus.HistogramVec
	localActivityExecutionLatency       *prometheus.HistogramVec
	localActivitySucceedEndToEndLatency *prometheus.HistogramVec
}

// newPrometheusMetricsHandler creates a new Temporal SDK metrics handler.
func newPrometheusMetricsHandler(registry *prometheus.Registry) client.MetricsHandler {
	h := &prometheusMetricsHandler{
		registry: registry,
		tags:     make(map[string]string),
		gauges:   make(map[string]*prometheus.GaugeVec),
		counters: make(map[string]*prometheus.CounterVec),
	}

	// Standard latency buckets: 1ms to ~32s
	latencyBuckets := prometheus.ExponentialBuckets(0.001, 2, 15)
	// Extended latency buckets for workflow e2e: 1ms to ~500s
	extendedBuckets := prometheus.ExponentialBuckets(0.001, 2, 20)

	// Request latencies
	h.requestLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_request_latency_seconds",
		Help:    "Latency of Temporal API requests in seconds",
		Buckets: latencyBuckets,
	}, []string{"operation", "namespace"})

	h.longRequestLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_long_request_latency_seconds",
		Help:    "Latency of long-running Temporal API requests (polls) in seconds",
		Buckets: extendedBuckets,
	}, []string{"operation", "namespace"})

	// Workflow latencies
	h.workflowEndToEndLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_workflow_endtoend_latency_seconds",
		Help:    "End-to-end workflow execution latency in seconds",
		Buckets: extendedBuckets,
	}, []string{"namespace", "workflow_type"})

	h.workflowTaskScheduleToStartLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_workflow_task_schedule_to_start_latency_seconds",
		Help:    "Time from workflow task scheduling to start in seconds",
		Buckets: latencyBuckets,
	}, []string{"namespace", "task_queue"})

	h.workflowTaskExecutionLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_workflow_task_execution_latency_seconds",
		Help:    "Time to execute a workflow task in seconds",
		Buckets: latencyBuckets,
	}, []string{"namespace", "task_queue", "workflow_type"})

	h.workflowTaskReplayLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_workflow_task_replay_latency_seconds",
		Help:    "Time to replay workflow history in seconds",
		Buckets: latencyBuckets,
	}, []string{"namespace", "task_queue", "workflow_type"})

	// Activity latencies
	h.activityScheduleToStartLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_activity_schedule_to_start_latency_seconds",
		Help:    "Time from activity scheduling to start in seconds",
		Buckets: latencyBuckets,
	}, []string{"namespace", "task_queue"})

	h.activityExecutionLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_activity_execution_latency_seconds",
		Help:    "Time to execute an activity in seconds",
		Buckets: latencyBuckets,
	}, []string{"namespace", "task_queue", "activity_type"})

	h.activitySucceedEndToEndLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_activity_succeed_endtoend_latency_seconds",
		Help:    "End-to-end latency of successful activities in seconds",
		Buckets: extendedBuckets,
	}, []string{"namespace", "task_queue", "activity_type"})

	// Local activity latencies
	h.localActivityExecutionLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_local_activity_execution_latency_seconds",
		Help:    "Time to execute a local activity in seconds",
		Buckets: latencyBuckets,
	}, []string{"namespace", "task_queue", "activity_type"})

	h.localActivitySucceedEndToEndLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "temporal_local_activity_succeed_endtoend_latency_seconds",
		Help:    "End-to-end latency of successful local activities in seconds",
		Buckets: latencyBuckets,
	}, []string{"namespace", "task_queue", "activity_type"})

	// Register all histogram metrics
	registry.MustRegister(h.requestLatency)
	registry.MustRegister(h.longRequestLatency)
	registry.MustRegister(h.workflowEndToEndLatency)
	registry.MustRegister(h.workflowTaskScheduleToStartLatency)
	registry.MustRegister(h.workflowTaskExecutionLatency)
	registry.MustRegister(h.workflowTaskReplayLatency)
	registry.MustRegister(h.activityScheduleToStartLatency)
	registry.MustRegister(h.activityExecutionLatency)
	registry.MustRegister(h.activitySucceedEndToEndLatency)
	registry.MustRegister(h.localActivityExecutionLatency)
	registry.MustRegister(h.localActivitySucceedEndToEndLatency)

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

// getOrCreateCounter returns an existing counter or creates a new one.
func (h *prometheusMetricsHandler) getOrCreateCounter(name string, labelNames []string) *prometheus.CounterVec {
	h.mu.RLock()
	if counter, ok := h.counters[name]; ok {
		h.mu.RUnlock()
		return counter
	}
	h.mu.RUnlock()

	h.mu.Lock()
	defer h.mu.Unlock()

	// Double-check after acquiring write lock
	if counter, ok := h.counters[name]; ok {
		return counter
	}

	counter := prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: name + "_total",
		Help: "Temporal SDK counter: " + name,
	}, labelNames)

	// Try to register, ignore if already registered
	if err := h.registry.Register(counter); err != nil {
		if existing, ok := h.counters[name]; ok {
			return existing
		}
	}

	h.counters[name] = counter
	return counter
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
		registry:                            h.registry,
		tags:                                newTags,
		gauges:                              h.gauges,
		counters:                            h.counters,
		mu:                                  sync.RWMutex{},
		requestLatency:                      h.requestLatency,
		longRequestLatency:                  h.longRequestLatency,
		workflowEndToEndLatency:             h.workflowEndToEndLatency,
		workflowTaskScheduleToStartLatency:  h.workflowTaskScheduleToStartLatency,
		workflowTaskExecutionLatency:        h.workflowTaskExecutionLatency,
		workflowTaskReplayLatency:           h.workflowTaskReplayLatency,
		activityScheduleToStartLatency:      h.activityScheduleToStartLatency,
		activityExecutionLatency:            h.activityExecutionLatency,
		activitySucceedEndToEndLatency:      h.activitySucceedEndToEndLatency,
		localActivityExecutionLatency:       h.localActivityExecutionLatency,
		localActivitySucceedEndToEndLatency: h.localActivitySucceedEndToEndLatency,
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
	namespace := c.getTag("namespace", "_unknown_")
	workflowType := c.getTag("workflow_type", "unknown")
	activityType := c.getTag("activity_type", "unknown")
	operation := c.getTag("operation", "unknown")

	switch c.name {
	// Workflow counters
	case "temporal_workflow_completed":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "workflow_type"})
		counter.WithLabelValues(namespace, workflowType).Add(float64(delta))
	case "temporal_workflow_canceled":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "workflow_type"})
		counter.WithLabelValues(namespace, workflowType).Add(float64(delta))
	case "temporal_workflow_failed":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "workflow_type"})
		counter.WithLabelValues(namespace, workflowType).Add(float64(delta))
	case "temporal_workflow_continue_as_new":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "workflow_type"})
		counter.WithLabelValues(namespace, workflowType).Add(float64(delta))
	case "temporal_workflow_task_execution_failed":
		failureReason := c.getTag("failure_reason", "unknown")
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "workflow_type", "failure_reason"})
		counter.WithLabelValues(namespace, workflowType, failureReason).Add(float64(delta))

	// Activity counters
	case "temporal_activity_execution_failed":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "activity_type"})
		counter.WithLabelValues(namespace, activityType).Add(float64(delta))

	// Local activity counters
	case "temporal_local_activity_total":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "activity_type"})
		counter.WithLabelValues(namespace, activityType).Add(float64(delta))
	case "temporal_local_activity_execution_cancelled":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "activity_type"})
		counter.WithLabelValues(namespace, activityType).Add(float64(delta))
	case "temporal_local_activity_execution_failed":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "activity_type"})
		counter.WithLabelValues(namespace, activityType).Add(float64(delta))

	// Sticky cache counters
	case "temporal_sticky_cache_hit":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace"})
		counter.WithLabelValues(namespace).Add(float64(delta))
	case "temporal_sticky_cache_miss":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace"})
		counter.WithLabelValues(namespace).Add(float64(delta))

	// Request counters
	case "temporal_request":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "operation"})
		counter.WithLabelValues(namespace, operation).Add(float64(delta))
	case "temporal_request_failure":
		statusCode := c.getTag("status_code", "unknown")
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "operation", "status_code"})
		counter.WithLabelValues(namespace, operation, statusCode).Add(float64(delta))
	case "temporal_long_request":
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "operation"})
		counter.WithLabelValues(namespace, operation).Add(float64(delta))
	case "temporal_long_request_failure":
		statusCode := c.getTag("status_code", "unknown")
		counter := c.handler.getOrCreateCounter(c.name, []string{"namespace", "operation", "status_code"})
		counter.WithLabelValues(namespace, operation, statusCode).Add(float64(delta))
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
	namespace := g.getTag("namespace", "_unknown_")
	taskQueue := g.getTag("task_queue", "unknown")
	workerType := g.getTag("worker_type", "unknown")

	switch g.name {
	case "temporal_worker_task_slots_available":
		gauge := g.handler.getOrCreateGauge(g.name, []string{"namespace", "task_queue", "worker_type"})
		gauge.WithLabelValues(namespace, taskQueue, workerType).Set(value)
	case "temporal_worker_task_slots_used":
		gauge := g.handler.getOrCreateGauge(g.name, []string{"namespace", "task_queue", "worker_type"})
		gauge.WithLabelValues(namespace, taskQueue, workerType).Set(value)
	case "temporal_num_pollers":
		pollerType := g.getTag("poller_type", "unknown")
		gauge := g.handler.getOrCreateGauge(g.name, []string{"namespace", "task_queue", "poller_type"})
		gauge.WithLabelValues(namespace, taskQueue, pollerType).Set(value)
	case "temporal_sticky_cache_size":
		gauge := g.handler.getOrCreateGauge(g.name, []string{"namespace"})
		gauge.WithLabelValues(namespace).Set(value)
	}
}

func (g *prometheusGauge) getTag(key, defaultValue string) string {
	if v, ok := g.tags[key]; ok {
		return v
	}
	return defaultValue
}

// prometheusTimer implements client.MetricsTimer.
type prometheusTimer struct {
	handler *prometheusMetricsHandler
	name    string
	tags    map[string]string
}

func (t *prometheusTimer) Record(d time.Duration) {
	seconds := d.Seconds()
	namespace := t.getTag("namespace", "_unknown_")
	taskQueue := t.getTag("task_queue", "unknown")
	workflowType := t.getTag("workflow_type", "unknown")
	activityType := t.getTag("activity_type", "unknown")
	operation := t.getTag("operation", "unknown")

	switch t.name {
	// Request latencies
	case "temporal_request_latency":
		t.handler.requestLatency.WithLabelValues(operation, namespace).Observe(seconds)
	case "temporal_long_request_latency":
		t.handler.longRequestLatency.WithLabelValues(operation, namespace).Observe(seconds)

	// Workflow latencies
	case "temporal_workflow_endtoend_latency":
		t.handler.workflowEndToEndLatency.WithLabelValues(namespace, workflowType).Observe(seconds)
	case "temporal_workflow_task_schedule_to_start_latency":
		t.handler.workflowTaskScheduleToStartLatency.WithLabelValues(namespace, taskQueue).Observe(seconds)
	case "temporal_workflow_task_execution_latency":
		t.handler.workflowTaskExecutionLatency.WithLabelValues(namespace, taskQueue, workflowType).Observe(seconds)
	case "temporal_workflow_task_replay_latency":
		t.handler.workflowTaskReplayLatency.WithLabelValues(namespace, taskQueue, workflowType).Observe(seconds)

	// Activity latencies
	case "temporal_activity_schedule_to_start_latency":
		t.handler.activityScheduleToStartLatency.WithLabelValues(namespace, taskQueue).Observe(seconds)
	case "temporal_activity_execution_latency":
		t.handler.activityExecutionLatency.WithLabelValues(namespace, taskQueue, activityType).Observe(seconds)
	case "temporal_activity_succeed_endtoend_latency":
		t.handler.activitySucceedEndToEndLatency.WithLabelValues(namespace, taskQueue, activityType).Observe(seconds)

	// Local activity latencies
	case "temporal_local_activity_execution_latency":
		t.handler.localActivityExecutionLatency.WithLabelValues(namespace, taskQueue, activityType).Observe(seconds)
	case "temporal_local_activity_succeed_endtoend_latency":
		t.handler.localActivitySucceedEndToEndLatency.WithLabelValues(namespace, taskQueue, activityType).Observe(seconds)
	}
}

func (t *prometheusTimer) getTag(key, defaultValue string) string {
	if v, ok := t.tags[key]; ok {
		return v
	}
	return defaultValue
}
