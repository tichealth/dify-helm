# Operations: Endpoints and Keys

How to get the main endpoints and secrets used by the deployment.

---

## PostgreSQL endpoint (FQDN)

**Recommended:** Terraform output (after `terraform apply`):

```bash
cd deployments/aks
terraform output postgresql_fqdn
terraform output postgresql_connection_string   # connection string without password
```

**Other ways:** Azure Portal → Azure Database for PostgreSQL flexible servers → your server → Overview (Server name). Or Azure CLI: `az postgres flexible-server list --query "[].{Name:name, FQDN:fullyQualifiedDomainName}" -o table`.

---

## Dify public endpoint (IP and domain)

**Recommended:** nginx-ingress LoadBalancer IP:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Use the `EXTERNAL-IP` column. Access Dify at `https://<your-domain>/apps` (once DNS points to this IP) or `http://<EXTERNAL-IP>` (HTTP only).

**Domain:** Set in `values.yaml` (e.g. `dify-dev.tichealth.com.au`). Point a DNS A record at the LoadBalancer IP. Cert-manager will issue TLS.

**From cluster:** `kubectl get ingress -n dify` and `kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`

---

## Azure Blob Storage account key

Used for Dify file storage (and optionally Terraform state). **Do not commit the key.**

**Azure Portal:** Storage accounts → your account → Access keys → Show → Copy (key1 or key2).

**Azure CLI:**

```bash
az storage account keys list \
  --resource-group <resource-group-name> \
  --account-name <storage-account-name> \
  --query "[0].value" -o tsv
```

**Create storage account (if needed):**

```bash
az storage account create --name <name> --resource-group <rg> --location australiaeast --sku Standard_LRS --kind StorageV2
az storage container create --name dify-data --account-name <name> --account-key <key>
```

Use the key only in local `terraform.tfvars` or GitHub Secrets (see [GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md)); never commit it.
