variable "prefix" {
  description = "Prefix to resource created by this module"
  type        = string
  default     = "openwebui"
}

variable "region" {
  description = "aws region for setup"
  type        = string
  default     = "ap-southeast-1"
}

variable "azs" {
  description = "Availability zones to deploy the ECS"
  type        = list(string)
}

# VPC related
variable "vpc_id" {
  description = "VPC id to deploy the Open webui ECS"
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block"
  type        = string
}

variable "ecs_subnet_ids" {
  description = "ID of subnets to deploy the ECS (and EFS storage), recommend pvt subnets"
  type        = list(string)
}

variable "alb_subnet_ids" {
  description = "ID of subnets to deploy the ALB to expose ECS, recommend pub subnets"
  type        = list(string)
}

# Open webui related
variable "open_webui_task_cpu" {
  description = "CPU in open webui task def"
  type        = number
  default     = 1024
}

variable "open_webui_task_mem" {
  description = "Memory in open webui task def"
  type        = number
  default     = 2048
}

variable "open_webui_task_count" {
  description = "Desired tasks in open webui ECS service"
  type        = number
  default     = 3
}

variable "open_webui_port" {
  description = "Port that open webui is open for"
  type        = number
  default     = 8080
}

variable "open_webui_image_url" {
  description = "URL to open webui docker image for deployment"
  type        = string
}

variable "open_webui_domain" {
  description = "Domain to be used to expose Open Webui ALB"
  type        = string
  default     = ""
}

variable "open_webui_domain_route53_zone" {
  description = "Route53 zone id where the domain name for Open webui ALB is hosted at"
  type        = string
  default     = ""
}

variable "open_webui_domain_ssl_cert_arn" {
  description = "The arn of the acm cert for Open webui ALb"
  type        = string
  default     = ""
}

# Admin user configuration
variable "admin_name" {
  description = "Name for the initial admin user"
  type        = string
}

variable "admin_email" {
  description = "Email address for the initial admin user"
  type        = string
}

variable "enable_signup" {
  description = "Enable user signup (set to false after initial admin account creation)"
  type        = bool
  default     = true
}

variable "default_user_role" {
  description = "Default role for new users (pending, user, admin)"
  type        = string
  default     = "admin"
  validation {
    condition     = contains(["pending", "user", "admin"], var.default_user_role)
    error_message = "default_user_role must be one of: pending, user, admin"
  }
}

# OAuth/SSO Configuration (AWS Cognito)
variable "enable_oauth_signup" {
  description = "Enable OAuth/SSO signup"
  type        = bool
  default     = false
}

variable "oauth_provider_name" {
  description = "Display name for OAuth provider (e.g., 'AWS Cognito', 'UMBC SSO')"
  type        = string
  default     = "SSO"
}

variable "cognito_user_pool_id" {
  description = "AWS Cognito User Pool ID (leave empty to disable Cognito SSO)"
  type        = string
  default     = ""
}

variable "cognito_app_client_id" {
  description = "AWS Cognito App Client ID"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cognito_app_client_secret" {
  description = "AWS Cognito App Client Secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "oauth_merge_accounts_by_email" {
  description = "Merge OAuth accounts with existing accounts by email"
  type        = bool
  default     = true
}

variable "oauth_allowed_domains" {
  description = "Comma-separated list of allowed email domains for OAuth (use '*' for all)"
  type        = string
  default     = "*"
}

variable "disable_local_auth" {
  description = "Disable local username/password authentication (requires OAuth to be configured)"
  type        = bool
  default     = false
}

variable "force_oauth_login" {
  description = "Force all users to authenticate via OAuth/SSO only"
  type        = bool
  default     = false
}

# API Key Configuration
variable "enable_api_key" {
  description = "Enable API key authentication (allows users to create API keys for programmatic access)"
  type        = bool
  default     = false
}

# Direct Connections - allows users to configure their own LLM connections in UI
variable "enable_direct_connections" {
  description = "Allow users to configure their own OpenAI/LLM connections directly in the UI"
  type        = bool
  default     = true
}

# Security - IP allowlist for ALB public access
variable "allowed_ingress_cidrs" {
  description = "List of CIDR blocks allowed to access the ALB on ports 80/443. Use ['0.0.0.0/0'] to allow public access. Default blocks all access for security."
  type        = list(string)
  default     = ["127.0.0.1/32"]  # Effectively blocks all external access by default
  validation {
    condition     = length(var.allowed_ingress_cidrs) > 0
    error_message = "At least one CIDR block must be specified. Use ['0.0.0.0/0'] for public access."
  }
}

# Security - AWS WAF Configuration
variable "enable_waf" {
  description = "Enable AWS WAF v2 for the Application Load Balancer with managed rule groups"
  type        = bool
  default     = true
}

variable "waf_enable_logging" {
  description = "Enable WAF logging to CloudWatch Logs"
  type        = bool
  default     = false
}

variable "waf_log_retention_days" {
  description = "Number of days to retain WAF logs in CloudWatch"
  type        = number
  default     = 7
}
