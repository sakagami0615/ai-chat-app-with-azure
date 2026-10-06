locals {
  resource_group_name = "rg-aichat-sandbox-${var.name_suffix}"
  registry_name       = "aichatsbx${var.name_suffix}"
  service_plan_name   = "asp-aichat-sbx-${var.name_suffix}"
  web_app_name        = "app-aichat-sbx-${var.name_suffix}"
}

resource "azurerm_resource_group" "sandbox" {
  name     = local.resource_group_name
  location = var.location
}

resource "azurerm_container_registry" "sandbox" {
  name                = local.registry_name
  resource_group_name = azurerm_resource_group.sandbox.name
  location            = azurerm_resource_group.sandbox.location
  sku                 = var.acr_sku
  admin_enabled       = false
}

resource "azurerm_service_plan" "sandbox" {
  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.sandbox.name
  location            = azurerm_resource_group.sandbox.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
}

resource "azurerm_linux_web_app" "hello_world" {
  name                = local.web_app_name
  resource_group_name = azurerm_resource_group.sandbox.name
  location            = azurerm_resource_group.sandbox.location
  service_plan_id     = azurerm_service_plan.sandbox.id
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    WEBSITES_PORT = "8501"
  }

  site_config {
    always_on                               = true
    websockets_enabled                      = true
    container_registry_use_managed_identity = true
    ip_restriction_default_action           = "Deny"
    scm_ip_restriction_default_action       = "Deny"
    scm_use_main_ip_restriction             = true

    application_stack {
      docker_image_name   = "hello-world:pending"
      docker_registry_url = "https://${azurerm_container_registry.sandbox.login_server}"
    }

    ip_restriction {
      name       = "owner-ip"
      priority   = 100
      action     = "Allow"
      ip_address = var.allowed_ip_cidr
    }
  }

  lifecycle {
    ignore_changes = [site_config[0].application_stack[0].docker_image_name]
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                            = azurerm_container_registry.sandbox.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_linux_web_app.hello_world.identity[0].principal_id
  skip_service_principal_aad_check = true
}
