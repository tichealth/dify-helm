#!/bin/bash
# Fix DNS resolution for PostgreSQL private FQDN in AKS

set -e

echo "=== Fixing DNS Resolution for PostgreSQL ==="
echo ""

# Get resource group and DNS zone
RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
DNS_ZONE="privatelink.postgres.database.azure.com"
POSTGRES_FQDN=$(terraform output -raw postgresql_fqdn 2>/dev/null || echo "")

if [ -z "$RG_NAME" ]; then
    echo "ERROR: Could not get resource group name"
    exit 1
fi

echo "Resource Group: $RG_NAME"
echo "DNS Zone: $DNS_ZONE"
echo "PostgreSQL FQDN: $POSTGRES_FQDN"
echo ""

# Check DNS links
echo "=== Checking DNS Zone Links ==="
az network private-dns link vnet list \
    --resource-group "$RG_NAME" \
    --zone-name "$DNS_ZONE" \
    --output table

echo ""
echo "=== Testing DNS Resolution ==="
echo "Creating test pod..."
kubectl run dns-test-fix \
    --image=busybox:1.36 \
    --rm -i --restart=Never -- \
    nslookup "$POSTGRES_FQDN" 2>&1 || echo "DNS test completed"

echo ""
echo "=== Restarting CoreDNS ==="
echo "Restarting CoreDNS to pick up DNS changes..."
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s

echo ""
echo "=== Waiting for DNS Propagation ==="
echo "Waiting 30 seconds for DNS to propagate..."
sleep 30

echo ""
echo "=== Testing DNS Again ==="
kubectl run dns-test-after \
    --image=busybox:1.36 \
    --rm -i --restart=Never -- \
    nslookup "$POSTGRES_FQDN" 2>&1 || echo "DNS test completed"

echo ""
echo "=== Restarting Dify Pods ==="
echo "Restarting Dify pods to pick up DNS changes..."
kubectl rollout restart deployment/dify-api -n dify
kubectl rollout restart deployment/dify-plugin-daemon -n dify

echo ""
echo "=== Fix Complete ==="
echo "Monitor pods: kubectl get pods -n dify -w"
