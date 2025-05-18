# Terraform configuration to deploy pgAdmin on Azure Container Apps
# with VNet integration, Azure PostgreSQL Flexible Server, and P2S VPN (certificate auth)

variable "resource_group" {
  default = "rg-pgadmin"
}

variable "location" {
  default = "japaneast"
}

variable "vnet_name" {
  default = "vnet-pgadmin"
}

variable "subnet_name" {
  default = "snet-containerapps"
}

variable "pgadmin_admin_email" {
  default = "admin@pgadmin.com"
}

variable "pgadmin_admin_password" {
  default = "P@ssword123!"
}

variable "postgres_admin_username" {
  default = "pgadmin"
}

variable "postgres_admin_password" {
  default = "P@ssw0rdpg!"
}

variable "vpn_client_root_cert_name" {
  default = "PHomeCert"
}

variable "vpn_client_root_cert_pem" {
  description = "Base64-encoded root certificate content (public part only)"
  default     = "<your-root-cert-pem>"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet_containerapps" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "subnet_postgres" {
  name                 = "snet-postgres"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "subnet_gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.255.0/27"]
}

resource "azurerm_public_ip" "vpn_pip" {
  name                = "pip-vpn"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

resource "azurerm_virtual_network_gateway" "vpn_gw" {
  name                = "vpngw-pgadmin"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  enable_bgp          = false

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_pip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.subnet_gateway.id
  }

  sku                 = "Basic"

  vpn_client_configuration {
    address_space = ["172.16.201.0/24"]

    root_certificate {
      name             = var.vpn_client_root_cert_name
      public_cert_data = var.vpn_client_root_cert_pem
    }
  }
}



# Note:
# - 自己署名証明書を作成するには：
#     openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes
# - cert.pem の Base64 部分を var.vpn_client_root_cert_pem に設定する
# - クライアントPCでは Azure VPN Client を使用し、xml構成ファイルを自作 or Azure Portalでダウンロード

# あと必要なのは DNS (private.postgres.database.azure.com) の Private DNS Zone と link やな
