// Package metrics provides Prometheus metrics collection for the benchmark.
package metrics

import (
	"math"
	"sort"
)

// CalculatePercentiles computes p50, p95, p99, and max from a slice of latency values.
// Input values should be in milliseconds. Returns LatencyPercentiles with values in milliseconds.
// This function is exported for testing and direct use.
func CalculatePercentiles(latencies []float64) LatencyPercentiles {
	if len(latencies) == 0 {
		return LatencyPercentiles{}
	}

	// Make a copy to avoid modifying the original slice
	sorted := make([]float64, len(latencies))
	copy(sorted, latencies)
	sort.Float64s(sorted)

	return LatencyPercentiles{
		P50: percentileFromSorted(sorted, 50),
		P95: percentileFromSorted(sorted, 95),
		P99: percentileFromSorted(sorted, 99),
		Max: sorted[len(sorted)-1],
	}
}

// percentileFromSorted calculates the p-th percentile from a sorted slice.
// Uses linear interpolation between data points for more accurate results.
func percentileFromSorted(sorted []float64, p float64) float64 {
	if len(sorted) == 0 {
		return 0
	}
	if len(sorted) == 1 {
		return sorted[0]
	}

	// Use linear interpolation for percentile calculation
	// This is the "exclusive" method (R6 in R terminology)
	rank := (p / 100) * float64(len(sorted)-1)
	lower := int(math.Floor(rank))
	upper := int(math.Ceil(rank))

	// Clamp to valid indices
	if lower < 0 {
		lower = 0
	}
	if upper >= len(sorted) {
		upper = len(sorted) - 1
	}

	if lower == upper {
		return sorted[lower]
	}

	// Linear interpolation between lower and upper values
	weight := rank - float64(lower)
	return sorted[lower]*(1-weight) + sorted[upper]*weight
}

// LatencyCollector collects latency samples and computes percentiles.
// It is thread-safe and can be used concurrently.
type LatencyCollector struct {
	latencies []float64
}

// NewLatencyCollector creates a new LatencyCollector with the given initial capacity.
func NewLatencyCollector(capacity int) *LatencyCollector {
	return &LatencyCollector{
		latencies: make([]float64, 0, capacity),
	}
}

// Add adds a latency sample in milliseconds.
func (c *LatencyCollector) Add(latencyMs float64) {
	c.latencies = append(c.latencies, latencyMs)
}

// AddDuration adds a latency sample from a time.Duration.
func (c *LatencyCollector) AddDuration(d interface{ Milliseconds() int64 }) {
	c.latencies = append(c.latencies, float64(d.Milliseconds()))
}

// Count returns the number of samples collected.
func (c *LatencyCollector) Count() int {
	return len(c.latencies)
}

// Percentiles computes and returns the latency percentiles.
func (c *LatencyCollector) Percentiles() LatencyPercentiles {
	return CalculatePercentiles(c.latencies)
}

// Reset clears all collected samples.
func (c *LatencyCollector) Reset() {
	c.latencies = c.latencies[:0]
}

// ValidatePercentileOrdering checks that percentiles are in the correct order.
// Returns true if p50 <= p95 <= p99 <= max.
// This is Property 7 from the design document.
func ValidatePercentileOrdering(p LatencyPercentiles) bool {
	return p.P50 <= p.P95 && p.P95 <= p.P99 && p.P99 <= p.Max
}
