# Production Deployment (No DR)

How to deploy Dify to **production** using the AKS stack, with **no disaster recovery** (no read replicas, single region).

See **[LITE_PROD_VS_PROD.md](./LITE_PROD_VS_PROD.md)** for cost and scalability: **lite prod** (1 node, lower cost) vs **full prod** (3 nodes, higher resilience).

---

## Parameter to Use for Prod

**There is no `--env prod` flag.** Production is selected by **which Terraform variables file you use**:

- **Lite prod** (1 node, ~250–350 AUD/mo): `environments/lite-prod.tfvars`
- **Full prod** (3 nodes, ~930–1,040 AUD/mo): `environments/prod-full.tfvars`

1. **Option A (recommended for local):** Copy the chosen env file into place, **add the secret variables** (they are not in the repo), then run deploy. See [Local deploy](#local-deploy) below.

2. **Option B:** Use the [GitHub Actions workflow](../../.github/workflows/deploy-aks.yml): run manually, choose **environment** (lite-prod or prod-full), **action** (deploy/teardown), **deploy_mode** (all/app/db). Secrets go in GitHub Secrets (see [GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md)).

3. **Option C:** Use Terraform’s `-var-file` and run deploy (see [Deploy script and var file](#deploy-script-and-var-file) below).

So the “parameter” for prod is: **which tfvars file you use** (lite-prod or prod-full).

---

## No DR Settings

- **PostgreSQL:** Single Azure Flexible Server only. Read replicas are **not** implemented in this Terraform (see `outputs.tf`: “Read replicas not implemented”). So no extra “DR” toggle is needed; it’s already no-DR.
- **Redis:** Single instance in-cluster (replica count 0 in `values.yaml`).
- **AKS:** Single region; no multi-region or failover in this stack.

The file `environments/prod-no-dr.tfvars` is a prod-oriented tfvars with no DR options (no read replica variables).

---

## Local deploy

You can still run a full deploy from your machine. Secrets are **not** in the repo, so you must provide them in one of two ways.

### Option 1: Add secrets to `terraform.tfvars` (simple)

1. Copy an environment file to `terraform.tfvars` (that file is gitignored):
   ```bash
   cd deployments/aks
   cp environments/lite-prod.tfvars terraform.tfvars   # or prod-full.tfvars / prod-no-dr.tfvars
   ```
2. Open `terraform.tfvars` and **add** these variables (with your real values):
   ```hcl
   # Add these – values are only on your machine, never commit
   azure_blob_account_name   = "your-storage-account"
   azure_blob_account_key    = "your-storage-key"
   azure_blob_account_url    = "https://your-storage-account.blob.core.windows.net"
   dify_secret_key           = "your-dify-secret-key"
   postgresql_password       = "your-postgres-password"
   redis_password            = "your-redis-password"
   qdrant_api_key            = "your-qdrant-api-key"
   ```
3. Run deploy:
   ```bash
   ./deploy.sh --auto-approve
   ```

### Option 2: Use environment variables (no secrets in files)

Export Terraform variables before running; Terraform reads `TF_VAR_<name>` automatically:

```bash
cd deployments/aks
cp environments/lite-prod.tfvars terraform.tfvars

export TF_VAR_azure_blob_account_name="your-storage-account"
export TF_VAR_azure_blob_account_key="your-storage-key"
export TF_VAR_azure_blob_account_url="https://your-storage-account.blob.core.windows.net"
export TF_VAR_dify_secret_key="your-dify-secret-key"
export TF_VAR_postgresql_password="your-postgres-password"
export TF_VAR_redis_password="your-redis-password"
export TF_VAR_qdrant_api_key="your-qdrant-api-key"

./deploy.sh --auto-approve
```

`deploy.sh` runs `terraform apply` in the same shell, so it will see these env vars.

---

## Deploy script and var file

`deploy.sh` does **not** pass a var file to Terraform; it runs `terraform apply -auto-approve`, which uses:

- `terraform.tfvars` in the current directory (if present)
- Any `*.auto.tfvars` in the current directory
- Environment variables `TF_VAR_*` (for any variable not set in tfvars)

So for prod:

- **Local:** Copy an env file to `terraform.tfvars`, add secrets (Option 1) or set `TF_VAR_*` (Option 2), then run `./deploy.sh --auto-approve`.
- **With Terraform only first:** Run `terraform apply -auto-approve` (with secrets in tfvars or `TF_VAR_*`), then `./deploy.sh --app --auto-approve` to deploy only the app.

---

## Infrastructure Summary (Prod, No DR)

| Layer | Component | Prod (no DR) |
|-------|-----------|----------------|
| **Compute** | AKS | 1 cluster, `node_count` = 3, `vm_size` = Standard_D4s_v5 (or as in tfvars). No spot pool in prod. |
| **Database** | Azure PostgreSQL Flexible Server | Single server, GP SKU, 128GB storage, SSL required, firewall restricted (no “open all”). |
| **Network** | VNet (optional) | If `create_vnet_for_postgres = true`: VNet, Postgres subnet, optional management subnet, Private DNS, VNet peering to AKS. |
| **K8s add-ons** | Installed by `deploy.sh` | nginx-ingress (LoadBalancer), cert-manager, ClusterIssuers (Let’s Encrypt staging + prod). |
| **App** | Helm | Dify chart (API, Web, Worker, Beat, Sandbox, Plugin Daemon, Proxy, SSRF), Redis (Bitnami, in-cluster), Qdrant (in-cluster). |
| **Storage** | Azure Blob | For Dify file storage (account/container/URL in tfvars). |
| **Ingress** | Ingress + TLS | Host from `values.yaml` (e.g. `dify-prod.tichealth.com.au`), TLS via cert-manager. |

High-level flow:

```
Internet → nginx-ingress (LB) → Ingress (TLS) → Dify proxy → API/Web/Plugin
                                                      ↓
Azure PostgreSQL (Flexible, single server) ← API, Worker, Plugin Daemon
Redis (in-cluster) ← API, Worker, Beat
Qdrant (in-cluster) ← API, Worker
Azure Blob ← API, Worker, Plugin (files)
```

---

## Quick Checklist

1. Copy `environments/lite-prod.tfvars` or `environments/prod-full.tfvars` to `terraform.tfvars` (or use as `-var-file`).
2. Set in `terraform.tfvars` (or via `TF_VAR_*`):
   - `project_name`, `location`, `resource_group_name` (or leave blank to create).
   - `azure_blob_*`, `dify_secret_key`, `postgresql_password`, `redis_password`, `qdrant_api_key` (no placeholders).
3. Ensure `values.yaml` has the correct ingress host (e.g. `dify-prod.tichealth.com.au`) and any prod-specific settings.
4. Run:
   - Full: `./deploy.sh --auto-approve`
   - Or Terraform with prod var file, then `./deploy.sh --app --auto-approve`.
5. Point DNS for that host at the nginx LoadBalancer IP (`kubectl get svc -n ingress-nginx`).
6. Verify: `kubectl get pods -n dify`, `kubectl get certificate -n dify`.

---

## Files Reference

| File | Purpose |
|------|--------|
| `environments/lite-prod.tfvars` | Lite prod: 1 node, smaller DB (~250–350 AUD/mo). |
| `environments/prod-full.tfvars` | Full prod: 3 nodes, larger DB (~930–1,040 AUD/mo). |
| `environments/prod-no-dr.tfvars` | Legacy prod no-DR (single DB); prefer lite-prod or prod-full. |
| `terraform.tfvars` | Active Terraform vars (git-ignored); copy from an env file and fill secrets. |
| `values.yaml` | Helm values for Dify (ingress host, resources, images). |
| `deploy.sh` | Orchestrates Terraform + Helm (ingress, cert-manager, Dify). |
| `main.tf`, `variables.tf`, `outputs.tf` | Terraform infra (AKS, PostgreSQL, optional VNet, no read replicas). |

For more detail: [ARCHITECTURE.md](./ARCHITECTURE.md), [README.md](./README.md), [DEPLOYMENT_MODES.md](./DEPLOYMENT_MODES.md).
