# PostgreSQL Architecture: In-Cluster vs Azure Flexible Server

## Current Deployment: In-Cluster PostgreSQL

**Status**: PostgreSQL is currently deployed **inside the Kubernetes cluster** using the Bitnami PostgreSQL Helm chart.

### Evidence
- **Pods**: `dify-postgresql-primary-0` and `dify-postgresql-read-0` are running in the cluster
- **Storage**: Using PVCs (Persistent Volume Claims) with managed disks
- **Configuration**: `values.yaml` has `postgresql.enabled: true`
- **Terraform**: `use_azure_postgres` is not set (defaults to `false`)

### Architecture

```
AKS Cluster
├── AKS Nodes (Standard_D4s_v5)
│   ├── PostgreSQL Primary Pod (Bitnami)
│   │   └── PVC: 10Gi Premium SSD
│   ├── PostgreSQL Read Pod (Bitnami)
│   │   └── PVC: 8Gi Premium SSD
│   └── Other Dify Pods (API, Web, Worker, etc.)
└── Storage: Managed Disks (Premium SSD)
```

### Cost Impact

**In-Cluster PostgreSQL:**
- **Compute**: Included in AKS node costs (no separate charge)
- **Storage**: ~$3.40/month (10Gi + 8Gi Premium SSD)
- **Total Additional Cost**: ~$3.40/month

**vs Azure PostgreSQL Flexible Server:**
- **Compute**: ~$15-240/month (depending on SKU)
- **Storage**: Included in compute cost
- **Total Additional Cost**: ~$15-240/month

**Savings**: ~$11.60-236.60/month by using in-cluster PostgreSQL

---

## Option: Azure PostgreSQL Flexible Server

The Terraform configuration **supports** Azure PostgreSQL Flexible Server, but it's currently **disabled**.

### How to Enable

1. **Set in `terraform.tfvars`:**
```hcl
use_azure_postgres = true
postgresql_username = "difyadmin"
postgresql_password = "your-secure-password"
postgres_sku_name = "B_Standard_B1ms"  # Dev: Burstable, smallest
postgres_storage_mb = 32768  # 32GB
postgres_public_access = true
postgres_open_firewall_all = true  # Dev only
```

2. **Disable in-cluster PostgreSQL in `values.yaml`:**
```yaml
postgresql:
  enabled: false  # Disable Bitnami PostgreSQL
```

3. **Configure Dify to use external PostgreSQL:**
```yaml
externalPostgresql:
  enabled: true
  host: "<postgresql-server-name>.postgres.database.azure.com"
  port: 5432
  database: "dify"
  username: "difyadmin"
  password: "your-secure-password"
```

### When to Use Azure PostgreSQL Flexible Server

**Use Azure PostgreSQL Flexible Server when:**
- ✅ Need managed backups and point-in-time restore
- ✅ Need high availability (99.99% SLA)
- ✅ Need automatic patching and updates
- ✅ Want to scale database independently from cluster
- ✅ Need advanced monitoring and alerting
- ✅ Production workloads requiring managed service
- ✅ Need to comply with regulations requiring managed databases

**Use In-Cluster PostgreSQL when:**
- ✅ Cost optimization is priority
- ✅ Development/testing environments
- ✅ Simple deployments
- ✅ Don't need managed backups
- ✅ Can tolerate downtime during node maintenance
- ✅ Want everything in one cluster

---

## Comparison Table

| Feature | In-Cluster (Current) | Azure Flexible Server |
|---------|---------------------|----------------------|
| **Cost** | ~$3.40/month (storage only) | ~$15-240/month (compute + storage) |
| **Compute** | Included in AKS nodes | Separate managed service |
| **Backups** | Manual (via Helm chart) | Automatic (7-35 days retention) |
| **High Availability** | Depends on node availability | 99.99% SLA (with HA config) |
| **Scaling** | Requires cluster scaling | Independent scaling |
| **Maintenance** | Manual (via Helm) | Automatic patching |
| **Monitoring** | Basic (via Kubernetes) | Advanced (Azure Monitor) |
| **Point-in-Time Restore** | Not available | Available |
| **Network** | Cluster-internal | External (can be private) |
| **Best For** | Dev/Test, Cost-sensitive | Production, Enterprise |

---

## Current Configuration Details

### In-Cluster PostgreSQL (Bitnami)

**Primary Pod:**
- **Image**: `docker.io/bitnamilegacy/postgresql:15.3.0-debian-11-r7`
- **Storage**: 10Gi Premium SSD
- **Resources**: 256Mi-512Mi memory, 250m-500m CPU

**Read Replica Pod:**
- **Image**: `docker.io/bitnamilegacy/postgresql:15.3.0-debian-11-r7`
- **Storage**: 8Gi Premium SSD
- **Resources**: Similar to primary

**Configuration** (`values.yaml`):
```yaml
postgresql:
  enabled: true
  global:
    postgresql:
      auth:
        username: "postgres"
        password: "difyai123456"
        database: "dify"
  primary:
    persistence:
      enabled: true
      size: 10Gi
    resources:
      requests:
        memory: "256Mi"
        cpu: "250m"
      limits:
        memory: "512Mi"
        cpu: "500m"
```

---

## Migration Path (If Needed)

### From In-Cluster to Azure Flexible Server

1. **Provision Azure PostgreSQL Flexible Server** (via Terraform)
2. **Export data from in-cluster PostgreSQL**
3. **Import data to Azure PostgreSQL Flexible Server**
4. **Update Dify configuration** to use external PostgreSQL
5. **Disable in-cluster PostgreSQL** in `values.yaml`
6. **Redeploy Dify** with new configuration
7. **Verify connectivity** and functionality
8. **Delete in-cluster PostgreSQL** (after verification)

### From Azure Flexible Server to In-Cluster

1. **Export data from Azure PostgreSQL Flexible Server**
2. **Enable in-cluster PostgreSQL** in `values.yaml`
3. **Deploy in-cluster PostgreSQL** (via Helm)
4. **Import data to in-cluster PostgreSQL**
5. **Update Dify configuration** to use in-cluster PostgreSQL
6. **Redeploy Dify** with new configuration
7. **Verify connectivity** and functionality
8. **Delete Azure PostgreSQL Flexible Server** (after verification)

---

## Cost Estimation Update

### Current Deployment (In-Cluster)

| Component | Cost |
|-----------|------|
| PostgreSQL Storage (18Gi Premium SSD) | ~$3.40/month |
| PostgreSQL Compute | Included in AKS nodes |
| **Total PostgreSQL Cost** | **~$3.40/month** |

### If Using Azure Flexible Server

| Component | Dev | Test | Prod |
|-----------|-----|------|------|
| PostgreSQL Compute (B1ms) | ~$15/month | ~$15/month | N/A |
| PostgreSQL Compute (GP D2ds_v5) | N/A | N/A | ~$220-240/month |
| Storage (included) | Included | Included | Included |
| **Total PostgreSQL Cost** | **~$15/month** | **~$15/month** | **~$220-240/month** |

---

## Recommendations

### For Current Dev Environment
✅ **Keep in-cluster PostgreSQL** - Cost-effective, sufficient for dev

### For Test Environment
✅ **Keep in-cluster PostgreSQL** - Cost-effective, sufficient for testing

### For Production Environment
⚠️ **Consider Azure PostgreSQL Flexible Server** if:
- Need managed backups
- Need high availability (99.99% SLA)
- Need point-in-time restore
- Need independent scaling
- Budget allows (~$220-240/month)

✅ **Keep in-cluster PostgreSQL** if:
- Cost optimization is priority
- Can manage backups manually
- Can tolerate brief downtime during maintenance
- Simple deployment requirements

---

## References

- [Bitnami PostgreSQL Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/postgresql)
- [Azure Database for PostgreSQL Flexible Server](https://azure.microsoft.com/services/postgresql/)
- [Azure PostgreSQL Pricing](https://azure.microsoft.com/pricing/details/postgresql/flexible-server/)
