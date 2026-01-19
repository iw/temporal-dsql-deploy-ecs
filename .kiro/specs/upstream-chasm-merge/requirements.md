# Requirements Document

## Introduction

This document specifies the requirements for merging upstream CHASM (Component-based Hierarchical Architecture for State Management) changes from `temporalio/temporal` into the `temporal-dsql` fork. CHASM introduces a new architecture for managing different types of executions beyond traditional workflows, including standalone activities and new scheduler implementations. The merge requires schema updates, plugin modifications, and migration tooling to maintain DSQL compatibility.

## Glossary

- **CHASM**: Component-based Hierarchical Architecture for State Management - Temporal's new internal architecture for managing different execution types
- **Archetype**: A type of execution abstraction (e.g., Workflow, Activity, Scheduler)
- **ArchetypeID**: Internal numeric identifier for an Archetype type (e.g., WorkflowArchetypeID for traditional workflows)
- **BusinessID**: User-meaningful identifier, unique among non-terminal executions in a namespace (maps to WorkflowID for workflows)
- **DSQL_Plugin**: The Aurora DSQL persistence plugin implementation in `common/persistence/sql/sqlplugin/dsql/`
- **Schema_Migration**: The process of updating database schema from one version to another
- **temporal-dsql-tool**: Command-line tool for managing DSQL schema setup and migrations
- **current_executions**: Existing table storing current workflow executions
- **current_chasm_executions**: New table storing current executions for non-workflow archetypes

## Requirements

### Requirement 1: DSQL Schema Update

**User Story:** As a Temporal operator, I want the DSQL schema to include the new `current_chasm_executions` table, so that my deployment can support CHASM features like standalone activities and new schedulers.

#### Acceptance Criteria

1. THE DSQL_Schema SHALL include a `current_chasm_executions` table with columns: shard_id, namespace_id, business_id, archetype_id, run_id, create_request_id, state, status, start_version, start_time, last_write_version, data, and data_encoding
2. THE DSQL_Schema SHALL use UUID type for namespace_id and run_id columns in the `current_chasm_executions` table
3. THE DSQL_Schema SHALL define the primary key as (shard_id, namespace_id, business_id, archetype_id) for the `current_chasm_executions` table
4. THE DSQL_Schema SHALL NOT include CHECK constraints in the `current_chasm_executions` table definition
5. WHEN the schema version is queried, THE DSQL_Plugin SHALL report version 1.1 (DSQL-specific versioning, incrementing from current v1.0)
6. THE schema.sql file SHALL include comments referencing the upstream PostgreSQL schema version it derives from for traceability

### Requirement 2: CHASM Query Routing

**User Story:** As a developer, I want the DSQL plugin to correctly route queries based on ArchetypeID, so that CHASM executions are stored in the appropriate table.

#### Acceptance Criteria

1. WHEN a current execution operation is performed with WorkflowArchetypeID, THE DSQL_Plugin SHALL route the query to the `current_executions` table
2. WHEN a current execution operation is performed with a non-workflow ArchetypeID, THE DSQL_Plugin SHALL route the query to the `current_chasm_executions` table
3. THE CurrentExecutionsRow struct SHALL include an ArchetypeID field of type chasm.ArchetypeID
4. THE CurrentExecutionsFilter struct SHALL include an ArchetypeID field of type chasm.ArchetypeID
5. WHEN inserting into current_chasm_executions, THE DSQL_Plugin SHALL map WorkflowID to business_id column

### Requirement 3: Plugin Interface Updates

**User Story:** As a developer, I want the DSQL plugin to implement the updated persistence interfaces, so that it remains compatible with the upstream Temporal codebase.

#### Acceptance Criteria

1. THE newDB function in db.go SHALL accept a logger parameter
2. THE plugin.go file SHALL pass the logger parameter to newDB when creating database connections
3. THE DSQL_Plugin SHALL implement all methods required by the updated HistoryExecution interface
4. WHEN UUID fields are stored, THE DSQL_Plugin SHALL convert them to string format for DSQL compatibility

### Requirement 4: Schema Migration Support

**User Story:** As a Temporal operator, I want to migrate existing DSQL deployments to the new schema version, so that I can use CHASM features without data loss.

#### Acceptance Criteria

1. THE temporal-dsql-tool SHALL support `update-schema` command for DSQL databases
2. WHEN update-schema is executed, THE temporal-dsql-tool SHALL create the `current_chasm_executions` table if it does not exist
3. WHEN update-schema is executed, THE temporal-dsql-tool SHALL update the schema_version table to version 1.1
4. THE migration SHALL be idempotent - running it multiple times SHALL produce the same result
5. THE migration SHALL NOT modify existing data in the `current_executions` table

### Requirement 5: Interface Compatibility

**User Story:** As a developer, I want the DSQL plugin to implement the updated upstream interfaces correctly, so that it integrates seamlessly with the Temporal codebase after the merge.

#### Acceptance Criteria

1. WHEN ArchetypeID is not specified in a filter, THE DSQL_Plugin SHALL default to WorkflowArchetypeID to match upstream behavior
2. THE DSQL_Plugin SHALL implement the same query routing logic as the PostgreSQL plugin for ArchetypeID-based table selection
3. WHEN reading from current_executions, THE DSQL_Plugin SHALL return rows with ArchetypeID set to WorkflowArchetypeID to match the implicit archetype of existing workflow data
4. THE DSQL_Plugin SHALL pass all upstream integration tests that exercise current execution operations

### Requirement 6: Migration Documentation

**User Story:** As a Temporal operator, I want clear documentation for the migration process, so that I can safely upgrade my DSQL deployment.

#### Acceptance Criteria

1. THE migration documentation SHALL include step-by-step upgrade instructions
2. THE migration documentation SHALL include rollback procedures
3. THE migration documentation SHALL specify the minimum temporal-dsql-tool version required
4. THE migration documentation SHALL document any downtime requirements
5. THE migration documentation SHALL include verification steps to confirm successful migration

### Requirement 8: Version Structure Cleanup

**User Story:** As a developer, I want the DSQL schema versioning to be consistent and correct, so that migrations work reliably and documentation is accurate.

#### Acceptance Criteria

1. THE version.go file SHALL define Version as "1.1" after the CHASM merge
2. THE documentation SHALL use the correct version number when referencing setup-schema commands
3. THE temporal-dsql-tool SHALL use the version from version.go for schema setup
4. THE versioned migration directory structure SHALL follow the pattern `schema/dsql/temporal/versioned/v1.1/` (removing the unnecessary v12 subdirectory)
5. THE migration manifest.json SHALL specify the correct version and minimum compatible version


### Requirement 9: Test Coverage

**User Story:** As a developer, I want comprehensive test coverage for CHASM functionality, so that I can be confident the implementation is correct.

#### Acceptance Criteria

1. THE DSQL_Plugin SHALL have unit tests for inserting into current_chasm_executions
2. THE DSQL_Plugin SHALL have unit tests for selecting from current_chasm_executions
3. THE DSQL_Plugin SHALL have unit tests for deleting from current_chasm_executions
4. THE DSQL_Plugin SHALL have unit tests for query routing based on ArchetypeID
5. THE existing unit tests SHALL continue to pass after the changes
