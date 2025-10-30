variable "region" {
  description = "AWS region"
  type        = string
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR"
  type        = string
}

variable "ecs_subnet_ids" {
  description = "Subnet IDs for ECS"
  type        = list(string)
}

variable "alb_subnet_ids" {
  description = "Subnet IDs for ALB"
  type        = list(string)
}

variable "open_webui_task_cpu" {
  description = "ECS task CPU units"
  type        = number
}

variable "open_webui_task_mem" {
  description = "ECS task memory in MB"
  type        = number
}

variable "open_webui_task_count" {
  description = "Number of ECS tasks"
  type        = number
}

variable "open_webui_port" {
  description = "Port Open WebUI listens on"
  type        = number
}

variable "open_webui_image_url" {
  description = "Docker image URL for Open WebUI service"
  type        = string
}

variable "open_webui_domain" {
  description = "Domain for Open WebUI"
  type        = string
}

variable "open_webui_domain_route53_zone" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "open_webui_domain_ssl_cert_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
}

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
}

variable "enable_oauth_signup" {
  description = "Enable OAuth/SSO signup"
  type        = bool
  default     = false
}

variable "oauth_provider_name" {
  description = "Display name for OAuth provider"
  type        = string
  default     = "SSO"
}

variable "cognito_user_pool_id" {
  description = "AWS Cognito User Pool ID"
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
  description = "Comma-separated list of allowed email domains for OAuth"
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

variable "enable_api_key" {
  description = "Enable API key authentication for programmatic access"
  type        = bool
  default     = false
}

variable "enable_direct_connections" {
  description = "Allow users to configure their own LLM connections in the UI"
  type        = bool
  default     = true
}

variable "allowed_ingress_cidrs" {
  description = "List of CIDR blocks allowed to access the ALB on ports 80/443. Use ['0.0.0.0/0'] to allow public access. Default blocks all access for security."
  type        = list(string)
  default     = ["127.0.0.1/32"]  # Effectively blocks all external access by default
}

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
