# Cost Summary (Dev/Test/Prod)

Date: 2026-01-24
Region: Australia East (australiaeast)
Currency: AUD (estimated)

## Scope
Based on Terraform in this directory:
- **Dev**: `terraform.tfvars`
- **Test**: `environments/test.tfvars.example` (or `environments/test.tfvars` if created)
- **Prod**: `environments/prod.tfvars.example` (or `environments/prod.tfvars` if created)

Use Infracost for exact, current pricing (see `INFRACOST.md`).

## Resources by environment

### Dev
- AKS system pool: 1 x Standard_D2ads_v6 (from `terraform.tfvars`)
- AKS spot pool: disabled (no spot in current config)
- PostgreSQL Flexible Server: B_Standard_B1ms, 32 GB
- Storage: Azure Blob (usage-based), AKS disks, Azure Files PVCs
- Networking: Standard Load Balancer + public IP

Estimated monthly cost (AUD): **~131–153**

### Test
- AKS system pool: 1 x Standard_D2s_v5
- AKS spot pool: 1 x Standard_D4s_v5 (spot enabled)
- PostgreSQL Flexible Server: B_Standard_B1ms, 32 GB
- Storage: Azure Blob (usage-based), AKS disks, Azure Files PVCs
- Networking: Standard Load Balancer + public IP

Estimated monthly cost (AUD): **~170–214**

### Prod
- AKS system pool: 3 x Standard_D4s_v5
- AKS spot pool: disabled
- PostgreSQL Flexible Server: GP_Standard_D2ds_v5, 128 GB
- Storage: Azure Blob (usage-based), AKS disks, Azure Files PVCs
- Networking: Standard Load Balancer + public IP

Estimated monthly cost (AUD): **~933–1,041**

## Notes
- Largest drivers: AKS compute and managed PostgreSQL.
- Storage and egress are usage‑based and will vary.

## Next step for exact pricing
Use Infracost from `dify-helm/deployments/aks` (see `INFRACOST.md`).
