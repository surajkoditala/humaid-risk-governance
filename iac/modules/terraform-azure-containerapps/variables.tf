#Common Variables
variable "resource_group_name" {
  description = "Name of the resource group where resources will be created"
  type        = string
}

#Name of the Container App
variable "container_app_service_name" {
  description = "Name of the Azure Container App Service. Use either this variable or the 'name' variable, not both. If this is used, it will follow the naming convention 'ca-<container_app_service_name>-<environment>'."
  type        = string
}

variable "name" {
  description = "Custom name of the container app. Use either this variable or the 'container_app_service_name' variable, not both. This can be used for passing a specific name to the container app."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "The name must start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase alphanumeric characters and hyphens."
  }

  validation {
    condition     = var.name == null || !can(regex("--", var.name))
    error_message = "The name cannot contain consecutive hyphens ('--')."
  }

  validation {
    condition     = var.name == null || length(var.name) <= 32
    error_message = "The name must not exceed 32 characters."
  }
}

variable "tags" {
  description = "Map of tags to be applied to all resources"
  type        = map(string)
  default = {
    "business_unit" = "banking"
    "customer"      = "myridius"
    "environment"   = "dev"
    "product"       = "gh" #genius-hacks
    "owner"         = "devops"
    "region"        = "eastus2"
  }
  validation {
    condition     = contains(keys(var.tags), "business_unit")
    error_message = "ERROR: tag 'business_unit' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
  validation {
    condition     = contains(keys(var.tags), "customer")
    error_message = "ERROR: tag 'customer' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
  validation {
    condition     = contains(keys(var.tags), "environment")
    error_message = "ERROR: tag 'environment' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
  validation {
    condition     = contains(keys(var.tags), "product")
    error_message = "ERROR: tag 'product' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
  validation {
    condition     = contains(keys(var.tags), "owner")
    error_message = "ERROR: tag 'owner' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
  validation {
    condition     = contains(keys(var.tags), "region")
    error_message = "ERROR: tag 'region' is required, tags provided are: ${join(", ", keys(var.tags))}"
  }
}

# Index value to add to the name of the resource
variable "user_preferred_index" {
  description = "A value to append at the end of the name"
  type        = number
  default     = 1
}

#Resource level lock
variable "lock" {
  type = object({
    kind = string
    name = optional(string, null)
  })
  default     = null
  description = <<DESCRIPTION
  Controls the Resource Lock configuration for this resource. The following properties can be specified:

  - `kind` - (Required) The type of lock. Possible values are `\"CanNotDelete\"` and `\"ReadOnly\"`.
  - `name` - (Optional) The name of the lock. If not specified, a name will be generated based on the `kind` value. Changing this forces the creation of a new resource.
  DESCRIPTION

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either `\"CanNotDelete\"` or `\"ReadOnly\"`."
  }
}

#Role assignment on the resource
variable "role_assignments" {
  type = map(object({
    role_definition_id_or_name             = string
    principal_id                           = string
    scope                                  = string
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = <<DESCRIPTION
  A map of role assignments to create on the <RESOURCE>. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.

  - `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.
  - `principal_id` - The ID of the principal to assign the role to.
  - `description` - (Optional) The description of the role assignment.
  - `skip_service_principal_aad_check` - (Optional) If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.
  - `condition` - (Optional) The condition which will be used to scope the role assignment.
  - `condition_version` - (Optional) The version of the condition syntax. Leave as `null` if you are not using a condition, if you are then valid values are '2.0'.
  - `delegated_managed_identity_resource_id` - (Optional) The delegated Azure Resource Id which contains a Managed Identity. Changing this forces a new resource to be created. This field is only used in cross-tenant scenario.
  - `principal_type` - (Optional) The type of the `principal_id`. Possible values are `User`, `Group` and `ServicePrincipal`. It is necessary to explicitly set this attribute when creating role assignments if the principal creating the assignment is constrained by ABAC rules that filters on the PrincipalType attribute.

  > Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal.
  DESCRIPTION
  nullable    = false
}

# Container App Variables
# ID of the Container App Environment
variable "container_app_environment_id" {
  type        = string
  description = "ID of the Azure Container App Environment."
}

# Revision mode (Single or Multiple)
variable "revision_mode" {
  type        = string
  description = "Revision mode for the container app."
  default     = "Single" #Single or Multiple
}

# Workload Profile
variable "workload_profile_name" {
  type        = string
  description = "Workload profile for the container app. Leave null for a Consumption-only Container App Environment (no workload_profile blocks defined) — Azure rejects any explicit value, including \"Consumption\", in that case. Only set this when the environment actually defines workload profiles."
  default     = null
}

variable "max_inactive_revisions" {
  description = "The maximum of inactive revisions allowed for this Container App."
  type        = number
  default     = 10
}

# Template block - define container specs
variable "template" {
  type = object({
    max_replicas                     = optional(number, 2) #for dev, we will keep at 2
    min_replicas                     = optional(number, 0)
    revision_suffix                  = optional(string, "")
    termination_grace_period_seconds = optional(number, 0)

    container = list(object({
      args    = optional(list(string))
      command = optional(list(string))
      cpu     = number
      image   = string
      memory  = string
      name    = string
      env = optional(list(object({
        name        = string
        secret_name = optional(string)
        value       = optional(string)
      })), [])
      liveness_probe = optional(list(object({
        failure_count_threshold          = optional(number)
        host                             = optional(string)
        initial_delay                    = optional(number)
        interval_seconds                 = optional(number)
        path                             = optional(string)
        port                             = number
        termination_grace_period_seconds = optional(number)
        timeout                          = optional(number)
        transport                        = string
        header = optional(object({
          name  = string
          value = string
        }))
      })), [])
      startup_probe = optional(list(object({
        failure_count_threshold          = optional(number)
        host                             = optional(string)
        initial_delay                    = optional(number)
        interval_seconds                 = optional(number)
        path                             = optional(string)
        port                             = number
        termination_grace_period_seconds = optional(number)
        timeout                          = optional(number)
        transport                        = string
        header = optional(object({
          name  = string
          value = string
        }))
      })), [])
      volume_mounts = optional(list(object({
        name     = string
        path     = string
        sub_path = optional(string)
      })), [])
    }))

    init_container = optional(list(object({
      args    = optional(list(string))
      command = optional(list(string))
      cpu     = optional(number)
      image   = string
      memory  = optional(string)
      name    = string
      env = optional(list(object({
        name        = string
        secret_name = optional(string)
        value       = optional(string)
      })), [])
      volume_mounts = optional(list(object({
        name     = string
        path     = string
        sub_path = optional(string)
      })), [])
    })), [])

    tcp_scale_rule = optional(list(object({
      concurrent_requests = string
      name                = string
      identity            = optional(string)
      metadata            = optional(map(string))
      authentication = optional(object({
        secret_name       = string
        trigger_parameter = optional(string)
      }))
    })), [])

    http_scale_rule = optional(list(object({
      concurrent_requests = string
      name                = string
      identity            = optional(string)
      metadata            = optional(map(string))
      authentication = optional(object({
        secret_name       = string
        trigger_parameter = optional(string)
      }))
    })), [])

    custom_scale_rule = optional(list(object({
      custom_rule_type = string
      metadata         = map(string)
      name             = string
      identity         = optional(string)
      authentication = optional(object({
        secret_name       = string
        trigger_parameter = string
      }))
    })), [])

    volume = optional(list(object({
      mount_options = optional(string)
      name          = string
      secrets = optional(object({
        path        = string
        secret_name = string
      }))
      storage_name = optional(string)
      storage_type = optional(string)
    })), [])
  })
  nullable    = false
  description = <<DESCRIPTION
        - `max_replicas` - (Optional) The maximum number of replicas for this container.
        - `min_replicas` - (Optional) The minimum number of replicas for this container.
        - `revision_suffix` - (Optional) The suffix for the revision. This value must be unique for the lifetime of the Resource. If omitted the service will use a hash function to create one.

        ---
        `azure_queue_scale_rule` block supports the following:
        - `name` - (Required) The name of the Scaling Rule
        - `queue_length` - (Required) The value of the length of the queue to trigger scaling actions.
        - `queue_name` - (Required) The name of the Azure Queue

        ---
        `authentication` block supports the following:
        - `secret_name` - (Required) The name of the Container App Secret to use for this Scale Rule Authentication.
        - `trigger_parameter` - (Required) The Trigger Parameter name to use the supply the value retrieved from the `secret_name`.

        ---
        `containers` block supports the following:
        - `args` - (Optional) A list of extra arguments to pass to the container.
        - `command` - (Optional) A command to pass to the container to override the default. This is provided as a list of command line elements without spaces.
        - `cpu` - (Required) The amount of vCPU to allocate to the container. Possible values include `0.25`, `0.5`, `0.75`, `1.0`, `1.25`, `1.5`, `1.75`, and `2.0`. When there's a workload profile specified, there's no such constraint.
        - `image` - (Required) The image to use to create the container.
        - `memory` - (Required) The amount of memory to allocate to the container. Possible values are `0.5Gi`, `1Gi`, `1.5Gi`, `2Gi`, `2.5Gi`, `3Gi`, `3.5Gi` and `4Gi`. When there's a workload profile specified, there's no such constraint.
        - `name` - (Required) The name of the container

        ---
        `env` block supports the following:
        - `name` - (Required) The name of the environment variable for the container.
        - `secret_name` - (Optional) The name of the secret that contains the value for this environment variable.
        - `value` - (Optional) The value for this environment variable.

        ---
        `liveness_probes` block supports the following:
        - `failure_count_threshold` - (Optional) The number of consecutive failures required to consider this probe as failed. Possible values are between `1` and `10`. Defaults to `3`.
        - `host` - (Optional) The probe hostname. Defaults to the pod IP address. Setting a value for `Host` in `headers` can be used to override this for `HTTP` and `HTTPS` type probes.
        - `initial_delay` - (Optional) The time in seconds to wait after the container has started before the probe is started.
        - `interval_seconds` - (Optional) How often, in seconds, the probe should run. Possible values are in the range `1`
        - `path` - (Optional) The URI to use with the `host` for http type probes. Not valid for `TCP` type probes. Defaults to `/`.
        - `port` - (Required) The port number on which to connect. Possible values are between `1` and `65535`.
        - `timeout` - (Optional) Time in seconds after which the probe times out. Possible values are in the range `1`
        - `transport` - (Required) Type of probe. Possible values are `TCP`, `HTTP`, and `HTTPS`.

        ---
        `header` block supports the following:
        - `name` - (Required) The HTTP Header Name.
        - `value` - (Required) The HTTP Header value.

        ---
        `readiness_probes` block supports the following:
        - `failure_count_threshold` - (Optional) The number of consecutive failures required to consider this probe as failed. Possible values are between `1` and `10`. Defaults to `3`.
        - `host` - (Optional) The probe hostname. Defaults to the pod IP address. Setting a value for `Host` in `headers` can be used to override this for `HTTP` and `HTTPS` type probes.
        - `initial_delay` - (Optional) The number of seconds elapsed after the container has started before the probe is initiated. Possible values are between `0` and `60`. Defaults to `0` seconds.
        - `interval_seconds` - (Optional) How often, in seconds, the probe should run. Possible values are between `1` and `240`. Defaults to `10`
        - `path` - (Optional) The URI to use for http type probes. Not valid for `TCP` type probes. Defaults to `/`.
        - `port` - (Required) The port number on which to connect. Possible values are between `1` and `65535`.
        - `success_count_threshold` - (Optional) The number of consecutive successful responses required to consider this probe as successful. Possible values are between `1` and `10`. Defaults to `3`.
        - `timeout` - (Optional) Time in seconds after which the probe times out. Possible values are in the range `1`
        - `transport` - (Required) Type of probe. Possible values are `TCP`, `HTTP`, and `HTTPS`.

        ---
        `header` block supports the following:
        - `name` - (Required) The HTTP Header Name.
        - `value` - (Required) The HTTP Header value.

        ---
        `startup_probes` block supports the following:
        - `failure_count_threshold` - (Optional) The number of consecutive failures required to consider this probe as failed. Possible values are between `1` and `10`. Defaults to `3`.
        - `host` - (Optional) The value for the host header which should be sent with this probe. If unspecified, the IP Address of the Pod is used as the host header. Setting a value for `Host` in `headers` can be used to override this for `HTTP` and `HTTPS` type probes.
        - `initial_delay` - (Optional) The number of seconds elapsed after the container has started before the probe is initiated. Possible values are between `0` and `60`. Defaults to `0` seconds.
        - `interval_seconds` - (Optional) How often, in seconds, the probe should run. Possible values are between `1` and `240`. Defaults to `10`
        - `path` - (Optional) The URI to use with the `host` for http type probes. Not valid for `TCP` type probes. Defaults to `/`.
        - `port` - (Required) The port number on which to connect. Possible values are between `1` and `65535`.
        - `timeout` - (Optional) Time in seconds after which the probe times out. Possible values are in the range `1`
        - `transport` - (Required) Type of probe. Possible values are `TCP`, `HTTP`, and `HTTPS`.

        ---
        `header` block supports the following:
        - `name` - (Required) The HTTP Header Name.
        - `value` - (Required) The HTTP Header value.

        ---
        `volume_mounts` block supports the following:
        - `name` - (Required) The name of the Volume to be mounted in the container.
        - `path` - (Required) The path in the container at which to mount this volume.

        ---
        `custom_scale_rule` block supports the following:
        - `custom_rule_type` - (Required) The Custom rule type. Possible values include: `activemq`, `artemis-queue`, `kafka`, `pulsar`, `aws-cloudwatch`, `aws-dynamodb`, `aws-dynamodb-streams`, `aws-kinesis-stream`, `aws-sqs-queue`, `azure-app-insights`, `azure-blob`, `azure-data-explorer`, `azure-eventhub`, `azure-log-analytics`, `azure-monitor`, `azure-pipelines`, `azure-servicebus`, `azure-queue`, `cassandra`, `cpu`, `cron`, `datadog`, `elasticsearch`, `external`, `external-push`, `gcp-stackdriver`, `gcp-storage`, `gcp-pubsub`, `graphite`, `http`, `huawei-cloudeye`, `ibmmq`, `influxdb`, `kubernetes-workload`, `liiklus`, `memory`, `metrics-api`, `mongodb`, `mssql`, `mysql`, `nats-jetstream`, `stan`, `tcp`, `new-relic`, `openstack-metric`, `openstack-swift`, `postgresql`, `predictkube`, `prometheus`, `rabbitmq`, `redis`, `redis-cluster`, `redis-sentinel`, `redis-streams`, `redis-cluster-streams`, `redis-sentinel-streams`, `selenium-grid`,`solace-event-queue`, and `github-runner`.
        - `metadata` - (Required)
        - `name` - (Required) The name of the Scaling Rule

        ---
        `authentication` block supports the following:
        - `secret_name` - (Required) The name of the Container App Secret to use for this Scale Rule Authentication.
        - `trigger_parameter` - (Required) The Trigger Parameter name to use the supply the value retrieved from the `secret_name`.

        ---
        `http_scale_rule` block supports the following:
        - `concurrent_requests` - (Required)
        - `name` - (Required) The name of the Scaling Rule

        ---
        `authentication` block supports the following:
        - `secret_name` - (Required) The name of the Container App Secret to use for this Scale Rule Authentication.
        - `trigger_parameter` - (Required) The Trigger Parameter name to use the supply the value retrieved from the `secret_name`.

        ---
        `init_container` block supports the following:
        - `args` - (Optional) A list of extra arguments to pass to the container.
        - `command` - (Optional) A command to pass to the container to override the default. This is provided as a list of command line elements without spaces.
        - `cpu` - (Optional) The amount of vCPU to allocate to the container. Possible values include `0.25`, `0.5`, `0.75`, `1.0`, `1.25`, `1.5`, `1.75`, and `2.0`. When there's a workload profile specified, there's no such constraint.
        - `image` - (Required) The image to use to create the container.
        - `memory` - (Optional) The amount of memory to allocate to the container. Possible values are `0.5Gi`, `1Gi`, `1.5Gi`, `2Gi`, `2.5Gi`, `3Gi`, `3.5Gi` and `4Gi`. When there's a workload profile specified, there's no such constraint.
        - `name` - (Required) The name of the container

        ---
        `env` block supports the following:
        - `name` - (Required) The name of the environment variable for the container.
        - `secret_name` - (Optional) The name of the secret that contains the value for this environment variable.
        - `value` - (Optional) The value for this environment variable.

        ---
        `volume_mounts` block supports the following:
        - `name` - (Required) The name of the Volume to be mounted in the container.
        - `path` - (Required) The path in the container at which to mount this volume.

        ---
        `tcp_scale_rule` block supports the following:
        - `concurrent_requests` - (Required)
        - `name` - (Required) The name of the Scaling Rule

        ---
        `authentication` block supports the following:
        - `secret_name` - (Required) The name of the Container App Secret to use for this Scale Rule Authentication.
        - `trigger_parameter` - (Required) The Trigger Parameter name to use the supply the value retrieved from the `secret_name`.

        ---
        `volume` block supports the following:
        - `name` - (Required) The name of the volume.
        - `storage_name` - (Optional) The name of the `AzureFile` storage.
        - `storage_type` - (Optional) The type of storage volume. Possible values are `AzureFile`, `EmptyDir` and `Secret`. Defaults to `EmptyDir`.
    DESCRIPTION
}

# Optional Identity block
variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
  Controls the Managed Identity configuration on this resource. The following properties can be specified:

  - `system_assigned` - (Optional) Specifies if the System Assigned Managed Identity should be enabled.
  - `user_assigned_resource_ids` - (Optional) Specifies a list of User Assigned Managed Identity resource IDs to be assigned to this resource.
  DESCRIPTION
  nullable    = false
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
    }), null)
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

# Optional: Container registry credentials
variable "registry" {
  description = "Optional list of container registries."
  type = list(object({
    server               = string
    username             = optional(string, "")
    password_secret_name = optional(string, "")
    identity             = optional(string, "")
  }))
  default = []
}

# Optional: Secrets
variable "secret" {
  description = "Optional secrets for the container app."
  type = map(object({
    name                = optional(string)     # Secret name
    value               = optional(string, "") # Inline secret value
    identity            = optional(string, "") # User Assigned Identity or "System"
    key_vault_secret_id = optional(string, "") # Full Key Vault secret ID
  }))
  default = {}
}
