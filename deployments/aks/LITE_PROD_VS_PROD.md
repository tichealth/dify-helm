# Lite Prod vs Full Prod: Cost, Scalability, and When to Use

Discussion doc before making changes. Region: Australia East (australiaeast). Currency: AUD (approximate).

---

## 1. What We’re Defining

| Variant | Purpose | Nodes | PostgreSQL | Use case |
|--------|---------|--------|------------|----------|
| **Lite prod** | Low-cost production | **1 node** | Smaller SKU, less storage | Early prod, low traffic, cost-sensitive; no need for multi-node resilience. |
| **Full prod** | Higher capacity / resilience | **3 nodes** | Larger SKU, more storage | When you want node-level HA and room to scale out. |

---

## 2. Cost Comparison (Estimated Monthly, AUD)

Based on current Azure list pricing and [COST_SUMMARY_2026-01-24.md](./COST_SUMMARY_2026-01-24.md).

| Component | Lite prod | Full prod |
|-----------|-----------|-----------|
| **AKS** | 1 × Standard_D4s_v5 (or 1 × D2s_v5 for lower) | 3 × Standard_D4s_v5 |
| **PostgreSQL** | B_Standard_B1ms, 32 GB (or GP_Standard_D2ds_v5, 32 GB) | GP_Standard_D2ds_v5, 128 GB |
| **Load balancer, disks, blob** | Same order of magnitude | Same |
| **Estimated total** | **~250–350 / month** | **~930–1,040 / month** |

- **Lite prod** saves roughly **~600–700 AUD/month** vs full prod, mainly from 2 fewer AKS nodes and smaller PostgreSQL.
- For more exact numbers, run Infracost from this directory (see [INFRACOST.md](./INFRACOST.md)) with the chosen tfvars.

---

## 3. Does Lite Prod “Scale”?

Yes, but within a single node.

- **Vertical scaling**  
  - Same for both: you can increase node size (e.g. D4s_v5 → D8s_v5) or PostgreSQL SKU/storage in place.
- **Horizontal scaling (more pods)**  
  - **Lite (1 node):** You can increase Dify replicas (API, worker, etc.) and they all run on that one node. Throughput can go up until you hit the node’s CPU/memory. There is no “active–active” across nodes; it’s single-node scaling.
- **Resilience**  
  - **Lite:** One node = single point of failure. If the node goes down, the app is down until the node (or replacement) is back.
  - **Full (3 nodes):** Workloads spread across nodes; one node failure doesn’t take down the whole app. Better availability and “scale” in the sense of spreading load and surviving node failure.

So: lite prod scales vertically and can run more replicas on the same node; full prod adds node-level resilience and horizontal spread.

---

## 4. Difference in Scalability: Summary

| Aspect | Lite prod (1 node) | Full prod (3 nodes) |
|--------|--------------------|----------------------|
| **Add more API/worker replicas** | Yes (all on 1 node) | Yes (spread across nodes) |
| **Survive single node failure** | No | Yes |
| **Bigger single-node capacity** | Yes (resize VM) | Yes (resize VM) |
| **Add more nodes later** | Yes (change tfvars and scale) | Yes (already 3; can add more) |
| **Active–active across nodes** | No (only one node) | Yes (multiple nodes) |

So the main difference is **resilience and multi-node spread**, not “can it scale at all.” Lite prod is fine when you’re okay with one node and want lower cost.

---

## 5. Suggested Layout

- **`environments/lite-prod.tfvars`**  
  - 1 node, smaller PostgreSQL (e.g. B_Standard_B1ms 32 GB or GP_Standard_D2ds_v5 with 32 GB).  
  - Use for: low-cost prod, no need for active–active nodes.

- **`environments/prod-full.tfvars`**  
  - 3 nodes, Standard_D4s_v5, GP_Standard_D2ds_v5 128 GB (current “full” prod).  
  - Use when you want node-level HA and higher capacity.

- **Current `prod-no-dr.tfvars`**  
  - Can be treated as “full prod” (3 nodes, 128 GB) and aligned with `prod-full.tfvars`, or retired in favour of `prod-full.tfvars`.

---

## 6. GitHub Actions

Use the **manual** workflow: [Deploy or teardown Dify on AKS](../../.github/workflows/deploy-aks.yml). Choose **action** (deploy/teardown), **deploy_mode** (all/app/db), **environment** (lite-prod or prod-full). Secrets are passed as `TF_VAR_*` from GitHub Secrets — see [GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md).

---

## 7. Moving from Lite Prod to Full Prod (No Data Loss)

Yes. You can move from lite to full **without data loss** by doing an **in-place scale-up** of the same cluster and database.

### In-place upgrade (recommended)

Keep the **same** `project_name` (and thus the same resource group, AKS cluster, and PostgreSQL server). Only change:

- `node_count`: 1 → 3  
- `postgres_sku_name`: e.g. `B_Standard_B1ms` → `GP_Standard_D2ds_v5`  
- `postgres_storage_mb`: e.g. 32768 → 131072  

Then run:

```bash
cd deployments/aks
# Use your existing terraform.tfvars (from lite), edit the three settings above, then:
terraform plan   # confirm: AKS node count change, PostgreSQL in-place update
terraform apply
./deploy.sh --app --auto-approve   # optional: refresh Helm if needed
```

- **AKS:** Terraform updates the node pool (1 → 3 nodes). Azure adds nodes; existing pods can be rescheduled. No data loss.
- **PostgreSQL:** Azure Database for PostgreSQL Flexible Server supports **in-place scaling** of SKU and storage. There may be a short restart or brief read-only window depending on the change; data is preserved.
- **Blob / Redis / Qdrant:** Unchanged (same cluster, same storage account). No migration.

So: **same project_name + only scaling node_count and PostgreSQL = no data loss.**

### Downtime

| Change | Downtime? |
|--------|------------|
| **AKS: 1 → 3 nodes** | Typically **no**. New nodes are added; existing pods keep running on the current node. Kubernetes may reschedule some workloads once new nodes are ready. |
| **PostgreSQL: SKU / storage scale** | **Yes.** Azure usually **restarts** the server for the change. The DB is unavailable for a few minutes (often ~2–5 min; can be longer for large storage changes). During that window Dify will be down (API and workers cannot reach the DB). |

**Practical approach:** Plan a short maintenance window (e.g. 10–15 minutes), scale PostgreSQL first (accept the restart), then run Terraform for the AKS node count change. Or scale AKS first during normal operation (no app impact), then schedule the PostgreSQL scale in a maintenance window.

### If you used different project names (lite vs full)

`lite-prod.tfvars` uses `project_name = "dify-prod-lite"` and `prod-full.tfvars` uses `project_name = "dify-prod"`. If you **first deployed lite** with that default, your resources are named `dify-prod-lite-*`. To move to “full” **in place** (no data loss), **do not switch to prod-full.tfvars as-is** (that would create a new `dify-prod` cluster and DB). Instead:

- Keep using your current `terraform.tfvars` (the one that matches your live lite deployment).
- In that file, keep `project_name = "dify-prod-lite"` and only change `node_count`, `postgres_sku_name`, and `postgres_storage_mb` as above. Then `terraform apply`.

If you really want a **new** full prod deployment (e.g. new `dify-prod` cluster and DB) and to retire lite, that’s a **migration**: backup PostgreSQL and restore to the new server, copy Azure Blob data, point the new Dify at the new DB and Blob. Doable without data loss if you follow a proper backup/restore and cutover.

### Summary

| Path | Data loss? |
|------|------------|
| In-place: same project, scale nodes + PG only | **No** |
| New cluster/DB + backup & restore + Blob copy | **No** (if done correctly) |
| New cluster/DB with no migration | Yes (new empty DB) |

If you want different node counts or SKUs (e.g. 1 × D2s_v5 for lite, or 2 nodes for a middle tier), add another env file and a row in the cost table. Run [Infracost](./INFRACOST.md) with each tfvars file for exact estimates.
