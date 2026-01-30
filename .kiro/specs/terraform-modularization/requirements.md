# Requirements Document

## Status: ✅ COMPLETE

The Terraform modularization has been fully implemented. The flat structure has been removed and replaced with a modular architecture.

## Introduction

This document specifies the requirements for modularizing the Terraform infrastructure in the temporal-dsql-deploy-ecs project. The original flat structure with 25+ files in a single directory has been restructured into reusable modules with environment-specific deployments (dev, bench, prod). This enables code reuse, environment isolation, and follows HashiCorp's recommended module structure and style conventions.

## References

- [HashiCorp Module Structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure) - Standard module structure conventions
- [HashiCorp Terraform Style Guide](https://developer.hashicorp.com/terraform/language/style) - File naming and organization conventions

## Glossary

- **Module**: A reusable Terraform configuration that encapsulates related resources with defined inputs (variables) and outputs
- **Environment**: A deployment target (dev, bench, prod) with its own state, configuration, and resource instances
- **Root_Module**: The top-level Terraform configuration in an environment directory that instantiates child modules
- **Child_Module**: A reusable module called from a root module via `module` blocks
- **State_Isolation**: Keeping Terraform state files separate per environment to prevent cross-environment interference
- **Module_Interface**: The variables.tf (inputs) and outputs.tf (outputs) that define how a module is consumed
- **Temporal_Service**: One of the Temporal server components (History, Matching, Frontend, Worker, UI)
- **Sidecar**: A container that runs alongside the main container (e.g., Alloy for metrics/logs collection)

## Requirements

### Requirement 1: Module Directory Structure

**User Story:** As a platform engineer, I want Terraform modules organized in a standard directory structure, so that I can easily navigate, maintain, and reuse infrastructure components.

#### Acceptance Criteria

1. THE Module_Structure SHALL follow HashiCorp's standard module structure with main.tf, variables.tf, and outputs.tf files
2. WHEN a module requires additional resources, THE Module_Structure SHALL organize them in logically named files (e.g., iam.tf, security-groups.tf)
3. THE Module_Directory SHALL be located at terraform/modules/ relative to the project root
4. WHEN a module uses template files, THE Module_Structure SHALL include a templates/ subdirectory within the module
5. THE Module_Structure SHALL include a README.md file documenting the module's purpose, inputs, and outputs

### Requirement 2: Environment Directory Structure

**User Story:** As a platform engineer, I want environment-specific configurations in separate directories, so that I can deploy and manage dev, bench, and prod environments independently.

#### Acceptance Criteria

1. THE Environment_Structure SHALL create directories at terraform/envs/dev/, terraform/envs/bench/, and terraform/envs/prod/
2. WHEN an environment is configured, THE Environment_Structure SHALL include terraform.tf (version constraints), providers.tf, main.tf, variables.tf, and outputs.tf
3. THE Environment_Main_File SHALL primarily contain module blocks that instantiate child modules
4. WHEN environment-specific values differ, THE Environment_Variables SHALL define appropriate defaults or require explicit values
5. THE Environment_Structure SHALL maintain separate Terraform state per environment

### Requirement 3: VPC and Networking Module

**User Story:** As a platform engineer, I want VPC and networking resources in a dedicated module, so that I can reuse the same network topology across environments with different CIDR ranges.

#### Acceptance Criteria

1. THE VPC_Module SHALL encapsulate VPC, subnets, NAT Gateway, Internet Gateway, and route tables
2. WHEN the VPC_Module is instantiated, THE Module_Interface SHALL accept vpc_cidr, availability_zones, and project_name as inputs
3. THE VPC_Module SHALL output vpc_id, private_subnet_ids, public_subnet_id, and vpc_cidr for use by other modules
4. THE VPC_Module SHALL create VPC endpoints for AWS services (ECR, SSM, Logs, S3) as part of the networking layer
5. WHEN availability_zones are provided, THE VPC_Module SHALL create one private subnet per availability zone

### Requirement 4: ECS Cluster Module

**User Story:** As a platform engineer, I want ECS cluster resources in a dedicated module, so that I can configure cluster settings independently from services.

#### Acceptance Criteria

1. THE ECS_Cluster_Module SHALL encapsulate the ECS cluster, Service Connect namespace, and ECS Exec log group
2. WHEN the ECS_Cluster_Module is instantiated, THE Module_Interface SHALL accept project_name, vpc_id, and log_retention_days as inputs
3. THE ECS_Cluster_Module SHALL output cluster_id, cluster_arn, cluster_name, and service_connect_namespace_arn
4. THE ECS_Cluster_Module SHALL configure Container Insights and execute command logging
5. THE ECS_Cluster_Module SHALL set Service Connect defaults to use the created namespace

### Requirement 5: EC2 Capacity Provider Module

**User Story:** As a platform engineer, I want EC2 capacity provider resources in a dedicated module, so that I can configure instance types and counts per environment.

#### Acceptance Criteria

1. THE EC2_Capacity_Module SHALL encapsulate launch template, Auto Scaling Group, and ECS capacity provider
2. WHEN the EC2_Capacity_Module is instantiated, THE Module_Interface SHALL accept instance_type, instance_count, vpc_id, subnet_ids, and cluster_name as inputs
3. THE EC2_Capacity_Module SHALL output capacity_provider_name, asg_name, and instance_security_group_id
4. THE EC2_Capacity_Module SHALL configure the ECS-optimized ARM64 AMI for Graviton instances
5. WHEN instance_count is specified, THE EC2_Capacity_Module SHALL configure the ASG with that desired capacity

### Requirement 6: Temporal Service Module

**User Story:** As a platform engineer, I want a reusable module for Temporal services, so that I can deploy History, Matching, Frontend, and Worker with consistent configuration patterns.

#### Acceptance Criteria

1. THE Temporal_Service_Module SHALL encapsulate task definition, ECS service, security group, and CloudWatch log group for a single Temporal service
2. WHEN the Temporal_Service_Module is instantiated, THE Module_Interface SHALL accept service_name (history, matching, frontend, worker), cpu, memory, desired_count, and image as inputs
3. THE Temporal_Service_Module SHALL accept dsql_endpoint, opensearch_endpoint, and prometheus_workspace_arn for backend configuration
4. THE Temporal_Service_Module SHALL output service_name, task_definition_arn, and security_group_id
5. WHEN loki_enabled is true, THE Temporal_Service_Module SHALL include Alloy sidecar containers for metrics and log collection
6. THE Temporal_Service_Module SHALL configure Service Connect with appropriate port mappings for each service type

### Requirement 7: Temporal UI Module

**User Story:** As a platform engineer, I want the Temporal UI in a separate module, so that I can optionally deploy it per environment.

#### Acceptance Criteria

1. THE Temporal_UI_Module SHALL encapsulate task definition, ECS service, security group, and CloudWatch log group
2. WHEN the Temporal_UI_Module is instantiated, THE Module_Interface SHALL accept cpu, memory, desired_count, and image as inputs
3. THE Temporal_UI_Module SHALL configure Service Connect to discover temporal-frontend
4. THE Temporal_UI_Module SHALL output service_name and task_definition_arn

### Requirement 8: Observability Module

**User Story:** As a platform engineer, I want observability resources (Prometheus, Grafana, Loki) in a dedicated module, so that I can configure monitoring consistently across environments.

#### Acceptance Criteria

1. THE Observability_Module SHALL encapsulate Amazon Managed Prometheus workspace, Grafana ECS service, and optionally Loki ECS service
2. WHEN the Observability_Module is instantiated, THE Module_Interface SHALL accept loki_enabled, grafana_image, and grafana_admin_secret_name as inputs
3. THE Observability_Module SHALL output prometheus_workspace_arn, prometheus_remote_write_endpoint, and loki_endpoint
4. WHEN loki_enabled is true, THE Observability_Module SHALL create S3 bucket, Loki task definition, and Loki ECS service
5. THE Observability_Module SHALL configure Grafana with datasources for Prometheus and optionally Loki

### Requirement 9: OpenSearch Module

**User Story:** As a platform engineer, I want OpenSearch resources in a dedicated module, so that I can configure visibility store settings per environment.

#### Acceptance Criteria

1. THE OpenSearch_Module SHALL encapsulate OpenSearch domain, security group, and schema setup task definition
2. WHEN the OpenSearch_Module is instantiated, THE Module_Interface SHALL accept instance_type, instance_count, and visibility_index_name as inputs
3. THE OpenSearch_Module SHALL output domain_endpoint, domain_arn, and security_group_id
4. THE OpenSearch_Module SHALL configure VPC access with the provided subnet IDs and security groups

### Requirement 10: Benchmark Module

**User Story:** As a platform engineer, I want benchmark infrastructure in a dedicated module, so that I can optionally deploy it only in bench environment.

#### Acceptance Criteria

1. THE Benchmark_Module SHALL encapsulate benchmark task definition, benchmark worker service, benchmark EC2 capacity provider, and security groups
2. WHEN the Benchmark_Module is instantiated, THE Module_Interface SHALL accept benchmark_image, cpu, memory, and max_instances as inputs
3. THE Benchmark_Module SHALL output task_definition_arn, capacity_provider_name, and worker_service_name
4. THE Benchmark_Module SHALL configure scale-from-zero capability for benchmark EC2 instances
5. WHEN benchmark_enabled is false, THE Root_Module SHALL not instantiate the Benchmark_Module

### Requirement 11: IAM Module

**User Story:** As a platform engineer, I want IAM roles and policies in a dedicated module, so that I can manage permissions consistently and reference them from service modules.

#### Acceptance Criteria

1. THE IAM_Module SHALL encapsulate ECS execution role, Temporal task role, Grafana task role, and Loki task role
2. WHEN the IAM_Module is instantiated, THE Module_Interface SHALL accept dsql_cluster_arn, prometheus_workspace_arn, and opensearch_domain_arn as inputs
3. THE IAM_Module SHALL output execution_role_arn, temporal_task_role_arn, grafana_task_role_arn, and loki_task_role_arn
4. THE IAM_Module SHALL configure least-privilege policies for each role based on required AWS service access

### Requirement 12: Alloy Sidecar Module

**User Story:** As a platform engineer, I want Alloy sidecar configuration in a dedicated module, so that I can consistently add metrics and log collection to any ECS service.

#### Acceptance Criteria

1. THE Alloy_Sidecar_Module SHALL encapsulate SSM parameter for Alloy config and container definition locals
2. WHEN the Alloy_Sidecar_Module is instantiated, THE Module_Interface SHALL accept service_name, prometheus_endpoint, and loki_endpoint as inputs
3. THE Alloy_Sidecar_Module SHALL output init_container_definition and sidecar_container_definition for inclusion in task definitions
4. THE Alloy_Sidecar_Module SHALL configure Docker socket mounting for log collection

### Requirement 13: Environment-Specific Configuration

**User Story:** As a platform engineer, I want environment-specific defaults, so that dev uses minimal resources while prod uses production-grade settings.

#### Acceptance Criteria

1. WHEN deploying to dev environment, THE Environment_Config SHALL default to minimal instance counts and smaller instance types
2. WHEN deploying to bench environment, THE Environment_Config SHALL include benchmark module and larger instance counts for load testing
3. WHEN deploying to prod environment, THE Environment_Config SHALL default to production-grade instance counts and multi-AZ deployment
4. THE Environment_Config SHALL allow overriding defaults via terraform.tfvars files
5. WHEN environment-specific secrets are required, THE Environment_Config SHALL reference environment-prefixed secret names

### Requirement 14: State Management

**User Story:** As a platform engineer, I want isolated Terraform state per environment, so that changes in one environment cannot affect another.

#### Acceptance Criteria

1. THE State_Configuration SHALL use separate state files for each environment (dev, bench, prod)
2. WHEN using remote state, THE State_Configuration SHALL use environment-specific S3 keys or workspaces
3. THE State_Configuration SHALL document the recommended backend configuration in each environment's README
4. IF cross-environment references are needed, THE State_Configuration SHALL use terraform_remote_state data sources

### Requirement 15: Migration Path

**User Story:** As a platform engineer, I want a clear migration path from the current flat structure, so that I can transition without losing existing infrastructure.

#### Acceptance Criteria

1. THE Migration_Process SHALL document steps to move resources from flat structure to modular structure
2. WHEN migrating existing state, THE Migration_Process SHALL use terraform state mv commands to relocate resources
3. THE Migration_Process SHALL provide a validation checklist to verify successful migration
4. THE Migration_Process SHALL maintain backward compatibility during the transition period
5. IF migration fails, THE Migration_Process SHALL document rollback procedures


### Requirement 16: Script Updates

**User Story:** As a platform engineer, I want operational scripts updated to work with the new modular structure, so that I can continue using familiar commands for scaling and management.

#### Acceptance Criteria

1. THE scale-services.sh Script SHALL be updated to accept an environment parameter (dev, bench, prod)
2. WHEN scale-services.sh is invoked, THE Script SHALL change to the appropriate environment directory before running Terraform commands
3. THE scale-benchmark-workers.sh Script SHALL be updated to work with the modular structure and accept an environment parameter
4. WHEN scripts reference Terraform outputs, THE Scripts SHALL use the correct module output paths
5. THE Scripts SHALL validate that the specified environment directory exists before executing
6. THE Scripts SHALL provide clear error messages when invoked with invalid environment parameters

### Requirement 17: DSQL Connection Reservoir Support

**User Story:** As a platform engineer, I want to configure the DSQL Connection Reservoir feature, so that I can use rate-limit-aware connection management for improved performance and reliability.

#### Acceptance Criteria

1. THE DynamoDB_Module SHALL create an optional connection lease table for distributed connection count limiting
2. WHEN reservoir_enabled is true, THE Temporal_Service_Module SHALL configure reservoir environment variables (DSQL_RESERVOIR_ENABLED, DSQL_RESERVOIR_TARGET_READY, DSQL_RESERVOIR_BASE_LIFETIME, DSQL_RESERVOIR_LIFETIME_JITTER, DSQL_RESERVOIR_GUARD_WINDOW)
3. WHEN distributed_conn_lease_enabled is true, THE Temporal_Service_Module SHALL configure distributed connection lease environment variables (DSQL_DISTRIBUTED_CONN_LEASE_ENABLED, DSQL_DISTRIBUTED_CONN_LEASE_TABLE, DSQL_DISTRIBUTED_CONN_LIMIT)
4. THE IAM_Module SHALL grant DynamoDB access to the connection lease table when distributed connection leasing is enabled
5. THE Environment_Config SHALL provide sensible defaults for reservoir configuration (reservoir_enabled=true for bench/prod, distributed_conn_lease_enabled=true for bench/prod)
6. THE DynamoDB_Module SHALL output conn_lease_table_name and conn_lease_table_arn for use by other modules
