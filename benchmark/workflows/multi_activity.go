// Package workflows provides benchmark workflow definitions.
package workflows

import (
	"context"
	"fmt"
	"time"

	"go.temporal.io/sdk/workflow"
)

// MultiActivityWorkflowName is the registered name for MultiActivityWorkflow.
const MultiActivityWorkflowName = "MultiActivityWorkflow"

// NoOpActivityName is the registered name for NoOpActivity.
const NoOpActivityName = "NoOpActivity"

// MinActivityCount is the minimum allowed activity count.
const MinActivityCount = 1

// MaxActivityCount is the maximum allowed activity count.
const MaxActivityCount = 100

// MultiActivityWorkflow executes N activities sequentially.
// Used to measure activity scheduling and execution overhead.
//
// Parameters:
//   - activityCount: Number of activities to execute (1-100)
//
// Requirements: 1.2 - THE Workflow_Generator SHALL support a workflow
// with configurable activity count (1-100 activities).
func MultiActivityWorkflow(ctx workflow.Context, activityCount int) error {
	// Validate activity count
	if activityCount < MinActivityCount || activityCount > MaxActivityCount {
		return fmt.Errorf("activityCount must be between %d and %d, got %d",
			MinActivityCount, MaxActivityCount, activityCount)
	}

	ao := workflow.ActivityOptions{
		StartToCloseTimeout: time.Minute,
	}
	ctx = workflow.WithActivityOptions(ctx, ao)

	for range activityCount {
		err := workflow.ExecuteActivity(ctx, NoOpActivity).Get(ctx, nil)
		if err != nil {
			return err
		}
	}
	return nil
}

// NoOpActivity is a minimal activity for testing.
// It completes immediately without doing any work.
func NoOpActivity(ctx context.Context) error {
	return nil
}
