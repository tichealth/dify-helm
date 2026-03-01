#!/bin/bash
# Fix DNS and retry deployment

set -e

echo "=== Fixing DNS and Retrying Deployment ==="
echo ""

# Step 1: Clean up stuck Helm release if needed
echo "Step 1: Checking Helm release status..."
if helm status dify -n dify &>/dev/null; then
    RELEASE_STATUS=$(helm status dify -n dify -o json | jq -r '.info.status' 2>/dev/null || echo "unknown")
    if [[ "$RELEASE_STATUS" == "pending-install" ]] || [[ "$RELEASE_STATUS" == "pending-upgrade" ]]; then
        echo "  Found stuck Helm release, cleaning up..."
        helm uninstall dify -n dify || true
        sleep 5
    fi
fi

# Step 2: Fix DNS
echo ""
echo "Step 2: Fixing DNS configuration..."
terraform refresh -no-color

echo "  Reapplying DNS link and peering..."
terraform apply -target=data.azurerm_resources.aks_vnets[0] \
    -target=azurerm_private_dns_zone_virtual_network_link.aks[0] \
    -target=azurerm_virtual_network_peering.postgres_to_aks[0] \
    -target=azurerm_virtual_network_peering.aks_to_postgres[0] \
    -auto-approve -no-color

# Step 3: Restart CoreDNS
echo ""
echo "Step 3: Restarting CoreDNS..."
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s

# Step 4: Wait for DNS
echo ""
echo "Step 4: Waiting for DNS propagation (30 seconds)..."
sleep 30

# Step 5: Test DNS
echo ""
echo "Step 5: Testing DNS resolution..."
POSTGRES_FQDN=$(terraform output -raw postgresql_fqdn 2>/dev/null || echo "")
if [ -n "$POSTGRES_FQDN" ] && [ "$POSTGRES_FQDN" != "N/A" ]; then
    echo "  Testing: $POSTGRES_FQDN"
    if kubectl run dns-test-$$ --image=busybox:1.36 --rm -i --restart=Never -- \
        nslookup "$POSTGRES_FQDN" 2>&1 | grep -q "NXDOMAIN"; then
        echo "  ⚠️  DNS still not resolving. Waiting 60 more seconds..."
        sleep 60
    else
        echo "  ✓ DNS is resolving"
    fi
else
    echo "  ⚠️  Could not get PostgreSQL FQDN"
fi

# Step 6: Retry deployment
echo ""
echo "Step 6: Retrying deployment with --app mode..."
echo "  (Infrastructure is already deployed, only deploying Helm charts)"
echo ""
./deploy.sh --app --auto-approve

echo ""
echo "=== Done ==="
