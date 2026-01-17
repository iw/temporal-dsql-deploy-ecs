# -----------------------------------------------------------------------------
# Benchmark Runner Task Definition and Service
# -----------------------------------------------------------------------------
# This file creates the benchmark runner ECS task definition.
# The benchmark runner is a one-shot task (not a long-running service) that:
# - Executes configurable workflow patterns against Temporal
# - Collects metrics and exposes them on port 9090
# - Reports results in JSON format
#
# Key features:
# - ARM64 architecture for Graviton instances
# - awsvpc networking for Service Connect
# - Client-only Service Connect mode (consumes temporal-frontend)
# - Configurable via environment variables
#
# Requirements: 4.6, 5.1, 5.7
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Benchmark IAM Role
# -----------------------------------------------------------------------------
# Task role for benchmark runner with ECS Exec support

resource "aws_iam_role" "benchmark_task" {
  name = "${var.project_name}-benchmark-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-benchmark-task"
  }
}

# ECS Exec permissions for benchmark
resource "aws_iam_role_policy" "benchmark_ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.benchmark_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Benchmark CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "benchmark" {
  name              = "/ecs/${var.project_name}/benchmark"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-benchmark-logs"
  }
}

# -----------------------------------------------------------------------------
# Benchmark Task Definition
# -----------------------------------------------------------------------------
# Requirements: 4.6, 5.1, 5.7

resource "aws_ecs_task_definition" "benchmark" {
  family                   = "${var.project_name}-benchmark"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.benchmark_cpu
  memory                   = var.benchmark_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.benchmark_task.arn

  # ARM64 (Graviton) architecture for cost efficiency
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "benchmark"
      image     = var.benchmark_image != "" ? var.benchmark_image : "public.ecr.aws/amazonlinux/amazonlinux:2023-minimal"
      essential = true

      # Port mapping for Prometheus metrics
      portMappings = [
        {
          containerPort = 9090
          protocol      = "tcp"
          name          = "metrics"
        }
      ]

      # Default environment variables - can be overridden at runtime
      environment = [
        { name = "TEMPORAL_ADDRESS", value = "temporal-frontend:7233" },
        { name = "BENCHMARK_NAMESPACE", value = "benchmark" },
        { name = "BENCHMARK_WORKFLOW_TYPE", value = "simple" },
        { name = "BENCHMARK_TARGET_RATE", value = "100" },
        { name = "BENCHMARK_DURATION", value = "5m" },
        { name = "BENCHMARK_RAMP_UP", value = "30s" },
        { name = "BENCHMARK_WORKER_COUNT", value = "4" },
        { name = "BENCHMARK_ITERATIONS", value = "1" },
        { name = "BENCHMARK_MAX_P99_LATENCY", value = "5s" },
        { name = "BENCHMARK_MIN_THROUGHPUT", value = "50" }
      ]

      # CloudWatch Logs configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.benchmark.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "benchmark"
          "awslogs-create-group"  = "true"
        }
      }

      # Enable ECS Exec
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = {
    Name    = "${var.project_name}-benchmark"
    Service = "benchmark"
  }
}


# -----------------------------------------------------------------------------
# Benchmark Security Group
# -----------------------------------------------------------------------------
# Security group for benchmark runner with:
# - Ingress for metrics scraping from ADOT (port 9090)
# - Egress to Temporal Frontend via Service Connect
# - Egress to AWS services (CloudWatch Logs)
#
# Requirements: 4.6

resource "aws_security_group" "benchmark" {
  name        = "${var.project_name}-benchmark"
  description = "Security group for Benchmark Runner"
  vpc_id      = aws_vpc.main.id

  # Egress to VPC for Service Connect communication with Temporal Frontend
  egress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # HTTPS egress for AWS services (CloudWatch Logs, etc.)
  egress {
    description = "HTTPS for AWS services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-benchmark-sg"
  }
}

# -----------------------------------------------------------------------------
# Security Group Rules for Metrics Scraping
# -----------------------------------------------------------------------------
# Allow ADOT to scrape Prometheus metrics from benchmark runner

resource "aws_security_group_rule" "benchmark_metrics_from_adot" {
  type                     = "ingress"
  from_port                = 9090
  to_port                  = 9090
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.adot.id
  security_group_id        = aws_security_group.benchmark.id
  description              = "Prometheus metrics from ADOT Collector"
}

# Allow benchmark to connect to Temporal Frontend (gRPC port 7233)
resource "aws_security_group_rule" "frontend_from_benchmark" {
  type                     = "ingress"
  description              = "gRPC from Benchmark runner"
  from_port                = 7233
  to_port                  = 7233
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.benchmark.id
  security_group_id        = aws_security_group.temporal_frontend.id
}

# -----------------------------------------------------------------------------
# Benchmark Outputs
# -----------------------------------------------------------------------------

output "benchmark_task_definition_arn" {
  description = "ARN of the Benchmark task definition"
  value       = aws_ecs_task_definition.benchmark.arn
}

output "benchmark_task_definition_family" {
  description = "Family of the Benchmark task definition"
  value       = aws_ecs_task_definition.benchmark.family
}

output "benchmark_task_role_arn" {
  description = "ARN of the Benchmark task role"
  value       = aws_iam_role.benchmark_task.arn
}

output "benchmark_security_group_id" {
  description = "ID of the Benchmark security group"
  value       = aws_security_group.benchmark.id
}

output "benchmark_capacity_provider_name" {
  description = "Name of the Benchmark ECS capacity provider"
  value       = aws_ecs_capacity_provider.benchmark.name
}

output "benchmark_log_group_name" {
  description = "Name of the Benchmark CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.benchmark.name
}

# -----------------------------------------------------------------------------
# Benchmark Run Command
# -----------------------------------------------------------------------------
# Command to run a benchmark task with default configuration

output "benchmark_run_command" {
  description = "Command to run a benchmark task"
  value       = <<-EOT
    # Run benchmark with default configuration
    aws ecs run-task \
      --cluster ${aws_ecs_cluster.main.name} \
      --task-definition ${aws_ecs_task_definition.benchmark.family} \
      --capacity-provider-strategy capacityProvider=${aws_ecs_capacity_provider.benchmark.name},weight=1,base=1 \
      --network-configuration "awsvpcConfiguration={subnets=[${join(",", aws_subnet.private[*].id)}],securityGroups=[${aws_security_group.ecs_instances.id},${aws_security_group.benchmark.id}],assignPublicIp=DISABLED}" \
      --enable-execute-command \
      --region ${var.region}
    
    # Run benchmark with custom configuration (example: 200 WPS for 10 minutes)
    # aws ecs run-task \
    #   --cluster ${aws_ecs_cluster.main.name} \
    #   --task-definition ${aws_ecs_task_definition.benchmark.family} \
    #   --capacity-provider-strategy capacityProvider=${aws_ecs_capacity_provider.benchmark.name},weight=1,base=1 \
    #   --network-configuration "awsvpcConfiguration={subnets=[${join(",", aws_subnet.private[*].id)}],securityGroups=[${aws_security_group.ecs_instances.id},${aws_security_group.benchmark.id}],assignPublicIp=DISABLED}" \
    #   --enable-execute-command \
    #   --overrides '{
    #     "containerOverrides": [{
    #       "name": "benchmark",
    #       "environment": [
    #         {"name": "BENCHMARK_WORKFLOW_TYPE", "value": "simple"},
    #         {"name": "BENCHMARK_TARGET_RATE", "value": "200"},
    #         {"name": "BENCHMARK_DURATION", "value": "10m"}
    #       ]
    #     }]
    #   }' \
    #   --region ${var.region}
  EOT
}

output "benchmark_get_results_command" {
  description = "Command to get benchmark results from CloudWatch Logs"
  value       = <<-EOT
    # Get the latest benchmark task ARN
    TASK_ARN=$(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --family ${aws_ecs_task_definition.benchmark.family} --desired-status STOPPED --query 'taskArns[0]' --output text --region ${var.region})
    TASK_ID=$(echo $TASK_ARN | cut -d'/' -f3)
    
    # Get logs from the benchmark task
    aws logs get-log-events \
      --log-group-name ${aws_cloudwatch_log_group.benchmark.name} \
      --log-stream-name "benchmark/$TASK_ID" \
      --region ${var.region} \
      --query 'events[*].message' \
      --output text
  EOT
}
