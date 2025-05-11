
output "vnet_name" {
  value = azurerm_virtual_network.vnet-1.name
}

output "subnet_id" {
  value = azurerm_subnet.snet-1.id
}
