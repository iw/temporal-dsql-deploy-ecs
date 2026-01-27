# Implementation Tasks

> **Note:** Tasks 10 (Grafana Dashboard) and 11 (Setup Script for DynamoDB Table) should be implemented in the `temporal-dsql-deploy` repository, not `temporal-dsql-deploy-ecs`.

## Task 1: Fix Compilation Issues

### Description
Fix duplicate constant declarations and other compilation errors in the reservoir implementation sketch.

### Files to Modify
- `common/persistence/sql/sqlplugin/dsql/distributed_conn_lease.go` - Remove duplicate constants
- `common/persistence/sql/sqlplugin/dsql/reservoir_config.go` - Keep as source of truth for helper functions

### Acceptance Criteria
- [x] Code compiles without errors
- [x] `go vet` passes
- [x] No duplicate symbol declarations

### Status: Completed

---

## Task 2: Add Initial Fill Synchronization

### Description
Add synchronous initial fill to ensure reservoir has connections before returning from `CreateDB`.

### Implementation
```go
// In plugin.go, after registering reservoir driver:
ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()
for res.Len() < cfg.LowWatermark {
    select {
    case <-ctx.Done():
        logger.Warn("Reservoir initial fill timeout", tag.NewInt("current", res.Len()), tag.NewInt("target", cfg.LowWatermark))
        break
    case <-time.After(100 * time.Millisecond):
    }
}
```

### Files to Modify
- `common/persistence/sql/sqlplugin/dsql/plugin.go`

### Acceptance Criteria
- [x] Service waits for reservoir to reach low watermark before accepting requests
- [x] Timeout prevents indefinite blocking
- [x] Warning logged if timeout reached

### Status: Completed

---

## Task 3: Add Brief Blocking Wait on Empty

### Description
Add optional brief blocking wait before returning `ErrBadConn` when reservoir is empty.

### Implementation
```go
func (d *reservoirDriver) Open(_ string) (driver.Conn, error) {
    now := time.Now().UTC()
    
    // Try non-blocking first
    if pc, ok := d.res.TryCheckout(now); ok {
        return newReservoirConn(d.res, pc), nil
    }
    
    // Brief wait for refiller to catch up
    select {
    case pc := <-d.res.ready:
        if pc != nil && now.Before(pc.ExpiresAt.Add(-d.res.guardWindow)) {
            return newReservoirConn(d.res, pc), nil
        }
        // Expired, discard and fall through
        if pc != nil {
            d.res.discard(pc, "expired_on_wait")
        }
    case <-time.After(100 * time.Millisecond):
    }
    
    return nil, driver.ErrBadConn
}
```

### Files to Modify
- `common/persistence/sql/sqlplugin/dsql/driver/reservoir_driver.go`

### Acceptance Criteria
- [x] Brief wait smooths out transient empty reservoir
- [x] Timeout prevents indefinite blocking
- [x] Expired connections during wait are discarded

### Status: Completed

---

## Task 4: Add Prometheus Metrics

### Description
Add Prometheus metrics for reservoir observability.

### Metrics to Add
| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `dsql_reservoir_size` | Gauge | service | Current reservoir size |
| `dsql_reservoir_target` | Gauge | service | Target reservoir size |
| `dsql_reservoir_checkouts_total` | Counter | service | Successful checkouts |
| `dsql_reservoir_empty_total` | Counter | service | Checkout when empty |
| `dsql_reservoir_discards_total` | Counter | service, reason | Discarded connections |
| `dsql_reservoir_refills_total` | Counter | service | Connections created |
| `dsql_reservoir_refill_failures_total` | Counter | service, reason | Failed creates |

### Files to Modify
- `common/persistence/sql/sqlplugin/dsql/metrics.go` - Add metric definitions
- `common/persistence/sql/sqlplugin/dsql/driver/reservoir.go` - Emit metrics
- `common/persistence/sql/sqlplugin/dsql/driver/reservoir_refiller.go` - Emit metrics

### Acceptance Criteria
- [x] All metrics defined and registered
- [x] Metrics emitted at appropriate points
- [x] Metrics visible in Prometheus/Grafana

### Status: In Progress

---

## Task 5: Improve Refiller Pacing

### Description
Improve refiller pacing to better utilize rate limit budget during warmup while maintaining steady-state efficiency.

### Implementation
```go
func (r *reservoirRefiller) loop() {
    // Calculate steady-state refill interval
    // With 11min lifetime and 50 connections, need ~0.076/sec = 1 every 13 seconds
    steadyStateInterval := time.Duration(float64(r.cfg.BaseLifetime) / float64(r.cfg.TargetReady))
    
    // During warmup, use faster interval (limited by rate limiter)
    warmupInterval := 50 * time.Millisecond
    
    for {
        ready := r.res.Len()
        need := r.cfg.TargetReady - ready
        
        if need <= 0 {
            sleepOrStop(r.stopC, steadyStateInterval)
            continue
        }
        
        // Use warmup interval when below target
        interval := warmupInterval
        if ready >= r.cfg.LowWatermark {
            interval = steadyStateInterval
        }
        
        r.openOne(ctx)
        sleepOrStop(r.stopC, interval)
    }
}
```

### Files to Modify
- `common/persistence/sql/sqlplugin/dsql/driver/reservoir_refiller.go`

### Acceptance Criteria
- [x] Warmup uses full rate limit budget
- [x] Steady state uses minimal rate limit budget
- [x] Smooth transition between modes

### Status: Completed

---

## Task 6: Track Connection Age Properly

### Description
Track connection creation time and compute remaining lifetime at checkout, rather than fixed expiry time.

### Implementation
```go
type PhysicalConn struct {
    Conn      driver.Conn
    CreatedAt time.Time  // When connection was established
    Lifetime  time.Duration  // Total lifetime (base + jitter)
    LeaseID   string
}

func (r *Reservoir) TryCheckout(now time.Time) (*PhysicalConn, bool) {
    select {
    case pc := <-r.ready:
        if pc == nil {
            return nil, false
        }
        
        // Compute remaining lifetime
        age := now.Sub(pc.CreatedAt)
        remaining := pc.Lifetime - age
        
        if remaining < r.guardWindow {
            r.discard(pc, "insufficient_remaining_lifetime")
            return nil, false
        }
        
        return pc, true
    default:
        return nil, false
    }
}
```

### Files to Modify
- `common/persistence/sql/sqlplugin/dsql/driver/reservoir.go`
- `common/persistence/sql/sqlplugin/dsql/driver/reservoir_refiller.go`

### Acceptance Criteria
- [x] Connection age tracked from creation
- [x] Remaining lifetime computed at checkout
- [x] Connections with insufficient remaining lifetime discarded

### Status: Completed

---

## Task 7: Add Unit Tests

### Description
Add comprehensive unit tests for reservoir components.

### Test Cases

**Reservoir Tests:**
- Checkout from non-empty reservoir
- Checkout from empty reservoir
- Return to non-full reservoir
- Return to full reservoir (discard)
- Guard window enforcement on checkout
- Guard window enforcement on return

**ReservoirConn Tests:**
- Close returns connection to reservoir
- Close with bad flag discards connection
- Double close is idempotent
- Interface forwarding works

**Refiller Tests:**
- Refills when below target
- Stops when at target
- Aggressive refill below low watermark
- Jitter applied to lifetime
- Handles rate limiter wait
- Handles lease acquire failure
- Graceful shutdown

**DistributedConnLeases Tests:**
- Acquire increments counter
- Acquire fails at limit
- Release decrements counter
- TTL set on lease items

### Files to Create
- `common/persistence/sql/sqlplugin/dsql/driver/reservoir_test.go`
- `common/persistence/sql/sqlplugin/dsql/driver/reservoir_conn_test.go`
- `common/persistence/sql/sqlplugin/dsql/driver/reservoir_refiller_test.go`
- `common/persistence/sql/sqlplugin/dsql/distributed_conn_lease_test.go`

### Acceptance Criteria
- [x] All test cases implemented
- [x] Tests pass
- [x] Good coverage of edge cases

### Status: Completed

---

## Task 8: Add Integration Tests

### Description
Add integration tests that verify reservoir behavior with actual DSQL connections.

### Test Cases
- End-to-end connection lifecycle
- Empty reservoir recovery
- Rate limit compliance
- Global limit enforcement (with DynamoDB)

### Files to Create
- `common/persistence/sql/sqlplugin/dsql/reservoir_integration_test.go`

### Acceptance Criteria
- [ ] Integration tests pass against DSQL
- [ ] Tests tagged for CI/CD filtering

### Status: Not Started

---

## Task 9: Update Documentation

### Description
Update DSQL documentation to cover reservoir mode.

### Documentation Updates
- `docs/dsql/implementation.md` - Add reservoir section
- `docs/dsql/metrics.md` - Add reservoir metrics
- `docs/dsql/reservoir-design.md` - Update with implementation details

### Acceptance Criteria
- [x] Documentation complete and accurate
- [x] Configuration options documented
- [x] Troubleshooting guidance included

### Status: Completed

---

## Task 10: Add Grafana Dashboard

### Description
Add Grafana dashboard panels for reservoir metrics.

### Panels to Add
- Reservoir size vs target (gauge)
- Checkout rate (rate graph)
- Empty reservoir events (counter)
- Discard rate by reason (stacked graph)
- Refill rate (rate graph)
- Refill failures (counter)

### Files to Modify
- `grafana/dsql/persistence.json`

### Acceptance Criteria
- [x] Dashboard panels added
- [x] Panels show meaningful data
- [ ] Alerts configured for empty reservoir

### Status: In Progress

---

## Task 11: Setup Script for Connection Lease DynamoDB Table

### Description
Add setup script for the connection lease DynamoDB table, following the pattern of `setup-rate-limiter-table.sh`.

### Script: `scripts/setup-conn-lease-table.sh`
```bash
#!/bin/bash
# Setup DynamoDB table for distributed DSQL connection lease tracking
#
# This table coordinates global connection count limiting across all Temporal
# service instances to respect DSQL's 10,000 max connections limit.
#
# Schema:
#   Counter item: pk=dsqllease_counter#<endpoint>
#     - active (Number): current connection count
#     - updated_ms (Number): last update timestamp
#   Lease items: pk=dsqllease#<endpoint>#<leaseID>
#     - ttl_epoch (Number): TTL for automatic cleanup
#     - service_name (String): service that owns the lease
#     - created_ms (Number): creation timestamp
#
# Usage:
#   ./scripts/setup-conn-lease-table.sh [table-name] [region]

set -euo pipefail

TABLE_NAME="${1:-temporal-dsql-conn-lease}"
REGION="${2:-${AWS_REGION:-eu-west-1}}"

echo "Creating DynamoDB table for connection lease tracking..."
echo "  Table: $TABLE_NAME"
echo "  Region: $REGION"

# Check if table already exists
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" &>/dev/null; then
    echo "✅ Table '$TABLE_NAME' already exists"
    exit 0
fi

# Create table with on-demand billing
aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions \
        AttributeName=pk,AttributeType=S \
    --key-schema \
        AttributeName=pk,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" \
    --output text \
    --query 'TableDescription.TableArn'

echo "Waiting for table to become active..."
aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$REGION"

# Enable TTL for automatic lease cleanup
echo "Enabling TTL on ttl_epoch attribute..."
aws dynamodb update-time-to-live \
    --table-name "$TABLE_NAME" \
    --time-to-live-specification "Enabled=true,AttributeName=ttl_epoch" \
    --region "$REGION" \
    --output text

echo ""
echo "✅ DynamoDB table '$TABLE_NAME' created successfully"
echo ""
echo "To enable distributed connection leasing, add to your .env:"
echo "  DSQL_DISTRIBUTED_CONN_LEASE_ENABLED=true"
echo "  DSQL_DISTRIBUTED_CONN_LEASE_TABLE=$TABLE_NAME"
echo "  DSQL_DISTRIBUTED_CONN_LIMIT=10000"
echo ""
echo "IAM permissions required for Temporal services:"
echo "  dynamodb:GetItem, dynamodb:PutItem, dynamodb:UpdateItem, dynamodb:DeleteItem"
echo "  dynamodb:TransactWriteItems"
echo "  on arn:aws:dynamodb:$REGION:*:table/$TABLE_NAME"
```

### Files to Create
- `scripts/setup-conn-lease-table.sh`

### Acceptance Criteria
- [x] Script creates DynamoDB table with correct schema
- [x] Script is idempotent (safe to run multiple times)
- [x] TTL enabled for automatic lease cleanup
- [x] Script outputs required environment variables
- [x] Script outputs required IAM permissions

### Status: Completed

---

## Task 12: ECS Task Definition Updates

### Description
Add reservoir environment variables to ECS task definitions.

### Environment Variables
```hcl
{ name = "DSQL_RESERVOIR_ENABLED", value = "true" },
{ name = "DSQL_RESERVOIR_TARGET_READY", value = "50" },
{ name = "DSQL_RESERVOIR_LOW_WATERMARK", value = "50" },
{ name = "DSQL_RESERVOIR_BASE_LIFETIME", value = "11m" },
{ name = "DSQL_RESERVOIR_LIFETIME_JITTER", value = "2m" },
{ name = "DSQL_RESERVOIR_GUARD_WINDOW", value = "45s" },
{ name = "DSQL_DISTRIBUTED_CONN_LEASE_ENABLED", value = "true" },
{ name = "DSQL_DISTRIBUTED_CONN_LEASE_TABLE", value = "${var.project_name}-dsql-conn-lease" },
{ name = "DSQL_DISTRIBUTED_CONN_LIMIT", value = "10000" },
```

### Files to Modify
- `terraform/temporal-history.tf`
- `terraform/temporal-matching.tf`
- `terraform/temporal-frontend.tf`
- `terraform/temporal-worker.tf`

### Acceptance Criteria
- [ ] Environment variables added to all services
- [ ] IAM policy allows DynamoDB access
- [ ] Services start successfully with reservoir enabled

### Status: Not Started

---

## Task 13: Update Poolsim for Reservoir Simulation

### Description
Update `tools/poolsim` to simulate reservoir behavior, allowing validation of reservoir design decisions before implementation.

### Simulation Components to Add

1. **Reservoir struct** - Channel-based buffer with capacity
2. **Refiller** - Background fill with rate limiting
3. **Checkout/Return** - Non-blocking operations with guard window
4. **Metrics** - Track hits, misses, discards, refills

### Scenarios to Add

```yaml
# scenarios/reservoir-basic.yaml
name: "Reservoir Basic"
description: "Basic reservoir behavior with steady workload"
pools:
  - name: history
    target_size: 50
    reservoir:
      enabled: true
      target_ready: 50
      low_watermark: 25
      base_lifetime: 11m
      jitter: 2m
      guard_window: 45s
workload:
  type: constant
  checkout_rate: 10  # checkouts/sec
  hold_duration: 100ms
global_rate_limit: 100
duration: 30m
assertions:
  - type: reservoir_hits_ratio
    min: 0.95  # 95% of checkouts should hit reservoir
  - type: reservoir_empty_events
    max: 10
```

```yaml
# scenarios/reservoir-burst.yaml
name: "Reservoir Burst Recovery"
description: "Reservoir recovery after burst demand"
pools:
  - name: history
    target_size: 50
    reservoir:
      enabled: true
      target_ready: 50
workload:
  type: burst
  baseline_rate: 5
  burst_rate: 100
  burst_duration: 10s
  burst_interval: 5m
```

### Files to Modify
- `tools/poolsim/internal/pool/reservoir.go` - New reservoir simulation
- `tools/poolsim/internal/pool/pool.go` - Integrate reservoir option
- `tools/poolsim/internal/config/config.go` - Reservoir config parsing
- `tools/poolsim/scenarios/reservoir-*.yaml` - New scenarios

### Acceptance Criteria
- [ ] Reservoir simulation matches implementation behavior
- [ ] Scenarios validate design assumptions
- [ ] Metrics track reservoir-specific events
- [ ] Can compare reservoir vs non-reservoir behavior

### Status: Not Started

---

## Task 14: Update temporal-dsql-deploy Environment Files

### Description
Add reservoir configuration environment variables to `.env` and `.env.example` in the `temporal-dsql-deploy` repository for local Docker Compose deployments.

### Environment Variables to Add
```bash
# DSQL Connection Reservoir Configuration
# Reservoir mode pre-creates connections to avoid rate limit pressure under load
DSQL_RESERVOIR_ENABLED=false
DSQL_RESERVOIR_TARGET_READY=50
DSQL_RESERVOIR_LOW_WATERMARK=50
DSQL_RESERVOIR_BASE_LIFETIME=11m
DSQL_RESERVOIR_LIFETIME_JITTER=2m
DSQL_RESERVOIR_GUARD_WINDOW=45s
DSQL_RESERVOIR_INITIAL_FILL_TIMEOUT=30s

# Distributed Connection Lease Configuration (optional)
# Coordinates global connection count across all service instances
DSQL_DISTRIBUTED_CONN_LEASE_ENABLED=false
DSQL_DISTRIBUTED_CONN_LEASE_TABLE=temporal-dsql-conn-lease
DSQL_DISTRIBUTED_CONN_LIMIT=10000
```

### Files to Modify
- `temporal-dsql-deploy/.env.example` - Add reservoir configuration section with documentation
- `temporal-dsql-deploy/.env` - Add reservoir configuration (if file exists)

### Acceptance Criteria
- [x] `.env.example` updated with all reservoir environment variables
- [x] Variables include descriptive comments explaining their purpose
- [x] Default values match the reservoir_config.go defaults
- [x] Distributed connection lease variables included (disabled by default)

### Status: Completed

---

## Summary

| Task | Priority | Status |
|------|----------|--------|
| 1. Fix Compilation Issues | P0 | Completed |
| 2. Add Initial Fill Synchronization | P0 | Completed |
| 3. Add Brief Blocking Wait on Empty | P1 | Completed |
| 4. Add Prometheus Metrics | P1 | Not Started |
| 5. Improve Refiller Pacing | P2 | Completed |
| 6. Track Connection Age Properly | P2 | Completed |
| 7. Add Unit Tests | P1 | Not Started |
| 8. Add Integration Tests | P2 | Not Started |
| 9. Update Documentation | P2 | Not Started |
| 10. Add Grafana Dashboard | P2 | Not Started |
| 11. Setup Script for DynamoDB Table | P1 | Completed |
| 12. ECS Task Definition Updates | P1 | Not Started |
| 13. Update Poolsim for Reservoir | P2 | Not Started |
| 14. Update temporal-dsql-deploy Env Files | P1 | Completed |
