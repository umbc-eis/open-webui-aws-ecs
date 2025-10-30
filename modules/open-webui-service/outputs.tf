output "ecs_cluster" {
  description = "ECS cluster where Open webui is deployed in (tf resource: aws_ecs_cluster)"
  value       = aws_ecs_cluster.open_webui

}

output "ecs_task_def" {
  description = "ECS task definition for Open webui (tf resource: aws_ecs_task_definition)"
  value       = aws_ecs_task_definition.open_webui
}

output "ecs_service" {
  description = "ECS fargate service for Open webui (tf resource: aws_ecs_service)"
  value       = aws_ecs_service.open_webui
}

output "efs" {
  description = "EFS used by the ECS tasks (tf resource: aws_efs_file_system)"
  value       = aws_efs_file_system.open_webui
}

output "alb" {
  description = "ALB in the front of ECS (tf resource: aws_lb)"
  value       = aws_lb.openwebui
}

output "service_endpoint" {
  description = "Endpoint to access Open WebUI service"
  value       = local.alb_configs.create_domain ? "https://${var.open_webui_domain}" : "http://${aws_lb.openwebui.dns_name}"
}

output "aurora_cluster" {
  description = "Aurora PostgreSQL cluster for Open WebUI (tf resource: aws_rds_cluster)"
  value       = aws_rds_cluster.open_webui
}

output "aurora_endpoint" {
  description = "Aurora cluster endpoint"
  value       = aws_rds_cluster.open_webui.endpoint
}

output "database_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_master_password.arn
}

output "admin_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing admin user credentials"
  value       = aws_secretsmanager_secret.admin_credentials.arn
}

output "admin_email" {
  description = "Admin email address configured for the application"
  value       = var.admin_email
}

output "admin_init_lambda_function" {
  description = "Lambda function that creates the admin user"
  value       = aws_lambda_function.admin_init.function_name
}

output "admin_init_lambda_log_group" {
  description = "CloudWatch log group for admin init Lambda"
  value       = aws_cloudwatch_log_group.admin_init_lambda.name
}
