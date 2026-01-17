// Package metrics provides Prometheus metrics collection for the benchmark.
package metrics

import (
	"context"
	"fmt"
	"log"
	"math"
	"net/http"
	"sort"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.temporal.io/sdk/client"
)

// MetricsHandler exposes Prometheus metrics.
type MetricsHandler interface {
	// ServeHTTP handles Prometheus scrape requests
	http.Handler

	// RecordWorkflowLatency records a workflow completion latency
	RecordWorkflowLatency(duration time.Duration)

	// RecordWorkflowResult records a workflow completion (success/failure)
	RecordWorkflowResult(success bool)

	// GetLatencyPercentiles returns p50, p95, p99, and max latencies in milliseconds
	GetLatencyPercentiles() LatencyPercentiles

	// GetThroughput returns the current throughput (completions per second)
	GetThroughput() float64

	// Registry returns the Prometheus registry for SDK metrics integration
	Registry() *prometheus.Registry

	// StartServer starts the HTTP server for metrics on the specified port
	StartServer(ctx context.Context, port int) error

	// StopServer stops the HTTP server
	StopServer(ctx context.Context) error
}

// LatencyPercentiles contains latency percentile values in milliseconds.
type LatencyPercentiles struct {
	P50 float64
	P95 float64
	P99 float64
	Max float64
}

// handler implements MetricsHandler with Prometheus metrics.
type handler struct {
	registry        *prometheus.Registry
	workflowLatency prometheus.Histogram
	workflowsTotal  *prometheus.CounterVec
	throughput      prometheus.Gauge
	httpHandler     http.Handler
	server          *http.Server

	// Latency tracking for percentile calculation
	latencyMu      sync.Mutex
	latencies      []float64
	startTime      time.Time
	completedCount int64
}

// NewHandler creates a new MetricsHandler with Prometheus metrics.
func NewHandler() MetricsHandler {
	registry := prometheus.NewRegistry()

	// Workflow latency histogram with buckets from 1ms to ~500s
	// Buckets: 1ms, 2ms, 4ms, 8ms, 16ms, 32ms, 64ms, 128ms, 256ms, 512ms, 1s, 2s, 4s, 8s, 16s, 32s, 64s, 128s, 256s, 512s
	workflowLatency := prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:    "benchmark_workflow_latency_seconds",
		Help:    "Workflow completion latency in seconds",
		Buckets: prometheus.ExponentialBuckets(0.001, 2, 20),
	})

	// Counter for workflow results (success/failure)
	workflowsTotal := prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "benchmark_workflows_total",
		Help: "Total number of workflows by result",
	}, []string{"result"})

	// Gauge for current throughput
	throughput := prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "benchmark_throughput_per_second",
		Help: "Current workflow throughput (completions per second)",
	})

	registry.MustRegister(workflowLatency)
	registry.MustRegister(workflowsTotal)
	registry.MustRegister(throughput)

	return &handler{
		registry:        registry,
		workflowLatency: workflowLatency,
		workflowsTotal:  workflowsTotal,
		throughput:      throughput,
		httpHandler:     promhttp.HandlerFor(registry, promhttp.HandlerOpts{}),
		latencies:       make([]float64, 0, 10000),
		startTime:       time.Now(),
	}
}

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.httpHandler.ServeHTTP(w, r)
}

func (h *handler) RecordWorkflowLatency(duration time.Duration) {
	latencySeconds := duration.Seconds()
	h.workflowLatency.Observe(latencySeconds)

	// Store latency for percentile calculation
	h.latencyMu.Lock()
	h.latencies = append(h.latencies, latencySeconds*1000) // Store in milliseconds
	h.latencyMu.Unlock()
}

func (h *handler) RecordWorkflowResult(success bool) {
	result := "success"
	if !success {
		result = "failure"
	}
	h.workflowsTotal.WithLabelValues(result).Inc()

	if success {
		h.latencyMu.Lock()
		h.completedCount++
		elapsed := time.Since(h.startTime).Seconds()
		if elapsed > 0 {
			h.throughput.Set(float64(h.completedCount) / elapsed)
		}
		h.latencyMu.Unlock()
	}
}

// GetLatencyPercentiles calculates and returns p50, p95, p99, and max latencies.
func (h *handler) GetLatencyPercentiles() LatencyPercentiles {
	h.latencyMu.Lock()
	defer h.latencyMu.Unlock()

	if len(h.latencies) == 0 {
		return LatencyPercentiles{}
	}

	// Make a copy to avoid modifying the original slice
	sorted := make([]float64, len(h.latencies))
	copy(sorted, h.latencies)
	sort.Float64s(sorted)

	return LatencyPercentiles{
		P50: calculatePercentile(sorted, 50),
		P95: calculatePercentile(sorted, 95),
		P99: calculatePercentile(sorted, 99),
		Max: sorted[len(sorted)-1],
	}
}

// calculatePercentile calculates the p-th percentile from a sorted slice.
func calculatePercentile(sorted []float64, p float64) float64 {
	if len(sorted) == 0 {
		return 0
	}
	if len(sorted) == 1 {
		return sorted[0]
	}

	// Use linear interpolation for percentile calculation
	rank := (p / 100) * float64(len(sorted)-1)
	lower := int(math.Floor(rank))
	upper := int(math.Ceil(rank))

	if lower == upper {
		return sorted[lower]
	}

	// Linear interpolation
	weight := rank - float64(lower)
	return sorted[lower]*(1-weight) + sorted[upper]*weight
}

// GetThroughput returns the current throughput (completions per second).
func (h *handler) GetThroughput() float64 {
	h.latencyMu.Lock()
	defer h.latencyMu.Unlock()

	elapsed := time.Since(h.startTime).Seconds()
	if elapsed <= 0 {
		return 0
	}
	return float64(h.completedCount) / elapsed
}

// Registry returns the Prometheus registry for SDK metrics integration.
func (h *handler) Registry() *prometheus.Registry {
	return h.registry
}

// StartServer starts the HTTP server for metrics on the specified port.
func (h *handler) StartServer(ctx context.Context, port int) error {
	mux := http.NewServeMux()
	mux.Handle("/metrics", h)

	h.server = &http.Server{
		Addr:    fmt.Sprintf(":%d", port),
		Handler: mux,
	}

	go func() {
		log.Printf("Starting metrics server on port %d", port)
		if err := h.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("Metrics server error: %v", err)
		}
	}()

	return nil
}

// StopServer stops the HTTP server.
func (h *handler) StopServer(ctx context.Context) error {
	if h.server == nil {
		return nil
	}

	log.Println("Stopping metrics server")
	return h.server.Shutdown(ctx)
}

// ResetStartTime resets the start time for throughput calculation.
// Call this when starting a new benchmark run.
func (h *handler) ResetStartTime() {
	h.latencyMu.Lock()
	defer h.latencyMu.Unlock()
	h.startTime = time.Now()
	h.completedCount = 0
	h.latencies = h.latencies[:0]
}

// SDKMetricsHandler creates a Temporal SDK metrics handler that reports to the same registry.
// This integrates Temporal SDK metrics with the benchmark metrics endpoint.
func SDKMetricsHandler(registry *prometheus.Registry) client.MetricsHandler {
	return NewPrometheusMetricsHandler(registry)
}
