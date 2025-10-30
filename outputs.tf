output "open_webui_url" {
  description = "URL to access Open WebUI service"
  value       = module.open_webui_service.service_endpoint
}
