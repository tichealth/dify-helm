# GitHub Actions configuration

This is the single reference for variables, secrets, state mapping, and approvals
used by `.github/workflows/deploy-aks.yml`.

## Environment mapping

Create GitHub Environments named `dev`, `uat`, and `prod` under **Settings ->
Environments**. The workflow maps its input as follows:

| Workflow input | GitHub Environment | Terraform profile | Backend key |
| --- | --- | --- | --- |
| `dev` | `dev` | `dev.tfvars` | `dev.terraform.tfstate` |
| `uat` | `uat` | `uat.tfvars` | `uat.terraform.tfstate` |
| `lite-prod` | `prod` | `lite-prod.tfvars` | `prod.terraform.tfstate` |
| `prod-full` | `prod` | `prod-full.tfvars` | `prod.terraform.tfstate` |

`lite-prod` and `prod-full` deliberately describe the same Prod state at two
sizes. UAT is isolated; never reuse a Dev or Prod backend key for it.

## Required configuration

Add these to each GitHub Environment. Values must be unique per environment
unless the row explicitly describes shared backend infrastructure.

| Name | Kind | Purpose |
| --- | --- | --- |
| `AZURE_CREDENTIALS` | Secret | Azure service-principal JSON |
| `AZURE_BLOB_ACCOUNT_NAME` | Variable | Terraform backend storage account |
| `BACKEND_RESOURCE_GROUP` | Variable | Resource group containing that account |
| `AZURE_BLOB_ACCOUNT_KEY` | Secret | Terraform backend access key |
| `DIFY_SECRET_KEY` | Secret | Dify signing/encryption key |
| `POSTGRESQL_PASSWORD` | Secret | Azure PostgreSQL password |
| `REDIS_PASSWORD` | Secret | In-cluster Redis password |
| `QDRANT_API_KEY` | Secret | Dify vector-store key; also provisions UAT Qdrant |
| `PLUGIN_DAEMON_SERVER_KEY` | Secret | Required for UAT; unique plugin server key |
| `PLUGIN_DAEMON_DIFY_API_KEY` | Secret | Required for UAT; unique plugin-to-Dify key |
| `PHOENIX_OTLP_ENDPOINT` | Variable | Optional OTLP HTTP base URL; omit to disable |

`AZURE_CREDENTIALS` uses this exact shape:

```json
{"clientId":"<APP_ID>","clientSecret":"<SECRET_VALUE>","tenantId":"<TENANT_ID>","subscriptionId":"<SUBSCRIPTION_ID>"}
```

The identity needs permissions to manage the in-scope resource groups, AKS,
networking, PostgreSQL, storage, and public IPs. Create one if needed:

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
az ad sp create-for-rbac --name "dify-aks-github" --role Contributor \
  --scopes "/subscriptions/<SUBSCRIPTION_ID>"
```

Use the returned `appId`, `password`, and `tenant` as `clientId`, `clientSecret`,
and `tenantId`. Store the secret value, not its Azure object ID.

Generate application keys locally, then copy each value directly into GitHub:

```bash
cd deployments/aks
bash scripts/generate-secrets.sh
```

Never commit generated values or paste them into a tracked environment tfvars.

## Terraform backend prerequisite

The workflow expects an existing Azure Storage account and a private container
named `tfstate`. It does not create them.

```bash
az storage account create --name "<UNIQUE_NAME>" --resource-group "<BACKEND_RG>" \
  --location australiaeast --sku Standard_LRS
az storage container create --name tfstate --account-name "<UNIQUE_NAME>" \
  --auth-mode key
az storage account keys list --resource-group "<BACKEND_RG>" \
  --account-name "<UNIQUE_NAME>" --query '[0].value' -o tsv
```

The storage account is currently for Terraform state. Dify and plugin files use
Azure File PVCs; the declared Blob variables are not application object-storage
wiring.

## Approvals and workflow use

Add required reviewers to `dev`, `uat`, and especially `prod`. Both plan and apply
jobs reference the selected GitHub Environment, so protected environments may ask
for approval twice. Review the saved Terraform plan before approving apply.

Run **Actions -> Deploy or teardown Dify on AKS -> Run workflow**:

| Input | Choices / rule |
| --- | --- |
| `enabled` | Must be checked; unchecked is a safe no-op |
| `action` | `deploy`, `teardown`, or `force-unlock` |
| `environment` | `dev`, `uat`, `lite-prod`, or `prod-full` |
| `deploy_mode` | `all`, `app`, or `db` for deploy |
| `lock_id` | Required only for `force-unlock` |

Runs are serialized per environment. Kubernetes upgrades are not part of this
workflow; use [AKS_KUBERNETES_UPGRADE.md](./AKS_KUBERNETES_UPGRADE.md).

For a stale state lock, first confirm no plan/apply is active. Then run
`action=force-unlock` with the matching environment and the UUID printed by
Terraform. Never unlock one environment while another process is using its state.

## Local equivalent

Create ignored `terraform.tfvars` and `backend.azurerm.tfvars` from their example
files. The backend key must match the table above. Export secrets instead of
writing them to disk when practical:

```bash
export TF_VAR_azure_blob_account_name="<backend-account>"
export TF_VAR_azure_blob_account_key="<backend-key>"
export TF_VAR_azure_blob_account_url="https://<backend-account>.blob.core.windows.net"
export TF_VAR_dify_secret_key="<value>"
export TF_VAR_postgresql_password="<value>"
export TF_VAR_redis_password="<value>"
export TF_VAR_qdrant_api_key="<value>"

# UAT only
export PLUGIN_DAEMON_SERVER_KEY="<value>"
export PLUGIN_DAEMON_DIFY_API_KEY="<value>"
```

Then select the matching profile and run `./deploy.sh`. See
[README.md](./README.md#deploy) for modes.
