#!/bin/bash
# Fix NSG rules to allow LoadBalancer traffic on ports 80 and 443

set -e

echo "=== Fixing NSG Rules for LoadBalancer ==="
echo ""

# Get resource group and cluster name from Terraform
RESOURCE_GROUP=$(cd "$(dirname "$0")" && terraform output -raw resource_group_name 2>/dev/null || echo "")
CLUSTER_NAME=$(cd "$(dirname "$0")" && terraform output -raw aks_cluster_name 2>/dev/null || echo "")

if [ -z "$RESOURCE_GROUP" ] || [ -z "$CLUSTER_NAME" ]; then
  echo "Error: Could not get resource group or cluster name from Terraform"
  echo "Please set these manually:"
  echo "  export RESOURCE_GROUP='your-rg-name'"
  echo "  export CLUSTER_NAME='your-cluster-name'"
  exit 1
fi

echo "Resource Group: $RESOURCE_GROUP"
echo "Cluster Name: $CLUSTER_NAME"
echo ""

# Get the node resource group (where NSG is located)
NODE_RG=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query nodeResourceGroup -o tsv)
echo "Node Resource Group: $NODE_RG"

# Find the NSG (usually the first one in the node resource group)
NSG_NAME=$(az network nsg list --resource-group "$NODE_RG" --query "[0].name" -o tsv)

if [ -z "$NSG_NAME" ]; then
  echo "Error: Could not find NSG in node resource group"
  exit 1
fi

echo "NSG Name: $NSG_NAME"
echo ""

# Function to create or update NSG rule
create_or_update_rule() {
  local name=$1
  local priority=$2
  local port=$3
  
  echo "Processing rule: $name (port $port)..."
  
  # Try to create, if exists, update
  az network nsg rule create \
    --resource-group "$NODE_RG" \
    --nsg-name "$NSG_NAME" \
    --name "$name" \
    --priority "$priority" \
    --protocol Tcp \
    --destination-port-ranges "$port" \
    --access Allow \
    --direction Inbound \
    --source-address-prefixes Internet \
    --output none 2>/dev/null || \
  az network nsg rule update \
    --resource-group "$NODE_RG" \
    --nsg-name "$NSG_NAME" \
    --name "$name" \
    --protocol Tcp \
    --destination-port-ranges "$port" \
    --access Allow \
    --direction Inbound \
    --source-address-prefixes Internet \
    --output none
  
  echo "  ✓ Rule $name configured"
}

# Resolve nodePorts for ingress-nginx (for Standard LB backend)
HTTP_NODEPORT=""
HTTPS_NODEPORT=""
if command -v kubectl &> /dev/null; then
  HTTP_NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "")
  HTTPS_NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null || echo "")
fi

# Resolve nodePorts for Dify LoadBalancer service (if using direct LB)
DIFY_HTTP_NODEPORT=""
if command -v kubectl &> /dev/null; then
  DIFY_HTTP_NODEPORT=$(kubectl get svc -n dify dify -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null || echo "")
fi

# Add HTTP rule (port 80)
create_or_update_rule "allow-http" 1000 80

# Add HTTPS rule (port 443)
create_or_update_rule "allow-https" 1001 443

# Add NodePort rules (required for Standard LoadBalancer backend)
if [ -n "$HTTP_NODEPORT" ]; then
  create_or_update_rule "allow-http-nodeport" 1010 "$HTTP_NODEPORT"
else
  echo "Warning: Could not determine HTTP nodePort for ingress-nginx"
fi

if [ -n "$HTTPS_NODEPORT" ]; then
  create_or_update_rule "allow-https-nodeport" 1011 "$HTTPS_NODEPORT"
else
  echo "Warning: Could not determine HTTPS nodePort for ingress-nginx"
fi

# Add Dify nodePort rule (direct LoadBalancer service)
if [ -n "$DIFY_HTTP_NODEPORT" ]; then
  create_or_update_rule "allow-dify-nodeport" 1012 "$DIFY_HTTP_NODEPORT"
else
  echo "Warning: Could not determine Dify nodePort (service may not be LoadBalancer)"
fi

echo ""
echo "=== NSG Rules Updated ==="
echo ""
echo "Rules added:"
echo "  - allow-http: Allow HTTP (port 80) from Internet"
echo "  - allow-https: Allow HTTPS (port 443) from Internet"
echo "  - allow-http-nodeport: Allow HTTP nodePort from Internet"
echo "  - allow-https-nodeport: Allow HTTPS nodePort from Internet"
echo "  - allow-dify-nodeport: Allow Dify HTTP nodePort from Internet"
echo ""
LB_IP=""
if command -v kubectl &> /dev/null; then
  LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
fi
echo "Wait 1-2 minutes for rules to propagate, then test:"
if [ -n "$LB_IP" ]; then
  echo "  curl -I http://$LB_IP -H 'Host: dify-dev.tichealth.com.au'"
else
  echo "  kubectl get svc -n ingress-nginx ingress-nginx-controller"
fi
echo "  curl -I https://dify-dev.tichealth.com.au"
echo ""
