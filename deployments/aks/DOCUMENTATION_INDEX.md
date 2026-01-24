# Documentation Index

Complete guide to all documentation for the Dify AKS deployment.

## Main Documentation

### [README.md](./README.md)
**Primary entry point** - Overview, quick start, current status, and links to all other documentation.

### [HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md)
**Complete HTTPS/TLS guide** - Setup instructions, troubleshooting, DNS configuration, certificate management, and current status.

### [COST_SUMMARY_2026-01-24.md](./COST_SUMMARY_2026-01-24.md)
**Cost summary** - Current monthly estimates for Dev, Test, Prod.

### [COST_OPTIMIZATIONS_2026-01-24.md](./COST_OPTIMIZATIONS_2026-01-24.md)
**Cost optimization** - Recommended savings opportunities by environment.

### [INFRACOST.md](./INFRACOST.md)
**Infracost usage** - How to generate exact estimates from Terraform.

### [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)
**Version upgrades** - Step-by-step guide for upgrading Dify versions, version compatibility reference, and common issues.

### [DOCKER_COMPOSE_COMPARISON.md](./DOCKER_COMPOSE_COMPARISON.md)
**Configuration alignment** - Comparison between docker-compose.yaml and Helm chart configuration to ensure compatibility.

### [HOW_TO_GET_AZURE_BLOB_KEY.md](./HOW_TO_GET_AZURE_BLOB_KEY.md)
**Azure Storage setup** - Instructions for retrieving Azure Blob Storage account keys.

### [CHANGELOG.md](./CHANGELOG.md)
**Deployment changes** - History of changes, upgrades, and configuration updates.

### [CHANGES_TO_PROPAGATE.md](./CHANGES_TO_PROPAGATE.md)
**Propagation guide** - Changes made in dev that should be propagated to test and production environments.

## Quick Reference

### Current Deployment
- **Domain**: `dify-dev.tichealth.com.au`
- **HTTPS**: Check with `kubectl get certificate -n dify`
- **Dify Version**: 1.11.2
- **Cost**: See `COST_SUMMARY_2026-01-24.md`

### Key Files
- `values.yaml` - Helm chart configuration (includes HTTPS settings)
- `terraform.tfvars` - Infrastructure variables (git-ignored)
- `coredns-patch.yaml` - CoreDNS configuration (external DNS servers)

### Common Commands

```bash
# Check certificate status
kubectl get certificate -n dify

# Check all pods
kubectl get pods -n dify

# Check ingress and ingress LoadBalancer IP
kubectl get ingress -n dify
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

## Documentation Structure

```
dify-helm/deployments/aks/
├── README.md                      # Main overview
├── HTTPS_SETUP_GUIDE.md          # Complete HTTPS guide (consolidated)
├── COST_SUMMARY_2026-01-24.md     # Current cost summary
├── COST_OPTIMIZATIONS_2026-01-24.md # Cost optimization recommendations
├── INFRACOST.md                  # Infracost usage
├── UPGRADE_GUIDE.md              # Version upgrade procedures
├── DOCKER_COMPOSE_COMPARISON.md  # Configuration alignment
├── HOW_TO_GET_AZURE_BLOB_KEY.md  # Azure Storage setup
├── CHANGELOG.md                  # Deployment changes history
└── DOCUMENTATION_INDEX.md        # This file
```

## Getting Help

1. **HTTPS Issues**: See [HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md) troubleshooting section
2. **Upgrade Questions**: See [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)
3. **Cost Questions**: See [COST_SUMMARY_2026-01-24.md](./COST_SUMMARY_2026-01-24.md) and [INFRACOST.md](./INFRACOST.md)
4. **Configuration Issues**: See [DOCKER_COMPOSE_COMPARISON.md](./DOCKER_COMPOSE_COMPARISON.md)
