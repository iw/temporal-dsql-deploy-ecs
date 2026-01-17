# Design: Ringpop Behavior Improvements for ECS on EC2

## Overview

This design addresses ringpop membership issues observed when running Temporal on ECS with EC2 instances. The core problem is that ringpop's membership model assumes relatively stable node IPs, but ECS assigns new IPs on every task launch.

## Current Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    CURRENT RINGPOP FLOW                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐         ┌─────────────────────────────────┐│
│  │  Temporal Task  │         │     cluster_membership table    ││
│  │                 │         │                                 ││
│  │  ┌───────────┐  │  Write  │  host_id | rpc_address | role   ││
│  │  │ Ringpop   │──┼────────►│  uuid    | 10.0.x.y    | 1-4    ││
│  │  │ Heartbeat │  │         │                                 ││
│  │  └───────────┘  │         │  last_heartbeat (updated every  ││
│  │       │         │         │  ~30s by default)               ││
│  │       ▼         │         └─────────────────────────────────┘│
│  │  ┌───────────┐  │                      │                     │
│  │  │ In-Memory │  │  Read (on startup    │                     │
│  │  │ Peer Cache│◄─┼──────────────────────┘                     │
│  │  └───────────┘  │  + periodic refresh)                       │
│  │       │         │                                            │
│  │       ▼         │                                            │
│  │  ┌───────────┐  │                                            │
│  │  │  gRPC to  │  │  May try to connect to dead IPs            │
│  │  │  Peers    │──┼───────────────────────────────────────────►│
│  │  └───────────┘  │                                            │
│  └─────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Problems with Current Design

1. **Heartbeat interval (30s default)**: Too slow for ECS where tasks can terminate in seconds
2. **No graceful deregistration**: Tasks don't remove themselves from membership on shutdown
3. **In-memory cache not invalidated**: Even after DB cleanup, cache retains stale peers
4. **No connection-failure feedback**: Failed connections don't trigger cache refresh

## Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    IMPROVED RINGPOP FLOW                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐         ┌─────────────────────────────────┐│
│  │  Temporal Task  │         │     cluster_membership table    ││
│  │                 │         │                                 ││
│  │  ┌───────────┐  │  Write  │  host_id | rpc_address | role   ││
│  │  │ Ringpop   │──┼────────►│  uuid    | 10.0.x.y    | 1-4    ││
│  │  │ Heartbeat │  │  (5s)   │                                 ││
│  │  └───────────┘  │         │  last_heartbeat (5s interval)   ││
│  │       │         │         │  draining (bool) ◄── NEW        ││
│  │       │         │         └─────────────────────────────────┘│
│  │  ┌────┴────┐    │                      │                     │
│  │  │Shutdown │    │  DELETE on SIGTERM   │                     │
│  │  │ Handler │────┼──────────────────────┘                     │
│  │  └─────────┘    │                                            │
│  │       │         │                                            │
│  │       ▼         │                                            │
│  │  ┌───────────┐  │  Read (10s refresh)  ┌───────────────────┐ │
│  │  │ In-Memory │◄─┼──────────────────────│  Background       │ │
│  │  │ Peer Cache│  │                      │  Cleanup (15s)    │ │
│  │  └───────────┘  │                      │  removes stale    │ │
│  │       │         │                      └───────────────────┘ │
│  │       │ Connection                                           │
│  │       │ Failure ──────► Immediate cache invalidation         │
│  │       ▼                 for failed peer                      │
│  │  ┌───────────┐  │                                            │
│  │  │  gRPC to  │  │                                            │
│  │  │  Peers    │──┼───────────────────────────────────────────►│
│  │  └───────────┘  │                                            │
│  └─────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

## Design Components

### Component 1: Graceful Shutdown Handler

**Location**: `common/membership/ringpop/service_resolver.go`

```go
// Enhanced shutdown handling
func (r *serviceResolver) Stop() {
    // 1. Mark self as draining in DB (optional, for gradual transition)
    r.markDraining()
    
    // 2. Wait for in-flight requests to complete (configurable timeout)
    r.drainTimeout()
    
    // 3. Remove self from cluster_membership
    r.deregister()
    
    // 4. Close connections
    r.closeConnections()
}

func (r *serviceResolver) deregister() error {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    
    return r.persistence.DeleteClusterMembership(ctx, &persistence.DeleteClusterMembershipRequest{
        HostID: r.hostID,
    })
}
```

**ECS Integration**: The entrypoint script should trap SIGTERM and allow graceful shutdown:

```bash
#!/bin/bash
# entrypoint.sh
trap 'kill -TERM $PID; wait $PID' TERM

./temporal-server start &
PID=$!
wait $PID
```

### Component 2: Configurable Heartbeat & Cleanup Intervals

**Location**: `common/dynamicconfig/constants.go`

```go
// New dynamic config keys for ECS-optimized membership
const (
    // MembershipHeartbeatInterval controls how often services update their heartbeat
    // Default: 30s, ECS recommended: 5s
    MembershipHeartbeatInterval = "membership.heartbeatInterval"
    
    // MembershipStaleThreshold controls when entries are considered stale
    // Default: 60s, ECS recommended: 15s  
    MembershipStaleThreshold = "membership.staleThreshold"
    
    // MembershipCacheRefreshInterval controls in-memory cache refresh
    // Default: 60s, ECS recommended: 10s
    MembershipCacheRefreshInterval = "membership.cacheRefreshInterval"
    
    // MembershipCleanupInterval controls background stale entry cleanup
    // Default: 60s, ECS recommended: 15s
    MembershipCleanupInterval = "membership.cleanupInterval"
)
```

**ECS Dynamic Config** (`dynamicconfig/ecs-membership.yaml`):

```yaml
# Optimized for ECS on EC2 where task IPs change frequently
membership.heartbeatInterval:
  - value: "5s"
    constraints: {}

membership.staleThreshold:
  - value: "15s"
    constraints: {}

membership.cacheRefreshInterval:
  - value: "10s"
    constraints: {}

membership.cleanupInterval:
  - value: "15s"
    constraints: {}
```

### Component 3: Connection Failure Feedback

**Location**: `common/membership/ringpop/service_resolver.go`

```go
// Enhanced peer tracking with failure detection
type peerState struct {
    address       string
    lastSeen      time.Time
    failureCount  int
    suspect       bool
}

func (r *serviceResolver) onConnectionFailure(address string, err error) {
    // Check if this is a "hard" failure (no route, connection refused)
    if isHardFailure(err) {
        r.mu.Lock()
        defer r.mu.Unlock()
        
        if peer, ok := r.peers[address]; ok {
            peer.failureCount++
            if peer.failureCount >= r.config.SuspectThreshold {
                peer.suspect = true
                r.metrics.IncCounter(metrics.MembershipPeerSuspected)
                
                // Trigger immediate cache refresh
                go r.refreshFromDatabase()
            }
        }
    }
}

func isHardFailure(err error) bool {
    errStr := err.Error()
    return strings.Contains(errStr, "no route to host") ||
           strings.Contains(errStr, "connection refused") ||
           strings.Contains(errStr, "network is unreachable")
}
```

### Component 4: Background Stale Entry Cleanup

**Location**: `common/membership/ringpop/monitor.go` (new file)

```go
// MembershipMonitor runs background cleanup of stale entries
type MembershipMonitor struct {
    persistence   persistence.ClusterMetadataManager
    config        *Config
    logger        log.Logger
    metrics       metrics.Handler
    stopCh        chan struct{}
}

func (m *MembershipMonitor) Start() {
    ticker := time.NewTicker(m.config.CleanupInterval)
    defer ticker.Stop()
    
    for {
        select {
        case <-ticker.C:
            m.cleanupStaleEntries()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MembershipMonitor) cleanupStaleEntries() {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    
    threshold := time.Now().Add(-m.config.StaleThreshold)
    
    deleted, err := m.persistence.PruneClusterMembership(ctx, &persistence.PruneClusterMembershipRequest{
        MaxLastHeartbeat: threshold,
    })
    
    if err != nil {
        m.logger.Error("Failed to prune stale membership entries", tag.Error(err))
        return
    }
    
    if deleted > 0 {
        m.logger.Info("Pruned stale membership entries", tag.Counter(deleted))
        m.metrics.AddCounter(metrics.MembershipEntriesPruned, int64(deleted))
    }
}
```

### Component 5: ECS Metadata Integration (Optional Enhancement)

**Location**: `common/membership/ringpop/ecs_detector.go` (new file)

```go
// ECSTaskDetector uses ECS metadata to detect task state
type ECSTaskDetector struct {
    metadataEndpoint string
    logger           log.Logger
}

func NewECSTaskDetector() *ECSTaskDetector {
    endpoint := os.Getenv("ECS_CONTAINER_METADATA_URI_V4")
    if endpoint == "" {
        return nil // Not running on ECS
    }
    return &ECSTaskDetector{metadataEndpoint: endpoint}
}

func (d *ECSTaskDetector) IsTaskStopping() bool {
    resp, err := http.Get(d.metadataEndpoint + "/task")
    if err != nil {
        return false
    }
    defer resp.Body.Close()
    
    var metadata struct {
        KnownStatus   string `json:"KnownStatus"`
        DesiredStatus string `json:"DesiredStatus"`
    }
    
    if err := json.NewDecoder(resp.Body).Decode(&metadata); err != nil {
        return false
    }
    
    // Task is stopping if desired status is STOPPED
    return metadata.DesiredStatus == "STOPPED"
}
```

## Database Schema Changes

### Option A: Add Draining Column (Recommended)

```sql
ALTER TABLE cluster_membership ADD COLUMN draining BOOLEAN DEFAULT FALSE;

-- Index for efficient cleanup queries
CREATE INDEX idx_cluster_membership_heartbeat ON cluster_membership(last_heartbeat);
```

### Option B: Use Existing Schema with Tighter Thresholds

No schema changes, just configure shorter heartbeat/cleanup intervals.

## Configuration Recommendations

### ECS on EC2 (Recommended Settings)

| Setting | Default | ECS Recommended | Rationale |
|---------|---------|-----------------|-----------|
| Heartbeat Interval | 30s | 5s | ECS tasks can terminate quickly |
| Stale Threshold | 60s | 15s | 3x heartbeat interval |
| Cache Refresh | 60s | 10s | Quick discovery of new peers |
| Cleanup Interval | 60s | 15s | Match stale threshold |
| Suspect Threshold | 3 | 2 | Faster failure detection |
| Drain Timeout | 30s | 10s | ECS stop timeout is 30s |

### ECS Task Definition Settings

```json
{
  "stopTimeout": 30,
  "healthCheck": {
    "command": ["CMD-SHELL", "curl -f http://localhost:7233/health || exit 1"],
    "interval": 10,
    "timeout": 5,
    "retries": 3,
    "startPeriod": 60
  }
}
```

## Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `membership_heartbeat_latency` | Histogram | Time to update heartbeat |
| `membership_entries_pruned` | Counter | Stale entries removed |
| `membership_peer_suspected` | Counter | Peers marked suspect |
| `membership_cache_refresh_latency` | Histogram | Cache refresh duration |
| `membership_deregister_success` | Counter | Successful deregistrations |
| `membership_deregister_failure` | Counter | Failed deregistrations |

## Migration Strategy

### Phase 1: Configuration Only (Low Risk)
1. Deploy with shorter heartbeat/cleanup intervals via dynamic config
2. Monitor for improvements in stale entry cleanup
3. No code changes required

### Phase 2: Graceful Shutdown (Medium Risk)
1. Implement shutdown handler with deregistration
2. Update entrypoint scripts to handle SIGTERM
3. Test with rolling deployments

### Phase 3: Connection Failure Feedback (Medium Risk)
1. Implement peer suspect tracking
2. Add immediate cache refresh on hard failures
3. Test with simulated network partitions

### Phase 4: Background Monitor (Low Risk)
1. Deploy membership monitor as separate goroutine
2. Configure cleanup intervals
3. Monitor pruning metrics

## Testing Strategy

### Unit Tests
- Shutdown handler deregistration
- Stale entry detection logic
- Connection failure classification
- Cache refresh triggers

### Integration Tests
- Rolling deployment simulation
- Task termination scenarios
- Network partition recovery
- Multi-service membership convergence

### Load Tests
- Membership churn under high throughput
- Cleanup performance with many stale entries
- Cache refresh impact on latency

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Aggressive cleanup removes healthy nodes | High | Use heartbeat interval as minimum threshold |
| Shutdown handler timeout exceeded | Medium | Configure ECS stop timeout > drain timeout |
| Database load from frequent heartbeats | Medium | Use batch updates, connection pooling |
| Cache refresh storms | Medium | Jitter refresh intervals, rate limit |

## Alternatives Considered

### Alternative 1: Use ECS Service Connect
- **Pros**: Built-in service discovery, no ringpop needed
- **Cons**: Requires significant architecture change, may not support all Temporal features

### Alternative 2: External Service Discovery (Consul, etcd)
- **Pros**: Purpose-built for service discovery
- **Cons**: Additional infrastructure, operational complexity

### Alternative 3: DNS-Based Discovery
- **Pros**: Simple, well-understood
- **Cons**: DNS TTL issues, slower convergence than ringpop

## Decision

Proceed with **Phase 1 (Configuration)** immediately, followed by **Phase 2 (Graceful Shutdown)** as the primary improvements. These provide the best risk/reward ratio for ECS deployments.
