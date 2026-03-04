#!/bin/bash
# Hybrid Deployment Script: Terraform + Helm for AKS
# This script orchestrates infrastructure creation with Terraform and application deployment with Helm
# Part of dify-helm repository: deployments/aks/

set -euo pipefail  # Exit on error; fail pipelines; error on unset vars

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the script directory (deployments/aks/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
TF_DIR="$SCRIPT_DIR"  # Terraform files are in the same directory as deploy.sh
HELM_REPO_NAME="dify"
HELM_CHART="dify/dify"
HELM_REPO_URL="https://borispolonsky.github.io/dify-helm"
NAMESPACE="dify"
RELEASE_NAME="dify"
# Parse arguments
AUTO_APPROVE=false
VALUES_FILE="$SCRIPT_DIR/values.yaml"
DEPLOY_MODE="all"  # Default: deploy everything

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --db)
            DEPLOY_MODE="db"
            shift
            ;;
        --app)
            DEPLOY_MODE="app"
            shift
            ;;
        --all)
            DEPLOY_MODE="all"
            shift
            ;;
        *)
            if [[ -f "$1" ]]; then
                VALUES_FILE="$1"
            fi
            shift
            ;;
    esac
done

CERT_EMAIL="${CERT_EMAIL:-vivek.narayanan@tichealth.com.au}"

on_err() {
    echo -e "${RED}✗ Deployment failed.${NC}"
    if [ -f "$TF_DIR/terraform-apply.log" ]; then
        echo ""
        echo "Last 200 lines of terraform-apply.log:"
        tail -n 200 "$TF_DIR/terraform-apply.log" || true
    fi
}
trap on_err ERR

echo -e "${GREEN}Dify AKS (Terraform + Helm)${NC}\n"

case $DEPLOY_MODE in
    db)   echo -e "${YELLOW}Mode: db only${NC}\n" ;;
    app)  echo -e "${YELLOW}Mode: app only (Helm)${NC}\n" ;;
    all)  echo -e "${YELLOW}Mode: full${NC}\n" ;;
esac

# Prerequisites
check_and_install_kubectl() {
    if command -v kubectl &> /dev/null; then
        return 0
    fi
    echo "  Installing kubectl..."
    
    if command -v curl &> /dev/null; then
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/kubectl 2>/dev/null || { mkdir -p ~/.local/bin; mv kubectl ~/.local/bin/kubectl; export PATH="$HOME/.local/bin:$PATH"; }
    elif command -v snap &> /dev/null; then
        sudo snap install kubectl --classic
    else
        echo -e "${RED}kubectl not found. Install manually.${NC}"; return 1
    fi
    command -v kubectl &> /dev/null || { export PATH="$HOME/.local/bin:$PATH"; command -v kubectl &> /dev/null || { echo -e "${RED}kubectl install failed${NC}"; return 1; }; }
    return 0
}

check_and_install_helm() {
    command -v helm &> /dev/null && return 0
    echo "  Installing helm..."
    command -v curl &> /dev/null && curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || { echo -e "${RED}helm: install manually.${NC}"; return 1; }
    export PATH="$HOME/.local/bin:$PATH"
    command -v helm &> /dev/null || { echo -e "${RED}helm install failed${NC}"; return 1; }
    return 0
}

MISSING_TOOLS=0
command -v terraform &> /dev/null || { echo -e "${RED}terraform required${NC}"; MISSING_TOOLS=1; }
command -v az &> /dev/null || { echo -e "${RED}az (Azure CLI) required${NC}"; MISSING_TOOLS=1; }

if ! check_and_install_kubectl; then
    MISSING_TOOLS=1
fi

if ! check_and_install_helm; then
    MISSING_TOOLS=1
fi

# Ensure ~/.local/bin is in PATH for this session
export PATH="$HOME/.local/bin:$PATH"

[ $MISSING_TOOLS -eq 1 ] && { echo -e "${RED}Missing prerequisites.${NC}"; exit 1; }

# Terraform
cd "$TF_DIR" || exit 1
echo -e "${YELLOW}Step 1: Terraform init${NC}"
if [ -f "backend.azurerm.tfvars" ]; then
    terraform init -reconfigure -backend-config=backend.azurerm.tfvars
else
    terraform init
fi
echo -e "${GREEN}✓ Terraform initialized${NC}\n"

# Step 2: Create/Update Infrastructure
if [ "$DEPLOY_MODE" != "app" ]; then
    if [ "$DEPLOY_MODE" == "db" ]; then
        echo -e "${YELLOW}Step 2: Creating/Updating Database infrastructure...${NC}"
        echo "This will create/update PostgreSQL, VNet, and related database resources."
        echo "AKS resources will be skipped."
    else
        echo -e "${YELLOW}Step 2: Creating/Updating infrastructure...${NC}"
        echo "This will create/update the AKS cluster, PostgreSQL, and related resources."
    fi
    
    if [ "$AUTO_APPROVE" != "true" ]; then
        read -p "Continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled."
            exit 1
        fi
    fi

    if [ "$DEPLOY_MODE" == "db" ]; then
        # Deploy only database-related resources
        echo "Applying Terraform for database resources only..."
        terraform apply -auto-approve \
            -target=azurerm_virtual_network.postgres \
            -target=azurerm_subnet.postgres \
            -target=azurerm_subnet.management \
            -target=azurerm_private_dns_zone.postgres \
            -target=azurerm_private_dns_zone_virtual_network_link.postgres \
            -target=azurerm_private_dns_zone_virtual_network_link.aks \
            -target=azurerm_network_security_group.management \
            -target=azurerm_network_security_rule.management_ssh \
            -target=azurerm_network_security_rule.management_rdp \
            -target=azurerm_network_security_rule.management_to_postgres \
            -target=azurerm_subnet_network_security_group_association.management \
            -target=azurerm_postgresql_flexible_server.pg \
            -target=azurerm_postgresql_flexible_server_database.db \
            -target=azurerm_postgresql_flexible_server_database.plugin_db \
            -target=azurerm_postgresql_flexible_server_configuration.require_secure_transport \
            -target=azurerm_postgresql_flexible_server_configuration.azure_extensions \
            -target=null_resource.create_extensions_dify \
            -target=null_resource.create_extensions_plugin \
            -target=azurerm_virtual_network_peering.postgres_to_aks \
            -target=azurerm_virtual_network_peering.aks_to_postgres \
            2>&1 | tee terraform-apply.log
    else
        # Deploy all infrastructure
        terraform apply -auto-approve 2>&1 | tee terraform-apply.log
    fi

    echo -e "${GREEN}✓ Infrastructure created/updated${NC}\n"
else
    echo -e "${YELLOW}Step 2: Skipping infrastructure deployment (--app mode)${NC}"
    echo "Assuming AKS and PostgreSQL already exist."
    echo ""
fi

# Step 3: Get AKS credentials (skip if --db only)
if [ "$DEPLOY_MODE" != "db" ]; then
    echo -e "${YELLOW}Step 3: Getting AKS credentials...${NC}"
    CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
    RG_NAME=$(terraform output -raw resource_group_name)

    if [ -z "$CLUSTER_NAME" ] || [ -z "$RG_NAME" ]; then
        echo -e "${RED}Error: Could not get cluster name or resource group from Terraform outputs${NC}"
        echo "If using --app mode, ensure Terraform state exists and AKS is already deployed."
        exit 1
    fi

    echo "Cluster: $CLUSTER_NAME"
    echo "Resource Group: $RG_NAME"

    az aks get-credentials \
        --resource-group "$RG_NAME" \
        --name "$CLUSTER_NAME" \
        --overwrite-existing

    echo -e "${GREEN}✓ Credentials retrieved${NC}\n"
else
    echo -e "${YELLOW}Step 3: Skipping AKS credentials (--db mode)${NC}\n"
    # Set dummy values to prevent errors in later steps that check these
    CLUSTER_NAME=""
    RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
fi

# Wait a moment for credentials to be written and API server to be ready (skip if --db only)
if [ "$DEPLOY_MODE" != "db" ]; then
    echo "Waiting for API server to be ready (cluster was just created)..."
    echo "This can take 2-5 minutes for a newly created cluster..."
    sleep 30

    # Step 4: Verify cluster connectivity (with retries)
    echo -e "${YELLOW}Step 4: Verifying cluster connectivity...${NC}"
MAX_RETRIES=60  # Increased to 10 minutes total
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if kubectl cluster-info &>/dev/null 2>&1; then
        echo -e "${GREEN}✓ Cluster is reachable (after $((RETRY_COUNT * 10 + 30))s)${NC}\n"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $((RETRY_COUNT % 6)) -eq 0 ]; then
        # Show progress every minute
        echo "  Still waiting... ($((RETRY_COUNT * 10 / 60)) minutes elapsed)"
    fi
    sleep 10
done

    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo -e "${RED}Error: Cannot connect to cluster after 10 minutes. Run: az aks get-credentials -g $RG_NAME -n $CLUSTER_NAME --overwrite-existing${NC}"
        exit 1
    fi

    # Wait for at least one node Ready so Helm can schedule pods (CI: node pool may still be coming up)
    echo -e "${YELLOW}Waiting for node(s) to be Ready...${NC}"
    NODE_WAIT=0
    while [ $NODE_WAIT -lt 600 ]; do
        READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
        if [ "${READY:-0}" -ge 1 ]; then
            echo -e "${GREEN}✓ Node(s) Ready${NC}\n"
            break
        fi
        echo "  Waiting for nodes... (${NODE_WAIT}s)"
        sleep 15
        NODE_WAIT=$((NODE_WAIT + 15))
    done
    if [ "${READY:-0}" -lt 1 ]; then
        echo -e "${RED}Error: No Ready nodes after 10 min. Run: kubectl get nodes${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Step 4: Skipping cluster connectivity check (--db mode)${NC}\n"
fi

# Step 5: Add Helm repository (skip if --db only)
if [ "$DEPLOY_MODE" != "db" ]; then
    echo -e "${YELLOW}Step 5: Adding Helm repository...${NC}"
    if helm repo list | grep -q "^${HELM_REPO_NAME}"; then
        echo "  Repository already exists, updating..."
        helm repo update "$HELM_REPO_NAME"
    else
        echo "  Adding repository: $HELM_REPO_URL"
        helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
        helm repo update
    fi

    echo -e "${GREEN}✓ Helm repository ready${NC}\n"

    # Step 6: Create namespace if it doesn't exist
    echo -e "${YELLOW}Step 6: Ensuring namespace exists...${NC}"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}✓ Namespace ready${NC}\n"

    # Step 7: Install nginx-ingress controller
    echo -e "${YELLOW}Step 7: Installing nginx-ingress...${NC}"
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx \
      --create-namespace \
      --set controller.service.type=LoadBalancer \
      --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
      --wait --timeout 5m
    echo -e "${GREEN}✓ nginx-ingress installed${NC}\n"

    # Step 8: Install cert-manager
    echo -e "${YELLOW}Step 8: Installing cert-manager...${NC}"
    helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml
    helm upgrade --install cert-manager jetstack/cert-manager \
      --namespace cert-manager \
      --create-namespace \
      --version v1.13.3 \
      --wait --timeout 5m
    echo -e "${GREEN}✓ cert-manager installed${NC}\n"

    # Step 8b: CoreDNS patch so cert-manager can resolve public domains (e.g. dify-prod.tichealth.com.au)
    echo -e "${YELLOW}Step 8b: Applying CoreDNS patch (public DNS for cert-manager)...${NC}"
    if [ -f "$SCRIPT_DIR/coredns-patch.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/coredns-patch.yaml"
        kubectl -n kube-system rollout restart deployment coredns
        echo "Waiting for CoreDNS to be ready..."
        kubectl -n kube-system rollout status deployment coredns --timeout=60s
        echo -e "${GREEN}✓ CoreDNS patch applied${NC}\n"
    else
        echo -e "${YELLOW}⚠ coredns-patch.yaml not found, skipping (cert-manager may fail to resolve your domain)${NC}\n"
    fi

    # Step 9: Create ClusterIssuer (Let's Encrypt)
    echo -e "${YELLOW}Step 9: Creating ClusterIssuer...${NC}"
    kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${CERT_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${CERT_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
    echo -e "${GREEN}✓ ClusterIssuer applied${NC}\n"

    # Step 10: Deploy Dify with Helm
    echo -e "${YELLOW}Step 10: Deploying Dify...${NC}"
    if [ "$AUTO_APPROVE" != "true" ]; then
        read -p "Continue? (y/n) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 1; }
    fi

    VALUES_ARG=""
    [[ -f "$VALUES_FILE" ]] && VALUES_ARG="-f $VALUES_FILE"

    # Postgres FQDN + secrets from TF_VAR_* or terraform.tfvars
    SET_POSTGRES=""
    POSTGRES_FQDN=$(cd "$TF_DIR" && terraform output -raw postgresql_fqdn 2>/dev/null || true)
    if [[ -n "$POSTGRES_FQDN" && "$POSTGRES_FQDN" != *"N/A"* ]]; then
        SET_POSTGRES="--set externalPostgres.address=$POSTGRES_FQDN"
    fi

    # Secrets: from TF_VAR_* (CI/local) or terraform.tfvars — same source as Terraform; no secrets in values.yaml
    get_secret() {
        local env_var="$1"
        local tfvars_key="$2"
        local val="${!env_var:-}"
        if [[ -z "$val" && -f "$TF_DIR/terraform.tfvars" ]]; then
            val=$(grep -E "^${tfvars_key}\s*=" "$TF_DIR/terraform.tfvars" 2>/dev/null | sed -n 's/^[^=]*=\s*"\(.*\)"\s*$/\1/p' | sed 's/\\"/"/g')
        fi
        printf '%s' "$val"
    }
    SECRETS_DIR=$(mktemp -d)
    trap 'rm -rf "$SECRETS_DIR"' EXIT

    POSTGRESQL_PASSWORD=$(get_secret TF_VAR_postgresql_password postgresql_password)
    SET_POSTGRES_PASSWORD=""
    if [[ -n "$POSTGRESQL_PASSWORD" ]]; then
        printf '%s' "$POSTGRESQL_PASSWORD" > "$SECRETS_DIR/pg_pass"
        SET_POSTGRES_PASSWORD="--set-file externalPostgres.password=$SECRETS_DIR/pg_pass"
    fi
    DIFY_SECRET_KEY=$(get_secret TF_VAR_dify_secret_key dify_secret_key)
    SET_DIFY_SECRET=""
    if [[ -n "$DIFY_SECRET_KEY" ]]; then
        printf '%s' "$DIFY_SECRET_KEY" > "$SECRETS_DIR/dify_secret"
        SET_DIFY_SECRET="--set-file global.appSecretKey=$SECRETS_DIR/dify_secret"
    fi
    REDIS_PASSWORD=$(get_secret TF_VAR_redis_password redis_password)
    SET_REDIS_PASSWORD=""
    if [[ -n "$REDIS_PASSWORD" ]]; then
        printf '%s' "$REDIS_PASSWORD" > "$SECRETS_DIR/redis_pass"
        SET_REDIS_PASSWORD="--set-file redis.auth.password=$SECRETS_DIR/redis_pass"
    fi
    QDRANT_API_KEY=$(get_secret TF_VAR_qdrant_api_key qdrant_api_key)
    SET_QDRANT_KEY=""
    if [[ -n "$QDRANT_API_KEY" ]]; then
        printf '%s' "$QDRANT_API_KEY" > "$SECRETS_DIR/qdrant_key"
        SET_QDRANT_KEY="--set-file externalQdrant.apiKey=$SECRETS_DIR/qdrant_key"
    fi
    if [[ -n "$SET_POSTGRES_PASSWORD$SET_DIFY_SECRET$SET_REDIS_PASSWORD$SET_QDRANT_KEY" ]]; then
        echo "Secrets from TF_VAR_* or terraform.tfvars"
    fi

    # Ingress host: prod (lite or full) always uses dify-prod; dev/test use dify-dev / dify-test
    PROJECT_NAME=$(grep -E '^project_name\s*=' "$TF_DIR/terraform.tfvars" 2>/dev/null | sed -n 's/.*=\s*"\([^"]*\)".*/\1/p' || true)
    if [[ "$PROJECT_NAME" == *"prod"* ]]; then
        INGRESS_HOST="dify-prod.tichealth.com.au"
    elif [[ "$PROJECT_NAME" == *"dev"* ]]; then
        INGRESS_HOST="dify-dev.tichealth.com.au"
    elif [[ "$PROJECT_NAME" == *"test"* ]]; then
        INGRESS_HOST="dify-test.tichealth.com.au"
    else
        INGRESS_HOST="${PROJECT_NAME}.tichealth.com.au"
    fi
    BASE_URL="https://$INGRESS_HOST"
    SET_INGRESS="--set ingress.hosts[0].host=$INGRESS_HOST --set ingress.tls[0].hosts[0]=$INGRESS_HOST"
    # Force Dify frontend/API to use HTTPS URLs (avoids "not secure" / mixed content)
    SET_DOMAINS="--set global.consoleWebDomain=$BASE_URL --set global.consoleApiDomain=$BASE_URL --set global.serviceApiDomain=$BASE_URL --set global.appApiDomain=$BASE_URL --set global.appWebDomain=$BASE_URL --set global.filesDomain=$BASE_URL --set global.triggerDomain=$BASE_URL"

    helm upgrade --install "$RELEASE_NAME" "$HELM_CHART" \
        --namespace "$NAMESPACE" \
        --create-namespace \
        --timeout 45m \
        --atomic \
        --wait \
        $VALUES_ARG $SET_POSTGRES $SET_POSTGRES_PASSWORD $SET_DIFY_SECRET $SET_REDIS_PASSWORD $SET_QDRANT_KEY $SET_INGRESS $SET_DOMAINS

    echo -e "${GREEN}✓ Dify deployed${NC}\n"

    kubectl wait --for=condition=available --timeout=300s deployment/"$RELEASE_NAME"-api -n "$NAMESPACE" || true
    kubectl wait --for=condition=available --timeout=300s deployment/"$RELEASE_NAME"-web -n "$NAMESPACE" || true

    [ -f "$SCRIPT_DIR/fix-nsg-rules.sh" ] && { chmod +x "$SCRIPT_DIR/fix-nsg-rules.sh"; "$SCRIPT_DIR/fix-nsg-rules.sh" || true; }

    echo -e "\n${GREEN}Deployment complete.${NC}"
    kubectl get pods -n "$NAMESPACE"
    echo ""

    # LoadBalancer IP for DNS
    LB_IP=""
    MAX_WAIT=120
    WAIT_COUNT=0
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        [[ -n "$LB_IP" && "$LB_IP" != "<pending>" ]] && break
        sleep 5
        WAIT_COUNT=$((WAIT_COUNT + 5))
    done

    if [[ -n "$LB_IP" && "$LB_IP" != "<pending>" ]]; then
        echo -e "${GREEN}DNS: $INGRESS_HOST -> $LB_IP${NC}"
        echo "  Add A record, then https://$INGRESS_HOST (cert-manager will issue TLS)"
    else
        echo -e "${YELLOW}LoadBalancer IP pending. Check: kubectl get svc -n ingress-nginx ingress-nginx-controller${NC}"
    fi
else
    # --db mode: Show database information
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Database Deployment Complete!${NC}"
    POSTGRES_FQDN=$(terraform output -raw postgresql_fqdn 2>/dev/null || echo "N/A")
    echo -e "${GREEN}DB complete.${NC} PostgreSQL FQDN: $POSTGRES_FQDN"
    terraform output -raw vnet_id &>/dev/null && echo "VNet: $(terraform output -raw vnet_id)"
    echo "Next: ./deploy.sh --app --auto-approve"
fi
