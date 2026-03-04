# Enabling PostgreSQL SSL Later

Prod is currently using non-SSL connections to Azure PostgreSQL. To switch to SSL:

## 1. Terraform

In your prod tfvars (e.g. `terraform.tfvars` or `environments/lite-prod.tfvars`):

```hcl
postgres_require_secure_transport = true
```

Then run:

```bash
terraform apply -auto-approve
```

## 2. Helm values (deployments/aks/values.yaml)

Add these `extraEnv` (values only; no chart changes needed):

- **api**, **worker**, **beat**:  
  `PGSSLMODE: "require"`, `DB_SSLMODE: "require"`

- **pluginDaemon**:  
  `PGSSLMODE: "require"`, `DB_SSLMODE: "require"`, `DB_SSL_MODE: "require"`  
  (and remove or change `DB_SSL_MODE: "disable"` if present)

## 3. Redeploy

Run your usual deploy (e.g. `./deploy.sh --app --auto-approve` or the GitHub workflow) so the new env vars are applied. Restart pods if needed:  
`kubectl rollout restart deployment/dify-api deployment/dify-worker deployment/dify-beat deployment/dify-plugin-daemon -n dify`
