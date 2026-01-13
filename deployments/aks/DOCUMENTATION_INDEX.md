# Documentation Index

Complete guide to all documentation for the Dify AKS deployment.

## Main Documentation

### [README.md](./README.md)
**Primary entry point** - Overview, quick start, current status, and links to all other documentation.

### [HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md)
**Complete HTTPS/TLS guide** - Setup instructions, troubleshooting, DNS configuration, certificate management, and current status.

### [COST_ESTIMATION.md](./COST_ESTIMATION.md)
**Cost analysis** - Detailed monthly cost breakdown, optimization recommendations, scaling scenarios, and HTTPS cost impact.

### [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)
**Version upgrades** - Step-by-step guide for upgrading Dify versions, version compatibility reference, and common issues.

### [DOCKER_COMPOSE_COMPARISON.md](./DOCKER_COMPOSE_COMPARISON.md)
**Configuration alignment** - Comparison between docker-compose.yaml and Helm chart configuration to ensure compatibility.

### [POD_STATUS_SUMMARY.md](./POD_STATUS_SUMMARY.md)
**Current deployment status** - Pod health check, version information, and recent changes.

### [HOW_TO_GET_AZURE_BLOB_KEY.md](./HOW_TO_GET_AZURE_BLOB_KEY.md)
**Azure Storage setup** - Instructions for retrieving Azure Blob Storage account keys.

### [CHANGELOG.md](./CHANGELOG.md)
**Deployment changes** - History of changes, upgrades, and configuration updates.

## Quick Reference

### Current Deployment
- **Domain**: `dify-dev.tichealth.com.au`
- **HTTPS**: ✅ Enabled (Let's Encrypt)
- **Dify Version**: 1.11.2
- **Cost**: ~$77-90/month (includes HTTPS)

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

# Test HTTPS
curl -I https://dify-dev.tichealth.com.au

# Check ingress
kubectl get ingress -n dify
```

## Documentation Structure

```
dify-helm/deployments/aks/
├── README.md                      # Main overview
├── HTTPS_SETUP_GUIDE.md          # Complete HTTPS guide (consolidated)
├── COST_ESTIMATION.md            # Cost analysis
├── UPGRADE_GUIDE.md              # Version upgrade procedures
├── DOCKER_COMPOSE_COMPARISON.md  # Configuration alignment
├── POD_STATUS_SUMMARY.md         # Current pod status
├── HOW_TO_GET_AZURE_BLOB_KEY.md  # Azure Storage setup
├── CHANGELOG.md                  # Deployment changes history
└── DOCUMENTATION_INDEX.md        # This file
```

## Getting Help

1. **HTTPS Issues**: See [HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md) troubleshooting section
2. **Upgrade Questions**: See [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)
3. **Cost Questions**: See [COST_ESTIMATION.md](./COST_ESTIMATION.md)
4. **Configuration Issues**: See [DOCKER_COMPOSE_COMPARISON.md](./DOCKER_COMPOSE_COMPARISON.md)
