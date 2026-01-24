# How to Get PostgreSQL Endpoint (FQDN)

After deploying Azure PostgreSQL Flexible Server via Terraform, here are several ways to find the endpoint/FQDN:

## Method 1: Terraform Output (Recommended)

After running `terraform apply`, get the PostgreSQL FQDN directly:

```bash
# Get just the PostgreSQL FQDN
terraform output postgresql_fqdn

# Get all outputs (including PostgreSQL info)
terraform output

# Get PostgreSQL connection string (without password)
terraform output postgresql_connection_string
```

**Example output:**
```
postgresql_fqdn = "dify-pg-abc123.postgres.database.azure.com"
```

---

## Method 2: Azure Portal (Web UI)

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Database for PostgreSQL flexible servers**
3. Click on your PostgreSQL server (name will be like `dify-pg-xxxxx`)
4. In the **Overview** page, you'll see:
   - **Server name**: The FQDN (e.g., `dify-pg-abc123.postgres.database.azure.com`)
   - **Connection strings**: Pre-formatted connection strings

---

## Method 3: Azure CLI

```bash
# List all PostgreSQL flexible servers in your subscription
az postgres flexible-server list --output table

# Get specific server details (replace with your server name)
az postgres flexible-server show \
  --resource-group <your-resource-group-name> \
  --name <your-postgres-server-name> \
  --query "fullyQualifiedDomainName" \
  --output tsv

# Or get all details in JSON format
az postgres flexible-server show \
  --resource-group <your-resource-group-name> \
  --name <your-postgres-server-name>
```

**To find your resource group and server name:**
```bash
# Get resource group name from Terraform
terraform output resource_group_name

# PostgreSQL server name follows pattern: <project-name>-pg-<random-suffix>
# You can list all servers to find it:
az postgres flexible-server list --query "[].{Name:name, ResourceGroup:resourceGroup, FQDN:fullyQualifiedDomainName}" --output table
```

---

## Method 4: From Terraform State

If you have access to the Terraform state:

```bash
# Show PostgreSQL resource details
terraform state show azurerm_postgresql_flexible_server.pg[0]

# Or query specific attribute
terraform state show azurerm_postgresql_flexible_server.pg[0] | grep fqdn
```

---

## Method 5: PowerShell (Azure PowerShell)

```powershell
# Get PostgreSQL server details
$server = Get-AzPostgreSqlFlexibleServer `
  -ResourceGroupName "<your-resource-group-name>" `
  -Name "<your-postgres-server-name>"

# Get FQDN
$server.FullyQualifiedDomainName

# Or get all properties
$server | Select-Object Name, FullyQualifiedDomainName, Location, Sku
```

---

## Using the Endpoint in Helm values.yaml

Once you have the FQDN, update your `values.yaml`:

```yaml
postgresql:
  enabled: false  # Disable in-cluster PostgreSQL

externalPostgresql:
  enabled: true
  host: "dify-pg-abc123.postgres.database.azure.com"  # Use the FQDN from terraform output
  port: 5432
  database: "dify"
  username: "difyadmin"  # From terraform.tfvars
  password: "your-password"  # From terraform.tfvars (postgresql_password)
  sslMode: "require"  # Azure requires SSL
```

---

## Quick Reference: Connection Details

After `terraform apply`, you'll have:

| Item | Source |
|------|--------|
| **FQDN** | `terraform output postgresql_fqdn` |
| **Username** | `terraform.tfvars` → `postgresql_username` |
| **Password** | `terraform.tfvars` → `postgresql_password` |
| **Database** | `terraform.tfvars` → `postgresql_database` (default: "dify") |
| **Port** | `5432` (standard PostgreSQL port) |
| **SSL** | Required (`sslMode: "require"`) |

---

## Example: Complete Workflow

```bash
# 1. Deploy infrastructure
cd dify-helm/deployments/aks
terraform apply

# 2. Get PostgreSQL FQDN
POSTGRES_FQDN=$(terraform output -raw postgresql_fqdn)
echo "PostgreSQL FQDN: $POSTGRES_FQDN"

# 3. Update values.yaml (manually or via script)
# Edit values.yaml and set:
# externalPostgresql.host = "$POSTGRES_FQDN"

# 4. Deploy Helm chart
./deploy.sh
```

---

## Troubleshooting

### If `terraform output` shows "N/A"
- Check that `use_azure_postgres = true` in your `terraform.tfvars`
- Verify Terraform apply completed successfully
- Check Terraform state: `terraform state list | grep postgresql`

### If you can't find the server in Azure Portal
- Check the correct subscription
- Verify the resource group name: `terraform output resource_group_name`
- Search for resources with tag `component = postgres`

### Connection Issues
- Ensure firewall rules allow your IP (or `postgres_open_firewall_all = true` for dev)
- Verify SSL is enabled: `postgres_require_secure_transport = true`
- Check that the server is in "Ready" state in Azure Portal

---

## Read Replicas

If you have read replicas configured (Test/Prod), get their FQDNs:

```bash
# Get all read replica FQDNs
terraform output postgresql_read_replica_fqdns

# Example output:
# postgresql_read_replica_fqdns = [
#   "dify-pg-abc123-replica-1.postgres.database.azure.com"
# ]
```

Read replicas can be used for read-only queries to offload the primary database.
