#!/bin/bash
# Troubleshoot PostgreSQL connectivity from AKS pods

set -e

echo "=== PostgreSQL Connectivity Troubleshooting ==="
echo ""

# Get PostgreSQL FQDN
POSTGRES_FQDN=$(terraform output -raw postgresql_fqdn 2>/dev/null || echo "")
if [ -z "$POSTGRES_FQDN" ] || [ "$POSTGRES_FQDN" == "N/A" ]; then
    echo "ERROR: Could not get PostgreSQL FQDN from Terraform"
    exit 1
fi

echo "PostgreSQL FQDN: $POSTGRES_FQDN"
echo ""

# Check if it's a private FQDN
if [[ "$POSTGRES_FQDN" == *"privatelink"* ]]; then
    echo "✓ Using private FQDN (privatelink)"
else
    echo "⚠ Using public FQDN (not privatelink)"
fi
echo ""

# Check VNet peering status
echo "=== Checking VNet Peering ==="
RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
VNET_NAME=$(terraform output -raw vnet_id 2>/dev/null | xargs basename 2>/dev/null || echo "")

if [ -n "$RG_NAME" ] && [ -n "$VNET_NAME" ]; then
    echo "Resource Group: $RG_NAME"
    echo "PostgreSQL VNet: $VNET_NAME"
    echo ""
    echo "VNet Peerings:"
    az network vnet peering list \
        --resource-group "$RG_NAME" \
        --vnet-name "$VNET_NAME" \
        --output table 2>/dev/null || echo "  Could not list peerings"
    echo ""
else
    echo "⚠ Could not get VNet information"
fi

# Check Private DNS Zone links
echo "=== Checking Private DNS Zone Links ==="
DNS_ZONE_NAME="privatelink.postgres.database.azure.com"
if [ -n "$RG_NAME" ]; then
    echo "DNS Zone: $DNS_ZONE_NAME"
    echo "Links:"
    az network private-dns link vnet list \
        --resource-group "$RG_NAME" \
        --zone-name "$DNS_ZONE_NAME" \
        --output table 2>/dev/null || echo "  Could not list DNS links"
    echo ""
fi

# Test DNS resolution from a pod
echo "=== Testing DNS Resolution from AKS Pod ==="
echo "Creating test pod..."
kubectl run postgres-dns-test \
    --image=busybox:1.36 \
    --rm -i --restart=Never -- \
    nslookup "$POSTGRES_FQDN" 2>&1 || echo "DNS test failed"
echo ""

# Test PostgreSQL connectivity from a pod
echo "=== Testing PostgreSQL Connectivity ==="
echo "Creating test pod..."
PGPASSWORD=$(terraform output -raw postgresql_password 2>/dev/null || echo "difyai123456")
PGUSER=$(terraform output -raw postgresql_username 2>/dev/null || echo "difyadmin")

kubectl run postgres-conn-test \
    --image=postgres:16 \
    --rm -i --restart=Never --env="PGPASSWORD=$PGPASSWORD" -- \
    psql -h "$POSTGRES_FQDN" -U "$PGUSER" -d postgres -c "SELECT version();" 2>&1 || echo "Connection test failed"
echo ""

# Check current Dify pods
echo "=== Current Dify Pod Status ==="
kubectl get pods -n dify -o wide
echo ""

# Check pod logs for connection errors
echo "=== Checking API Pod Logs (last 20 lines) ==="
API_POD=$(kubectl get pods -n dify -l app.kubernetes.io/component=api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$API_POD" ]; then
    echo "API Pod: $API_POD"
    kubectl logs -n dify "$API_POD" --tail=20 | grep -i -E "(postgres|database|connection|error)" || echo "  No relevant logs found"
else
    echo "  No API pod found"
fi
echo ""

echo "=== Troubleshooting Complete ==="
echo ""
echo "If DNS resolution fails:"
echo "  1. Check VNet peering is established (both directions)"
echo "  2. Check Private DNS Zone link exists for AKS VNet"
echo "  3. Wait 2-5 minutes for DNS propagation"
echo ""
echo "If connection fails:"
echo "  1. Verify PostgreSQL is running: az postgres flexible-server show --name <server-name>"
echo "  2. Check NSG rules allow traffic on port 5432"
echo "  3. Verify VNet peering allows forwarded traffic"
