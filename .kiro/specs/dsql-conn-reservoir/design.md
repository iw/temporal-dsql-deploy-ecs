# Design Document

## Introduction

This document describes the technical design for the Connection Reservoir feature in the DSQL plugin. The reservoir addresses the mismatch between DSQL's cluster-wide connection rate limit and the bursty nature of pool refill.

## Architecture Overview

```
                    Global Rate Limit (100/sec)
                           │
                           ▼
┌──────────────────────────────────────────────────┐
│              RESERVOIR (per service)             │
│                                                  │
│  Continuously filled by background refiller      │
│  Maintains buffer of "ready" connections         │
│                                                  │
│  ┌─────────────────────────────────────────┐    │
│  │  Channel buffer (capacity = targetReady) │    │
│  │  [conn1] [conn2] [conn3] ... [connN]     │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
└──────────────────────────────────────────────────┘
                           │
                           ▼ (instant - no rate limit)
┌──────────────────────────────────────────────────┐
│              POOL (Go's database/sql)            │
│                                                  │
│  Calls driver.Open() when it needs a connection  │
│  Driver returns connection from reservoir        │
│  No waiting for rate limit                       │
└──────────────────────────────────────────────────┘
```

## Component Design

### 1. Reservoir (`reservoir.go`)

The reservoir is a simple channel-based buffer of physical connections.

```go
type Reservoir struct {
    ready       chan *PhysicalConn  // Buffered channel
    guardWindow time.Duration       // Discard if expiry within this window
    leaseRel    LeaseReleaser       // For releasing global leases
    logFunc     LogFunc
}

type PhysicalConn struct {
    Conn      driver.Conn
    ExpiresAt time.Time
    LeaseID   string
}
```

**Key Operations:**

- `TryCheckout(now)` - Non-blocking checkout from channel
- `Return(pc, now)` - Non-blocking return to channel (discard if full or expired)

**Design Decisions:**

1. **Channel-based**: Using a buffered channel provides natural FIFO ordering and thread-safe access without explicit locking for the hot path.

2. **Guard Window**: Connections within `guardWindow` of expiry are discarded on checkout/return. This prevents handing out connections that will expire mid-transaction.

3. **Non-blocking Return**: If the channel is full, returned connections are discarded. This prevents blocking the caller.

### 2. Reservoir Driver (`reservoir_driver.go`)

Implements `driver.Driver` interface, sourcing connections from the reservoir.

```go
type reservoirDriver struct {
    res       *Reservoir
    openCount atomic.Int64
    logFunc   LogFunc
}

func (d *reservoirDriver) Open(_ string) (driver.Conn, error) {
    pc, ok := d.res.TryCheckout(time.Now().UTC())
    if !ok {
        return nil, driver.ErrBadConn  // Triggers retry
    }
    return newReservoirConn(d.res, pc), nil
}
```

**Design Decisions:**

1. **ErrBadConn on Empty**: When reservoir is empty, returning `driver.ErrBadConn` tells `database/sql` to retry. This is the standard mechanism for transient connection failures.

2. **DSN Ignored**: The DSN parameter is ignored because connections are pre-created by the refiller. The DSN was used during refiller's connection creation.

### 3. Reservoir Connection (`reservoir_conn.go`)

Wraps a physical connection and returns it to the reservoir on `Close()`.

```go
type reservoirConn struct {
    r      *Reservoir
    pc     *PhysicalConn
    closed atomic.Bool
    bad    atomic.Bool
}

func (c *reservoirConn) Close() error {
    if c.closed.Swap(true) {
        return nil  // Already closed
    }
    if c.bad.Load() {
        // Mark as expired to force discard
        c.pc.ExpiresAt = time.Now().Add(-1 * time.Second)
    }
    c.r.Return(c.pc, time.Now().UTC())
    return nil
}
```

**Design Decisions:**

1. **Bad Connection Tracking**: If any operation returns `driver.ErrBadConn`, the `bad` flag is set. On `Close()`, bad connections are discarded rather than returned to reservoir.

2. **Interface Forwarding**: The wrapper forwards all optional driver interfaces (`ConnBeginTx`, `ExecerContext`, `QueryerContext`, `Pinger`, `SessionResetter`, `Validator`) to the underlying connection.

### 4. Refiller (`reservoir_refiller.go`)

Background goroutine that fills the reservoir.

```go
type reservoirRefiller struct {
    res           *Reservoir
    cfg           ReservoirConfig
    tokenProvider TokenProvider
    rateLimiter   RateLimiter
    leaseManager  LeaseManager
    underlying    driver.Driver
}

func (r *reservoirRefiller) loop() {
    for {
        ready := r.res.Len()
        need := r.cfg.TargetReady - ready
        
        if need <= 0 {
            sleep(500ms)
            continue
        }
        
        // Aggressive refill if below low watermark
        batch := 1
        if ready < r.cfg.LowWatermark {
            batch = 5
        }
        
        for i := 0; i < batch; i++ {
            r.openOne(ctx)
        }
    }
}

func (r *reservoirRefiller) openOne(ctx context.Context) error {
    // 1. Acquire global connection lease (if enabled)
    leaseID, err := r.leaseManager.Acquire(ctx)
    
    // 2. Wait on rate limiter
    err = r.rateLimiter.Wait(ctx)
    
    // 3. Get fresh IAM token
    token, err := r.tokenProvider(ctx)
    
    // 4. Create physical connection
    conn, err := r.underlying.Open(dsnWithToken)
    
    // 5. Add to reservoir with jittered expiry
    expiresAt := time.Now().Add(baseLifetime + randomJitter)
    r.res.Return(&PhysicalConn{Conn: conn, ExpiresAt: expiresAt, LeaseID: leaseID}, time.Now())
}
```

**Design Decisions:**

1. **Lease Before Rate Limit**: Acquire global connection lease first, then wait on rate limiter. This ensures we don't consume rate limit budget if we can't get a lease.

2. **Jittered Expiry**: Each connection gets a random jitter added to its lifetime. This naturally distributes expiry over time, preventing synchronized expiry.

3. **Aggressive Refill**: When below low watermark, refill in batches of 5 instead of 1. This helps recover from empty reservoir faster.

### 5. Distributed Connection Lease (`distributed_conn_lease.go`)

DynamoDB-backed global connection count limiting.

```go
type DistributedConnLeases struct {
    ddb      *dynamodb.Client
    table    string
    endpoint string
    limit    int64
    ttl      time.Duration
}
```

**DynamoDB Schema:**

| Item Type | Partition Key | Attributes |
|-----------|---------------|------------|
| Counter | `dsqllease_counter#<endpoint>` | `active` (count), `updated_ms` |
| Lease | `dsqllease#<endpoint>#<leaseID>` | `ttl_epoch`, `service_name`, `created_ms` |

**Operations:**

- `Acquire(ctx)` - TransactWriteItems: increment counter (if < limit) + put lease item
- `Release(ctx, leaseID)` - TransactWriteItems: delete lease item + decrement counter

**Design Decisions:**

1. **Two-Item Approach**: Counter item for fast limit checking, lease items for TTL cleanup. This allows atomic acquire/release while enabling automatic cleanup of crashed services.

2. **TTL Cleanup**: Lease items have TTL (3 minutes). If a service crashes, its leases are automatically cleaned up. However, the counter may drift - see Open Questions.

3. **Conditional Update**: Counter increment uses `ConditionExpression: active < limit` to enforce the global limit atomically.

## Plugin Integration

The reservoir is integrated into `plugin.go`:

```go
func (p *plugin) createConnectionWithTokenRefresh(...) (*sqlx.DB, error) {
    if IsReservoirEnabled() {
        // Register reservoir driver
        driverName, res, err := driver.RegisterReservoirDriverWithLogger(...)
        
        // Open connection using reservoir driver
        sqlDB, err := sql.Open(driverName, baseDSN)
        db := sqlx.NewDb(sqlDB, "pgx")
        
        // Disable database/sql lifetime management
        db.SetConnMaxLifetime(0)
        db.SetConnMaxIdleTime(0)
        
        return db, nil
    }
    
    // Non-reservoir mode (existing behavior)
    ...
}
```

**Design Decisions:**

1. **Disable Pool Lifetime Management**: When using reservoir, we disable `ConnMaxLifetime` and `ConnMaxIdleTime` on the `database/sql` pool. The reservoir manages connection lifetime instead.

2. **Feature Flag**: Reservoir mode is gated by `DSQL_RESERVOIR_ENABLED=true`. This allows safe rollout and easy rollback.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `DSQL_RESERVOIR_ENABLED` | `false` | Enable reservoir mode |
| `DSQL_RESERVOIR_TARGET_READY` | `maxOpen` | Target reservoir size |
| `DSQL_RESERVOIR_LOW_WATERMARK` | `maxOpen` | Aggressive refill threshold |
| `DSQL_RESERVOIR_BASE_LIFETIME` | `11m` | Base connection lifetime |
| `DSQL_RESERVOIR_LIFETIME_JITTER` | `2m` | Lifetime jitter range |
| `DSQL_RESERVOIR_GUARD_WINDOW` | `45s` | Discard if expiry within this |
| `DSQL_DISTRIBUTED_CONN_LEASE_ENABLED` | `false` | Enable global conn limiting |
| `DSQL_DISTRIBUTED_CONN_LEASE_TABLE` | - | DynamoDB table name |
| `DSQL_DISTRIBUTED_CONN_LIMIT` | `10000` | Global connection limit |

## Sequence Diagrams

### Connection Checkout (Happy Path)

```
database/sql          reservoirDriver          Reservoir
     │                      │                      │
     │──Open(dsn)──────────>│                      │
     │                      │──TryCheckout(now)───>│
     │                      │<──(PhysicalConn)─────│
     │<──reservoirConn──────│                      │
     │                      │                      │
```

### Connection Checkout (Empty Reservoir)

```
database/sql          reservoirDriver          Reservoir
     │                      │                      │
     │──Open(dsn)──────────>│                      │
     │                      │──TryCheckout(now)───>│
     │                      │<──(nil, false)───────│
     │<──ErrBadConn─────────│                      │
     │                      │                      │
     │  (retry after backoff)                      │
     │──Open(dsn)──────────>│                      │
     │                      │                      │
```

### Refiller Loop

```
Refiller              RateLimiter         LeaseManager         Reservoir
   │                      │                    │                   │
   │──Wait(ctx)──────────>│                    │                   │
   │<─────────────────────│                    │                   │
   │──Acquire(ctx)────────────────────────────>│                   │
   │<──(leaseID)───────────────────────────────│                   │
   │                      │                    │                   │
   │  (create connection with IAM token)       │                   │
   │                      │                    │                   │
   │──Return(PhysicalConn)─────────────────────────────────────────>│
   │                      │                    │                   │
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Reservoir empty | Return `ErrBadConn`, `database/sql` retries |
| Connection expired on checkout | Discard, return `ErrBadConn` |
| Connection error during use | Mark bad, discard on close |
| Rate limiter timeout | Refiller backs off, retries |
| Lease acquire fails (limit reached) | Refiller backs off, retries |
| DynamoDB unavailable | Fall back to local-only (no global limiting) |

## Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `dsql_reservoir_size` | Gauge | service | Current reservoir size |
| `dsql_reservoir_checkouts_total` | Counter | service | Successful checkouts |
| `dsql_reservoir_empty_total` | Counter | service | Checkout when empty |
| `dsql_reservoir_discards_total` | Counter | service, reason | Discarded connections |
| `dsql_reservoir_refills_total` | Counter | service | Connections created |
| `dsql_reservoir_refill_failures_total` | Counter | service | Failed creates |

## Testing Strategy

### Unit Tests

1. **Reservoir**: Test checkout/return, guard window, full reservoir discard
2. **ReservoirConn**: Test close behavior, bad connection handling, interface forwarding
3. **Refiller**: Test refill logic, jitter application, shutdown
4. **DistributedConnLeases**: Test acquire/release, limit enforcement, TTL

### Integration Tests

1. **End-to-end**: Start service with reservoir, verify connections work
2. **Empty reservoir recovery**: Drain reservoir, verify refiller recovers
3. **Rate limit compliance**: Verify refiller respects rate limit
4. **Global limit**: Verify lease manager enforces cluster-wide limit

### Load Tests

1. **Steady state**: Verify reservoir maintains target size under load
2. **Burst demand**: Verify behavior when demand exceeds reservoir capacity
3. **Connection expiry**: Verify smooth transition as connections expire

## Open Questions

1. **Brief Blocking Wait**: Should `Open()` wait briefly (100ms) before returning `ErrBadConn`? This could smooth out transient empty reservoir.

2. **Lease TTL vs Lifetime**: Lease TTL (3 min) < connection lifetime (11 min). If service crashes, counter may drift. Need reconciliation mechanism?

3. **Initial Fill**: Should we block startup until reservoir reaches low watermark? Current implementation starts refiller but doesn't wait.

4. **Multiple Reservoirs**: Each `CreateDB` creates a new reservoir. With 4 services × 2 pools = 8 reservoirs per instance. Is this intended?

## Implementation Status

### Completed (Sketch)

- [x] `reservoir.go` - Basic reservoir with channel buffer
- [x] `reservoir_driver.go` - Driver implementation
- [x] `reservoir_conn.go` - Connection wrapper
- [x] `reservoir_refiller.go` - Background refiller
- [x] `distributed_conn_lease.go` - DynamoDB lease manager
- [x] `reservoir_config.go` - Configuration
- [x] `conn_lease_config.go` - Lease configuration
- [x] `plugin.go` - Integration

### Pending

- [ ] Fix duplicate constant declarations
- [ ] Add initial fill synchronization
- [ ] Add Prometheus metrics
- [ ] Add unit tests
- [ ] Add integration tests
- [ ] Documentation updates
