#Resource level lock (Optional)
#Use this only for higherlevel environment (like prod) as necessary
resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  lock_level = var.lock.kind
  name       = coalesce(var.lock.name, "lock-ca-${var.tags.product}-${var.tags.environment}-${local.user_preferred_index}")
  scope      = azurerm_container_app.this.id
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
}

#----------role assignment settings for the container app -----------
resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = each.value.scope != null ? each.value.scope : azurerm_container_app.this.id
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  principal_type                         = each.value.principal_type
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}

#Container APP
resource "azurerm_container_app" "this" {
  name                         = var.name != null ? var.name : "ca-${var.container_app_service_name}-${var.tags.environment}"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = var.revision_mode
  workload_profile_name        = var.workload_profile_name
  max_inactive_revisions       = var.max_inactive_revisions
  tags                         = merge(local.default_tags, var.tags)

  lifecycle {
    ignore_changes = [
      template[0].container[0].image, #Terraform will ignore the changes on the image attribute
      template[0].container[1].image, #Ignore_changes doesn’t validate whether that exact index exists in the current resource state — it just treats those paths as “things to ignore if they exist.”
      template[0].container[2].image,
      template[0].init_container[0].image,
      template[0].init_container[1].image
    ]
  }

  template {
    max_replicas                     = var.template.max_replicas
    min_replicas                     = var.template.min_replicas
    revision_suffix                  = var.template.revision_suffix
    termination_grace_period_seconds = var.template.termination_grace_period_seconds

    dynamic "container" {
      for_each = var.template.container #{ for c in var.template.container : c.name => c } : {}
      content {
        name   = container.value.name
        image  = container.value.image
        cpu    = container.value.cpu
        memory = "${container.value.memory}Gi"
        dynamic "env" {
          for_each = container.value.env
          content {
            name        = env.value.name
            secret_name = env.value.secret_name
            value       = env.value.value
          }
        }
        dynamic "liveness_probe" {
          for_each = container.value.liveness_probe
          content {
            path      = liveness_probe.value.path
            port      = liveness_probe.value.port
            transport = liveness_probe.value.transport
          }
        }
        dynamic "startup_probe" {
          for_each = container.value.startup_probe
          content {
            path      = startup_probe.value.path
            port      = startup_probe.value.port
            transport = startup_probe.value.transport
          }
        }
        dynamic "volume_mounts" {
          for_each = container.value.volume_mounts
          content {
            name = volume_mounts.value.name
            path = volume_mounts.value.path
          }
        }
      }
    }

    dynamic "init_container" {
      for_each = var.template.init_container
      content {
        name   = init_container.value.name
        image  = init_container.value.image
        cpu    = init_container.value.cpu
        memory = "${init_container.value.memory}Gi"
        dynamic "env" {
          for_each = init_container.value.env
          content {
            name        = env.value.name
            secret_name = env.value.secret_name
            value       = env.value.value
          }
        }
      }
    }

    dynamic "tcp_scale_rule" {
      for_each = var.template.tcp_scale_rule
      content {
        name                = tcp_scale_rule.value.name
        concurrent_requests = tcp_scale_rule.value.concurrent_requests
      }
    }

    dynamic "http_scale_rule" {
      for_each = var.template.http_scale_rule
      content {
        name                = http_scale_rule.value.name
        concurrent_requests = http_scale_rule.value.concurrent_requests
      }
    }

    dynamic "custom_scale_rule" {
      for_each = var.template.custom_scale_rule
      content {
        name             = custom_scale_rule.value.name
        custom_rule_type = custom_scale_rule.value.custom_rule_type
        metadata         = custom_scale_rule.value.metadata
      }
    }

    dynamic "volume" {
      for_each = var.template.volume
      content {
        name = volume.value.name
      }
    }
  }

  dynamic "identity" {
    for_each = (var.managed_identities.system_assigned || length(var.managed_identities.user_assigned_resource_ids) > 0) ? { this = var.managed_identities } : {}

    content {
      type         = identity.value.system_assigned && length(identity.value.user_assigned_resource_ids) > 0 ? "SystemAssigned, UserAssigned" : length(identity.value.user_assigned_resource_ids) > 0 ? "UserAssigned" : "SystemAssigned"
      identity_ids = identity.value.user_assigned_resource_ids
    }
  }

  ingress {
    external_enabled           = var.ingress.external_enabled
    target_port                = var.ingress.target_port
    allow_insecure_connections = var.ingress.allow_insecure_connections
    exposed_port               = var.ingress.exposed_port
    transport                  = var.ingress.transport
    client_certificate_mode    = var.ingress.client_certificate_mode

    dynamic "cors" {
      for_each = var.ingress.cors != null ? [var.ingress.cors] : []
      content {
        allowed_origins    = cors.value.allowed_origins
        allowed_methods    = cors.value.allowed_methods
        allowed_headers    = cors.value.allowed_headers
        exposed_headers    = cors.value.exposed_headers
        max_age_in_seconds = cors.value.max_age_in_seconds
      }
    }

    dynamic "traffic_weight" {
      for_each = var.ingress.traffic_weight
      content {
        percentage      = traffic_weight.value.percentage
        label           = traffic_weight.value.label
        revision_suffix = traffic_weight.value.revision_suffix
        latest_revision = traffic_weight.value.latest_revision
      }
    }
  }

  dynamic "registry" {
    for_each = var.registry
    content {
      server               = registry.value.server
      identity             = registry.value.identity
      username             = registry.value.username
      password_secret_name = registry.value.password_secret_name
    }
  }

  dynamic "secret" {
    for_each = var.secret
    content {
      name                = secret.value.name
      value               = secret.value.key_vault_secret_id != "" ? "" : secret.value.value
      identity            = secret.value.key_vault_secret_id == "" ? "" : secret.value.identity
      key_vault_secret_id = secret.value.key_vault_secret_id
    }
  }

}