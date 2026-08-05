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

Do **not** add `ARM_CLIENT_ID`, `ARM_TENANT_ID`, or `ARM_SUBSCRIPTION_ID` —
the workflow derives them from `AZURE_CREDENTIALS` at runtime.

| Name | Kind | Required | Purpose |
| --- | --- | --- | --- |
| `AZURE_CREDENTIALS` | Secret | Always | Azure service-principal JSON |
| `AZURE_BLOB_ACCOUNT_NAME` | Variable | Always | Terraform backend storage account |
| `BACKEND_RESOURCE_GROUP` | Variable | Always | Resource group containing that account |
| `AZURE_BLOB_ACCOUNT_KEY` | Secret | Always | Terraform backend access key |
| `DIFY_SECRET_KEY` | Secret | Always | Dify signing/encryption key |
| `POSTGRESQL_PASSWORD` | Secret | Always | Azure PostgreSQL password |
| `REDIS_PASSWORD` | Secret | Always | In-cluster Redis password |
| `QDRANT_API_KEY` | Secret | Always | Dify vector-store key; also provisions UAT Qdrant |
| `PLUGIN_DAEMON_SERVER_KEY` | Secret | UAT only | Unique plugin server key |
| `PLUGIN_DAEMON_DIFY_API_KEY` | Secret | UAT only | Unique plugin-to-Dify key |
| `PHOENIX_OTLP_ENDPOINT` | Variable | Optional | OTLP HTTP base URL; omit to disable |

## How to create them (per environment)

> **First-time setup only.** This section describes standing up a **new**
> environment. Do not follow it to "refresh" a live environment — regenerating
> `DIFY_SECRET_KEY`, `POSTGRESQL_PASSWORD`, or `REDIS_PASSWORD` against a running
> Dev/Prod is destructive. See [Rotating secrets on a live environment](#rotating-secrets-on-a-live-environment).

1. Open the repo → **Settings → Environments → New environment** (or open `dev` / `uat` / `prod`).
2. Add required reviewers for apply gates (especially `prod` and `uat`).
3. Under **Environment secrets** / **Environment variables**, create the rows below.

### A. Azure service principal (AZURE_CREDENTIALS)

Reuse an existing SP if it already has Contributor on the subscription, or create one:

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
az ad sp create-for-rbac --name "dify-aks-github" --role Contributor \
  --scopes "/subscriptions/<SUBSCRIPTION_ID>"
```

Paste this exact JSON as the secret value (use the returned `appId` /
`password` / `tenant`, plus your subscription ID):

```json
{"clientId":"<APP_ID>","clientSecret":"<SECRET_VALUE>","tenantId":"<TENANT_ID>","subscriptionId":"<SUBSCRIPTION_ID>"}
```

Store the secret **value**, not its Azure object ID. Do not add separate
`ARM_*` GitHub variables.

### B. Terraform backend

The workflow does **not** create the backend resource group, storage account, or
container. Create them once per environment:

```bash
BACKEND_RG=rg-dify-tfstate-uat        # backend RG (holds state only)
SA=stdifytfstateuat                   # 3-24 chars, lowercase letters/digits, globally unique
LOCATION=australiaeast

az group create --name "$BACKEND_RG" --location "$LOCATION"

az storage account create --name "$SA" --resource-group "$BACKEND_RG" \
  --location "$LOCATION" --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false

az storage container create --name tfstate --account-name "$SA" --auth-mode login

az storage account keys list -g "$BACKEND_RG" -n "$SA" --query '[0].value' -o tsv
```

Then set:

| GitHub name | Kind | Value |
| --- | --- | --- |
| `AZURE_BLOB_ACCOUNT_NAME` | Variable | The storage account name (`$SA`) |
| `BACKEND_RESOURCE_GROUP` | Variable | The backend RG (`$BACKEND_RG`) |
| `AZURE_BLOB_ACCOUNT_KEY` | Secret | The key printed by the last command |

This RG is **only** for Terraform state. The RG that holds AKS, PostgreSQL, and
networking is created by Terraform itself when `resource_group_name = ""` in the
environment tfvars (UAT and Dev), or must already exist when a name is set
(`rg-cme-prod` for both Prod profiles).

UAT should use its **own** backend account/key (or at least its own state key
`uat.terraform.tfstate`). Never point UAT at Dev or Prod state.

### C. Application secrets

> **New environments only.** On a live environment these values are load-bearing;
> see [Rotating secrets on a live environment](#rotating-secrets-on-a-live-environment).

```bash
cd deployments/aks
bash scripts/generate-secrets.sh
```

Copy each printed line into the matching **Environment secret**:

- Always: `DIFY_SECRET_KEY`, `POSTGRESQL_PASSWORD`, `REDIS_PASSWORD`, `QDRANT_API_KEY`
- UAT only: `PLUGIN_DAEMON_SERVER_KEY`, `PLUGIN_DAEMON_DIFY_API_KEY`

Generate **fresh** values per environment. Never reuse Dev/Prod keys for UAT.
Never commit the script output or paste it into tracked tfvars.

### D. Optional Phoenix tracing

Set only if this environment should export OTLP traces (e.g.
`https://<phoenix-host>/v1/traces`). Leave unset to disable.

## Rotating secrets on a live environment

Creating a new environment is safe. Changing these on a **running** environment
is not — read this before touching Dev or Prod.

| Secret | Effect of changing it on a live environment |
| --- | --- |
| `DIFY_SECRET_KEY` | **Destructive.** Dify cannot decrypt stored model-provider credentials and API keys encrypted with the old key. Re-enter them after rotating. |
| `POSTGRESQL_PASSWORD` | Terraform resets the flexible-server admin password. Any other consumer holding the old value (e.g. Phoenix in `dify-arize-ai`) breaks until updated. |
| `REDIS_PASSWORD` | Redis release is updated and pods restart; queued background jobs are lost. |
| `QDRANT_API_KEY` | Dify loses access to the vector store until every component is redeployed with the new value. |
| `PLUGIN_DAEMON_*` | Plugin daemon and API must be redeployed together, otherwise plugins fail to authenticate. |
| `AZURE_BLOB_ACCOUNT_KEY` | Safe. Rotate whenever the storage key is rotated; affects Terraform state access only. |
| `AZURE_CREDENTIALS` | Safe. Rotate on SP secret expiry. |

Rotate one secret at a time, during a maintenance window, and redeploy with
`deploy_mode=all` so every component picks up the new value together.

The backend storage account holds Terraform state only. Dify and plugin files
use Azure File PVCs; the declared Blob variables are not application
object-storage wiring.

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
workflow; use [UPGRADE_KUBERNETES.md](./UPGRADE_KUBERNETES.md).

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
