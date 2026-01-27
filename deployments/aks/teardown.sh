#!/bin/bash
# Teardown script for Dify AKS deployment
# This will uninstall Helm releases and destroy Terraform infrastructure

set -e

# Parse arguments
AUTO_APPROVE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo "=== Teardown Dify Deployment ==="
echo ""

# Uninstall Helm releases
echo "1. Uninstalling Helm releases..."
helm uninstall dify -n dify 2>/dev/null && echo "   ✓ Dify uninstalled" || echo "   ⚠ Dify not found (already removed?)"
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null && echo "   ✓ nginx-ingress uninstalled" || echo "   ⚠ nginx-ingress not found"
helm uninstall cert-manager -n cert-manager 2>/dev/null && echo "   ✓ cert-manager uninstalled" || echo "   ⚠ cert-manager not found"

echo ""
echo "2. Destroying Terraform infrastructure..."
echo "   This will destroy:"
echo "   - AKS cluster"
echo "   - Azure PostgreSQL (if enabled)"
echo "   - All associated resources"
echo ""
if [ "$AUTO_APPROVE" != "true" ]; then
    read -p "   Continue with destroy? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "   Destroy cancelled."
        exit 0
    fi
fi

terraform destroy -auto-approve

echo ""
echo "=== Teardown Complete ==="
echo ""
echo "To redeploy, run:"
echo "  ./deploy.sh"
echo ""
echo "  (deploy.sh runs terraform apply, Helm + ingress + cert-manager, Dify, and fix-nsg-rules.sh)"
echo ""
