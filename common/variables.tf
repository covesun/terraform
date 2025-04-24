
variable "location" {
  description = "Azure リージョン名"
  type        = string
  default     = "japaneast"
}

variable "resource_prefix" {
  description = "リソース名に付与するプレフィックス"
  type        = string
  default     = "example"
}

variable "vm_admin_ssh_key" {
  description = "VM用SSH公開鍵ファイルのパス"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
