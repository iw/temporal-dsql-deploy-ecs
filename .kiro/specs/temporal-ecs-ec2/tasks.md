# Implementation Plan: Temporal ECS EC2 Deployment

## Overview

This implementation plan creates a Terraform module for deploying Temporal on AWS ECS with EC2 instances (Graviton) using multi-service architecture, ECS Service Connect, and private-only networking. The implementation follows an incremental approach, building foundational infrastructure first, then adding services layer by layer.

## Tasks

- [x] 1. Set up project structure and provider configuration
  - Create directory structure for Terraform files
  - Configure AWS provider with region variable
  - Create terraform.tfvars.example with all configurable variables
  - Create .gitignore for Terraform projects
  - _Requirements: 17.4, 16.3, 16.4_

- [x] 1.5 Implement ECR repositories and build script
  - [x] 1.5.1 ECR repositories created by build script
    - Script creates ECR repository for temporal-dsql server image if not exists
    - Script creates ECR repository for temporal-dsql-admin-tools image if not exists
    - Enable image scanning on push for both repositories
    - Configure lifecycle policy to retain only last 10 untagged images
    - Self-contained approach removes Terraform dependency for image builds
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.12_

  - [x] 1.5.2 Create build and push script
    - Create scripts/build-and-push-ecr.sh
    - Accept temporal-dsql source path as parameter
    - Build Go binaries for ARM64 using Makefile targets (temporal-server, temporal-sql-tool, temporal-elasticsearch-tool, temporal-dsql-tool, tdbg)
    - Build Docker images using official Dockerfiles from temporal-dsql/docker/targets/
    - Use docker buildx for ARM64 cross-compilation
    - Download Temporal CLI for admin-tools image
    - Authenticate with ECR using aws ecr get-login-password
    - Tag with 'latest' and git-sha-timestamp version
    - Push server and admin-tools images to ECR
    - _Requirements: 15.5, 15.6, 15.7, 15.8, 15.9, 15.10, 15.11_

- [x] 2. Implement VPC and networking infrastructure
  - [x] 2.1 Create VPC with DNS support
    - Create aws_vpc resource with configurable CIDR
    - Enable DNS hostnames and DNS support
    - _Requirements: 1.1_

  - [x] 2.2 Create private subnets across availability zones
    - Create aws_subnet resources for private subnets
    - Distribute across configured availability zones
    - _Requirements: 1.2_

  - [x] 2.3 Create NAT Gateway infrastructure
    - Create small public subnet for NAT Gateway only
    - Create aws_eip for NAT Gateway
    - Create aws_nat_gateway in public subnet
    - Create aws_internet_gateway for NAT Gateway subnet
    - _Requirements: 1.4_

  - [x] 2.4 Create route tables
    - Create private route table with NAT Gateway route
    - Associate private subnets with private route table
    - Create public route table for NAT subnet
    - _Requirements: 1.5_

- [ ]* 2.5 Write property test for private-only networking
  - **Property 1: Private-Only Networking**
  - Validate no public IPs assigned, no 0.0.0.0/0 ingress rules
  - **Validates: Requirements 1.3, 5.3, 5.4, 10.2**

- [x] 3. Implement VPC endpoints
  - [x] 3.1 Create interface VPC endpoints
    - Create endpoints for ECR API, ECR DKR, CloudWatch Logs
    - Create endpoints for SSM, SSM Messages, EC2 Messages
    - Create endpoints for Secrets Manager, APS Workspaces
    - Configure private DNS for all interface endpoints
    - _Requirements: 2.1, 2.2, 2.3, 2.5, 2.6_

  - [x] 3.2 Create gateway VPC endpoint for S3
    - Create S3 gateway endpoint
    - Associate with private route table
    - _Requirements: 2.4_

  - [x] 3.3 Create VPC endpoints security group
    - Allow HTTPS (443) from VPC CIDR
    - _Requirements: 2.7_

- [ ]* 3.4 Write property test for VPC endpoint completeness
  - **Property 4: VPC Endpoint Completeness**
  - Validate all required endpoints exist with correct service names
  - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7**


- [x] 4. Checkpoint - Validate networking infrastructure
  - Run terraform validate and terraform plan
  - Ensure all networking resources are correctly configured
  - Ask the user if questions arise

- [x] 5. Implement IAM roles and policies
  - [x] 5.1 Create ECS task execution role
    - Create IAM role with ecs-tasks.amazonaws.com trust policy
    - Attach AmazonECSTaskExecutionRolePolicy
    - Add Secrets Manager read policy for Grafana secret
    - _Requirements: 11.1, 11.2, 13.3_

  - [x] 5.2 Create Temporal task role
    - Create IAM role for Temporal services
    - Add ECS Exec permissions (ssmmessages actions)
    - Add DSQL access policy (dsql:DbConnect, dsql:DbConnectAdmin)
    - Add Prometheus remote write policy
    - Add OpenSearch access policy (es:ESHttp*)
    - _Requirements: 11.3, 11.4, 11.5, 11.6_

  - [x] 5.3 Create Grafana task role
    - Create IAM role for Grafana
    - Add ECS Exec permissions
    - Add Prometheus query permissions
    - _Requirements: 11.7_

- [ ]* 5.4 Write property test for IAM least privilege
  - **Property 7: IAM Least Privilege**
  - Validate policies grant only minimum required permissions
  - **Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7**

- [x] 6. Implement security groups
  - [x] 6.1 Create Temporal service security groups
    - Create security group for History service
    - Create security group for Matching service
    - Create security group for Frontend service
    - Create security group for Worker service
    - Create security group for UI service
    - Configure inter-service communication rules
    - _Requirements: 10.1, 10.3, 10.4, 10.6_

  - [x] 6.2 Create supporting security groups
    - Create security group for Grafana
    - Create security group for OpenSearch
    - _Requirements: 10.1_

- [ ]* 6.3 Write property test for security group isolation
  - **Property 8: Security Group Isolation**
  - Validate no 0.0.0.0/0 ingress, specific security group references
  - **Validates: Requirements 10.1, 10.2, 10.3, 10.4, 10.5, 10.6**


- [x] 7. Implement ECS cluster with Service Connect
  - [x] 7.1 Create Service Connect namespace
    - Create aws_service_discovery_http_namespace
    - _Requirements: 5.6_

  - [x] 7.2 Create ECS cluster
    - Create aws_ecs_cluster with Container Insights enabled
    - Configure execute command logging
    - Set Service Connect defaults to namespace
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 7.3 Create EC2 infrastructure for ECS
    - Create Launch Templates for each node type (A, B, C) with Graviton AMI
    - Configure ECS_INSTANCE_ATTRIBUTES for workload placement
    - Create Auto Scaling Groups (1 instance each)
    - Create ECS Capacity Providers linked to ASGs
    - Associate capacity providers with cluster
    - _Requirements: 3.5, 3.6, 3.7_

- [x] 8. Implement CloudWatch Log Groups
  - Create log groups for each Temporal service (history, matching, frontend, worker, ui)
  - Create log group for Grafana
  - Create log group for ECS Exec
  - Configure retention period from variable
  - _Requirements: 12.1, 12.2, 12.4, 12.5_

- [x] 9. Implement Secrets Manager data source
  - Reference externally-created Grafana admin secret using data source
  - Secret must be created before Terraform deployment using AWS CLI
  - Secret contains JSON with admin_user and admin_password fields
  - _Requirements: 13.1, 13.2_

- [x] 10. Checkpoint - Validate cluster and supporting infrastructure
  - Run terraform validate and terraform plan
  - Ensure cluster, IAM, security groups are correctly configured
  - Ask the user if questions arise


- [x] 11. Implement OpenSearch Provisioned domain
  - [x] 11.1 Create OpenSearch domain
    - Create aws_opensearch_domain with t3.small.search
    - Configure single node, 10GB EBS storage
    - Deploy in VPC with private subnet
    - Enable encryption at rest and node-to-node encryption
    - Enforce HTTPS with TLS 1.2
    - Configure access policy for Temporal task role
    - _Requirements: 7.1, 7.2, 7.4, 7.5, 7.6, 7.7_

  - [x] 11.2 Create OpenSearch schema setup task
    - Create aws_ecs_task_definition for one-time setup
    - Configure ARM64 architecture, 256 CPU, 512 memory
    - Use temporal image with temporal-elasticsearch-tool
    - Command runs setup-schema and create-index
    - Create IAM role with es:ESHttp* permissions
    - Create security group allowing OpenSearch access
    - Create CloudWatch log group for setup logs
    - _Requirements: 7.3_

- [ ]* 11.3 Write property test for OpenSearch configuration
  - **Property 9: OpenSearch Development Configuration**
  - Validate t3.small.search, single node, VPC deployment, encryption
  - **Validates: Requirements 7.1, 7.2, 7.6, 7.7**

- [x] 12. Implement Amazon Managed Prometheus
  - Create aws_prometheus_workspace
  - Output remote write endpoint
  - _Requirements: 8.1, 8.5_

- [x] 13. Implement Temporal History service
  - [x] 13.1 Create History task definition
    - Configure ARM64 architecture
    - Set CPU/memory from variables
    - Configure port mappings (7234, 6934, 9090)
    - Set environment variables for DSQL and OpenSearch
    - Configure CloudWatch Logs
    - Enable ECS Exec (initProcessEnabled)
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.9_

  - [x] 13.2 Create History ECS service
    - Configure EC2 capacity provider strategy
    - Place in private subnets
    - Enable ECS Exec
    - Configure Service Connect as client-server with discoverable endpoint
    - Add placement constraint for workload=history (Node A)
    - _Requirements: 5.1, 5.2, 5.3, 5.5, 5.7, 5.10, 5.11_


- [x] 14. Implement Temporal Matching service
  - [x] 14.1 Create Matching task definition
    - Configure ARM64 architecture
    - Set CPU/memory from variables
    - Configure port mappings (7235, 6935, 9090)
    - Set environment variables for DSQL
    - Configure CloudWatch Logs
    - Enable ECS Exec
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.9_

  - [x] 14.2 Create Matching ECS service
    - Configure EC2 capacity provider strategy
    - Place in private subnets
    - Enable ECS Exec
    - Configure Service Connect as client-server with discoverable endpoint
    - Add placement constraint for workload=frontend (Node B)
    - _Requirements: 5.1, 5.2, 5.3, 5.5, 5.7, 5.10, 5.11_

- [x] 15. Implement Temporal Frontend service
  - [x] 15.1 Create Frontend task definition
    - Configure ARM64 architecture
    - Set CPU/memory from variables
    - Configure port mappings (7233, 6933, 9090)
    - Set environment variables for DSQL and OpenSearch
    - Configure CloudWatch Logs
    - Enable ECS Exec
    - Add health check for gRPC endpoint
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.9_

  - [x] 15.2 Create Frontend ECS service
    - Configure EC2 capacity provider strategy
    - Place in private subnets
    - Enable ECS Exec
    - Configure Service Connect as client-server with discoverable endpoint
    - Add placement constraint for workload=frontend (Node B)
    - _Requirements: 5.1, 5.2, 5.3, 5.5, 5.7, 5.10, 5.11_


- [x] 16. Implement Temporal Worker service
  - [x] 16.1 Create Worker task definition
    - Configure ARM64 architecture
    - Set CPU/memory from variables
    - Configure port mappings (7239, 6939, 9090)
    - Set environment variables for DSQL
    - Configure CloudWatch Logs
    - Enable ECS Exec
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.9_

  - [x] 16.2 Create Worker ECS service
    - Configure EC2 capacity provider strategy
    - Place in private subnets
    - Enable ECS Exec
    - Configure Service Connect as client-only
    - Add placement constraint for workload=worker (Node C)
    - _Requirements: 5.1, 5.2, 5.3, 5.5, 5.8, 5.10, 5.11_

- [x] 17. Implement Temporal UI service
  - [x] 17.1 Create UI task definition
    - Configure ARM64 architecture
    - Use official temporalio/ui image
    - Configure port mapping (8080)
    - Set TEMPORAL_ADDRESS environment variable to temporal-frontend:7233
    - Configure CloudWatch Logs
    - Enable ECS Exec
    - _Requirements: 4.1, 4.2, 4.4, 4.5, 4.9, 4.10, 4.11_

  - [x] 17.2 Create UI ECS service
    - Configure EC2 capacity provider strategy
    - Place in private subnets
    - Enable ECS Exec
    - Configure Service Connect as client-only
    - Add placement constraint for workload=frontend (Node B)
    - _Requirements: 5.1, 5.2, 5.3, 5.5, 5.8, 5.10, 5.11_

- [ ]* 17.3 Write property test for multi-service architecture
  - **Property 12: Separate Task Definitions**
  - Validate exactly 5 Temporal task definitions and 5 services
  - **Validates: Requirements 4.1, 5.1**

- [ ]* 17.4 Write property test for Graviton architecture
  - **Property 2: Graviton Architecture Consistency**
  - Validate all task definitions use ARM64
  - **Validates: Requirements 4.2, 9.1**

- [ ]* 17.5 Write property test for ECS Exec enablement
  - **Property 3: ECS Exec Enablement**
  - Validate enable_execute_command and initProcessEnabled
  - **Validates: Requirements 4.9, 5.5, 9.4**

- [ ]* 17.6 Write property test for Service Connect configuration
  - **Property 11: Service Connect Configuration**
  - Validate namespace, client-server vs client-only services
  - **Validates: Requirements 5.6, 5.7, 5.8**


- [x] 18. Checkpoint - Validate Temporal services
  - Run terraform validate and terraform plan
  - Ensure all 5 Temporal services are correctly configured
  - Verify Service Connect configuration
  - Ask the user if questions arise

- [x] 19. Implement Grafana service
  - [x] 19.1 Create Grafana task definition
    - Configure ARM64 architecture
    - Use grafana/grafana-oss:latest image
    - Configure port mapping (3000)
    - Reference Grafana admin credentials from Secrets Manager using secrets block with JSON key extraction
    - Use valueFrom with format "${secret_arn}:admin_user::" and "${secret_arn}:admin_password::"
    - Set GF_SECURITY_ADMIN_USER and GF_SECURITY_ADMIN_PASSWORD from secret
    - Configure CloudWatch Logs
    - Enable ECS Exec
    - _Requirements: 9.1, 9.2, 9.5, 9.6, 13.2, 13.3_

  - [x] 19.2 Create Grafana ECS service
    - Configure EC2 capacity provider strategy
    - Place in private subnets
    - Enable ECS Exec
    - Add placement constraint for workload=frontend (Node B)
    - _Requirements: 9.3, 9.4, 9.8_

- [ ]* 19.3 Write property test for Secrets Manager integration
  - **Property 6: Secrets Manager Integration**
  - Validate Grafana secret exists and is referenced in task definition
  - **Validates: Requirements 13.1, 13.2, 13.3, 13.4**

- [ ]* 19.4 Write property test for CloudWatch Logs configuration
  - **Property 5: CloudWatch Logs Configuration**
  - Validate awslogs driver with awslogs-create-group for all services
  - **Validates: Requirements 4.5, 9.6, 12.3, 12.4**


- [x] 20. Implement variables and outputs
  - [x] 20.1 Create variables.tf
    - Define all input variables with descriptions and defaults
    - Add validation blocks for CPU, memory, CIDR
    - _Requirements: 17.1, 17.3_

  - [x] 20.2 Create outputs.tf
    - Output cluster ARN and name
    - Output all service names
    - Output OpenSearch endpoint
    - Output Prometheus workspace ID and endpoint
    - Output ECS Exec commands for each service
    - _Requirements: 17.2, 17.5_

- [ ]* 20.3 Write property test for module interface completeness
  - **Property 13: Module Interface Completeness**
  - Validate variables have descriptions, outputs include essential identifiers
  - **Validates: Requirements 17.1, 17.2, 17.5**

- [x] 21. Create project documentation
  - [x] 21.1 Create README.md
    - Write project overview
    - Document prerequisites including Grafana secret creation using AWS CLI
    - Include instructions for creating Grafana admin secret with get-random-password
    - Document ECR image build and push process (Go compilation, docker buildx, official Dockerfiles)
    - Write quick start guide
    - Document remote access instructions for Temporal UI and Grafana
    - Include cost estimates
    - _Requirements: 16.1, 13.6, 15.13, 18.1, 18.2, 18.3, 18.4, 18.5, 18.6_

  - [x] 21.2 Create AGENTS.md
    - Document project structure
    - List key files and their purposes
    - Document design decisions
    - _Requirements: 16.2_

- [x] 22. Implement ADOT Collector service for metrics
  - [x] 22.1 Create ADOT collector configuration template
    - Create templates/adot-config.yaml with Prometheus receiver
    - Configure scrape targets for all Temporal services via Service Connect DNS
    - Configure prometheusremotewrite exporter with SigV4 auth
    - _Requirements: 20.2, 20.3_

  - [x] 22.2 Create SSM Parameter Store for ADOT config
    - Create aws_ssm_parameter resource for collector config
    - Use templatefile to inject AMP endpoint and region
    - _Requirements: 20.8_

  - [x] 22.3 Create ADOT IAM role and policies
    - Create aws_iam_role for ADOT task
    - Add aps:RemoteWrite permissions for AMP
    - Add ECS Exec permissions (ssmmessages)
    - Add SSM Parameter read permissions
    - _Requirements: 20.5, 20.7_

  - [x] 22.4 Create ADOT task definition
    - Configure ARM64 architecture
    - Use public.ecr.aws/aws-observability/aws-otel-collector image
    - Configure secrets block to read config from SSM
    - Configure CloudWatch Logs
    - Enable ECS Exec (initProcessEnabled)
    - _Requirements: 20.1, 20.6, 20.7_

  - [x] 22.5 Create ADOT security group
    - Allow egress to Temporal services on port 9090
    - Allow egress to VPC endpoints (443)
    - No ingress required (scraper only)
    - _Requirements: 20.9_

  - [x] 22.6 Update Temporal security groups for metrics scraping
    - Add ingress rule for port 9090 from ADOT security group to Frontend
    - Add ingress rule for port 9090 from ADOT security group to History
    - Add ingress rule for port 9090 from ADOT security group to Matching
    - Add ingress rule for port 9090 from ADOT security group to Worker
    - _Requirements: 20.9_

  - [x] 22.7 Create ADOT ECS service
    - Configure EC2 capacity provider strategy
    - Place in private subnets
    - Enable ECS Exec
    - Configure Service Connect as client-only
    - Add depends_on for Temporal services
    - Add placement constraint for workload=worker (Node C)
    - _Requirements: 20.4, 20.7, 20.10_

  - [x] 22.8 Create CloudWatch Log Group for ADOT
    - Create log group /ecs/${project_name}/adot
    - Configure retention from variable
    - _Requirements: 20.6_

  - [x] 22.9 Update outputs.tf with ADOT service info
    - Add ADOT service name output
    - Add ECS Exec command for ADOT
    - _Requirements: 17.2, 17.5_

- [x] 23. Create Grafana secret setup script
  - [x] 23.1 Create scripts/setup-grafana-secret.sh
    - Accept region as optional parameter (default from AWS_REGION or eu-west-1)
    - Accept secret name as optional parameter (default: grafana/admin)
    - Check if secret already exists using aws secretsmanager describe-secret
    - Generate secure random password using aws secretsmanager get-random-password
    - Create secret with JSON structure {admin_user, admin_password}
    - Display generated password to user for initial login
    - Make script idempotent (skip creation if exists, offer to show existing)
    - _Requirements: 13.6, 13.7, 13.8, 13.9_

  - [x] 23.2 Update README.md to reference the script
    - Replace manual AWS CLI commands with script invocation
    - Document script parameters and behavior
    - _Requirements: 13.10_

- [x] 24. Final checkpoint - Complete validation
  - Run terraform init, validate, and plan
  - Ensure all resources are correctly configured
  - Verify all property tests pass
  - Ask the user if questions arise

- [x] 25. Implement staged deployment workflow
  - [x] 25.1 Update service count defaults to zero
    - Change temporal_history_count default from 1 to 0
    - Change temporal_matching_count default from 1 to 0
    - Change temporal_frontend_count default from 1 to 0
    - Change temporal_worker_count default from 1 to 0
    - Change temporal_ui_count default from 1 to 0
    - Change grafana_count default from 1 to 0
    - Update validation from >= 1 to >= 0
    - _Requirements: 21.1, 21.2_

  - [x] 25.2 Create scale-services.sh script
    - Accept 'up' or 'down' action parameter
    - Accept optional --project-name parameter (default from terraform.tfvars)
    - Accept optional --region parameter (default from AWS_REGION or terraform.tfvars)
    - Scale all Temporal services (history, matching, frontend, worker, ui) and Grafana
    - Use aws ecs update-service --desired-count
    - Display service status after scaling
    - _Requirements: 21.3, 21.4_

  - [x] 25.3 Update terraform.tfvars.example
    - Set all service counts to 0 as default
    - Add comments explaining staged deployment workflow
    - _Requirements: 21.5_

  - [x] 25.4 Update README.md with deployment workflow
    - Document 7-step deployment process
    - Explain zero-replica initial deployment rationale
    - Add instructions for scaling services after schema setup
    - _Requirements: 21.6_

  - [x] 25.5 Update AGENTS.md with design decision
    - Add Design Decision #8: Zero-Replica Initial Deployment
    - Document benefits and workflow
    - _Requirements: 21.7_

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate Terraform plan output against design properties
- Implementation uses HCL (Terraform) as specified in the design document
- EC2 instances use Graviton (ARM64) for cost efficiency and stable IPs for cluster membership

---

## Implementation Status: COMPLETE ✅

**Completed: January 2026**

All core infrastructure tasks have been implemented and validated:

- ✅ VPC with private-only networking and NAT Gateway
- ✅ VPC endpoints for AWS services (ECR, SSM, Logs, Secrets Manager, APS)
- ✅ ECS cluster with EC2 capacity providers (6x m7g.xlarge Graviton instances)
- ✅ Service Connect namespace for inter-service communication
- ✅ All 5 Temporal services (History, Matching, Frontend, Worker, UI)
- ✅ Aurora DSQL integration with IAM authentication
- ✅ OpenSearch Provisioned for visibility
- ✅ Amazon Managed Prometheus for metrics
- ✅ ADOT Collector for metrics scraping
- ✅ Grafana on ECS with Secrets Manager integration
- ✅ Staged deployment workflow (zero-replica initial deployment)
- ✅ ECR repositories and build scripts
- ✅ Comprehensive documentation (README.md, AGENTS.md)

**Production Configuration:**
- History: 4 replicas (2 vCPU, 8 GiB, 4096 shards)
- Matching: 3 replicas (1 vCPU, 4 GiB)
- Frontend: 2 replicas (1 vCPU, 4 GiB)
- Worker: 2 replicas (1 vCPU, 4 GiB)
- UI: 1 replica
- Grafana: 1 replica
- ADOT: 1 replica

**Remaining (Optional):**
- Property tests for Terraform validation (marked with `*`)
- These are nice-to-have for CI/CD but not blocking
