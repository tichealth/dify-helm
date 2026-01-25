# Teardown and Redeploy Guide

Complete guide to tear down and redeploy the Dify AKS deployment from scratch.

## ⚠️ Warning

This will **DELETE** all resources:
- AKS cluster
- PostgreSQL database (if using Azure PostgreSQL)
- All data in the cluster
- LoadBalancer IPs

**Backup any important data before proceeding!**

---

## Step 1: Uninstall Helm Releases

```bash
cd dify-helm/deployments/aks

# Uninstall Dify Helm release
helm uninstall dify -n dify

# Uninstall nginx-ingress (if installed)
helm uninstall ingress-nginx -n ingress-nginx

# Uninstall cert-manager (if installed)
helm uninstall cert-manager -n cert-manager

# Verify all releases are removed
helm list -A
```

---

## Step 2: Destroy Terraform Infrastructure

```bash
cd dify-helm/deployments/aks

# Review what will be destroyed
terraform plan -destroy

# Destroy all infrastructure
terraform destroy

# Confirm when prompted (type: yes)
```

**Note**: This will destroy:
- AKS cluster
- Azure PostgreSQL (if `use_azure_postgres = true`)
- Resource group (if created by Terraform)
- All associated resources

---

## Step 3: Clean Up Manual Resources (if any)

If you created NSG rules manually, they will be deleted when the AKS cluster is destroyed (they're in the node resource group).

If you have any other manual resources:
```bash
# List resource groups
az group list --query "[?contains(name, 'dify')].{Name:name, Location:location}" -o table

# Delete specific resource group (if needed)
az group delete --name <resource-group-name> --yes --no-wait
```

---

## Step 4: Redeploy using deploy.sh

`deploy.sh` now handles:
- Terraform init/apply
- nginx-ingress install
- cert-manager install
- ClusterIssuer creation
- Dify Helm deployment
- NSG rule updates

```bash
cd dify-helm/deployments/aks
./deploy.sh
```

## Step 5: Configure DNS

Get the ingress LoadBalancer IP:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Create DNS A record:
- **Name**: `dify-dev`
- **Type**: `A`
- **Value**: `<ingress-lb-ip>` (from the command above)
- **TTL**: `300` (or default)

## Step 6: Verify HTTPS

```bash
kubectl get certificate -n dify
curl -I https://dify-dev.tichealth.com.au/apps
```

```bash
# Test HTTP (with Host header)
curl -I http://<LoadBalancer-IP> -H "Host: dify-dev.tichealth.com.au"

# Test HTTPS (if DNS is configured)
curl -I https://dify-dev.tichealth.com.au

# Check ingress
kubectl get ingress -n dify

# Check certificate
kubectl get certificate -n dify
```

---

## Quick Teardown Script

Save as `teardown.sh`:

```bash
#!/bin/bash
set -e

echo "=== Teardown Dify Deployment ==="

# Uninstall Helm releases
echo "Uninstalling Helm releases..."
helm uninstall dify -n dify 2>/dev/null || true
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
helm uninstall cert-manager -n cert-manager 2>/dev/null || true

# Destroy Terraform
echo "Destroying Terraform infrastructure..."
terraform destroy -auto-approve

echo "=== Teardown Complete ==="
```

Make executable: `chmod +x teardown.sh`

---

## Troubleshooting

### If NSG rules don't work

1. **Verify rules exist**:
   ```bash
   NODE_RG=$(az aks show --resource-group <rg> --name <cluster> --query nodeResourceGroup -o tsv)
   NSG_NAME=$(az network nsg list --resource-group "$NODE_RG" --query "[0].name" -o tsv)
   az network nsg rule list --resource-group "$NODE_RG" --nsg-name "$NSG_NAME" --query "[?destinationPortRanges=='80' || destinationPortRanges=='443']" -o table
   ```

2. **Check LoadBalancer status**:
   ```bash
   kubectl get svc -n ingress-nginx ingress-nginx-controller
   ```

3. **Test from inside cluster**:
   ```bash
   kubectl run -it --rm test --image=curlimages/curl --restart=Never -- curl -I http://dify.dify.svc.cluster.local
   ```

### If Terraform destroy fails

```bash
# Force unlock (if state is locked)
terraform force-unlock <lock-id>

# Or remove from state manually
terraform state rm <resource-address>
```

---

## Complete Redeploy Checklist

- [ ] Uninstall Helm releases (Step 1)
- [ ] Destroy Terraform infrastructure (Step 2)
- [ ] Run `./deploy.sh` (handles Terraform, ingress, cert-manager, Dify, **and** fix-nsg-rules.sh)
- [ ] Configure DNS (Step 5)
- [ ] Verify access (Step 6)

---

## Notes

- **NSG rules** are applied automatically by `deploy.sh` (it runs `fix-nsg-rules.sh`).
- **LoadBalancer IP changes** on each deployment - update DNS accordingly.
- **Wait times**: NSG rules (1-2 min), DNS propagation (5-10 min), certificates (2-5 min).
