output "open_webui_url" {
  description = "URL to access Open WebUI service"
  value       = module.open_webui_service.service_endpoint
}

output "ecr_repository_url" {
  description = "ECR repo URL for the Open WebUI image with extra Python libs"
  value       = module.open_webui_service.ecr_repository_url
}
