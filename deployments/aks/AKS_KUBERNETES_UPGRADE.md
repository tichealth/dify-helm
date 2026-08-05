# AKS Kubernetes upgrades

Terraform pins `kubernetes_version` per env, but **only applies it at cluster
creation** and then ignores drift. All ongoing upgrades are manual via
`az aks upgrade`. This keeps the pin as documentation of the intended target and
lets manual CLI work happen without ever causing a Terraform diff.

## How the pin works

| Env | Cluster | Pin (in `environments/*.tfvars`) | Reality |
| --- | --- | --- | --- |
| UAT | greenfield | `1.35` | Created at `1.35`. Bump pin only when you're about to upgrade. |
| Dev | `dify-aks-9764` (`dify-rg-9764`) | `1.35` | Manually upgraded via CLI to match; Terraform ignores drift. |
| Prod | `dify-prod-lite-aks-b440` (`rg-cme-prod`) | `1.35` | Manually upgraded via CLI to match; Terraform ignores drift. |

**Workflow when you want to move to a new minor** (e.g. `1.35` → `1.36`):

1. Update the pin in `environments/dev.tfvars`, `uat.tfvars`, `lite-prod.tfvars`,
   and `prod-full.tfvars`. Commit.
2. Do the CLI upgrade in each ring (Dev, then Prod). UAT is already at the new
   version if you rebuild it; otherwise upgrade it too.
3. Next Terraform apply is a no-op on the K8s version (guarded by
   `lifecycle.ignore_changes`).

## AKS constraint you must respect

Non-LTS clusters **cannot skip minor versions**. From 1.33 you must go
`1.33 → 1.34 → 1.35` — one minor at a time.
See [AKS supported versions](https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions).
AKS LTS (which would allow skipping) requires the Premium tier; we're on Free.

## Prep (once per ring)

```bash
RG=<resource-group>          # dev: dify-rg-9764   prod: rg-cme-prod
AKS=<cluster>                # dev: dify-aks-9764  prod: dify-prod-lite-aks-b440

az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
az aks show -g "$RG" -n "$AKS" --query '{v:currentKubernetesVersion,s:provisioningState}' -o json
az aks get-upgrades -g "$RG" -n "$AKS" -o table
kubectl get nodes
kubectl get pdb -A
```

Stop if: state ≠ `Succeeded`, any node not `Ready`, a blocking PDB exists, or
the target minor isn't in the offered list.

Take a fresh PostgreSQL logical backup (`pg_dump` of `dify` and `dify_plugin`)
and record the current chart/image versions before every hop.

## Upgrade — one minor at a time

```bash
TARGET=1.34.9   # or whatever `az aks get-upgrades` currently offers
POOL=system     # or whichever node pool holds the workloads

# Small surge so AKS can bring up a replacement node before draining the old one.
# Requires enough regional quota for one temporary node.
az aks nodepool update -g "$RG" --cluster-name "$AKS" --name "$POOL" \
  --max-surge 1 --drain-timeout 30 --node-soak-duration 5

az aks upgrade -g "$RG" -n "$AKS" --kubernetes-version "$TARGET" --yes
```

Repeat with the next minor. Do not skip.

## Downtime expectation (be honest)

Both live clusters are **single-node**. `--max-surge 1` minimises node-level
disruption, but singleton workloads (Redis primary, plugin daemon, sandbox,
proxy) will still restart when their pod moves. Expect **~30-60 seconds of
per-pod blip**, not zero downtime. Schedule a maintenance window and describe it
that way.

For truly minimal HTTP downtime on a 1-node cluster, scale ingress-nginx to 2
replicas before the upgrade — the replicas will land on the surge node while the
old node is draining. This does not help singletons like Redis.

## Cert-manager (do this once, before the first K8s hop)

Dev/Prod are still on `cert-manager v1.13.3` (EOL). Upgrade it one minor at a
time. Dev first, then Prod. UAT installs `v1.21.1` directly.

```bash
kubectl get certificates,certificaterequests,issuers -A -o yaml > cm-ns-backup.yaml
kubectl get clusterissuers -o yaml > cm-cluster-backup.yaml
helm repo add jetstack https://charts.jetstack.io && helm repo update

TARGET=v1.14.7   # step through: v1.14 → v1.15 → v1.16 → ... → v1.21
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${TARGET}/cert-manager.crds.yaml"
helm upgrade cert-manager jetstack/cert-manager -n cert-manager \
  --version "${TARGET}" --reset-then-reuse-values --wait --timeout 10m
kubectl rollout status deployment --all -n cert-manager --timeout=5m
kubectl get certificate,certificaterequest,challenge -A
```

## Validate after every hop

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp | tail -50
kubectl get pvc -n dify
kubectl get certificate,certificaterequest,challenge -A
curl -fsSI https://<env-hostname>/ | head -1
```

- [ ] Control plane and all node pools report the target; all nodes `Ready`.
- [ ] No `CrashLoopBackOff`, mount, or image-pull errors.
- [ ] Login, streaming chat, file upload, workflow run, background jobs OK.
- [ ] No unexpected 5xx / 504 / OOM / cert failures in logs.

If anything's off, AKS cannot downgrade. Recovery is fix-forward, workload
rollback, or PostgreSQL restore from the pre-hop backup.

## Ongoing cadence

Check [AKS supported versions](https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions)
monthly. When the current pin nears end of life, bump the tfvars pin and run
this runbook again (UAT rebuild or upgrade → Dev → Prod).
