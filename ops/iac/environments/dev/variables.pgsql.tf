variable "pgsql_public_network_access_enabled" {
  type        = bool
  default     = false
  description = "(Optional) Whether the server is publicly accessible.  Defaults to `false`."
}

variable "sku_name" {
  type        = string
  default     = null
  description = "(Optional) The SKU Name for the PostgreSQL Flexible Server. The name of the SKU, follows the `tier` + `name` pattern (e.g. `B_Standard_B1ms`, `GP_Standard_D2s_v3`, `MO_Standard_E4s_v3`). Note: High availability is not supported for Burstable SKUs (those with the `B_` prefix). When using a Burstable SKU, set `high_availability` to `null`."
}

variable "server_version" {
  type        = string
  default     = null
  description = "(Optional) The version of PostgreSQL Flexible Server to use. Possible values are `11`,`12`, `13`, `14`, `15`, `16`, `17`, and `18`. Required when `create_mode` is `Default`."
}

variable "storage_mb" {
  type        = number
  default     = null
  description = "(Optional) The max storage allowed for the PostgreSQL Flexible Server. Possible values are `32768`, `65536`, `131072`, `262144`, `524288`, `1048576`, `2097152`, `4193280`, `4194304`, `8388608`, `16777216` and `33553408`."
}

variable "storage_tier" {
  type        = string
  default     = null
  description = "(Optional) The storage tier for the PostgreSQL Flexible Server. Possible values are `P4`, `P6`, `P10`, `P15`, `P20`, `P30`, `P40`, `P50`, `P60`, `P70` or `P80`."

  validation {
    condition     = var.storage_tier != null ? contains(["P4", "P6", "P10", "P15", "P20", "P30", "P40", "P50", "P60", "P70", "P80"], var.storage_tier) : true
    error_message = "The storage_tier must be one of the following values: P4, P6, P10, P15, P20, P30, P40, P50, P60, P70, P80."
  }
}