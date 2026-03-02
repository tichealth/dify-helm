# GitHub Actions: Required Secrets and Variables

For the **Deploy or teardown Dify on AKS** workflow (`.github/workflows/deploy-aks.yml`), configure **Variables** and **Secrets** per **GitHub Environment** so each run uses the right credentials.

**Use GitHub Environments (dev, test, prod):** Create three environments under **Settings → Environments**: `dev`, `test`, `prod`. In each environment, add the Variables and Secrets listed below (same names, different values per env). The workflow selects the environment from your run input: **dev** / **test** use the `dev` / `test` environment; **lite-prod** and **prod-full** both use the `prod` environment. That way dev, test, and prod each get their own Azure SP, storage account, and passwords.

**Where to add them:** Repo → **Settings** → **Environments** → choose `dev`, `test`, or `prod` → **Environment variables** and **Environment secrets**.

**Passwords and keys are not stored in the repo.** Environment tfvars do not contain secret values. The workflow passes them to Terraform as `TF_VAR_*` from the active environment’s Variables and Secrets.

## Azure (service principal)

| Name | Description | Store as |
|------|-------------|----------|
| `ARM_CLIENT_ID` | Application (client) ID of the service principal | **Variable** |
| `ARM_TENANT_ID` | Directory (tenant) ID of the Azure AD tenant | **Variable** |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID | **Variable** |
| `ARM_CLIENT_SECRET` | Client secret **value** (the password) | **Secret** |

Create a service principal with Contributor (or appropriate) scope on the subscription or resource group used for Dify. [Azure: Create service principal](https://learn.microsoft.com/en-us/cli/azure/ad/sp/create-for-rbac).

### Fix: "Not all values are present. Ensure 'client-id' and 'tenant-id' are supplied"

This error means the Azure login step is missing one or more of the four values. Do the following:

1. **In GitHub:** Repo → **Settings** → **Environments** → select the environment used by the run (e.g. `prod`).
2. **Environment variables:** add `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`.
3. **Environment secrets:** add `ARM_CLIENT_SECRET` — the client secret **value** (the secret string, not the secret ID).
4. **Get the values from Azure:**
   - **Option A (Azure Portal):** Azure AD → App registrations → your app → Overview (Application ID, Directory ID). Certificates & secrets → create a client secret and copy its **Value** (only shown once).
   - **Option B (Azure CLI):** See "Create service principal (one-time)" below.
5. **Subscription ID:** Azure Portal → Subscriptions, or run: `az account show --query id -o tsv`.
6. Re-run the workflow.

**Create service principal (one-time)** — run locally with Azure CLI:

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
az ad sp create-for-rbac --name "dify-aks-github" --role Contributor --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID>
```

From the JSON output: use `appId` → Variable `ARM_CLIENT_ID`, `tenant` → Variable `ARM_TENANT_ID`, `password` → Secret `ARM_CLIENT_SECRET`. Use your subscription ID for Variable `ARM_SUBSCRIPTION_ID`.

**Checklist:** In each environment (dev, test, prod), three variables and one secret; names exact (case-sensitive); `ARM_CLIENT_SECRET` is the secret **value** not the secret ID.

## Terraform / Dify (passed as TF_VAR_*)

The workflow sets these as Terraform environment variables from the **active GitHub Environment’s** Variables and Secrets; they are never written into tfvars. Add them in each environment (dev, test, prod) with values for that env.

| Name | Purpose | Store as |
|------|---------|----------|
| `AZURE_BLOB_ACCOUNT_NAME` | Dify blob + Terraform backend storage account name | **Variable** |
| `BACKEND_RESOURCE_GROUP` | Resource group where the storage account lives (for Terraform backend only) | **Variable** |
| `AZURE_BLOB_ACCOUNT_KEY` | Dify blob + Terraform backend access key | **Secret** |
| `DIFY_SECRET_KEY` | `TF_VAR_dify_secret_key` | **Secret** |
| `POSTGRESQL_PASSWORD` | `TF_VAR_postgresql_password` | **Secret** |
| `REDIS_PASSWORD` | `TF_VAR_redis_password` | **Secret** |
| `QDRANT_API_KEY` | `TF_VAR_qdrant_api_key` | **Secret** |

### Set up AZURE_BLOB_ACCOUNT_NAME and AZURE_BLOB_ACCOUNT_KEY

Terraform does **not** create the Storage Account. You need an existing Azure Storage account (any resource group in the same subscription).

**Two different uses of Blob storage (same account, different containers):**

| Purpose | Container | Used by |
|--------|-----------|---------|
| **Terraform state** | `tfstate` | Terraform remote backend (state file per environment). Does **not** hold Dify data. |
| **Dify file storage** | e.g. `difydata` | Dify app only; set via `azure_blob_container_name` in tfvars. |

**Remote backend is enabled:** Terraform state is stored in the **tfstate** container (same storage account as above). The workflow runs `terraform init -reconfigure` with backend config. You need a **Variable** `BACKEND_RESOURCE_GROUP` = the resource group where the storage account lives (e.g. `rg-cme-prod`). State file key is `{environment}.terraform.tfstate` (e.g. `dev.terraform.tfstate`, `lite-prod.terraform.tfstate`).

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

## Terraform remote backend (local runs)

For **local** runs (e.g. `./deploy.sh`), Terraform uses the same **azurerm** backend. Create `deployments/aks/backend.azurerm.tfvars` from `backend.azurerm.tfvars.example`, set `resource_group_name`, `storage_account_name`, `container_name` = `tfstate`, `key` (e.g. `dev.terraform.tfstate`), and `access_key` (same as Blob key). Do not commit `backend.azurerm.tfvars`. Then `deploy.sh` will run `terraform init -reconfigure -backend-config=backend.azurerm.tfvars` automatically.

## Optional

- **Environments:** In the workflow you can add `environment: aks-deploy` (and create that environment in Settings → Environments) to require approvals before deploy/teardown.

## Workflow inputs (manual run)

When you click **Run workflow** you choose:

- **action:** `deploy` or `teardown`
- **deploy_mode:** `all`, `app`, or `db` (only when action = deploy)
- **environment:** `dev`, `test`, `lite-prod`, or `prod-full` (picks the tfvars file **and** the GitHub Environment for secrets/variables)
- **auto_approve:** skip confirmation prompts (default: true)

**How environment is used:** The selected value chooses both (1) which tfvars file is copied (e.g. `dev.tfvars`, `lite-prod.tfvars`) and (2) which GitHub Environment’s Variables and Secrets are used. Mapping: **dev** → env `dev`, **test** → env `test`, **lite-prod** and **prod-full** → env `prod`. So create GitHub Environments named exactly `dev`, `test`, and `prod`, and add the Variables and Secrets to each.
