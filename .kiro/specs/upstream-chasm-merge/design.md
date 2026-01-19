# Design Document: Upstream CHASM Merge

## Overview

This design document describes the technical approach for merging upstream CHASM (Component-based Hierarchical Architecture for State Management) changes from `temporalio/temporal` into the `temporal-dsql` fork. The merge introduces a new table for non-workflow executions, updates the persistence plugin interfaces, and establishes a proper schema versioning structure for DSQL.

### Key Changes

1. **New `current_chasm_executions` table** - Stores current executions for non-workflow archetypes (standalone activities, schedulers)
2. **ArchetypeID-based query routing** - Routes queries to the appropriate table based on execution type
3. **Plugin interface updates** - Adds logger parameter and ArchetypeID fields to structs
4. **Schema versioning cleanup** - Establishes proper DSQL-specific versioning structure

### Upstream Reference

These changes are derived from upstream PostgreSQL schema changes, specifically:
- PostgreSQL v1.17: `chasm_node_maps` table (already in DSQL schema)
- PostgreSQL v1.19 (pending): `current_chasm_executions` table
- Related upstream PR: [#8915 CHASM SQL separate ID spaces](https://github.com/temporalio/temporal/pull/8915)

## Architecture

### Table Routing Strategy

CHASM introduces the concept of archetypes - different types of execution abstractions. The persistence layer routes queries to different tables based on the `ArchetypeID`:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Current Execution Operations                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────┐                                        │
│  │  ArchetypeID Check  │                                        │
│  └──────────┬──────────┘                                        │
│             │                                                   │
│     ┌───────┴───────┐                                           │
│     │               │                                           │
│     ▼               ▼                                           │
│  ┌──────────────┐  ┌────────────────────────┐                   │
│  │ Workflow     │  │ Non-Workflow           │                   │
│  │ ArchetypeID  │  │ ArchetypeID            │                   │
│  └──────┬───────┘  └───────────┬────────────┘                   │
│         │                      │                                │
│         ▼                      ▼                                │
│  ┌──────────────────┐  ┌──────────────────────────┐             │
│  │ current_executions│  │ current_chasm_executions │             │
│  │ (existing table)  │  │ (new table)              │             │
│  └──────────────────┘  └──────────────────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Schema Directory Structure (After Cleanup)

```
schema/
├── dsql/
│   ├── temporal/
│   │   ├── schema.sql              # Full schema (v1.1)
│   │   └── versioned/
│   │       ├── v1.0/
│   │       │   ├── manifest.json
│   │       │   └── schema.sql      # Initial schema
│   │       └── v1.1/
│   │           ├── manifest.json
│   │           └── current_chasm_executions.sql
│   └── version.go                  # Version = "1.1"
├── embed.go                        # Updated to embed dsql/temporal/versioned/
```

### temporal-dsql-tool Changes

The `temporal-dsql-tool` already supports `update-schema` via the common schema framework. The following changes are needed:

1. **Schema Embedding**: Update `schema/embed.go` to embed the new `dsql/temporal/versioned/` directory
2. **Path Registration**: Ensure `dbschemas.PathsByDB("dsql")` returns the correct paths including versioned migrations
3. **No Code Changes**: The tool's `update-schema` command uses the common `schema.Update()` function which handles versioned migrations automatically

## Components and Interfaces

### 1. Schema Changes

#### New Table: `current_chasm_executions`

```sql
-- DSQL-compatible schema for CHASM executions
-- Derived from PostgreSQL v1.19 schema
CREATE TABLE current_chasm_executions(
  shard_id INTEGER NOT NULL,
  namespace_id UUID NOT NULL,           -- DSQL: UUID instead of BYTEA
  business_id VARCHAR(255) NOT NULL,    -- Maps to WorkflowID for workflows
  archetype_id BIGINT NOT NULL,
  --
  run_id UUID NOT NULL,                 -- DSQL: UUID instead of BYTEA
  create_request_id VARCHAR(255) NOT NULL,
  state INTEGER NOT NULL,
  status INTEGER NOT NULL,
  start_version BIGINT NOT NULL DEFAULT 0,
  start_time TIMESTAMP NULL,
  last_write_version BIGINT NOT NULL,
  data BYTEA NULL,
  data_encoding VARCHAR(16) NOT NULL DEFAULT '',
  PRIMARY KEY (shard_id, namespace_id, business_id, archetype_id)
);
```

**DSQL-Specific Adaptations:**
- `namespace_id` and `run_id` use `UUID` type instead of `BYTEA` (consistent with existing DSQL schema)
- No `CHECK` constraints (DSQL doesn't support them)
- No `INDEX ASYNC` needed for this table (primary key is sufficient)

### 2. Interface Updates

#### CurrentExecutionsRow (Updated)

```go
// CurrentExecutionsRow represents a row in current_executions or current_chasm_executions
type CurrentExecutionsRow struct {
    ShardID          int32
    NamespaceID      primitives.UUID
    WorkflowID       string              // Maps to business_id in CHASM table
    RunID            primitives.UUID
    ArchetypeID      chasm.ArchetypeID   // NEW: Determines table routing
    CreateRequestID  string
    StartTime        *time.Time
    LastWriteVersion int64
    State            enumsspb.WorkflowExecutionState
    Status           enumspb.WorkflowExecutionStatus
    Data             []byte
    DataEncoding     string
}
```

#### CurrentExecutionsFilter (Updated)

```go
// CurrentExecutionsFilter for querying current executions
type CurrentExecutionsFilter struct {
    ShardID     int32
    NamespaceID primitives.UUID
    WorkflowID  string              // Maps to business_id in CHASM table
    RunID       primitives.UUID
    ArchetypeID chasm.ArchetypeID   // NEW: Determines table routing
}
```

### 3. Plugin Implementation

#### Query Routing Logic

The DSQL plugin will implement table routing based on `ArchetypeID`:

```go
// isWorkflowArchetype determines if the archetype is a workflow
func isWorkflowArchetype(archetypeID chasm.ArchetypeID) bool {
    return archetypeID == chasm.WorkflowArchetypeID || 
           archetypeID == chasm.UnspecifiedArchetypeID
}

// getTableName returns the appropriate table based on archetype
func getTableName(archetypeID chasm.ArchetypeID) string {
    if isWorkflowArchetype(archetypeID) {
        return "current_executions"
    }
    return "current_chasm_executions"
}
```

#### Updated db.go

```go
// newDB returns an instance of DB with logger support
func newDB(
    dbKind sqlplugin.DbKind,
    dbName string,
    dbDriver driver.Driver,
    handle *sqlplugin.DatabaseHandle,
    tx *sqlx.Tx,
    logger log.Logger,  // NEW: Logger parameter
) *db {
    // ... existing implementation with logger
}
```

### 4. Migration Strategy

#### For New Deployments

1. Run `temporal-dsql-tool setup-schema` with the full v1.1 schema
2. Schema includes both `current_executions` and `current_chasm_executions` tables

#### For Existing Deployments

1. Run `temporal-dsql-tool update-schema` to apply v1.1 migration
2. Migration creates only the new `current_chasm_executions` table
3. Existing `current_executions` data remains unchanged

#### Migration File: `v1.1/current_chasm_executions.sql`

```sql
-- Migration v1.1: Add current_chasm_executions table for CHASM support
-- Derived from PostgreSQL v1.19 schema

CREATE TABLE IF NOT EXISTS current_chasm_executions(
  shard_id INTEGER NOT NULL,
  namespace_id UUID NOT NULL,
  business_id VARCHAR(255) NOT NULL,
  archetype_id BIGINT NOT NULL,
  run_id UUID NOT NULL,
  create_request_id VARCHAR(255) NOT NULL,
  state INTEGER NOT NULL,
  status INTEGER NOT NULL,
  start_version BIGINT NOT NULL DEFAULT 0,
  start_time TIMESTAMP NULL,
  last_write_version BIGINT NOT NULL,
  data BYTEA NULL,
  data_encoding VARCHAR(16) NOT NULL DEFAULT '',
  PRIMARY KEY (shard_id, namespace_id, business_id, archetype_id)
);
```

#### Migration Manifest: `v1.1/manifest.json`

```json
{
  "CurrVersion": "1.1",
  "MinCompatibleVersion": "1.0",
  "Description": "Add current_chasm_executions table for CHASM support",
  "SchemaUpdateCqlFiles": ["current_chasm_executions.sql"]
}
```

## Data Models

### ArchetypeID Values

```go
const (
    UnspecifiedArchetypeID ArchetypeID = 0  // Legacy/uninitialized, treated as Workflow
    WorkflowArchetypeID    ArchetypeID = <computed>  // Traditional workflows
    // Other archetypes (Activity, Scheduler) have their own computed IDs
)
```

### Table Column Mapping

| CurrentExecutionsRow Field | current_executions Column | current_chasm_executions Column |
|---------------------------|---------------------------|--------------------------------|
| ShardID                   | shard_id                  | shard_id                       |
| NamespaceID               | namespace_id              | namespace_id                   |
| WorkflowID                | workflow_id               | business_id                    |
| RunID                     | run_id                    | run_id                         |
| ArchetypeID               | (implicit: Workflow)      | archetype_id                   |
| CreateRequestID           | create_request_id         | create_request_id              |
| State                     | state                     | state                          |
| Status                    | status                    | status                         |
| StartTime                 | start_time                | start_time                     |
| LastWriteVersion          | last_write_version        | last_write_version             |
| Data                      | data                      | data                           |
| DataEncoding              | data_encoding             | data_encoding                  |



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Query Routing Correctness

*For any* current execution operation with an ArchetypeID, the query SHALL be routed to `current_executions` if the ArchetypeID is WorkflowArchetypeID or UnspecifiedArchetypeID, and to `current_chasm_executions` otherwise.

**Validates: Requirements 2.1, 2.2, 5.2**

### Property 2: WorkflowID to BusinessID Mapping

*For any* insert operation into `current_chasm_executions`, the WorkflowID field from CurrentExecutionsRow SHALL be stored in the `business_id` column, and reading back SHALL return the same value in the WorkflowID field.

**Validates: Requirements 2.5**

### Property 3: UUID Round-Trip Consistency

*For any* valid UUID value stored in namespace_id or run_id columns, converting to string format for storage and back to UUID on retrieval SHALL produce an equivalent UUID value.

**Validates: Requirements 3.4**

### Property 4: Migration Idempotency

*For any* DSQL database, running the v1.1 migration multiple times SHALL produce the same schema state as running it once, with no errors on subsequent runs.

**Validates: Requirements 4.4**

### Property 5: Migration Data Preservation

*For any* existing data in the `current_executions` table, running the v1.1 migration SHALL NOT modify, delete, or corrupt that data.

**Validates: Requirements 4.5**

### Property 6: Default ArchetypeID Behavior

*For any* CurrentExecutionsFilter where ArchetypeID is not explicitly set (zero value), the plugin SHALL treat it as WorkflowArchetypeID and route to `current_executions`. *For any* row read from `current_executions`, the returned ArchetypeID SHALL be WorkflowArchetypeID.

**Validates: Requirements 5.1, 5.3**

## Error Handling

### Schema Migration Errors

| Error Condition | Handling Strategy |
|----------------|-------------------|
| Table already exists | Use `CREATE TABLE IF NOT EXISTS` for idempotency |
| Connection failure during migration | Rollback transaction, return error with context |
| Invalid schema version | Validate version format before applying migration |
| Insufficient permissions | Return clear error message with required permissions |

### Query Routing Errors

| Error Condition | Handling Strategy |
|----------------|-------------------|
| Unknown ArchetypeID | Treat as non-workflow, route to `current_chasm_executions` |
| Table not found | Return error indicating schema migration required |
| UUID conversion failure | Return error with original value for debugging |

### DSQL-Specific Errors

| Error Condition | Handling Strategy |
|----------------|-------------------|
| Serialization conflict (SQLSTATE 40001) | Retry with exponential backoff (existing retry logic) |
| Connection rate limit exceeded | Apply rate limiting (existing rate limiter) |

## Testing Strategy

### Dual Testing Approach

This implementation requires both unit tests and property-based tests:

- **Unit tests**: Verify specific examples, edge cases, and error conditions
- **Property tests**: Verify universal properties across all inputs

### Unit Tests

1. **Schema Tests**
   - Verify `current_chasm_executions` table creation
   - Verify column types (UUID for namespace_id, run_id)
   - Verify primary key constraint enforcement

2. **Query Routing Tests**
   - Test routing with WorkflowArchetypeID → `current_executions`
   - Test routing with UnspecifiedArchetypeID → `current_executions`
   - Test routing with non-workflow ArchetypeID → `current_chasm_executions`

3. **CRUD Operation Tests**
   - Insert into `current_chasm_executions`
   - Select from `current_chasm_executions`
   - Update in `current_chasm_executions`
   - Delete from `current_chasm_executions`

4. **Migration Tests**
   - Test fresh schema setup (v1.1)
   - Test upgrade from v1.0 to v1.1
   - Test idempotency (run migration twice)
   - Test data preservation during migration

### Property-Based Tests

Property-based tests will use the `gopter` library (already used in Temporal codebase) with minimum 100 iterations per property.

1. **Property 1: Query Routing Correctness**
   - Generate random ArchetypeIDs
   - Verify routing to correct table
   - Tag: `Feature: upstream-chasm-merge, Property 1: Query Routing Correctness`

2. **Property 3: UUID Round-Trip Consistency**
   - Generate random UUIDs
   - Store and retrieve
   - Verify equality
   - Tag: `Feature: upstream-chasm-merge, Property 3: UUID Round-Trip Consistency`

3. **Property 6: Default ArchetypeID Behavior**
   - Generate random filters with zero ArchetypeID
   - Verify WorkflowArchetypeID behavior
   - Tag: `Feature: upstream-chasm-merge, Property 6: Default ArchetypeID Behavior`

### Integration Tests

1. **End-to-End CHASM Flow**
   - Create non-workflow execution
   - Verify stored in `current_chasm_executions`
   - Query and verify data integrity

2. **Mixed Archetype Operations**
   - Create workflow and non-workflow executions
   - Verify correct table routing for each
   - Verify no cross-contamination

### Test File Locations

```
common/persistence/sql/sqlplugin/dsql/
├── execution_test.go           # Existing tests (update for CHASM)
├── execution_chasm_test.go     # New CHASM-specific tests
└── execution_property_test.go  # Property-based tests
```

## Rollback Procedure

If issues are discovered after migration:

1. **Schema Rollback**
   ```sql
   -- Drop the new table (data loss for CHASM executions)
   DROP TABLE IF EXISTS current_chasm_executions;
   
   -- Revert schema version
   UPDATE schema_version 
   SET curr_version = '1.0' 
   WHERE version_partition = 0 AND db_name = 'postgres';
   ```

2. **Code Rollback**
   - Revert to previous DSQL plugin version
   - Redeploy Temporal services

3. **Verification**
   - Confirm `current_executions` operations work
   - Confirm schema version is 1.0

**Note**: Rollback will lose any data stored in `current_chasm_executions`. This is acceptable since CHASM features would not be in use if rollback is needed.
