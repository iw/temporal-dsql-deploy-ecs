# -----------------------------------------------------------------------------
# Output Values
# -----------------------------------------------------------------------------
# This file will be populated as resources are created in subsequent tasks.
# Outputs will include:
# - ECS cluster ARN and name
# - Service names for each Temporal component
# - OpenSearch endpoint
# - Prometheus workspace ID and endpoint
# - ECS Exec commands for accessing each service
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}


# -----------------------------------------------------------------------------
# IAM Role Outputs
# -----------------------------------------------------------------------------

output "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_execution.arn
}

output "ecs_execution_role_name" {
  description = "Name of the ECS task execution role"
  value       = aws_iam_role.ecs_execution.name
}

output "temporal_task_role_arn" {
  description = "ARN of the Temporal task role"
  value       = aws_iam_role.temporal_task.arn
}

output "temporal_task_role_name" {
  description = "Name of the Temporal task role"
  value       = aws_iam_role.temporal_task.name
}

output "grafana_task_role_arn" {
  description = "ARN of the Grafana task role"
  value       = aws_iam_role.grafana_task.arn
}

output "grafana_task_role_name" {
  description = "Name of the Grafana task role"
  value       = aws_iam_role.grafana_task.name
}

output "temporal_ui_task_role_arn" {
  description = "ARN of the Temporal UI task role"
  value       = aws_iam_role.temporal_ui_task.arn
}

output "temporal_ui_task_role_name" {
  description = "Name of the Temporal UI task role"
  value       = aws_iam_role.temporal_ui_task.name
}


# -----------------------------------------------------------------------------
# ECS Cluster Outputs
# -----------------------------------------------------------------------------

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_instances_security_group_id" {
  description = "ID of the ECS instances security group"
  value       = aws_security_group.ecs_instances.id
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "service_connect_namespace_arn" {
  description = "ARN of the Service Connect namespace"
  value       = aws_service_discovery_http_namespace.main.arn
}

output "service_connect_namespace_id" {
  description = "ID of the Service Connect namespace"
  value       = aws_service_discovery_http_namespace.main.id
}

output "service_connect_namespace_name" {
  description = "Name of the Service Connect namespace"
  value       = aws_service_discovery_http_namespace.main.name
}

output "ecs_exec_log_group_name" {
  description = "Name of the CloudWatch Log Group for ECS Exec"
  value       = aws_cloudwatch_log_group.ecs_exec.name
}


# -----------------------------------------------------------------------------
# Secrets Manager Outputs
# -----------------------------------------------------------------------------

output "grafana_admin_secret_arn" {
  description = "ARN of the Grafana admin credentials secret"
  value       = data.aws_secretsmanager_secret.grafana_admin.arn
}

output "grafana_admin_secret_name" {
  description = "Name of the Grafana admin credentials secret"
  value       = data.aws_secretsmanager_secret.grafana_admin.name
}


# -----------------------------------------------------------------------------
# OpenSearch Outputs
# -----------------------------------------------------------------------------

output "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.temporal.arn
}

output "opensearch_domain_id" {
  description = "ID of the OpenSearch domain"
  value       = aws_opensearch_domain.temporal.domain_id
}

output "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.temporal.domain_name
}

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint (use with https://)"
  value       = aws_opensearch_domain.temporal.endpoint
}

output "opensearch_dashboard_endpoint" {
  description = "OpenSearch Dashboards endpoint"
  value       = aws_opensearch_domain.temporal.dashboard_endpoint
}

output "opensearch_visibility_index" {
  description = "OpenSearch visibility index name"
  value       = var.opensearch_visibility_index
}

output "opensearch_setup_task_definition_arn" {
  description = "ARN of the OpenSearch setup task definition"
  value       = aws_ecs_task_definition.opensearch_setup.arn
}

output "opensearch_setup_task_role_arn" {
  description = "ARN of the OpenSearch setup task role"
  value       = aws_iam_role.opensearch_setup_task.arn
}

# -----------------------------------------------------------------------------
# OpenSearch Setup Commands
# -----------------------------------------------------------------------------

output "opensearch_setup_command" {
  description = "Command to run the OpenSearch schema setup task"
  value       = <<-EOT
    aws ecs run-task \
      --cluster ${aws_ecs_cluster.main.name} \
      --task-definition ${aws_ecs_task_definition.opensearch_setup.family} \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[${aws_subnet.private[0].id}],securityGroups=[${aws_security_group.opensearch_setup.id}],assignPublicIp=DISABLED}" \
      --region ${var.region}
  EOT
}


# -----------------------------------------------------------------------------
# Amazon Managed Prometheus Outputs
# -----------------------------------------------------------------------------

output "prometheus_workspace_id" {
  description = "ID of the Amazon Managed Prometheus workspace"
  value       = aws_prometheus_workspace.main.id
}

output "prometheus_workspace_arn" {
  description = "ARN of the Amazon Managed Prometheus workspace"
  value       = aws_prometheus_workspace.main.arn
}

output "prometheus_remote_write_endpoint" {
  description = "Prometheus remote write endpoint URL"
  value       = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"
}

output "prometheus_query_endpoint" {
  description = "Prometheus query endpoint URL"
  value       = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/query"
}



# -----------------------------------------------------------------------------
# Grafana Service Outputs
# -----------------------------------------------------------------------------

output "grafana_service_name" {
  description = "Name of the Grafana ECS service"
  value       = aws_ecs_service.grafana.name
}

output "grafana_task_definition_arn" {
  description = "ARN of the Grafana task definition"
  value       = aws_ecs_task_definition.grafana.arn
}

output "grafana_task_definition_family" {
  description = "Family of the Grafana task definition"
  value       = aws_ecs_task_definition.grafana.family
}

# -----------------------------------------------------------------------------
# Grafana ECS Exec Command
# -----------------------------------------------------------------------------

output "grafana_ecs_exec_command" {
  description = "Command to access Grafana container via ECS Exec"
  value       = <<-EOT
    # Get the task ARN first
    TASK_ARN=$(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.grafana.name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${aws_ecs_cluster.main.name} \
      --task $TASK_ARN \
      --container grafana \
      --interactive \
      --command "/bin/sh" \
      --region ${var.region}
  EOT
}

output "grafana_port_forward_command" {
  description = "Command to port forward Grafana via SSM Session Manager"
  value       = <<-EOT
    # Get the task ARN and runtime ID
    TASK_ARN=$(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.grafana.name} --query 'taskArns[0]' --output text --region ${var.region})
    TASK_ID=$(echo $TASK_ARN | cut -d'/' -f3)
    RUNTIME_ID=$(aws ecs describe-tasks --cluster ${aws_ecs_cluster.main.name} --tasks $TASK_ARN --query 'tasks[0].containers[?name==`grafana`].runtimeId' --output text --region ${var.region})
    
    # Start port forwarding session (Grafana on port 3000)
    aws ssm start-session \
      --target ecs:${aws_ecs_cluster.main.name}_$${TASK_ID}_$${RUNTIME_ID} \
      --document-name AWS-StartPortForwardingSession \
      --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}' \
      --region ${var.region}
    
    # Then access Grafana at http://localhost:3000
  EOT
}


# -----------------------------------------------------------------------------
# Temporal Service Outputs
# -----------------------------------------------------------------------------

# History Service
output "temporal_history_service_name" {
  description = "Name of the Temporal History ECS service"
  value       = aws_ecs_service.temporal_history.name
}

output "temporal_history_task_definition_arn" {
  description = "ARN of the Temporal History task definition"
  value       = aws_ecs_task_definition.temporal_history.arn
}

output "temporal_history_task_definition_family" {
  description = "Family of the Temporal History task definition"
  value       = aws_ecs_task_definition.temporal_history.family
}

# Matching Service
output "temporal_matching_service_name" {
  description = "Name of the Temporal Matching ECS service"
  value       = aws_ecs_service.temporal_matching.name
}

output "temporal_matching_task_definition_arn" {
  description = "ARN of the Temporal Matching task definition"
  value       = aws_ecs_task_definition.temporal_matching.arn
}

output "temporal_matching_task_definition_family" {
  description = "Family of the Temporal Matching task definition"
  value       = aws_ecs_task_definition.temporal_matching.family
}

# Frontend Service
output "temporal_frontend_service_name" {
  description = "Name of the Temporal Frontend ECS service"
  value       = aws_ecs_service.temporal_frontend.name
}

output "temporal_frontend_task_definition_arn" {
  description = "ARN of the Temporal Frontend task definition"
  value       = aws_ecs_task_definition.temporal_frontend.arn
}

output "temporal_frontend_task_definition_family" {
  description = "Family of the Temporal Frontend task definition"
  value       = aws_ecs_task_definition.temporal_frontend.family
}

# Worker Service
output "temporal_worker_service_name" {
  description = "Name of the Temporal Worker ECS service"
  value       = aws_ecs_service.temporal_worker.name
}

output "temporal_worker_task_definition_arn" {
  description = "ARN of the Temporal Worker task definition"
  value       = aws_ecs_task_definition.temporal_worker.arn
}

output "temporal_worker_task_definition_family" {
  description = "Family of the Temporal Worker task definition"
  value       = aws_ecs_task_definition.temporal_worker.family
}

# UI Service
output "temporal_ui_service_name" {
  description = "Name of the Temporal UI ECS service"
  value       = aws_ecs_service.temporal_ui.name
}

output "temporal_ui_task_definition_arn" {
  description = "ARN of the Temporal UI task definition"
  value       = aws_ecs_task_definition.temporal_ui.arn
}

output "temporal_ui_task_definition_family" {
  description = "Family of the Temporal UI task definition"
  value       = aws_ecs_task_definition.temporal_ui.family
}


# -----------------------------------------------------------------------------
# Temporal ECS Exec Commands
# -----------------------------------------------------------------------------

output "temporal_history_ecs_exec_command" {
  description = "Command to access Temporal History container via ECS Exec"
  value       = <<-EOT
    # Get the task ARN first
    TASK_ARN=$(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.temporal_history.name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${aws_ecs_cluster.main.name} \
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
    TASK_ARN=$(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.temporal_matching.name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${aws_ecs_cluster.main.name} \
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
    TASK_ARN=$(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.temporal_frontend.name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${aws_ecs_cluster.main.name} \
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
    TASK_ARN=$(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.temporal_worker.name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${aws_ecs_cluster.main.name} \
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
    TASK_ARN=$(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.temporal_ui.name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${aws_ecs_cluster.main.name} \
      --task $TASK_ARN \
      --container temporal-ui \
      --interactive \
      --command "/bin/sh" \
      --region ${var.region}
  EOT
}


# -----------------------------------------------------------------------------
# Temporal UI Port Forwarding Command
# -----------------------------------------------------------------------------

output "temporal_ui_port_forward_command" {
  description = "Command to port forward Temporal UI via SSM Session Manager"
  value       = <<-EOT
    # Get the task ARN and runtime ID
    TASK_ARN=$(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.temporal_ui.name} --query 'taskArns[0]' --output text --region ${var.region})
    TASK_ID=$(echo $TASK_ARN | cut -d'/' -f3)
    RUNTIME_ID=$(aws ecs describe-tasks --cluster ${aws_ecs_cluster.main.name} --tasks $TASK_ARN --query 'tasks[0].containers[?name==`temporal-ui`].runtimeId' --output text --region ${var.region})
    
    # Start port forwarding session (Temporal UI on port 8080)
    aws ssm start-session \
      --target ecs:${aws_ecs_cluster.main.name}_$${TASK_ID}_$${RUNTIME_ID} \
      --document-name AWS-StartPortForwardingSession \
      --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}' \
      --region ${var.region}
    
    # Then access Temporal UI at http://localhost:8080
  EOT
}


# -----------------------------------------------------------------------------
# Summary Outputs
# -----------------------------------------------------------------------------

output "all_service_names" {
  description = "Map of all ECS service names"
  value = {
    temporal_history  = aws_ecs_service.temporal_history.name
    temporal_matching = aws_ecs_service.temporal_matching.name
    temporal_frontend = aws_ecs_service.temporal_frontend.name
    temporal_worker   = aws_ecs_service.temporal_worker.name
    temporal_ui       = aws_ecs_service.temporal_ui.name
    grafana           = aws_ecs_service.grafana.name
    adot              = aws_ecs_service.adot.name
  }
}

output "deployment_summary" {
  description = "Summary of the deployment with key endpoints and access commands"
  value       = <<-EOT
    
    ============================================================
    TEMPORAL ECS FARGATE DEPLOYMENT SUMMARY
    ============================================================
    
    ECS Cluster: ${aws_ecs_cluster.main.name}
    Region: ${var.region}
    
    SERVICES:
    - Temporal History:  ${aws_ecs_service.temporal_history.name}
    - Temporal Matching: ${aws_ecs_service.temporal_matching.name}
    - Temporal Frontend: ${aws_ecs_service.temporal_frontend.name}
    - Temporal Worker:   ${aws_ecs_service.temporal_worker.name}
    - Temporal UI:       ${aws_ecs_service.temporal_ui.name}
    - Grafana:           ${aws_ecs_service.grafana.name}
    - ADOT Collector:    ${aws_ecs_service.adot.name}
    
    ENDPOINTS:
    - OpenSearch: https://${aws_opensearch_domain.temporal.endpoint}
    - Prometheus: ${aws_prometheus_workspace.main.prometheus_endpoint}
    
    METRICS COLLECTION:
    - ADOT scrapes metrics from all Temporal services on port 9090
    - Metrics are remote written to Amazon Managed Prometheus
    - ADOT config stored in SSM: ${aws_ssm_parameter.adot_config.name}
    
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


# -----------------------------------------------------------------------------
# ADOT Collector Outputs
# -----------------------------------------------------------------------------

output "adot_service_name" {
  description = "Name of the ADOT Collector ECS service"
  value       = aws_ecs_service.adot.name
}

output "adot_task_definition_arn" {
  description = "ARN of the ADOT Collector task definition"
  value       = aws_ecs_task_definition.adot.arn
}

output "adot_task_definition_family" {
  description = "Family of the ADOT Collector task definition"
  value       = aws_ecs_task_definition.adot.family
}

output "adot_task_role_arn" {
  description = "ARN of the ADOT Collector task role"
  value       = aws_iam_role.adot_task.arn
}

output "adot_config_ssm_parameter_arn" {
  description = "ARN of the SSM Parameter containing ADOT collector configuration"
  value       = aws_ssm_parameter.adot_config.arn
}

output "adot_config_ssm_parameter_name" {
  description = "Name of the SSM Parameter containing ADOT collector configuration"
  value       = aws_ssm_parameter.adot_config.name
}

output "adot_ecs_exec_command" {
  description = "Command to access ADOT Collector container via ECS Exec"
  value       = <<-EOT
    # Get the task ARN first
    TASK_ARN=$(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.adot.name} --query 'taskArns[0]' --output text --region ${var.region})
    
    # Execute shell in the container
    aws ecs execute-command \
      --cluster ${aws_ecs_cluster.main.name} \
      --task $TASK_ARN \
      --container adot-collector \
      --interactive \
      --command "/bin/sh" \
      --region ${var.region}
  EOT
}
