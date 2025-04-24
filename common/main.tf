
resource "azurerm_virtual_network" "example_vnet" {
  name                = "${var.resource_prefix}-vnet"
  location            = var.location
  resource_group_name = "example-rg"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "example_subnet" {
  name                 = "${var.resource_prefix}-subnet"
  resource_group_name  = "example-rg"
  virtual_network_name = azurerm_virtual_network.example_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "example_nsg" {
  name                = "${var.resource_prefix}-nsg"
  location            = var.location
  resource_group_name = "example-rg"
}
