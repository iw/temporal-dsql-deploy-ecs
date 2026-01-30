# -----------------------------------------------------------------------------
# DynamoDB Module - Input Variables
# -----------------------------------------------------------------------------
# Requirements: 11.2, 17.1
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "conn_lease_enabled" {
  description = "Enable creation of connection lease table for distributed connection count limiting"
  type        = bool
  default     = false
}
