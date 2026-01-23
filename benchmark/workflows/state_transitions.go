// Package workflows provides benchmark workflow definitions.
package workflows

import (
	"context"
	"time"

	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/workflow"
)

// StateTransitionWorkflowName is the registered name for StateTransitionWorkflow.
const StateTransitionWorkflowName = "StateTransitionWorkflow"

// FastActivityName is the registered name for FastActivity.
const FastActivityName = "FastActivity"

// StateTransitionWorkflow executes 10 activities serially to generate state transitions
// without OCC conflicts from concurrent activity completions on the same workflow.
//
// Pattern: 10 sequential activities, each completing instantly.
// This avoids the OCC conflict storm that occurs when multiple activities
// complete concurrently and all try to update the same workflow execution row.
//
// State transitions per workflow (~60):
// - 1 workflow started
// - 10 activity scheduled events
// - 10 activity started events
// - 10 activity completed events
// - ~10 workflow task events (scheduled/started/completed)
// - 1 workflow completed
//
// At 50 WPS, this generates ~3,000 state transitions/second.
// At 100 WPS, this generates ~6,000 state transitions/second.
func StateTransitionWorkflow(ctx workflow.Context) error {
	ao := workflow.ActivityOptions{
		StartToCloseTimeout: time.Minute,
	}
	ctx = workflow.WithActivityOptions(ctx, ao)

	runID := workflow.GetInfo(ctx).WorkflowExecution.RunID

	// Execute 10 activities serially to avoid OCC conflicts
	for i := 0; i < 10; i++ {
		input := ActivityInput{
			WorkflowRunID: runID,
			ActivityIndex: i,
		}
		var output ActivityOutput
		if err := workflow.ExecuteActivity(ctx, FastActivity, input).Get(ctx, &output); err != nil {
			return err
		}
	}

	return nil
}

// FastActivity completes instantly with minimal overhead.
// Used for state transition benchmarking where we want maximum throughput.
// Uses the same input/output types as NoOpActivity for consistency.
func FastActivity(ctx context.Context, input ActivityInput) (ActivityOutput, error) {
	info := activity.GetInfo(ctx)

	return ActivityOutput{
		TaskQueue:  info.TaskQueue,
		WorkerID:   info.WorkflowExecution.ID,
		ActivityID: info.ActivityID,
		Attempt:    info.Attempt,
	}, nil
}
