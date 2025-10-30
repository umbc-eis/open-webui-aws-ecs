terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

module "open_webui_service" {
  source = "./modules/open-webui-service"

  region                         = var.region
  azs                            = var.azs
  vpc_id                         = var.vpc_id
  vpc_cidr_block                 = var.vpc_cidr_block
  ecs_subnet_ids                 = var.ecs_subnet_ids
  alb_subnet_ids                 = var.alb_subnet_ids
  open_webui_task_cpu            = var.open_webui_task_cpu
  open_webui_task_mem            = var.open_webui_task_mem
  open_webui_task_count          = var.open_webui_task_count
  open_webui_port                = var.open_webui_port
  open_webui_image_url           = var.open_webui_image_url
  open_webui_domain              = var.open_webui_domain
  open_webui_domain_route53_zone = var.open_webui_domain_route53_zone
  open_webui_domain_ssl_cert_arn = var.open_webui_domain_ssl_cert_arn
  db_engine_version              = var.db_engine_version
  admin_name                     = var.admin_name
  admin_email                    = var.admin_email
  enable_signup                  = var.enable_signup
  default_user_role              = var.default_user_role
  enable_oauth_signup            = var.enable_oauth_signup
  oauth_provider_name            = var.oauth_provider_name
  cognito_user_pool_id           = var.cognito_user_pool_id
  cognito_app_client_id          = var.cognito_app_client_id
  cognito_app_client_secret      = var.cognito_app_client_secret
  oauth_merge_accounts_by_email  = var.oauth_merge_accounts_by_email
  oauth_allowed_domains          = var.oauth_allowed_domains
  disable_local_auth             = var.disable_local_auth
  force_oauth_login              = var.force_oauth_login
  enable_api_key                 = var.enable_api_key
  enable_direct_connections      = var.enable_direct_connections
  allowed_ingress_cidrs          = var.allowed_ingress_cidrs
  enable_waf                     = var.enable_waf
  waf_enable_logging             = var.waf_enable_logging
  waf_log_retention_days         = var.waf_log_retention_days
}
