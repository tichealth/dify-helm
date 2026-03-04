# Secrets and Passwords – Never Commit

These files can contain real credentials and **must not be committed**:

| File | Contains | Status |
|------|----------|--------|
| `terraform.tfvars` | postgresql_password, dify_secret_key, redis_password, qdrant_api_key, azure_blob_account_key | Ignored via `.gitignore` |
| `backend.azurerm.tfvars` | access_key (storage account key) | Ignored via `.gitignore` |
| `terraform.tfvars.dev` (and any `*.tfvars` in this dir except under `environments/`) | Same as above if you put secrets there | Ignored via `*.tfvars` |

**Tracked files** (safe to commit): only `terraform.tfvars.example`, `backend.azurerm.tfvars.example`, and `environments/*.tfvars` / `environments/*.tfvars.example`. The tracked env tfvars do **not** contain secret values; secrets are set via `TF_VAR_*` or in a local (gitignored) `terraform.tfvars`.

**If you ever committed a file that had real secrets:**

1. Rotate every credential that was in it (Postgres password, Dify secret key, Redis password, Qdrant API key, Azure storage key).
2. Remove the file from history (e.g. `git filter-repo` or BFG) or treat the repo as compromised and create a new one; then update all systems with the new credentials.

**Local use:** Keep real secrets only in `terraform.tfvars` (or in environment variables `TF_VAR_*`). Do not `git add -f` any of the files listed above.
