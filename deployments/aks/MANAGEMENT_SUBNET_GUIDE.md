# Management Subnet Guide

This guide explains how to use the management subnet to access PostgreSQL for database dumps, maintenance, and troubleshooting.

## Overview

The management subnet (`10.1.2.0/24` by default) is a public subnet in the same VNet as PostgreSQL. This allows you to:

- Spin up VMs with public IPs for database access
- Perform database dumps, backups, and maintenance
- Troubleshoot database connectivity issues
- Access PostgreSQL using the private FQDN from within the VNet

## Architecture

```
Internet
   │
   │ SSH/RDP (22/3389)
   ▼
Management Subnet (10.1.2.0/24)
   │ Public IPs allowed
   │ NSG: Allows SSH/RDP from Internet
   │
   │ PostgreSQL (5432)
   ▼
PostgreSQL Subnet (10.1.1.0/24)
   │ Private subnet
   │ Delegated to PostgreSQL Flexible Server
   │
   ▼
PostgreSQL Server (Private FQDN)
```

## Network Security

**NSG Rules Configured:**
- ✅ **Inbound SSH (22)**: Allow from Internet
- ✅ **Inbound RDP (3389)**: Allow from Internet (for Windows VMs)
- ✅ **Outbound PostgreSQL (5432)**: Allow to PostgreSQL subnet

**Default VNet Communication:**
- Subnets in the same VNet can communicate by default
- No additional NSG rules needed on PostgreSQL subnet (it's delegated to PostgreSQL service)

## Creating a VM in the Management Subnet

### Option 1: Using Azure CLI

```bash
# Get the management subnet ID from Terraform
SUBNET_ID=$(cd deployments/aks && terraform output -raw management_subnet_id)
RESOURCE_GROUP=$(cd deployments/aks && terraform output -raw resource_group_name)
LOCATION=$(cd deployments/aks && terraform output -raw location)

# Create a public IP
az network public-ip create \
  --resource-group "$RESOURCE_GROUP" \
  --name "dify-jumpbox-ip" \
  --sku Standard \
  --location "$LOCATION"

# Create a network interface
az network nic create \
  --resource-group "$RESOURCE_GROUP" \
  --name "dify-jumpbox-nic" \
  --subnet "$SUBNET_ID" \
  --public-ip-address "dify-jumpbox-ip" \
  --location "$LOCATION"

# Create the VM (Ubuntu example)
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "dify-jumpbox" \
  --image "Ubuntu2204" \
  --size "Standard_B2s" \
  --nics "dify-jumpbox-nic" \
  --admin-username "azureuser" \
  --generate-ssh-keys \
  --location "$LOCATION"
```

### Option 2: Using Azure Portal

1. Go to **Virtual machines** → **Create**
2. **Basics:**
   - Resource group: Use the same RG as your AKS deployment
   - VM name: `dify-jumpbox` (or any name)
   - Region: Same as your deployment (e.g., Australia East)
   - Image: Ubuntu Server 22.04 LTS (or Windows if preferred)
   - Size: Standard_B2s (2 vCPU, 4GB RAM) is sufficient
   - Authentication: SSH public key or password

3. **Networking:**
   - Virtual network: Select the VNet created by Terraform (e.g., `dify-vnet-xxxx`)
   - Subnet: Select `dify-management-subnet` (or the management subnet name)
   - Public IP: Create new (Standard SKU)
   - NIC security group: Use the NSG created by Terraform (or create new)

4. **Review + Create**

### Option 3: Using Terraform (Optional)

You can add a VM resource to `main.tf`:

```hcl
# Example: Jumpbox VM (optional - uncomment if you want Terraform to manage it)
# resource "azurerm_public_ip" "jumpbox" {
#   count               = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
#   name                = "${local.name_prefix}-jumpbox-ip"
#   location            = local.rg_location
#   resource_group_name = local.rg_name
#   allocation_method   = "Static"
#   sku                 = "Standard"
#   tags                = var.tags
# }
#
# resource "azurerm_network_interface" "jumpbox" {
#   count               = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
#   name                = "${local.name_prefix}-jumpbox-nic"
#   location            = local.rg_location
#   resource_group_name = local.rg_name
#
#   ip_configuration {
#     name                          = "internal"
#     subnet_id                     = azurerm_subnet.management[0].id
#     private_ip_address_allocation = "Dynamic"
#     public_ip_address_id          = azurerm_public_ip.jumpbox[0].id
#   }
#
#   tags = var.tags
# }
#
# resource "azurerm_linux_virtual_machine" "jumpbox" {
#   count                           = var.use_azure_postgres && var.create_vnet_for_postgres && length(var.management_subnet_address_prefixes) > 0 ? 1 : 0
#   name                            = "${local.name_prefix}-jumpbox"
#   location                        = local.rg_location
#   resource_group_name             = local.rg_name
#   size                            = "Standard_B2s"
#   admin_username                  = "azureuser"
#   disable_password_authentication = true
#
#   network_interface_ids = [
#     azurerm_network_interface.jumpbox[0].id,
#   ]
#
#   admin_ssh_key {
#     username   = "azureuser"
#     public_key = file("~/.ssh/id_rsa.pub")  # Update with your SSH key path
#   }
#
#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "Standard_LRS"
#   }
#
#   source_image_reference {
#     publisher = "Canonical"
#     offer     = "0001-com-ubuntu-server-jammy"
#     sku       = "22_04-lts"
#     version   = "latest"
#   }
#
#   tags = var.tags
# }
```

## Connecting to PostgreSQL from the VM

Once your VM is created, SSH into it and connect to PostgreSQL:

```bash
# SSH into the VM
ssh azureuser@<VM_PUBLIC_IP>

# Install PostgreSQL client (Ubuntu/Debian)
sudo apt update
sudo apt install -y postgresql-client

# Get PostgreSQL connection details from Terraform
# From your local machine:
cd deployments/aks
terraform output postgresql_fqdn
terraform output postgresql_connection_string

# Connect to PostgreSQL (from the VM)
# Use the PRIVATE FQDN (ends with .privatelink.postgres.database.azure.com)
psql -h <postgres-private-fqdn> -U difyadmin -d dify

# Example connection string:
# PGPASSWORD='difyai123456' psql -h dify-pg-xxxx.privatelink.postgres.database.azure.com -U difyadmin -d dify
```

## Performing Database Dumps

```bash
# Full database dump
PGPASSWORD='difyai123456' pg_dump \
  -h dify-pg-xxxx.privatelink.postgres.database.azure.com \
  -U difyadmin \
  -d dify \
  -F c \
  -f dify_backup_$(date +%Y%m%d_%H%M%S).dump

# Schema only
PGPASSWORD='difyai123456' pg_dump \
  -h dify-pg-xxxx.privatelink.postgres.database.azure.com \
  -U difyadmin \
  -d dify \
  --schema-only \
  -f dify_schema.sql

# Data only
PGPASSWORD='difyai123456' pg_dump \
  -h dify-pg-xxxx.privatelink.postgres.database.azure.com \
  -U difyadmin \
  -d dify \
  --data-only \
  -f dify_data.sql
```

## Security Best Practices

1. **Use SSH Keys**: Prefer SSH key authentication over passwords
2. **Restrict SSH Access**: Consider restricting SSH source IPs in NSG (instead of "Internet")
3. **Use VPN/Bastion**: For production, consider Azure Bastion instead of public IPs
4. **Rotate Credentials**: Regularly rotate PostgreSQL passwords
5. **Delete VMs When Not Needed**: Delete jumpbox VMs when not in use to reduce attack surface
6. **Enable Logging**: Enable NSG flow logs for monitoring

## Cost Considerations

- **VM Cost**: ~$15-30/month for Standard_B2s (2 vCPU, 4GB RAM)
- **Public IP**: ~$3-5/month (Standard SKU)
- **Storage**: ~$5-10/month for OS disk
- **Total**: ~$25-45/month when running

**Tip**: Delete the VM when not in use to save costs. You can recreate it quickly when needed.

## Troubleshooting

### Cannot connect to PostgreSQL from VM

1. **Check NSG Rules:**
   ```bash
   az network nsg rule list \
     --resource-group <rg-name> \
     --nsg-name <nsg-name> \
     --output table
   ```

2. **Verify Subnet:**
   ```bash
   # Ensure VM is in management subnet
   az vm show --resource-group <rg-name> --name <vm-name> --query "networkProfile.networkInterfaces[0].id" -o tsv
   ```

3. **Test DNS Resolution:**
   ```bash
   # From the VM, test if private FQDN resolves
   nslookup dify-pg-xxxx.privatelink.postgres.database.azure.com
   ```

4. **Test Connectivity:**
   ```bash
   # Test PostgreSQL port
   telnet dify-pg-xxxx.privatelink.postgres.database.azure.com 5432
   ```

### VM Cannot Access Internet

- Check if NSG allows outbound traffic (default is allow all)
- Verify public IP is attached and Standard SKU
- Check route table (should use default routes)

## Alternative: Using AKS Subnet

If you prefer to use AKS's subnet instead of creating a separate management subnet:

1. **Get AKS Subnet ID:**
   ```bash
   # AKS uses a managed VNet in the node resource group
   NODE_RG=$(az aks show --resource-group <rg> --name <cluster> --query nodeResourceGroup -o tsv)
   AKS_SUBNET_ID=$(az network vnet subnet list --resource-group "$NODE_RG" --vnet-name <vnet-name> --query "[0].id" -o tsv)
   ```

2. **Create VM in AKS Subnet:**
   - Use the AKS subnet ID when creating the VM
   - Note: This subnet is managed by AKS, so be careful with changes

**Recommendation**: Use the dedicated management subnet instead - it's cleaner, easier to manage, and doesn't interfere with AKS operations.

---

**Last Updated:** 2026-01-24
