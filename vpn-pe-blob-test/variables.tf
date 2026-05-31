variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD Tenant ID (used for P2S VPN AAD auth and RBAC)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "japaneast"
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "vpnpe"
}

variable "vpn_client_address_pool" {
  description = "Address pool assigned to P2S VPN clients"
  type        = string
  default     = "172.16.0.0/24"
}

# Object ID of the user/group to grant Storage Blob Data Reader on the storage account
# Get with: az ad signed-in-user show --query id -o tsv
variable "blob_reader_object_id" {
  description = "Entra ID Object ID of the user or group to grant Blob access (for Storage Explorer)"
  type        = string
}
