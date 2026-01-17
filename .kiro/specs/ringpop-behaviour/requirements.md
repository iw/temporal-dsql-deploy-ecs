# Requirements: Ringpop Behavior Improvements for ECS on EC2

## Problem Statement

When running Temporal on ECS with EC2 instances, ringpop cluster membership can become stale during rolling deployments, service restarts, or task failures. This leads to:

1. **Stale membership entries**: Dead nodes remain in `cluster_membership` table, causing services to attempt connections to non-existent IPs
2. **In-memory cache staleness**: Even after DB cleanup, ringpop's in-memory cache retains stale peer information
3. **Slow convergence**: Services take time to discover new peers and remove dead ones
4. **Connection errors during deployments**: Rolling deployments cause temporary connection failures as old tasks drain

## Observed Issues

### Issue 1: Stale Database Entries
- **Symptom**: `cluster_membership` table contains entries for IPs that no longer exist
- **Cause**: Tasks terminated without graceful shutdown, or heartbeat interval too long
- **Impact**: New services try to connect to dead peers on startup

### Issue 2: In-Memory Cache Staleness  
- **Symptom**: Services continue trying to reach dead IPs even after DB cleanup
- **Cause**: Ringpop caches peer list in memory, doesn't immediately reflect DB changes
- **Impact**: Requires service restart to clear stale cache

### Issue 3: ECS Task IP Volatility
- **Symptom**: Each new task gets a new IP address
- **Cause**: ECS assigns IPs from VPC subnet pool dynamically
- **Impact**: Membership churn during every deployment

### Issue 4: Rolling Deployment Disruption
- **Symptom**: Connection errors during ECS rolling deployments
- **Cause**: Old tasks drain while new tasks start, membership in flux
- **Impact**: Temporary service degradation, error logs

---

## Requirements

### REQ-1: Graceful Shutdown Handling
**EARS Format**: When a Temporal service receives SIGTERM, the system shall remove its entry from `cluster_membership` before exiting.

**Acceptance Criteria**:
- [ ] Service removes own membership entry on shutdown signal
- [ ] Removal completes within ECS stop timeout (default 30s)
- [ ] Other services stop routing to draining node within 5 seconds

### REQ-2: Faster Stale Entry Detection
**EARS Format**: The system shall detect and remove stale membership entries within 30 seconds of a node becoming unreachable.

**Acceptance Criteria**:
- [ ] Heartbeat interval configurable (default: 5s for ECS)
- [ ] Stale threshold configurable (default: 30s for ECS)
- [ ] Background cleanup process removes entries exceeding threshold

### REQ-3: In-Memory Cache Refresh
**EARS Format**: When the `cluster_membership` table changes, the system shall refresh in-memory peer cache within 10 seconds.

**Acceptance Criteria**:
- [ ] Periodic cache refresh from database
- [ ] Immediate refresh on connection failure to cached peer
- [ ] Configurable refresh interval

### REQ-4: ECS Metadata Integration
**EARS Format**: When running on ECS, the system shall use ECS task metadata to detect task state changes.

**Acceptance Criteria**:
- [ ] Detect own task stopping via metadata endpoint
- [ ] Optionally use ECS service events for peer discovery
- [ ] Handle metadata endpoint unavailability gracefully

### REQ-5: Deployment-Aware Membership
**EARS Format**: During rolling deployments, the system shall prioritize routing to healthy new tasks over draining old tasks.

**Acceptance Criteria**:
- [ ] Detect draining state from ECS metadata or health checks
- [ ] Mark draining nodes in membership with reduced priority
- [ ] New tasks fully join before old tasks marked for removal

### REQ-6: Connection Failure Fast-Path
**EARS Format**: When a connection to a peer fails with "no route to host" or "connection refused", the system shall immediately mark that peer as suspect.

**Acceptance Criteria**:
- [ ] Immediate suspect marking on network errors
- [ ] Suspect peers excluded from routing after N failures (default: 2)
- [ ] Suspect status cleared on successful connection

---

## Non-Functional Requirements

### NFR-1: Performance
- Membership operations shall not add more than 5ms latency to requests
- Background cleanup shall use less than 1% CPU

### NFR-2: Reliability
- Membership system shall remain functional if database is temporarily unavailable
- Cached membership shall be used as fallback during DB outages

### NFR-3: Observability
- Metrics for membership churn rate
- Metrics for stale entry cleanup
- Alerts for excessive membership changes

---

## Out of Scope

- Changes to ringpop protocol itself (upstream dependency)
- Service mesh integration (Envoy, App Mesh)
- Multi-region membership federation
- Kubernetes-specific optimizations (focus is ECS on EC2)

---

## References

- [Temporal Ringpop Implementation](https://github.com/temporalio/temporal/tree/main/common/membership/ringpop)
- [ECS Task Metadata Endpoint](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-metadata-endpoint.html)
- [ECS Container Stop Timeout](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#container_definition_timeout)
