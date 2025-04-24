
resource "azurerm_storage_account" "example_storage" {
  name                     = "${var.resource_prefix}storage"
  resource_group_name      = "example-rg"
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  enable_https_traffic_only = true
  allow_blob_public_access = false
}

resource "azurerm_private_endpoint" "example_pe" {
  name                = "${var.resource_prefix}-blob-pe"
  location            = var.location
  resource_group_name = "example-rg"
  subnet_id           = azurerm_subnet.example_subnet.id

  private_service_connection {
    name                           = "${var.resource_prefix}-blob-psc"
    private_connection_resource_id = azurerm_storage_account.example_storage.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}
