output "name" {
  description = "The name of the parent resource."
  value       = module.containerregistry.name
}

output "resource_id" {
  description = "The resource id for the parent resource."
  value       = module.containerregistry.resource_id
}