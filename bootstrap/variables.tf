variable "region" {
  description = "AWS region for the state bucket and DynamoDB table"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name for the S3 bucket that will store Terraform state (must be globally unique)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.state_bucket_name))
    error_message = "Bucket name must be lowercase, numbers, and hyphens only."
  }
}

variable "dynamodb_table_name" {
  description = "Name for the DynamoDB table used for state locking"
  type        = string
  default     = "terraform-state-lock"
}
variable "extra_state_access_role_arns" {
  description = "IAM role ARNs (wildcards allowed) that may read/write state, in addition to the SSO AdministratorAccess roles and OrganizationAccountAccessRole"
  type        = list(string)
  default     = []
}
