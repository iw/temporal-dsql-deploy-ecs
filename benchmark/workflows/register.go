// Package workflows provides benchmark workflow definitions.
package workflows

import (
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"
)

// RegisterWorkflows registers all benchmark workflows with the given worker.
// This should be called during worker initialization.
func RegisterWorkflows(w worker.Worker) {
	w.RegisterWorkflowWithOptions(SimpleWorkflow, workflow.RegisterOptions{
		Name: SimpleWorkflowName,
	})
	w.RegisterWorkflowWithOptions(MultiActivityWorkflow, workflow.RegisterOptions{
		Name: MultiActivityWorkflowName,
	})
	w.RegisterWorkflowWithOptions(TimerWorkflow, workflow.RegisterOptions{
		Name: TimerWorkflowName,
	})
	w.RegisterWorkflowWithOptions(ChildWorkflow, workflow.RegisterOptions{
		Name: ChildWorkflowName,
	})
	w.RegisterWorkflowWithOptions(StateTransitionWorkflow, workflow.RegisterOptions{
		Name: StateTransitionWorkflowName,
	})
}

// RegisterActivities registers all benchmark activities with the given worker.
// This should be called during worker initialization.
func RegisterActivities(w worker.Worker) {
	w.RegisterActivityWithOptions(NoOpActivity, activity.RegisterOptions{
		Name: NoOpActivityName,
	})
	w.RegisterActivityWithOptions(FastActivity, activity.RegisterOptions{
		Name: FastActivityName,
	})
}

// RegisterAll registers all workflows and activities with the given worker.
// This is a convenience function that calls both RegisterWorkflows and RegisterActivities.
func RegisterAll(w worker.Worker) {
	RegisterWorkflows(w)
	RegisterActivities(w)
}
