provider "azurerm" {
  features {}
}

locals {
  location = "japaneast"
}

resource "azurerm_resource_group" "ca" {
  name     = "rg-ca-demo"
  location = local.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-ca-demo"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.ca.location
  resource_group_name = azurerm_resource_group.ca.name
}

resource "azurerm_subnet" "cae" {
  name                 = "snet-ca-env"
  resource_group_name  = azurerm_resource_group.ca.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/21"]
  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-ca-pe"
  resource_group_name  = azurerm_resource_group.ca.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.16.0/28"]
  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.Network/privateEndpoints"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_container_app_environment" "cae" {
  name                            = "ca-env-demo"
  location                        = azurerm_resource_group.ca.location
  resource_group_name             = azurerm_resource_group.ca.name
  infrastructure_subnet_id        = azurerm_subnet.cae.id
  internal_load_balancer_enabled  = true # Private Ingress
  zone_redundant                  = true

  workload_profile {
    name                  = "consumption"
    workload_profile_type = "Consumption"
    min_count             = 0
    max_count             = 10
  }
}

resource "azurerm_container_app" "nginx" {
  name                         = "ca-demo-nginx"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = azurerm_resource_group.ca.name
  location                     = azurerm_resource_group.ca.location
  revision_mode                = "Single"

  workload_profile_name        = "consumption" # ←ココが「従量課金ワークロード」指定

  template {
    container {
      name   = "nginx"
      image  = "nginx:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
    scale {
      min_replicas = 0
      max_replicas = 3
      rules {
        name = "http-rule"
        custom {
          type = "http"
          metadata = {
            concurrentRequests = "50"
          }
        }
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 80
    transport        = "auto"
  }
}

# Functionランタイム・Python版も同様に↓
resource "azurerm_container_app" "func" {
  name                         = "ca-demo-func"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = azurerm_resource_group.ca.name
  location                     = azurerm_resource_group.ca.location
  revision_mode                = "Single"

  workload_profile_name        = "consumption"

  template {
    container {
      name   = "func-python"
      image  = "mcr.microsoft.com/azure-functions/python:4-python3.11"
      cpu    = 0.25
      memory = "0.5Gi"
    }
    scale {
      min_replicas = 0
      max_replicas = 3
      rules {
        name = "http-rule"
        custom {
          type = "http"
          metadata = {
            concurrentRequests = "50"
          }
        }
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 80
    transport        = "auto"
  }
}

# Private Endpoint（CAE環境対象）
resource "azurerm_private_endpoint" "cae_pe" {
  name                = "pe-ca-env"
  location            = azurerm_resource_group.ca.location
  resource_group_name = azurerm_resource_group.ca.name
  subnet_id           = azurerm_subnet.pe.id

  private_service_connection {
    name                           = "psc-ca-env"
    private_connection_resource_id  = azurerm_container_app_environment.cae.id
    subresource_names              = ["environment"]
    is_manual_connection           = false
  }
}

resource "azurerm_private_dns_zone" "ca" {
  name                = "privatelink.azurecontainerapps.io"
  resource_group_name = azurerm_resource_group.ca.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "ca" {
  name                  = "ca-vnet-link"
  resource_group_name   = azurerm_resource_group.ca.name
  private_dns_zone_name = azurerm_private_dns_zone.ca.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

# Aレコード追加は通常不要（自動登録）。手動で追加したい場合だけ下記：
# resource "azurerm_private_dns_a_record" "cae" {
#   name                = azurerm_container_app_environment.cae.name
#   zone_name           = azurerm_private_dns_zone.ca.name
#   resource_group_name = azurerm_resource_group.ca.name
#   ttl                 = 300
#   records             = [azurerm_private_endpoint.cae_pe.private_service_connection[0].private_ip_address]
# }

