#!/bin/bash
# Verify NSG rules and test connection

set -e

echo "=== Verifying NSG Rules ==="
echo ""

RESOURCE_GROUP=$(cd "$(dirname "$0")" && terraform output -raw resource_group_name 2>/dev/null || echo "")
CLUSTER_NAME=$(cd "$(dirname "$0")" && terraform output -raw aks_cluster_name 2>/dev/null || echo "")

if [ -z "$RESOURCE_GROUP" ] || [ -z "$CLUSTER_NAME" ]; then
  echo "Error: Could not get resource group or cluster name from Terraform"
  exit 1
fi

NODE_RG=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query nodeResourceGroup -o tsv)
NSG_NAME=$(az network nsg list --resource-group "$NODE_RG" --query "[0].name" -o tsv)

echo "Node Resource Group: $NODE_RG"
echo "NSG Name: $NSG_NAME"
echo ""

# List rules for ports 80 and 443
az network nsg rule list \
  --resource-group "$NODE_RG" \
  --nsg-name "$NSG_NAME" \
  --query "[?contains(destinationPortRanges, '80') || contains(destinationPortRanges, '443')].{Name:name, Port:destinationPortRanges, Access:access, Priority:priority, Source:sourceAddressPrefixes}" \
  -o table

echo ""
echo "=== Testing Connection ==="
echo "Waiting 30 seconds for NSG rules to propagate..."
sleep 30

echo ""
LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -z "$LB_IP" ]; then
  echo "Could not determine ingress LoadBalancer IP"
  exit 1
fi

echo "Testing HTTP connection (with Host header) to $LB_IP..."
curl -v --connect-timeout 15 -H "Host: dify-dev.tichealth.com.au" "http://$LB_IP" 2>&1 | head -30 || echo "Connection failed or timed out"

echo ""
echo "=== Summary ==="
echo "If connection still fails:"
echo "1. Wait 1-2 more minutes for NSG rules to fully propagate"
echo "2. Check if your local firewall is blocking the connection"
echo "3. Try accessing from a different network"
echo "4. Verify DNS is configured: nslookup dify-dev.tichealth.com.au"
