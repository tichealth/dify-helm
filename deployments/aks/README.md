# Dify AKS Deployment

This directory contains the Terraform and Helm configuration for deploying Dify on Azure Kubernetes Service (AKS) with HTTPS enabled.

## Quick Links

- [Cost Estimation](./COST_ESTIMATION.md) - Detailed cost breakdown and optimization recommendations
- [HTTPS Guide](./HTTPS_SETUP_GUIDE.md) - Complete HTTPS/TLS setup and troubleshooting
- [Upgrade Guide](./UPGRADE_GUIDE.md) - How to upgrade Dify versions
- [Docker Compose Comparison](./DOCKER_COMPOSE_COMPARISON.md) - Configuration alignment reference

## Current Deployment Status

- **AKS Cluster**: 1 node (Standard_D4s_v5)
- **Dify Version**: 1.11.2
- **HTTPS**: ✅ **Enabled** - `https://dify-dev.tichealth.com.au`
- **Certificate**: Let's Encrypt (Production) - Auto-renewing
- **Estimated Monthly Cost**: ~$77-90/month (includes HTTPS)

## Quick Start

### Deploy Infrastructure

```bash
cd dify-helm/deployments/aks
terraform init
terraform plan
terraform apply
```

### Deploy Dify Application

```bash
./deploy.sh
```

## Configuration Files

- `terraform.tfvars` - Infrastructure variables (git-ignored, contains secrets)
- `values.yaml` - Helm chart values for Dify (includes HTTPS configuration)
- `main.tf` - Terraform infrastructure code
- `coredns-patch.yaml` - CoreDNS configuration (uses external DNS servers for faster resolution)

## HTTPS Status

✅ **HTTPS is enabled and working**

- **Domain**: `dify-dev.tichealth.com.au`
- **Certificate**: Let's Encrypt (Production, auto-renewing)
- **Auto-renewal**: Enabled (cert-manager will renew automatically)
- **Access**: `https://dify-dev.tichealth.com.au`

For troubleshooting or setup details, see [HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md).

## Cost Information

See [COST_ESTIMATION.md](./COST_ESTIMATION.md) for:
- Detailed cost breakdown
- Optimization recommendations
- Scaling scenarios
- HTTPS cost impact

## Documentation

- **[COST_ESTIMATION.md](./COST_ESTIMATION.md)** - Cost analysis and optimization
- **[HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md)** - Complete HTTPS setup, troubleshooting, and DNS configuration
- **[UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)** - Dify version upgrade procedures
- **[DOCKER_COMPOSE_COMPARISON.md](./DOCKER_COMPOSE_COMPARISON.md)** - Configuration alignment with docker-compose.yaml
- **[POD_STATUS_SUMMARY.md](./POD_STATUS_SUMMARY.md)** - Current pod status and health
- **[HOW_TO_GET_AZURE_BLOB_KEY.md](./HOW_TO_GET_AZURE_BLOB_KEY.md)** - Azure Storage account key retrieval
- **[DOCUMENTATION_INDEX.md](./DOCUMENTATION_INDEX.md)** - Complete documentation index
- **[CHANGELOG.md](./CHANGELOG.md)** - Deployment changes and updates

## Architecture

```
Internet
   ↓
nginx-ingress LoadBalancer (52.154.66.82)
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
curl -I https://dify-dev.tichealth.com.au

# Check all pods
kubectl get pods -n dify
```

## Support

For issues or questions:
1. Check the relevant guide in this directory
2. Review Kubernetes resources: `kubectl get all -n dify`
3. Check logs: `kubectl logs -n dify -l app.kubernetes.io/name=dify`
