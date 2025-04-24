
output "vnet_name" {
  value = azurerm_virtual_network.example_vnet.name
}

output "subnet_id" {
  value = azurerm_subnet.example_subnet.id
}
