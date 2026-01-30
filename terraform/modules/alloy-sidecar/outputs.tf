# -----------------------------------------------------------------------------
# Alloy Sidecar Module - Outputs
# -----------------------------------------------------------------------------
# Requirements: 12.3
# -----------------------------------------------------------------------------

output "init_container_definition" {
  description = "Init container definition for fetching Alloy config from SSM"
  value       = local.init_container_definition
}

output "sidecar_container_definition" {
  description = "Alloy sidecar container definition for metrics and log collection"
  value       = local.sidecar_container_definition
}

output "ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the Alloy configuration"
  value       = aws_ssm_parameter.alloy_config.arn
}

# -----------------------------------------------------------------------------
# Volume Definitions
# -----------------------------------------------------------------------------
# These outputs provide the volume definitions needed by task definitions
# that include the Alloy sidecar containers

output "docker_socket_volume" {
  description = "Docker socket volume definition for log collection"
  value       = local.docker_socket_volume
}

output "alloy_config_volume" {
  description = "Alloy config volume definition shared between init and sidecar containers"
  value       = local.alloy_config_volume
}
