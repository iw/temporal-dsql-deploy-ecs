// Package workflows provides benchmark workflow definitions.
package workflows

import (
	"go.temporal.io/sdk/workflow"
)

// SimpleWorkflowName is the registered name for SimpleWorkflow.
const SimpleWorkflowName = "SimpleWorkflow"

// SimpleWorkflow completes immediately.
// This is the most basic workflow for measuring baseline throughput.
// It performs no activities or timers, making it ideal for measuring
// the minimum overhead of workflow execution.
//
// Requirements: 1.1 - THE Workflow_Generator SHALL support a simple
// "hello world" workflow that completes immediately.
func SimpleWorkflow(ctx workflow.Context) error {
	return nil
}
