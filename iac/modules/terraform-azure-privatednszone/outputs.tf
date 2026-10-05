output "private_dns_zone_resource_id" {
  description = "This is the resource id of the Private DNS Zone"
  value       = azurerm_private_dns_zone.this.id
}