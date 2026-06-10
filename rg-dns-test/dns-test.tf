# dns-test.tf

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

variable "subscription_id" {}

variable "rg_name" {}

variable "location" {}

variable "dns_server_ip" {
  description = "自分のPC/DCの固定DNSサーバーIP"
}

variable "vpn_root_cert_data" {
  description = "P2S VPN ルート証明書の公開鍵データ (Base64、ヘッダー行除く)"
}

resource "azurerm_resource_group" "main" {
  name     = var.rg_name
  location = var.location
}

# ==================================================
# VNet 定義
# ==================================================

resource "azurerm_virtual_network" "vnet1" {
  name                = "vnet1-dnsrsiv-test-jpe"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.1.0.0/24"]
}

resource "azurerm_virtual_network" "vnet2" {
  name                = "vnet2-dnsrsiv-test-jpe"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.2.0.0/24", "10.2.1.0/24"]
}

resource "azurerm_virtual_network" "vnet3" {
  name                = "vnet3-dnsrsiv-test-jpe"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.3.0.0/16"]
}

# ====================
# VNet1 Subnets
# ====================

resource "azurerm_subnet" "vnet1_default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.1.0.0/25"]
}

resource "azurerm_subnet" "vnet1_gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.1.0.128/25"]
}

# ====================
# VNet2 Subnets
# ====================

resource "azurerm_subnet" "vnet2_default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.2.0.0/25"]
}

resource "azurerm_subnet" "vnet2_firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.2.0.128/25"]
}

# Basic Firewall は AzureFirewallManagementSubnet が必須 (10.2.1.0/24 の新アドレス空間に配置)
resource "azurerm_subnet" "vnet2_firewall_mgmt" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.2.1.0/26"]
}

# DNS Private Resolver 用サブネット (10.2.1.0/26 の後続アドレス)
resource "azurerm_subnet" "vnet2_dns_inbound" {
  name                 = "dns-inbound"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.2.1.64/28"]

  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "vnet2_dns_outbound" {
  name                 = "dns-outbound"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.2.1.80/28"]

  delegation {
    name = "dns-resolver"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# ====================
# VNet3 Subnets
# ====================

resource "azurerm_subnet" "vnet3_apps" {
  name                 = "container-apps"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet3.name
  address_prefixes     = ["10.3.16.0/20"]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# ==================================================
# Route tables for Firewall Transit
# ==================================================

resource "azurerm_route_table" "rt_vnet1_fw" {
  name                = "rt-vnet1-fw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  route {
    name                   = "to-vnet3-via-fw"
    address_prefix         = "10.3.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.vnet2.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "vnet1_gateway" {
  subnet_id      = azurerm_subnet.vnet1_gateway.id
  route_table_id = azurerm_route_table.rt_vnet1_fw.id
}

# vnet2 の Firewall/DNS サブネットは use_remote_gateways=true でも
# P2S VPN クライアントプール(172.16.0.0/24)を自動学習しないため明示的にUDRを追加
resource "azurerm_route_table" "rt_vnet2_vpn" {
  name                = "rt-vnet2-vpn"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  route {
    name           = "to-vpn-clients"
    address_prefix = "172.16.0.0/24"
    next_hop_type  = "VirtualNetworkGateway"
  }
}

resource "azurerm_subnet_route_table_association" "vnet2_firewall" {
  subnet_id      = azurerm_subnet.vnet2_firewall.id
  route_table_id = azurerm_route_table.rt_vnet2_vpn.id
}

resource "azurerm_subnet_route_table_association" "vnet2_dns_outbound" {
  subnet_id      = azurerm_subnet.vnet2_dns_outbound.id
  route_table_id = azurerm_route_table.rt_vnet2_vpn.id
}

resource "azurerm_route_table" "rt_vnet3" {
  name                = "rt-vnet3"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  route {
    name                   = "to-vpn-clients-via-fw"
    address_prefix         = "172.16.0.0/24"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.vnet2.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "vnet3_apps" {
  subnet_id      = azurerm_subnet.vnet3_apps.id
  route_table_id = azurerm_route_table.rt_vnet3.id
}

# ==================================================
# VNet ピアリング
# ==================================================

resource "azurerm_virtual_network_peering" "vnet1_to_vnet2" {
  name                         = "vnet1-to-vnet2"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.vnet1.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet2.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "vnet2_to_vnet1" {
  name                         = "vnet2-to-vnet1"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.vnet2.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet1.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = true

  depends_on = [azurerm_virtual_network_gateway.vpn_gw_vnet1]
}

resource "azurerm_virtual_network_peering" "vnet2_to_vnet3" {
  name                         = "vnet2-to-vnet3"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.vnet2.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet3.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "vnet3_to_vnet2" {
  name                         = "vnet3-to-vnet2"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.vnet3.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet2.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [azurerm_virtual_network_peering.vnet2_to_vnet3]
}

# ==================================================
# VPN Gateway (VNet1)
# ==================================================

resource "azurerm_public_ip" "pip_vnet1_vpngw" {
  name                = "pip-vnet1-vpngw-test-jpe"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  allocation_method   = "Static"
  zones               = ["1", "2", "3"]
}

resource "azurerm_virtual_network_gateway" "vpn_gw_vnet1" {
  name                = "vpgw-vnet1-test-jpe"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "Basic"

  # azurerm provider v3 は public_ip_address_id を必須として要求するため指定
  # (Basic SKU は Azure 内部で IP を管理するが、provider がまだ未対応)
  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.pip_vnet1_vpngw.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.vnet1_gateway.id
  }

  # P2S設定: 証明書認証 + IKEv2
  vpn_client_configuration {
    address_space        = ["172.16.0.0/24"]
    vpn_auth_types       = ["Certificate"]
    vpn_client_protocols = ["IkeV2"]

    root_certificate {
      name             = "p2s-root-cert"
      public_cert_data = var.vpn_root_cert_data
    }
  }

  # vnet3 と vnet2の第2アドレス空間(DNS Resolver用) を VPNクライアントに広告
  custom_route {
    address_prefixes = ["10.3.0.0/16", "10.2.1.0/24"]
  }
}

# ==================================================
# Azure Firewall Standard (VNet2)
# ==================================================

resource "azurerm_public_ip" "pip_vnet2_firewall" {
  name                = "afw-vnet2-test-jpe-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "pip_vnet2_firewall_mgmt" {
  name                = "afw-vnet2-test-jpe-mgmt-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  allocation_method   = "Static"
}

resource "azurerm_firewall" "vnet2" {
  name                = "afw-vnet2-test-jpe"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = azurerm_subnet.vnet2_firewall.id
    public_ip_address_id = azurerm_public_ip.pip_vnet2_firewall.id
  }

  # Basic SKU 必須: 管理トラフィック用の IP 設定
  management_ip_configuration {
    name                 = "fw-mgmt-ipconfig"
    subnet_id            = azurerm_subnet.vnet2_firewall_mgmt.id
    public_ip_address_id = azurerm_public_ip.pip_vnet2_firewall_mgmt.id
  }
}

# ==================================================
# Firewall Network Rules
# ==================================================

resource "azurerm_firewall_network_rule_collection" "allow_vpn_to_vnet3" {
  name                = "allow-vpn-to-vnet3"
  azure_firewall_name = azurerm_firewall.vnet2.name
  resource_group_name = azurerm_resource_group.main.name
  priority            = 100
  action              = "Allow"

  rule {
    name                  = "vpn-to-vnet3"
    protocols             = ["TCP", "UDP"]
    source_addresses      = ["172.16.0.0/24"]
    destination_addresses = ["10.3.0.0/16"]
    destination_ports     = ["*"]
  }
}

resource "azurerm_firewall_network_rule_collection" "allow_vnet3_to_vpn" {
  name                = "allow-vnet3-to-vpn"
  azure_firewall_name = azurerm_firewall.vnet2.name
  resource_group_name = azurerm_resource_group.main.name
  priority            = 200
  action              = "Allow"

  rule {
    name                  = "vnet3-to-vpn"
    protocols             = ["TCP", "UDP"]
    source_addresses      = ["10.3.0.0/16"]
    destination_addresses = ["172.16.0.0/24"]
    destination_ports     = ["*"]
  }
}

# ==================================================
# DNS Private Resolver (vnet2)
# ==================================================

resource "azurerm_private_dns_resolver" "vnet2" {
  name                = "dnspr-test-jpe"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  virtual_network_id  = azurerm_virtual_network.vnet2.id
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "vnet2" {
  name                    = "inbound-ep-test"
  private_dns_resolver_id = azurerm_private_dns_resolver.vnet2.id
  location                = azurerm_resource_group.main.location

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.vnet2_dns_inbound.id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "vnet2" {
  name                    = "outbound-ep-test"
  private_dns_resolver_id = azurerm_private_dns_resolver.vnet2.id
  location                = azurerm_resource_group.main.location
  subnet_id               = azurerm_subnet.vnet2_dns_outbound.id
}

# ==================================================
# DNS Forwarding Ruleset (vnet2)
# ==================================================

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "vnet2" {
  name                                       = "ruleset-test"
  resource_group_name                        = azurerm_resource_group.main.name
  location                                   = azurerm_resource_group.main.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.vnet2.id]
}

resource "azurerm_private_dns_resolver_forwarding_rule" "admix" {
  name                      = "admix"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.vnet2.id
  domain_name               = "admix.go.jp."
  enabled                   = true

  target_dns_servers {
    ip_address = var.dns_server_ip
    port       = 53
  }
}

resource "azurerm_virtual_network_dns_servers" "vnet3" {
  virtual_network_id = azurerm_virtual_network.vnet3.id
  dns_servers        = [azurerm_private_dns_resolver_inbound_endpoint.vnet2.ip_configurations[0].private_ip_address]

  depends_on = [azurerm_private_dns_resolver_inbound_endpoint.vnet2]
}

resource "azurerm_private_dns_resolver_virtual_network_link" "vnet3" {
  name                      = "vnet3-link"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.vnet2.id
  virtual_network_id        = azurerm_virtual_network.vnet3.id

  depends_on = [azurerm_private_dns_resolver_dns_forwarding_ruleset.vnet2]
}

# ==================================================
# Container App Environment (VNet接続)
# ==================================================

resource "azurerm_container_app_environment" "main" {
  name                           = "cae-test-jpe"
  resource_group_name            = azurerm_resource_group.main.name
  location                       = azurerm_resource_group.main.location
  infrastructure_subnet_id       = azurerm_subnet.vnet3_apps.id
  internal_load_balancer_enabled = false

  lifecycle {
    ignore_changes = [infrastructure_resource_group_name]
  }
}

# Container App (Ubuntu - DNS/疎通テスト用)
resource "azurerm_container_app" "ubuntu_test" {
  name                         = "ubuntu-test"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  template {
    min_replicas = 1
    max_replicas = 10

    container {
      name   = "ubuntu-tools"
      image  = "ubuntu:22.04"
      memory = "0.5Gi"
      cpu    = 0.25
      command = [
        "/bin/bash", "-c",
        "apt-get update && apt-get install -y netcat-openbsd dnsutils iputils-ping curl wget && sleep infinity"
      ]
    }
  }
}

# ==================================================
# Log Analytics Workspace
# ==================================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-test-jpe"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ==================================================
# Firewall Diagnostic Settings
# ==================================================

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "firewall-diagnostics"
  target_resource_id         = azurerm_firewall.vnet2.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ==================================================
# Outputs
# ==================================================

output "inbound_endpoint_ip" {
  value       = azurerm_private_dns_resolver_inbound_endpoint.vnet2.ip_configurations[0].private_ip_address
  description = "Inbound Endpoint の IP アドレス"
}

output "resolver_id" {
  value       = azurerm_private_dns_resolver.vnet2.id
  description = "DNS Resolver の ID"
}

output "vnet1_id" {
  value = azurerm_virtual_network.vnet1.id
}

output "vnet2_id" {
  value = azurerm_virtual_network.vnet2.id
}

output "vnet3_id" {
  value = azurerm_virtual_network.vnet3.id
}

output "vpn_gateway_id" {
  value       = azurerm_virtual_network_gateway.vpn_gw_vnet1.id
  description = "VNet1 VPN Gateway の ID"
}

output "firewall_id" {
  value       = azurerm_firewall.vnet2.id
  description = "VNet2 Azure Firewall の ID"
}


output "container_app_environment_id" {
  value       = azurerm_container_app_environment.main.id
  description = "Container App Environment ID"
}

output "container_app_id" {
  value       = azurerm_container_app.ubuntu_test.id
  description = "Ubuntu Test Container App ID"
}

output "container_app_fqdn" {
  value       = azurerm_container_app.ubuntu_test.latest_revision_fqdn
  description = "Container App FQDN"
}

# ==================================================
# LOGGING INFRASTRUCTURE メモ
# ==================================================
# Firewall diagnostics → Log Analytics Workspace (Terraform managed)
# VNet1 Flow Logs: Portal で作成、Terraform 管理外
#   - Name: vnet1-dnsrsiv-test-jpe rg-dnsrsivtest-flowlog
#   - Target: VNet1 (vnet1-dnsrsiv-test-jpe)
#   - Retention: 90 days
