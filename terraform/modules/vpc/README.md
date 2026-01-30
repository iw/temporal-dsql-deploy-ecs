# VPC Module

## Purpose

Creates VPC networking infrastructure including subnets, NAT Gateway, Internet Gateway, route tables, and VPC endpoints for AWS services. This module provides the foundational network layer for all other infrastructure components.

## Resources Created

- VPC with DNS support enabled
- Private subnets across multiple availability zones
- Public subnet for NAT Gateway
- Internet Gateway
- NAT Gateway with Elastic IP
- Route tables for public and private subnets
- VPC endpoints (optional):
  - Interface endpoints: ECR API, ECR DKR, CloudWatch Logs, SSM, SSM Messages, EC2 Messages, Secrets Manager, APS Workspaces
  - Gateway endpoints: S3, DynamoDB

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name for resource naming | required |
| vpc_cidr | string | CIDR block for VPC | "10.0.0.0/16" |
| availability_zones | list(string) | AZs for subnet distribution (minimum 2) | required |
| enable_vpc_endpoints | bool | Create VPC endpoints for AWS services | true |
| region | string | AWS region for VPC endpoint service names | required |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| vpc_id | string | ID of the created VPC |
| vpc_cidr | string | CIDR block of the VPC |
| private_subnet_ids | list(string) | IDs of private subnets |
| public_subnet_id | string | ID of NAT Gateway subnet |
| nat_gateway_id | string | ID of NAT Gateway |
| private_route_table_id | string | ID of the private route table |
| vpc_endpoints_security_group_id | string | ID of VPC endpoints security group (null if disabled) |

## Usage Example

```hcl
module "vpc" {
  source = "../../modules/vpc"

  project_name         = "temporal-dev"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  enable_vpc_endpoints = true
  region               = "eu-west-1"
}
```

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           VPC (10.0.0.0/16)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ Private Subnet  │  │ Private Subnet  │  │ Private Subnet  │  │
│  │   AZ-a          │  │   AZ-b          │  │   AZ-c          │  │
│  │ 10.0.0.0/20     │  │ 10.0.16.0/20    │  │ 10.0.32.0/20    │  │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
│           │                    │                    │           │
│           └────────────────────┼────────────────────┘           │
│                                │                                │
│                    ┌───────────▼───────────┐                    │
│                    │   Private Route Table │                    │
│                    │   0.0.0.0/0 → NAT GW  │                    │
│                    └───────────┬───────────┘                    │
│                                │                                │
│                    ┌───────────▼───────────┐                    │
│                    │     NAT Gateway       │                    │
│                    │   (Public Subnet)     │                    │
│                    │   10.0.255.0/24       │                    │
│                    └───────────┬───────────┘                    │
│                                │                                │
│                    ┌───────────▼───────────┐                    │
│                    │   Internet Gateway    │                    │
│                    └───────────────────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
