############################################
# main.tf  (単一ファイルで動くミニマム)
############################################
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.115.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

########################
# Variables (簡易)
########################
variable "prefix"       { default = "pgadmin-test" }            # リソース名プレフィックス
variable "location"     { default = "japaneast" }
variable "admin_email"  { default = "admin@example.com" } # pgAdmin 初期ユーザー
variable "admin_pass"   { default = "P@ssw0rd" } # pgAdmin 初期パス
# 必要なら変更
variable "appgw_sku"    { default = "Standard_v2" }
variable "appgw_cap"    { default = 1 } # 1台
variable "subscription_id" { default = "10a251c5-8576-47f6-bcda-5242f89a5e28" } # ご自身のサブスクリプションID

########################
# Resource Group
########################
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
}

########################
# VNet & Subnets
# - AppGW 専用サブネット
# - ACA 環境用サブネット
########################
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

# resource "azurerm_subnet" "sub_appgw" {
#   name                 = "snet-appgw"
#   resource_group_name  = azurerm_resource_group.rg.name
#   virtual_network_name = azurerm_virtual_network.vnet.name
#   address_prefixes     = ["10.10.0.0/24"]
# }

resource "azurerm_subnet" "sub_aca" {
  name                 = "snet-aca"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.2.0/23"]
  # delegation {
  #   name = "aca-delegation"
  #   service_delegation {
  #     name = "Microsoft.App/environments"
  #     actions = [
  #       "Microsoft.Network/virtualNetworks/subnets/action"
  #     ]
  #   }
  # }
}

########################
# Public IP for AppGW
########################
# resource "azurerm_public_ip" "pip" {
#   name                = "${var.prefix}-appgw-pip"
#   location            = var.location
#   resource_group_name = azurerm_resource_group.rg.name
#   allocation_method   = "Static"
#   sku                 = "Standard"
# }

########################
# Container Apps Environment (Internal)
########################
resource "azurerm_container_app_environment" "env" {
  name                           = "${var.prefix}-cae"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.rg.name
  infrastructure_subnet_id       = azurerm_subnet.sub_aca.id
  zone_redundancy_enabled        = false
  # internal_load_balancer_enabled = true   # 内部向け
  internal_load_balancer_enabled = false
}

########################
# Container App: pgAdmin
########################
resource "azurerm_container_app" "pgadmin" {
  name                         = "${var.prefix}-pgadmin"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  ingress {
    # external_enabled = false               # 内部のみ
    external_enabled = true
    target_port      = 5050
    transport        = "auto"
    traffic_weight {
      percentage = 100
      latest_revision = true
    }
  }

  template {
    container {
      name   = "pgadmin"
      image  = "dpage/pgadmin4:8.14"       # 例：安定タグ。必要に応じ更新
      cpu    = 0.5
      memory = "1Gi"

      # env {
      #   name  = "PGADMIN_LISTEN_ADDRESS"
      #   value = "0.0.0.0"
      # }
      env {
        name  = "PGADMIN_LISTEN_PORT"
        value = "5050"
      }
      # env {
      #   name  = "PGADMIN_CONFIG_ENABLE_PROXY_FIX"
      #   value = "True"
      # }
      # ルート公開なので SCRIPT_NAME は未設定
      env {
        name  = "PGADMIN_DEFAULT_EMAIL"
        value = var.admin_email
      }
      env {
        name  = "PGADMIN_DEFAULT_PASSWORD"
        value = var.admin_pass
      }
      # env {
      #   name  = "SCRIPT_NAME"
      #   value = "/pgadmin"
      # }
    }
  }
}

########################
# Application Gateway
########################
# resource "azurerm_application_gateway" "appgw" {
#   name                = "${var.prefix}-appgw"
#   location            = var.location
#   resource_group_name = azurerm_resource_group.rg.name

#   sku {
#     name     = var.appgw_sku      # Standard_v2
#     tier     = var.appgw_sku
#     capacity = var.appgw_cap      # 1
#   }

#   # autoscale_configuration {
#   #   min_capacity = var.appgw_cap
#   #   max_capacity = 2
#   # }

#   gateway_ip_configuration {
#     name      = "gwipc"
#     subnet_id = azurerm_subnet.sub_appgw.id
#   }

#   frontend_port {
#     name = "feport80"
#     port = 80
#   }

#   frontend_ip_configuration {
#     name                 = "feip"
#     public_ip_address_id = azurerm_public_ip.pip.id
#   }

#   http_listener {
#     name                           = "listener80"
#     frontend_ip_configuration_name = "feip"
#     frontend_port_name             = "feport80"
#     protocol                       = "Http"
#   }

#   # Backend pool: ACA 内部 FQDN を使用
#   backend_address_pool {
#     name  = "pool-pgadmin"
#     fqdns = [azurerm_container_app.pgadmin.ingress[0].fqdn]
#   }

#   probe {
#     name     = "probe-pgadmin"
#     protocol = "Http"
#     host     = "localhost"         # Host チェック無効化の意味合い（後述で上書き可）
#     path     = "/login"
#     interval = 30
#     timeout  = 30
#     unhealthy_threshold = 3

#     match {
#       status_code = ["200-399"]
#     }
#   }

#   backend_http_settings {
#     name                  = "bhs-pgadmin"
#     protocol              = "Http"
#     port                  = 5050
#     request_timeout       = 60
#     probe_name            = "probe-pgadmin"
#     pick_host_name_from_backend_address = true  # ← ACA 内部 FQDN を Host に使う
#     cookie_based_affinity = "Disabled"
#   }

#   request_routing_rule {
#     name                       = "rule80-root"
#     rule_type                  = "Basic"
#     http_listener_name         = "listener80"
#     backend_address_pool_name  = "pool-pgadmin"
#     backend_http_settings_name = "bhs-pgadmin"
#     rewrite_rule_set_name      = "rrs-xff"
#     priority                   = 100
#   }

#   # 余裕があれば：Rewrite で X-Forwarded-Proto/Host を明示
#   rewrite_rule_set {
#     name = "rrs-xff"
#     rewrite_rule {
#       name          = "set-xff"
#       rule_sequence = 10
#       request_header_configuration {
#         header_name  = "X-Forwarded-Proto"
#         header_value = "http"  # 検証は http。HTTPS 化時は "https" に変更
#       }
#       request_header_configuration {
#         header_name  = "X-Forwarded-Host"
#         header_value = "{http_req_host}"
#       }
#       # request_header_configuration {
#       #   header_name  = "X-Forwarded-Prefix"
#       #   header_value = "/pgadmin"
#       # }
#     }
#   }
# }

########################
# Private DNS Zones for ACA
######################## 
# resource "azurerm_private_dns_zone" "aca" {
#   name                = "privatelink.azurecontainerapps.io"
#   resource_group_name = azurerm_resource_group.rg.name
# }

# resource "azurerm_private_dns_zone_virtual_network_link" "aca_link" {
#   name                  = "aca-dnslink"
#   resource_group_name   = azurerm_resource_group.rg.name
#   private_dns_zone_name = azurerm_private_dns_zone.aca.name
#   virtual_network_id    = azurerm_virtual_network.vnet.id
# }

# resource "azurerm_private_dns_zone" "aca_internal" {
#   name                = "internal.azurecontainerapps.io"
#   resource_group_name = azurerm_resource_group.rg.name
# }

# resource "azurerm_private_dns_zone_virtual_network_link" "aca_internal_link" {
#   name                  = "aca-internal-dnslink"
#   resource_group_name   = azurerm_resource_group.rg.name
#   private_dns_zone_name = azurerm_private_dns_zone.aca_internal.name
#   virtual_network_id    = azurerm_virtual_network.vnet.id
# }

########################
# 出力
########################
# output "appgw_public_ip" {
#   value = azurerm_public_ip.pip.ip_address
# }

output "aca_internal_fqdn" {
  value = azurerm_container_app.pgadmin.ingress[0].fqdn
}
