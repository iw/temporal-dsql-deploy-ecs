// Package workflows provides benchmark workflow definitions.
package workflows

import (
	"fmt"

	"go.temporal.io/sdk/workflow"
)

// ChildWorkflowName is the registered name for ChildWorkflow.
const ChildWorkflowName = "ChildWorkflow"

// MinChildCount is the minimum allowed child workflow count.
const MinChildCount = 1

// MaxChildCount is the maximum allowed child workflow count.
const MaxChildCount = 100

// ChildWorkflow spawns N child workflows.
// Used to measure child workflow scheduling and execution overhead.
// All child workflows are started concurrently and then awaited.
//
// Parameters:
//   - childCount: Number of child workflows to spawn (1-100)
//
// Requirements: 1.4 - THE Workflow_Generator SHALL support a workflow
// with child workflow spawning.
func ChildWorkflow(ctx workflow.Context, childCount int) error {
	// Validate child count
	if childCount < MinChildCount || childCount > MaxChildCount {
		return fmt.Errorf("childCount must be between %d and %d, got %d",
			MinChildCount, MaxChildCount, childCount)
	}

	var futures []workflow.ChildWorkflowFuture
	for range childCount {
		future := workflow.ExecuteChildWorkflow(ctx, SimpleWorkflow)
		futures = append(futures, future)
	}
	for _, f := range futures {
		if err := f.Get(ctx, nil); err != nil {
			return err
		}
	}
	return nil
}
