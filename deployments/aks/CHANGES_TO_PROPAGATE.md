# Changes to Propagate from Dev to Test/Prod

This document lists the changes made in the dev environment that should be considered for propagation to test and production environments.

**Date:** 2026-01-24

---

## ✅ **MUST Propagate** (Critical Infrastructure Changes)

### 1. **PostgreSQL External Configuration**
- **What:** Using Azure PostgreSQL Flexible Server instead of in-cluster PostgreSQL
- **Files:** `main.tf`, `terraform.tfvars`, `values.yaml`
- **Status:** ✅ Already in test/prod examples
- **Action:** Ensure test/prod use `use_azure_postgres = true`

### 2. **PostgreSQL Extensions Configuration**
- **What:** Automatic enablement of `vector` and `uuid-ossp` extensions via Terraform
- **Files:** `main.tf` (azure_extensions configuration + null_resource provisioners)
- **Status:** ✅ Should be in all environments
- **Action:** Ensure this code exists in test/prod Terraform

### 3. **Dynamic PostgreSQL FQDN Injection**
- **What:** `deploy.sh` automatically fetches PostgreSQL FQDN from Terraform and passes to Helm
- **Files:** `deploy.sh`
- **Status:** ✅ Should be in all environments
- **Action:** Ensure `deploy.sh` has the `SET_POSTGRES` logic that uses `terraform output postgresql_fqdn`

### 4. **Auto-Approve Flags**
- **What:** `--auto-approve` flag for `deploy.sh` and `teardown.sh` to skip confirmation prompts
- **Files:** `deploy.sh`, `teardown.sh`
- **Status:** ✅ Should be in all environments
- **Action:** Ensure both scripts support `--auto-approve` flag

### 5. **PostgreSQL Private Subnet (NEW)**
- **What:** VNet integration for PostgreSQL with private subnet access
- **Files:** `main.tf`, `variables.tf`, `terraform.tfvars`
- **Status:** ⚠️ **NEW - Should be enabled in test/prod**
- **Action:** 
  - Add to test/prod `terraform.tfvars`:
    ```hcl
    create_vnet_for_postgres = true
    vnet_address_space = ["10.1.0.0/16"]  # Use different ranges for test/prod
    postgres_subnet_address_prefixes = ["10.1.1.0/24"]
    management_subnet_address_prefixes = ["10.1.2.0/24"]  # For jumpbox VMs
    ```
  - Ensure VNet peering code exists in `main.tf`
  - **Note:** When `create_vnet_for_postgres = true`, `postgres_public_access` is automatically set to `false`

### 6. **Management Subnet for Database Access (NEW)**
- **What:** Public subnet for jumpbox VMs to access PostgreSQL for dumps/maintenance
- **Files:** `main.tf`, `variables.tf`, `terraform.tfvars`
- **Status:** ⚠️ **NEW - Optional but recommended for test/prod**
- **Action:**
  - Add `management_subnet_address_prefixes = ["10.1.2.0/24"]` to test/prod `terraform.tfvars`
  - Use different address ranges per environment (e.g., test: `10.2.2.0/24`, prod: `10.3.2.0/24`)
  - See `MANAGEMENT_SUBNET_GUIDE.md` for usage instructions
  - **Security Note:** For production, consider restricting SSH source IPs in NSG instead of allowing from "Internet"

---

## ⚠️ **CONDITIONAL** (Environment-Specific)

### 7. **VM Size Downgrade**
- **What:** Changed from `Standard_D4s_v5` to `Standard_D2ads_v6` in dev
- **Files:** `terraform.tfvars`
- **Status:** ❌ **Dev only** - Test/Prod should keep appropriate sizes
- **Action:** 
  - Test: Keep `Standard_D2s_v5` (as in example)
  - Prod: Keep `Standard_D4s_v5` (as in example)
  - **Do NOT propagate** the dev VM size

### 8. **CPU Resource Adjustments**
- **What:** Removed CPU limits, reduced CPU requests to fit 2 vCPU node
- **Files:** `values.yaml`
- **Status:** ❌ **Dev only** - Test/Prod may need different resources
- **Action:**
  - Review CPU requests/limits based on node sizes in test/prod
  - Test (2 vCPU): May need similar adjustments
  - Prod (4+ vCPU): Can use higher requests/limits
  - **Do NOT blindly copy** dev resource values

### 9. **SSL/TLS Configuration**
- **What:** `postgres_require_secure_transport = false` in dev
- **Files:** `terraform.tfvars`
- **Status:** ❌ **Dev only** - Test/Prod should have SSL enabled
- **Action:**
  - Test: `postgres_require_secure_transport = true` ✅ (already in example)
  - Prod: `postgres_require_secure_transport = true` ✅ (already in example)
  - **Do NOT disable SSL** in test/prod

### 10. **Firewall Rules**
- **What:** `postgres_open_firewall_all = true` in dev
- **Files:** `terraform.tfvars`
- **Status:** ❌ **Dev only** - Test/Prod should restrict firewall
- **Action:**
  - Test: `postgres_open_firewall_all = true` (acceptable for test) or `false` with specific rules
  - Prod: `postgres_open_firewall_all = false` ✅ (already in example) + add specific firewall rules
  - **Do NOT open firewall to all IPs** in prod

---

## 📋 **Checklist for Test/Prod Deployment**

When deploying to test/prod, ensure:

- [ ] `use_azure_postgres = true` in `terraform.tfvars`
- [ ] `create_vnet_for_postgres = true` in `terraform.tfvars` (NEW)
- [ ] `management_subnet_address_prefixes` configured (optional but recommended)
- [ ] VNet address spaces are unique per environment (avoid conflicts)
- [ ] `postgres_require_secure_transport = true` in test/prod
- [ ] `postgres_open_firewall_all = false` in prod (or specific rules)
- [ ] PostgreSQL extensions code exists in `main.tf`
- [ ] `deploy.sh` has dynamic FQDN injection logic
- [ ] `deploy.sh` and `teardown.sh` support `--auto-approve`
- [ ] VM sizes are appropriate for each environment
- [ ] CPU resources in `values.yaml` match node sizes
- [ ] Strong passwords are used (not dev passwords)

---

## 🔄 **Migration Notes**

### When Enabling Private Subnet in Existing Environments

If you have an existing test/prod environment with public PostgreSQL access:

1. **Backup:** Ensure database backups are current
2. **Plan:** Schedule maintenance window (PostgreSQL will be recreated with VNet)
3. **Update:** Set `create_vnet_for_postgres = true` in `terraform.tfvars`
4. **Deploy:** Run `terraform apply` (this will recreate PostgreSQL in private subnet)
5. **Verify:** Test connectivity from AKS pods
6. **Update DNS:** If using private FQDN, update connection strings

**Note:** Enabling VNet integration requires recreating the PostgreSQL server. Plan accordingly.

---

## 📝 **Files Modified in Dev**

### Terraform Files:
- `main.tf` - Added VNet, subnet, Private DNS Zone, VNet peering, PostgreSQL extensions
- `variables.tf` - Added VNet configuration variables
- `terraform.tfvars` - Enabled VNet, configured address spaces

### Scripts:
- `deploy.sh` - Added `--auto-approve` flag, dynamic PostgreSQL FQDN injection
- `teardown.sh` - Added `--auto-approve` flag

### Helm Values:
- `values.yaml` - Removed CPU limits, adjusted CPU requests, external PostgreSQL config

---

## 🎯 **Summary**

**Must Propagate:**
1. PostgreSQL external configuration ✅
2. PostgreSQL extensions automation ✅
3. Dynamic FQDN injection ✅
4. Auto-approve flags ✅
5. **Private subnet configuration** ⚠️ **NEW**
6. **Management subnet** ⚠️ **NEW (optional but recommended)**

**Do NOT Propagate:**
- Dev VM size (Standard_D2ads_v6)
- Dev CPU resource values
- SSL disabled setting
- Open firewall to all IPs (prod)

---

**Last Updated:** 2026-01-24
