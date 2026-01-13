# Azure Kubernetes Service (AKS) Cost Estimation

## Current Infrastructure

Based on `terraform.tfvars` and deployed resources:

### Compute Resources
- **AKS Cluster**: 1 node
- **VM Size**: Standard_D4s_v5 (4 vCPU, 16 GB RAM)
- **Region**: East US
- **AKS Tier**: Free (default) - no control plane charges

### Network Resources
- **nginx-ingress LoadBalancer (Standard SKU)**: 1 instance
  - External IP: 52.154.66.82 (for HTTPS)
- **Dify Service**: ClusterIP (no LoadBalancer cost)

### Storage Resources
- **PostgreSQL Primary**: 10 Gi (Premium SSD - default)
- **PostgreSQL Read**: 8 Gi (Premium SSD - default)  
- **Redis**: 8 Gi (Premium SSD - default)
- **API Persistence (Azure Files)**: 5 Gi
- **Plugin Daemon (Azure Files)**: 20 Gi
- **Total**: ~51 Gi

## Monthly Cost Breakdown (East US Region)

### 1. AKS Control Plane
- **Tier**: Free (no charge for control plane)
- **Cost**: **$0/month**

### 2. Virtual Machines (Compute Nodes)
- **VM Size**: Standard_D4s_v5 (4 vCPU, 16 GB RAM)
- **Quantity**: 1 node
- **Hourly Rate**: ~$0.036/hour (East US)
- **Monthly Cost**: $0.036 × 730 hours = **~$26.28/month**

### 3. LoadBalancer (Standard SKU) - nginx-ingress
- **Base Cost**: ~$0.025/hour = **~$18.25/month**
- **Data Processing**: Additional charges based on outbound data transfer
- **Estimated Total**: **~$18-25/month** (depending on traffic)
- **Note**: Dify service uses ClusterIP (no LoadBalancer cost)

### 4. Storage Costs

#### Managed Disks (Premium SSD - P10/P15)
- PostgreSQL Primary (10 Gi): ~$1.70/month
- PostgreSQL Read (8 Gi): ~$1.70/month
- Redis (8 Gi): ~$1.70/month
- **Managed Disks Subtotal**: **~$5.10/month**

#### Azure Files (Standard)
- API Persistence (5 Gi): ~$0.06/month
- Plugin Daemon (20 Gi): ~$0.24/month
- **Azure Files Subtotal**: **~$0.30/month**

#### Storage Total: **~$5.40/month**

### 5. Additional Costs
- **Egress Data Transfer**: Variable (first 5GB free per month, then ~$0.05/GB)
- **Estimated**: **~$5-10/month** (depending on usage)

## Total Monthly Cost Estimate

| Component | Monthly Cost |
|-----------|--------------|
| AKS Control Plane (Free) | $0.00 |
| Compute Nodes (1 × D4s_v5) | $26.28 |
| LoadBalancer (nginx-ingress for HTTPS) | $20.00 |
| Storage (Managed Disks + Files) | $5.40 |
| Data Transfer (Egress) | $7.50 |
| **Total Estimated** | **~$59-65/month** |

**Note**: HTTPS adds ~$18-25/month for nginx-ingress LoadBalancer. The Dify service uses ClusterIP (no additional LoadBalancer cost).

## Annual Cost Estimate
- **Estimated Annual Cost**: **~$708-780/year**

## Cost Optimization Recommendations

### 1. Use Reserved Instances (1-year commitment)
- **Savings**: ~30-40% on compute
- **New Compute Cost**: ~$18/month (saves ~$8/month)
- **Annual Savings**: ~$96

### 2. Use Spot Instances for Non-Production
- **Savings**: 60-90% on compute (if workloads can tolerate interruptions)
- **New Compute Cost**: ~$5-10/month (saves ~$16-21/month)
- **Note**: Not recommended for production workloads

### 3. Optimize Storage
- Consider using Standard SSD instead of Premium SSD for non-critical data
- **Potential Savings**: ~$2-3/month

### 4. Use Azure Kubernetes Service Free Tier
- Already using this - no changes needed
- If you need SLA, Standard tier adds ~$72/month

### 5. Scale Down During Off-Hours
- Use Azure Automation or Kubernetes Horizontal Pod Autoscaler
- **Potential Savings**: 30-50% if scaling to zero during off-hours

## Scaling Scenarios

### Current Setup (1 node, HTTPS enabled)
- **Monthly Cost**: ~$77-90
  - Base infrastructure: ~$59-65
  - HTTPS (nginx-ingress LoadBalancer): ~$18-25

### Production Setup (3 nodes, Standard tier)
- Compute: 3 × $26.28 = $78.84
- Control Plane: $72.00 (Standard tier)
- LoadBalancer: $20.00
- Storage: $5.40
- Data Transfer: $10.00
- **Total**: **~$186/month**

### High Availability Setup (3 nodes, Premium tier)
- Compute: 3 × $26.28 = $78.84
- Control Plane: $108.00 (Premium tier)
- LoadBalancer: $20.00
- Storage: $10.00 (redundant storage)
- Data Transfer: $15.00
- **Total**: **~$231/month**

## Notes

- Prices are approximate and based on East US region pricing as of 2024
- Actual costs may vary based on:
  - Actual usage patterns
  - Data transfer volumes
  - Storage IOPS requirements
  - Network bandwidth usage
- Azure pricing can vary by region
- Check [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for exact current pricing
- Consider Azure Cost Management for detailed billing analysis

## Cost Monitoring

To monitor actual costs:
1. Azure Cost Management + Billing dashboard
2. Set up budget alerts
3. Use Azure Advisor for cost optimization recommendations
4. Review monthly billing statements

## References

- [Azure Kubernetes Service Pricing](https://azure.microsoft.com/en-us/pricing/details/kubernetes-service/)
- [Azure Virtual Machines Pricing](https://azure.microsoft.com/en-us/pricing/details/virtual-machines/series/)
- [Azure Load Balancer Pricing](https://azure.microsoft.com/en-us/pricing/details/load-balancer/)
- [Azure Storage Pricing](https://azure.microsoft.com/en-us/pricing/details/storage/)
