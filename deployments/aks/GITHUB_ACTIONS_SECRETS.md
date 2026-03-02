# GitHub Actions: Required Secrets

For the **Deploy or teardown Dify on AKS** workflow (`.github/workflows/deploy-aks.yml`), configure **Variables** and **Secrets** in GitHub: **Settings → Secrets and variables → Actions**.

**Passwords and keys are not stored in the repo.** Environment tfvars do not contain secret values. The workflow passes them to Terraform as `TF_VAR_*` from **Variables** (identifiers, e.g. account name) and **Secrets** (passwords, keys).

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

1. **In GitHub:** Repo → **Settings** → **Secrets and variables** → **Actions**.
2. **Variables** (tab): add `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`.
3. **Secrets** (tab): add `ARM_CLIENT_SECRET` — the client secret **value** (the secret string, not the secret ID).
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

**Checklist:** Three variables and one secret; names exact (case-sensitive); `ARM_CLIENT_SECRET` is the secret **value** not the secret ID.

## Terraform / Dify (passed as TF_VAR_*)

The workflow sets these as Terraform environment variables from Variables and Secrets; they are never written into tfvars.

| Name | Terraform variable | Store as |
|------|--------------------|----------|
| `AZURE_BLOB_ACCOUNT_NAME` | `TF_VAR_azure_blob_account_name` (and used to build `TF_VAR_azure_blob_account_url`) | **Variable** |
| `AZURE_BLOB_ACCOUNT_KEY` | `TF_VAR_azure_blob_account_key` | **Secret** |
| `DIFY_SECRET_KEY` | `TF_VAR_dify_secret_key` | **Secret** |
| `POSTGRESQL_PASSWORD` | `TF_VAR_postgresql_password` | **Secret** |
| `REDIS_PASSWORD` | `TF_VAR_redis_password` | **Secret** |
| `QDRANT_API_KEY` | `TF_VAR_qdrant_api_key` | **Secret** |

## Optional

- **Environments:** In the workflow you can add `environment: aks-deploy` (and create that environment in Settings → Environments) to require approvals before deploy/teardown.
- **Terraform backend:** For persistent state across runs, configure a remote backend (e.g. `azurerm`) in Terraform and set any required backend config (e.g. `ARM_ACCESS_KEY`) as secrets or variables.

## Workflow inputs (manual run)

When you click **Run workflow** you choose:

- **action:** `deploy` or `teardown`
- **deploy_mode:** `all`, `app`, or `db` (only when action = deploy)
- **environment:** `dev`, `test`, `lite-prod`, or `prod-full` (which tfvars file to use; each environment is separate)
- **auto_approve:** skip confirmation prompts (default: true)

**Environments:** Dev and test use `environments/dev.tfvars` and `environments/test.tfvars`. Prod uses `lite-prod` or `prod-full`. The same GitHub Secrets are used for all; for different credentials per environment, use [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments) and set secrets per environment.
