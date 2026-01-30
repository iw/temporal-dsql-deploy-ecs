# Implementation Plan: Terraform Modularization

## Status: ✅ COMPLETE

All tasks have been completed. The flat Terraform configuration has been removed and replaced with the modular structure.

## Summary

- **11 modules** created in `terraform/modules/`
- **3 environments** created in `terraform/envs/` (dev, bench, prod)
- **Flat TF removed** - 34 files deleted from `terraform/` root
- **AGENTS.md updated** to reflect new structure
- **Scripts updated** to work with environment parameter

## Overview

This implementation plan restructures the Terraform infrastructure from a flat file structure to a modular architecture with environment-specific deployments. The tasks are organized to build incrementally, with each module validated before proceeding to the next.

## Tasks

- [x] 1. Create module directory structure and base files
  - [x] 1.1 Create terraform/modules/ directory and subdirectories for all modules
    - Create directories: vpc, ecs-cluster, ec2-capacity, temporal-service, temporal-ui, observability, opensearch, benchmark, iam, alloy-sidecar, dynamodb
    - _Requirements: 1.1, 1.3_
  
  - [x] 1.2 Create README.md template for each module
    - Include sections: Purpose, Inputs, Outputs, Usage Example
    - _Requirements: 1.5_

- [x] 2. Implement VPC module
  - [x] 2.1 Create modules/vpc/main.tf with VPC, subnets, NAT Gateway, IGW, route tables
    - Extract resources from current vpc.tf
    - Parameterize project_name, vpc_cidr, availability_zones
    - _Requirements: 3.1, 3.5_
  
  - [x] 2.2 Create modules/vpc/vpc-endpoints.tf with VPC endpoints
    - Extract resources from current vpc-endpoints.tf
    - _Requirements: 3.4_
  
  - [x] 2.3 Create modules/vpc/variables.tf with required inputs
    - Define: project_name, vpc_cidr, availability_zones, enable_vpc_endpoints
    - _Requirements: 3.2_
  
  - [x] 2.4 Create modules/vpc/outputs.tf with required outputs
    - Define: vpc_id, vpc_cidr, private_subnet_ids, public_subnet_id, nat_gateway_id
    - _Requirements: 3.3_
  
  - [x] 2.5 Validate VPC module with terraform validate
    - Run terraform init and validate in modules/vpc/
    - _Requirements: 1.1_

- [x] 3. Implement ECS Cluster module
  - [x] 3.1 Create modules/ecs-cluster/main.tf with ECS cluster, Service Connect namespace, log group
    - Extract resources from current ecs-cluster.tf
    - Configure Container Insights and execute command logging
    - _Requirements: 4.1, 4.4, 4.5_
  
  - [x] 3.2 Create modules/ecs-cluster/variables.tf with required inputs
    - Define: project_name, log_retention_days
    - _Requirements: 4.2_
  
  - [x] 3.3 Create modules/ecs-cluster/outputs.tf with required outputs
    - Define: cluster_id, cluster_arn, cluster_name, service_connect_namespace_arn, ecs_exec_log_group_name
    - _Requirements: 4.3_
  
  - [x] 3.4 Validate ECS Cluster module with terraform validate
    - _Requirements: 1.1_

- [x] 4. Implement EC2 Capacity module
  - [x] 4.1 Create modules/ec2-capacity/main.tf with launch template, ASG, capacity provider
    - Extract resources from current ec2-cluster.tf
    - Configure ARM64 AMI for Graviton instances
    - _Requirements: 5.1, 5.4, 5.5_
  
  - [x] 4.2 Create modules/ec2-capacity/iam.tf with EC2 instance role
    - Extract instance role from current iam.tf
    - _Requirements: 5.1_
  
  - [x] 4.3 Create modules/ec2-capacity/security-groups.tf with instance security group
    - Extract ECS instances security group from current security-groups.tf
    - _Requirements: 5.1_
  
  - [x] 4.4 Create modules/ec2-capacity/variables.tf with required inputs
    - Define: project_name, cluster_name, vpc_id, subnet_ids, instance_type, instance_count, workload_type
    - _Requirements: 5.2_
  
  - [x] 4.5 Create modules/ec2-capacity/outputs.tf with required outputs
    - Define: capacity_provider_name, asg_name, instance_security_group_id, instance_role_arn
    - _Requirements: 5.3_
  
  - [x] 4.6 Validate EC2 Capacity module with terraform validate
    - _Requirements: 1.1_

- [x] 5. Checkpoint - Validate infrastructure modules
  - ✅ All infrastructure modules (vpc, ecs-cluster, ec2-capacity) pass terraform validate

- [x] 6. Implement IAM module
  - [x] 6.1 Create modules/iam/main.tf with ECS execution role, Temporal task role, Grafana task role, Loki task role
    - Extract roles and policies from current iam.tf
    - Parameterize resource ARNs for policies
    - _Requirements: 11.1_
  
  - [x] 6.2 Create modules/iam/variables.tf with required inputs
    - Define: project_name, dsql_cluster_arn, prometheus_workspace_arn, opensearch_domain_arn, dynamodb_table_arn, loki_enabled, loki_s3_bucket_arn
    - _Requirements: 11.2_
  
  - [x] 6.3 Create modules/iam/outputs.tf with required outputs
    - Define: execution_role_arn, temporal_task_role_arn, grafana_task_role_arn, loki_task_role_arn, temporal_ui_task_role_arn
    - _Requirements: 11.3_
  
  - [x] 6.4 Validate IAM module with terraform validate
    - _Requirements: 1.1_

- [x] 7. Implement DynamoDB module
  - [x] 7.1 Create modules/dynamodb/main.tf with rate limiter table
    - Extract resources from current dynamodb.tf
    - _Requirements: 11.1_
  
  - [x] 7.2 Create modules/dynamodb/variables.tf and outputs.tf
    - Define inputs: project_name
    - Define outputs: table_name, table_arn
    - _Requirements: 11.2, 11.3_
  
  - [x] 7.3 Validate DynamoDB module with terraform validate
    - _Requirements: 1.1_

- [x] 8. Implement OpenSearch module
  - [x] 8.1 Create modules/opensearch/main.tf with OpenSearch domain and setup task
    - Extract resources from current opensearch.tf
    - _Requirements: 9.1_
  
  - [x] 8.2 Create modules/opensearch/security-groups.tf with OpenSearch security group
    - Extract security group from current security-groups.tf
    - _Requirements: 9.1_
  
  - [x] 8.3 Create modules/opensearch/variables.tf with required inputs
    - Define: project_name, vpc_id, subnet_ids, instance_type, instance_count, visibility_index_name, execution_role_arn, admin_tools_image
    - _Requirements: 9.2_
  
  - [x] 8.4 Create modules/opensearch/outputs.tf with required outputs
    - Define: domain_endpoint, domain_arn, security_group_id, setup_task_definition_arn
    - _Requirements: 9.3_
  
  - [x] 8.5 Validate OpenSearch module with terraform validate
    - _Requirements: 1.1_

- [x] 9. Implement Observability module
  - [x] 9.1 Create modules/observability/main.tf with Prometheus workspace
    - Extract resources from current prometheus.tf
    - _Requirements: 8.1_
  
  - [x] 9.2 Create modules/observability/grafana.tf with Grafana task definition and service
    - Extract resources from current grafana.tf
    - _Requirements: 8.1, 8.5_
  
  - [x] 9.3 Create modules/observability/loki.tf with Loki task definition and service (conditional)
    - Extract resources from current loki.tf
    - Use count based on loki_enabled variable
    - _Requirements: 8.1, 8.4_
  
  - [x] 9.4 Create modules/observability/loki-s3.tf with S3 bucket for Loki (conditional)
    - Extract resources from current loki-s3.tf
    - _Requirements: 8.4_
  
  - [x] 9.5 Create modules/observability/templates/loki-config.yaml
    - Copy from current templates/loki-config.yaml
    - _Requirements: 1.4_
  
  - [x] 9.6 Create modules/observability/variables.tf with required inputs
    - Define: project_name, cluster_id, cluster_name, vpc_id, subnet_ids, capacity_provider_name, instance_security_group_id, service_connect_namespace_arn, execution_role_arn, grafana_task_role_arn, loki_task_role_arn, loki_enabled, grafana_image, grafana_admin_secret_name, loki_image, loki_retention_days, log_retention_days, region
    - _Requirements: 8.2_
  
  - [x] 9.7 Create modules/observability/outputs.tf with required outputs
    - Define: prometheus_workspace_arn, prometheus_remote_write_endpoint, prometheus_query_endpoint, loki_endpoint, loki_s3_bucket_name, loki_s3_bucket_arn, grafana_service_name
    - _Requirements: 8.3_
  
  - [x] 9.8 Validate Observability module with terraform validate
    - _Requirements: 1.1_

- [x] 10. Checkpoint - Validate data and observability modules
  - ✅ All modules pass terraform validate

- [x] 11. Implement Alloy Sidecar module
  - [x] 11.1 Create modules/alloy-sidecar/main.tf with SSM parameter and container definition locals
    - Extract resources from current alloy-sidecar.tf
    - Parameterize service_name for different services
    - _Requirements: 12.1, 12.4_
  
  - [x] 11.2 Create modules/alloy-sidecar/templates/alloy-sidecar-config.alloy
    - Copy from current templates/alloy-sidecar-config.alloy
    - _Requirements: 1.4_
  
  - [x] 11.3 Create modules/alloy-sidecar/variables.tf with required inputs
    - Define: project_name, service_name, prometheus_remote_write_endpoint, loki_endpoint, region, alloy_image, log_group_name
    - _Requirements: 12.2_
  
  - [x] 11.4 Create modules/alloy-sidecar/outputs.tf with required outputs
    - Define: init_container_definition, sidecar_container_definition, ssm_parameter_arn
    - _Requirements: 12.3_
  
  - [x] 11.5 Validate Alloy Sidecar module with terraform validate
    - _Requirements: 1.1_

- [x] 12. Implement Temporal Service module
  - [x] 12.1 Create modules/temporal-service/main.tf with task definition and ECS service
    - Create parameterized version supporting history, matching, frontend, worker
    - Use service_type variable to configure ports, environment variables
    - Include conditional Alloy sidecar containers
    - _Requirements: 6.1, 6.5, 6.6_
  
  - [x] 12.2 Create modules/temporal-service/security-groups.tf with service security group
    - Create parameterized security group based on service_type
    - _Requirements: 6.1_
  
  - [x] 12.3 Create modules/temporal-service/variables.tf with required inputs
    - Define all inputs from design document Components section
    - _Requirements: 6.2, 6.3_
  
  - [x] 12.4 Create modules/temporal-service/outputs.tf with required outputs
    - Define: service_name, task_definition_arn, security_group_id, log_group_name
    - _Requirements: 6.4_
  
  - [x] 12.5 Validate Temporal Service module with terraform validate
    - _Requirements: 1.1_

- [x] 13. Implement Temporal UI module
  - [x] 13.1 Create modules/temporal-ui/main.tf with task definition and ECS service
    - Extract resources from current temporal-ui.tf
    - Configure Service Connect to discover temporal-frontend
    - _Requirements: 7.1, 7.3_
  
  - [x] 13.2 Create modules/temporal-ui/variables.tf with required inputs
    - Define: project_name, cluster_id, cluster_name, vpc_id, subnet_ids, capacity_provider_name, instance_security_group_id, service_connect_namespace_arn, execution_role_arn, task_role_arn, image, cpu, memory, desired_count, log_retention_days, region
    - _Requirements: 7.2_
  
  - [x] 13.3 Create modules/temporal-ui/outputs.tf with required outputs
    - Define: service_name, task_definition_arn, security_group_id
    - _Requirements: 7.4_
  
  - [x] 13.4 Validate Temporal UI module with terraform validate
    - _Requirements: 1.1_

- [x] 14. Implement Benchmark module
  - [x] 14.1 Create modules/benchmark/main.tf with benchmark task definition
    - Extract resources from current benchmark.tf
    - _Requirements: 10.1_
  
  - [x] 14.2 Create modules/benchmark/worker.tf with benchmark worker service
    - Extract resources from current benchmark-worker.tf
    - _Requirements: 10.1_
  
  - [x] 14.3 Create modules/benchmark/ec2.tf with benchmark capacity provider
    - Extract resources from current benchmark-ec2.tf
    - Configure scale-from-zero capability
    - _Requirements: 10.1, 10.4_
  
  - [x] 14.4 Create modules/benchmark/security-groups.tf and iam.tf
    - Extract benchmark security group and IAM role
    - _Requirements: 10.1_
  
  - [x] 14.5 Create modules/benchmark/variables.tf with required inputs
    - Define: project_name, cluster_id, cluster_name, vpc_id, subnet_ids, service_connect_namespace_arn, execution_role_arn, prometheus_workspace_arn, frontend_security_group_id, benchmark_image, cpu, memory, max_instances, log_retention_days, region
    - _Requirements: 10.2_
  
  - [x] 14.6 Create modules/benchmark/outputs.tf with required outputs
    - Define: task_definition_arn, capacity_provider_name, worker_service_name, security_group_id
    - _Requirements: 10.3_
  
  - [x] 14.7 Validate Benchmark module with terraform validate
    - _Requirements: 1.1_

- [x] 15. Checkpoint - Validate all modules
  - ✅ All modules pass terraform validate

- [x] 16. Create dev environment
  - [x] 16.1 Create terraform/envs/dev/terraform.tf with version constraints
    - Define required_version >= 1.5.0
    - Define required_providers (aws >= 5.0)
    - _Requirements: 2.1, 2.2_
  
  - [x] 16.2 Create terraform/envs/dev/providers.tf with AWS provider
    - Configure region and default tags
    - _Requirements: 2.2_
  
  - [x] 16.3 Create terraform/envs/dev/main.tf with module instantiations
    - Instantiate all modules with appropriate variable values
    - Wire module outputs to dependent module inputs
    - _Requirements: 2.2, 2.3_
  
  - [x] 16.4 Create terraform/envs/dev/variables.tf with environment variables
    - Define all variables needed by modules
    - Set dev-appropriate defaults (minimal resources)
    - _Requirements: 2.2, 2.4, 13.1_
  
  - [x] 16.5 Create terraform/envs/dev/outputs.tf with environment outputs
    - Expose key outputs from modules
    - _Requirements: 2.2_
  
  - [x] 16.6 Create terraform/envs/dev/README.md with environment documentation
    - Document backend configuration
    - Document deployment steps
    - _Requirements: 14.3_
  
  - [x] 16.7 Validate dev environment with terraform validate
    - Run terraform init and validate in envs/dev/
    - _Requirements: 2.2_

- [x] 17. Create bench environment
  - [x] 17.1 Create terraform/envs/bench/ with all required files
    - Copy structure from dev environment
    - Include benchmark module instantiation
    - _Requirements: 2.1, 2.2, 13.2_
  
  - [x] 17.2 Configure bench-specific defaults in variables.tf
    - Larger instance counts for load testing
    - benchmark_enabled = true
    - _Requirements: 13.2_
  
  - [x] 17.3 Validate bench environment with terraform validate
    - _Requirements: 2.2_

- [x] 18. Create prod environment
  - [x] 18.1 Create terraform/envs/prod/ with all required files
    - Copy structure from dev environment
    - Exclude benchmark module
    - _Requirements: 2.1, 2.2, 13.3_
  
  - [x] 18.2 Configure prod-specific defaults in variables.tf
    - Production-grade instance counts
    - benchmark_enabled = false
    - _Requirements: 13.3_
  
  - [x] 18.3 Validate prod environment with terraform validate
    - _Requirements: 2.2_

- [x] 19. Checkpoint - Validate all environments
  - ✅ All environments pass terraform validate

- [x] 20. Update operational scripts
  - [x] 20.1 Update scripts/scale-services.sh to accept environment parameter
    - Add environment argument parsing
    - Change to appropriate environment directory
    - Update Terraform output references
    - _Requirements: 16.1, 16.2, 16.4_
  
  - [x] 20.2 Add environment validation to scale-services.sh
    - Check environment directory exists
    - Provide clear error messages for invalid environments
    - _Requirements: 16.5, 16.6_
  
  - [x] 20.3 Update scripts/scale-benchmark-workers.sh for modular structure
    - Add environment argument parsing
    - Update paths and output references
    - _Requirements: 16.3, 16.4_
  
  - [x] 20.4 Add environment validation to scale-benchmark-workers.sh
    - Check environment directory exists
    - Provide clear error messages
    - _Requirements: 16.5, 16.6_

- [x] 21. Create migration documentation
  - [x] 21.1 ~~Create terraform/MIGRATION.md with state migration steps~~ - Not needed, fresh deployment used
  - [x] 21.2 ~~Document rollback procedures~~ - Not needed, flat TF removed after successful modular deployment

- [x] 22. Create top-level documentation
  - [x] 22.1 Create terraform/README.md with project overview
    - Document directory structure
    - Document module usage
    - Document environment deployment
    - _Requirements: 1.5_

- [x] 23. Final checkpoint - Complete validation
  - ✅ All modules and environments pass terraform validate
  - ✅ All README files exist
  - ✅ Scripts work with new structure
  - ✅ Flat TF configuration removed (34 files deleted)

- [x] 24. Add DSQL Connection Reservoir support
  - [x] 24.1 Update DynamoDB module to create connection lease table
    - Add conn_lease_enabled variable to control table creation
    - Create aws_dynamodb_table.dsql_conn_lease with pk (String) hash key
    - Enable TTL on ttl_epoch attribute for automatic cleanup
    - Add outputs: conn_lease_table_name, conn_lease_table_arn
    - _Requirements: 17.1, 17.6_
  
  - [x] 24.2 Update IAM module to grant DynamoDB access for connection lease table
    - Add conn_lease_table_arn variable (optional)
    - Add DynamoDB permissions to Temporal task role when conn_lease_table_arn is provided
    - _Requirements: 17.4_
  
  - [x] 24.3 Update temporal-service module with reservoir configuration variables
    - Add dsql_reservoir_enabled, dsql_reservoir_target_ready, dsql_reservoir_base_lifetime, dsql_reservoir_lifetime_jitter, dsql_reservoir_guard_window variables
    - Add dsql_distributed_conn_lease_enabled, dsql_conn_lease_table, dsql_distributed_conn_limit variables
    - _Requirements: 17.2, 17.3_
  
  - [x] 24.4 Update temporal-service module task definition with reservoir environment variables
    - Add DSQL_RESERVOIR_ENABLED, DSQL_RESERVOIR_TARGET_READY, DSQL_RESERVOIR_BASE_LIFETIME, DSQL_RESERVOIR_LIFETIME_JITTER, DSQL_RESERVOIR_GUARD_WINDOW when reservoir_enabled is true
    - Add DSQL_DISTRIBUTED_CONN_LEASE_ENABLED, DSQL_DISTRIBUTED_CONN_LEASE_TABLE, DSQL_DISTRIBUTED_CONN_LIMIT when distributed_conn_lease_enabled is true
    - _Requirements: 17.2, 17.3_
  
  - [x] 24.5 Update dev environment with reservoir configuration
    - Add reservoir variables to variables.tf with dev defaults (disabled)
    - Update main.tf to pass reservoir variables to temporal-service modules
    - Update main.tf to pass conn_lease_table_arn to IAM module
    - _Requirements: 17.5_
  
  - [x] 24.6 Update bench environment with reservoir configuration
    - Add reservoir variables to variables.tf with bench defaults (enabled)
    - Update main.tf to pass reservoir variables to temporal-service modules
    - Update main.tf to pass conn_lease_table_arn to IAM module
    - _Requirements: 17.5_
  
  - [x] 24.7 Validate all modules and environments with terraform validate
    - _Requirements: 17.2, 17.3_

## Notes

- Tasks are ordered to build incrementally with validation at each step
- Infrastructure modules (vpc, ecs-cluster, ec2-capacity) are created first as they have no dependencies
- Application modules depend on infrastructure module outputs
- Environment configurations wire all modules together
- State migration was not needed - fresh deployment to modular structure was used
- Each module validation ensures the module is syntactically correct before proceeding

## Completion Notes (January 2026)

The modularization is complete:

1. **Modules Created**: 11 reusable modules in `terraform/modules/`
   - vpc, ecs-cluster, ec2-capacity, temporal-service, temporal-ui
   - observability, opensearch, benchmark, iam, alloy-sidecar, dynamodb

2. **Environments Created**: 3 environments in `terraform/envs/`
   - dev (minimal resources, no benchmark)
   - bench (high-throughput, benchmark enabled)
   - prod (production-grade, no benchmark)

3. **Flat TF Removed**: 34 files deleted from `terraform/` root
   - All `.tf` files, state files, lock files, tfvars, README

4. **Key Design Decisions**:
   - `loki_enabled` variable removed - Loki/Alloy always-on
   - `use_ec2_capacity` variable removed - EC2-only (no Fargate)
   - `temporal_dynamicconfig_tmpfs_size` not implemented - dynamic config baked into image
   - ADOT standalone service replaced by Alloy sidecars
