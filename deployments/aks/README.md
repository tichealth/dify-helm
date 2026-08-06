# Dify on AKS

Terraform creates Azure infrastructure; `deploy.sh` installs the pinned Helm
releases. This page is the documentation entry point for the AKS deployment.

## Start with the task

| Task | Document |
| --- | --- |
| Stand up UAT from scratch | [DEPLOY_UAT.md](./DEPLOY_UAT.md) |
| Seed a new UAT with Dev data | [RESTORE_DEV_TO_UAT.md](./RESTORE_DEV_TO_UAT.md) |
| Deploy or resize Prod | [DEPLOY_PROD.md](./DEPLOY_PROD.md) |
| Configure GitHub Environments, secrets, and the workflow | [GITHUB_ACTIONS.md](./GITHUB_ACTIONS.md) |
| Upgrade the Kubernetes cluster | [UPGRADE_KUBERNETES.md](./UPGRADE_KUBERNETES.md) |
| Upgrade the Dify application | [UPGRADE_DIFY.md](./UPGRADE_DIFY.md) |
| Find endpoints, FQDNs, and keys | [ENDPOINTS_AND_KEYS.md](./ENDPOINTS_AND_KEYS.md) |
| Diagnose a failed or stuck deploy | [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) |
| Review topology | [ARCHITECTURE.md](./ARCHITECTURE.md) |
| Estimate current cost | [COSTS.md](./COSTS.md) |
| Destroy and rebuild an environment | [TEARDOWN.md](./TEARDOWN.md) |
| Lock down prod PostgreSQL (TLS + firewall) | [HARDEN_PROD_POSTGRES.md](./HARDEN_PROD_POSTGRES.md) |
| Keep credentials out of git | [SECRETS.md](./SECRETS.md) |
| Open follow-ups (security + infra) | [TODO.md](./TODO.md) |

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
[GITHUB_ACTIONS.md](./GITHUB_ACTIONS.md).

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
  (see [UPGRADE_KUBERNETES.md](./UPGRADE_KUBERNETES.md)).
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
[DEPLOY_UAT.md](./DEPLOY_UAT.md).
