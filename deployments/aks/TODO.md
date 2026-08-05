# Open follow-ups

Single backlog for the AKS deployment. Ordered by area, priority tagged inline.
Update this file when items land; delete when done.

## Security — production Postgres hardening

**Scope:** `dify-prod-lite-pg-b440` in `rg-cme-prod`. Current state (2026-05-29):
public network access enabled, `allow-all-ipv4` firewall, `require_secure_transport = off`,
no VNet injection. Only the `difyadmin` password separates the internet from the DB.

- [ ] **P0 — Enforce TLS on prod PG.** Verify in Dev first:
      set `postgres_require_secure_transport = true` in `environments/dev.tfvars`,
      deploy, confirm `dify-api` / `dify-worker` / `dify-plugin-daemon` stay healthy
      for 24h with no `SSL connection has been closed unexpectedly` errors, then
      flip the same in `environments/lite-prod.tfvars` (or `prod-full.tfvars`).
      Manual fallback: `az postgres flexible-server parameter set --name require_secure_transport --value on` (needs pod restart).
      Follow [RUNBOOK-prod-pg-hardening.md](./RUNBOOK-prod-pg-hardening.md).
- [ ] **P1 — Restrict firewall to AKS outbound IPs.** Remove `allow-all-ipv4`;
      add rules for each IP returned by
      `az aks show ... --query 'networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id'`.
      Watch-out: if AKS recreates its outbound IP (cluster upgrade, node-pool churn),
      pods lose DB access — P2 is the durable fix.
- [ ] **P2 — Migrate prod PG to a private endpoint.** Flex Server can't convert
      public→private in place; do `pg_dump` → new private server → cutover, or
      read-replica → promote. Half day + downtime.
- [ ] **P3 — Move Dify/Phoenix off the `difyadmin` password to Workload Identity.**
      Phoenix chart already supports it; wait for Dify upstream to catch up.
- [ ] **P4 — Rotate `difyadmin` on prod** (never rotated since initial deploy) and
      document a 90-day cadence.

## Infrastructure

- [ ] **Wire Azure Blob to Dify object storage.** Terraform provisions Blob
      credentials but Dify still writes app/plugin files to Azure File PVCs.
      Either wire `values.yaml` `persistence.persistentVolumeClaim` / `storage`
      to Blob, or remove the unused Blob vars.
- [ ] **Cert-manager upgrade for Dev/Prod.** Currently on EOL `v1.13.3`. UAT
      installs `v1.21.1` directly. Step Dev then Prod through minors — see
      [AKS_KUBERNETES_UPGRADE.md](./AKS_KUBERNETES_UPGRADE.md#cert-manager).
- [ ] **AKS K8s upgrade to 1.35.** Both Dev (1.33.6) and Prod (1.33.7) need
      `1.33 → 1.34 → 1.35`, one minor at a time. Runbook in
      [AKS_KUBERNETES_UPGRADE.md](./AKS_KUBERNETES_UPGRADE.md).
- [ ] **Qdrant migration for Dev/Prod.** Existing Dev/Prod values reference the
      `dify-qdrant` service but have no Qdrant Helm release. UAT is the first env
      with automated Qdrant. Decide: fresh index vs. export/import from wherever
      the current vectors actually live, then enable the same release + values
      overlay for Dev/Prod.

## UAT-specific

- [ ] **Replace the temporary PG allow-all firewall.** UAT PG is public with
      `postgres_open_firewall_all = true` because the GitHub-hosted runner needs
      it for bootstrap. Move UAT to a private runner (or an explicit AKS-outbound
      + runner-IP firewall pair) before calling it production-equivalent.
- [ ] **Dify application config bootstrap** on first deploy: admin account,
      model providers, workflow DSL import, UAT API keys, downstream
      `cme-webapp-api` `DIFY_HTTP_ENDPOINT_URL` update, sanitized test data,
      optional Phoenix/OTLP wiring. See [UAT_RUNBOOK.md](./UAT_RUNBOOK.md#application-bootstrap).

## Related files

- `environments/{dev,uat,lite-prod,prod-full}.tfvars` — TF inputs per env
- `modules/postgres/*.tf` — PG resource definitions
- `dify-arize-ai/environments/{dev,prod}.env` — Phoenix's PG FQDN; updates
  needed after P2 lands
- `dify-arize-ai/deploy.sh` — already sets `PGSSLMODE=require` for Phoenix
