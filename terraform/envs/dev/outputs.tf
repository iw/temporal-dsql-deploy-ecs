# -----------------------------------------------------------------------------
# Dev Environment - Outputs
# -----------------------------------------------------------------------------
# This file exposes key outputs from all modules for use by operators,
# scripts, and other automation tools.
#
# Requirements: 2.2
# -----------------------------------------------------------------------------

# =============================================================================
# GENERAL OUTPUTS
# =============================================================================

output "region" {
  description = "AWS region for this deployment"
  value       = var.region
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

# =============================================================================
# VPC OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_id" {
  description = "ID of the NAT Gateway public subnet"
  value       = module.vpc.public_subnet_id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = module.vpc.nat_gateway_id
}

# =============================================================================
# ECS CLUSTER OUTPUTS
# =============================================================================

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_cluster.cluster_arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.cluster_name
}

output "service_connect_namespace_arn" {
  description = "ARN of the Service Connect namespace"
  value       = module.ecs_cluster.service_connect_namespace_arn
}

output "ecs_exec_log_group_name" {
  description = "Name of the CloudWatch Log Group for ECS Exec"
  value       = module.ecs_cluster.ecs_exec_log_group_name
}

# =============================================================================
# EC2 CAPACITY OUTPUTS
# =============================================================================

output "capacity_provider_name" {
  description = "Name of the main ECS capacity provider"
  value       = module.ec2_capacity.capacity_provider_name
}

output "asg_name" {
  description = "Name of the main Auto Scaling Group"
  value       = module.ec2_capacity.asg_name
}

output "ecs_instances_security_group_id" {
  description = "ID of the ECS instances security group"
  value       = module.ec2_capacity.instance_security_group_id
}

# =============================================================================
# IAM OUTPUTS
# =============================================================================

output "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = module.iam.execution_role_arn
}

output "temporal_task_role_arn" {
  description = "ARN of the Temporal task role"
  value       = module.iam.temporal_task_role_arn
}

output "grafana_task_role_arn" {
  description = "ARN of the Grafana task role"
  value       = module.iam.grafana_task_role_arn
}

output "temporal_ui_task_role_arn" {
  description = "ARN of the Temporal UI task role"
  value       = module.iam.temporal_ui_task_role_arn
}

# =============================================================================
# DYNAMODB OUTPUTS
# =============================================================================

output "dynamodb_table_name" {
  description = "DynamoDB table name for DSQL distributed rate limiter"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN for DSQL distributed rate limiter"
  value       = module.dynamodb.table_arn
}


# =============================================================================
# OPENSEARCH OUTPUTS
# =============================================================================

output "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = module.opensearch.domain_arn
}

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint (use with https://)"
  value       = module.opensearch.domain_endpoint
}

output "opensearch_security_group_id" {
  description = "Security group ID for the OpenSearch domain"
  value       = module.opensearch.security_group_id
}

output "opensearch_setup_task_definition_arn" {
  description = "ARN of the OpenSearch setup task definition"
  value       = module.opensearch.setup_task_definition_arn
}

output "opensearch_visibility_index" {
  description = "OpenSearch visibility index name"
  value       = var.opensearch_visibility_index
}

# =============================================================================
# OBSERVABILITY OUTPUTS
# =============================================================================

# Prometheus
output "prometheus_workspace_arn" {
  description = "ARN of the Amazon Managed Prometheus workspace"
  value       = module.observability.prometheus_workspace_arn
}

output "prometheus_remote_write_endpoint" {
  description = "Prometheus remote write endpoint URL"
  value       = module.observability.prometheus_remote_write_endpoint
}

output "prometheus_query_endpoint" {
  description = "Prometheus query endpoint URL"
  value       = module.observability.prometheus_query_endpoint
}

# Grafana
output "grafana_service_name" {
  description = "Name of the Grafana ECS service"
  value       = module.observability.grafana_service_name
}

output "grafana_security_group_id" {
  description = "Security group ID for Grafana service"
  value       = module.observability.grafana_security_group_id
}

# Loki (conditional)
output "loki_endpoint" {
  description = "Loki HTTP API endpoint (internal Service Connect DNS name)"
  value       = module.observability.loki_endpoint
}

output "loki_s3_bucket_name" {
  description = "Name of the S3 bucket used for Loki log storage"
  value       = module.observability.loki_s3_bucket_name
}

output "loki_s3_bucket_arn" {
  description = "ARN of the S3 bucket used for Loki log storage"
  value       = module.observability.loki_s3_bucket_arn
}

# =============================================================================
# TEMPORAL SERVICE OUTPUTS
# =============================================================================

# History Service
output "temporal_history_service_name" {
  description = "Name of the Temporal History ECS service"
  value       = module.temporal_history.service_name
}

output "temporal_history_task_definition_arn" {
  description = "ARN of the Temporal History task definition"
  value       = module.temporal_history.task_definition_arn
}

output "temporal_history_security_group_id" {
  description = "Security group ID for Temporal History service"
  value       = module.temporal_history.security_group_id
}

# Matching Service
output "temporal_matching_service_name" {
  description = "Name of the Temporal Matching ECS service"
  value       = module.temporal_matching.service_name
}

output "temporal_matching_task_definition_arn" {
  description = "ARN of the Temporal Matching task definition"
  value       = module.temporal_matching.task_definition_arn
}

output "temporal_matching_security_group_id" {
  description = "Security group ID for Temporal Matching service"
  value       = module.temporal_matching.security_group_id
}

# Frontend Service
output "temporal_frontend_service_name" {
  description = "Name of the Temporal Frontend ECS service"
  value       = module.temporal_frontend.service_name
}

output "temporal_frontend_task_definition_arn" {
  description = "ARN of the Temporal Frontend task definition"
  value       = module.temporal_frontend.task_definition_arn
}

output "temporal_frontend_security_group_id" {
  description = "Security group ID for Temporal Frontend service"
  value       = module.temporal_frontend.security_group_id
}

# Worker Service
output "temporal_worker_service_name" {
  description = "Name of the Temporal Worker ECS service"
  value       = module.temporal_worker.service_name
}

output "temporal_worker_task_definition_arn" {
  description = "ARN of the Temporal Worker task definition"
  value       = module.temporal_worker.task_definition_arn
}

output "temporal_worker_security_group_id" {
  description = "Security group ID for Temporal Worker service"
  value       = module.temporal_worker.security_group_id
}

# UI Service
output "temporal_ui_service_name" {
  description = "Name of the Temporal UI ECS service"
  value       = module.temporal_ui.service_name
}

output "temporal_ui_task_definition_arn" {
  description = "ARN of the Temporal UI task definition"
  value       = module.temporal_ui.task_definition_arn
}

output "temporal_ui_security_group_id" {
  description = "Security group ID for Temporal UI service"
  value       = module.temporal_ui.security_group_id
}


# =============================================================================
# BENCHMARK OUTPUTS (Conditional)
# =============================================================================

output "benchmark_task_definition_arn" {
  description = "ARN of the Benchmark task definition"
  value       = var.benchmark_enabled ? module.benchmark[0].task_definition_arn : null
}

output "benchmark_worker_service_name" {
  description = "Name of the Benchmark Worker ECS service"
  value       = var.benchmark_enabled ? module.benchmark[0].worker_service_name : null
}

output "benchmark_capacity_provider_name" {
  description = "Name of the Benchmark ECS capacity provider"
  value       = var.benchmark_enabled ? module.benchmark[0].capacity_provider_name : null
}

output "benchmark_security_group_id" {
  description = "ID of the Benchmark security group"
  value       = var.benchmark_enabled ? module.benchmark[0].security_group_id : null
}

output "benchmark_generator_service_name" {
  description = "Name of the Benchmark Generator ECS service"
  value       = var.benchmark_enabled ? module.benchmark[0].generator_service_name : null
}

# =============================================================================
# ECS EXEC COMMANDS
# =============================================================================
# These outputs provide ready-to-use commands for accessing containers via ECS Exec

output "temporal_history_ecs_exec_command" {
  description = "Command to access Temporal History container via ECS Exec"
  value       = <<-EOT
    # Get the task ARN first
    TASK_ARN=$(aws ecs list-tasks --cluster ${module.ecs_cluster.cluster_name} --service-name ${module.temporal_history.service_name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${module.ecs_cluster.cluster_name} \
      --task $TASK_ARN \
      --container temporal-history \
      --interactive \
      --command "/bin/sh" \
      --region ${var.region}
  EOT
}

output "temporal_matching_ecs_exec_command" {
  description = "Command to access Temporal Matching container via ECS Exec"
  value       = <<-EOT
    # Get the task ARN first
    TASK_ARN=$(aws ecs list-tasks --cluster ${module.ecs_cluster.cluster_name} --service-name ${module.temporal_matching.service_name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${module.ecs_cluster.cluster_name} \
      --task $TASK_ARN \
      --container temporal-matching \
      --interactive \
      --command "/bin/sh" \
      --region ${var.region}
  EOT
}

output "temporal_frontend_ecs_exec_command" {
  description = "Command to access Temporal Frontend container via ECS Exec"
  value       = <<-EOT
    # Get the task ARN first
    TASK_ARN=$(aws ecs list-tasks --cluster ${module.ecs_cluster.cluster_name} --service-name ${module.temporal_frontend.service_name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${module.ecs_cluster.cluster_name} \
      --task $TASK_ARN \
      --container temporal-frontend \
      --interactive \
      --command "/bin/sh" \
      --region ${var.region}
  EOT
}

output "temporal_worker_ecs_exec_command" {
  description = "Command to access Temporal Worker container via ECS Exec"
  value       = <<-EOT
    # Get the task ARN first
    TASK_ARN=$(aws ecs list-tasks --cluster ${module.ecs_cluster.cluster_name} --service-name ${module.temporal_worker.service_name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${module.ecs_cluster.cluster_name} \
      --task $TASK_ARN \
      --container temporal-worker \
      --interactive \
      --command "/bin/sh" \
      --region ${var.region}
  EOT
}

output "temporal_ui_ecs_exec_command" {
  description = "Command to access Temporal UI container via ECS Exec"
  value       = <<-EOT
    # Get the task ARN first
    TASK_ARN=$(aws ecs list-tasks --cluster ${module.ecs_cluster.cluster_name} --service-name ${module.temporal_ui.service_name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${module.ecs_cluster.cluster_name} \
      --task $TASK_ARN \
      --container temporal-ui \
      --interactive \
      --command "/bin/sh" \
      --region ${var.region}
  EOT
}

output "grafana_ecs_exec_command" {
  description = "Command to access Grafana container via ECS Exec"
  value       = <<-EOT
    # Get the task ARN first
    TASK_ARN=$(aws ecs list-tasks --cluster ${module.ecs_cluster.cluster_name} --service-name ${module.observability.grafana_service_name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${module.ecs_cluster.cluster_name} \
      --task $TASK_ARN \
      --container grafana \
      --interactive \
      --command "/bin/sh" \
      --region ${var.region}
  EOT
}


# =============================================================================
# PORT FORWARDING COMMANDS
# =============================================================================
# These outputs provide ready-to-use commands for port forwarding via SSM

output "temporal_ui_port_forward_command" {
  description = "Command to port forward Temporal UI via SSM Session Manager"
  value       = <<-EOT
    # Get the task ARN and runtime ID
    TASK_ARN=$(aws ecs list-tasks --cluster ${module.ecs_cluster.cluster_name} --service-name ${module.temporal_ui.service_name} --query 'taskArns[0]' --output text --region ${var.region})
    TASK_ID=$(echo $TASK_ARN | cut -d'/' -f3)
    RUNTIME_ID=$(aws ecs describe-tasks --cluster ${module.ecs_cluster.cluster_name} --tasks $TASK_ARN --query 'tasks[0].containers[?name==`temporal-ui`].runtimeId' --output text --region ${var.region})
    
    # Start port forwarding session (Temporal UI on port 8080)
    aws ssm start-session \
      --target ecs:${module.ecs_cluster.cluster_name}_$${TASK_ID}_$${RUNTIME_ID} \
      --document-name AWS-StartPortForwardingSession \
      --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}' \
      --region ${var.region}
    
    # Then access Temporal UI at http://localhost:8080
  EOT
}

output "grafana_port_forward_command" {
  description = "Command to port forward Grafana via SSM Session Manager"
  value       = <<-EOT
    # Get the task ARN and runtime ID
    TASK_ARN=$(aws ecs list-tasks --cluster ${module.ecs_cluster.cluster_name} --service-name ${module.observability.grafana_service_name} --query 'taskArns[0]' --output text --region ${var.region})
    TASK_ID=$(echo $TASK_ARN | cut -d'/' -f3)
    RUNTIME_ID=$(aws ecs describe-tasks --cluster ${module.ecs_cluster.cluster_name} --tasks $TASK_ARN --query 'tasks[0].containers[?name==`grafana`].runtimeId' --output text --region ${var.region})
    
    # Start port forwarding session (Grafana on port 3000)
    aws ssm start-session \
      --target ecs:${module.ecs_cluster.cluster_name}_$${TASK_ID}_$${RUNTIME_ID} \
      --document-name AWS-StartPortForwardingSession \
      --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}' \
      --region ${var.region}
    
    # Then access Grafana at http://localhost:3000
  EOT
}

# =============================================================================
# OPENSEARCH SETUP COMMAND
# =============================================================================

output "opensearch_setup_command" {
  description = "Command to run the OpenSearch schema setup task"
  value       = <<-EOT
    aws ecs run-task \
      --cluster ${module.ecs_cluster.cluster_name} \
      --task-definition ${module.opensearch.setup_task_definition_arn} \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[${module.vpc.private_subnet_ids[0]}],securityGroups=[${module.opensearch.setup_security_group_id}],assignPublicIp=DISABLED}" \
      --region ${var.region}
  EOT
}

# =============================================================================
# SUMMARY OUTPUTS
# =============================================================================

output "all_service_names" {
  description = "Map of all ECS service names"
  value = {
    temporal_history  = module.temporal_history.service_name
    temporal_matching = module.temporal_matching.service_name
    temporal_frontend = module.temporal_frontend.service_name
    temporal_worker   = module.temporal_worker.service_name
    temporal_ui       = module.temporal_ui.service_name
    grafana           = module.observability.grafana_service_name
  }
}

output "deployment_summary" {
  description = "Summary of the deployment with key endpoints and access commands"
  value       = <<-EOT
    
    ============================================================
    TEMPORAL ECS DEPLOYMENT SUMMARY (DEV ENVIRONMENT)
    ============================================================
    
    ECS Cluster: ${module.ecs_cluster.cluster_name}
    Region: ${var.region}
    
    SERVICES:
    - Temporal History:  ${module.temporal_history.service_name}
    - Temporal Matching: ${module.temporal_matching.service_name}
    - Temporal Frontend: ${module.temporal_frontend.service_name}
    - Temporal Worker:   ${module.temporal_worker.service_name}
    - Temporal UI:       ${module.temporal_ui.service_name}
    - Grafana:           ${module.observability.grafana_service_name}
    
    ENDPOINTS:
    - OpenSearch: https://${module.opensearch.domain_endpoint}
    - Prometheus: ${module.observability.prometheus_query_endpoint}
    
    OBSERVABILITY:
    - Alloy sidecars run alongside each Temporal service
    - Metrics: Scraped from localhost:9090 and pushed to AMP
    - Logs: Collected via Docker log tailing and pushed to Loki
    - All replicas are scraped (not just one via load balancer)
    
    ACCESS COMMANDS:
    
    1. Access Temporal UI (port 8080):
       terraform output -raw temporal_ui_port_forward_command | bash
       Then open: http://localhost:8080
    
    2. Access Grafana (port 3000):
       terraform output -raw grafana_port_forward_command | bash
       Then open: http://localhost:3000
    
    3. Run OpenSearch schema setup (one-time):
       terraform output -raw opensearch_setup_command | bash
    
    ============================================================
  EOT
}
