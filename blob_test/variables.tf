
variable "location" {
  type    = string
  default = "japaneast"
}

variable "resource_prefix" {
  type    = string
  default = "example"
}

variable "vm_admin_ssh_key" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}
