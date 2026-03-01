# Deployment Modes

The `deploy.sh` script supports selective deployment modes to update specific parts of your infrastructure.

## Usage

```bash
./deploy.sh [--db|--app|--all] [--auto-approve] [values-file.yaml]
```

## Modes

### `--all` (Default)

Deploys everything: infrastructure (AKS, PostgreSQL, VNet) and applications (Helm charts).

```bash
./deploy.sh --all
# or simply
./deploy.sh
```

**What it does:**
- ✅ Terraform: AKS cluster, PostgreSQL, VNet, subnets, peering
- ✅ Helm: ingress-nginx, cert-manager, Dify application
- ✅ NSG rules update
- ✅ LoadBalancer IP retrieval

**When to use:**
- Initial deployment
- Full infrastructure refresh
- After major changes

---

### `--db` (Database Only)

Deploys only database-related infrastructure. Skips AKS and all Helm deployments.

```bash
./deploy.sh --db
```

**What it does:**
- ✅ Terraform: PostgreSQL, VNet, management subnet, DNS zones, peering
- ❌ Skips: AKS cluster
- ❌ Skips: All Helm deployments
- ❌ Skips: kubectl operations

**When to use:**
- Update PostgreSQL configuration
- Modify VNet settings
- Add/update management subnet
- Change database extensions
- Update firewall/NSG rules for database

**Example scenarios:**
```bash
# Update PostgreSQL SKU
# Edit terraform.tfvars: postgres_sku_name = "GP_Standard_D2ds_v5"
./deploy.sh --db --auto-approve

# Add management subnet
# Edit terraform.tfvars: management_subnet_address_prefixes = ["10.1.2.0/24"]
./deploy.sh --db --auto-approve
```

---

### `--app` (Application Only)

Deploys only Helm charts. Assumes AKS and PostgreSQL already exist.

```bash
./deploy.sh --app
```

**What it does:**
- ❌ Skips: Terraform infrastructure deployment
- ✅ Helm: ingress-nginx, cert-manager, Dify application
- ✅ NSG rules update
- ✅ LoadBalancer IP retrieval

**Prerequisites:**
- AKS cluster must already exist
- PostgreSQL must already exist (if using external PostgreSQL)
- Terraform state must be available (for reading outputs like PostgreSQL FQDN)

**When to use:**
- Update Dify application configuration
- Upgrade Helm chart versions
- Redeploy after application changes
- Fix application issues without touching infrastructure
- Update values.yaml and redeploy

**Example scenarios:**
```bash
# Update Dify configuration
# Edit values.yaml: change resource limits, environment variables, etc.
./deploy.sh --app --auto-approve

# Upgrade Dify version
# Edit values.yaml: change image tags
./deploy.sh --app --auto-approve

# Fix a broken deployment
./deploy.sh --app --auto-approve
```

---

## Combined Flags

You can combine flags:

```bash
# Database only, skip confirmations
./deploy.sh --db --auto-approve

# Application only, skip confirmations
./deploy.sh --app --auto-approve

# Full deployment, skip confirmations
./deploy.sh --all --auto-approve
```

---

## Workflow Examples

### Scenario 1: Update Database Configuration

```bash
# 1. Edit terraform.tfvars (e.g., change PostgreSQL SKU)
vim terraform.tfvars

# 2. Deploy database changes only
./deploy.sh --db --auto-approve

# 3. Verify PostgreSQL is updated
terraform output postgresql_fqdn
```

### Scenario 2: Update Application Only

```bash
# 1. Edit values.yaml (e.g., change Dify image version)
vim values.yaml

# 2. Deploy application changes only
./deploy.sh --app --auto-approve

# 3. Verify pods are updated
kubectl get pods -n dify
```

### Scenario 3: Full Redeployment

```bash
# Deploy everything from scratch
./deploy.sh --all --auto-approve
```

---

## Important Notes

### `--db` Mode

- **Terraform targeting**: Uses `terraform apply -target` to only update database resources
- **Dependencies**: Automatically includes dependent resources (e.g., VNet peering depends on VNet)
- **State**: Requires existing Terraform state (won't create new resources if state doesn't exist)

### `--app` Mode

- **Prerequisites**: AKS must exist and be accessible
- **Terraform state**: Still reads from Terraform state for outputs (e.g., PostgreSQL FQDN)
- **kubectl**: Requires valid kubeconfig and cluster access
- **PostgreSQL FQDN**: Automatically fetched from Terraform outputs

### Error Handling

If `--app` mode fails because AKS doesn't exist:
```bash
Error: Could not get cluster name or resource group from Terraform outputs
If using --app mode, ensure Terraform state exists and AKS is already deployed.
```

**Solution**: Run `./deploy.sh --all` first to create infrastructure.

---

## Comparison Table

| Feature | `--all` | `--db` | `--app` |
|---------|---------|--------|---------|
| AKS Cluster | ✅ | ❌ | ⚠️ (must exist) |
| PostgreSQL | ✅ | ✅ | ⚠️ (must exist) |
| VNet/Subnets | ✅ | ✅ | ❌ |
| Helm Charts | ✅ | ❌ | ✅ |
| kubectl Operations | ✅ | ❌ | ✅ |
| Terraform Apply | ✅ (all) | ✅ (targeted) | ❌ |
| Time to Deploy | ~15-20 min | ~5-10 min | ~5-10 min |

---

## Best Practices

1. **Use `--db` for infrastructure changes**: Faster, safer, doesn't affect running applications
2. **Use `--app` for application updates**: Quick redeployments without infrastructure changes
3. **Use `--all` for initial setup**: Ensures everything is created correctly
4. **Always use `--auto-approve` in CI/CD**: Prevents interactive prompts
5. **Test in dev first**: Try modes in dev environment before production

---

**Last Updated:** 2026-01-24
