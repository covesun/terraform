variable "subscription_id" {
  default = ""  
}

variable "mod_containerapps_test" {
  default = false
}

variable "location" {
  default = ""
}

variable "resource_group_name" {
  default = ""
}

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

resource "azurerm_resource_group" "rg" {
  name      = var.resource_group_name
  location  = var.location
}

module "containerapps-test" {
  count               = var.mod_containerapps_test ? 1 : 0
  source              = "../containerapps-test"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}