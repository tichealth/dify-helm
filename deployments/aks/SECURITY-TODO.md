# Security TODO — prod Postgres hardening

**Status:** Open. Filed 2026-05-29.
**Owner:** TBD
**Scope:** `dify-prod-lite-pg-b440` in `rg-cme-prod` (Australia East).
**Why this lives in `dify-helm`:** this repo owns the Postgres infrastructure
(via Terraform). `dify-arize-ai` is a downstream consumer.

---

## Findings (current state, 2026-05-29)

| | Dev (`dify-pg-9764`) | Prod (`dify-prod-lite-pg-b440`) | Risk |
|---|---|---|---|
| Public network access | Disabled | **Enabled** | Internet-reachable |
| Firewall | n/a (private only) | **`allow-all-ipv4` (0.0.0.0 → 255.255.255.255)** | Effectively no firewall |
| `require_secure_transport` | off | **off** | Plaintext connections allowed |
| Private endpoint / VNet injection | Yes (delegated subnet + private DNS zone) | None | All traffic over public internet |
| TLS at server | not enforced | not enforced | Credentials may transit plaintext |

**Net effect on prod:** the only thing standing between the internet and the
Dify database is the `difyadmin` password. No network controls, no enforced
TLS. This is a regression vs. dev — usually you expect the opposite.

---

## Remediation, in priority order

### P0 — Enforce TLS on the server (1 hour, low risk if dev test passes)

The dev `terraform.tfvars` comment from the original deploy says:
> `postgres_require_secure_transport = false  # Dev: plugin daemon doesn't support SSL; set true for prod`

That comment is stale — newer versions of the Dify plugin daemon support SSL.
Verify in dev first, then flip prod.

**Steps:**

1. In `dify-helm/deployments/aks/environments/dev.tfvars`, set:
   ```hcl
   postgres_require_secure_transport = true
   ```
2. Deploy dev via the workflow. Watch for:
   - `dify-api`, `dify-worker`, `dify-plugin-daemon` pods all reach `Ready`
   - Logs of each pod (`kubectl -n dify logs deploy/dify-api --tail 100`) free
     of `SSL connection has been closed unexpectedly` / `no pg_hba.conf entry`
3. If dev is happy for 24h, set the same in `environments/prod.tfvars` and
   deploy prod.

**Manual fallback (no TF deploy):**
```bash
az postgres flexible-server parameter set \
    --resource-group rg-cme-prod \
    --server-name dify-prod-lite-pg-b440 \
    --name require_secure_transport --value on
```
Will require restart of dify-api/worker/plugin-daemon pods so they reconnect.

**Phoenix:** already sends `PGSSLMODE=require` (see `dify-arize-ai/deploy.sh`),
so it'll keep working transparently.

---

### P1 — Restrict firewall to AKS outbound IPs (30 min, low risk)

Remove the `allow-all-ipv4` rule; replace with the AKS cluster's outbound IPs
(small, stable set). This still keeps prod on a public endpoint but closes
the open door.

**Steps:**

```bash
RG=rg-cme-prod
PG=dify-prod-lite-pg-b440
AKS=dify-prod-lite-aks-b440

# 1. find AKS outbound IPs (usually 1-2)
az aks show -g "$RG" -n "$AKS" \
    --query 'networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id' -o tsv \
    | xargs -I{} az resource show --ids {} --query 'properties.ipAddress' -o tsv

# 2. add a rule per IP (replace X.X.X.X)
az postgres flexible-server firewall-rule create \
    -g "$RG" --name "$PG" \
    --rule-name aks-outbound-1 \
    --start-ip-address X.X.X.X --end-ip-address X.X.X.X

# 3. drop the wide-open rule LAST (verify AKS still connects first)
az postgres flexible-server firewall-rule delete \
    -g "$RG" --name "$PG" --rule-name allow-all-ipv4
```

**Watch-out:** if AKS recreates its public IP (cluster upgrade, node-pool
churn), pods lose DB access. Long-term fix is P2.

**Phoenix runner caveat:** the GitHub Actions runner has an ephemeral public
IP, so once this is tightened, the runner can NOT reach prod PG directly.
That's fine — DB bootstrap should run from inside the cluster anyway
(`./bootstrap-db.sh --env prod --in-cluster`), and the documented flow
already says so.

---

### P2 — Migrate prod to a private endpoint (≥ half day, involves downtime)

The right end state: prod PG matches dev (VNet-injected, no public endpoint).
This is invasive because Azure Flexible Server doesn't support converting
public → private in-place — you migrate via dump/restore or replica
promotion.

**High-level options:**

| Approach | Downtime | Effort | Notes |
|---|---|---|---|
| Stop server → enable Private Endpoint → restart | minutes | low | **Not supported** for Flex Server post-creation |
| Create new private PG → `pg_dump` / `pg_restore` → cutover | 30–60 min | medium | Standard path |
| Read replica → promote to private primary | minutes | high | Requires replication compatibility; verify on Flex Server |

**Decision needed:** schedule a maintenance window, pick approach, write
runbook. Until P2 lands, P0+P1 give us 80% of the protection.

---

### P3 — Move credentials off `difyadmin` (1 day, design work)

Today both Dify and Phoenix authenticate as PG users created with passwords
stored as GitHub secrets. Better:

- Switch Phoenix to **Workload Identity** (chart already supports it; just
  set `AZURE_CLIENT_ID` in `environments/<env>.env` and provision a UAMI
  with `azure_pg_admin` role).
- Same for Dify itself — Dify upstream is moving towards this; track when
  the chart catches up.

Once both are on WI, the only password-bearing identity left is `difyadmin`
(used for bootstrap and emergency access). That can be rotated quarterly
and the secret removed from CI entirely.

---

### P4 — Rotate `difyadmin` password on prod (15 min, any time)

Current dev `POSTGRESQL_PASSWORD` is `difyai123456` — the upstream chart's
placeholder default. Prod has a strong random value already, but no
rotation has happened since initial deploy. Set a rotation cadence (e.g.
every 90 days) and document the rotation procedure in this repo.

---

## Verification checklist (close this TODO when all green)

- [ ] P0 — `require_secure_transport=on` in prod; all Dify pods + Phoenix pod
      healthy after change; `tfvars` updated and committed
- [ ] P1 — `allow-all-ipv4` firewall rule removed from prod; only AKS
      outbound IPs allowed; tested that AKS still connects
- [ ] P2 — prod PG migrated to private endpoint; public access disabled;
      FQDN updated in `dify-arize-ai/environments/prod.env`
- [ ] P3 — at least one of {Dify, Phoenix} authenticating via Workload
      Identity in prod
- [ ] P4 — rotation procedure documented; first rotation completed

## Related files

- `dify-helm/deployments/aks/environments/{dev,prod}.tfvars` — TF inputs
- `dify-helm/deployments/aks/modules/postgres/*.tf` — PG resource definition
- `dify-arize-ai/environments/{dev,prod}.env` — Phoenix's reference to the
  PG FQDN; will need updating after P2
- `dify-arize-ai/deploy.sh` — already sets `PGSSLMODE=require` for Phoenix
