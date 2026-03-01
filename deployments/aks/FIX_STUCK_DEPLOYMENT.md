# Fix Stuck Deployment - Step by Step

## Current Situation
- `./deploy.sh` is stuck on Step 10 (Helm deployment)
- Plugin daemon pod is crashing due to DNS resolution failure
- Need to cancel, fix DNS, then retry

---

## Step 1: Cancel the Stuck Deployment

**In the terminal where deploy.sh is running:**
- Press `Ctrl+C` to cancel
- If that doesn't work, press `Ctrl+C` multiple times
- If still stuck, close the terminal and open a new one

---

## Step 2: Clean Up Stuck Helm Release (if needed)

```bash
cd deployments/aks

# Check Helm release status
helm status dify -n dify

# If it's stuck in "pending-install" or "pending-upgrade"
helm uninstall dify -n dify

# Wait a moment
sleep 5
```

---

## Step 3: Fix DNS Resolution

```bash
cd deployments/aks

# Refresh Terraform to get latest AKS VNet info
terraform refresh

# Reapply DNS link and peering to ensure they're correct
terraform apply -target=data.azurerm_resources.aks_vnets[0] \
    -target=azurerm_private_dns_zone_virtual_network_link.aks[0] \
    -target=azurerm_virtual_network_peering.postgres_to_aks[0] \
    -target=azurerm_virtual_network_peering.aks_to_postgres[0] \
    -auto-approve

# Verify DNS link was created correctly
terraform state show azurerm_private_dns_zone_virtual_network_link.aks[0] | grep virtual_network_id
```

---

## Step 4: Restart CoreDNS

```bash
# Restart CoreDNS to pick up DNS changes
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s

# Wait for DNS propagation
echo "Waiting 30 seconds for DNS propagation..."
sleep 30
```

---

## Step 5: Test DNS Resolution

```bash
# Test if DNS now resolves
kubectl run dns-test --image=busybox:1.36 --rm -i --restart=Never -- \
    nslookup dify-pg-d26e.privatelink.postgres.database.azure.com

# Should show an IP address (not NXDOMAIN)
```

---

## Step 6: Retry Deployment

Since infrastructure is already deployed, use `--app` mode:

```bash
# Deploy only the application (skips Terraform)
./deploy.sh --app --auto-approve
```

This will:
- Skip Terraform (infrastructure already exists)
- Deploy Helm charts (ingress, cert-manager, Dify)
- Use the fixed DNS configuration

---

## Alternative: If DNS Still Doesn't Work

If DNS still doesn't resolve after Step 3-4, check:

```bash
# Get AKS node resource group
RG_NAME=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
NODE_RG=$(az aks show --resource-group $RG_NAME --name $CLUSTER_NAME --query nodeResourceGroup -o tsv)

# List VNets in node RG
az network vnet list --resource-group $NODE_RG --output table

# Get VNet ID
AKS_VNET_ID=$(az network vnet list --resource-group $NODE_RG --query "[0].id" -o tsv)
echo "AKS VNet ID: $AKS_VNET_ID"

# Check DNS link points to this VNet
RG_NAME=$(terraform output -raw resource_group_name)
az network private-dns link vnet show \
    --resource-group $RG_NAME \
    --zone-name privatelink.postgres.database.azure.com \
    --name dify-aks-dns-link-* \
    --query virtualNetwork.id -o tsv
```

If VNet IDs don't match, manually fix the DNS link or re-run full Terraform apply.

---

## Quick One-Liner Fix

If you want to do everything at once:

```bash
cd deployments/aks && \
terraform refresh && \
terraform apply -target=data.azurerm_resources.aks_vnets[0] -target=azurerm_private_dns_zone_virtual_network_link.aks[0] -target=azurerm_virtual_network_peering.postgres_to_aks[0] -target=azurerm_virtual_network_peering.aks_to_postgres[0] -auto-approve && \
kubectl rollout restart deployment/coredns -n kube-system && \
kubectl rollout status deployment/coredns -n kube-system --timeout=60s && \
sleep 30 && \
kubectl run dns-test --image=busybox:1.36 --rm -i --restart=Never -- nslookup dify-pg-d26e.privatelink.postgres.database.azure.com && \
echo "DNS fixed! Now run: ./deploy.sh --app --auto-approve"
```
