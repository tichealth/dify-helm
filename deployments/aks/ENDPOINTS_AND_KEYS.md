# Endpoints and keys

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

## Terraform backend storage key

Creating the backend resource group, storage account, and container is covered
once in [GITHUB_ACTIONS.md](./GITHUB_ACTIONS.md#b-terraform-backend).

To read the key for an account that already exists:

```bash
az storage account keys list \
  --resource-group <backend-resource-group> \
  --account-name <storage-account-name> \
  --query "[0].value" -o tsv
```

Portal equivalent: Storage accounts → your account → Access keys → Show → copy
key1 or key2.

Use it only in a gitignored `backend.azurerm.tfvars` or as the
`AZURE_BLOB_ACCOUNT_KEY` GitHub secret — never commit it (see
[SECRETS.md](./SECRETS.md)).

This account holds Terraform state only. Dify and plugin files live on Azure
File PVCs; the Blob variables are not wired to application storage.
