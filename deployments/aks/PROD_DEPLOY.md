# Production deployment

Production is selected by profile, not by a `--env` shell flag. Both profiles
use the GitHub Environment `prod`, hostname `dify-prod.tichealth.com.au`, and
backend key `prod.terraform.tfstate`.

## Choose a profile

| Profile | Compute/database | Use when |
| --- | --- | --- |
| `environments/lite-prod.tfvars` | 1 x D4s_v5; PG16 B1ms / 32 GiB | Current cost-optimized, non-HA Prod |
| `environments/prod-full.tfvars` | 3 x D4s_v5; PG16 GP D2ds_v5 / 128 GiB | Node-level resilience and more headroom |

Use [INFRACOST.md](./INFRACOST.md) for current pricing; dated estimates are not a
deployment decision. Moving between these profiles changes the same live state,
so review the Terraform plan for replacement, storage, and quota implications.

## Preferred GitHub deployment

1. Configure the `prod` GitHub Environment using
   [GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md), with required reviewers.
2. Run **Deploy or teardown Dify on AKS** with:
   - `enabled`: checked
   - `action`: `deploy`
   - `environment`: `lite-prod` or `prod-full`
   - `deploy_mode`: `all` for coordinated infrastructure changes, otherwise the
     narrowest mode from [README.md](./README.md#deploy)
3. Review the saved plan. Stop on an unexpected destroy, replacement, state key,
   resource group, or hostname.
4. Approve apply and validate the checklist below.

Kubernetes version upgrades are a separate manual change; follow
[AKS_KUBERNETES_UPGRADE.md](./AKS_KUBERNETES_UPGRADE.md).

## Local equivalent

```bash
cd deployments/aks
cp environments/lite-prod.tfvars terraform.tfvars  # or prod-full.tfvars
# Configure backend.azurerm.tfvars with key = prod.terraform.tfstate.
# Export the required TF_VAR_* values from GITHUB_ACTIONS_SECRETS.md.
az login
az account set --subscription "<SUBSCRIPTION_ID>"
./deploy.sh --all --auto-approve
```

Do not commit `terraform.tfvars`, backend access keys, or generated application
secrets.

## Current Prod caveats

- Lite Prod is a one-node, single-region deployment. It has no node-level HA or
  database replica; planned node work can interrupt service.
- The live PostgreSQL B1ms server is public and currently permits non-TLS
  connections. Harden networking/TLS as a separate tested change before claiming
  production-equivalent security.
- Dify/plugin files are on Azure File PVCs. The Azure Blob account is used for
  Terraform state, not application files.
- Existing Prod has no Qdrant Helm release even though values reference the
  `dify-qdrant` service. Decide the vector-store data/migration path before
  automating Qdrant in Prod.
- Chart and image upgrades are separate changes. Promote the exact artifacts
  already accepted in UAT rather than changing versions during an infrastructure
  operation.

## Acceptance

```bash
kubectl get nodes
kubectl get pods,pvc,ingress -n dify
kubectl get certificate,certificaterequest,challenge -A
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

- [ ] Terraform state and resource group are the intended Prod targets.
- [ ] Nodes and workloads are healthy with no mount, pull, or restart loop.
- [ ] HTTPS, login, chat/streaming, workflows, upload, workers, Redis, plugins,
      PostgreSQL, and the configured vector store pass.
- [ ] Backups/PITR and an actual restore procedure are current.
- [ ] Monitoring shows no unexpected 5xx, 504, OOM, or certificate errors.
- [ ] The exact deployed chart/image versions and evidence are recorded.
