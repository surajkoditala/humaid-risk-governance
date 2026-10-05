variable "firewall_rules" {
  type = map(object({
    name             = optional(string)
    start_ip_address = optional(string)
    end_ip_address   = optional(string)
  }))
  default     = {}
  description = <<-EOT
 - `name` - (Optional) The name which should be used for this PostgreSQL Flexible Server Firewall Rule.  
 - `start_ip_address` - (Optional) The Start IP Address associated with this PostgreSQL Flexible Server Firewall Rule.  
 - `end_ip_address` - (Optional) The End IP Address associated with this PostgreSQL Flexible Server Firewall Rule. 

 `eg.`
   firewall_rules = {
    rule1 = {
      name             = "AllowAllFireWallRule"
      start_ip_address = "0.0.0.0"
      end_ip_address   = "255.255.255.255"
    }
  }  
EOT
}