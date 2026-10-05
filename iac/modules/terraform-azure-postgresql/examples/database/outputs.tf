output "postgresql_server_fqdn" {
  value       = module.pgsql.postgresql_server_fqdn
  description = "The fully qualified domain name of the PostgreSQL Flexible Server."
}