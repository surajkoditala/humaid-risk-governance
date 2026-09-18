# These are only examples to showcase how to refer the outputs; not needed to declare in the resource provisioning module; will be used for CAs env values
output "PE_Name" {
  value = module.keyvault.key_vault_private_end_point_name["kv_pe_name"]
}

output "PE_ID" {
  value = module.keyvault.key_vault_private_end_point_id["kv_pe_id"]
}

output "PEs" {
  value = module.keyvault.key_vault_private_endpoints
}