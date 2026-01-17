# Tasks: Ringpop Behavior Improvements for ECS on EC2

## Overview

Implementation tasks for improving ringpop membership behavior when running Temporal on ECS with EC2 instances.

---

## Phase 1: Configuration Optimization (No Code Changes)

### Task 1.1: Create ECS-Optimized Dynamic Config
- [ ] Create `dynamicconfig/ecs-membership.yaml` with shorter intervals
- [ ] Document recommended settings for ECS deployments
- [ ] Test with current ECS deployment

**Settings to configure:**
```yaml
# Faster heartbeat for ECS task volatility
system.membershipMonitorInterval:
  - value: "5s"
    constraints: {}

# Note: Some settings may require code changes to be configurable
```

### Task 1.2: Update ECS Task Definitions
- [ ] Ensure `stopTimeout` is set appropriately (30s)
- [ ] Add health checks to task definitions
- [ ] Configure `initProcessEnabled` for proper signal handling

### Task 1.3: Document Current Behavior
- [ ] Document observed issues during deployments
- [ ] Create runbook for membership cleanup
- [ ] Add troubleshooting guide to AGENTS.md

---

## Phase 2: Graceful Shutdown Implementation

### Task 2.1: Implement Shutdown Deregistration
**Location**: `temporal-dsql/common/membership/ringpop/service_resolver.go`

- [ ] Add `deregister()` method to remove self from `cluster_membership`
- [ ] Call deregister in `Stop()` method before closing connections
- [ ] Add timeout handling (5s max for deregistration)
- [ ] Add metrics for deregistration success/failure

### Task 2.2: Update Entrypoint Script
**Location**: `temporal-dsql-deploy-ecs/docker/entrypoint.sh` or runtime image

- [ ] Add SIGTERM trap to entrypoint
- [ ] Ensure graceful shutdown signal reaches Temporal process
- [ ] Test with ECS task stop scenarios

### Task 2.3: Add Draining State Support (Optional)
- [ ] Add `draining` column to `cluster_membership` schema
- [ ] Mark self as draining before deregistration
- [ ] Update peer selection to deprioritize draining nodes

---

## Phase 3: Connection Failure Feedback

### Task 3.1: Implement Peer Suspect Tracking
**Location**: `temporal-dsql/common/membership/ringpop/service_resolver.go`

- [ ] Add `peerState` struct with failure tracking
- [ ] Implement `onConnectionFailure()` callback
- [ ] Add suspect threshold configuration
- [ ] Exclude suspect peers from routing

### Task 3.2: Implement Hard Failure Detection
- [ ] Create `isHardFailure()` function
- [ ] Detect "no route to host", "connection refused", etc.
- [ ] Trigger immediate cache refresh on hard failures

### Task 3.3: Add Failure Metrics
- [ ] Add `membership_peer_suspected` counter
- [ ] Add `membership_connection_failures` counter by error type
- [ ] Add dashboard for membership health

---

## Phase 4: Background Cleanup Monitor

### Task 4.1: Implement MembershipMonitor
**Location**: `temporal-dsql/common/membership/ringpop/monitor.go` (new file)

- [ ] Create `MembershipMonitor` struct
- [ ] Implement `Start()` with ticker-based cleanup
- [ ] Implement `cleanupStaleEntries()` using persistence layer
- [ ] Add graceful shutdown support

### Task 4.2: Add Persistence Method for Pruning
**Location**: `temporal-dsql/common/persistence/sql/sqlplugin/`

- [ ] Add `PruneClusterMembership()` method
- [ ] Implement for DSQL plugin
- [ ] Add unit tests

### Task 4.3: Integrate Monitor with Services
- [ ] Start monitor in each Temporal service
- [ ] Configure via dynamic config
- [ ] Add metrics for pruning operations

---

## Phase 5: ECS Metadata Integration (Optional)

### Task 5.1: Implement ECS Task Detector
**Location**: `temporal-dsql/common/membership/ringpop/ecs_detector.go` (new file)

- [ ] Create `ECSTaskDetector` struct
- [ ] Implement `IsTaskStopping()` using metadata endpoint
- [ ] Handle non-ECS environments gracefully

### Task 5.2: Integrate with Shutdown Handler
- [ ] Check ECS task status periodically
- [ ] Trigger early deregistration when task stopping detected
- [ ] Add metrics for ECS-triggered shutdowns

---

## Phase 6: Testing & Validation

### Task 6.1: Unit Tests
- [ ] Test deregistration logic
- [ ] Test stale entry detection
- [ ] Test connection failure classification
- [ ] Test cache refresh triggers

### Task 6.2: Integration Tests
- [ ] Test rolling deployment scenario
- [ ] Test task termination cleanup
- [ ] Test membership convergence time
- [ ] Test with simulated network failures

### Task 6.3: ECS Deployment Testing
- [ ] Deploy to temporal-dsql-deploy-ecs
- [ ] Run rolling deployment tests
- [ ] Measure membership convergence time
- [ ] Validate no stale entries after deployments

---

## Phase 7: Documentation

### Task 7.1: Update AGENTS.md
- [ ] Document ringpop behavior for ECS
- [ ] Add troubleshooting section
- [ ] Document configuration options

### Task 7.2: Create Runbook
- [ ] Membership cleanup procedures
- [ ] Rolling deployment best practices
- [ ] Monitoring and alerting setup

### Task 7.3: Update README
- [ ] Add section on membership management
- [ ] Document ECS-specific considerations

---

## Current Status

### Implementation Status: INVESTIGATION COMPLETE ✅

**Completed: January 2026**

This spec captured an investigation into ringpop membership behavior on ECS. Key findings:

1. **Root Cause Identified**: Stale membership entries were caused by:
   - MaxConnLifetime (55min) exceeding IAM token expiration (15min)
   - Services crashing before graceful deregistration
   - In-memory cache not refreshing from database

2. **Critical Fix Applied**: Reduced `MaxConnLifetime` from 55min to 12min in the DSQL plugin. This ensures connections are recycled before their embedded IAM tokens expire.

3. **Operational Procedures Documented**: 
   - `cluster-management.sh` script for membership cleanup
   - Recovery procedure: scale-down → clean-membership → scale-up

### Observed Issues (2026-01-15) - RESOLVED
1. ✅ **Stale Docker Compose entries**: Cleaned up 172.23.0.x entries from local testing
2. ✅ **Worker crash loop**: Fixed by MaxConnLifetime change (token expiration)
3. ✅ **Stale matching node (10.0.14.78)**: Required frontend restart to clear in-memory cache
4. ✅ **Membership table now clean**: All entries have recent heartbeats

### Deferred Tasks

The following tasks were identified but deferred as the critical fix (MaxConnLifetime) resolved the immediate issues:

- Phase 2: Graceful Shutdown Implementation (code changes to temporal-dsql)
- Phase 3: Connection Failure Feedback (code changes to temporal-dsql)
- Phase 4: Background Cleanup Monitor (code changes to temporal-dsql)
- Phase 5: ECS Metadata Integration (optional enhancement)

These can be revisited if membership issues recur in production.

---

## Dependencies

- `temporal-dsql` repository for code changes (Phases 2-5)
- `temporal-dsql-deploy-ecs` for testing and configuration (Phase 1)
- ECS task definition updates (Phase 1)

---

## Success Criteria

1. **No stale entries after rolling deployment**: `cluster_membership` table should have only active nodes within 30 seconds of deployment completion
2. **No connection errors to dead peers**: Services should not attempt connections to IPs that are no longer in the membership table
3. **Fast convergence**: New services should discover all peers within 15 seconds of startup
4. **Clean shutdown**: Terminated tasks should remove themselves from membership before exit
