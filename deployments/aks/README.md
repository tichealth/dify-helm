# Dify on AKS

Terraform creates Azure infrastructure; `deploy.sh` installs the pinned Helm
releases. This page is the documentation entry point for the AKS deployment.

## Start with the task

| Task | Document |
| --- | --- |
| Create UAT | [UAT_RUNBOOK.md](./UAT_RUNBOOK.md) |
| Deploy or resize Prod | [PROD_DEPLOY.md](./PROD_DEPLOY.md) |
| Configure GitHub environments and secrets | [GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md) |
| Upgrade Kubernetes manually | [AKS_KUBERNETES_UPGRADE.md](./AKS_KUBERNETES_UPGRADE.md) |
| Operate or troubleshoot | [OPERATIONS.md](./OPERATIONS.md) and [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) |
| Upgrade Dify (application) | [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md) |
| Review topology | [ARCHITECTURE.md](./ARCHITECTURE.md) |
| Estimate current cost | [INFRACOST.md](./INFRACOST.md) |
| Destroy an environment | [TEARDOWN_AND_REDEPLOY.md](./TEARDOWN_AND_REDEPLOY.md) |
| Harden prod PostgreSQL | [RUNBOOK-prod-pg-hardening.md](./RUNBOOK-prod-pg-hardening.md) |
| Open follow-ups (security + infra) | [TODO.md](./TODO.md) |
| Secret handling guardrails | [SECRETS.md](./SECRETS.md) |

Terraform (`environments/*.tfvars`, `main.tf`, `modules/`) and Helm
(`values.yaml`, `values-*.yaml`, `deploy.sh`) are the source of truth. The
docs above are task-scoped.

## Environments

| Workflow input | Terraform profile | State key | Purpose |
| --- | --- | --- | --- |
| `dev` | `environments/dev.tfvars` | `dev.terraform.tfstate` | Development |
| `uat` | `environments/uat.tfvars` | `uat.terraform.tfstate` | Prod-like, dev-sized acceptance |
| `lite-prod` | `environments/lite-prod.tfvars` | `prod.terraform.tfstate` | Current single-node Prod |
| `prod-full` | `environments/prod-full.tfvars` | `prod.terraform.tfstate` | Three-node Prod target |

The former `test` profile is replaced by greenfield UAT. Never point UAT at a
Dev or Prod state key.

## Deploy

GitHub Actions is the preferred path: run **Deploy or teardown Dify on AKS**,
select the environment and mode, review the plan, then approve apply. Configure
the GitHub Environment first using
[GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md).

For a local run:

```bash
cd deployments/aks
cp environments/<environment>.tfvars terraform.tfvars
# Export the required TF_VAR_* secrets and configure backend.azurerm.tfvars.
az login
./deploy.sh --all --auto-approve
```

| Mode | Changes | Use for |
| --- | --- | --- |
| `--all` | Terraform, cluster add-ons, then Dify | First deployment or coordinated full change |
| `--app` | Dify and UAT Qdrant only; preserves Terraform and cluster add-ons | Application/chart/value changes |
| `--db` | Targeted PostgreSQL module only; no Helm | Database infrastructure changes |

`--all` is the default. `--plan-stage` and `--apply-stage` are CI phases;
`--auto-approve` is the non-interactive local mode. Kubernetes upgrades are not a
deploy mode—use the manual CLI runbook.

## Current implementation facts

- UAT is one on-demand `Standard_D2s_v5` node with a small Azure PostgreSQL 16
  server, required TLS, 14-day PITR, persistent Redis, and persistent Qdrant.
- Dify/plugin files use Azure File PVCs. The Azure Storage account configured in
  CI is the Terraform backend; Blob variables are not wired to application files.
- Qdrant is automated for UAT only. Do not infer a Dev/Prod Qdrant release from a
  `qdrant_chart_version` tfvars value.
- AKS Kubernetes version is pinned per env (`kubernetes_version` in
  `environments/*.tfvars`) but only applied at cluster creation — Terraform
  ignores post-create drift. Ongoing upgrades are manual via `az aks upgrade`
  (see [AKS_KUBERNETES_UPGRADE.md](./AKS_KUBERNETES_UPGRADE.md)).
- HTTPS is issued by cert-manager (Let's Encrypt) via ingress-nginx once a DNS A
  record points at the LoadBalancer IP. No separate setup guide is required.
- `coredns-custom.yaml` is the supported AKS customization for PostgreSQL DNS;
  the old managed-Corefile patches are retired.

## Verify

```bash
kubectl get nodes
kubectl get pods,pvc,ingress -n dify
kubectl get certificate,certificaterequest,challenge -A
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

For UAT, continue through the acceptance checklist in
[UAT_RUNBOOK.md](./UAT_RUNBOOK.md).
