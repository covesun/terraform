terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# ─────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}-test"
  location = var.location
}

# ─────────────────────────────────────────────
# VNet-VPN: VPN Gateway 側
# ─────────────────────────────────────────────

resource "azurerm_virtual_network" "vnet_vpn" {
  name                = "vnet-vpn"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]
}

# GatewaySubnet は名前固定
resource "azurerm_subnet" "snet_gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_vpn.name
  address_prefixes     = ["10.1.0.0/27"]
}

resource "azurerm_public_ip" "pip_vpn_gw" {
  name                = "pip-vpn-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

# P2S VPN Gateway (Azure AD / Entra ID 認証)
# SKU: VpnGw1 以上が必要
resource "azurerm_virtual_network_gateway" "vpn_gw" {
  name                = "vpn-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"
  generation          = "Generation1"

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.pip_vpn_gw.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.snet_gateway.id
  }

  vpn_client_configuration {
    address_space = [var.vpn_client_address_pool]

    # Entra ID (Azure AD) 認証
    # Azure VPN クライアントアプリの固定クライアントID
    aad_tenant    = "https://login.microsoftonline.com/${var.tenant_id}"
    aad_audience  = "41b23e61-6c1e-4545-b367-cd054e0ed4b4" # Azure VPN Client app (固定値)
    aad_issuer    = "https://sts.windows.net/${var.tenant_id}/"

    vpn_client_protocols = ["OpenVPN"]
  }
}

# ─────────────────────────────────────────────
# VNet-PE: Private Endpoint 側
# ─────────────────────────────────────────────

resource "azurerm_virtual_network" "vnet_pe" {
  name                = "vnet-pe"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.2.0.0/16"]
}

resource "azurerm_subnet" "snet_pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_pe.name
  address_prefixes     = ["10.2.1.0/24"]
}

# ─────────────────────────────────────────────
# VNet Peering (双方向)
# ─────────────────────────────────────────────

resource "azurerm_virtual_network_peering" "vpn_to_pe" {
  name                      = "peering-vpn-to-pe"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.vnet_vpn.name
  remote_virtual_network_id = azurerm_virtual_network.vnet_pe.id

  allow_forwarded_traffic   = true
  allow_gateway_transit     = true  # VPN GW 側でトランジットを許可
  use_remote_gateways       = false
}

resource "azurerm_virtual_network_peering" "pe_to_vpn" {
  name                      = "peering-pe-to-vpn"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.vnet_pe.name
  remote_virtual_network_id = azurerm_virtual_network.vnet_vpn.id

  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = true  # PE 側は VPN GW 経由でルーティング

  # VPN GW が完成してからピアリングを設定
  depends_on = [azurerm_virtual_network_gateway.vpn_gw]
}

# ─────────────────────────────────────────────
# Storage Account (パブリックアクセス完全無効)
# ─────────────────────────────────────────────

resource "azurerm_storage_account" "sa" {
  name                     = "${var.prefix}blobtest"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # パブリックアクセスを完全に無効化
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true

  network_rules {
    default_action = "Deny"
    bypass         = []  # 信頼済みMicrosoftサービスバイパスも無効化
  }
}

resource "azurerm_storage_container" "container" {
  name                  = "test-container"
  storage_account_id    = azurerm_storage_account.sa.id
  container_access_type = "private"
}

# ─────────────────────────────────────────────
# Private Endpoint (Blob)
# ─────────────────────────────────────────────

resource "azurerm_private_endpoint" "pe_blob" {
  name                = "pe-blob"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.snet_pe.id

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.sa.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-group-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

# ─────────────────────────────────────────────
# Private DNS Zone
# VPN クライアントが FQDN を解決するためには、
# 両 VNet にリンクが必要
# ─────────────────────────────────────────────

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

# VNet-PE へのリンク（Private Endpoint が属する VNet）
resource "azurerm_private_dns_zone_virtual_network_link" "link_pe" {
  name                  = "link-vnet-pe"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet_pe.id
  registration_enabled  = false
}

# VNet-VPN へのリンク（VPN クライアントが DNS 解決するために必要）
resource "azurerm_private_dns_zone_virtual_network_link" "link_vpn" {
  name                  = "link-vnet-vpn"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet_vpn.id
  registration_enabled  = false
}

# ─────────────────────────────────────────────
# RBAC: Storage Explorer からの Entra ID 認証用
# ─────────────────────────────────────────────

resource "azurerm_role_assignment" "blob_contributor" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.blob_reader_object_id
}
