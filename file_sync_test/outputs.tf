output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  value = azurerm_storage_account.files.name
}

output "file_share_name" {
  value = azurerm_storage_share.share.name
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "admin_password_secret_name" {
  value = azurerm_key_vault_secret.vm_admin_password.name
}

output "bastion_host_name" {
  value = azurerm_bastion_host.bastion.name
}

output "storage_sync_service_id" {
  value = azurerm_storage_sync.sync.id
}

output "storage_sync_group_id" {
  value = azurerm_storage_sync_group.sync_group.id
}

output "storage_sync_cloud_endpoint_id" {
  value = azurerm_storage_sync_cloud_endpoint.cloud_endpoint.id
}

output "vm_private_ips" {
  value = {
    vm1 = azurerm_network_interface.nic["vm1"].private_ip_address
    vm2 = azurerm_network_interface.nic["vm2"].private_ip_address
  }
}

output "registered_server_discovery_command" {
  value = "az storagesync registered-server list --resource-group ${azurerm_resource_group.rg.name} --storage-sync-service ${azurerm_storage_sync.sync.name} --query \"[].{id:id,name:name}\" -o table"
}

output "admin_password_fetch_command" {
  value = "az keyvault secret show --vault-name ${azurerm_key_vault.kv.name} --name ${azurerm_key_vault_secret.vm_admin_password.name} --query value -o tsv"
}

output "server_endpoint_ids" {
  value = { for k, v in azurerm_storage_sync_server_endpoint.server_endpoint : k => v.id }
}
