package metrics

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestCalculatePercentiles_Empty(t *testing.T) {
	result := CalculatePercentiles([]float64{})
	require.Equal(t, LatencyPercentiles{}, result)
}

func TestCalculatePercentiles_SingleValue(t *testing.T) {
	result := CalculatePercentiles([]float64{100.0})
	require.Equal(t, 100.0, result.P50)
	require.Equal(t, 100.0, result.P95)
	require.Equal(t, 100.0, result.P99)
	require.Equal(t, 100.0, result.Max)
}

func TestCalculatePercentiles_TwoValues(t *testing.T) {
	result := CalculatePercentiles([]float64{10.0, 20.0})
	// With 2 values, p50 should be interpolated between them
	require.InDelta(t, 15.0, result.P50, 0.01)
	require.InDelta(t, 19.5, result.P95, 0.01)
	require.InDelta(t, 19.9, result.P99, 0.01)
	require.Equal(t, 20.0, result.Max)
}

func TestCalculatePercentiles_KnownDistribution(t *testing.T) {
	// Create a distribution of 100 values from 1 to 100
	latencies := make([]float64, 100)
	for i := 0; i < 100; i++ {
		latencies[i] = float64(i + 1)
	}

	result := CalculatePercentiles(latencies)

	// p50 should be around 50.5 (interpolated between 50 and 51)
	require.InDelta(t, 50.5, result.P50, 0.5)
	// p95 should be around 95.05
	require.InDelta(t, 95.05, result.P95, 0.5)
	// p99 should be around 99.01
	require.InDelta(t, 99.01, result.P99, 0.5)
	// Max should be 100
	require.Equal(t, 100.0, result.Max)
}

func TestCalculatePercentiles_UnsortedInput(t *testing.T) {
	// Input is unsorted - function should handle this
	latencies := []float64{50.0, 10.0, 90.0, 30.0, 70.0}

	result := CalculatePercentiles(latencies)

	// Max should be 90
	require.Equal(t, 90.0, result.Max)
	// P50 should be 50 (middle value when sorted)
	require.Equal(t, 50.0, result.P50)
}

func TestCalculatePercentiles_DoesNotModifyInput(t *testing.T) {
	original := []float64{50.0, 10.0, 90.0, 30.0, 70.0}
	input := make([]float64, len(original))
	copy(input, original)

	CalculatePercentiles(input)

	// Input should not be modified
	require.Equal(t, original, input)
}

func TestValidatePercentileOrdering_Valid(t *testing.T) {
	valid := LatencyPercentiles{
		P50: 10.0,
		P95: 50.0,
		P99: 90.0,
		Max: 100.0,
	}
	require.True(t, ValidatePercentileOrdering(valid))
}

func TestValidatePercentileOrdering_EqualValues(t *testing.T) {
	// All equal values should be valid
	equal := LatencyPercentiles{
		P50: 50.0,
		P95: 50.0,
		P99: 50.0,
		Max: 50.0,
	}
	require.True(t, ValidatePercentileOrdering(equal))
}

func TestValidatePercentileOrdering_Invalid_P50GreaterThanP95(t *testing.T) {
	invalid := LatencyPercentiles{
		P50: 60.0,
		P95: 50.0,
		P99: 90.0,
		Max: 100.0,
	}
	require.False(t, ValidatePercentileOrdering(invalid))
}

func TestValidatePercentileOrdering_Invalid_P95GreaterThanP99(t *testing.T) {
	invalid := LatencyPercentiles{
		P50: 10.0,
		P95: 95.0,
		P99: 90.0,
		Max: 100.0,
	}
	require.False(t, ValidatePercentileOrdering(invalid))
}

func TestValidatePercentileOrdering_Invalid_P99GreaterThanMax(t *testing.T) {
	invalid := LatencyPercentiles{
		P50: 10.0,
		P95: 50.0,
		P99: 110.0,
		Max: 100.0,
	}
	require.False(t, ValidatePercentileOrdering(invalid))
}

func TestLatencyCollector_Basic(t *testing.T) {
	collector := NewLatencyCollector(100)

	collector.Add(10.0)
	collector.Add(20.0)
	collector.Add(30.0)

	require.Equal(t, 3, collector.Count())

	percentiles := collector.Percentiles()
	require.Equal(t, 30.0, percentiles.Max)
}

func TestLatencyCollector_Reset(t *testing.T) {
	collector := NewLatencyCollector(100)

	collector.Add(10.0)
	collector.Add(20.0)
	require.Equal(t, 2, collector.Count())

	collector.Reset()
	require.Equal(t, 0, collector.Count())

	percentiles := collector.Percentiles()
	require.Equal(t, LatencyPercentiles{}, percentiles)
}
