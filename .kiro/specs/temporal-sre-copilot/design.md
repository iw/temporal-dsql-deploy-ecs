# Design Document: Temporal SRE Copilot

## Overview

The Temporal SRE Copilot is an AI-powered observability agent that provides intelligent health monitoring for Temporal deployments running on Aurora DSQL. The system runs as a separate Temporal cluster using Pydantic AI workflows to continuously observe signals, derive health state from forward progress, and produce actionable assessments with natural language explanations.

### Key Design Decisions

1. **Separate Temporal Cluster**: The Copilot runs on its own ECS cluster to ensure isolation from the monitored deployment. A failure in the Copilot cannot impact the production Temporal services.

2. **Pydantic AI + Temporal**: Using Pydantic AI's native Temporal integration provides durable execution for LLM-powered analysis. If an LLM call fails mid-analysis, Temporal automatically retries from the last checkpoint.

3. **Health State Machine**: Health is derived from forward progress using deterministic rules. The state machine has three canonical states (Happy, Stressed, Critical) with well-defined transitions anchored to the forward progress invariant.

4. **"Rules Decide, AI Explains"**: Deterministic rules evaluate primary signals and set health state. The LLM receives the state and explains/ranks issues—it never decides state transitions or applies thresholds.

5. **Signal Taxonomy**: Signals are classified into Primary (decide state), Amplifiers (explain why), and Narrative (logs that explain transitions). This separation ensures health is anchored to progress, not pain.

6. **JSON API for Grafana**: A simple REST API exposes health assessments to Grafana's JSON API data source. Grafana consumes pre-computed values—it never computes health state.

7. **DSQL State Store**: Health assessments are persisted to Aurora DSQL, dogfooding the same database technology as the monitored deployment.

8. **Multi-Agent Architecture**: Following the Pydantic AI Temporal example patterns, we use a dispatcher agent for fast triage and a research agent for deep explanation. This saves costs and reduces latency for simple health checks.

9. **Same VPC Deployment**: The Copilot ECS cluster runs in the same VPC as the monitored Temporal cluster, enabling direct access to AMP, Loki, and DSQL without public endpoints.

10. **Modern Python Tooling**: Python 3.13+ with uv for package management, ruff for linting/formatting, and ty for type checking.


## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         COPILOT ECS CLUSTER (Same VPC)                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │
│  │  Temporal Server    │  │  Copilot Worker     │  │  API Service        │ │
│  │  (single-binary)    │  │  (Pydantic AI)      │  │  (FastAPI)          │ │
│  │                     │  │                     │  │                     │ │
│  │  - DSQL for         │  │  Workflows:         │  │  Endpoints:         │ │
│  │    workflow state   │  │  - MetricWatcher    │  │  - /status          │ │
│  │  - Same DSQL as     │  │  - LogWatcher       │  │  - /status/services │ │
│  │    state store      │  │  - DeepAnalysis     │  │  - /status/issues   │ │
│  │                     │  │  - Scheduled        │  │  - /status/summary  │ │
│  │                     │  │                     │  │  - /status/timeline │ │
│  │                     │  │  Agents:            │  │                     │ │
│  │                     │  │  - Dispatcher       │  │                     │ │
│  │                     │  │    (Sonnet 4.5)     │  │                     │ │
│  │                     │  │  - Researcher       │  │                     │ │
│  │                     │  │    (Opus 4.5)       │  │                     │ │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘ │
│           │                        │                        │              │
│           └────────────────────────┼────────────────────────┘              │
│                                    │                                       │
│  ┌─────────────────────────────────▼─────────────────────────────────────┐ │
│  │                    DSQL STATE STORE                                   │ │
│  │  Tables:                                                              │ │
│  │  - health_assessments (assessment history)                            │ │
│  │  - issues (active/resolved issues)                                    │ │
│  │  - metrics_snapshots (sliding window)                                 │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                    BEDROCK KNOWLEDGE BASE                             │ │
│  │  - S3 data source (AGENTS.md, docs/dsql/*.md, dashboard guides)       │ │
│  │  - Titan Embeddings V2 for vectorization                              │ │
│  │  - S3 Vectors for storage (low-cost vector store)                     │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
         │                    │                    │
         │ Queries            │ Invokes            │ Queries
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Amazon Managed  │  │ Amazon Bedrock  │  │ Loki            │
│ Prometheus      │  │                 │  │ (Logs)          │
│ (Metrics)       │  │ Claude Opus 4.5 │  │                 │
│                 │  │ Claude Sonnet   │  │                 │
│                 │  │ Titan Embed V2  │  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         │
         │ Queries JSON API
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GRAFANA - TEMPORAL COPILOT                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─ Advisor ─────────────────────────────────┐  ┌─ Status Filter ─────────┐│
│  │                                           │  │ 🟢 Happy  🟡 Stressed   ││
│  │  🤖  ● STRESSED                           │  │ 🔴 Critical             ││
│  │      Confidence: 82%  Just now            │  └─────────────────────────┘│
│  │                                           │                              │
│  │  Workflow progress continues, but History │  ┌─ Signal Metrics ────────┐│
│  │  backlog and DSQL contention increasing.  │  │ State Trans/sec  182 ↑  ││
│  │                                           │  │ Backlog Age      47s    ││
│  │  ⚠️ History backlog age rising:           │  │ DSQL Latency     92ms   ││
│  │     persistence latency amplifying        │  │ OCC Conflicts    38/s   ││
│  │     contention.                           │  │ Pool Util        86%    ││
│  └───────────────────────────────────────────┘  └─────────────────────────┘│
│                                                                             │
│  ┌─ Copilot Insights ───────────────────────────────────────────────────────┐
│  │                                                                          │
│  │  📊 Analysis                        💡 Suggested Remediations            │
│  │  ─────────────────────────────      ─────────────────────────────────    │
│  │  ⚠️ Persistence latency rising;     🟢 Increase History replicas   71%  │
│  │     amplifying contention in           History backlog rising faster    │
│  │     History service.                   than processing rate             │
│  │                                                                          │
│  │  🔥 DSQL conflicts increased;       🟡 Increase DSQL connection    58%  │
│  │     OCC contention > 30/s is           pool                             │
│  │     unhealthy.                         Pool utilization > 80%           │
│  │                                                                          │
│  │  📉 Instances shedding DSQL                      [ View Guide > ]        │
│  │     connections ("reservoir                                              │
│  │     discard") repeatedly.                                                │
│  └──────────────────────────────────────────────────────────────────────────┘
│                                                                             │
│  ┌─ Log Pattern Alerts ─────────────────────────────────────────────────────┐
│  │  Occurrences   Pattern                              Service              │
│  │  ───────────   ─────────────────────────────────    ─────────            │
│  │  128 times     DSQL reservoir discard               🏷️ history           │
│  └──────────────────────────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────────────────────────┘
```

### Multi-Agent Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         HEALTH EVALUATION FLOW                              │
│                      "Rules Decide, AI Explains"                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐     ┌─────────────────────────────────────────────────┐   │
│  │   Signals   │────▶│        HEALTH STATE MACHINE (Deterministic)     │   │
│  │  Collected  │     │                                                 │   │
│  │             │     │  Primary Signals → Evaluate Forward Progress    │   │
│  └─────────────┘     │                                                 │   │
│                      │  if progress_healthy and no_pressure:           │   │
│                      │      state = HAPPY                              │   │
│                      │  elif progress_continues and pressure_detected: │   │
│                      │      state = STRESSED                           │   │
│                      │  elif progress_impaired:                        │   │
│                      │      state = CRITICAL                           │   │
│                      │                                                 │   │
│                      │  Output: health_state (no LLM involved)         │   │
│                      └─────────────────────────────────────────────────┘   │
│                                         │                                   │
│                                         │ state + signals                   │
│                                         ▼                                   │
│                      ┌─────────────────────────────────────────────────┐   │
│                      │           DISPATCHER AGENT                      │   │
│                      │           (Claude Sonnet 4.5)                   │   │
│                      │                                                 │   │
│                      │  Fast triage: ~1-2 seconds                      │   │
│                      │  Receives: health_state (already decided)       │   │
│                      │                                                 │   │
│                      │  Outputs:                                       │   │
│                      │  ├── NoExplanationNeeded → Return state only    │   │
│                      │  ├── QuickExplanation → Brief summary           │   │
│                      │  └── NeedsDeepExplanation → Delegate            │   │
│                      └─────────────────────────────────────────────────┘   │
│                                         │                                   │
│                                         │ NeedsDeepExplanation              │
│                                         ▼                                   │
│                      ┌─────────────────────────────────────────────────┐   │
│                      │           RESEARCHER AGENT                      │   │
│                      │           (Claude Opus 4.5)                     │   │
│                      │                                                 │   │
│                      │  Deep explanation: ~10-20 seconds               │   │
│                      │  Receives: health_state + all signals + RAG     │   │
│                      │                                                 │   │
│                      │  Output: HealthAssessment                       │   │
│                      │  ├── Explanation of current state               │   │
│                      │  ├── Ranked contributing factors                │   │
│                      │  ├── Suggested actions with confidence          │   │
│                      │  └── Natural language summary                   │   │
│                      │                                                 │   │
│                      │  NOTE: Does NOT change health_state             │   │
│                      └─────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Health State Machine

The Health State Machine is the core of the Copilot's decision-making. It derives health from the **forward progress invariant**: "Is the cluster making forward progress on workflows?"

### Canonical States

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         HEALTH STATE MACHINE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│     ┌─────────┐                                                             │
│     │  HAPPY  │  Forward progress healthy, no concerning amplifiers         │
│     │   🟢    │  "Everything is working as expected"                        │
│     └────┬────┘                                                             │
│          │                                                                  │
│          │ amplifiers indicate pressure                                     │
│          │ (but progress continues)                                         │
│          ▼                                                                  │
│     ┌──────────┐                                                            │
│     │ STRESSED │  Forward progress continues but amplifiers show pressure   │
│     │    🟡    │  "Working, but under strain"                               │
│     └────┬─────┘                                                            │
│          │                                                                  │
│          │ forward progress impaired                                        │
│          │ (backlog growing, completions dropping)                          │
│          ▼                                                                  │
│     ┌──────────┐                                                            │
│     │ CRITICAL │  Forward progress is impaired or stopped                   │
│     │    🔴    │  "Workflows are not completing"                            │
│     └──────────┘                                                            │
│                                                                             │
│  INVARIANT: Happy → Critical transition MUST go through Stressed            │
│             (prevents over-eager critical alerts)                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### State Transition Rules (Pseudo-code)

```python
def evaluate_health_state(primary_signals: PrimarySignals, 
                          amplifiers: AmplifierSignals,
                          current_state: HealthState) -> HealthState:
    """
    Deterministic health evaluation - NO LLM INVOLVED.
    Rules are code, not prompts.
    """
    
    # Forward progress indicators
    progress_healthy = (
        primary_signals.state_transitions_per_sec > PROGRESS_THRESHOLD and
        primary_signals.backlog_age_sec < BACKLOG_HEALTHY_THRESHOLD
    )
    
    progress_impaired = (
        primary_signals.state_transitions_per_sec < PROGRESS_CRITICAL_THRESHOLD or
        primary_signals.backlog_age_sec > BACKLOG_CRITICAL_THRESHOLD
    )
    
    # Amplifier pressure indicators
    pressure_detected = (
        amplifiers.dsql_latency_ms > LATENCY_PRESSURE_THRESHOLD or
        amplifiers.occ_conflicts_per_sec > CONFLICT_PRESSURE_THRESHOLD or
        amplifiers.pool_utilization_pct > POOL_PRESSURE_THRESHOLD
    )
    
    # State transitions (anchored to progress, not pain)
    if progress_impaired:
        return HealthState.CRITICAL
    elif progress_healthy and not pressure_detected:
        return HealthState.HAPPY
    elif progress_healthy and pressure_detected:
        return HealthState.STRESSED
    else:
        # Progress continues but not fully healthy
        return HealthState.STRESSED
```

### Key Principle: Anchor to Progress, Not Pain

The state machine deliberately avoids "over-eager critical" alerts:

| Scenario | State | Rationale |
|----------|-------|-----------|
| High latency, workflows completing | STRESSED | Pain exists, but progress continues |
| Low latency, backlog growing | CRITICAL | No pain, but progress impaired |
| High latency, backlog growing | CRITICAL | Both pain and impaired progress |
| Low latency, workflows completing | HAPPY | No pain, progress healthy |

## Signal Taxonomy

Signals are classified into three categories that serve distinct purposes in health evaluation:

### Primary Signals (Decide State)

Primary signals answer the forward progress question. They are the ONLY inputs to state transitions.

| Signal | Description | Healthy Range |
|--------|-------------|---------------|
| State Transitions/sec | Workflow state machine progress | > 50/sec |
| Task Completions/sec | Activity and workflow task completions | > 100/sec |
| Backlog Age (sec) | Age of oldest pending task | < 30 sec |
| Workflow Completion Rate | Workflows completing vs starting | > 95% |

### Amplifier Signals (Explain Why)

Amplifiers explain WHY the state is what it is. They do NOT decide state—they provide context.

| Signal | Description | Pressure Threshold |
|--------|-------------|-------------------|
| DSQL Latency (ms) | Persistence operation latency | > 100ms |
| OCC Conflicts/sec | Optimistic concurrency conflicts | > 30/sec |
| Pool Utilization (%) | Connection pool usage | > 80% |
| Shard Churn Rate | Shard acquisitions + releases | > 5/sec |
| Schedule-to-Start (ms) | Task queue wait time | > 100ms |

### Narrative Signals (Logs Explain Transitions)

Log patterns provide narrative context for state transitions. They are fetched when state changes.

| Pattern | Service | Indicates |
|---------|---------|-----------|
| `reservoir discard` | history | Connection pool pressure |
| `SQLSTATE 40001` | all | OCC serialization failure |
| `member joined/left` | all | Ringpop membership change |
| `shard acquired/released` | history | Shard ownership change |
| `rate limit exceeded` | all | DSQL connection rate limit |

## Components and Interfaces

### 1. Copilot Worker Service

The worker service hosts Pydantic AI workflows that perform monitoring and analysis.

#### Workflow: ObserveClusterWorkflow

Continuously observes cluster signals and triggers health assessment when state changes.

```python
from temporalio import workflow
from pydantic_ai.durable_exec.temporal import PydanticAIWorkflow, TemporalAgent
from datetime import timedelta

@workflow.defn
class ObserveClusterWorkflow(PydanticAIWorkflow):
    """Continuous signal observation with health state evaluation."""
    
    @workflow.run
    async def run(self) -> None:
        current_state = HealthState.HAPPY
        
        while True:
            # Fetch current signals from AMP
            signals = await workflow.execute_activity(
                fetch_signals_from_amp,
                start_to_close_timeout=timedelta(seconds=30)
            )
            
            # Store signals in sliding window
            await workflow.execute_activity(
                store_signals_snapshot,
                args=[signals],
                start_to_close_timeout=timedelta(seconds=10)
            )
            
            # DETERMINISTIC: Evaluate health state (no LLM)
            new_state = evaluate_health_state(
                signals.primary,
                signals.amplifiers,
                current_state
            )
            
            # Trigger assessment if state changed or on schedule
            if new_state != current_state:
                await workflow.start_child_workflow(
                    AssessHealthWorkflow,
                    args=[new_state, signals, "state_change"],
                    id=f"assess-health-{workflow.now().isoformat()}"
                )
                current_state = new_state
            
            await workflow.sleep(timedelta(seconds=30))
```


#### Workflow: LogWatcherWorkflow

Continuously scans Loki for error patterns (narrative signals).

```python
@workflow.defn
class LogWatcherWorkflow(PydanticAIWorkflow):
    """Continuous log monitoring for narrative signals."""
    
    @workflow.run
    async def run(self) -> None:
        while True:
            # Query Loki for error patterns
            log_events = await workflow.execute_activity(
                query_loki_errors,
                start_to_close_timeout=timedelta(seconds=30)
            )
            
            # Detect error patterns (narrative signals)
            patterns = detect_error_patterns(log_events, ERROR_PATTERNS)
            
            if patterns:
                # Store patterns for correlation with health assessments
                await workflow.execute_activity(
                    store_log_patterns,
                    args=[patterns],
                    start_to_close_timeout=timedelta(seconds=10)
                )
            
            await workflow.sleep(timedelta(seconds=30))
```

#### Workflow: AssessHealthWorkflow

LLM-powered explanation of health state. Following "Rules decide, AI explains" principle.

```python
from pydantic_ai import Agent
from pydantic import BaseModel
from typing import List, Optional, Union

# Dispatcher agent - fast, lightweight triage
# NOTE: Receives health_state that was ALREADY DECIDED by rules
class NoExplanationNeeded(BaseModel):
    """State is clear, no detailed explanation required."""
    reason: str

class QuickExplanation(BaseModel):
    """Simple explanation without deep analysis."""
    summary: str

class NeedsDeepExplanation(BaseModel):
    """Complex situation, delegate to research agent for detailed explanation."""
    contributing_factors: List[str]
    priority: str  # low, medium, high

DispatcherOutput = Union[NoExplanationNeeded, QuickExplanation, NeedsDeepExplanation]

dispatcher_agent = Agent(
    'bedrock:anthropic.claude-sonnet-4-5-20250514-v1:0',  # Fast, cost-effective
    instructions="""You are a quick triage agent for Temporal health explanation.
    
    IMPORTANT: The health state has ALREADY BEEN DECIDED by deterministic rules.
    Your job is to decide how much explanation is needed, NOT to change the state.
    
    Given the health state and signals, determine:
    1. NoExplanationNeeded - state is obvious from signals, no explanation needed
    2. QuickExplanation - provide brief summary of why state is what it is
    3. NeedsDeepExplanation - complex situation, delegate for detailed analysis
    
    Be fast and decisive. Only escalate when truly needed.""",
    result_type=DispatcherOutput,
    name='health_dispatcher'
)

# Research agent - thorough explanation with RAG
# NOTE: Does NOT change health_state - only explains it
class Issue(BaseModel):
    severity: str  # warning, critical
    title: str
    description: str
    likely_cause: str
    suggested_actions: List[SuggestedAction]
    related_signals: List[str]

class HealthAssessment(BaseModel):
    timestamp: str
    health_state: str  # Passed in, NOT decided by LLM
    primary_signals: dict
    amplifiers: dict
    log_patterns: List[dict]
    issues: List[Issue]
    recommended_actions: List[dict]
    natural_language_summary: str

research_agent = Agent(
    'bedrock:anthropic.claude-opus-4-5-20251124-v1:0',  # Most capable for deep analysis
    instructions="""You are an SRE expert EXPLAINING Temporal service health.
    
    CRITICAL: The health state has ALREADY BEEN DECIDED by deterministic rules.
    You MUST NOT change the health_state. Your job is to EXPLAIN it.
    
    Given the health state, signals, logs, and context from the knowledge base:
    1. Explain WHY the cluster is in this state
    2. Rank contributing factors by importance
    3. Suggest remediation actions with confidence scores
    
    Be concise but thorough. Focus on actionable insights.""",
    result_type=HealthAssessment,
    name='health_explainer'
)

temporal_dispatcher = TemporalAgent(dispatcher_agent)
temporal_researcher = TemporalAgent(research_agent)

@workflow.defn
class AssessHealthWorkflow(PydanticAIWorkflow):
    """LLM-powered health explanation. Rules decide, AI explains."""
    __pydantic_ai_agents__ = [temporal_dispatcher, temporal_researcher]
    
    @workflow.run
    async def run(
        self, 
        health_state: HealthState,  # ALREADY DECIDED by rules
        signals: Signals, 
        trigger: str
    ) -> HealthAssessment:
        # First, run dispatcher for fast triage
        dispatch_result = await temporal_dispatcher.run(
            f"Health State: {health_state}\n"
            f"Primary Signals: {signals.primary}\n"
            f"Amplifiers: {signals.amplifiers}\n"
            f"Trigger: {trigger}"
        )
        
        # Handle dispatcher output
        if isinstance(dispatch_result.output, NoExplanationNeeded):
            # Return minimal assessment
            return create_minimal_assessment(health_state, signals)
        
        if isinstance(dispatch_result.output, QuickExplanation):
            # Return quick assessment
            return create_quick_assessment(
                health_state,
                signals,
                dispatch_result.output.summary
            )
        
        # NeedsDeepExplanation - run the research agent
        # Fetch RAG context based on contributing factors
        context = await workflow.execute_activity(
            fetch_rag_context,
            args=[dispatch_result.output.contributing_factors],
            start_to_close_timeout=timedelta(seconds=30)
        )
        
        # Fetch recent log patterns (narrative signals)
        log_patterns = await workflow.execute_activity(
            fetch_recent_log_patterns,
            start_to_close_timeout=timedelta(seconds=30)
        )
        
        # Fetch signal history
        history = await workflow.execute_activity(
            fetch_signal_history,
            start_to_close_timeout=timedelta(seconds=30)
        )
        
        # Build prompt with all context
        # NOTE: health_state is passed in, NOT decided by LLM
        prompt = build_explanation_prompt(
            health_state,  # Already decided
            signals, 
            log_patterns, 
            context, 
            history
        )
        
        # Run deep explanation via research agent
        result = await temporal_researcher.run(prompt)
        
        # Ensure health_state wasn't changed by LLM
        result.output.health_state = health_state.value
        
        # Store assessment
        await workflow.execute_activity(
            store_health_assessment,
            args=[result.output],
            start_to_close_timeout=timedelta(seconds=30)
        )
        
        return result.output
```


#### Workflow: ScheduledAssessmentWorkflow

Periodic health assessment even without state changes.

```python
@workflow.defn
class ScheduledAssessmentWorkflow(PydanticAIWorkflow):
    """Scheduled periodic health assessment."""
    
    @workflow.run
    async def run(self) -> None:
        while True:
            # Check if recent assessment exists (avoid duplicate work)
            recent = await workflow.execute_activity(
                check_recent_assessment,
                args=[timedelta(minutes=4)],
                start_to_close_timeout=timedelta(seconds=10)
            )
            
            if not recent:
                # Fetch current signals
                signals = await workflow.execute_activity(
                    fetch_signals_from_amp,
                    start_to_close_timeout=timedelta(seconds=30)
                )
                
                # Evaluate health state (deterministic)
                health_state = evaluate_health_state(
                    signals.primary,
                    signals.amplifiers,
                    HealthState.HAPPY  # Default for scheduled
                )
                
                await workflow.start_child_workflow(
                    AssessHealthWorkflow,
                    args=[health_state, signals, "scheduled"],
                    id=f"scheduled-assessment-{workflow.now().isoformat()}"
                )
            
            await workflow.sleep(timedelta(minutes=5))
```

### 2. Activities

Activities perform I/O operations and are automatically retried by Temporal on failure.

```python
from temporalio import activity
import boto3
import httpx

@activity.defn
async def fetch_metrics_from_amp() -> dict:
    """Query Amazon Managed Prometheus for current metrics."""
    client = boto3.client('amp')
    
    queries = {
        # Reservoir metrics
        'reservoir_size': 'sum(dsql_reservoir_size)',
        'reservoir_target': 'sum(dsql_reservoir_target)',
        'reservoir_empty': 'sum(increase(dsql_reservoir_empty_total[5m]))',
        'checkout_p95_ms': 'histogram_quantile(0.95, sum by (le) (rate(dsql_reservoir_checkout_latency_milliseconds_bucket[1m])))',
        
        # Service metrics
        'service_error_rate': 'sum(rate(service_error_with_type_total[1m]))',
        'persistence_latency_p95': 'histogram_quantile(0.95, sum by (le) (rate(persistence_latency_bucket[5m]))) * 1000',
        
        # History metrics
        'task_latency_p95': 'histogram_quantile(0.95, sum by (le) (rate(task_latency_processing_bucket{service_name="history"}[5m]))) * 1000',
        'shard_churn': 'sum(rate(sharditem_created_count_total[5m])) + sum(rate(sharditem_removed_count_total[5m]))',
        
        # Workflow metrics
        'workflow_success_rate': 'sum(rate(workflow_success_total[1m]))',
        'workflow_failure_rate': 'sum(rate(workflow_failed_total[1m]))',
        
        # OCC metrics
        'occ_conflicts': 'sum(rate(dsql_tx_conflict_total[1m]))',
        
        # Worker metrics
        'schedule_to_start_p95': 'histogram_quantile(0.95, sum(rate(temporal_workflow_task_schedule_to_start_latency_bucket[1m])) by (le)) * 1000',
        'workflow_slots_available': 'sum(temporal_worker_task_slots_available{worker_type="WorkflowWorker"})',
        'activity_slots_available': 'sum(temporal_worker_task_slots_available{worker_type="ActivityWorker"})',
    }
    
    results = {}
    for name, query in queries.items():
        response = await query_prometheus(client, query)
        results[name] = parse_prometheus_response(response)
    
    return results

@activity.defn
async def query_loki_errors() -> List[dict]:
    """Query Loki for error log patterns."""
    async with httpx.AsyncClient() as client:
        # Query for error-level logs in last 30 seconds
        response = await client.get(
            f"{LOKI_URL}/loki/api/v1/query_range",
            params={
                'query': '{job=~"temporal.*"} |= "error" or |= "ERROR"',
                'start': (datetime.now() - timedelta(seconds=30)).isoformat(),
                'end': datetime.now().isoformat(),
                'limit': 100
            }
        )
        return parse_loki_response(response.json())

@activity.defn
async def fetch_rag_context(anomalies: List[dict]) -> List[str]:
    """Retrieve relevant documentation from Bedrock Knowledge Base."""
    # Build query from anomaly descriptions
    query_text = " ".join([a['description'] for a in anomalies])
    
    bedrock_agent = boto3.client('bedrock-agent-runtime')
    
    response = bedrock_agent.retrieve(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        retrievalQuery={
            'text': query_text
        },
        retrievalConfiguration={
            'vectorSearchConfiguration': {
                'numberOfResults': 5
            }
        }
    )
    
    # Extract text content from results
    return [
        result['content']['text'] 
        for result in response['retrievalResults']
    ]
```


### 3. API Service

FastAPI service exposing health assessments to Grafana. Follows "Grafana consumes, not computes" principle.

```python
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timedelta
from typing import Optional

app = FastAPI(title="Temporal SRE Copilot API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Grafana access
    allow_methods=["GET"],
    allow_headers=["*"],
)

@app.get("/status")
async def get_status() -> dict:
    """Current health status with signal taxonomy. Grafana consumes, not computes."""
    assessment = await get_latest_assessment()
    return {
        "health_state": assessment.health_state,
        "timestamp": assessment.timestamp,
        "primary_signals": assessment.primary_signals,
        "amplifiers": assessment.amplifiers,
        "log_patterns": assessment.log_patterns,
        "recommended_actions": assessment.recommended_actions,
        "issue_count": len(assessment.issues)
    }

@app.get("/status/services")
async def get_services() -> dict:
    """Per-service health status for Grafana grid."""
    assessment = await get_latest_assessment()
    # Derive service health from signals (pre-computed)
    return {
        "services": [
            {
                "name": "history",
                "status": derive_service_status("history", assessment),
                "key_signals": extract_service_signals("history", assessment)
            },
            {
                "name": "matching",
                "status": derive_service_status("matching", assessment),
                "key_signals": extract_service_signals("matching", assessment)
            },
            {
                "name": "frontend",
                "status": derive_service_status("frontend", assessment),
                "key_signals": extract_service_signals("frontend", assessment)
            },
            {
                "name": "persistence",
                "status": derive_service_status("persistence", assessment),
                "key_signals": extract_service_signals("persistence", assessment)
            }
        ]
    }

@app.get("/status/issues")
async def get_issues(
    severity: Optional[str] = None,
    limit: int = Query(default=10, le=100)
) -> dict:
    """Active issues list with contributing factors."""
    assessment = await get_latest_assessment()
    issues = assessment.issues
    
    if severity:
        issues = [i for i in issues if i.severity == severity]
    
    return {
        "issues": [
            {
                "severity": i.severity,
                "title": i.title,
                "description": i.description,
                "likely_cause": i.likely_cause,
                "suggested_actions": [
                    {"action": a.description, "confidence": a.confidence}
                    for a in i.suggested_actions
                ],
                "related_signals": i.related_signals
            }
            for i in issues[:limit]
        ]
    }

@app.get("/status/summary")
async def get_summary() -> dict:
    """Natural language summary for Grafana text panel."""
    assessment = await get_latest_assessment()
    return {
        "summary": assessment.natural_language_summary,
        "timestamp": assessment.timestamp,
        "health_state": assessment.health_state
    }

@app.get("/status/timeline")
async def get_timeline(
    start: Optional[datetime] = None,
    end: Optional[datetime] = None
) -> dict:
    """Health status changes over time for Grafana state timeline."""
    if not start:
        start = datetime.now() - timedelta(hours=24)
    if not end:
        end = datetime.now()
    
    assessments = await get_assessments_in_range(start, end)
    
    return {
        "timeline": [
            {
                "timestamp": a.timestamp,
                "health_state": a.health_state,
                "issue_count": len(a.issues),
                "primary_signals": a.primary_signals
            }
            for a in assessments
        ]
    }

@app.post("/actions")
async def execute_action() -> dict:
    """Future: Execute remediation action. Currently returns 501."""
    return {"error": "Not implemented", "status": 501}
```

### 4. RAG Knowledge Base

The knowledge base uses Amazon Bedrock Knowledge Bases for fully managed RAG. This eliminates the need for pgvector (which DSQL doesn't support) and provides automatic chunking, embedding, and retrieval.

#### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BEDROCK KNOWLEDGE BASE                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐     ┌─────────────────────┐     ┌───────────────┐ │
│  │  S3 Data Source     │────▶│  Bedrock KB         │────▶│  S3 Vectors   │ │
│  │                     │     │  (managed)          │     │  (storage)    │ │
│  │  - AGENTS.md        │     │                     │     │               │ │
│  │  - docs/dsql/*.md   │     │  - Auto chunking    │     │  - Low cost   │ │
│  │  - Dashboard guides │     │  - Titan Embed V2   │     │  - Scalable   │ │
│  │  - Runbooks         │     │  - Sync on update   │     │               │ │
│  └─────────────────────┘     └─────────────────────┘     └───────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Terraform Configuration

```hcl
# S3 bucket for knowledge base source documents
resource "aws_s3_bucket" "copilot_kb_source" {
  bucket = "${var.project_name}-copilot-kb-source"
}

# Bedrock Knowledge Base
resource "aws_bedrockagent_knowledge_base" "copilot" {
  name        = "${var.project_name}-copilot-kb"
  description = "Knowledge base for Temporal SRE Copilot"
  role_arn    = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.copilot_kb_vectors.arn
    }
  }
}

# S3 data source for the knowledge base
resource "aws_bedrockagent_data_source" "copilot_docs" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.copilot.id
  name              = "copilot-documentation"
  
  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.copilot_kb_source.arn
    }
  }
}
```

#### Activity for RAG Retrieval

```python
@activity.defn
async def fetch_rag_context(anomalies: List[dict]) -> List[str]:
    """Retrieve relevant documentation from Bedrock Knowledge Base."""
    # Build query from anomaly descriptions
    query_text = " ".join([a['description'] for a in anomalies])
    
    bedrock_agent = boto3.client('bedrock-agent-runtime')
    
    response = bedrock_agent.retrieve(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        retrievalQuery={
            'text': query_text
        },
        retrievalConfiguration={
            'vectorSearchConfiguration': {
                'numberOfResults': 5
            }
        }
    )
    
    # Extract text content from results
    return [
        result['content']['text'] 
        for result in response['retrievalResults']
    ]
```

#### Document Sync

Documents are synced to S3 and the knowledge base is updated:

```python
async def sync_knowledge_base() -> None:
    """Sync documentation to S3 and trigger KB ingestion."""
    s3 = boto3.client('s3')
    bedrock_agent = boto3.client('bedrock-agent')
    
    # Upload documents to S3
    sources = [
        ('temporal-dsql-deploy-ecs/AGENTS.md', 'AGENTS.md'),
        ('temporal-dsql/docs/dsql/overview.md', 'docs/dsql/overview.md'),
        ('temporal-dsql/docs/dsql/reservoir-design.md', 'docs/dsql/reservoir-design.md'),
    ]
    
    for local_path, s3_key in sources:
        with open(local_path, 'rb') as f:
            s3.upload_fileobj(f, KB_SOURCE_BUCKET, s3_key)
    
    # Trigger knowledge base sync
    bedrock_agent.start_ingestion_job(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        dataSourceId=DATA_SOURCE_ID
    )
```


## Data Models

### Health Assessment Schema

```sql
CREATE TABLE health_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    trigger VARCHAR(50) NOT NULL,  -- 'anomaly', 'log_error', 'scheduled'
    overall_status VARCHAR(20) NOT NULL,  -- 'happy', 'stressed', 'critical'
    services JSONB NOT NULL,
    issues JSONB NOT NULL,
    natural_language_summary TEXT NOT NULL,
    metrics_snapshot JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ASYNC idx_assessments_timestamp ON health_assessments(timestamp DESC);
CREATE INDEX ASYNC idx_assessments_status ON health_assessments(overall_status);

-- Issues table for efficient querying
CREATE TABLE issues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID REFERENCES health_assessments(id) ON DELETE CASCADE,
    severity VARCHAR(20) NOT NULL,
    title VARCHAR(500) NOT NULL,
    description TEXT NOT NULL,
    likely_cause TEXT,
    suggested_actions JSONB,
    related_metrics JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE INDEX ASYNC idx_issues_severity ON issues(severity);
CREATE INDEX ASYNC idx_issues_created ON issues(created_at DESC);

-- Metrics snapshots for trend analysis
CREATE TABLE metrics_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metrics JSONB NOT NULL
);

CREATE INDEX ASYNC idx_snapshots_timestamp ON metrics_snapshots(timestamp DESC);
```

### Pydantic Models

```python
from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime
from enum import Enum

class HealthState(str, Enum):
    """Canonical health states derived from forward progress."""
    HAPPY = "happy"      # Forward progress healthy, no concerning amplifiers
    STRESSED = "stressed"  # Progress continues but amplifiers indicate pressure
    CRITICAL = "critical"  # Forward progress is impaired or stopped

class Severity(str, Enum):
    WARNING = "warning"
    CRITICAL = "critical"

class ActionType(str, Enum):
    SCALE = "scale"
    RESTART = "restart"
    CONFIGURE = "configure"
    ALERT = "alert"

class SuggestedAction(BaseModel):
    action_type: ActionType
    target_service: str
    description: str
    confidence: float = Field(ge=0.0, le=1.0)
    parameters: Optional[dict] = None
    risk_level: str = "low"  # low, medium, high

class Issue(BaseModel):
    severity: Severity
    title: str
    description: str
    likely_cause: str
    suggested_actions: List[SuggestedAction]
    related_signals: List[str]  # Changed from related_metrics
    related_logs: Optional[List[str]] = None

class PrimarySignals(BaseModel):
    """Signals that decide health state (forward progress indicators)."""
    state_transitions_per_sec: float
    task_completions_per_sec: float
    backlog_age_sec: float
    workflow_completion_rate: float

class AmplifierSignals(BaseModel):
    """Signals that explain why state changed (resource pressure, contention)."""
    dsql_latency_ms: float
    occ_conflicts_per_sec: float
    pool_utilization_pct: float
    shard_churn_rate: float
    schedule_to_start_ms: float

class LogPattern(BaseModel):
    """Narrative signal from logs."""
    count: int
    pattern: str
    service: str
    sample_message: Optional[str] = None

class Signals(BaseModel):
    """Complete signal collection with taxonomy."""
    primary: PrimarySignals
    amplifiers: AmplifierSignals
    timestamp: datetime

class HealthAssessment(BaseModel):
    """
    Health assessment with signal taxonomy.
    NOTE: health_state is determined by rules, NOT by LLM.
    """
    timestamp: datetime
    trigger: str  # 'state_change', 'scheduled'
    health_state: HealthState  # Determined by rules, passed to LLM
    primary_signals: dict
    amplifiers: dict
    log_patterns: List[LogPattern]
    issues: List[Issue]
    recommended_actions: List[SuggestedAction]
    natural_language_summary: str
```


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Signal Classification Correctness

*For any* set of signals collected from AMP, primary signals SHALL be forward progress indicators (state transitions, completions, backlog age) and amplifier signals SHALL be resource pressure indicators (latency, conflicts, utilization).

**Validates: Requirements 1.2, 1.3**

### Property 2: Sliding Window Invariant

*For any* sequence of signal snapshots added to the sliding window, the window SHALL contain only the most recent N snapshots (where N is the configured window size), and older snapshots SHALL be evicted in FIFO order.

**Validates: Requirements 1.6**

### Property 3: Log Pattern Detection

*For any* set of log entries containing error patterns, the pattern detection function SHALL identify all matching patterns as narrative signals.

**Validates: Requirements 2.2, 2.3**

### Property 4: Log-Signal Correlation

*For any* set of log events and signal snapshots with timestamps, the correlation function SHALL associate log events with signal snapshots if and only if their timestamps are within the configured proximity window.

**Validates: Requirements 2.5**

### Property 5: RAG Semantic Retrieval

*For any* contributing factor description, the RAG system SHALL return at most 5 documents, and all returned documents SHALL have a semantic similarity score above the configured threshold, ordered by descending similarity. Retrieved documents SHALL NOT contain raw metrics or PromQL queries.

**Validates: Requirements 3.2, 3.3, 3.4, 3.6**

### Property 6: Health Assessment Structure Round-Trip

*For any* valid HealthAssessment object, serializing to JSON and deserializing back SHALL produce an equivalent object with all required fields (timestamp, health_state, primary_signals, amplifiers, log_patterns, recommended_actions, natural_language_summary).

**Validates: Requirements 4.3**

### Property 7: Prompt Construction Completeness

*For any* AssessHealthWorkflow invocation with health_state, signals, logs, and context, the constructed prompt SHALL include the pre-determined health_state and all provided inputs, and SHALL NOT include any values matching sensitive data patterns (credentials, API keys, PII).

**Validates: Requirements 4.5, 4.9**

### Property 8: State Store Round-Trip

*For any* valid HealthAssessment stored in the state store, querying by timestamp range SHALL return the assessment if and only if its timestamp falls within the queried range.

**Validates: Requirements 5.2, 5.4**

### Property 9: API Response Format

*For any* API endpoint response, the response SHALL conform to the signal taxonomy structure (health_state, primary_signals, amplifiers, log_patterns, recommended_actions), include all required fields for the endpoint type, and correctly filter by any provided query parameters (severity, time range, limit).

**Validates: Requirements 6.1, 6.2, 6.3**

### Property 10: Assessment Deduplication

*For any* scheduled assessment trigger, if an assessment was completed within the deduplication window, the scheduled trigger SHALL NOT initiate a new assessment.

**Validates: Requirements 9.5**

### Property 11: Suggested Action Structure

*For any* issue in a health assessment, all suggested actions SHALL include action_type, target_service, description, confidence, and risk_level fields to support future automation.

**Validates: Requirements 10.2**

### Property 12: Health State Machine Invariants

*For any* sequence of signal observations, the Health State Machine SHALL:
1. Derive state from forward progress invariant ("Is the cluster making forward progress?")
2. Never transition directly from Happy to Critical (Stressed is always intermediate)
3. Produce deterministic state for identical inputs (no LLM involvement in state transitions)

**Validates: Requirements 12.2, 12.3, 12.5**

## Error Handling

### Metric Ingestion Failures

- **AMP Query Timeout**: Log error, skip cycle, retry on next iteration
- **AMP Authentication Failure**: Log error, alert, continue with cached metrics
- **Invalid Metric Response**: Log warning, use default/zero value for affected metric

### Log Query Failures

- **Loki Unavailable**: Log error, continue with metric-only analysis
- **Loki Query Timeout**: Log warning, proceed without log context
- **Invalid Log Format**: Skip malformed entries, continue processing

### LLM Analysis Failures

- **Bedrock Timeout**: Retry with exponential backoff (max 3 attempts)
- **Bedrock Rate Limit**: Queue analysis, retry after backoff
- **Bedrock Unavailable**: Fall back to threshold-based assessment without LLM
- **Invalid LLM Response**: Log error, retry with simplified prompt

### State Store Failures

- **DSQL Connection Error**: Retry with exponential backoff
- **OCC Conflict**: Automatic retry (DSQL plugin handles this)
- **Write Failure**: Log error, continue operation (assessment available in memory)

### API Service Failures

- **State Store Unavailable**: Return degraded status response with cached data
- **Request Timeout**: Return partial response with available data
- **Invalid Request**: Return 400 with descriptive error message


## Testing Strategy

### Unit Tests

Unit tests verify specific examples and edge cases:

1. **Threshold Evaluation**: Test each metric type against its threshold
2. **Pattern Matching**: Test each log pattern against sample log entries
3. **Correlation Logic**: Test timestamp proximity calculation
4. **Prompt Construction**: Test sensitive data filtering
5. **API Response Formatting**: Test each endpoint's response structure

### Property-Based Tests

Property tests verify universal properties across generated inputs using `hypothesis`:

```python
from hypothesis import given, strategies as st

@given(st.dictionaries(
    keys=st.sampled_from(['reservoir_empty', 'service_error_rate', 'persistence_latency_p95']),
    values=st.floats(min_value=0, max_value=10000)
))
def test_anomaly_detection_correctness(metrics):
    """Property 1: Anomaly detection identifies all threshold violations."""
    anomalies = detect_anomalies(metrics, THRESHOLDS)
    
    for metric, value in metrics.items():
        threshold = THRESHOLDS.get(metric)
        if threshold and value > threshold:
            assert any(a['metric'] == metric for a in anomalies)
        elif threshold and value <= threshold:
            assert not any(a['metric'] == metric for a in anomalies)

@given(st.lists(st.builds(MetricSnapshot), min_size=0, max_size=100))
def test_sliding_window_invariant(snapshots):
    """Property 2: Sliding window maintains size invariant."""
    window = SlidingWindow(max_size=10)
    
    for snapshot in snapshots:
        window.add(snapshot)
    
    assert len(window) <= 10
    if len(snapshots) >= 10:
        assert len(window) == 10
        # Verify FIFO order
        expected = snapshots[-10:]
        assert list(window) == expected

@given(st.builds(HealthAssessment))
def test_health_assessment_round_trip(assessment):
    """Property 6: Health assessment serialization round-trip."""
    json_str = assessment.model_dump_json()
    restored = HealthAssessment.model_validate_json(json_str)
    
    assert restored.timestamp == assessment.timestamp
    assert restored.overall_status == assessment.overall_status
    assert restored.services == assessment.services
    assert restored.issues == assessment.issues
    assert restored.natural_language_summary == assessment.natural_language_summary
```

### Integration Tests

Integration tests verify component interactions:

1. **Workflow Execution**: Test MetricWatcher → DeepAnalysis workflow chain
2. **RAG Pipeline**: Test Bedrock Knowledge Base retrieval with mocked responses
3. **API → State Store**: Test API queries against populated state store
4. **Bedrock Integration**: Test LLM invocation with mocked responses

### Test Configuration

- Property tests: Minimum 100 iterations per property
- Each property test tagged with: `Feature: temporal-service-health, Property N: {property_text}`
- Integration tests tagged with `integration` marker
- Use `pytest-asyncio` for async test support

## Infrastructure

### Terraform Module Structure

```
terraform/modules/copilot/
├── main.tf           # ECS cluster, services, task definitions
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── iam.tf            # IAM roles and policies
├── networking.tf     # Security groups, VPC endpoints
├── dsql.tf           # DSQL state store configuration
└── grafana.tf        # Grafana data source configuration
```

### ECS Task Definitions

```hcl
# Temporal Server (single-binary mode with DSQL)
resource "aws_ecs_task_definition" "copilot_temporal" {
  family                   = "${var.project_name}-copilot-temporal"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  
  container_definitions = jsonencode([{
    name  = "temporal"
    image = "${var.temporal_dsql_image}"  # Use temporal-dsql image
    environment = [
      { name = "TEMPORAL_ADDRESS", value = "0.0.0.0:7233" },
      { name = "TEMPORAL_SQL_PLUGIN", value = "dsql" },
      { name = "TEMPORAL_SQL_HOST", value = var.dsql_endpoint },
      { name = "TEMPORAL_SQL_PORT", value = "5432" },
      { name = "TEMPORAL_SQL_DATABASE", value = "copilot" },
      { name = "TEMPORAL_SQL_TLS_ENABLED", value = "true" },
      { name = "TEMPORAL_SQL_IAM_AUTH", value = "true" },
      { name = "AWS_REGION", value = var.aws_region },
      # Reservoir configuration for DSQL
      { name = "DSQL_RESERVOIR_ENABLED", value = "true" },
      { name = "DSQL_RESERVOIR_TARGET_READY", value = "20" },
      { name = "DSQL_RESERVOIR_BASE_LIFETIME", value = "11m" },
    ]
    portMappings = [{ containerPort = 7233 }]
  }])
  
  task_role_arn = aws_iam_role.copilot_task.arn
}

# Copilot Worker
resource "aws_ecs_task_definition" "copilot_worker" {
  family                   = "${var.project_name}-copilot-worker"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = 2048
  memory                   = 4096
  
  container_definitions = jsonencode([{
    name  = "worker"
    image = "${var.copilot_image}"
    command = ["python", "-m", "copilot.worker"]
    environment = [
      { name = "TEMPORAL_ADDRESS", value = "copilot-temporal:7233" },
      { name = "AMP_WORKSPACE_ID", value = var.amp_workspace_id },
      { name = "LOKI_URL", value = var.loki_url },
      { name = "DSQL_ENDPOINT", value = var.dsql_endpoint },
      { name = "AWS_REGION", value = var.aws_region }
    ]
  }])
  
  task_role_arn = aws_iam_role.copilot_task.arn
}

# API Service
resource "aws_ecs_task_definition" "copilot_api" {
  family                   = "${var.project_name}-copilot-api"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  
  container_definitions = jsonencode([{
    name  = "api"
    image = "${var.copilot_image}"
    command = ["uvicorn", "copilot.api:app", "--host", "0.0.0.0", "--port", "8080"]
    portMappings = [{ containerPort = 8080 }]
    environment = [
      { name = "DSQL_ENDPOINT", value = var.dsql_endpoint },
      { name = "AWS_REGION", value = var.aws_region }
    ]
  }])
  
  task_role_arn = aws_iam_role.copilot_task.arn
}
```

### IAM Permissions

```hcl
resource "aws_iam_role_policy" "copilot_task" {
  name = "${var.project_name}-copilot-task-policy"
  role = aws_iam_role.copilot_task.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics",
          "aps:GetMetricMetadata"
        ]
        Resource = var.amp_workspace_arn
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-opus-4-5-*",
          "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-sonnet-4-5-*",
          "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve"
        ]
        Resource = aws_bedrockagent_knowledge_base.copilot.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dsql:DbConnect",
          "dsql:DbConnectAdmin"
        ]
        Resource = var.dsql_cluster_arn
      }
    ]
  })
}
```

### Grafana Data Source Configuration

```yaml
# provisioning/datasources/copilot.yaml
apiVersion: 1
datasources:
  - name: Copilot
    type: marcusolsson-json-datasource
    access: proxy
    url: http://copilot-api:8080
    jsonData:
      httpMethod: GET
```


## Python Project Structure

### Tooling

The project uses modern Python tooling:

- **Python 3.13+**: Modern Python version for best performance and type hints
- **uv**: Fast Python package manager and project management
- **ruff**: Fast linter and formatter (replaces black, isort, flake8)
- **typer**: Elegant CLI framework with Rich integration
- **rich**: Beautiful terminal formatting

### Project Layout

The Copilot is a separate workspace (`temporal-sre-copilot/`) from the main deployment:

```
temporal-sre-copilot/
├── pyproject.toml          # Project configuration (uv, ruff)
├── uv.lock                  # Locked dependencies
├── terraform/              # Copilot-specific Terraform
│   ├── main.tf             # ECS cluster, log groups
│   ├── variables.tf        # Input variables
│   ├── terraform.tfvars.example  # Template with values from temporal-dsql-deploy-ecs
│   ├── iam.tf              # IAM roles and policies
│   ├── networking.tf       # Security groups
│   ├── ec2.tf              # Launch template, ASG, capacity provider
│   ├── services.tf         # Task definitions and ECS services
│   ├── knowledge_base.tf   # S3 buckets for KB
│   └── outputs.tf          # Output values
├── src/
│   └── copilot/
│       ├── __init__.py
│       ├── api.py           # FastAPI application
│       ├── worker.py        # Temporal worker entry point
│       ├── cli/             # Typer CLI commands
│       │   ├── __init__.py  # Main CLI app
│       │   ├── db.py        # Database commands
│       │   └── kb.py        # Knowledge base commands
│       ├── workflows/
│       │   ├── __init__.py
│       │   ├── metric_watcher.py
│       │   ├── log_watcher.py
│       │   ├── deep_analysis.py
│       │   └── scheduled_analysis.py
│       ├── activities/
│       │   ├── __init__.py
│       │   ├── metrics.py   # AMP queries
│       │   ├── logs.py      # Loki queries
│       │   ├── rag.py       # Knowledge base
│       │   └── storage.py   # DSQL operations
│       ├── agents/
│       │   ├── __init__.py
│       │   ├── dispatcher.py
│       │   └── researcher.py
│       ├── models/
│       │   ├── __init__.py
│       │   ├── health.py    # HealthAssessment, Issue, etc.
│       │   └── config.py    # Configuration models
│       └── db/
│           ├── __init__.py
│           └── schema.sql   # DSQL schema
├── tests/
│   ├── __init__.py
│   ├── conftest.py          # Pytest fixtures
│   ├── test_anomaly_detection.py
│   ├── test_pattern_matching.py
│   ├── test_rag.py
│   ├── test_api.py
│   └── properties/          # Property-based tests
│       ├── __init__.py
│       ├── test_sliding_window.py
│       ├── test_health_assessment.py
│       └── test_correlation.py
└── Dockerfile               # Multi-stage build
```

### pyproject.toml

```toml
[project]
name = "temporal-sre-copilot"
version = "0.1.0"
description = "AI-powered observability agent for Temporal deployments"
requires-python = ">=3.13"
dependencies = [
    "pydantic>=2.10",
    "pydantic-ai>=0.1",
    "temporalio>=1.10",
    "fastapi>=0.115",
    "uvicorn>=0.34",
    "httpx>=0.28",
    "boto3>=1.36",
    "asyncpg>=0.30",
    "typer>=0.15",
    "rich>=13.9",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.3",
    "pytest-asyncio>=0.25",
    "hypothesis>=6.122",
    "ruff>=0.9",
]

[project.scripts]
copilot = "copilot.cli:app"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/copilot"]

[tool.ruff]
target-version = "py313"
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "SIM", "TCH"]

[tool.ruff.format]
quote-style = "double"

[tool.pytest.ini_options]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "function"
testpaths = ["tests"]
```

### CLI Commands

The Copilot provides a Typer CLI for management operations:

```bash
# Database commands
copilot db setup-schema --endpoint <dsql-endpoint> --database copilot
copilot db check-connection --endpoint <dsql-endpoint>
copilot db list-tables --endpoint <dsql-endpoint>

# Knowledge base commands
copilot kb sync --bucket <s3-bucket> --source ./docs
copilot kb start-ingestion --kb-id <kb-id> --ds-id <data-source-id>
copilot kb status --kb-id <kb-id>
copilot kb list-jobs --kb-id <kb-id> --ds-id <data-source-id>
```

### Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.13-slim AS builder

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY src/ src/

FROM python:3.13-slim AS runtime

WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src /app/src

ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH="/app/src"

# Default to worker, override in task definition
CMD ["python", "-m", "copilot.worker"]
```

## Terraform Structure

The Copilot Terraform is in a separate workspace (`temporal-sre-copilot/terraform/`) and references dependent resources from `temporal-dsql-deploy-ecs` via `terraform.tfvars`:

```hcl
# terraform.tfvars.example - values from temporal-dsql-deploy-ecs
project_name = "temporal-bench"
aws_region   = "eu-west-1"

# From: cd ../temporal-dsql-deploy-ecs/terraform/envs/bench && terraform output
vpc_id             = "vpc-xxxxxxxxxxxxxxxxx"
private_subnet_ids = ["subnet-xxx", "subnet-xxx"]
vpc_cidr           = "10.0.0.0/16"
dsql_endpoint      = "xxx.dsql.eu-west-1.on.aws"
dsql_cluster_arn   = "arn:aws:dsql:eu-west-1:123456789012:cluster/xxx"
amp_workspace_id   = "ws-xxx"
amp_workspace_arn  = "arn:aws:aps:eu-west-1:123456789012:workspace/ws-xxx"
loki_url           = "http://loki:3100"
loki_security_group_id = "sg-xxx"
```

## VPC and Networking

The Copilot cluster runs in the same VPC as the monitored Temporal cluster for direct access to internal services.

```hcl
# Copilot services use the same VPC
resource "aws_ecs_service" "copilot_worker" {
  # ...
  network_configuration {
    subnets          = var.private_subnet_ids  # Same subnets as Temporal
    security_groups  = [aws_security_group.copilot.id]
    assign_public_ip = false
  }
}

# Security group allows access to AMP, Loki, DSQL
resource "aws_security_group" "copilot" {
  name        = "${var.project_name}-copilot"
  vpc_id      = var.vpc_id
  
  # Egress to AMP (via VPC endpoint)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  # Egress to Loki
  egress {
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [var.loki_security_group_id]
  }
  
  # Egress to DSQL (via VPC endpoint or public endpoint)
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}
```


## Cost Analysis (24-Hour Estimate)

This section provides a cost estimate for running the Temporal SRE Copilot for 24 hours.

### Assumptions

- **Analysis frequency**: 
  - Scheduled deep analysis: every 5 minutes = 288/day
  - Anomaly-triggered analysis: ~50/day (estimated)
  - Total deep analyses: ~340/day
- **Dispatcher calls**: Every 30 seconds = 2,880/day
- **RAG retrievals**: 1 per deep analysis = ~340/day
- **Knowledge base size**: ~50 documents, ~500KB total
- **Average prompt size**: 
  - Dispatcher: ~2,000 input tokens, ~200 output tokens
  - Researcher: ~8,000 input tokens, ~2,000 output tokens

### LLM Costs (Amazon Bedrock)

| Model | Usage | Input Tokens | Output Tokens | Cost |
|-------|-------|--------------|---------------|------|
| Claude Sonnet 4.5 (Dispatcher) | 2,880 calls | 5.76M | 0.58M | $17.28 + $8.64 = **$25.92** |
| Claude Opus 4.5 (Researcher) | 340 calls | 2.72M | 0.68M | $13.60 + $17.00 = **$30.60** |

**Pricing used:**
- Claude Sonnet 4.5: $3/1M input, $15/1M output
- Claude Opus 4.5: $5/1M input, $25/1M output

**Total LLM cost: ~$56.52/day**

### Embedding Costs (Amazon Titan)

| Usage | Tokens | Cost |
|-------|--------|------|
| RAG queries (340 × ~500 tokens) | 170K | $0.0034 |
| KB ingestion (one-time, ~100K tokens) | 100K | $0.002 |

**Pricing:** $0.00002/1K tokens

**Total embedding cost: ~$0.01/day** (negligible)

### Knowledge Base Storage (S3 Vectors)

| Component | Usage | Cost |
|-----------|-------|------|
| Vector storage | ~50 documents, ~500KB | ~$0.01/day |
| Vector queries | 340 queries | ~$0.01/day |
| S3 storage | ~1MB source docs | ~$0.00003/day |

**Total KB cost: ~$0.02/day** (negligible)

### Compute Costs (ECS)

| Service | vCPU | Memory | Hours | Cost |
|---------|------|--------|-------|------|
| Temporal Server | 1 | 2GB | 24 | ~$1.20 |
| Copilot Worker | 2 | 4GB | 24 | ~$2.40 |
| API Service | 0.5 | 1GB | 24 | ~$0.60 |

**Pricing:** ~$0.05/vCPU-hour (Graviton, on-demand)

**Total compute cost: ~$4.20/day**

### DSQL Costs

| Component | Usage | Cost |
|-----------|-------|------|
| Workflow state | ~1000 writes/day | ~$0.50 |
| Health assessments | ~340 writes/day | ~$0.20 |
| Reads | ~5000 reads/day | ~$0.10 |

**Total DSQL cost: ~$0.80/day**

### Summary

| Category | Daily Cost | Monthly Cost |
|----------|------------|--------------|
| LLM (Claude) | $56.52 | $1,695.60 |
| Embeddings (Titan) | $0.01 | $0.30 |
| Knowledge Base (S3 Vectors) | $0.02 | $0.60 |
| Compute (ECS) | $4.20 | $126.00 |
| DSQL | $0.80 | $24.00 |
| **Total** | **$61.55** | **$1,846.50** |

### Cost Optimization Strategies

1. **Reduce dispatcher frequency**: Change from 30s to 60s → saves ~$13/day
2. **Use prompt caching**: Bedrock supports prompt caching at 90% discount for repeated context
3. **Batch analysis**: Combine multiple anomalies into single analysis → fewer Opus calls
4. **Adjust scheduled analysis**: Change from 5min to 15min → saves ~$20/day
5. **Use Haiku for simple triage**: Replace Sonnet with Haiku ($1/$5) for obvious healthy states → saves ~$20/day

### Cost-Optimized Configuration

With optimizations applied:

| Change | Savings |
|--------|---------|
| Dispatcher every 60s | -$13/day |
| Scheduled analysis every 15min | -$20/day |
| Haiku for 80% of dispatches | -$20/day |
| Prompt caching (50% hit rate) | -$15/day |

**Optimized total: ~$25-30/day (~$750-900/month)**
