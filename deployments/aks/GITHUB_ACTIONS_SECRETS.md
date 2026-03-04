# GitHub Actions: Required Secrets and Variables

For the **Deploy or teardown Dify on AKS** workflow (`.github/workflows/deploy-aks.yml`), configure **Variables** and **Secrets** per **GitHub Environment** so each run uses the right credentials.

**Use GitHub Environments (dev, test, prod):** Create three environments under **Settings → Environments**: `dev`, `test`, `prod`. In each environment, add the Variables and Secrets listed below (same names, different values per env). The workflow selects the environment from your run input: **dev** / **test** use the `dev` / `test` environment; **lite-prod** and **prod-full** both use the `prod` environment. That way dev, test, and prod each get their own Azure SP, storage account, and passwords.

**Where to add them:** Repo → **Settings** → **Environments** → choose `dev`, `test`, or `prod` → **Environment variables** and **Environment secrets**.

**Passwords and keys are not stored in the repo.** Environment tfvars do not contain secret values. The workflow passes them to Terraform as `TF_VAR_*` from the active environment’s Variables and Secrets.

## Azure (service principal) — use one JSON secret

The workflow uses **client-secret auth only** (no OIDC/federated credentials). Add a single **Environment secret** so login never falls back to OIDC:

| Name | Description | Store as |
|------|-------------|----------|
| `AZURE_CREDENTIALS` | JSON with `clientId`, `clientSecret`, `tenantId`, `subscriptionId` | **Secret** |

**Format (one line, no extra spaces):**

```json
{"clientId":"<APP_ID>","clientSecret":"<SECRET_VALUE>","tenantId":"<TENANT_ID>","subscriptionId":"<SUBSCRIPTION_ID>"}
```

Create a service principal with Contributor (or appropriate) scope on the subscription or resource group used for Dify. [Azure: Create service principal](https://learn.microsoft.com/en-us/cli/azure/ad/sp/create-for-rbac).

### Fix: "Failed to fetch federated token" or "Not all values are present"

The workflow does **not** use OIDC. Ensure you have **one** secret `AZURE_CREDENTIALS` (not four separate vars/secrets). Do the following:

1. **In GitHub:** Repo → **Settings** → **Environments** → select the environment (e.g. `prod`).
2. **Environment secrets:** add `AZURE_CREDENTIALS` with the JSON above. Keys must be exactly: `clientId`, `clientSecret`, `tenantId`, `subscriptionId` (camelCase).
3. **Get the values from Azure:**
   - **Option A (Azure Portal):** Azure AD → App registrations → your app → Overview (Application ID = clientId, Directory ID = tenantId). Certificates & secrets → create a client secret, copy its **Value** = clientSecret. Subscriptions → copy subscription ID = subscriptionId.
   - **Option B (Azure CLI):** See below.
4. Re-run the workflow.

**Create service principal (one-time)** — run locally with Azure CLI:

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
az ad sp create-for-rbac --name "dify-aks-github" --role Contributor --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID>
```

From the JSON output: `appId` → clientId, `password` → clientSecret, `tenant` → tenantId. Add your subscription ID as subscriptionId. Build the JSON and paste as the **value** of secret `AZURE_CREDENTIALS`.

**Checklist:** In each environment (dev, test, prod), one secret `AZURE_CREDENTIALS`; keys are camelCase; `clientSecret` is the secret **value** not the secret ID.

## Terraform / Dify (passed as TF_VAR_*)

The workflow sets these as Terraform environment variables from the **active GitHub Environment’s** Variables and Secrets; they are never written into tfvars. **deploy.sh** also reads these (TF_VAR_* or terraform.tfvars) and passes them to Helm so values.yaml has no real secrets. Add them in each environment (dev, test, prod) with values for that env.

| Name | Purpose | Store as |
|------|---------|----------|
| `AZURE_BLOB_ACCOUNT_NAME` | Dify blob + Terraform backend storage account name | **Variable** |
| `BACKEND_RESOURCE_GROUP` | Resource group where the storage account lives (for Terraform backend only) | **Variable** |
| `AZURE_BLOB_ACCOUNT_KEY` | Dify blob + Terraform backend access key | **Secret** |
| `DIFY_SECRET_KEY` | `TF_VAR_dify_secret_key` | **Secret** |
| `POSTGRESQL_PASSWORD` | `TF_VAR_postgresql_password` | **Secret** |
| `REDIS_PASSWORD` | `TF_VAR_redis_password` | **Secret** |
| `QDRANT_API_KEY` | `TF_VAR_qdrant_api_key` → Helm `externalQdrant.apiKey` | **Secret** | deploy.sh → Helm |

**values.yaml** contains only placeholders; real values come from GitHub Secrets (CI) or terraform.tfvars / TF_VAR_* (local). See [Secrets for local runs](#secrets-for-local-runs).

### PostgreSQL firewall

Use **`postgres_open_firewall_all = true`** in the environment tfvars used by CI (e.g. lite-prod) so AKS pods and the runner can reach Postgres. Otherwise Helm can time out. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md#0-azure-postgresql-firewall-helm-times-out--pods-never-ready).

### Set up AZURE_BLOB_ACCOUNT_NAME and AZURE_BLOB_ACCOUNT_KEY

Terraform does **not** create the Storage Account. You need an existing Azure Storage account (any resource group in the same subscription).

**Two different uses of Blob storage (same account, different containers):**

| Purpose | Container | Used by |
|--------|-----------|---------|
| **Terraform state** | `tfstate` | Terraform remote backend (state file per environment). Does **not** hold Dify data. |
| **Dify file storage** | e.g. `difydata` | Dify app only; set via `azure_blob_container_name` in tfvars. |

**Remote backend is enabled:** Terraform state is stored in the **tfstate** container (same storage account as above). The workflow runs `terraform init -reconfigure` with backend config. You need a **Variable** `BACKEND_RESOURCE_GROUP` = the resource group where the storage account lives (e.g. `rg-cme-prod`). State file key: `dev` → `dev.terraform.tfstate`, `test` → `test.terraform.tfstate`, **lite-prod and prod-full** → **`prod.terraform.tfstate`**.

**Why Dify needs a container:** Dify uses object storage for **application file storage** — user uploads (documents, images), dataset files, and generated assets. The API and worker pods need a shared, persistent place for these files. Without a blob container, Dify would use local pod disk, which is not shared across pods and is lost on restart. So you need a **separate** container from `tfstate`: one for Terraform state, one for Dify data.

**Storage account name:** Use your storage account (e.g. `stcmedifyhelmprod`). Same key is used for both containers (tfstate and difydata).

**Good practice:** One storage account per environment with two containers: `tfstate` (Terraform backend, optional) and `difydata` (Dify app). The workflow’s `AZURE_BLOB_*` and tfvars `azure_blob_container_name` refer to **Dify storage only** (not tfstate).

**1. Create a Storage Account (if you don’t have one)**

**Azure Portal:** Storage accounts → Create → subscription, resource group (e.g. `rg-cme-prod`), unique name (e.g. `stcmedifyhelmprod`), region, Standard_LRS → Create.

**Azure CLI:**

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
az storage account create \
  --name "stcmedifyhelmprod" \
  --resource-group "rg-cme-prod" \
  --location "australiaeast" \
  --sku Standard_LRS
```

**2. Create Blob containers**

Create at least the **Dify** container. Name is configurable in tfvars (`azure_blob_container_name`); env files use `difydata`.

**Portal:** Storage account → Containers → + Container → e.g. `tfstate`, then `difydata` (or `dify-data` to match current tfvars).

**CLI (e.g. both containers):**

```bash
az storage container create --name "tfstate"   --account-name "stcmedifyhelmprod" --auth-mode key
az storage container create --name "difydata"  --account-name "stcmedifyhelmprod" --auth-mode key
```

If you use `difydata`, set `azure_blob_container_name = "difydata"` in each env tfvars file.

**3. Get the account name and key**

- **Account name:** Your storage account name (e.g. `stcmedifyhelmprod`). Add as GitHub **Variable** `AZURE_BLOB_ACCOUNT_NAME`.
- **Key:** One of the two access keys. Add as GitHub **Secret** `AZURE_BLOB_ACCOUNT_KEY`.

**Portal:** Storage account → Access keys → Show key1 → Copy **Key** value.

**CLI:**

```bash
az storage account keys list \
  --resource-group "rg-cme-prod" \
  --account-name "stcmedifyhelmprod" \
  --query "[0].value" -o tsv
```

**4. Add to each GitHub Environment**

- **Environment variables:** `AZURE_BLOB_ACCOUNT_NAME` (e.g. `stcmedifyhelmprod` for prod), and `BACKEND_RESOURCE_GROUP` (e.g. `rg-cme-prod`) — required for Terraform remote backend in CI.
- **Environment secrets:** `AZURE_BLOB_ACCOUNT_KEY` = the key from step 3 (used for both Dify blob and Terraform backend).

Use one storage account per environment (e.g. different account names in dev vs prod) so each GitHub Environment has its own credentials.

### Generate secret values

You can generate strong random values for the four secrets above. **Use each value only once** and store them in GitHub Secrets (do not commit).

**Option A — Script (Git Bash, WSL, or Linux/macOS):**

```bash
cd deployments/aks && bash scripts/generate-secrets.sh
```

Use `bash scripts/generate-secrets.sh` (not `./generate-secrets.sh`) so it works even if the file has Windows line endings. If you see `'bash\r': No such file or directory`, run the same command with `bash` in front.

Copy each line’s value into the matching GitHub Secret. The script uses `openssl rand` (Dify recommends base64 42 for `SECRET_KEY`).

**Option B — One-liners:**

| Secret | Bash (openssl) | PowerShell (crypto-safe) |
|--------|----------------|-------------------------|
| `DIFY_SECRET_KEY` | `openssl rand -base64 42` | `[Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(42))` |
| `POSTGRESQL_PASSWORD` | `openssl rand -base64 32` | `[Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))` |
| `REDIS_PASSWORD` | `openssl rand -base64 32` | (same as POSTGRESQL_PASSWORD) |
| `QDRANT_API_KEY` | `openssl rand -hex 32` | `[BitConverter]::ToString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).Replace('-','').ToLower()` |

**Note:** `AZURE_BLOB_ACCOUNT_KEY` comes from Azure (Storage account → Access keys), not from these generators.

## Secrets for local runs

For **local** runs (e.g. `./deploy.sh`), **deploy.sh** reads secrets from (in order):

1. **Environment variables:** `TF_VAR_postgresql_password`, `TF_VAR_dify_secret_key`, `TF_VAR_redis_password`, `TF_VAR_qdrant_api_key`
2. **terraform.tfvars:** if a TF_VAR is unset, deploy.sh parses `terraform.tfvars` in the same directory for the matching key.

So you can either `export TF_VAR_...` in the shell or put the secrets in **terraform.tfvars** (do not commit that file). Required keys for Helm (so Dify works) are:

| In terraform.tfvars (or TF_VAR_*) | Helm value | Required for |
|-----------------------------------|------------|--------------|
| `postgresql_password`             | externalPostgres.password | Azure Postgres + Dify API/worker/plugin-daemon |
| `dify_secret_key`                 | global.appSecretKey      | Dify app signing/session |
| `redis_password`                  | redis.auth.password      | Redis (in-cluster) |
| `qdrant_api_key`                  | externalQdrant.apiKey    | Qdrant vector DB |

Copy `environments/<env>.tfvars` to `terraform.tfvars`, then add the secret variables. See `environments/prod.tfvars.example` for a full example including placeholders for these and other optional vars (e.g. Azure blob for state).

## Terraform remote backend (local runs)

For **local** runs (e.g. `./deploy.sh`), Terraform uses the same **azurerm** backend. Create `deployments/aks/backend.azurerm.tfvars` from `backend.azurerm.tfvars.example`, set `resource_group_name`, `storage_account_name`, `container_name` = `tfstate`, `key` (e.g. `dev.terraform.tfstate` for dev, **`prod.terraform.tfstate`** for lite-prod or prod-full), and `access_key`. Do not commit `backend.azurerm.tfvars`. Then `deploy.sh` will run `terraform init -reconfigure -backend-config=backend.azurerm.tfvars` automatically.

## Optional

- **Environments:** In the workflow you can add `environment: aks-deploy` (and create that environment in Settings → Environments) to require approvals before deploy/teardown.

## Status badge, unpin, disable

- **Status badge:** Add to your README (replace OWNER/REPO):
  ```markdown
  [![Deploy or teardown Dify on AKS](https://github.com/OWNER/REPO/actions/workflows/deploy-aks.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/deploy-aks.yml)
  ```
- **Unpin workflow:** In the Actions tab, click the workflow → click the **pin** icon (if it’s pinned) to unpin it so it doesn’t stay at the top of the list.
- **Disable by default:** The workflow has an input **“Enable workflow run”** (default **unchecked**). The job runs only when that box is checked. Leave it unchecked to avoid running; check it when you want to deploy or teardown.

## Workflow inputs (manual run)

When you click **Run workflow** you choose:

- **enabled:** Check to allow the workflow to run (default: unchecked = disabled).
- **action:** `deploy` or `teardown`
- **deploy_mode:** `all`, `app`, or `db` (only when action = deploy)
- **environment:** `dev`, `test`, `lite-prod`, or `prod-full` (picks the tfvars file **and** the GitHub Environment for secrets/variables)
- **auto_approve:** skip confirmation prompts (default: false)

**How environment is used:** The selected value chooses both (1) which tfvars file is copied (e.g. `dev.tfvars`, `lite-prod.tfvars`) and (2) which GitHub Environment’s Variables and Secrets are used. Mapping: **dev** → env `dev`, **test** → env `test`, **lite-prod** and **prod-full** → env `prod`. So create GitHub Environments named exactly `dev`, `test`, and `prod`, and add the Variables and Secrets to each.

## Troubleshooting: Can't run the workflow

- **"Run workflow" not showing or disabled**  
  The workflow only runs when triggered manually. Go to **Actions** → select **"Deploy or teardown Dify on AKS"** in the left sidebar → use the **Run workflow** dropdown. Choose the **branch** that contains this workflow file (e.g. `main`). If the workflow isn't on the default branch, run from the branch where `.github/workflows/deploy-aks.yml` exists. You need **write** access to the repo to run it.

- **Workflow fails immediately with "Environment X could not be found"**  
  The job uses a GitHub Environment (`dev`, `test`, or `prod`). Create them first: **Settings** → **Environments** → **New environment** → add `dev`, `test`, and `prod`. You can leave protection rules empty. Then add the Variables and Secrets to each environment.

- **Workflow is waiting for approval**  
  If an environment has **Required reviewers**, someone must approve the run. Either approve it or edit the environment and remove the required reviewers.

- **Workflow file not on GitHub yet**  
  Commit and push `.github/workflows/deploy-aks.yml` (and the rest of the repo). After push, the workflow appears under Actions and you can run it from the branch you pushed to.
