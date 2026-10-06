output "subscription_id" {
  value = var.subscription_id
}

output "resource_group_name" {
  value = azurerm_resource_group.sandbox.name
}

output "registry_name" {
  value = azurerm_container_registry.sandbox.name
}

output "registry_login_server" {
  value = azurerm_container_registry.sandbox.login_server
}

output "web_app_name" {
  value = azurerm_linux_web_app.hello_world.name
}

output "web_app_url" {
  value = "https://${azurerm_linux_web_app.hello_world.default_hostname}"
}
