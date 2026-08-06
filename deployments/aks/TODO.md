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
      Follow [HARDEN_PROD_POSTGRES.md](./HARDEN_PROD_POSTGRES.md).
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
      [UPGRADE_KUBERNETES.md](./UPGRADE_KUBERNETES.md#cert-manager).
- [ ] **AKS K8s upgrade to 1.35.** Both Dev (1.33.6) and Prod (1.33.7) need
      `1.33 → 1.34 → 1.35`, one minor at a time. Runbook in
      [UPGRADE_KUBERNETES.md](./UPGRADE_KUBERNETES.md).
- [ ] **Qdrant for Dev/Prod — no data migration needed.** Dev/Prod values
      reference the `dify-qdrant` service but have no Qdrant Helm release. A
      2026-08-06 inventory of `dify-pg-9764` found the knowledge base empty
      (`document_segments` 0 rows; no `datasets`/`documents` above 56 kB), so there
      are no vectors to export and the earlier export/import question is moot.
      Remaining work is just enabling the UAT release + values overlay for
      Dev/Prod; any indexing starts fresh. Re-check Prod before acting.

## UAT-specific

- [x] **Replaced the temporary PG allow-all firewall.** UAT PG is VNet-injected and
      private on `10.2.0.0/16` as of 2026-08-06, matching Dev. Done while the server
      was still empty: public→private forces a Flexible Server replacement, so the
      cost of this rises sharply once the Dev restore lands. Terraform's
      `create_extensions_*` provisioners can no longer reach the server from the
      runner — they already end in `|| true`, and Dify's own migrations create
      `vector` and `uuid-ossp` under the `azure.extensions` allowlist, which is how
      Dev has always worked.
- [ ] **Dify application config bootstrap** on first deploy: admin account,
      model providers, workflow DSL import, UAT API keys, downstream
      `cme-webapp-api` `DIFY_HTTP_ENDPOINT_URL` update, sanitized test data,
      optional Phoenix/OTLP wiring. See [DEPLOY_UAT.md](./DEPLOY_UAT.md#application-bootstrap).

## Related files

- `environments/{dev,uat,lite-prod,prod-full}.tfvars` — TF inputs per env
- `modules/postgres/*.tf` — PG resource definitions
- `dify-arize-ai/environments/{dev,prod}.env` — Phoenix's PG FQDN; updates
  needed after P2 lands
- `dify-arize-ai/deploy.sh` — already sets `PGSSLMODE=require` for Phoenix
