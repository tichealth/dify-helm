# PostgreSQL Configuration Guide

## Overview

PostgreSQL is configured as **Azure PostgreSQL Flexible Server** (separate from AKS cluster) for independent scaling and better performance isolation.

## Storage Tiers and IOPS

| Tier | IOPS | Use Case |
|------|------|----------|
| P4 | 120 | Dev (low cost, minimal IOPS) |
| P6 | 240 | Test (low-medium IOPS) |
| P10 | 500 | Test/Prod (medium IOPS) |
| P15 | 1,100 | Prod (medium-high IOPS) |
| P20 | 2,300 | Prod (high IOPS) |
| P30 | 5,000 | Prod (very high IOPS) |
| P40 | 7,500 | Prod (extremely high IOPS) |
| P50 | 10,000 | Prod (maximum IOPS) |

## Environment Configurations

### Dev Environment

**Configuration:**
```hcl
use_azure_postgres = true
postgresql_username = "difyadmin"
postgresql_password = "your-secure-password"
postgres_sku_name = "B_Standard_B1ms"  # 1 vCore, 2GB RAM (smallest available - B1s doesn't exist)
postgres_storage_mb = 32768  # 32GB
postgres_storage_tier = "P4"  # 120 IOPS
postgres_read_replica_count = 0  # No read replica
postgres_public_access = true
postgres_open_firewall_all = true  # Dev only
postgres_require_secure_transport = true
```

**Cost:** ~$15/month (Australia East)

**Note**: `B_Standard_B1s` doesn't exist. The smallest Burstable SKU is `B_Standard_B1ms` (1 vCore, 2GB RAM).

---

### Test Environment

**Configuration:**
```hcl
use_azure_postgres = true
postgresql_username = "difyadmin"
postgresql_password = "your-secure-password"
postgres_sku_name = "B_Standard_B1ms"  # 1 vCore, 2GB RAM
postgres_storage_mb = 32768  # 32GB
postgres_storage_tier = "P10"  # 500 IOPS (higher than dev)
postgres_read_replica_count = 1  # 1 read replica
postgres_read_replica_zone = "2"  # Different AZ from primary (primary typically in zone 1)
postgres_public_access = true
postgres_open_firewall_all = true  # Test only
postgres_require_secure_transport = true
```

**Cost:** ~$30/month (primary ~$15 + replica ~$15)

**Read Replica:**
- Same SKU as primary (B_Standard_B1ms)
- Same storage size (32GB)
- Same storage tier (P10)
- Different availability zone for HA

---

### Prod Environment

**Configuration:**
```hcl
use_azure_postgres = true
postgresql_username = "difyadmin"
postgresql_password = "your-secure-password"
postgres_sku_name = "GP_Standard_D2ds_v5"  # 2 vCore, 8GB RAM
postgres_storage_mb = 131072  # 128GB
postgres_storage_tier = "P15"  # 1,100 IOPS (higher performance)
postgres_read_replica_count = 1  # 1 read replica
postgres_read_replica_zone = "2"  # Different AZ from primary
postgres_public_access = true
postgres_open_firewall_all = false  # Prod: restrict firewall rules
postgres_require_secure_transport = true
```

**Cost:** ~$440-480/month (primary ~$220-240 + replica ~$220-240)

**Read Replica:**
- Same SKU as primary (GP_Standard_D2ds_v5)
- Same storage size (128GB)
- Same storage tier (P15)
- Different availability zone for HA

---

## Read Replica Details

### Benefits
- **High Availability**: Automatic failover capability
- **Read Scaling**: Offload read queries from primary
- **Geographic Distribution**: Can be in different AZ (same region)
- **Disaster Recovery**: Can be promoted to primary if needed

### Configuration
- **Same SKU**: Replicas use same compute SKU as primary
- **Same Storage**: Replicas use same storage size and tier
- **Different AZ**: Replicas are in different availability zone for HA
- **Automatic Sync**: Data is automatically replicated from primary

### Limitations
- **Storage Type**: Primary must use Premium SSD (not Basic)
- **Replication Lag**: May have slight delay (usually < 1 second)
- **Write Operations**: Only primary accepts writes

---

## Migration from In-Cluster PostgreSQL

If migrating from in-cluster PostgreSQL:

1. **Export data**:
   ```bash
   kubectl exec -it dify-postgresql-primary-0 -n dify -- pg_dump -U postgres dify > dify_backup.sql
   kubectl exec -it dify-postgresql-primary-0 -n dify -- pg_dump -U postgres dify_plugin > dify_plugin_backup.sql
   ```

2. **Provision Azure PostgreSQL** (via Terraform)

3. **Import data**:
   ```bash
   psql -h <server-name>.postgres.database.azure.com -U difyadmin -d dify -f dify_backup.sql
   psql -h <server-name>.postgres.database.azure.com -U difyadmin -d dify_plugin -f dify_plugin_backup.sql
   ```

4. **Update Helm values.yaml**:
   ```yaml
   postgresql:
     enabled: false
   
   externalPostgresql:
     enabled: true
     host: "<server-name>.postgres.database.azure.com"
     port: 5432
     database: "dify"
     username: "difyadmin"
     password: "your-secure-password"
     sslMode: "require"
   ```

5. **Deploy updated Helm chart**

6. **Verify and cleanup** in-cluster PostgreSQL

---

## Terraform Variables Reference

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `use_azure_postgres` | Enable Azure PostgreSQL Flexible Server | `false` | `true` |
| `postgresql_username` | PostgreSQL admin username | `"postgres"` | `"difyadmin"` |
| `postgresql_password` | PostgreSQL admin password | - | `"secure-password"` |
| `postgres_sku_name` | Compute SKU | `"B_Standard_B1ms"` | `"B_Standard_B1s"`, `"GP_Standard_D2ds_v5"` |
| `postgres_storage_mb` | Storage size in MB | `32768` (32GB) | `32768`, `131072` (128GB) |
| `postgres_storage_tier` | Storage tier (IOPS) | `"P4"` | `"P4"`, `"P10"`, `"P15"` |
| `postgres_read_replica_count` | Number of read replicas | `0` | `0` (dev), `1` (test/prod) |
| `postgres_read_replica_zone` | AZ for read replica | `null` (auto) | `"2"` (different from primary) |
| `postgres_public_access` | Enable public network access | `true` | `true` (dev/test), `false` (prod) |
| `postgres_open_firewall_all` | Open firewall to all IPs | `true` | `true` (dev/test), `false` (prod) |
| `postgres_require_secure_transport` | Require SSL | `true` | `true` |

---

## Cost Summary

| Environment | SKU | Storage | Tier | Replicas | Monthly Cost (AUD) |
|------------|-----|---------|------|----------|-------------------|
| Dev | B_Standard_B1s | 32GB | P4 (120 IOPS) | 0 | ~$10-12 |
| Test | B_Standard_B1ms | 32GB | P10 (500 IOPS) | 1 | ~$30 |
| Prod | GP_Standard_D2ds_v5 | 128GB | P15 (1,100 IOPS) | 1 | ~$440-480 |

---

## References

- [Azure PostgreSQL Flexible Server Storage Tiers](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-storage)
- [Azure PostgreSQL Read Replicas](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/how-to-create-read-replica)
- [Azure PostgreSQL Pricing](https://azure.microsoft.com/pricing/details/postgresql/flexible-server/)
