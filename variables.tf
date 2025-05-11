variable "subscription_id" {
  description = "サブスクリプションID"
  type        = string
  default     = ""
}

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

variable "storage_account_name" {
  description = "バックエンド用ストレージアカウント"
  type        = string
  default     = "st"
}
variable "container_name" {
  description = "バックエンド用コンテナ名"
  type        = string
  default     = "tfstate"
}
variable "key" {
  description = "ステートファイル名"
  type        = string
  default     = "test.tfstate"
}