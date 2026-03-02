# Dify AKS Deployment

Terraform and Helm for Dify on Azure Kubernetes Service (AKS) with HTTPS.

## Quick Start

```bash
cd deployments/aks
cp environments/lite-prod.tfvars terraform.tfvars   # or prod-full.tfvars
# Add secret variables to terraform.tfvars (see PROD_DEPLOY.md)
./deploy.sh --auto-approve
```

Secrets are not in the repo: add them to `terraform.tfvars` (git-ignored) or use `TF_VAR_*` env vars. See [PROD_DEPLOY.md](./PROD_DEPLOY.md#local-deploy).

## Deploy and environments

- **[PROD_DEPLOY.md](./PROD_DEPLOY.md)** — Production deploy: lite vs full, local deploy, secrets, checklist
- **[DEPLOYMENT_MODES.md](./DEPLOYMENT_MODES.md)** — `./deploy.sh --all | --app | --db`
- **[LITE_PROD_VS_PROD.md](./LITE_PROD_VS_PROD.md)** — Lite prod (1 node) vs full prod (3 nodes): cost, scalability, migration
- **[GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md)** — Secrets for the [deploy/teardown workflow](../../.github/workflows/deploy-aks.yml)

## Operations and troubleshooting

- **[OPERATIONS.md](./OPERATIONS.md)** — Get PostgreSQL FQDN, Dify endpoint, Azure Blob key
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** — Stuck deployment, DNS (NXDOMAIN) fixes
- **[HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md)** — HTTPS/TLS, cert-manager, DNS

## Cost and architecture

- [COST_SUMMARY_2026-01-24.md](./COST_SUMMARY_2026-01-24.md) — Cost estimates
- [INFRACOST.md](./INFRACOST.md) — Exact cost from Terraform
- [ARCHITECTURE.md](./ARCHITECTURE.md) — Architecture overview

## Configuration files

- `terraform.tfvars` — Infra variables (git-ignored; copy from `environments/*.tfvars` and add secrets)
- `values.yaml` — Helm values for Dify (ingress host, resources)
- `main.tf`, `variables.tf`, `outputs.tf` — Terraform

## Verification

```bash
kubectl get certificate -n dify
kubectl get ingress -n dify
kubectl get pods -n dify
kubectl get svc -n ingress-nginx ingress-nginx-controller   # LoadBalancer IP
```

## Full doc list

See **[DOCUMENTATION_INDEX.md](./DOCUMENTATION_INDEX.md)** for the complete list (teardown, upgrade, PostgreSQL, changelog, etc.).

## Architecture (summary)

Internet → nginx-ingress (LoadBalancer) → Ingress (TLS) → Dify (ClusterIP) → API/Web/Worker/Sandbox. cert-manager issues Let's Encrypt certs; CoreDNS uses 8.8.8.8 / 1.1.1.1. Details: [ARCHITECTURE.md](./ARCHITECTURE.md).

## Support

Use [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) and [OPERATIONS.md](./OPERATIONS.md); run `kubectl get all -n dify` and `kubectl logs -n dify -l app.kubernetes.io/name=dify` for debugging.
