terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.61.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}


data "azurerm_client_config" "current" {}

resource "random_string" "storage_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "random_string" "keyvault_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "random_password" "vm_admin" {
  length           = var.admin_password_length
  special          = true
  override_special = "!@#%^*-_=+?"

  keepers = {
    rotation_token = var.password_rotation_token
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
}

resource "azurerm_key_vault" "kv" {
  name                          = "${var.key_vault_name_prefix}${random_string.keyvault_suffix.result}"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  rbac_authorization_enabled    = false
  public_network_access_enabled = true

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover",
      "Purge"
    ]
  }
}

resource "azurerm_key_vault_secret" "vm_admin_password" {
  name         = var.admin_password_secret_name
  value        = random_password.vm_admin.result
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-snet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_cidr]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowRdpFromAzureBastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_bastion_host" "bastion" {
  name                = "${var.prefix}-bastion"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Developer"
  virtual_network_id  = azurerm_virtual_network.vnet.id
}

resource "azurerm_storage_account" "files" {
  name                     = "${replace(var.prefix, "-", "")}${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_share" "share" {
  name               = var.file_share_name
  storage_account_id = azurerm_storage_account.files.id
  quota              = var.file_share_quota_gb
}

resource "azurerm_storage_sync" "sync" {
  name                = var.storage_sync_service_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_storage_sync_group" "sync_group" {
  name            = var.storage_sync_group_name
  storage_sync_id = azurerm_storage_sync.sync.id
}

resource "null_resource" "storage_sync_identity_role" {
  triggers = {
    storage_sync_id    = azurerm_storage_sync.sync.id
    storage_account_id = azurerm_storage_account.files.id
    role_script_ver    = "v2"
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      SYNC_ID="${self.triggers.storage_sync_id}"
      STORAGE_ID="${self.triggers.storage_account_id}"

      SYNC_PRINCIPAL="$(az resource show --ids "$SYNC_ID" --api-version 2022-09-01 --query identity.principalId -o tsv)"
      if [ -z "$SYNC_PRINCIPAL" ]; then
        az resource update --ids "$SYNC_ID" --api-version 2022-09-01 --set identity.type=SystemAssigned properties.useIdentity=true --only-show-errors >/dev/null
        SYNC_PRINCIPAL="$(az resource show --ids "$SYNC_ID" --api-version 2022-09-01 --query identity.principalId -o tsv)"
      fi

      ensure_role() {
        local role_name="$1"
        if ! az role assignment list --assignee "$SYNC_PRINCIPAL" --scope "$STORAGE_ID" --query "[?roleDefinitionName=='$role_name'] | length(@)" -o tsv | grep -q "^1$"; then
          az role assignment create --assignee-object-id "$SYNC_PRINCIPAL" --assignee-principal-type ServicePrincipal --role "$role_name" --scope "$STORAGE_ID" --only-show-errors >/dev/null
        fi
      }

      ensure_role "Storage Account Contributor"
      ensure_role "Storage File Data Privileged Contributor"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "azurerm_storage_sync_cloud_endpoint" "cloud_endpoint" {
  name                  = var.storage_sync_cloud_endpoint_name
  storage_sync_group_id = azurerm_storage_sync_group.sync_group.id
  file_share_name       = azurerm_storage_share.share.name
  storage_account_id    = azurerm_storage_account.files.id

  depends_on = [
    null_resource.storage_sync_identity_role
  ]
}

resource "azurerm_network_interface" "nic" {
  for_each            = toset(["vm1", "vm2"])
  name                = "${var.prefix}-${each.key}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

locals {
  vm_names = toset(["vm1", "vm2"])
}

resource "azurerm_windows_virtual_machine" "vm" {
  for_each              = local.vm_names
  name                  = "${var.prefix}-${each.key}"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = random_password.vm_admin.result
  network_interface_ids = [azurerm_network_interface.nic[each.key].id]

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.nsg_assoc,
    azurerm_key_vault_secret.vm_admin_password
  ]
}

resource "azurerm_managed_disk" "data" {
  for_each             = local.vm_names
  name                 = "${var.prefix}-${each.key}-data"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each           = local.vm_names
  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_windows_virtual_machine.vm[each.key].id
  lun                = 0
  caching            = "ReadWrite"
}

resource "azurerm_role_assignment" "sync_registration" {
  for_each             = local.vm_names
  scope                = azurerm_storage_sync.sync.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_windows_virtual_machine.vm[each.key].identity[0].principal_id
}

resource "azurerm_virtual_machine_extension" "afs_agent_install_register" {
  for_each                   = local.vm_names
  name                       = "${var.prefix}-${each.key}-afsregister"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm[each.key].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='Stop';$syncRg='${azurerm_resource_group.rg.name}';$syncSvc='${azurerm_storage_sync.sync.name}';$syncPath='${var.server_endpoint_local_path}';$agentUrl='${var.afs_agent_download_url}';$agentMsi='C:\\\\Windows\\\\Temp\\\\StorageSyncAgent.msi';$targetDrive=($syncPath -split ':')[0];$volume=Get-Volume -DriveLetter $targetDrive -ErrorAction SilentlyContinue;if (-not $volume) { $rawDisk=Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Select-Object -First 1; if ($rawDisk) { Initialize-Disk -Number $rawDisk.Number -PartitionStyle GPT -PassThru | New-Partition -UseMaximumSize -DriveLetter $targetDrive | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'AFSData' -Confirm:$false | Out-Null } };if (-not (Test-Path -LiteralPath $syncPath)) { New-Item -Path $syncPath -ItemType Directory -Force | Out-Null };if ($agentUrl -ne '') { Invoke-WebRequest -Uri $agentUrl -OutFile $agentMsi; Start-Process msiexec.exe -ArgumentList '/i',$agentMsi,'/qn','/norestart' -Wait; };Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;Set-PSRepository -Name PSGallery -InstallationPolicy Trusted;if (-not (Get-Module -ListAvailable -Name Az.Accounts)) { Install-Module Az.Accounts -Force -Scope AllUsers; };if (-not (Get-Module -ListAvailable -Name Az.StorageSync)) { Install-Module Az.StorageSync -Force -Scope AllUsers; };Import-Module Az.Accounts;Import-Module Az.StorageSync;Connect-AzAccount -Identity;$registered=$false;for ($i=0; $i -lt 10 -and -not $registered; $i++) { try { Register-AzStorageSyncServer -ResourceGroupName $syncRg -StorageSyncServiceName $syncSvc; $registered=$true } catch { if ($_.Exception.Message -match 'already|0x80C8004F') { $registered=$true } else { if ($i -eq 9) { throw }; Start-Sleep -Seconds 30 } } }\""
  })

  depends_on = [
    azurerm_storage_sync_cloud_endpoint.cloud_endpoint,
    azurerm_role_assignment.sync_registration,
    azurerm_virtual_machine_data_disk_attachment.data
  ]
}

resource "azurerm_storage_sync_server_endpoint" "server_endpoint" {
  for_each              = var.registered_server_ids
  name                  = "${var.prefix}-${each.key}-sep"
  storage_sync_group_id = azurerm_storage_sync_group.sync_group.id
  registered_server_id  = each.value
  server_local_path     = var.server_endpoint_local_path

  depends_on = [
    azurerm_virtual_machine_extension.afs_agent_install_register,
    azurerm_storage_sync_cloud_endpoint.cloud_endpoint
  ]
}
