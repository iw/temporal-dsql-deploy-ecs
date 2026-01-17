package generator

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestRampUpController_NoRampUp(t *testing.T) {
	targetRate := 100.0
	controller := NewRampUpController(targetRate, 0)

	// With no ramp-up, should immediately return target rate
	require.Equal(t, targetRate, controller.CurrentRate())
	require.True(t, controller.IsRampUpComplete())
	require.Equal(t, 1.0, controller.Progress())
}

func TestRampUpController_InitialRate(t *testing.T) {
	targetRate := 100.0
	rampUpDuration := 30 * time.Second
	controller := NewRampUpController(targetRate, rampUpDuration)

	// Initial rate should be 10% of target or 1, whichever is higher
	expectedInitial := max(targetRate*0.1, 1.0)
	require.Equal(t, expectedInitial, controller.InitialRate())
}

func TestRampUpController_LowTargetRate(t *testing.T) {
	// When target rate is very low, initial rate should be at least 1
	targetRate := 5.0
	rampUpDuration := 30 * time.Second
	controller := NewRampUpController(targetRate, rampUpDuration)

	// 10% of 5 = 0.5, but minimum is 1
	require.Equal(t, 1.0, controller.InitialRate())
}

func TestRampUpController_RateAtProgress(t *testing.T) {
	targetRate := 100.0
	rampUpDuration := 30 * time.Second
	controller := NewRampUpController(targetRate, rampUpDuration)

	startTime := time.Now()
	controller.ResetAt(startTime)

	// At start (0% progress)
	rate0 := controller.RateAt(startTime)
	require.Equal(t, controller.InitialRate(), rate0)

	// At 50% progress
	midTime := startTime.Add(rampUpDuration / 2)
	rate50 := controller.RateAt(midTime)
	expectedMid := controller.InitialRate() + (targetRate-controller.InitialRate())*0.5
	require.InDelta(t, expectedMid, rate50, 0.01)

	// At 100% progress
	endTime := startTime.Add(rampUpDuration)
	rate100 := controller.RateAt(endTime)
	require.Equal(t, targetRate, rate100)

	// After ramp-up complete
	afterTime := startTime.Add(rampUpDuration + time.Second)
	rateAfter := controller.RateAt(afterTime)
	require.Equal(t, targetRate, rateAfter)
}

func TestRampUpController_MonotonicIncrease(t *testing.T) {
	targetRate := 100.0
	rampUpDuration := 30 * time.Second
	controller := NewRampUpController(targetRate, rampUpDuration)

	startTime := time.Now()
	controller.ResetAt(startTime)

	// Sample rates at multiple points during ramp-up
	var lastRate float64
	for i := 0; i <= 100; i++ {
		progress := float64(i) / 100.0
		elapsed := time.Duration(float64(rampUpDuration) * progress)
		currentTime := startTime.Add(elapsed)

		rate := controller.RateAt(currentTime)

		// Rate should never decrease (monotonic increase)
		require.GreaterOrEqual(t, rate, lastRate,
			"Rate decreased at progress %.2f: %.2f -> %.2f", progress, lastRate, rate)

		lastRate = rate
	}

	// Final rate should be target rate
	require.Equal(t, targetRate, lastRate)
}

func TestRampUpController_Progress(t *testing.T) {
	targetRate := 100.0
	rampUpDuration := 30 * time.Second
	controller := NewRampUpController(targetRate, rampUpDuration)

	startTime := time.Now()
	controller.ResetAt(startTime)

	// At start
	require.Equal(t, 0.0, controller.ProgressAt(startTime))

	// At 50%
	require.InDelta(t, 0.5, controller.ProgressAt(startTime.Add(rampUpDuration/2)), 0.01)

	// At 100%
	require.Equal(t, 1.0, controller.ProgressAt(startTime.Add(rampUpDuration)))

	// After completion
	require.Equal(t, 1.0, controller.ProgressAt(startTime.Add(rampUpDuration*2)))
}

func TestRampUpController_Reset(t *testing.T) {
	targetRate := 100.0
	rampUpDuration := 30 * time.Second
	controller := NewRampUpController(targetRate, rampUpDuration)

	// Advance time
	time.Sleep(10 * time.Millisecond)

	// Reset should restart from current time
	controller.Reset()

	// Progress should be back to ~0
	require.InDelta(t, 0.0, controller.Progress(), 0.01)
}

func TestRampUpController_IsRampUpComplete(t *testing.T) {
	targetRate := 100.0
	rampUpDuration := 30 * time.Second
	controller := NewRampUpController(targetRate, rampUpDuration)

	startTime := time.Now()
	controller.ResetAt(startTime)

	// Before completion
	require.False(t, controller.IsRampUpCompleteAt(startTime))
	require.False(t, controller.IsRampUpCompleteAt(startTime.Add(rampUpDuration/2)))

	// At completion
	require.True(t, controller.IsRampUpCompleteAt(startTime.Add(rampUpDuration)))

	// After completion
	require.True(t, controller.IsRampUpCompleteAt(startTime.Add(rampUpDuration*2)))
}
