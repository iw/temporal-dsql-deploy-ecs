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
  description = "Create connection lease table. Set to true to create the table. Table is not destroyed when set to false after creation - use lifecycle prevent_destroy."
  type        = bool
  default     = true
}
