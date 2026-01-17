# Design Document

## Overview

This document captures the technical investigation of IAM authentication token renewal in the DSQL plugin for Temporal. The investigation focuses on understanding the current implementation, identifying potential issues, and recommending improvements.

## Architecture

The DSQL plugin uses a layered architecture for database connectivity:

```
┌─────────────────────────────────────────────────────────────┐
│                    DSQL Plugin (plugin.go)                  │
│  - Generates IAM tokens via AWS SDK                         │
│  - Creates connections with token as password               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  DatabaseHandle (db_handle.go)              │
│  - Manages connection lifecycle                             │
│  - Detects errors requiring refresh                         │
│  - Triggers reconnection with new token                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Driver (postgresql/driver)               │
│  - IsConnNeedsRefreshError() detects refresh triggers       │
│  - Currently uses PostgreSQL driver, not DSQL driver        │
└─────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### Token Generation (plugin.go)

```go
// generateDbConnectAuthToken generates an IAM auth token for DSQL
func (p *plugin) generateDbConnectAuthToken(ctx context.Context, region, clusterEndpoint string, action DSQLAction, logger log.Logger) (string, error)
```

- Uses `github.com/aws/aws-sdk-go-v2/feature/dsql/auth`
- Token expiry set to 1 hour
- Called during initial connection and reconnection

### Connection Refresh (db_handle.go)

```go
// ConvertError checks if error requires connection refresh
func (h *DatabaseHandle) ConvertError(err error) error {
    if h.needsRefresh(err) || errors.Is(err, driver.ErrBadConn) || ... {
        h.reconnect(true)
        return serviceerror.NewUnavailablef("database connection lost: %s", err.Error())
    }
    return err
}
```

### Driver Error Detection

**PostgreSQL Driver** (currently used):
```go
func isConnNeedsRefreshError(code, message string) bool {
    if code == readOnlyTransactionCode || code == cannotConnectNowCode {
        return true
    }
    // Limited error detection
}
```

**DSQL Driver** (not used, but has better detection):
```go
func isConnNeedsRefreshError(code, message string) bool {
    // Connection exception codes (08xxx) for IAM auth failures
    if code == connectionExceptionCode ||
        code == connectionDoesNotExistCode ||
        code == connectionFailureCode ||
        code == sqlclientUnableToEstablishConnection {
        return true
    }
    // Message-based detection for "access denied"
    if strings.Contains(strings.ToLower(message), "access denied") {
        return true
    }
}
```

## Data Models

### Error Codes Relevant to IAM Auth

| Code | Name | Description |
|------|------|-------------|
| 08000 | connection_exception | General connection error |
| 08001 | sqlclient_unable_to_establish_sqlconnection | Cannot establish connection |
| 08003 | connection_does_not_exist | Connection no longer exists |
| 08006 | connection_failure | Connection failed (includes IAM "access denied") |

## Correctness Properties

*Investigation spec - no testable properties defined*

## Error Handling

### Current Behavior

1. Token expires after 1 hour
2. Next database operation fails with connection error
3. `ConvertError()` checks if refresh needed
4. If PostgreSQL driver doesn't recognize error code, refresh may not trigger
5. Eventually falls back to generic connection error detection

### Potential Gap

The PostgreSQL driver may not recognize DSQL-specific IAM authentication errors (08xxx codes with "access denied" message), potentially delaying reconnection.

## Testing Strategy

### Investigation Tasks

1. Review driver selection rationale
2. Test IAM token expiration behavior
3. Compare error detection between drivers
4. Evaluate proactive renewal feasibility
