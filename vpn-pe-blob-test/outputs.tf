output "vpn_gateway_public_ip" {
  description = "P2S VPN Gateway のパブリック IP (VPN クライアント設定に使用)"
  value       = azurerm_public_ip.pip_vpn_gw.ip_address
}

output "storage_account_name" {
  description = "Storage Account 名"
  value       = azurerm_storage_account.sa.name
}

output "storage_account_blob_endpoint" {
  description = "Blob エンドポイント FQDN (Storage Explorer で指定)"
  value       = azurerm_storage_account.sa.primary_blob_endpoint
}

output "private_endpoint_ip" {
  description = "Private Endpoint の IP アドレス"
  value       = azurerm_private_endpoint.pe_blob.private_service_connection[0].private_ip_address
}

output "vpn_client_config_download_command" {
  description = "VPN クライアント設定ファイルのダウンロードコマンド"
  value       = "az network vnet-gateway vpn-client generate --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_virtual_network_gateway.vpn_gw.name} --authentication-method EAPTLS"
}
