# Requirements Document

## Introduction

This spec captures the design and implementation of a Connection Reservoir for the DSQL plugin. The reservoir addresses the fundamental mismatch between DSQL's cluster-wide connection rate limit (100 connections/second) and the bursty nature of connection pool refill when connections expire due to `MaxConnLifetime`.

## Problem Statement

DSQL has a **cluster-wide connection rate limit of 100 connections/second**. When connections expire due to `MaxConnLifetime`, the pool needs to replace them. If many connections expire at once (burst expiry), the pool shrinks because the refill rate can't keep up with the rate limit.

**Current behavior:**
- Pool warmup creates N connections
- Without sufficient stagger, connections have similar ages
- After `MaxConnLifetime`, many expire within a short window
- Pool Keeper tries to refill at 1-10 connections/tick
- Global rate limit (100/sec) constrains all services
- Pool shrinks during burst expiry, causing latency spikes

## Glossary

- **DSQL**: Amazon Aurora DSQL, a serverless PostgreSQL-compatible database
- **Reservoir**: A buffer of pre-created connections that sits between rate-limited connection creation and the pool's bursty demand
- **Pool Keeper**: Background goroutine that maintains pool size by replacing expired connections
- **Rate Limiter**: Component that enforces DSQL's connection rate limit (local or distributed)
- **Connection Lease**: DynamoDB-backed global connection count tracking
- **Guard Window**: Time before expiry when connections are considered too old to hand out
- **Refiller**: Background goroutine that continuously fills the reservoir

## Core Design Principles

The reservoir is built around four fundamental requirements:

| Principle | Description | Why It Matters |
|-----------|-------------|----------------|
| **Fast Checkout** | Sub-millisecond checkout from reservoir | The hot path - request latency depends on this |
| **Proactive Expiry** | Don't let stale connections sit in reservoir | Prevents handing out connections that will expire mid-transaction |
| **Continuous Refill** | Always keep reservoir full | Connection availability is paramount |
| **Eviction Callback** | Release lease on discard | Global connection count must stay accurate |

These principles drive all design decisions. The reservoir exists to ensure connections are **always available** without blocking on rate limiters.

## Requirements

### Requirement 1: Fast Checkout (Sub-Millisecond)

**User Story:** As a Temporal service, I want `driver.Open()` to return immediately without blocking on rate limiters, so that request latency is not impacted by connection creation delays.

**Background:** Go's `database/sql` calls `driver.Open()` when it needs a new connection. If this blocks on rate limiters, request latency suffers. The reservoir decouples connection acquisition from rate-limited creation. **This is the hot path - checkout must be sub-millisecond.**

#### Acceptance Criteria

1. THE Reservoir_Driver.Open() SHALL return immediately (non-blocking)
2. THE Reservoir_Driver.Open() SHALL complete in under 1ms (channel receive only)
3. WHEN the reservoir has available connections, THE Reservoir_Driver.Open() SHALL return a connection from the reservoir
4. WHEN the reservoir is empty, THE Reservoir_Driver.Open() SHALL return `driver.ErrBadConn` to trigger retry
5. THE Reservoir_Driver.Open() SHALL NOT wait on rate limiters or network I/O
6. THE Implementation SHALL be gated by `DSQL_RESERVOIR_ENABLED=true` environment variable

### Requirement 2: Continuous Refill (Always Keep Reservoir Full)

**User Story:** As an operator, I want the reservoir to be continuously refilled in the background, so that connections are always available when the pool needs them.

**Background:** A background refiller goroutine is the only component that waits on rate limiters and creates physical connections. This isolates blocking operations from the request path. **The refiller must be aggressive - the rate limiter is the ONLY throttle.**

#### Acceptance Criteria

1. THE Refiller SHALL run as a background goroutine
2. THE Refiller SHALL respect the global connection rate limit when creating connections
3. THE Refiller SHALL maintain the reservoir at the configured target size
4. THE Refiller SHALL run back-to-back connection creation with NO artificial delays
5. THE Rate_Limiter SHALL be the ONLY throttle on connection creation
6. THE Refiller SHALL apply jitter to connection lifetimes to prevent synchronized expiry
7. THE Refiller SHALL stop gracefully when the service shuts down

### Requirement 3: Proactive Expiry (Don't Let Stale Connections Sit)

**User Story:** As an operator, I want expired connections to be proactively evicted from the reservoir, so that stale connections don't sit waiting for checkout.

**Background:** Connections have a finite lifetime (e.g., 11 minutes). Without proactive scanning, expired connections would only be discovered at checkout time, wasting reservoir capacity and potentially causing checkout failures. **The reservoir must actively scan and evict expired connections.**

#### Acceptance Criteria

1. THE Reservoir SHALL run a background expiry scanner goroutine
2. THE Expiry_Scanner SHALL periodically scan all connections in the reservoir (every 1 second)
3. THE Expiry_Scanner SHALL evict connections that are expired or within the guard window
4. THE Expiry_Scanner SHALL be eager on eviction, especially for clustered connections with similar expiry times
5. WHEN a connection is evicted, THE Reservoir SHALL invoke the eviction callback (lease release)
6. THE Reservoir SHALL track connection creation time and lifetime for accurate expiry calculation

### Requirement 4: Eviction Callback (Release Lease on Discard)

**User Story:** As an operator, I want the global connection lease to be released when a connection is discarded, so that the cluster-wide connection count stays accurate.

**Background:** When using distributed connection leasing (DynamoDB-backed), each connection holds a lease. If connections are discarded without releasing the lease, the global count drifts and eventually blocks new connections. **Every discard must release its lease.**

#### Acceptance Criteria

1. WHEN a connection is discarded (for any reason), THE Reservoir SHALL release its global lease
2. THE Lease_Release SHALL be invoked via the `LeaseReleaser` interface
3. THE Lease_Release SHALL be non-blocking (fire-and-forget with background retry)
4. THE Reservoir SHALL handle nil LeaseReleaser gracefully (no-op when leasing disabled)
5. THE Discard operation SHALL close the underlying physical connection

### Requirement 5: Connection Lifecycle Management

**User Story:** As an operator, I want connections to be recycled back to the reservoir when released by the pool, so that connection creation is minimized.

**Background:** When `database/sql` calls `Close()` on a connection, the reservoir wrapper returns the physical connection to the reservoir instead of closing it. This enables connection reuse.

#### Acceptance Criteria

1. WHEN a connection is closed by the pool, THE Reservoir_Conn SHALL return the physical connection to the reservoir
2. WHEN a connection is marked as bad (error encountered), THE Reservoir_Conn SHALL discard it instead of returning to reservoir
3. WHEN a connection is too close to expiry (within guard window), THE Reservoir SHALL discard it
4. WHEN the reservoir is full, THE Reservoir SHALL discard returned connections
5. THE Reservoir SHALL track connection creation time for lifetime management

### Requirement 6: Global Connection Count Limiting

**User Story:** As an operator, I want to enforce a cluster-wide connection count limit, so that services don't exceed DSQL's 10,000 connection limit.

**Background:** DSQL has a maximum of 10,000 connections per cluster. With multiple services and instances, we need global coordination to prevent exceeding this limit.

#### Acceptance Criteria

1. THE Connection_Lease_Manager SHALL use DynamoDB for global coordination
2. THE Connection_Lease_Manager SHALL atomically acquire a lease before creating a connection
3. THE Connection_Lease_Manager SHALL release the lease when a connection is discarded
4. THE Connection_Lease_Manager SHALL use TTL for automatic lease cleanup if a service crashes
5. THE Connection_Lease_Manager SHALL be optional (enabled via `DSQL_DISTRIBUTED_CONN_LEASE_ENABLED=true`)
6. THE Implementation SHALL gracefully degrade if DynamoDB is unavailable

### Requirement 7: Initial Fill Synchronization

**User Story:** As an operator, I want the reservoir to be pre-filled before the service starts accepting requests, so that the first requests don't encounter an empty reservoir.

**Background:** Without initial fill, the first requests after startup will hit an empty reservoir and return `ErrBadConn`, causing retries and latency.

#### Acceptance Criteria

1. WHEN reservoir mode is enabled, THE Plugin SHALL wait for the reservoir to reach the low watermark before returning the connection
2. THE Initial_Fill SHALL have a configurable timeout (default 30 seconds)
3. IF the initial fill times out, THE Plugin SHALL log a warning and continue (best-effort)
4. THE Initial_Fill SHALL respect the global rate limit

### Requirement 8: Observability

**User Story:** As an operator, I want metrics and logs for reservoir operations, so that I can monitor reservoir health and diagnose issues.

#### Acceptance Criteria

1. THE Reservoir SHALL expose `dsql_reservoir_size` gauge (current reservoir size)
2. THE Reservoir SHALL expose `dsql_reservoir_checkouts_total` counter (successful checkouts)
3. THE Reservoir SHALL expose `dsql_reservoir_empty_total` counter (checkout attempts when empty)
4. THE Reservoir SHALL expose `dsql_reservoir_discards_total` counter (connections discarded, labeled by reason)
5. THE Reservoir SHALL expose `dsql_reservoir_refills_total` counter (connections created by refiller)
6. THE Reservoir SHALL log significant events (empty reservoir, discard reasons, refill failures)

### Requirement 9: Configuration

**User Story:** As an operator, I want to configure reservoir behavior via environment variables, so that I can tune it for my workload without code changes.

#### Acceptance Criteria

1. THE Reservoir SHALL be configurable via the following environment variables:
   - `DSQL_RESERVOIR_ENABLED` - Enable reservoir mode (default: false)
   - `DSQL_RESERVOIR_TARGET_READY` - Target reservoir size (default: maxOpen)
   - `DSQL_RESERVOIR_LOW_WATERMARK` - Aggressive refill threshold (default: maxOpen)
   - `DSQL_RESERVOIR_BASE_LIFETIME` - Base connection lifetime (default: 11m)
   - `DSQL_RESERVOIR_LIFETIME_JITTER` - Lifetime jitter range (default: 2m)
   - `DSQL_RESERVOIR_GUARD_WINDOW` - Time before expiry to discard (default: 45s)
2. THE Connection_Lease SHALL be configurable via:
   - `DSQL_DISTRIBUTED_CONN_LEASE_ENABLED` - Enable global conn limiting (default: false)
   - `DSQL_DISTRIBUTED_CONN_LEASE_TABLE` - DynamoDB table name
   - `DSQL_DISTRIBUTED_CONN_LIMIT` - Global connection limit (default: 10000)

### Requirement 10: Backward Compatibility

**User Story:** As an operator, I want reservoir mode to be opt-in, so that existing deployments continue to work without changes.

#### Acceptance Criteria

1. WHEN `DSQL_RESERVOIR_ENABLED` is not set or false, THE Plugin SHALL use the existing token-refreshing driver
2. THE Reservoir implementation SHALL NOT change the behavior of non-reservoir mode
3. THE Reservoir implementation SHALL NOT require DynamoDB if connection leasing is disabled
4. THE Implementation SHALL be safe to merge and deploy without enabling reservoir mode

## Non-Functional Requirements

### Performance

1. THE Reservoir_Driver.Open() SHALL complete in under 1ms (channel receive only - the hot path)
2. THE Refiller SHALL create connections back-to-back with rate limiter as the only throttle
3. THE Expiry_Scanner SHALL complete a full scan in under 10ms
4. THE DynamoDB operations SHALL have a timeout of 5 seconds

### Reliability

1. THE Reservoir SHALL handle DynamoDB unavailability gracefully (fall back to local-only)
2. THE Reservoir SHALL handle connection creation failures with exponential backoff
3. THE Reservoir SHALL not leak connections on service shutdown

### Scalability

1. THE Reservoir SHALL support up to 100 connections per service instance
2. THE Connection_Lease SHALL support up to 10,000 connections cluster-wide
3. THE DynamoDB table SHALL use on-demand billing to handle variable load

## Open Questions

1. **Connection Transfer**: Can we return a pre-created `driver.Conn` from `Open()`? Need to verify Go's `database/sql` accepts this.

2. **Token Refresh**: Reservoir connections have IAM tokens. Do we need to refresh tokens for connections sitting in reservoir?

3. **Connection State**: Are there connection-level settings that need to be reset when transferring from reservoir to pool?

4. **Lease TTL Alignment**: Lease TTL (3 min) vs connection lifetime (11 min) - how to handle counter drift if services crash?

5. **Multiple Pools**: Each `CreateDB` call creates a new reservoir. Is this the intended behavior for services with multiple pools?
