# GitHub Actions: Required Secrets

For the **Deploy or teardown Dify on AKS** workflow (`.github/workflows/deploy-aks.yml`), add these **repository secrets** in GitHub: **Settings → Secrets and variables → Actions → New repository secret**.

**Passwords and keys are not stored in the repo.** Environment tfvars (`lite-prod.tfvars`, `prod-full.tfvars`, etc.) do not contain any secret values. The workflow passes them to Terraform as `TF_VAR_*` from these secrets.

## Azure (service principal)

| Secret name | Description |
|-------------|-------------|
| `ARM_CLIENT_ID` | Azure AD app (service principal) Application (client) ID |
| `ARM_CLIENT_SECRET` | Service principal client secret |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID |
| `ARM_TENANT_ID` | Azure AD tenant ID |

Create a service principal with Contributor (or appropriate) scope on the subscription or resource group used for Dify. [Azure: Create service principal](https://learn.microsoft.com/en-us/cli/azure/ad/sp/create-for-rbac).

## Terraform / Dify (passed as TF_VAR_*)

The workflow sets these as Terraform environment variables from secrets; they are never written into tfvars.

| Secret name | Terraform variable |
|-------------|--------------------|
| `AZURE_BLOB_ACCOUNT_NAME` | `TF_VAR_azure_blob_account_name` (and used to build `TF_VAR_azure_blob_account_url`) |
| `AZURE_BLOB_ACCOUNT_KEY` | `TF_VAR_azure_blob_account_key` |
| `DIFY_SECRET_KEY` | `TF_VAR_dify_secret_key` |
| `POSTGRESQL_PASSWORD` | `TF_VAR_postgresql_password` |
| `REDIS_PASSWORD` | `TF_VAR_redis_password` |
| `QDRANT_API_KEY` | `TF_VAR_qdrant_api_key` |

## Optional

- **Environments:** In the workflow you can add `environment: aks-deploy` (and create that environment in Settings → Environments) to require approvals before deploy/teardown.
- **Terraform backend:** For persistent state across runs, configure a remote backend (e.g. `azurerm`) in Terraform and set any required backend config (e.g. `ARM_ACCESS_KEY`) as secrets or variables.

## Workflow inputs (manual run)

When you click **Run workflow** you choose:

- **action:** `deploy` or `teardown`
- **deploy_mode:** `all`, `app`, or `db` (only when action = deploy)
- **environment:** `lite-prod` or `prod-full` (which tfvars file to use)
- **auto_approve:** skip confirmation prompts (default: true)
