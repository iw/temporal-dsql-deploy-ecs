// Package workflows provides benchmark workflow definitions.
package workflows

import (
	"context"
	"math/rand"
	"time"

	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/workflow"
)

// MultiActivityWorkflowName is the registered name for MultiActivityWorkflow.
const MultiActivityWorkflowName = "MultiActivityWorkflow"

// NoOpActivityName is the registered name for NoOpActivity.
const NoOpActivityName = "NoOpActivity"

// ActivityInput contains the input for NoOpActivity.
type ActivityInput struct {
	WorkflowRunID string
	ActivityIndex int
}

// ActivityOutput contains the output from NoOpActivity.
type ActivityOutput struct {
	TaskQueue  string
	WorkerID   string
	ActivityID string
	Attempt    int32
}

// MultiActivityWorkflow executes 10 activities total:
// - 4 concurrent activities that run in parallel and join
// - 6 sequential activities that run one after another
//
// This pattern tests both parallel execution and sequential scheduling overhead.
func MultiActivityWorkflow(ctx workflow.Context) error {
	ao := workflow.ActivityOptions{
		StartToCloseTimeout: time.Minute,
	}
	ctx = workflow.WithActivityOptions(ctx, ao)

	runID := workflow.GetInfo(ctx).WorkflowExecution.RunID
	activityIndex := 0

	// Phase 1: Execute 4 activities concurrently
	var futures []workflow.Future
	for i := 0; i < 4; i++ {
		input := ActivityInput{
			WorkflowRunID: runID,
			ActivityIndex: activityIndex,
		}
		activityIndex++
		future := workflow.ExecuteActivity(ctx, NoOpActivity, input)
		futures = append(futures, future)
	}

	// Wait for all concurrent activities to complete
	for _, future := range futures {
		var output ActivityOutput
		if err := future.Get(ctx, &output); err != nil {
			return err
		}
	}

	// Phase 2: Execute 6 activities sequentially
	for i := 0; i < 6; i++ {
		input := ActivityInput{
			WorkflowRunID: runID,
			ActivityIndex: activityIndex,
		}
		activityIndex++
		var output ActivityOutput
		if err := workflow.ExecuteActivity(ctx, NoOpActivity, input).Get(ctx, &output); err != nil {
			return err
		}
	}

	return nil
}

// NoOpActivity is a minimal activity for testing.
// It sleeps for a random duration between 100-600ms to simulate work.
// Returns metadata about the activity execution.
func NoOpActivity(ctx context.Context, input ActivityInput) (ActivityOutput, error) {
	info := activity.GetInfo(ctx)

	// Random sleep between 100ms and 600ms (min 0.1s as per tuning guidance)
	sleepDuration := time.Duration(100+rand.Intn(500)) * time.Millisecond
	time.Sleep(sleepDuration)

	return ActivityOutput{
		TaskQueue:  info.TaskQueue,
		WorkerID:   info.WorkflowExecution.ID,
		ActivityID: info.ActivityID,
		Attempt:    info.Attempt,
	}, nil
}
