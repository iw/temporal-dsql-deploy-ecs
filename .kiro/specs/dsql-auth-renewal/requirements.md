# Requirements Document

## Introduction

This spec captures the investigation and potential improvements for IAM authentication token renewal in the DSQL plugin for Temporal. The DSQL plugin uses AWS IAM authentication tokens that expire, requiring proper renewal mechanisms to maintain database connectivity.

## Glossary

- **DSQL**: Amazon Aurora DSQL, a serverless PostgreSQL-compatible database
- **IAM_Token**: AWS Identity and Access Management authentication token used for DSQL connections
- **DatabaseHandle**: Temporal's connection lifecycle manager that handles reconnection logic
- **Driver**: Database driver interface that detects connection errors requiring refresh

## Requirements

### Requirement 1: Driver Selection Correction

**User Story:** As a developer, I want the DSQL plugin to use the DSQL-specific driver instead of the PostgreSQL driver, so that DSQL-specific error detection (especially IAM token expiration) works correctly.

**Background:** The DSQL plugin was initially created by cloning the PostgreSQL plugin. The PostgreSQL driver import was mistakenly left in place and should be corrected to use the DSQL driver.

#### Acceptance Criteria

1. THE DSQL_Plugin SHALL import `dsql/driver` instead of `postgresql/driver`
2. THE DSQL_Plugin SHALL import `dsql/session` instead of `postgresql/session`
3. THE DSQL_Driver SHALL detect connection exception codes (08xxx class) for IAM token expiration
4. THE DSQL_Driver SHALL detect "access denied" messages indicating expired IAM tokens
5. THE Implementation SHALL NOT introduce breaking changes to the plugin's public API

### Requirement 2: IAM Token Expiration Handling

**User Story:** As an operator, I want the DSQL plugin to properly detect and handle IAM token expiration, so that database connectivity is maintained without manual intervention.

#### Acceptance Criteria

1. WHEN an IAM token expires, THE DSQL_Plugin SHALL detect the authentication failure
2. WHEN an authentication failure is detected, THE DSQL_Plugin SHALL trigger a connection refresh with a new token
3. THE DSQL_Plugin SHALL log token renewal events for observability

### Requirement 3: Proactive Token Renewal Evaluation

**User Story:** As an operator, I want to evaluate whether proactive token renewal (before expiration) would improve reliability, so that I can avoid brief connectivity gaps.

#### Acceptance Criteria

1. THE Investigation SHALL document the current reactive renewal behavior
2. THE Investigation SHALL evaluate the feasibility of proactive token renewal
3. IF proactive renewal is recommended, THE Investigation SHALL propose an implementation approach

### Requirement 4: Observability

**User Story:** As an operator, I want metrics and logs for IAM token renewal events, so that I can monitor authentication health.

#### Acceptance Criteria

1. THE Investigation SHALL identify existing metrics for connection refresh events
2. THE Investigation SHALL recommend any additional metrics needed for IAM-specific monitoring
