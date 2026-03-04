variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "key_vault_name_prefix" {
  description = "Prefix for Key Vault name (suffix is auto-generated)"
  type        = string
  default     = "kvfilesync"

  validation {
    condition     = can(regex("^[a-z0-9]{3,18}$", var.key_vault_name_prefix))
    error_message = "key_vault_name_prefix must be 3-18 chars, lowercase letters and digits only."
  }
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "filesync"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "japaneast"
}

variable "vnet_cidr" {
  description = "VNet CIDR"
  type        = string
  default     = "10.30.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet CIDR"
  type        = string
  default     = "10.30.1.0/24"
}

variable "admin_username" {
  description = "Windows VM admin username"
  type        = string
  default     = "azureuser"
}

variable "admin_password_secret_name" {
  description = "Key Vault secret name to store generated VM admin password"
  type        = string
  default     = "filesync-vm-admin-password"
}

variable "admin_password_length" {
  description = "Length of generated VM admin password"
  type        = number
  default     = 20

  validation {
    condition     = var.admin_password_length >= 12
    error_message = "admin_password_length must be at least 12."
  }
}

variable "password_rotation_token" {
  description = "Change this value to rotate generated VM admin password"
  type        = string
  default     = "initial"
}

variable "vm_size" {
  description = "VM size (cost optimized default)"
  type        = string
  default     = "Standard_B2s"
}

variable "data_disk_size_gb" {
  description = "Data disk size for Azure File Sync server endpoint volume (GB)"
  type        = number
  default     = 128
}

variable "file_share_name" {
  description = "Azure Files share name"
  type        = string
  default     = "shared"
}

variable "file_share_quota_gb" {
  description = "Share quota (GB)"
  type        = number
  default     = 100
}

variable "storage_sync_service_name" {
  description = "Storage Sync Service name"
  type        = string
  default     = "filesync-svc"
}

variable "storage_sync_group_name" {
  description = "Storage Sync Group name"
  type        = string
  default     = "filesync-group"
}

variable "storage_sync_cloud_endpoint_name" {
  description = "Cloud Endpoint name"
  type        = string
  default     = "filesync-cloud-endpoint"
}

variable "server_endpoint_local_path" {
  description = "Local Windows path to be used as Server Endpoint"
  type        = string
  default     = "F:\\AFSData"
}

variable "afs_agent_download_url" {
  description = "Azure File Sync Agent MSI download URL"
  type        = string
  default     = ""
}

variable "registered_server_ids" {
  description = "Map of server endpoint key to registered server id. Example: { vm1 = \"/subscriptions/.../registeredServers/...\", vm2 = \"...\" }"
  type        = map(string)
  default     = {}
}
