variable "location" {
  description = "Azure region where the resource group will be created"
  type        = string
  nullable    = false
  default     = "eastus2"
}

variable "enable_lock" {
  description = "Enable or disable the lock on the resource group"
  type        = bool
  default     = true
}

variable "lock_level" {
  description = "Lock level for the resource group. Possible values are CanNotDelete and ReadOnly"
  type        = string
  default     = "CanNotDelete"
}