// Package cleanup provides workflow cleanup functionality for the benchmark runner.
// Requirement 8.2: WHEN a benchmark completes, THE Benchmark_Runner SHALL terminate all running workflows
// Requirement 8.4: IF cleanup fails, THEN THE Benchmark_Runner SHALL log the failure and provide manual cleanup instructions
package cleanup

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"

	"go.temporal.io/api/workflowservice/v1"
	"go.temporal.io/sdk/client"
)

// CleanupError represents a cleanup operation failure with details.
// Requirement 8.4: Provide detailed error information for cleanup failures.
type CleanupError struct {
	Namespace         string
	Phase             string // "list", "terminate", "verify"
	WorkflowsFound    int
	WorkflowsFailed   int
	TerminationErrors []TerminationError
	Cause             error
}

func (e *CleanupError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("cleanup failed in %s phase for namespace %s: %v", e.Phase, e.Namespace, e.Cause)
	}
	return fmt.Sprintf("cleanup failed in %s phase for namespace %s: %d/%d workflows failed to terminate",
		e.Phase, e.Namespace, e.WorkflowsFailed, e.WorkflowsFound)
}

func (e *CleanupError) Unwrap() error {
	return e.Cause
}

// CleanupResult contains the results of a cleanup operation.
type CleanupResult struct {
	Namespace           string
	WorkflowsFound      int
	WorkflowsTerminated int
	TerminationErrors   []TerminationError
	Duration            time.Duration
	Success             bool
}

// TerminationError represents a failed workflow termination.
type TerminationError struct {
	WorkflowID string
	RunID      string
	Error      error
}

// Cleaner handles workflow cleanup operations.
type Cleaner struct {
	client client.Client
}

// NewCleaner creates a new Cleaner instance.
func NewCleaner(c client.Client) *Cleaner {
	return &Cleaner{client: c}
}

// CleanupNamespace terminates all running workflows in the specified namespace.
// Requirement 8.2: WHEN a benchmark completes, THE Benchmark_Runner SHALL terminate all running workflows
// in the benchmark namespace.
func (c *Cleaner) CleanupNamespace(ctx context.Context, namespace string) (*CleanupResult, error) {
	startTime := time.Now()
	result := &CleanupResult{
		Namespace:         namespace,
		TerminationErrors: []TerminationError{},
	}

	slog.Info("Starting cleanup", "namespace", namespace)

	// List all running workflows in the namespace
	workflows, err := c.listOpenWorkflows(ctx, namespace)
	if err != nil {
		// Requirement 8.4: IF cleanup fails, THEN THE Benchmark_Runner SHALL log the failure
		// and provide manual cleanup instructions
		logManualCleanupInstructions(namespace, err)
		return result, fmt.Errorf("failed to list workflows for cleanup: %w", err)
	}

	result.WorkflowsFound = len(workflows)
	slog.Info("Found running workflows to terminate", "count", result.WorkflowsFound)

	if result.WorkflowsFound == 0 {
		slog.Info("No running workflows found", "namespace", namespace)
		result.Success = true
		result.Duration = time.Since(startTime)
		return result, nil
	}

	// Terminate workflows with progress logging
	result.WorkflowsTerminated, result.TerminationErrors = c.terminateWorkflows(ctx, namespace, workflows)

	result.Duration = time.Since(startTime)
	result.Success = len(result.TerminationErrors) == 0

	// Log cleanup summary
	c.logCleanupSummary(result)

	// If there were errors, provide manual cleanup instructions
	if !result.Success {
		logManualCleanupInstructions(namespace, fmt.Errorf("%d workflows failed to terminate", len(result.TerminationErrors)))
	}

	return result, nil
}

// WorkflowExecution represents a workflow to be terminated.
type WorkflowExecution struct {
	WorkflowID string
	RunID      string
}

// listOpenWorkflows retrieves all open workflows in the namespace.
func (c *Cleaner) listOpenWorkflows(ctx context.Context, namespace string) ([]WorkflowExecution, error) {
	var workflows []WorkflowExecution
	var nextPageToken []byte

	for {
		resp, err := c.client.WorkflowService().ListOpenWorkflowExecutions(ctx, &workflowservice.ListOpenWorkflowExecutionsRequest{
			Namespace:       namespace,
			MaximumPageSize: 100,
			NextPageToken:   nextPageToken,
		})
		if err != nil {
			return nil, fmt.Errorf("failed to list open workflows: %w", err)
		}

		for _, execution := range resp.Executions {
			workflows = append(workflows, WorkflowExecution{
				WorkflowID: execution.Execution.WorkflowId,
				RunID:      execution.Execution.RunId,
			})
		}

		nextPageToken = resp.NextPageToken
		if len(nextPageToken) == 0 {
			break
		}
	}

	return workflows, nil
}

// terminateWorkflows terminates the given workflows and returns counts and errors.
// Includes retry logic for transient failures.
func (c *Cleaner) terminateWorkflows(ctx context.Context, namespace string, workflows []WorkflowExecution) (int, []TerminationError) {
	var terminated int
	var errors []TerminationError
	var mu sync.Mutex

	// Use a semaphore to limit concurrent terminations
	const maxConcurrent = 10
	const maxRetries = 3
	sem := make(chan struct{}, maxConcurrent)
	var wg sync.WaitGroup

	progressInterval := max(len(workflows)/10, 1)

	for i, wf := range workflows {
		// Log progress periodically
		if (i+1)%progressInterval == 0 || i == 0 {
			slog.Info("Cleanup progress", "processed", i+1, "total", len(workflows))
		}

		wg.Add(1)
		sem <- struct{}{} // Acquire semaphore

		go func(wf WorkflowExecution) {
			defer wg.Done()
			defer func() { <-sem }() // Release semaphore

			// Retry logic for transient failures
			var lastErr error
			for attempt := 1; attempt <= maxRetries; attempt++ {
				err := c.client.TerminateWorkflow(ctx, wf.WorkflowID, wf.RunID, "Benchmark cleanup - terminating workflows after benchmark completion")
				if err == nil {
					mu.Lock()
					terminated++
					mu.Unlock()
					return
				}

				lastErr = err

				// Check if error is retryable (transient)
				if !isRetryableError(err) {
					break
				}

				// Wait before retry with exponential backoff
				if attempt < maxRetries {
					select {
					case <-ctx.Done():
						break
					case <-time.After(time.Duration(attempt*100) * time.Millisecond):
					}
				}
			}

			mu.Lock()
			errors = append(errors, TerminationError{
				WorkflowID: wf.WorkflowID,
				RunID:      wf.RunID,
				Error:      lastErr,
			})
			mu.Unlock()
		}(wf)
	}

	wg.Wait()
	return terminated, errors
}

// isRetryableError determines if an error is transient and worth retrying.
func isRetryableError(err error) bool {
	if err == nil {
		return false
	}
	errStr := err.Error()
	// Retry on common transient errors
	return strings.Contains(errStr, "unavailable") ||
		strings.Contains(errStr, "deadline exceeded") ||
		strings.Contains(errStr, "connection") ||
		strings.Contains(errStr, "timeout")
}

// logCleanupSummary logs a summary of the cleanup operation.
func (c *Cleaner) logCleanupSummary(result *CleanupResult) {
	slog.Info("=== Cleanup Summary ===",
		"namespace", result.Namespace,
		"workflows_found", result.WorkflowsFound,
		"workflows_terminated", result.WorkflowsTerminated,
		"termination_errors", len(result.TerminationErrors),
		"duration", result.Duration,
		"success", result.Success)

	if !result.Success {
		// Log first few errors for debugging
		maxErrorsToLog := 5
		for i, termErr := range result.TerminationErrors {
			if i >= maxErrorsToLog {
				slog.Warn("Additional termination errors not shown",
					"remaining", len(result.TerminationErrors)-maxErrorsToLog)
				break
			}
			slog.Error("Failed to terminate workflow",
				"workflow_id", termErr.WorkflowID,
				"error", termErr.Error)
		}
	}
}

// logManualCleanupInstructions logs instructions for manual cleanup.
// Requirement 8.4: IF cleanup fails, THEN THE Benchmark_Runner SHALL log the failure
// and provide manual cleanup instructions.
func logManualCleanupInstructions(namespace string, err error) {
	slog.Error("=== MANUAL CLEANUP REQUIRED ===",
		"namespace", namespace,
		"error", err)
	slog.Info("To manually clean up workflows, run one of the following:")
	slog.Info("Using tctl:",
		"command", fmt.Sprintf("tctl --namespace %s workflow terminate --query 'ExecutionStatus=\"Running\"'", namespace))
	slog.Info("Using temporal CLI:",
		"command", fmt.Sprintf("temporal workflow terminate --namespace %s --query 'ExecutionStatus=\"Running\"'", namespace))
	slog.Info("To list running workflows first:",
		"command", fmt.Sprintf("temporal workflow list --namespace %s --query 'ExecutionStatus=\"Running\"'", namespace))
	slog.Info("To terminate a specific workflow:",
		"command", fmt.Sprintf("temporal workflow terminate --namespace %s --workflow-id <WORKFLOW_ID>", namespace))
}

// GetRunningWorkflowCount returns the count of running workflows in a namespace.
func (c *Cleaner) GetRunningWorkflowCount(ctx context.Context, namespace string) (int, error) {
	workflows, err := c.listOpenWorkflows(ctx, namespace)
	if err != nil {
		return 0, err
	}
	return len(workflows), nil
}

// VerifyCleanup checks that no running workflows remain in the namespace.
// Requirement 8.2: Verify cleanup completeness.
func (c *Cleaner) VerifyCleanup(ctx context.Context, namespace string) error {
	count, err := c.GetRunningWorkflowCount(ctx, namespace)
	if err != nil {
		return fmt.Errorf("failed to verify cleanup: %w", err)
	}

	if count > 0 {
		return fmt.Errorf("cleanup incomplete: %d workflows still running in namespace %s", count, namespace)
	}

	slog.Info("Cleanup verified: no running workflows", "namespace", namespace)
	return nil
}

// GenerateCleanupScript generates a shell script for manual cleanup.
// Requirement 8.4: Provide manual cleanup instructions.
func GenerateCleanupScript(namespace string, failedWorkflows []TerminationError) string {
	var sb strings.Builder

	sb.WriteString("#!/bin/bash\n")
	sb.WriteString("# Benchmark Cleanup Script\n")
	sb.WriteString(fmt.Sprintf("# Generated for namespace: %s\n", namespace))
	sb.WriteString(fmt.Sprintf("# Timestamp: %s\n\n", time.Now().Format(time.RFC3339)))

	sb.WriteString("NAMESPACE=\"" + namespace + "\"\n\n")

	sb.WriteString("echo \"Starting cleanup for namespace: $NAMESPACE\"\n\n")

	// If there are specific failed workflows, terminate them individually
	if len(failedWorkflows) > 0 {
		sb.WriteString("# Terminate specific failed workflows\n")
		for _, wf := range failedWorkflows {
			sb.WriteString(fmt.Sprintf("echo \"Terminating workflow: %s\"\n", wf.WorkflowID))
			sb.WriteString(fmt.Sprintf("temporal workflow terminate --namespace \"$NAMESPACE\" --workflow-id \"%s\" --run-id \"%s\" || true\n",
				wf.WorkflowID, wf.RunID))
		}
		sb.WriteString("\n")
	}

	// Add bulk termination command
	sb.WriteString("# Terminate all remaining running workflows\n")
	sb.WriteString("echo \"Terminating all running workflows...\"\n")
	sb.WriteString("temporal workflow terminate --namespace \"$NAMESPACE\" --query 'ExecutionStatus=\"Running\"' || true\n\n")

	// Add verification
	sb.WriteString("# Verify cleanup\n")
	sb.WriteString("echo \"Verifying cleanup...\"\n")
	sb.WriteString("REMAINING=$(temporal workflow list --namespace \"$NAMESPACE\" --query 'ExecutionStatus=\"Running\"' --limit 1 2>/dev/null | wc -l)\n")
	sb.WriteString("if [ \"$REMAINING\" -gt 0 ]; then\n")
	sb.WriteString("    echo \"WARNING: Some workflows may still be running\"\n")
	sb.WriteString("    temporal workflow list --namespace \"$NAMESPACE\" --query 'ExecutionStatus=\"Running\"'\n")
	sb.WriteString("else\n")
	sb.WriteString("    echo \"Cleanup complete: no running workflows found\"\n")
	sb.WriteString("fi\n")

	return sb.String()
}

// CleanupWithRetry performs cleanup with configurable retry attempts.
// Requirement 8.4: Handle cleanup failures gracefully.
func (c *Cleaner) CleanupWithRetry(ctx context.Context, namespace string, maxAttempts int) (*CleanupResult, error) {
	var lastResult *CleanupResult
	var lastErr error

	for attempt := 1; attempt <= maxAttempts; attempt++ {
		if attempt > 1 {
			slog.Info("Cleanup retry attempt", "attempt", attempt, "max_attempts", maxAttempts, "namespace", namespace)
			// Wait before retry
			select {
			case <-ctx.Done():
				return lastResult, ctx.Err()
			case <-time.After(time.Duration(attempt) * time.Second):
			}
		}

		result, err := c.CleanupNamespace(ctx, namespace)
		lastResult = result
		lastErr = err

		if err == nil && result.Success {
			return result, nil
		}

		// If we got partial success, continue to next attempt
		if result != nil && result.WorkflowsTerminated > 0 {
			slog.Info("Partial cleanup success, retrying remaining",
				"terminated", result.WorkflowsTerminated,
				"found", result.WorkflowsFound)
		}
	}

	// All attempts failed, provide comprehensive error
	if lastResult != nil && len(lastResult.TerminationErrors) > 0 {
		cleanupErr := &CleanupError{
			Namespace:         namespace,
			Phase:             "terminate",
			WorkflowsFound:    lastResult.WorkflowsFound,
			WorkflowsFailed:   len(lastResult.TerminationErrors),
			TerminationErrors: lastResult.TerminationErrors,
		}
		logManualCleanupInstructions(namespace, cleanupErr)

		// Generate and log cleanup script
		script := GenerateCleanupScript(namespace, lastResult.TerminationErrors)
		slog.Info("=== CLEANUP SCRIPT ===\n" + script + "\n======================")

		return lastResult, cleanupErr
	}

	return lastResult, lastErr
}
