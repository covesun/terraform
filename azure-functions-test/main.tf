provider "azurerm" {
  features {}
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "func" {
  name     = "rg-func-flex-test"
  location = "japaneast"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-func"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.func.location
  resource_group_name = azurerm_resource_group.func.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "snet-func"
  resource_group_name  = azurerm_resource_group.func.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
  delegation {
    name = "Microsoft.Web.serverFarms"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_storage_account" "func" {
  name                     = "funcflexstor${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.func.name
  location                 = azurerm_resource_group.func.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  allow_blob_public_access = false
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.subnet.id]
  }
}

resource "azurerm_app_service_plan" "func" {
  name                = "asp-func-flex"
  location            = azurerm_resource_group.func.location
  resource_group_name = azurerm_resource_group.func.name
  kind                = "functionapp"
  sku {
    tier = "Flexible"
    size = "C1"
  }
  zone_redundant = true
}

resource "azurerm_application_insights" "func" {
  name                = "appi-func-flex"
  location            = azurerm_resource_group.func.location
  resource_group_name = azurerm_resource_group.func.name
  application_type    = "web"
}

resource "azurerm_linux_function_app" "func" {
  name                       = "func-flex-demo-${random_string.suffix.result}"
  location                   = azurerm_resource_group.func.location
  resource_group_name         = azurerm_resource_group.func.name
  storage_account_name        = azurerm_storage_account.func.name
  storage_account_access_key  = azurerm_storage_account.func.primary_access_key
  service_plan_id             = azurerm_app_service_plan.func.id
  application_insights_key    = azurerm_application_insights.func.instrumentation_key
  site_config {
    linux_fx_version = "Python|3.11"
  }
  https_only      = true
  zone_redundant  = true
  virtual_network_subnet_id = azurerm_subnet.subnet.id # VNet統合
}

##############################
# Private Endpoint for Function App本体
##############################
resource "azurerm_private_endpoint" "func" {
  name                = "pe-func-app"
  location            = azurerm_resource_group.func.location
  resource_group_name = azurerm_resource_group.func.name
  subnet_id           = azurerm_subnet.subnet.id

  private_service_connection {
    name                           = "psc-func-app"
    private_connection_resource_id  = azurerm_linux_function_app.func.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }
}

##############################
# Private DNS for Function App (privatelink.azurewebsites.net)
##############################
resource "azurerm_private_dns_zone" "func" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.func.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "func" {
  name                  = "vnetlink-func"
  resource_group_name   = azurerm_resource_group.func.name
  private_dns_zone_name = azurerm_private_dns_zone.func.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_a_record" "func" {
  name                = azurerm_linux_function_app.func.name
  zone_name           = azurerm_private_dns_zone.func.name
  resource_group_name = azurerm_resource_group.func.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.func.private_service_connection[0].private_ip_address]
}

##############################
# Private Endpoint for Storage Account (blob)
##############################
resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-func-storage-blob"
  location            = azurerm_resource_group.func.location
  resource_group_name = azurerm_resource_group.func.name
  subnet_id           = azurerm_subnet.subnet.id

  private_service_connection {
    name                           = "psc-func-storage-blob"
    private_connection_resource_id  = azurerm_storage_account.func.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}

##############################
# Private DNS for Storage Account (privatelink.blob.core.windows.net)
##############################
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.func.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "vnetlink-blob"
  resource_group_name   = azurerm_resource_group.func.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_a_record" "blob" {
  name                = azurerm_storage_account.func.name
  zone_name           = azurerm_private_dns_zone.blob.name
  resource_group_name = azurerm_resource_group.func.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage_blob.private_service_connection[0].private_ip_address]
}
