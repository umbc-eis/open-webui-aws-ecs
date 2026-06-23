locals {
  open_webui = {
    arch     = "ARM64"
    os       = "LINUX"
    data_dir = "/app/backend/data"
  }

  # Construct DATABASE_URL from Aurora cluster details
  database_url = "postgresql://${aws_rds_cluster.open_webui.master_username}:${urlencode(random_password.db_master_password.result)}@${aws_rds_cluster.open_webui.endpoint}:5432/${aws_rds_cluster.open_webui.database_name}"

  # Compute OAuth/Cognito configuration
  oauth_enabled         = var.enable_oauth_signup && var.cognito_user_pool_id != ""
  cognito_region        = var.cognito_user_pool_id != "" ? split("_", var.cognito_user_pool_id)[0] : var.region
  cognito_issuer        = var.cognito_user_pool_id != "" ? "https://cognito-idp.${local.cognito_region}.amazonaws.com/${var.cognito_user_pool_id}" : ""
  openid_provider_url   = local.cognito_issuer != "" ? "${local.cognito_issuer}/.well-known/openid-configuration" : ""
  oauth_redirect_uri    = local.alb_configs.create_domain ? "https://${var.open_webui_domain}/oauth/oidc/callback" : "http://${aws_lb.openwebui.dns_name}/oauth/oidc/callback"
  webui_url             = local.alb_configs.create_domain ? "https://${var.open_webui_domain}" : "http://${aws_lb.openwebui.dns_name}"

  # Base environment variables
  base_environment = [
    { name = "OPEN_WEBUI_PORT", value = tostring(var.open_webui_port) },
    { name = "DATABASE_URL", value = local.database_url },
    { name = "DATA_DIR", value = local.open_webui.data_dir },
    { name = "WEBUI_SECRET_KEY", value = random_password.webui_secret_key.result },
    { name = "ENABLE_SIGNUP", value = tostring(var.enable_signup) },
    { name = "DEFAULT_USER_ROLE", value = var.default_user_role },
    { name = "ADMIN_EMAIL", value = var.admin_email },
    { name = "SHOW_ADMIN_DETAILS", value = "true" },
    { name = "WEBUI_URL", value = local.webui_url },
    { name = "ENABLE_API_KEY", value = tostring(var.enable_api_key) },
    { name = "ENABLE_DIRECT_CONNECTIONS", value = tostring(var.enable_direct_connections) },
    { name = "ENABLE_OLLAMA_API", value = "False" },  # Disabled - not using Ollama
    { name = "VECTOR_DB", value = "pgvector" }        # Use PostgreSQL for vector storage instead of ChromaDB
  ]

  # OAuth environment variables (only if OAuth is enabled)
  oauth_environment = local.oauth_enabled ? [
    { name = "ENABLE_OAUTH_SIGNUP", value = "True" },
    { name = "OAUTH_MERGE_ACCOUNTS_BY_EMAIL", value = tostring(var.oauth_merge_accounts_by_email) },
    { name = "OAUTH_CLIENT_ID", value = var.cognito_app_client_id },
    { name = "OAUTH_CLIENT_SECRET", value = var.cognito_app_client_secret },
    { name = "OPENID_PROVIDER_URL", value = local.openid_provider_url },
    { name = "OPENID_REDIRECT_URI", value = local.oauth_redirect_uri },
    { name = "OAUTH_PROVIDER_NAME", value = var.oauth_provider_name },
    { name = "OAUTH_SCOPES", value = "openid email" },
    { name = "OAUTH_USERNAME_CLAIM", value = "email" },
    { name = "OAUTH_ALLOWED_DOMAINS", value = var.oauth_allowed_domains },
    { name = "DISABLE_LOCAL_AUTH", value = tostring(var.disable_local_auth) },
    { name = "FORCE_OAUTH_LOGIN", value = tostring(var.force_oauth_login) },
    { name = "ENABLE_LOGIN_FORM", value = "True" }
  ] : []

  # Combined environment variables
  container_environment = concat(local.base_environment, local.oauth_environment)

  ecs_iamr_policies = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientReadWriteAccess",
    "arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess",
    # Note: SecretsManagerReadWrite replaced with custom scoped policy (see ecs-related.tf)
  ]

  alb_configs = {
    listener_port            = var.open_webui_domain_ssl_cert_arn == "" ? 80 : 443
    listener_protocol        = var.open_webui_domain_ssl_cert_arn == "" ? "HTTP" : "HTTPS"
    listener_ssl_policy      = var.open_webui_domain_ssl_cert_arn == "" ? null : "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
    listener_certificate_arn = var.open_webui_domain_ssl_cert_arn == "" ? null : var.open_webui_domain_ssl_cert_arn

    create_domain = tobool(
      var.open_webui_domain != "" &&
      var.open_webui_domain_route53_zone != "" &&
      var.open_webui_domain_ssl_cert_arn != ""
    )
  }
}
