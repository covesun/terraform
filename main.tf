terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.24.0"
    }
  }
}
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
#module "common" {
#  source = "./common"
#  location = var.location
#  resource_prefix = var.resource_prefix
#  vm_admin_ssh_key = var.vm_admin_ssh_key
#}

module "pgadmin_test" {
  source = "./pgadmin_test"
  vpn_client_root_cert_pem = var.vpn_client_root_cert_pem
}