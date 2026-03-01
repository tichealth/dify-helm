# Migration to Private Subnet - PostgreSQL

## ⚠️ **CRITICAL WARNING**

**Moving PostgreSQL from public to private subnet requires RECREATING the server, which will DELETE ALL DATA.**

This is an Azure limitation - you cannot change `public_network_access_enabled` or add `delegated_subnet_id` to an existing PostgreSQL Flexible Server.

---

## Migration Options

### Option 1: Fresh Deployment (No Data to Preserve)

If this is a **new deployment** or you **don't need to preserve data**:

```bash
# Simply run the full deployment
./deploy.sh --all --auto-approve
```

**What happens:**
1. Terraform will detect the change
2. It will **destroy** the existing PostgreSQL server (and all data)
3. It will **create** a new PostgreSQL server in the private subnet
4. Helm will deploy Dify with the new database (empty)

**Time:** ~10-15 minutes

---

### Option 2: Preserve Data (Backup & Restore)

If you **have data you need to preserve**:

#### Step 1: Backup Current Database

```bash
# Option A: Using Azure Portal
# 1. Go to Azure Portal → Your PostgreSQL server
# 2. Go to "Backups" → Create manual backup
# 3. Or use automated backup (if enabled)

# Option B: Using pg_dump from a VM or your local machine
PGPASSWORD='difyai123456' pg_dump \
  -h <current-postgres-fqdn> \
  -U difyadmin \
  -d dify \
  -F c \
  -f dify_backup_$(date +%Y%m%d_%H%M%S).dump

# Also backup plugin database
PGPASSWORD='difyai123456' pg_dump \
  -h <current-postgres-fqdn> \
  -U difyadmin \
  -d dify_plugin \
  -F c \
  -f dify_plugin_backup_$(date +%Y%m%d_%H%M%S).dump
```

#### Step 2: Deploy New Infrastructure

```bash
# Deploy database infrastructure (this will recreate PostgreSQL)
./deploy.sh --db --auto-approve
```

**What happens:**
- Old PostgreSQL server is destroyed
- New PostgreSQL server is created in private subnet
- Databases are created (empty)
- Extensions are installed

#### Step 3: Restore Data

```bash
# Get the new private FQDN
terraform output postgresql_fqdn

# Create a VM in the management subnet (see MANAGEMENT_SUBNET_GUIDE.md)
# Or use Azure Cloud Shell

# Restore main database
PGPASSWORD='difyai123456' pg_restore \
  -h <new-private-fqdn> \
  -U difyadmin \
  -d dify \
  -v \
  dify_backup_YYYYMMDD_HHMMSS.dump

# Restore plugin database
PGPASSWORD='difyai123456' pg_restore \
  -h <new-private-fqdn> \
  -U difyadmin \
  -d dify_plugin \
  -v \
  dify_plugin_backup_YYYYMMDD_HHMMSS.dump
```

#### Step 4: Redeploy Application

```bash
# Redeploy Dify application (it will connect to the new database)
./deploy.sh --app --auto-approve
```

**Time:** ~20-30 minutes (depending on database size)

---

## Step-by-Step: Fresh Deployment (No Data)

If you're okay with losing data (dev environment, fresh start):

### 1. Verify Configuration

```bash
# Check terraform.tfvars
cat terraform.tfvars | grep -A 5 "VNet Configuration"
```

Should show:
```hcl
create_vnet_for_postgres = true
vnet_address_space = ["10.1.0.0/16"]
postgres_subnet_address_prefixes = ["10.1.1.0/24"]
management_subnet_address_prefixes = ["10.1.2.0/24"]
```

### 2. Run Full Deployment

```bash
# This will:
# - Create VNet, subnets, DNS zones
# - Recreate PostgreSQL in private subnet (DESTROYS OLD DATA)
# - Set up VNet peering with AKS
# - Deploy all Helm charts
./deploy.sh --all --auto-approve
```

### 3. Verify Deployment

```bash
# Check PostgreSQL is in private subnet
terraform output postgresql_fqdn
# Should show: <server-name>.privatelink.postgres.database.azure.com

# Check VNet
terraform output vnet_id

# Check management subnet
terraform output management_subnet_id

# Verify Dify pods can connect
kubectl get pods -n dify
kubectl logs -n dify deployment/dify-api | grep -i postgres
```

---

## What Terraform Will Do

When you run `terraform apply` with `create_vnet_for_postgres = true`:

1. **Create VNet resources:**
   - `azurerm_virtual_network.postgres`
   - `azurerm_subnet.postgres` (delegated)
   - `azurerm_subnet.management`
   - `azurerm_private_dns_zone.postgres`
   - NSG and rules

2. **Recreate PostgreSQL:**
   - **Destroy** existing `azurerm_postgresql_flexible_server.pg`
   - **Create** new PostgreSQL server with:
     - `delegated_subnet_id` set
     - `private_dns_zone_id` set
     - `public_network_access_enabled = false`

3. **Set up peering:**
   - VNet peering between PostgreSQL VNet and AKS VNet

4. **Create databases:**
   - `dify` database
   - `dify_plugin` database
   - Install extensions (`vector`, `uuid-ossp`)

---

## Troubleshooting

### Error: "Cannot change public_network_access_enabled"

**Cause:** Terraform is trying to update an existing server.

**Solution:** Terraform will automatically destroy and recreate. This is expected.

### Error: "Subnet not found" or "DNS zone not found"

**Cause:** Dependencies not created in correct order.

**Solution:** Terraform handles dependencies automatically. If it fails, run:
```bash
terraform apply -auto-approve
# Terraform will create resources in the correct order
```

### Error: "VNet peering failed"

**Cause:** AKS VNet might not exist yet or peering already exists.

**Solution:** 
- If AKS doesn't exist, run `./deploy.sh --all` instead of `--db`
- If peering exists, Terraform will update it

### Application Cannot Connect to PostgreSQL

**Cause:** VNet peering not working or DNS not resolving.

**Solution:**
```bash
# Check VNet peering
terraform output vnet_id
az network vnet peering list --resource-group <rg> --vnet-name <vnet>

# Test DNS resolution from AKS pod
kubectl run -it --rm debug --image=postgres:16 --restart=Never -- nslookup <postgres-private-fqdn>

# Check PostgreSQL is accessible
kubectl run -it --rm debug --image=postgres:16 --restart=Never -- \
  psql -h <postgres-private-fqdn> -U difyadmin -d dify
```

---

## Rollback Plan

If something goes wrong and you need to rollback:

### Option 1: Disable Private Subnet

```bash
# Edit terraform.tfvars
create_vnet_for_postgres = false

# This will recreate PostgreSQL in public mode (DESTROYS DATA AGAIN)
./deploy.sh --db --auto-approve
```

### Option 2: Restore from Backup

If you have backups:
1. Restore from backup (see Option 2 above)
2. Or use Azure Portal to restore from automated backup

---

## Recommended Approach for Dev

Since this is a **dev environment**:

1. **If no important data:** Just run `./deploy.sh --all --auto-approve`
2. **If you have test data:** Backup first, then restore after migration

---

## Recommended Approach for Prod

For production:

1. **Schedule maintenance window**
2. **Create full backup** (automated + manual)
3. **Test migration in dev/test first**
4. **Run migration during maintenance window**
5. **Verify connectivity**
6. **Restore data if needed**
7. **Test application thoroughly**

---

## Quick Reference

```bash
# Fresh deployment (no data preservation)
./deploy.sh --all --auto-approve

# Database only (recreates PostgreSQL)
./deploy.sh --db --auto-approve

# Application only (after database migration)
./deploy.sh --app --auto-approve

# Check PostgreSQL FQDN
terraform output postgresql_fqdn

# Check VNet
terraform output vnet_id
```

---

**Last Updated:** 2026-01-24
