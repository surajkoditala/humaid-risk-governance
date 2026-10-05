output "resource_group_id" {
  description = "The ID of the resource group"
  value       = module.rg.resource_group_id
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = module.rg.resource_group_name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = module.rg.resource_group_location
}
