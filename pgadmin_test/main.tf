# Terraform configuration to deploy pgAdmin on Azure Container Apps
# with VNet integration, Azure PostgreSQL Flexible Server, and P2S VPN (certificate auth)

variable "resource_group" {
  default = "rg-pgadmin"
}

variable "location" {
  default = "japaneast"
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

locals {
  resolved_root_cert = file("pem/rootcert.pem")
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group
  location = var.location
}

#################### Vnet ####################
resource "azurerm_virtual_network" "vnet-frontend" {
  name                = "vnet-frontend"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_virtual_network" "vnet-management" {
  name                = "vnet-management"
  address_space       = ["10.1.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_virtual_network" "vnet-database" {
  name                = "vnet-database"
  address_space       = ["10.2.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_virtual_network" "vnet-functions" {
  name                = "vnet-functions"
  address_space       = ["10.3.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_virtual_network" "vnet-container" {
  name                = "vnet-container"
  address_space       = ["10.4.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

#################### Subnet ####################
resource "azurerm_subnet" "snet-gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet-management.name
  address_prefixes     = ["10.1.255.0/27"]
}

resource "azurerm_subnet" "snet-pgadmin" {
  name                 = "snet-pgadmin"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet-management.name
  address_prefixes     = ["10.1.1.0/24"]

  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "snet-postgres" {
  name                 = "snet-postgres"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet-database.name
  address_prefixes     = ["10.2.0.0/24"]

  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

#################### Private IP ####################
resource "azurerm_public_ip" "pip-vpn" {
  name                = "pip-vpn"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

#################### VGW ####################
resource "azurerm_virtual_network_gateway" "vpngw-pgadmin" {
  name                = "vpngw-pgadmin"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  enable_bgp          = false

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.pip-vpn.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.snet-gateway.id
  }

  sku                 = "Basic"

  vpn_client_configuration {
    address_space = ["172.16.201.0/24"]

    root_certificate {
      name             = var.vpn_client_root_cert_name
      public_cert_data = local.resolved_root_cert
    }
  }
}

# Note:
# - 自己署名証明書を作成するには：
#     openssl req -x509 -newkey rsa:2048 -keyout rootkey.pem -out rootcert.pem -days 365 -nodes -subj "/CN=pgadminvpn"
#     openssl pkcs12 -export -inkey rootkey.pem -in rootcert.pem -out clientcert.pfx
#     パスワードを設定（Azure　VPN Client設定時に必要）

#     ルート証明書の-----BEGIN CERTIFICATE-----と-----END CERTIFICATE-----は削除しないとエラーになる
# - cert.pem の Base64 部分を var.vpn_client_root_cert_pem に設定する
# - クライアントPCでは Azure VPN Client を使用し、xml構成ファイルを自作 or Azure Portalでダウンロード

# あと必要なのは DNS (private.postgres.database.azure.com) の Private DNS Zone と link やな

#################### Private DNS Zone ####################
resource "azurerm_private_dns_zone" "pdz-postgres" {
  name                = "private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone" "pdz-pgadmin" {
  name                = "private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dl-postgres" {
  name                  = "dnslink-postgres"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.pdz-postgres.name
  virtual_network_id    = azurerm_virtual_network.vnet-frontend.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "dl-pgadmin" {
  name                  = "dnslink-pgadmin"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.pdz-pgadmin.name
  virtual_network_id    = azurerm_virtual_network.vnet-frontend.id
  registration_enabled  = false
}

#################### Database for PostgreSQL Flexiable Server ####################
resource "azurerm_postgresql_flexible_server" "psql-test" {
  name                   = "psql-test"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = var.location
  version                = "13"
  administrator_login    = var.postgres_admin_username
  administrator_password = var.postgres_admin_password
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"
  delegated_subnet_id    = azurerm_subnet.snet-postgres.id
  private_dns_zone_id    = azurerm_private_dns_zone.pdz-postgres.id
  zone                   = "1"
}

#################### Container Apps Environment ####################
resource "azurerm_container_app_environment" "cae-pgadmin" {
  name                       = "cae-pgadmin"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg.name
  infrastructure_subnet_id   = azurerm_subnet.snet-pgadmin.id
}

#################### Container Apps ####################
resource "azurerm_container_app" "ca-pgadmin" {
  name                         = "ca-pgadmin"
  container_app_environment_id = azurerm_container_app_environment.cae-pgadmin.id
  resource_group_name          = azurerm_resource_group.rg.name
  #location                     = var.location
  revision_mode               = "Single"

  template {
    container {
      name   = "pgadmin"
      image  = "dpage/pgadmin4:latest"
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "PGADMIN_DEFAULT_EMAIL"
        value = var.pgadmin_admin_email
      }
      env {
        name  = "PGADMIN_DEFAULT_PASSWORD"
        value = var.pgadmin_admin_password
      }
    }
  }

  ingress {
    external_enabled = false
    target_port      = 80
    traffic_weight {
      latest_revision = true
      percentage = 100
    }
  }

  identity {
    type = "SystemAssigned"
  }
}
