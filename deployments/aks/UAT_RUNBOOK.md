# UAT Environment Runbook

**Status:** Authoritative instructions for creating and operating Dify UAT on AKS.  
**Last verified:** 2026-08-03 against the Azure subscription and this repository.  
**Scope:** Infrastructure, CI configuration, deployment, DNS, and acceptance checks.

This runbook replaces the former `test` environment instructions. Use the other
documents only for the specialist topics linked from this page.

## Decision and assumptions

UAT is a **greenfield, isolated environment**. The live Azure inventory contained
Dev and Lite Prod, but no `rg-cme-test`, `rg-cme-uat`, Test AKS cluster, or Test
PostgreSQL server. Therefore UAT uses a new `uat.terraform.tfstate` and new
resources; it does not share or rename Dev/Prod resources.

If Test exists in another subscription or backend, stop before deploying and
perform an explicit state/data migration. Never point UAT at Dev or Prod state.

## Approved UAT profile

| Item | UAT setting | Reason |
| --- | --- | --- |
| Terraform profile/state | `environments/uat.tfvars` / `uat.terraform.tfstate` | Isolation |
| URL | `https://dify-uat.tichealth.com.au` | Canonical UAT endpoint |
| AKS | 1 x `Standard_D2s_v5`, no Spot | Dev-sized, predictable capacity |
| Kubernetes | `1.35` (pinned via `kubernetes_version` in `uat.tfvars`) | Matches the manual target for Dev/Prod |
| Maintenance | Scheduled manual window | UAT runs before Dev and Prod |
| PostgreSQL | Flexible Server 16, B1ms, 32 GiB/P4 | Same service type as Prod, smaller size |
| PostgreSQL protection | TLS required, 14-day PITR retention | Production-like behavior |
| Dify | chart `0.37.0`; app images `1.12.1` | Pinned to the repository/live Dev baseline |
| cert-manager | `v1.21.1` | Supports Kubernetes 1.33-1.36 |
| ingress-nginx | chart `4.15.1` | Pinned to the live Dev/Prod version |
| Redis | Single persistent in-cluster master | Matches the current deployment topology |
| Qdrant | Official chart `1.16.3`, single 10-GiB disk | Makes the configured vector endpoint reproducible |
| App/plugin files | Azure File PVCs | Matches current live behavior |

This profile is production-like in topology and configuration, not availability.
One node means expected downtime during node maintenance and no node-level HA.

## What must exist before the first run

1. **Azure access and quota**
   - The service principal can create resource groups, AKS, networking, PostgreSQL,
     disks, file shares, and public IPs in the target subscription.
   - Australia East has quota for the D2s_v5 node plus one temporary surge node
     during a manual upgrade.
2. **A Terraform backend storage account**
   - Create or select a UAT-only storage account.
   - Create a private `tfstate` container. The workflow uses the key
     `uat.terraform.tfstate`.
   - The application does **not** currently use this account for Dify file storage;
     application files remain on AKS PVCs.
3. **A GitHub Environment named `uat`**
   - Add required reviewers for the apply gate.
   - Do not copy Dev or Prod application/database keys; generate UAT-only values.
4. **DNS control** for `tichealth.com.au`.
5. **A UAT owner and test window**, including who will approve the first apply and
   who will complete Dify application configuration.

## GitHub Environment configuration

Configure the common variables, secrets, backend, and approval gate once using
[GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md). For UAT, all application
keys must be newly generated; `PLUGIN_DAEMON_SERVER_KEY` and
`PLUGIN_DAEMON_DIFY_API_KEY` are also mandatory. Generate them with:

```bash
bash scripts/generate-secrets.sh
```

Store the output only in the GitHub Environment named `uat` or approved secret
storage. Do not add it to the tracked UAT profile.

## First deployment

1. Open **Actions -> Deploy or teardown Dify on AKS -> Run workflow**.
2. Select:
   - `enabled`: checked
   - `action`: `deploy`
   - `deploy_mode`: `all`
   - `environment`: `uat`
3. Approve the plan job. On a greenfield environment, the Terraform plan is
   produced but Helm diffs are skipped because the cluster does not exist yet.
4. Review the Terraform plan before approving apply:
   - backend key is `uat.terraform.tfstate`;
   - names start with `dify-uat`;
   - region is `australiaeast`;
   - one D2s_v5 node and one B1ms PostgreSQL server are created;
   - there are no Dev/Prod changes or destroy/replacement actions.
5. Approve apply. The workflow creates infrastructure, ingress-nginx,
   cert-manager, Qdrant, and Dify in that order.
6. Copy the LoadBalancer IP from the workflow output and create/update:

   ```text
   dify-uat.tichealth.com.au  A  <INGRESS_LOAD_BALANCER_IP>
   ```

7. Wait for DNS propagation and certificate readiness:

   ```bash
   kubectl get certificate,certificaterequest,challenge -n dify
   kubectl get ingress,pods,pvc -n dify
   curl -fsS https://dify-uat.tichealth.com.au/
   ```

8. If the initial certificate was issued before DNS propagated, rerun only the
   application scope (`environment=uat`, `deploy_mode=app`) after DNS resolves.

## Application bootstrap

Infrastructure deployment does not copy production business data or credentials.
Complete these explicitly:

1. Create the UAT admin account and restrict membership.
2. Configure UAT model-provider credentials and spend/rate limits.
3. Import approved Dify workflow/app DSL exports; do not manually rebuild them.
4. Create UAT API keys and update downstream callers. In particular, set the
   `cme-webapp-api` UAT GitHub variable `DIFY_HTTP_ENDPOINT_URL` to the intended
   UAT API base (normally `https://dify-uat.tichealth.com.au/v1`).
5. Load synthetic/sanitized test documents. Do not copy production personal or
   health data without an approved data-handling process.
6. Configure optional Phoenix/OTLP and confirm traces land in the UAT project.

## Acceptance checklist

- [ ] Terraform state contains only UAT resources and can be planned again with
      zero unexpected changes.
- [ ] All nodes are `Ready`; all Dify, Redis, Qdrant, ingress, and cert-manager
      pods are healthy.
- [ ] HTTPS certificate is valid for `dify-uat.tichealth.com.au`.
- [ ] Login, app creation/import, chat/streaming, file upload, workflow execution,
      and background jobs work.
- [ ] A knowledge-base document can be indexed and retrieved through Qdrant.
- [ ] PostgreSQL connections use TLS and both `dify` and `dify_plugin` databases
      are usable.
- [ ] Restart one Dify pod and verify PVC-backed files and Redis-backed jobs recover.
- [ ] Run representative concurrency/load tests without 5xx/504 errors or pod OOMs.
- [ ] Record the exact chart/image/Kubernetes versions and test evidence in the
      release ticket before promoting the same artifacts to Prod.

## Known limitations and follow-ups

- PostgreSQL is temporarily public with an allow-all firewall rule because the
  current GitHub-hosted runner must bootstrap it. Replace this with a private
  runner/private networking or explicit egress rules before calling UAT fully
  production-equivalent.
- UAT is single-node. It validates compatibility and function, not HA.
- Qdrant is now automated for UAT only. Existing Dev/Prod do not currently have a
  Qdrant Helm release, so their vector-store data path needs a separate migration
  decision before enabling the same release there.
- Azure Blob Terraform variables are not wired to Dify object storage. Do not
  remove the Azure File PVCs based on older documentation.
- Chart `0.37.0` advertises app `1.14.2`, while the AKS values deliberately pin
  Dify images `1.12.1`. Treat the application upgrade as a separate tested change.
- The old managed-Corefile replacement is retired. UAT uses the supported
  `coredns-custom` ConfigMap for Azure PostgreSQL DNS forwarding.

## Related current runbooks

- [AKS_KUBERNETES_UPGRADE.md](./AKS_KUBERNETES_UPGRADE.md) - Dev/UAT/Prod cluster upgrade rings.
- [GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md) - CI secret details.
- [OPERATIONS.md](./OPERATIONS.md) - Routine endpoint and infrastructure queries.
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Deployment troubleshooting.
