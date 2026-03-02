# Troubleshooting: Stuck Deployment & DNS

When `./deploy.sh` hangs on Helm or pods fail with **NXDOMAIN** resolving the PostgreSQL private FQDN, use this guide.

---

## 1. Stuck deployment (cancel and clean up)

**In the terminal where deploy.sh is running:**
- Press `Ctrl+C` (multiple times if needed). If still stuck, close the terminal.

**If Helm release is stuck (pending-install / pending-upgrade):**

```bash
cd deployments/aks
helm status dify -n dify
helm uninstall dify -n dify
sleep 5
```

---

## 2. Fix DNS (Private DNS Zone link to AKS)

Pods can't resolve `*.<project>-pg-*.privatelink.postgres.database.azure.com` (NXDOMAIN). Usually the Private DNS Zone link to the AKS VNet is wrong or Terraform’s data source didn’t find the VNet yet.

**Recommended sequence:**

```bash
cd deployments/aks

# Refresh Terraform and reapply DNS link + peering
terraform refresh
terraform apply -target=data.azurerm_resources.aks_vnets[0] \
    -target=azurerm_private_dns_zone_virtual_network_link.aks[0] \
    -target=azurerm_virtual_network_peering.postgres_to_aks[0] \
    -target=azurerm_virtual_network_peering.aks_to_postgres[0] \
    -auto-approve

# Restart CoreDNS and wait
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s
sleep 30
```

**Verify DNS (replace FQDN with your PostgreSQL private FQDN from `terraform output postgresql_fqdn`):**

```bash
kubectl run dns-test --image=busybox:1.36 --rm -i --restart=Never -- \
    nslookup <your-pg-fqdn>.privatelink.postgres.database.azure.com
# Should show an IP, not NXDOMAIN
```

---

## 3. Retry deployment (app only)

Infra is already there; redeploy only the app:

```bash
./deploy.sh --app --auto-approve
```

---

## 4. If DNS still fails

**Check that the DNS link points to the AKS VNet:**

```bash
RG_NAME=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
NODE_RG=$(az aks show --resource-group $RG_NAME --name $CLUSTER_NAME --query nodeResourceGroup -o tsv)
az network vnet list --resource-group $NODE_RG --output table
# Compare VNet ID with the link:
az network private-dns link vnet list \
    --resource-group $RG_NAME \
    --zone-name privatelink.postgres.database.azure.com \
    --output table
```

**Force Terraform to refresh the data source:**

```bash
terraform apply -refresh=true -target=data.azurerm_resources.aks_vnets[0] -auto-approve
terraform apply -target=azurerm_private_dns_zone_virtual_network_link.aks[0] -auto-approve
```

**Restart Dify pods after DNS is fixed:**

```bash
kubectl rollout restart deployment/dify-api -n dify
kubectl rollout restart deployment/dify-plugin-daemon -n dify
kubectl rollout restart deployment/dify-worker -n dify
kubectl get pods -n dify -w
```

---

## 5. Quick one-liner (after canceling deploy.sh)

Replace `<your-pg-fqdn>` with the output of `terraform output -raw postgresql_fqdn` (without `https://` or path).

```bash
cd deployments/aks && \
terraform refresh && \
terraform apply -target=data.azurerm_resources.aks_vnets[0] \
  -target=azurerm_private_dns_zone_virtual_network_link.aks[0] \
  -target=azurerm_virtual_network_peering.postgres_to_aks[0] \
  -target=azurerm_virtual_network_peering.aks_to_postgres[0] \
  -auto-approve && \
kubectl rollout restart deployment/coredns -n kube-system && \
sleep 30 && \
./deploy.sh --app --auto-approve
```
