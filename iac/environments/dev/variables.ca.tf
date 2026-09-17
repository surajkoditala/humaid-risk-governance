# Environment variables
variable "container_app_service_name" {
  description = "Name of the container app service"
  type        = string
  default     = "gh-riskgovernance-ui"
}

variable "min_replicas" {
  description = "Minimum number of replicas for a container app service"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of replicas for a container app service"
  type        = number
  default     = 1
}

# Optional: Ingress configuration
variable "ingress" {
  description = "Optional ingress configuration."
  type = object({
    target_port = number
    traffic_weight = optional(list(object({ #Only applies if revision_mode is set to multiple
      percentage      = number
      label           = optional(string)
      latest_revision = optional(bool, true)
      revision_suffix = optional(string) #If latest_revision is false, the revision_suffix shall be specified.
    })), [{ percentage = 100 }])
    external_enabled           = optional(bool, true)
    allow_insecure_connections = optional(bool, false)
    client_certificate_mode    = optional(string, "ignore") #require, accept, ignore
    cors = optional(object({
      allowed_origins    = list(string)
      allowed_methods    = optional(list(string))
      allowed_headers    = optional(list(string))
      exposed_headers    = optional(list(string))
      max_age_in_seconds = optional(number)
    }))
    fqdn = optional(string)
    ip_security_restriction = optional(object({
      ip_address_range = string
      name             = string
      action           = string #Allow or Deny
    }))
    exposed_port = optional(number)         #can only be specified if transport is set to tcp
    transport    = optional(string, "auto") #auto, http, http2 and tcp. Defaults to auto.
  })
  default = {
    target_port = 443
  }
}

#Backend app variables
variable "container_app_backend_app_name" {
  description = "Name of the backend app container app service"
  type        = string
  default     = "gh-riskgovernance-backend-app"
}

variable "backend_app_min_replicas" {
  description = "Minimum number of replicas for the backend app container app"
  type        = number
  default     = 1
}

variable "backend_app_max_replicas" {
  description = "Maximum number of replicas for the backend app container app"
  type        = number
  default     = 1
}

variable "backend_app_ingress" {
  description = "Optional ingress configuration for the backend app container app."
  type = object({
    target_port = number
    traffic_weight = optional(list(object({ #Only applies if revision_mode is set to multiple
      percentage      = number
      label           = optional(string)
      latest_revision = optional(bool, true)
      revision_suffix = optional(string) #If latest_revision is false, the revision_suffix shall be specified.
    })), [{ percentage = 100 }])
    external_enabled           = optional(bool, true)
    allow_insecure_connections = optional(bool, false)
    client_certificate_mode    = optional(string, "ignore") #require, accept, ignore
    cors = optional(object({
      allowed_origins    = list(string)
      allowed_methods    = optional(list(string))
      allowed_headers    = optional(list(string))
      exposed_headers    = optional(list(string))
      max_age_in_seconds = optional(number)
    }))
    fqdn = optional(string)
    ip_security_restriction = optional(object({
      ip_address_range = string
      name             = string
      action           = string #Allow or Deny
    }))
    exposed_port = optional(number)         #can only be specified if transport is set to tcp
    transport    = optional(string, "auto") #auto, http, http2 and tcp. Defaults to auto.
  })
  default = {
    target_port = 3000
  }
}
