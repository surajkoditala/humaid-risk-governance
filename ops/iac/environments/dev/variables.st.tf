variable "storage_public_network_access_enabled" {
  description = "Enable or disable public network access for the Storage Account"
  type        = bool
  default     = true
}

variable "blob_allowed_origins" {
  description = "List of allowed origins for blob CORS"
  type        = list(string)
  default     = ["http://localhost:4200"]
}

variable "blob_max_age_in_seconds" {
  description = "The number of seconds the client/browser should cache a preflight response"
  type        = number
  default     = 3600
}

variable "storage_ip_rules" {
  description = "List of allowed public IPs for storage account access"
  type        = list(string)
  default     = ["210.14.21.200", "157.66.143.200", "208.195.3.201"]
}