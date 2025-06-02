variable "location" {
  default = ""
}

variable "resource_group_name" {
  default = ""
}

resource "azurerm_virtual_network" "vnet-container" {
  name                = "vnet-container"
  address_space       = ["10.4.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "snet-consonly" {
  name                 = "snet-consonly"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet-container.name
  address_prefixes     = ["10.4.0.0/23"]
}

resource "azurerm_subnet" "snet-conswkld" {
  name                 = "snet-conswkld"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet-container.name
  address_prefixes     = ["10.4.8.0/27"]
  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "snet-conswkld-vnet-int" {
  name                 = "snet-conswkld-vnet-int"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet-container.name
  address_prefixes     = ["10.4.8.32/27"]
  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "snet-pe" {
  name                 = "snet-pe"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet-container.name
  address_prefixes     = ["10.4.16.0/29"]
}

resource "azurerm_container_app_environment" "cae-pri-consonly" {
  name                            = "cae-pri-consonly"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  infrastructure_subnet_id        = azurerm_subnet.snet-consonly.id
  internal_load_balancer_enabled  = true # Private Ingress
  zone_redundancy_enabled         = true
}

resource "azurerm_container_app_environment" "cae-pri-conswkld" {
  name                                = "cae-pri-conswkld"
  location                            = var.location
  resource_group_name                 = var.resource_group_name
  infrastructure_resource_group_name  = var.resource_group_name
  infrastructure_subnet_id            = azurerm_subnet.snet-conswkld.id
  internal_load_balancer_enabled      = true # Private Ingress
  zone_redundancy_enabled             = true
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_container_app_environment" "cae-pub-consonly" {
  name                            = "cae-pub-consonly"
  location                        = var.location
  resource_group_name             = var.resource_group_name
}

resource "azurerm_container_app_environment" "cae-pub-conswkld-vnet-int" {
  name                                = "cae-pub-conswkld-vnet-int"
  location                            = var.location
  resource_group_name                 = var.resource_group_name
  infrastructure_resource_group_name  = var.resource_group_name
  infrastructure_subnet_id            = azurerm_subnet.snet-conswkld-vnet-int.id
  internal_load_balancer_enabled      = true # Private Ingress
  zone_redundancy_enabled             = true
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    maximum_count         = 0
    minimum_count         = 0
  }
}

resource "azurerm_container_app" "ca-pri-1" {
  name                         = "ca-pri-1"
  container_app_environment_id = azurerm_container_app_environment.cae-pri-consonly.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    container {
      name   = "nginx"
      image  = "nginx:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = false
    target_port      = 80
    traffic_weight {
      percentage      = 100
      latest_revision = true
    } 
  }
}

resource "azurerm_container_app" "ca-pri-2" {
  name                         = "ca-pri-2"
  container_app_environment_id = azurerm_container_app_environment.cae-pri-conswkld.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    container {
      name   = "nginx"
      image  = "nginx:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = false
    target_port      = 80
    traffic_weight {
      percentage     = 100
      latest_revision = true
    }
  }
}

resource "azurerm_container_app" "ca-pri-3" {
  name                         = "ca-pri-3"
  container_app_environment_id = azurerm_container_app_environment.cae-pub-conswkld-vnet-int.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    container {
      name   = "nginx"
      image  = "nginx:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = false
    target_port      = 80
    traffic_weight {
      percentage     = 100
      latest_revision = true
    }
  }
}

resource "azurerm_container_app" "ca-pub-1" {
  name                         = "ca-pub-1"
  container_app_environment_id = azurerm_container_app_environment.cae-pub-consonly.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    container {
      name   = "nginx"
      image  = "nginx:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = true
    target_port      = 80
    traffic_weight {
      percentage     = 100
      latest_revision = true
    }
  }
}

# Private Endpoint（CAE環境対象）
resource "azurerm_private_endpoint" "pe-pub-conswkld" {
  name                = "pe-pub-conswkld"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.snet-pe.id

  private_service_connection {
    name                           = "psc-ca-pri-3"
    private_connection_resource_id  = azurerm_container_app_environment.cae-pub-conswkld-vnet-int.id
    subresource_names              = ["managedEnvironments"]
    is_manual_connection           = false
  }
}

# # Functionランタイム・Python版も同様に↓
# resource "azurerm_container_app" "func" {
#   count = 0
#   name                         = "ca-demo-func"
#   container_app_environment_id = azurerm_container_app_environment.cae.id
#   resource_group_name          = azurerm_resource_group.ca.name
#   location                     = azurerm_resource_group.ca.location
#   revision_mode                = "Single"

#   workload_profile_name        = "consumption"

#   template {
#     container {
#       name   = "func-python"
#       image  = "mcr.microsoft.com/azure-functions/python:4-python3.11"
#       cpu    = 0.25
#       memory = "0.5Gi"
#     }
#     min_replicas = 0
#     max_replicas = 3
#     http_scale_rule {
#       name="http-scale-rule"
#       concurrent_requests = 50
#     }

#   }

#   ingress {
#     external_enabled  = true
#     target_port       = 80
#     transport         = "auto"
#     traffic_weight {
#       percentage      = 100
#     }
#   }
# }

# resource "azurerm_private_dns_zone" "ca" {
#   count               = 0
#   name                = "privatelink.azurecontainerapps.io"
#   resource_group_name = azurerm_resource_group.ca.name
# }

# resource "azurerm_private_dns_zone_virtual_network_link" "ca" {
#   count                 = 0
#   name                  = "ca-vnet-link"
#   resource_group_name   = azurerm_resource_group.ca.name
#   private_dns_zone_name = azurerm_private_dns_zone.ca.name
#   virtual_network_id    = azurerm_virtual_network.vnet.id
# }

# # Aレコード追加は通常不要（自動登録）。手動で追加したい場合だけ下記：
# resource "azurerm_private_dns_a_record" "cae" {
#   count               = 0
#   name                = azurerm_container_app_environment.cae.name
#   zone_name           = azurerm_private_dns_zone.ca.name
#   resource_group_name = azurerm_resource_group.ca.name
#   ttl                 = 300
#   records             = [azurerm_private_endpoint.cae_pe.private_service_connection[0].private_ip_address]
# }

