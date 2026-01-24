# Dify AKS Deployment

This directory contains the Terraform and Helm configuration for deploying Dify on Azure Kubernetes Service (AKS) with HTTPS enabled.

## Quick Links

- [Cost Summary](./COST_SUMMARY_2026-01-24.md) - Current cost estimates
- [Cost Optimizations](./COST_OPTIMIZATIONS_2026-01-24.md) - Savings opportunities
- [Infracost](./INFRACOST.md) - Generate exact estimates from Terraform
- [HTTPS Guide](./HTTPS_SETUP_GUIDE.md) - Complete HTTPS/TLS setup and troubleshooting
- [Upgrade Guide](./UPGRADE_GUIDE.md) - How to upgrade Dify versions
- [Docker Compose Comparison](./DOCKER_COMPOSE_COMPARISON.md) - Configuration alignment reference

## Current Deployment Status

- **Dify Version**: 1.11.2
- **HTTPS Status**: `kubectl get certificate -n dify`
- **Ingress IP**: `kubectl get svc -n ingress-nginx ingress-nginx-controller`

## Quick Start

### Deploy Infrastructure + Dify

```bash
./deploy.sh
```

## Configuration Files

- `terraform.tfvars` - Infrastructure variables (git-ignored, contains secrets)
- `values.yaml` - Helm chart values for Dify (includes HTTPS configuration)
- `main.tf` - Terraform infrastructure code
- `coredns-patch.yaml` - CoreDNS configuration (uses external DNS servers for faster resolution)

## HTTPS Status

Check status:
```bash
kubectl get certificate -n dify
```

For troubleshooting or setup details, see [HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md).

## Cost Information

- [COST_SUMMARY_2026-01-24.md](./COST_SUMMARY_2026-01-24.md)
- [COST_OPTIMIZATIONS_2026-01-24.md](./COST_OPTIMIZATIONS_2026-01-24.md)
- [INFRACOST.md](./INFRACOST.md)

## Documentation

- **[COST_SUMMARY_2026-01-24.md](./COST_SUMMARY_2026-01-24.md)** - Cost summary (Dev/Test/Prod)
- **[COST_OPTIMIZATIONS_2026-01-24.md](./COST_OPTIMIZATIONS_2026-01-24.md)** - Cost optimizations
- **[INFRACOST.md](./INFRACOST.md)** - Infracost usage
- **[HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md)** - Complete HTTPS setup, troubleshooting, and DNS configuration
- **[UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)** - Dify version upgrade procedures
- **[DOCKER_COMPOSE_COMPARISON.md](./DOCKER_COMPOSE_COMPARISON.md)** - Configuration alignment with docker-compose.yaml
- **[HOW_TO_GET_AZURE_BLOB_KEY.md](./HOW_TO_GET_AZURE_BLOB_KEY.md)** - Azure Storage account key retrieval
- **[DOCUMENTATION_INDEX.md](./DOCUMENTATION_INDEX.md)** - Complete documentation index
- **[CHANGELOG.md](./CHANGELOG.md)** - Deployment changes and updates
- **[CHANGES_TO_PROPAGATE.md](./CHANGES_TO_PROPAGATE.md)** - Changes to propagate to other environments
- **[POSTGRESQL_ARCHITECTURE.md](./POSTGRESQL_ARCHITECTURE.md)** - PostgreSQL deployment architecture (in-cluster vs Azure Flexible Server)

## Architecture

```
Internet
   ↓
nginx-ingress LoadBalancer (<ingress-lb-ip>)
   ↓
Ingress (TLS termination)
   ↓
Dify Service (ClusterIP)
   ↓
Dify Pods (API, Web, Worker, etc.)
```

## Key Components

- **nginx-ingress**: Routes external traffic and terminates TLS
- **cert-manager**: Manages Let's Encrypt certificates
- **CoreDNS**: Configured to use external DNS (8.8.8.8, 1.1.1.1) for faster resolution
- **Dify**: Application deployed via Helm chart

## Verification

```bash
# Check certificate status
kubectl get certificate -n dify

# Check ingress
kubectl get ingress -n dify

# Test HTTPS
curl -I https://dify-dev.tichealth.com.au/apps

# Check all pods
kubectl get pods -n dify
```

## Support

For issues or questions:
1. Check the relevant guide in this directory
2. Review Kubernetes resources: `kubectl get all -n dify`
3. Check logs: `kubectl logs -n dify -l app.kubernetes.io/name=dify`
