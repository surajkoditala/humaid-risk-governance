output "name" {
  description = "The name of the parent resource."
  value       = module.containerregistry.name
}

output "resource_id" {
  description = "The resource id for the parent resource."
  value       = module.containerregistry.resource_id
}

output "system_assigned_mi_principal_id" {
  description = "The system assigned managed identity principal ID of the parent resource."
  value       = module.containerregistry.system_assigned_mi_principal_id
}