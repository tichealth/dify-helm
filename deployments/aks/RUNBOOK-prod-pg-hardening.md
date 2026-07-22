# Runbook — prod Postgres hardening (P0 + P1)

**Goal:** in one ~1 hour session, go from
> *"prod PG accepts plaintext connections from anywhere on the internet"*

to
> *"prod PG accepts TLS-only connections from AKS outbound IPs"*

**Scope:** P0 (enforce TLS) + P1 (restrict firewall) from `SECURITY-TODO.md`.
P2/P3/P4 are out of scope.

**Maintenance window:** not required. Expect ~30–60s of failed requests during
pod restarts in step 2.4. Schedule outside peak hours anyway.

**Rollback:** every step has a one-command rollback. Total recovery time
under 2 minutes.

---

## Pre-flight (5 min)

```bash
# 1. Confirm you're on the right subscription
az account show --query '{name:name,id:id}' -o table
# Expect:  subscription id = cce1d8e5-9a56-4bb4-ad7d-9c17aaa74482

# 2. Establish names you'll reuse
export DEV_RG=dify-rg-9764
export DEV_PG=dify-pg-9764
export PROD_RG=rg-cme-prod
export PROD_PG=dify-prod-lite-pg-b440
export PROD_AKS=dify-prod-lite-aks-b440

# 3. Snapshot the BEFORE state (keep terminal open)
az postgres flexible-server parameter show \
    -g "$PROD_RG" --server-name "$PROD_PG" \
    --name require_secure_transport \
    --query 'value' -o tsv
# Expect: off

az postgres flexible-server firewall-rule list \
    -g "$PROD_RG" --name "$PROD_PG" -o table
# Expect: allow-all-ipv4 0.0.0.0 - 255.255.255.255

# 4. Make sure prod Dify pods are currently healthy
az aks get-credentials -g "$PROD_RG" --name "$PROD_AKS" --overwrite-existing >/dev/null
kubectl --context "$PROD_AKS" -n dify get pods
# All should be Running 1/1 (or 2/2). If anything is crashing already, STOP
# and fix that first — you don't want to attribute existing failures to this
# change.
```

If everything above looks expected, proceed.

---

## Stage 1 — P0 canary on dev (30 min watch period)

Dev is currently `require_secure_transport=off` too, but it's private-only so
no internet exposure. The reason we test here first is to verify that
**Dify's pods can actually speak TLS to PG** before flipping the same switch
on prod. The stale comment in `environments/dev.tfvars` says they couldn't —
we need to disprove that.

### 1.1 Flip dev

```bash
az postgres flexible-server parameter set \
    -g "$DEV_RG" --server-name "$DEV_PG" \
    --name require_secure_transport --value on
```

Dynamic parameter — no server restart. Existing connections keep working
until they're recycled.

### 1.2 Force Dify clients to reconnect

```bash
kubectl --context dify-aks-9764 -n dify rollout restart \
    deploy/dify-api deploy/dify-worker
# plugin-daemon may be a different resource type — list and restart it too:
kubectl --context dify-aks-9764 -n dify get deploy,sts | grep -i plugin
# then:
kubectl --context dify-aks-9764 -n dify rollout restart deploy/dify-plugin-daemon
```

### 1.3 Watch for 5 min

```bash
kubectl --context dify-aks-9764 -n dify get pods -w
# Ctrl-C after 5 min if everything is Ready
```

Then check logs for SSL-related errors:

```bash
for d in dify-api dify-worker dify-plugin-daemon; do
    echo "=== $d ==="
    kubectl --context dify-aks-9764 -n dify logs deploy/$d --tail 50 \
        | grep -iE 'ssl|tls|secure|hba|fatal|error' | head -20
done
```

**Pass criteria:**
- All pods Ready
- No `SSL connection has been closed unexpectedly`
- No `no pg_hba.conf entry for host …, no encryption`
- No new restart count bumps

**If any pod is crash-looping** → roll back immediately:
```bash
az postgres flexible-server parameter set \
    -g "$DEV_RG" --server-name "$DEV_PG" \
    --name require_secure_transport --value off
kubectl --context dify-aks-9764 -n dify rollout restart deploy
```
Then investigate before retrying. The most likely fix is to add
`sslmode=require` to Dify's DB connection string via chart values.

### 1.4 Soak for the rest of the maintenance window (or overnight)

If 5 min of healthy pods, leave it. Come back in 30 min (or next morning)
and confirm no restart-count growth:

```bash
kubectl --context dify-aks-9764 -n dify get pods
# Look at RESTARTS column — should still be 0 (or unchanged from before)
```

**If healthy after the soak → proceed to Stage 2.**
**If not → roll back dev, fix Dify config, retry. Do NOT proceed to prod.**

### 1.5 Commit the dev change to Terraform

So the change survives the next Terraform run:

```bash
# In dify-helm/deployments/aks/environments/dev.tfvars
# Change:
#   postgres_require_secure_transport = false
# to:
#   postgres_require_secure_transport = true
git add deployments/aks/environments/dev.tfvars
git commit -m "Enable TLS enforcement on dev Postgres (P0 canary passed)"
git push
```

---

## Stage 2 — P1 firewall tightening on prod (15 min, zero downtime)

We do this **before** P0 on prod so that if anything goes weird, we can still
hit prod PG from the management host to debug.

### 2.1 Discover the AKS outbound IP(s)

```bash
az aks show -g "$PROD_RG" -n "$PROD_AKS" \
    --query 'networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id' -o tsv \
    | xargs -I{} az resource show --ids {} --query 'properties.ipAddress' -o tsv
```

Save these IPs — you might see 1 or 2. Call them `AKS_IP_1`, `AKS_IP_2`.

### 2.2 Add additive rules (no traffic impact)

```bash
# Replace X.X.X.X with each IP from step 2.1
az postgres flexible-server firewall-rule create \
    -g "$PROD_RG" --name "$PROD_PG" \
    --rule-name aks-outbound-1 \
    --start-ip-address X.X.X.X --end-ip-address X.X.X.X

# Repeat for any additional IPs (aks-outbound-2, etc.)
```

### 2.3 (Optional) Add your laptop IP for emergency access

```bash
MY_IP=$(curl -s ifconfig.me)
az postgres flexible-server firewall-rule create \
    -g "$PROD_RG" --name "$PROD_PG" \
    --rule-name admin-laptop-$(whoami) \
    --start-ip-address "$MY_IP" --end-ip-address "$MY_IP"
# Remove this when you're done debugging.
```

### 2.4 Verify AKS still connects (BEFORE removing the open rule)

```bash
kubectl --context "$PROD_AKS" -n dify exec deploy/dify-api -- \
    sh -c 'echo "SELECT 1" | psql "$DB_URL" -tA 2>&1' | head -5
# Should print: 1
# If it errors, your firewall rules don't match the actual AKS egress IP.
# DO NOT proceed to 2.5. Re-check step 2.1.
```

### 2.5 Drop the wide-open rule

```bash
az postgres flexible-server firewall-rule delete \
    -g "$PROD_RG" --name "$PROD_PG" --rule-name allow-all-ipv4 --yes
```

### 2.6 Re-verify

```bash
az postgres flexible-server firewall-rule list \
    -g "$PROD_RG" --name "$PROD_PG" -o table
# allow-all-ipv4 should be gone

kubectl --context "$PROD_AKS" -n dify exec deploy/dify-api -- \
    sh -c 'echo "SELECT now()" | psql "$DB_URL" -tA 2>&1' | head -3
# Should still print a timestamp
```

**Rollback for stage 2:**
```bash
az postgres flexible-server firewall-rule create \
    -g "$PROD_RG" --name "$PROD_PG" \
    --rule-name allow-all-ipv4 \
    --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255
```

---

## Stage 3 — P0 TLS enforcement on prod (5 min)

Only do this if Stage 1 (dev canary) was clean.

### 3.1 Flip the parameter

```bash
az postgres flexible-server parameter set \
    -g "$PROD_RG" --server-name "$PROD_PG" \
    --name require_secure_transport --value on
```

### 3.2 Recycle Dify clients

```bash
kubectl --context "$PROD_AKS" -n dify rollout restart \
    deploy/dify-api deploy/dify-worker deploy/dify-plugin-daemon

# Watch for ~3 min until all Ready
kubectl --context "$PROD_AKS" -n dify rollout status deploy/dify-api --timeout=3m
kubectl --context "$PROD_AKS" -n dify rollout status deploy/dify-worker --timeout=3m
kubectl --context "$PROD_AKS" -n dify rollout status deploy/dify-plugin-daemon --timeout=3m
```

### 3.3 Smoke test prod

```bash
# Web reachable
curl -ksS -o /dev/null -w 'HTTP %{http_code}\n' https://dify-prod.tichealth.com.au/
# Expect 2xx or 3xx

# DB query through dify-api
kubectl --context "$PROD_AKS" -n dify exec deploy/dify-api -- \
    sh -c 'echo "SELECT version()" | psql "$DB_URL" -tA' | head -1
# Expect a PostgreSQL version string
```

**Pass criteria:** both green.

**Rollback for stage 3:**
```bash
az postgres flexible-server parameter set \
    -g "$PROD_RG" --server-name "$PROD_PG" \
    --name require_secure_transport --value off
kubectl --context "$PROD_AKS" -n dify rollout restart deploy
```
This brings prod back to where it was at the start of stage 3.

### 3.4 Commit the prod change to Terraform

Same as 1.5 but for `prod.tfvars`:

```bash
# In dify-helm/deployments/aks/environments/prod.tfvars
# Change postgres_require_secure_transport = false -> true
git add deployments/aks/environments/prod.tfvars
git commit -m "Enable TLS enforcement on prod Postgres (P0 done)"
git push
```

---

## Stage 4 — Verify Phoenix still works (2 min)

Phoenix on dev already runs with `PGSSLMODE=require`, so it shouldn't notice
this change. Verify anyway:

```bash
kubectl --context dify-aks-9764 -n phoenix get pods
# phoenix-* should be 1/1 Ready

curl -ksS -o /dev/null -w 'HTTP %{http_code}\n' \
    --resolve "phoenix-dev.tichealth.com.au:443:$(kubectl --context dify-aks-9764 -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
    https://phoenix-dev.tichealth.com.au/
# Expect 2xx or 3xx
```

For Phoenix prod — it'll be deployed for the first time later. When you do,
it'll connect via TLS to the now-hardened prod PG with no extra work
because `deploy.sh` already injects `PGSSLMODE=require`.

---

## Final state checklist

- [ ] dev PG: `require_secure_transport=on`; `dev.tfvars` committed
- [ ] prod PG firewall: only `aks-outbound-*` rules; no `allow-all-ipv4`
- [ ] prod PG: `require_secure_transport=on`; `prod.tfvars` committed
- [ ] All Dify pods on both clusters Ready with no SSL errors in logs
- [ ] Dify web reachable on both `https://dify-dev.tichealth.com.au/` and
      `https://dify-prod.tichealth.com.au/`
- [ ] Phoenix dev Web UI still reachable
- [ ] Admin-laptop firewall rule from 2.3 removed (if you added one)
- [ ] Update `SECURITY-TODO.md` — tick the P0 and P1 boxes

## After this is done

Prod PG goes from "internet-reachable, plaintext-allowed" to "TLS-only from
AKS". That kills the most exploitable findings in `SECURITY-TODO.md`.

P2 (private endpoint), P3 (workload identity), and P4 (password rotation)
can each be done independently when there's appetite. No urgency.
