
resource "azurerm_virtual_network" "vnet-1" {
  name                = "${var.resource_prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_prefix
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "snet-1" {
  name                 = "${var.resource_prefix}-subnet"
  resource_group_name  = var.resource_prefix
  virtual_network_name = azurerm_virtual_network.vnet-1.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "nsg-1" {
  name                = "${var.resource_prefix}-nsg"
  location            = var.location
  resource_group_name = var.resource_prefix
}

# 追加 VNet
resource "azurerm_virtual_network" "vnet-2" {
  name                = "${var.resource_prefix}-vnet-check"
  location            = var.location
  resource_group_name = var.resource_prefix
  address_space       = ["10.2.0.0/16"]
}

resource "azurerm_subnet" "snet-2" {
  name                 = "${var.resource_prefix}-subnet-check"
  resource_group_name  = var.resource_prefix
  virtual_network_name = azurerm_virtual_network.vnet-2.name
  address_prefixes     = ["10.2.1.0/24"]
}

# NSG とルール
resource "azurerm_network_security_group" "nsg-2" {
  name                = "${var.resource_prefix}-nsg-check"
  location            = var.location
  resource_group_name = var.resource_prefix

  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc_check" {
  subnet_id                 = azurerm_subnet.snet-2.id
  network_security_group_id = azurerm_network_security_group.nsg-2.id
}

# ルートテーブル（任意のルート設定）
resource "azurerm_route_table" "rt_check" {
  name                = "${var.resource_prefix}-rt-check"
  location            = var.location
  resource_group_name = var.resource_prefix
}

resource "azurerm_subnet_route_table_association" "rt_assoc_check" {
  subnet_id      = azurerm_subnet.snet-2.id
  route_table_id = azurerm_route_table.rt_check.id
}

# Private DNS Zone（仮に blob.core.windows.net を名前解決する想定）
resource "azurerm_private_dns_zone" "blob_dns_zone" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_prefix
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_link_check" {
  name                  = "${var.resource_prefix}-dnslink-check"
  resource_group_name   = var.resource_prefix
  private_dns_zone_name = azurerm_private_dns_zone.blob_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet-2.id
  registration_enabled  = false
}

# NIC
resource "azurerm_network_interface" "nic_check" {
  name                = "${var.resource_prefix}-nic-check"
  location            = var.location
  resource_group_name = var.resource_prefix

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet-2.id
    private_ip_address_allocation = "Dynamic"
  }
}

# 確認用VM（Ubuntu）
resource "azurerm_linux_virtual_machine" "vm_check" {
  name                = "check-vm"
  resource_group_name = var.resource_prefix
  location            = var.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.nic_check.id
  ]
  admin_ssh_key {
    username   = "azureuser"
    public_key = file("${var.vm_admin_ssh_key}")
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "check-osdisk"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}