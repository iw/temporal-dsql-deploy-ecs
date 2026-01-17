// Package workflows provides benchmark workflow definitions.
package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/workflow"
)

// TimerWorkflowName is the registered name for TimerWorkflow.
const TimerWorkflowName = "TimerWorkflow"

// TimerWorkflow waits for a configurable duration.
// Used to measure timer scheduling and firing overhead.
//
// Parameters:
//   - duration: How long the workflow should sleep
//
// Requirements: 1.3 - THE Workflow_Generator SHALL support a workflow
// with configurable sleep/timer duration.
func TimerWorkflow(ctx workflow.Context, duration time.Duration) error {
	// Validate duration is positive
	if duration < 0 {
		return fmt.Errorf("duration must be non-negative, got %v", duration)
	}
	return workflow.Sleep(ctx, duration)
}
