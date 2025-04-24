
terraform {
  backend "azurerm" {
    resource_group_name  = "example-rg"
    storage_account_name = "examplestorage"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
