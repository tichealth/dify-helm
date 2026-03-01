# Quick Fix: DNS Resolution Issue

## Problem
Pods can't resolve `dify-pg-d26e.privatelink.postgres.database.azure.com` - getting NXDOMAIN.

## Root Cause
The Private DNS Zone link to AKS VNet might not be pointing to the correct VNet, or the data source didn't find it correctly.

## Quick Fix Options

### Option 1: Re-run Terraform to Fix DNS Link

```bash
cd deployments/aks

# Check what Terraform thinks about DNS link
terraform state show azurerm_private_dns_zone_virtual_network_link.aks[0]

# Refresh the data source and reapply
terraform apply -refresh=true -auto-approve
```

### Option 2: Manually Verify and Fix DNS Link

```bash
# Get resource group
RG_NAME=$(terraform output -raw resource_group_name)

# Get AKS node resource group
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
NODE_RG=$(az aks show --resource-group $RG_NAME --name $CLUSTER_NAME --query nodeResourceGroup -o tsv)

# List VNets in node RG
az network vnet list --resource-group $NODE_RG --output table

# Get the VNet ID (usually the first one)
AKS_VNET_ID=$(az network vnet list --resource-group $NODE_RG --query "[0].id" -o tsv)

# Check current DNS link
az network private-dns link vnet list \
    --resource-group $RG_NAME \
    --zone-name privatelink.postgres.database.azure.com \
    --output table

# If link is wrong, delete and recreate via Terraform
terraform apply -target=azurerm_private_dns_zone_virtual_network_link.aks[0] -auto-approve
```

### Option 3: Restart CoreDNS and Pods

```bash
# Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system

# Wait 30 seconds
sleep 30

# Restart Dify pods
kubectl rollout restart deployment/dify-api -n dify
kubectl rollout restart deployment/dify-plugin-daemon -n dify
kubectl rollout restart deployment/dify-worker -n dify

# Monitor
kubectl get pods -n dify -w
```

### Option 4: Check if Data Source Found VNet

```bash
# Check Terraform outputs
terraform output -json | jq '.aks_vnet_id.value'

# If null, the data source didn't find the VNet
# Force refresh
terraform apply -refresh=true -target=data.azurerm_resources.aks_vnets[0] -auto-approve
```

## Most Likely Solution

Run this sequence:

```bash
cd deployments/aks

# 1. Refresh Terraform state
terraform refresh

# 2. Reapply DNS link and peering
terraform apply -target=data.azurerm_resources.aks_vnets[0] \
    -target=azurerm_private_dns_zone_virtual_network_link.aks[0] \
    -target=azurerm_virtual_network_peering.postgres_to_aks[0] \
    -target=azurerm_virtual_network_peering.aks_to_postgres[0] \
    -auto-approve

# 3. Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
sleep 30

# 4. Restart Dify pods
kubectl rollout restart deployment/dify-api -n dify
kubectl rollout restart deployment/dify-plugin-daemon -n dify
kubectl rollout restart deployment/dify-worker -n dify

# 5. Monitor
kubectl get pods -n dify -w
```

## Verify Fix

```bash
# Test DNS resolution
kubectl run dns-test --image=busybox:1.36 --rm -i --restart=Never -- \
    nslookup dify-pg-d26e.privatelink.postgres.database.azure.com

# Should show an IP address, not NXDOMAIN
```
