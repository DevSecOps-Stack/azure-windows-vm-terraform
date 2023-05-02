# Configure the Azure Provider
provider "azurerm" {
  # whilst the `version` attribute is optional, we recommend pinning to a given version of the Provider
  subscription_id = "205021e2-11c0-4939-8aa7-41c29b36b86f"
  client_id = "70fe070f-1c91-46d6-918e-6e8ff746efd5"
  client_secret = "Bto8Q~4YUQizHa.bOxj5DWrtds4_ALs7VyrSeb3x"
  tenant_id = "4c6f1364-8db1-4e57-95ef-b3cf7dd7d4c9"
  # version = "~> 2.54.0"
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "example_rg" {
  name     = "${var.resource_prefixes}-RG"
  location = var.node_location
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "example_vnet" {
  name                = "${var.resource_prefixes}-vnet"
  resource_group_name = azurerm_resource_group.example_rg.name
  location            = var.node_location
  address_space       = var.node_address_space
}

# Create a subnets within the virtual network
resource "azurerm_subnet" "example_subnet" {
  name                 = "${var.resource_prefixes}-subnet"
  resource_group_name  = azurerm_resource_group.example_rg.name
  virtual_network_name = azurerm_virtual_network.example_vnet.name
  address_prefixes     = var.node_address_prefixes
}

# Create Linux Public IP
resource "azurerm_public_ip" "example_public_ip" {
  count = var.node_count
  name  = "${var.resource_prefixes}-${format("%02d", count.index)}-PublicIP"
  #name = "${var.resource_prefix}-PublicIP"
  location            = azurerm_resource_group.example_rg.location
  resource_group_name = azurerm_resource_group.example_rg.name
  allocation_method   = var.Environment == "Test" ? "Static" : "Dynamic"

  tags = {
    environment = "Test"
  }
}

# Create Network Interface
resource "azurerm_network_interface" "example_nic" {
  count = var.node_count
  #name = "${var.resource_prefix}-NIC"
  name                = "${var.resource_prefixes}-${format("%02d", count.index)}-NIC"
  location            = azurerm_resource_group.example_rg.location
  resource_group_name = azurerm_resource_group.example_rg.name
  #

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.example_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = element(azurerm_public_ip.example_public_ip.*.id, count.index)
    #public_ip_address_id = azurerm_public_ip.example_public_ip.id
    #public_ip_address_id = azurerm_public_ip.example_public_ip.id
  }
}

# Creating resource NSG
resource "azurerm_network_security_group" "example_nsg" {

  name                = "${var.resource_prefixes}-NSG"
  location            = azurerm_resource_group.example_rg.location
  resource_group_name = azurerm_resource_group.example_rg.name

  # Security rule can also be defined with resource azurerm_network_security_rule, here just defining it inline.
  security_rule {
    name                       = "Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"

  }
  tags = {
    environment = "Test"
  }
}

# Subnet and NSG association
resource "azurerm_subnet_network_security_group_association" "example_subnet_nsg_association" {
  subnet_id                 = azurerm_subnet.example_subnet.id
  network_security_group_id = azurerm_network_security_group.example_nsg.id

}

# use existing log analytics workspace
data "azurerm_log_analytics_workspace" "example_log_analytics" {
  name                = "logs-prod-hub"
  resource_group_name = "logs-prod-hub-rg"
}
resource "azurerm_virtual_machine_extension" "example" {
  count                = var.node_count
  name                 = "example-extension"
  virtual_machine_id   = azurerm_windows_virtual_machine.example_vm[count.index].id
  publisher            = "Microsoft.EnterpriseCloud.Monitoring"
  type                 = "MicrosoftMonitoringAgent"
  type_handler_version = "1.0"
  auto_upgrade_minor_version = true
  settings             = <<SETTINGS
{
    "workspaceId": "${data.azurerm_log_analytics_workspace.example_log_analytics.workspace_id}"
}
SETTINGS
  protected_settings   = <<PROTECTED_SETTINGS
    {
        "workspaceKey": "${data.azurerm_log_analytics_workspace.example_log_analytics.primary_shared_key}"
    }
PROTECTED_SETTINGS
}

# Virtual Machine Creation — Linux
resource "azurerm_windows_virtual_machine" "example_vm" {
  count                 = var.node_count
  name                  = "${var.resource_prefixes}-${format("%02d", count.index)}"
  location              = azurerm_resource_group.example_rg.location
  resource_group_name   = azurerm_resource_group.example_rg.name
  network_interface_ids = [element(azurerm_network_interface.example_nic.*.id, count.index)]
  admin_username        = "adminuser"
  admin_password        = "P@ssw0rd1234!"
  size                  = "Standard_DS1_v2"

   os_disk {
    name              = "${var.resource_prefixes}-osdisk${count.index}"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

}
