# -----------------------------------------------------------------------------
# VPC Module - Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_id" {
  description = "ID of the NAT Gateway public subnet"
  value       = aws_subnet.public_nat.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the VPC endpoints security group (null if endpoints disabled)"
  value       = var.enable_vpc_endpoints ? aws_security_group.vpc_endpoints[0].id : null
}
