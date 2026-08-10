# Restore the Dev database into UAT

**Status:** Authoritative steps for seeding a freshly built UAT with Dev data.
**Last verified:** 2026-08-06 — sizes and timings measured against `dify-pg-9764`.
**Scope:** PostgreSQL copy, post-restore sanitization, and the upgrade rehearsal it enables.

A greenfield UAT runs migrations against an empty schema, which proves nothing
about Dev or Prod. This runbook seeds UAT with real Dev data so the Dify
`1.12.1 → 1.14.2` upgrade can be rehearsed against realistic volume, as
[UPGRADE_DIFY.md](./UPGRADE_DIFY.md) requires.

## Measured baseline

| Item | Value |
| --- | --- |
| `dify` dump size (`-Fc`) | 196 MiB (205,983,910 bytes), 1m41s to produce |
| `dify_plugin` dump size | 66 KiB, 1.5s — schema only |
| Largest tables | `workflow_node_executions` 415 MB / 65,732 rows; `workflow_runs` 82 MB / 2,955 rows |
| Configuration data | ~13 MB total: 42 apps, 110 workflows, 42 sites |
| Knowledge base | Empty — `document_segments` 0 rows, no `datasets`/`documents` of any size |
| User content | 1,024 `end_users`, 1,786 `messages`, 1,782 `conversations`, 5 `accounts` |
| Credentials in data | 34 `api_tokens`; 1 `providers` / 2 `provider_models` / 3 `tenant_default_models` |

The two telemetry tables are 97% of the volume and are copied deliberately: a
schema migration against 65,732 rows on UAT's single burstable vCore is the
failure mode this rehearsal exists to catch.

Because the knowledge base is empty there are no vectors to migrate and no
re-indexing to do. UAT's Qdrant release stays idle until someone loads test
documents.

## Where this fits

Between step 4 (deploy) and step 6 (application bootstrap) of
[DEPLOY_UAT.md](./DEPLOY_UAT.md). Running it after bootstrap destroys the admin
account and provider configuration created there.

UAT must already be deployed and holding at Dify `1.12.1` — the `image:` block in
`values-uat.yaml` stays commented out until the rehearsal in step 7 below.
Restoring a 1.12.1 dump into a 1.14.2 UAT conflates restore failures with
migration failures.

## Prerequisites

- Both databases are private (VNet-injected, no public access) and their VNets are
  not peered to each other — Dev is `10.1.0.0/16`, UAT is `10.2.0.0/16`, and each
  peers only with its own AKS VNet. No single host can reach both, and a GitHub
  runner or a laptop can reach neither.
- The copy therefore runs as two hops with a dump file in between, one jump host
  per environment. Peering Dev to UAT would allow the original single-stream copy,
  but it leaves a standing network path between the two environments; a
  short-lived file is the safer trade.
- Data-handling sign-off for the user content listed above.
- Both `difyadmin` passwords. Use `read -rsp` rather than literals so they do not
  land in shell history.

## 1. Create the copy hosts

Each environment has an empty management subnet for exactly this — Dev's
`10.1.2.0/24` and UAT's `10.2.2.0/24`. A VM there sits in the same VNet as its
PostgreSQL server, so it resolves the privatelink name and avoids the peering
data charge. Its NSG already allows inbound SSH and outbound 5432 to the
PostgreSQL subnet.

```bash
# Dev side - dump source
az vm create -g dify-rg-9764 -n dify-dbcopy-vm \
  --image Ubuntu2404 --size Standard_B2s \
  --vnet-name dify-vnet-9764 --subnet dify-management-subnet \
  --admin-username azureuser --generate-ssh-keys

# UAT side - restore target
az vm create -g dify-uat-rg-1df2 -n dify-uat-dbcopy-vm \
  --image Ubuntu2404 --size Standard_B2s \
  --vnet-name dify-uat-vnet-1df2 --subnet dify-uat-management-subnet \
  --admin-username azureuser --generate-ssh-keys
```

On each host: `sudo apt-get update && sudo apt-get install -y postgresql-client-16`.

Both need ~200 MiB free for the dump, which a B2s OS disk has comfortably. A
capped pod in the Dev cluster also works as the dump source (requests 100m/256Mi,
limits 500m/512Mi) and measured 0.29 cores average, but prefer the VM: writing a
dump file inside either cluster risks node `DiskPressure`, which evicts Dify pods.

## 2. Quiesce UAT

```bash
az aks get-credentials -g <uat-rg> -n <uat-cluster>
kubectl -n dify scale deploy --replicas=0 --all
kubectl -n dify get pods
```

Wait until no Dify pods remain. The API writes on startup and during operation;
restoring underneath a running API produces inconsistent state.

## 3. Reset the target schemas

UAT is not empty — Dify's 1.12.1 migrations have already created tables. Dropping
and recreating the schema gives a deterministic exit code, unlike
`pg_restore --clean --if-exists`, which emits harmless errors that make real
failures hard to spot.

On the **UAT** host:

```bash
read -rsp "UAT difyadmin password: " PGPW_UAT; echo
export PGPASSWORD="$PGPW_UAT"
export UAT_HOST=dify-uat-pg-1df2.privatelink.postgres.database.azure.com

for DB in dify dify_plugin; do
  PGSSLMODE=require psql -h "$UAT_HOST" -U difyadmin -d "$DB" \
    -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
done
```

The `vector` and `uuid-ossp` extensions live in `public` and are dropped with it.
The dump recreates them, and `azure.extensions` already allows both. If the drop
fails on ownership, fall back to `pg_restore --clean --if-exists`.

## 4. Dump on Dev, relay, restore on UAT

Neither host can see the other environment's database, so the dump lands on disk
and moves between them. Expect roughly 20–60 minutes for the `dify` restore:
index rebuilds on a `B_Standard_B1ms` are the slow part and may exhaust burst
credits. The dump itself takes about 1m41s and the transfer seconds.
`dify_plugin` is schema only and takes seconds throughout.

On the **Dev** host:

```bash
read -rsp "Dev difyadmin password: " PGPW_DEV; echo
export DEV_HOST=dify-pg-9764.postgres.database.azure.com

for DB in dify dify_plugin; do
  PGPASSWORD="$PGPW_DEV" pg_dump -h "$DEV_HOST" -U difyadmin -d "$DB" \
    -Fc --no-sync -f "$DB.dump"
done
ls -lh dify.dump dify_plugin.dump   # expect ~196 MiB and ~66 KiB
```

Move both files to the UAT host, then delete them from the Dev host — they hold
Dev user content in the clear:

```bash
scp dify.dump dify_plugin.dump azureuser@<uat-host-ip>:~/
shred -u dify.dump dify_plugin.dump
```

On the **UAT** host:

```bash
for DB in dify dify_plugin; do
  echo "=== $DB ==="
  PGPASSWORD="$PGPW_UAT" PGSSLMODE=require pg_restore -h "$UAT_HOST" \
    -U difyadmin -d "$DB" --no-owner --no-privileges "$DB.dump"
done
shred -u dify.dump dify_plugin.dump
```

`--no-owner --no-privileges` is required: `difyadmin` is not a superuser on Azure
PostgreSQL and cannot reassign ownership.

Restoring from a file does make parallel restore (`pg_restore -j`) available, but
it still will not help against a single vCore. Leave it serial.

## 5. Sanitize

Copied rows carry live Dev credentials into UAT. A UAT compromise would
otherwise leak them.

```bash
PGSSLMODE=require psql -h "$UAT_HOST" -U difyadmin -d dify <<'SQL'
TRUNCATE api_tokens;
SQL
```

That removes 34 Dev API keys. Issue fresh UAT keys in step 6.

The 5 rows in `accounts` are Dev logins that now work against UAT. Either delete
all but your own and re-invite through the UI, or clear their credentials and
confirm Dify's reset flow accepts them — verify that behaviour on this version
before relying on it rather than assuming null credentials force a reset.

The 42 rows in `sites` carry Dev public share codes, so Dev share links resolve
in UAT with identical codes. Regenerate them if UAT is reachable by anyone who
should not see Dev apps.

## 6. Restart and verify

```bash
kubectl -n dify scale deploy --replicas=1 --all
kubectl -n dify get pods -w
kubectl -n dify logs -l app.kubernetes.io/component=api --tail=100 | grep -i error
```

Both sides are `1.12.1`, so **no migrations should run here**. Migration output at
this point means the version pin did not hold — check that the `image:` block in
`values-uat.yaml` is still commented out on the deployed branch.

Then confirm: login works, 42 apps and 110 workflows are listed, a workflow
executes, and workflow run history is visible.

Re-enter the model-provider credentials — 1 provider, 2 provider models, 3 tenant
default models. UAT uses a fresh `DIFY_SECRET_KEY`, so the copied encrypted rows
cannot be decrypted. Create new UAT API keys and set the `cme-webapp-api` UAT
variable `DIFY_HTTP_ENDPOINT_URL` to `https://dify-uat.tichealth.com.au/v1`.

## 7. Run the rehearsal

Only now uncomment the `image:` block in `values-uat.yaml` as a complete set, push,
and run the workflow with `deploy_mode: app`. The `1.12.1 → 1.14.2` migrations
execute against 65,732 real `workflow_node_executions` rows. Time them and watch
for lock waits — this is the number that tells you whether the same upgrade is
safe on Dev and Prod.

Then work the acceptance checklist in
[DEPLOY_UAT.md](./DEPLOY_UAT.md#acceptance-checklist).

## 8. Clean up

Both jump hosts go, not just the Dev one:

```bash
az vm delete -g dify-rg-9764 -n dify-dbcopy-vm --yes
az network nic delete -g dify-rg-9764 -n dify-dbcopy-vmVMNic
az disk list -g dify-rg-9764 --query "[?contains(name,'dify-dbcopy')].name" -o tsv

az vm delete -g dify-uat-rg-1df2 -n dify-uat-dbcopy-vm --yes
az network nic delete -g dify-uat-rg-1df2 -n dify-uat-dbcopy-vmVMNic
az disk list -g dify-uat-rg-1df2 --query "[?contains(name,'dbcopy')].name" -o tsv
```

`az vm delete` leaves the NIC, public IP, and OS disk behind. Remove them or they
bill indefinitely. Confirm the dump files were shredded in step 4 before deleting
the disks, so no copy of Dev user content survives on an orphaned disk.

## Known gaps

- **Uploaded files do not come across.** `upload_files` has 2,561 metadata rows
  and `workflow_node_execution_offload` 688, but the payloads live on Azure File
  PVCs. Restored rows reference files absent in UAT, so downloads and offloaded
  node payloads fail. Copy the PVC contents separately or accept broken links.
- **Plugins are not installed.** Plugin packages live on PVCs; `dify_plugin` is
  schema only. Reinstall through the UI.
- **This copies user content.** 1,024 end users and 1,782 conversations, plus
  input/output payloads in `workflow_node_executions`. It requires sign-off and
  it means UAT must be access-controlled like Dev.
