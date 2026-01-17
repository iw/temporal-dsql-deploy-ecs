# Requirements Document

## Introduction

This document defines the requirements for deploying a custom Temporal image to AWS ECS on EC2 using Infrastructure as Code (Terraform). This represents a minimal development deployment with private-only access, using Aurora DSQL for persistence, OpenSearch Provisioned for visibility, Amazon Managed Prometheus for metrics, and Grafana on ECS for dashboards.

## AWS Documentation References

- [Amazon ECS on Amazon EC2](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/getting-started-ecs-ec2.html)
- [ECS Service Connect](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html)
- [Working with 64-bit ARM workloads on Amazon ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-arm64.html)
- [Amazon ECS interface VPC endpoints (AWS PrivateLink)](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/vpc-endpoints.html)
- [Best practices for connecting Amazon ECS services in a VPC](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/networking-connecting-services.html)
- [Aurora DSQL Authentication and Authorization](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/authentication-authorization.html)
- [Security best practices for Amazon Aurora DSQL](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/best-practices-security.html)
- [Amazon OpenSearch Service](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/what-is.html)
- [Amazon Managed Service for Prometheus](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html)
- [Using ECS Exec for debugging](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)
- [Amazon ECS capacity providers](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-capacity-providers.html)

## Glossary

- **Temporal**: An open-source workflow orchestration platform for building reliable distributed applications
- **Temporal_History**: Temporal service responsible for maintaining workflow execution state and history
- **Temporal_Matching**: Temporal service responsible for matching workflow tasks to workers
- **Temporal_Frontend**: Temporal service providing the gRPC API gateway for client connections
- **Temporal_Worker**: Temporal internal service for system workflows and background tasks
- **Temporal_UI**: Web-based user interface for viewing and managing Temporal workflows
- **ECS_EC2**: AWS Elastic Container Service with EC2 launch type, providing container compute on managed EC2 instances
- **Custom_Image**: A Docker container image containing Temporal server with custom configurations
- **Terraform**: Infrastructure as Code tool for provisioning and managing cloud resources
- **VPC**: Virtual Private Cloud, an isolated network environment in AWS
- **DSQL**: Amazon Aurora DSQL, a serverless distributed SQL database with IAM-only authentication
- **OpenSearch_Provisioned**: Amazon OpenSearch Service with provisioned capacity for Temporal visibility (required for Temporal compatibility)
- **AMP**: Amazon Managed Service for Prometheus for metrics collection
- **Grafana**: Open-source analytics and monitoring platform deployed on ECS
- **ECS_Exec**: AWS feature enabling interactive shell access to running containers via SSM
- **Graviton**: AWS ARM-based processors (Graviton3) offering up to 40% better price-performance than x86
- **VPC_Endpoint**: Private connectivity to AWS services via AWS PrivateLink without internet gateway
- **Task_Definition**: ECS configuration specifying container settings, resources, and networking
- **Service**: ECS construct that maintains desired count of running tasks
- **Security_Group**: AWS firewall rules controlling inbound and outbound traffic
- **Secrets_Manager**: AWS service for securely storing and retrieving secrets
- **Service_Connect**: AWS ECS feature providing service mesh capabilities with automatic Envoy sidecar proxy for faster failover and service discovery (recommended over Cloud Map DNS-based discovery)
- **Port_Forwarding**: Technique to tunnel remote service ports to local machine via SSM Session Manager
- **ECR**: Amazon Elastic Container Registry, a fully managed Docker container registry for storing and deploying container images
- **ADOT**: AWS Distro for OpenTelemetry, an AWS-supported distribution of the OpenTelemetry project for collecting metrics, traces, and logs

## Requirements

### Requirement 1: VPC and Network Infrastructure

**User Story:** As a DevOps engineer, I want a properly configured VPC with private subnets only, so that Temporal services can be deployed securely without public internet exposure.

**Reference:** [Best practices for connecting Amazon ECS to AWS services from inside your VPC](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/networking-connecting-vpc.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create a VPC with configurable CIDR block
2. THE Terraform_Module SHALL create private subnets across multiple availability zones for all services
3. THE Terraform_Module SHALL NOT create public subnets or internet-facing resources
4. THE Terraform_Module SHALL configure a single NAT Gateway for private subnet outbound internet access (development cost optimization)
5. THE Terraform_Module SHALL create appropriate route tables for private subnets

### Requirement 2: VPC Endpoints

**User Story:** As a DevOps engineer, I want VPC endpoints for AWS services, so that traffic stays within the AWS network and reduces NAT Gateway costs.

**Reference:** [Amazon ECS interface VPC endpoints (AWS PrivateLink)](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/vpc-endpoints.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create VPC endpoints for ECR API and ECR Docker registry (com.amazonaws.region.ecr.api, com.amazonaws.region.ecr.dkr)
2. THE Terraform_Module SHALL create VPC endpoint for CloudWatch Logs (com.amazonaws.region.logs)
3. THE Terraform_Module SHALL create VPC endpoints for SSM, SSM Messages, and EC2 Messages for ECS Exec (com.amazonaws.region.ssm, com.amazonaws.region.ssmmessages, com.amazonaws.region.ec2messages)
4. THE Terraform_Module SHALL create VPC endpoint for S3 (gateway type) for ECR layer storage
5. THE Terraform_Module SHALL create VPC endpoint for Amazon Managed Prometheus (com.amazonaws.region.aps-workspaces)
6. THE Terraform_Module SHALL create VPC endpoint for Secrets Manager (com.amazonaws.region.secretsmanager)
7. THE Terraform_Module SHALL configure security groups for VPC endpoints allowing HTTPS (443) traffic from ECS tasks

### Requirement 3: ECS Cluster Configuration

**User Story:** As a DevOps engineer, I want an ECS cluster configured with EC2 capacity providers using Graviton instances, so that I can run containers with stable IPs for cluster membership and better cost efficiency.

**Reference:** [Amazon ECS clusters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/clusters.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create an ECS cluster with EC2 capacity providers linked to Auto Scaling Groups
2. THE Terraform_Module SHALL enable Container Insights for monitoring and logging
3. THE Terraform_Module SHALL configure cluster settings with appropriate naming conventions using project_name variable
4. THE Terraform_Module SHALL configure execute command logging for ECS Exec audit trail
5. THE Terraform_Module SHALL create Launch Templates for Graviton (ARM64) EC2 instances with ECS-optimized AMI
6. THE Terraform_Module SHALL create Auto Scaling Groups with workload-specific instance attributes for placement constraints
7. THE Terraform_Module SHALL configure three node types with custom ECS_INSTANCE_ATTRIBUTES for workload placement

### Requirement 4: Temporal Service Task Definitions

**User Story:** As a DevOps engineer, I want separate task definitions for each Temporal service component using Graviton, so that ECS runs Temporal services independently with proper resource allocation.

**Reference:** [Amazon ECS task definitions for 64-bit ARM workloads](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-arm64.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create separate task definitions for each Temporal service: History, Matching, Frontend, Worker, and UI
2. THE Terraform_Module SHALL configure all task definitions for ARM64 (Graviton) architecture with EC2 compatibility
3. THE Terraform_Module SHALL configure CPU and memory allocations as input variables for each service with sensible defaults
4. THE Terraform_Module SHALL define container port mappings for each service: History (7234, 6934), Matching (7235, 6935), Frontend (7233, 6933), Worker (7239, 6939), UI (8080)
5. THE Terraform_Module SHALL configure CloudWatch Logs using awslogs log driver with awslogs-create-group enabled for each service
6. THE Terraform_Module SHALL support environment variables for DSQL connection configuration on History, Matching, Frontend, and Worker services
7. THE Terraform_Module SHALL support environment variables for OpenSearch Provisioned connection configuration on History, Matching, Frontend, and Worker services
8. THE Terraform_Module SHALL create an IAM task execution role with permissions for ECR image pull and CloudWatch logging
9. THE Terraform_Module SHALL enable ECS Exec on all task definitions by setting initProcessEnabled to true in linuxParameters
10. THE Terraform_Module SHALL configure the UI task definition to reference the official Temporal UI image (temporalio/ui)
11. THE Terraform_Module SHALL configure the UI task definition with TEMPORAL_ADDRESS environment variable pointing to Frontend service via Service Connect

### Requirement 5: ECS Services for Temporal Components

**User Story:** As a DevOps engineer, I want separate ECS services for each Temporal component in private subnets, so that Temporal runs as a distributed system without public exposure.

**Reference:** [Use Service Connect to connect Amazon ECS services with short names](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create separate ECS services for History, Matching, Frontend, Worker, and UI
2. THE Terraform_Module SHALL configure all services to use EC2 capacity provider strategy with workload-specific placement constraints
3. THE Terraform_Module SHALL configure service networking to place all tasks in private subnets only
4. THE Terraform_Module SHALL NOT configure any load balancer or public endpoint for any service
5. THE Terraform_Module SHALL enable ECS Exec on all services by setting enable_execute_command = true
6. THE Terraform_Module SHALL configure ECS Service Connect namespace for internal service communication with automatic Envoy sidecar proxy
7. THE Terraform_Module SHALL configure Service Connect client-server services for History, Matching, and Frontend with discoverable endpoints
8. THE Terraform_Module SHALL configure Service Connect client-only services for Worker and UI
9. THE Terraform_Module SHALL configure each service with configurable desired task count (default: 0 for staged deployment)
10. THE Terraform_Module SHALL configure health checks for services to enable proper startup ordering
11. THE Terraform_Module SHALL configure placement constraints to assign services to specific node types (History→Node A, Frontend/Matching/UI/Grafana→Node B, Worker/ADOT→Node C)

### Requirement 6: Aurora DSQL Integration

**User Story:** As a DevOps engineer, I want Temporal configured to use Aurora DSQL for persistence, so that workflow state is stored in a serverless distributed database.

**Reference:** [Authentication and authorization for Aurora DSQL](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/authentication-authorization.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL accept DSQL cluster endpoint as an input variable (DSQL cluster created externally)
2. THE Terraform_Module SHALL accept DSQL cluster ARN as an input variable for IAM policy configuration
3. THE Terraform_Module SHALL configure Temporal environment variables for DSQL connection (POSTGRES_SEEDS, DB_PORT)
4. THE Terraform_Module SHALL create security group rules allowing Temporal tasks to connect to DSQL on port 5432
5. THE Terraform_Module SHALL configure IAM policy with dsql:DbConnect and dsql:DbConnectAdmin actions for DSQL access

### Requirement 7: OpenSearch Provisioned for Visibility

**User Story:** As a DevOps engineer, I want OpenSearch Provisioned configured for Temporal visibility, so that workflow search and visibility features work correctly.

**Reference:** [Amazon OpenSearch Service](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/what-is.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create an OpenSearch Provisioned domain in the VPC
2. THE Terraform_Module SHALL configure OpenSearch with development-oriented capacity (single t3.small.search node, 10GB EBS storage)
3. THE Terraform_Module SHALL create a one-time ECS task definition for OpenSearch schema setup using temporal-elasticsearch-tool
4. THE Terraform_Module SHALL configure Temporal environment variables for OpenSearch connection (ES_SEEDS, ES_PORT, ES_SCHEME) with awsRequestSigning enabled
5. THE Terraform_Module SHALL create security group rules allowing Temporal tasks to connect to OpenSearch on port 443
6. THE Terraform_Module SHALL configure OpenSearch access policies for Temporal service IAM role and schema setup task role
7. THE Terraform_Module SHALL enable encryption at rest and node-to-node encryption
8. THE Terraform_Module SHALL enforce HTTPS with TLS 1.2 minimum

### Requirement 8: Amazon Managed Prometheus Configuration

**User Story:** As a DevOps engineer, I want Amazon Managed Prometheus collecting Temporal metrics with simple IAM access, so that metrics are available without complex authentication.

**Reference:** [Amazon Managed Service for Prometheus](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create an Amazon Managed Prometheus workspace
2. THE Terraform_Module SHALL configure IAM-based access to the Prometheus workspace using task role
3. THE Terraform_Module SHALL configure Temporal services to expose Prometheus metrics endpoint on port 9090
4. THE Terraform_Module SHALL create IAM policies allowing aps:RemoteWrite, aps:GetSeries, aps:GetLabels, aps:GetMetricMetadata actions
5. THE Terraform_Module SHALL output the Prometheus remote write endpoint for metrics collection configuration

### Requirement 20: ADOT Collector Service for Metrics

**User Story:** As a DevOps engineer, I want AWS Distro for OpenTelemetry (ADOT) deployed as a dedicated ECS service to scrape Temporal metrics and remote write to Amazon Managed Prometheus, so that metrics are collected centrally without sidecars.

**Reference:** [AWS Distro for OpenTelemetry](https://aws-otel.github.io/docs/introduction)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create a task definition for ADOT Collector using ARM64 (Graviton) architecture with EC2 compatibility
2. THE Terraform_Module SHALL configure ADOT Collector to scrape Prometheus metrics from all Temporal services via Service Connect DNS names (temporal-frontend:9090, temporal-history:9090, temporal-matching:9090, temporal-worker:9090)
3. THE Terraform_Module SHALL configure ADOT Collector to remote write metrics to the Amazon Managed Prometheus workspace using AWS SigV4 authentication
4. THE Terraform_Module SHALL deploy ADOT Collector as a client-only Service Connect service in private subnets using EC2 capacity provider
5. THE Terraform_Module SHALL create an IAM task role for ADOT with aps:RemoteWrite permissions
6. THE Terraform_Module SHALL configure CloudWatch Logs for ADOT Collector container logging
7. THE Terraform_Module SHALL enable ECS Exec for ADOT Collector container access
8. THE Terraform_Module SHALL store the ADOT collector configuration in SSM Parameter Store for easy updates
9. THE Terraform_Module SHALL create security group rules allowing ADOT to connect to Temporal services on port 9090
10. THE Terraform_Module SHALL configure ADOT placement constraint to run on Node C (workload=worker)

### Requirement 9: Grafana on ECS

**User Story:** As a DevOps engineer, I want Grafana deployed on ECS with simple access via ECS Exec, so that I can view metrics dashboards without public exposure.

**Reference:** [Using ECS Exec for debugging](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create a task definition for Grafana using ARM64 (Graviton) architecture with EC2 compatibility
2. THE Terraform_Module SHALL configure Grafana to use Amazon Managed Prometheus as data source via environment variables
3. THE Terraform_Module SHALL deploy Grafana in private subnets using EC2 capacity provider
4. THE Terraform_Module SHALL enable ECS Exec for Grafana container access
5. THE Terraform_Module SHALL configure Grafana with admin user credentials from Secrets Manager
6. THE Terraform_Module SHALL configure CloudWatch Logs for Grafana container logging
7. THE Terraform_Module SHALL create IAM policy for Grafana task role to query Amazon Managed Prometheus
8. THE Terraform_Module SHALL configure Grafana placement constraint to run on Node B (workload=frontend)

### Requirement 10: Security Configuration

**User Story:** As a DevOps engineer, I want properly configured security groups with no public ingress, so that all services are protected from internet access.

#### Acceptance Criteria

1. THE Terraform_Module SHALL create security groups for each service (Temporal History, Temporal Matching, Temporal Frontend, Temporal Worker, Temporal UI, Grafana)
2. THE Terraform_Module SHALL NOT allow any inbound traffic from the internet (0.0.0.0/0) on any security group
3. THE Terraform_Module SHALL configure security groups to allow inter-service communication: Frontend to History (7234), Frontend to Matching (7235), Worker to Frontend (7233), UI to Frontend (7233)
4. THE Terraform_Module SHALL configure security groups to allow Temporal membership ports for cluster communication (6933, 6934, 6935, 6939)
5. THE Terraform_Module SHALL configure outbound rules to allow HTTPS (443) egress for AWS service access
6. THE Terraform_Module SHALL create security group for VPC endpoints allowing HTTPS from VPC CIDR

### Requirement 11: IAM Roles and Policies

**User Story:** As a DevOps engineer, I want IAM roles with least-privilege permissions including ECS Exec support, so that services can access required AWS resources securely.

**Reference:** [Security best practices for Amazon Aurora DSQL](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/best-practices-security.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create a task execution role for ECS agent operations with AmazonECSTaskExecutionRolePolicy
2. THE Terraform_Module SHALL attach policies for ECR image pull and CloudWatch Logs access to the execution role
3. THE Terraform_Module SHALL create a task role for Temporal services with ECS Exec permissions (ssmmessages:CreateControlChannel, ssmmessages:CreateDataChannel, ssmmessages:OpenControlChannel, ssmmessages:OpenDataChannel)
4. THE Terraform_Module SHALL create IAM policies for DSQL authentication (dsql:DbConnect, dsql:DbConnectAdmin)
5. THE Terraform_Module SHALL create IAM policies for Amazon Managed Prometheus access (aps:RemoteWrite, aps:GetSeries, aps:GetLabels, aps:GetMetricMetadata)
6. THE Terraform_Module SHALL create IAM policies for OpenSearch access (es:ESHttp*)
7. THE Terraform_Module SHALL create separate task role for Grafana with Prometheus query permissions

### Requirement 12: CloudWatch Logs Configuration

**User Story:** As a DevOps engineer, I want CloudWatch Logs configured with the latest ECS log publishing methods, so that container logs are captured efficiently.

#### Acceptance Criteria

1. THE Terraform_Module SHALL create CloudWatch Log Groups for each Temporal service (History, Matching, Frontend, Worker, UI) and Grafana
2. THE Terraform_Module SHALL configure log retention period as an input variable (default: 7 days for development)
3. THE Terraform_Module SHALL use awslogs log driver with awslogs-create-group enabled
4. THE Terraform_Module SHALL configure log stream prefixes for each service (temporal-history, temporal-matching, temporal-frontend, temporal-worker, temporal-ui, grafana)
5. THE Terraform_Module SHALL create CloudWatch Log Group for ECS Exec session logging

### Requirement 13: Secrets Manager Integration

**User Story:** As a DevOps engineer, I want secrets stored in AWS Secrets Manager and referenced by Terraform, so that sensitive configuration is managed securely without storing secrets in Terraform state.

#### Acceptance Criteria

1. THE Grafana_Admin_Secret SHALL be created externally in Secrets Manager before Terraform deployment with JSON structure containing admin_user and admin_password fields
2. THE Terraform_Module SHALL reference the externally-created Grafana admin secret using a data source (not create it)
3. THE Terraform_Module SHALL configure ECS task definitions to retrieve secrets from Secrets Manager using secrets block with JSON key extraction (e.g., valueFrom = "${secret_arn}:admin_password::")
4. THE Terraform_Module SHALL create IAM policies allowing task execution role to read secrets (secretsmanager:GetSecretValue)
5. THE Terraform_Module SHALL NOT store DSQL credentials in Secrets Manager as DSQL uses IAM authentication exclusively
6. THE Setup_Script SHALL generate a secure random password using AWS Secrets Manager get-random-password API
7. THE Setup_Script SHALL create the Grafana admin secret in Secrets Manager with JSON structure containing admin_user and admin_password
8. THE Setup_Script SHALL be idempotent, checking if the secret already exists before creating
9. THE Setup_Script SHALL display the generated password to the user for initial login
10. THE Documentation SHALL reference the setup script for creating the Grafana admin secret

### Requirement 15: ECR Repository and Image Management

**User Story:** As a DevOps engineer, I want ECR repositories created by Terraform and a script to build and push the custom Temporal DSQL images following the official build process, so that ECS can pull the container images from a private registry.

**Reference:** [Amazon ECR private repositories](https://docs.aws.amazon.com/AmazonECR/latest/userguide/Repositories.html)

#### Acceptance Criteria

1. THE Terraform_Module SHALL create ECR private repositories for temporal-dsql server and admin-tools images
2. THE Terraform_Module SHALL configure ECR repositories with image scanning on push enabled
3. THE Terraform_Module SHALL configure ECR lifecycle policy to retain only the last 10 untagged images (cost optimization)
4. THE Terraform_Module SHALL output the ECR repository URLs for use in build scripts
5. THE Build_Script SHALL compile Go binaries for ARM64 using the temporal-dsql Makefile targets (temporal-server, temporal-sql-tool, temporal-elasticsearch-tool, temporal-dsql-tool, tdbg)
6. THE Build_Script SHALL build Docker images using the official Dockerfiles from temporal-dsql/docker/targets/ (server.Dockerfile, admin-tools.Dockerfile)
7. THE Build_Script SHALL use docker buildx for ARM64 cross-compilation
8. THE Build_Script SHALL authenticate with ECR and push images to the repositories
9. THE Build_Script SHALL accept the path to the temporal-dsql source repository as a parameter
10. THE Build_Script SHALL tag images with both 'latest' and a git-sha-timestamp version tag
11. THE Build_Script SHALL download Temporal CLI for inclusion in the admin-tools image
12. THE Terraform_Module SHALL reference the ECR repository URL in Temporal service task definitions
13. THE Documentation SHALL include instructions for building and pushing the custom Temporal DSQL images

### Requirement 14: Cost Estimation

**User Story:** As a DevOps engineer, I want cost estimates for the deployment, so that I can understand the financial impact of running this infrastructure.

#### Acceptance Criteria

1. THE Documentation SHALL include hourly cost estimates for all resources
2. THE Documentation SHALL include daily (8-hour) cost estimates for development usage
3. THE Cost_Estimate SHALL itemize costs for: VPC, EC2 instances (3x m7g.large), NAT Gateway, OpenSearch Provisioned, VPC endpoints, CloudWatch Logs, Secrets Manager, and Amazon Managed Prometheus
4. THE Cost_Estimate SHALL be based on eu-west-1 pricing as reference
5. THE Cost_Estimate SHALL note that Graviton provides approximately 20-40% cost savings over x86

### Requirement 16: Project Documentation

**User Story:** As a DevOps engineer, I want comprehensive project documentation, so that the repository is well-documented for contributors and users.

#### Acceptance Criteria

1. THE Project SHALL include a README.md with project overview, prerequisites, usage instructions, and cost estimates
2. THE Project SHALL include an AGENTS.md document describing the project structure for AI coding assistants
3. THE Project SHALL include a .gitignore file appropriate for Terraform projects
4. THE Project SHALL include a terraform.tfvars.example file with all configurable variables

### Requirement 17: Terraform Module Interface

**User Story:** As a DevOps engineer, I want a well-documented Terraform module with clear inputs and outputs, so that I can easily integrate and customize the deployment.

#### Acceptance Criteria

1. THE Terraform_Module SHALL expose input variables for all configurable parameters with descriptions and defaults
2. THE Terraform_Module SHALL output essential resource identifiers (cluster ARN, service ARNs, OpenSearch endpoint, Prometheus endpoint)
3. THE Terraform_Module SHALL include validation for required input variables using variable validation blocks
4. THE Terraform_Module SHALL organize resources into logical file structure (vpc.tf, ecs.tf, opensearch.tf, prometheus.tf, iam.tf, security-groups.tf, etc.)
5. THE Terraform_Module SHALL output ECS Exec commands for accessing each service

### Requirement 18: Remote Access Documentation

**User Story:** As a DevOps engineer, I want clear documentation for remotely accessing Temporal UI and Grafana dashboards, so that I can browse these interfaces from my local machine.

**Reference:** [Using ECS Exec for debugging](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)

#### Acceptance Criteria

1. THE Documentation SHALL include step-by-step instructions for accessing Temporal UI via SSM Session Manager port forwarding
2. THE Documentation SHALL include step-by-step instructions for accessing Grafana via SSM Session Manager port forwarding
3. THE Documentation SHALL include example AWS CLI commands for establishing port forwarding sessions using aws ssm start-session with portForwardingSessionType
4. THE Documentation SHALL explain how to find running task IDs using aws ecs list-tasks and aws ecs describe-tasks commands
5. THE Documentation SHALL include troubleshooting guidance for common access issues (IAM permissions, VPC endpoint connectivity, Session Manager plugin installation)
6. THE Documentation SHALL include instructions for installing the AWS Session Manager plugin

### Requirement 21: Staged Deployment Workflow

**User Story:** As a DevOps engineer, I want ECS services to deploy with zero replicas initially, so that I can setup database schemas before services attempt to connect and avoid crash-loops.

#### Acceptance Criteria

1. THE Terraform_Module SHALL configure all ECS service desired_count variables to default to 0
2. THE Terraform_Module SHALL allow desired_count values of 0 or greater (remove minimum 1 validation)
3. THE Scale_Script SHALL accept 'up' command to scale all services to specified count (default: 1)
4. THE Scale_Script SHALL accept 'down' command to scale all services to 0
5. THE Scale_Script SHALL support --from-terraform option to read cluster name and region from terraform.tfvars
6. THE Scale_Script SHALL support --cluster and --region options for direct specification
7. THE Scale_Script SHALL scale services in proper startup order (History, Matching, Frontend, Worker, UI, Grafana, ADOT)
8. THE Documentation SHALL describe the staged deployment workflow: deploy infrastructure, setup schemas, then scale services
