# Implementation Plan: Upstream CHASM Merge

## Overview

This implementation plan covers merging upstream CHASM changes into the temporal-dsql fork. The work is organized into phases: schema restructuring, plugin updates, migration support, and testing.

## Tasks

- [x] 1. Restructure DSQL schema directory
  - [x] 1.1 Move schema files from `schema/dsql/v12/` to `schema/dsql/`
    - Moved `schema/dsql/v12/temporal/` to `schema/dsql/temporal/`
    - Moved `schema/dsql/v12/version.go` to `schema/dsql/version.go`
    - Removed `schema/dsql/v12/` directory
    - _Requirements: 8.4_

  - [x] 1.2 Create v1.0 versioned migration directory
    - Created `schema/dsql/temporal/versioned/v1.0/` directory
    - Created `manifest.json` with version "1.0" and minCompatibleVersion "1.0"
    - Copied current `schema.sql` as the v1.0 base schema
    - _Requirements: 8.4, 8.5_

  - [x] 1.3 Update schema/embed.go for new DSQL paths
    - embed.go already uses `//go:embed *` which includes all subdirectories
    - Verified `PathsByDB("dsql")` returns `[dsql/temporal]` correctly
    - _Requirements: 8.3_

- [x] 2. Add current_chasm_executions table
  - [x] 2.1 Create v1.1 migration directory and files
    - Created `schema/dsql/temporal/versioned/v1.1/` directory
    - Created `manifest.json` with version "1.1", minCompatibleVersion "1.0"
    - Created `current_chasm_executions.sql` with DSQL-compatible table definition
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 2.2 Update main schema.sql to include current_chasm_executions
    - Added `current_chasm_executions` table definition to `schema/dsql/temporal/schema.sql`
    - Added comment referencing upstream PostgreSQL version for traceability
    - _Requirements: 1.1, 1.6_

  - [x] 2.3 Update version.go to version 1.1
    - Changed `Version = "1.0"` to `Version = "1.1"` in `schema/dsql/version.go`
    - _Requirements: 1.5, 8.1_

- [x] 3. Checkpoint - Verify schema changes
  - Schema files are valid SQL
  - embed.go compiles correctly (`go build ./schema/...` passes)
  - `PathsByDB("dsql")` returns `[dsql/temporal]` correctly

- [x] 4. Update DSQL plugin interfaces
  - [x] 4.1 Add ArchetypeID to CurrentExecutionsRow and CurrentExecutionsFilter
    - Upstream merge brought these changes automatically
    - `CurrentExecutionsRow` now has `ArchetypeID chasm.ArchetypeID` field
    - `CurrentExecutionsFilter` now has `ArchetypeID chasm.ArchetypeID` field
    - _Requirements: 2.3, 2.4_

  - [x] 4.2 Update db.go to accept logger parameter
    - Added `logger log.Logger` field to db struct
    - `newDBWithDependencies` now stores logger in struct
    - _Requirements: 3.1_

  - [x] 4.3 Update plugin.go to pass logger to newDB
    - Logger is already passed via `newDBWithDependencies`
    - _Requirements: 3.2_

- [x] 5. Implement CHASM query routing in execution.go
  - [x] 5.1 Add query routing helper functions
    - Added `assertArchetypeIDSpecified(archetypeID)` function
    - Uses `softassert.UnexpectedInternalErr` for validation
    - _Requirements: 2.1, 2.2_

  - [x] 5.2 Add current_chasm_executions SQL queries
    - Added `createCurrentChasmExecutionQuery` for INSERT
    - Added `getCurrentChasmExecutionQuery` for SELECT
    - Added `updateCurrentChasmExecutionsQuery` for UPDATE
    - Added `deleteCurrentChasmExecutionQuery` for DELETE
    - Added `lockCurrentChasmExecutionQuery` for LOCK
    - _Requirements: 2.5_

  - [x] 5.3 Update InsertIntoCurrentExecutions with routing
    - Routes to current_executions for WorkflowArchetypeID
    - Routes to current_chasm_executions for other archetypes
    - Maps WorkflowID to business_id for CHASM table
    - _Requirements: 2.1, 2.2, 2.5_

  - [x] 5.4 Update SelectFromCurrentExecutions with routing
    - Routes based on ArchetypeID
    - Sets ArchetypeID on returned row
    - _Requirements: 5.1, 5.3_

  - [x] 5.5 Update UpdateCurrentExecutions with routing
    - Routes based on ArchetypeID
    - _Requirements: 2.1, 2.2_

  - [x] 5.6 Update DeleteFromCurrentExecutions with routing
    - Routes based on ArchetypeID
    - _Requirements: 2.1, 2.2_

  - [x] 5.7 Update LockCurrentExecutions with routing
    - Routes based on ArchetypeID
    - _Requirements: 2.1, 2.2_

- [x] 6. Checkpoint - Verify plugin compiles
  - `go build ./...` passes
  - `go vet ./common/persistence/sql/sqlplugin/dsql/...` passes
  - All DSQL tests pass

- [x] 7. Update documentation
  - [x] 7.1 Update docs/dsql/migration-guide.md
    - Added section for v1.0 to v1.1 migration
    - Documented the new current_chasm_executions table
    - Updated setup-schema examples with correct version and path
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 8.2_

  - [x] 7.2 Update docs/dsql/overview.md
    - Added schema version information (v1.1)
    - Added CHASM support information
    - Fixed schema path from dsql/v12/temporal to dsql/temporal
    - _Requirements: 8.2_

- [ ] 8. Write unit tests for CHASM functionality (OPTIONAL)
  - [ ]* 8.1 Write unit tests for query routing
    - Test routing with WorkflowArchetypeID
    - Test routing with UnspecifiedArchetypeID
    - Test routing with non-workflow ArchetypeID
    - _Requirements: 9.4_

  - [ ]* 8.2 Write unit tests for current_chasm_executions CRUD
    - Test InsertIntoCurrentExecutions for CHASM table
    - Test SelectFromCurrentExecutions for CHASM table
    - Test DeleteFromCurrentExecutions for CHASM table
    - _Requirements: 9.1, 9.2, 9.3_

- [x] 9. Verify existing tests pass
  - [x] 9.1 Run existing DSQL unit tests
    - `go test ./common/persistence/sql/sqlplugin/dsql/...` passes
    - Fixed session test for updated DefaultMaxIdleConns value
    - _Requirements: 9.5_

  - [x] 9.2 Run linting
    - `go vet ./common/persistence/sql/sqlplugin/dsql/...` passes
    - Full `make lint-code` times out (large codebase)
    - _Requirements: 5.4_

- [x] 10. Final checkpoint - Full verification
  - `go build ./...` passes
  - All DSQL unit tests pass
  - Documentation updated
  - Ready for integration testing with actual DSQL cluster

- [x] 11. Push branch and create PR
  - Branch `upstream-merge-chasm` pushed to origin
  - PR available at: https://github.com/iw/temporal/pull/new/upstream-merge-chasm
  - 4 commits: schema restructure, upstream merge, CHASM routing, documentation

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
- The implementation should be done on the `upstream-merge-chasm` branch in temporal-dsql
