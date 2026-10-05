mock_provider "azurerm" {}

run "sandbox_security" {
  command = plan

  variables {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    name_suffix     = "abc123"
    allowed_ip_cidr = "203.0.113.10/32"
  }

  assert {
    condition     = azurerm_container_registry.sandbox.admin_enabled == false
    error_message = "ACR admin user must stay disabled."
  }

  assert {
    condition     = azurerm_linux_web_app.hello_world.https_only == true
    error_message = "HTTPS must be required."
  }

  assert {
    condition     = azurerm_linux_web_app.hello_world.site_config[0].ip_restriction_default_action == "Deny"
    error_message = "Unlisted client IPs must be denied."
  }

  assert {
    condition     = azurerm_linux_web_app.hello_world.site_config[0].scm_use_main_ip_restriction == true
    error_message = "SCM must share the main site's IP restrictions."
  }

  assert {
    condition     = azurerm_linux_web_app.hello_world.site_config[0].container_registry_use_managed_identity == true
    error_message = "The web app must use managed identity for ACR pull."
  }
}

run "invalid_client_ip" {
  command = plan

  variables {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    name_suffix     = "abc123"
    allowed_ip_cidr = "invalid"
  }

  expect_failures = [var.allowed_ip_cidr]
}

run "empty_client_ip" {
  command = plan

  variables {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    name_suffix     = "abc123"
    allowed_ip_cidr = ""
  }

  expect_failures = [var.allowed_ip_cidr]
}

run "broad_client_range" {
  command = plan

  variables {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    name_suffix     = "abc123"
    allowed_ip_cidr = "0.0.0.0/1"
  }

  expect_failures = [var.allowed_ip_cidr]
}
