// Package generator provides workflow generation with rate limiting.
package generator

import (
	"time"
)

// RampUpController manages the gradual increase of workflow submission rate.
// It ensures monotonic rate increase during the ramp-up period.
//
// Requirements: 2.3 - THE Workflow_Generator SHALL support ramp-up periods
// to gradually increase load.
type RampUpController struct {
	targetRate     float64
	initialRate    float64
	rampUpDuration time.Duration
	startTime      time.Time
	lastRate       float64
}

// NewRampUpController creates a new RampUpController.
// If rampUpDuration is 0, the controller will immediately return the target rate.
func NewRampUpController(targetRate float64, rampUpDuration time.Duration) *RampUpController {
	// Start at 10% of target rate or 1 WPS, whichever is higher
	initialRate := max(targetRate*0.1, 1.0)
	if rampUpDuration == 0 {
		initialRate = targetRate
	}

	return &RampUpController{
		targetRate:     targetRate,
		initialRate:    initialRate,
		rampUpDuration: rampUpDuration,
		startTime:      time.Now(),
		lastRate:       initialRate,
	}
}

// CurrentRate returns the current rate based on elapsed time.
// The rate monotonically increases from initialRate to targetRate during ramp-up.
// After ramp-up completes, it returns the target rate.
func (r *RampUpController) CurrentRate() float64 {
	return r.RateAt(time.Now())
}

// RateAt returns the rate at a specific time.
// This is useful for testing and for calculating rates at specific points.
func (r *RampUpController) RateAt(t time.Time) float64 {
	if r.rampUpDuration == 0 {
		return r.targetRate
	}

	elapsed := t.Sub(r.startTime)
	if elapsed < 0 {
		// Before start time, return initial rate
		return r.initialRate
	}

	if elapsed >= r.rampUpDuration {
		// Ramp-up complete, return target rate
		return r.targetRate
	}

	// Linear interpolation during ramp-up
	progress := float64(elapsed) / float64(r.rampUpDuration)
	rate := r.initialRate + (r.targetRate-r.initialRate)*progress

	// Ensure monotonic increase: never return less than the last rate
	if rate < r.lastRate {
		rate = r.lastRate
	}
	r.lastRate = rate

	return rate
}

// IsRampUpComplete returns true if the ramp-up period has completed.
func (r *RampUpController) IsRampUpComplete() bool {
	return r.IsRampUpCompleteAt(time.Now())
}

// IsRampUpCompleteAt returns true if the ramp-up period has completed at the given time.
func (r *RampUpController) IsRampUpCompleteAt(t time.Time) bool {
	if r.rampUpDuration == 0 {
		return true
	}
	return t.Sub(r.startTime) >= r.rampUpDuration
}

// Progress returns the ramp-up progress as a value between 0 and 1.
// Returns 1.0 if ramp-up is complete.
func (r *RampUpController) Progress() float64 {
	return r.ProgressAt(time.Now())
}

// ProgressAt returns the ramp-up progress at a specific time.
func (r *RampUpController) ProgressAt(t time.Time) float64 {
	if r.rampUpDuration == 0 {
		return 1.0
	}

	elapsed := t.Sub(r.startTime)
	if elapsed < 0 {
		return 0.0
	}

	progress := float64(elapsed) / float64(r.rampUpDuration)
	if progress > 1.0 {
		return 1.0
	}
	return progress
}

// Reset resets the ramp-up controller to start from the current time.
func (r *RampUpController) Reset() {
	r.startTime = time.Now()
	r.lastRate = r.initialRate
}

// ResetAt resets the ramp-up controller to start from the given time.
func (r *RampUpController) ResetAt(t time.Time) {
	r.startTime = t
	r.lastRate = r.initialRate
}

// TargetRate returns the target rate.
func (r *RampUpController) TargetRate() float64 {
	return r.targetRate
}

// InitialRate returns the initial rate.
func (r *RampUpController) InitialRate() float64 {
	return r.initialRate
}

// RampUpDuration returns the ramp-up duration.
func (r *RampUpController) RampUpDuration() time.Duration {
	return r.rampUpDuration
}
