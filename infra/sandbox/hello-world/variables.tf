variable "subscription_id" {
  description = "Azure subscription ID selected for this sandbox."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a UUID."
  }
}

variable "location" {
  description = "Azure region for all sandbox resources."
  type        = string
  default     = "japaneast"
}

variable "app_service_plan_sku" {
  description = "Linux App Service Plan SKU."
  type        = string
  default     = "B1"
}

variable "acr_sku" {
  description = "Azure Container Registry SKU."
  type        = string
  default     = "Basic"
}

variable "name_suffix" {
  description = "Unique lower-case letters and digits used in resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,12}$", var.name_suffix))
    error_message = "name_suffix must contain 4 to 12 lower-case letters or digits."
  }
}

variable "allowed_ip_cidr" {
  description = "Single public client IPv4 address in CIDR notation, for example x.x.x.x/32."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_ip_cidr)) && endswith(var.allowed_ip_cidr, "/32")
    error_message = "allowed_ip_cidr must be a single IPv4 host in x.x.x.x/32 notation."
  }
}
