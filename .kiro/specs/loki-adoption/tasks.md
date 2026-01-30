# Implementation Plan: Loki Adoption

## Overview

This implementation plan covers replacing CloudWatch Logs with Grafana Loki for log aggregation, using Grafana Alloy as a unified collector for both metrics and logs. The plan is organized into phases: infrastructure setup, Alloy migration, Grafana integration, and validation.

## Tasks

- [x] 1. Create Loki Infrastructure
  - [x] 1.1 Create S3 bucket for Loki storage
    - Create `loki-s3.tf` with S3 bucket resource
    - Configure server-side encryption (SSE-S3)
    - Add lifecycle policy for retention + 1 day expiration
    - Disable versioning (append-only logs)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [x] 1.2 Create Loki IAM role and policy
    - Add Loki task role to `iam.tf`
    - Grant S3 read/write permissions to Loki bucket
    - Grant ECS task execution permissions
    - _Requirements: 2.6, 6.6_

  - [x] 1.3 Create Loki security group
    - Add security group to `security-groups.tf`
    - Allow ingress on port 3100 from ECS instances
    - Allow ingress from Grafana security group
    - _Requirements: 6.3, 6.4_

  - [x] 1.4 Create Loki configuration template
    - Create `templates/loki-config.yaml`
    - Configure S3 storage backend with TSDB
    - Set retention period from variable
    - Configure compactor for retention enforcement
    - _Requirements: 1.6, 1.7, 5.1, 5.2, 5.3_

  - [x] 1.5 Create Loki ECS task definition and service
    - Create `loki.tf` with task definition
    - Use ARM64 architecture
    - Configure port 3100 for HTTP API
    - Add health check on `/ready` endpoint
    - Store config in SSM Parameter Store
    - _Requirements: 1.1, 1.2, 1.3, 1.5, 1.6_

  - [x] 1.6 Add Loki to Service Connect namespace
    - Configure Service Connect for Loki service
    - Register DNS name `loki`
    - _Requirements: 1.4_

  - [x] 1.7 Add Loki variables to variables.tf
    - Add `loki_enabled`, `loki_cpu`, `loki_memory`, `loki_count`
    - Add `loki_retention_days`, `loki_image`
    - Add `alloy_image` variable
    - _Requirements: 5.5, 7.1, 7.5, 10.1_

- [ ] 2. Checkpoint - Verify Loki deployment
  - Deploy Loki infrastructure with `terraform apply`
  - Verify Loki service is healthy
  - Test `/ready` endpoint via ECS Exec
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Create Alloy Sidecar Configuration
  - [x] 3.1 Create Alloy configuration template
    - Create `templates/alloy-sidecar-config.alloy`
    - Configure `loki.source.docker` for log collection
    - Configure `prometheus.scrape` for metrics
    - Configure `loki.write` to send logs to Loki
    - Configure `prometheus.remote_write` to send metrics to AMP
    - Add label enrichment for service_name, task_id, cluster
    - _Requirements: 3.3, 3.5, 3.6, 3.7, 3.8_

  - [x] 3.2 Create Alloy sidecar Terraform locals
    - Create `alloy-sidecar.tf`
    - Define Alloy container definition template
    - Configure Docker socket mount for log access
    - Set essential=false for resilience
    - Configure SSM parameter for config
    - _Requirements: 3.1, 3.4, 3.10, 3.11, 3.12_

  - [x] 3.3 Create SSM parameters for Alloy configs
    - Create per-service SSM parameters (history, matching, frontend, worker)
    - Template with service-specific labels
    - _Requirements: 3.12_

- [x] 4. Migrate Temporal Services to Alloy
  - [x] 4.1 Update temporal-history.tf
    - Replace ADOT sidecar with Alloy sidecar
    - Add Docker socket volume mount
    - Update container definitions
    - _Requirements: 3.1, 3.2_

  - [x] 4.2 Update temporal-matching.tf
    - Replace ADOT sidecar with Alloy sidecar
    - Add Docker socket volume mount
    - Update container definitions
    - _Requirements: 3.1, 3.2_

  - [x] 4.3 Update temporal-frontend.tf
    - Replace ADOT sidecar with Alloy sidecar
    - Add Docker socket volume mount
    - Update container definitions
    - _Requirements: 3.1, 3.2_

  - [x] 4.4 Update temporal-worker.tf
    - Replace ADOT sidecar with Alloy sidecar
    - Add Docker socket volume mount
    - Update container definitions
    - _Requirements: 3.1, 3.2_

  - [x] 4.5 Update benchmark-worker.tf (if exists)
    - Replace ADOT sidecar with Alloy sidecar
    - Add Docker socket volume mount
    - _Requirements: 3.1, 3.2_

- [ ] 5. Checkpoint - Verify Alloy migration
  - Deploy updated services with `terraform apply`
  - Verify logs appear in Loki via LogQL query
  - Verify metrics continue flowing to AMP
  - Check Alloy sidecar logs for errors
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Configure Grafana Integration
  - [x] 6.1 Create Loki datasource provisioning file
    - Create `grafana/provisioning/datasources/loki.yaml`
    - Configure URL as `http://loki:3100`
    - Set appropriate timeout and max lines
    - _Requirements: 4.1, 4.2, 4.3_

  - [x] 6.2 Update Grafana Dockerfile
    - Add Loki datasource to provisioning
    - Rebuild Grafana image
    - _Requirements: 4.4_

  - [x] 6.3 Update grafana.tf if needed
    - Ensure Grafana can reach Loki via Service Connect
    - Add Loki security group to Grafana network config
    - _Requirements: 4.1_

- [ ] 7. Checkpoint - Verify Grafana integration
  - Rebuild and push Grafana image
  - Redeploy Grafana service
  - Verify Loki datasource appears in Grafana
  - Test LogQL query in Grafana Explore
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Cleanup and Documentation
  - [x] 8.1 Remove ADOT sidecar configuration
    - Delete `adot-sidecar.tf`
    - Delete `templates/adot-sidecar-config.yaml`
    - Remove ADOT SSM parameters
    - _Requirements: 3.2_

  - [x] 8.2 Update outputs.tf
    - Add Loki endpoint output
    - Add Loki S3 bucket output
    - _Requirements: N/A_

  - [x] 8.3 Update terraform.tfvars.example
    - Add Loki configuration examples
    - Document Alloy image version
    - _Requirements: N/A_

  - [x] 8.4 Keep CloudWatch Log Groups (do not delete)
    - Verify CloudWatch log groups remain for rollback
    - Document that CloudWatch can be re-enabled if needed
    - _Requirements: 8.3, 8.5_

- [ ] 9. Final Checkpoint - End-to-end validation
  - Run a benchmark workload to generate logs
  - Query logs in Grafana using LogQL
  - Verify all services have logs in Loki
  - Verify metrics dashboards still work
  - Verify S3 bucket contains log chunks
  - Ensure all tests pass, ask the user if questions arise.

- [ ]* 10. Optional: Property-based tests
  - [ ]* 10.1 Write test for log ingestion completeness
    - **Property 1: Log Ingestion Completeness**
    - Generate test logs, verify they appear in Loki
    - **Validates: Requirements 3.3, 3.5**

  - [ ]* 10.2 Write test for label consistency
    - **Property 2: Label Consistency**
    - Query logs, verify required labels are present
    - **Validates: Requirements 3.8**

  - [ ]* 10.3 Write test for metrics continuity
    - **Property 3: Metrics Pipeline Continuity**
    - Compare metrics before/after migration
    - **Validates: Requirements 3.2, 3.6**

  - [ ]* 10.4 Write test for sidecar resilience
    - **Property 5: Sidecar Resilience**
    - Kill Alloy sidecar, verify main container continues
    - **Validates: Requirements 3.11**

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- CloudWatch Logs resources are intentionally kept for rollback capability
- The migration replaces ADOT with Alloy - this is a unified collector change
