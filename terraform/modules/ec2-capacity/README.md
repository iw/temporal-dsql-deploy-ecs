# EC2 Capacity Module

## Purpose

Creates EC2 capacity provider with Auto Scaling Group for ECS tasks. This module provisions Graviton-based EC2 instances that provide compute capacity for ECS services, with configurable instance types and counts per environment.

Benefits over Fargate:
- Stable IPs for cluster membership (ringpop)
- Host networking mode option
- Better cost efficiency for sustained workloads
- More control over instance placement

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name for resource naming | required |
| cluster_name | string | ECS cluster name to join | required |
| vpc_id | string | VPC ID for security group | required |
| vpc_cidr | string | VPC CIDR block for security group rules | required |
| subnet_ids | list(string) | Subnet IDs for EC2 instances | required |
| instance_type | string | EC2 instance type (Graviton recommended) | "m7g.xlarge" |
| instance_count | number | Desired number of EC2 instances | 2 |
| min_size | number | Minimum number of instances in ASG | 1 |
| max_size | number | Maximum number of instances in ASG | instance_count + 2 |
| workload_type | string | Workload identifier (main/benchmark) | "main" |
| ebs_volume_size | number | EBS volume size in GB | 50 |
| protect_from_scale_in | bool | Enable scale-in protection | true |
| scaling_step_size | number | Maximum scaling step size | 2 |
| target_capacity | number | Target capacity percentage | 100 |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| capacity_provider_name | string | Name of the ECS capacity provider |
| asg_name | string | Name of the Auto Scaling Group |
| asg_arn | string | ARN of the Auto Scaling Group |
| instance_security_group_id | string | ID of the security group for EC2 instances |
| instance_role_arn | string | ARN of the EC2 instance IAM role |
| instance_role_name | string | Name of the EC2 instance IAM role |
| instance_profile_arn | string | ARN of the EC2 instance profile |
| launch_template_id | string | ID of the launch template |

## Usage Example

```hcl
module "ec2_capacity" {
  source = "../../modules/ec2-capacity"

  project_name   = "temporal-dev"
  cluster_name   = module.ecs_cluster.cluster_name
  vpc_id         = module.vpc.vpc_id
  vpc_cidr       = module.vpc.vpc_cidr
  subnet_ids     = module.vpc.private_subnet_ids
  instance_type  = "m7g.xlarge"
  instance_count = 6
  workload_type  = "main"
}

# For benchmark workload with scale-from-zero
module "benchmark_capacity" {
  source = "../../modules/ec2-capacity"

  project_name          = "temporal-dev"
  cluster_name          = module.ecs_cluster.cluster_name
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr
  subnet_ids            = module.vpc.private_subnet_ids
  instance_type         = "m7g.2xlarge"
  instance_count        = 0
  min_size              = 0
  max_size              = 13
  workload_type         = "benchmark"
  protect_from_scale_in = false
}
```

## Resources Created

- `aws_launch_template.ecs` - Launch template with ECS-optimized ARM64 AMI
- `aws_autoscaling_group.ecs` - Auto Scaling Group for EC2 instances
- `aws_ecs_capacity_provider.ec2` - ECS capacity provider linked to ASG
- `aws_iam_role.ecs_instance` - IAM role for EC2 instances
- `aws_iam_instance_profile.ecs_instance` - Instance profile for EC2 instances
- `aws_security_group.ecs_instances` - Security group for EC2 instances

## Notes

- Uses ECS-optimized Amazon Linux 2023 AMI for ARM64 (Graviton)
- Instances automatically join the specified ECS cluster via user data
- Security group allows all traffic within VPC and egress for AWS services and DSQL
- IAM role includes permissions for ECS, SSM, and DSQL access
