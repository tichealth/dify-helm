#!/bin/bash
# Hybrid Deployment Script: Terraform + Helm for AKS
# This script orchestrates infrastructure creation with Terraform and application deployment with Helm
# Part of dify-helm repository: deployments/aks/

set -e  # Exit on error

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
VALUES_FILE="${1:-$SCRIPT_DIR/values.yaml}"  # Allow passing values file as argument

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Dify Hybrid Deployment (Terraform + Helm)${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 0: Check prerequisites
echo -e "${YELLOW}Step 0: Checking prerequisites...${NC}"

check_and_install_kubectl() {
    if command -v kubectl &> /dev/null; then
        echo "  ✓ kubectl is installed ($(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo 'unknown'))"
        return 0
    fi
    
    echo "  kubectl not found. Installing..."
    
    # Try curl method (works best on WSL/Ubuntu)
    if command -v curl &> /dev/null; then
        echo "  Installing kubectl via curl..."
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/kubectl || {
            echo "  Attempting to install to ~/.local/bin (no sudo required)..."
            mkdir -p ~/.local/bin
            mv kubectl ~/.local/bin/kubectl
            export PATH="$HOME/.local/bin:$PATH"
        }
    # Try snap as fallback (requires --classic flag)
    elif command -v snap &> /dev/null; then
        echo "  Installing kubectl via snap (requires --classic flag)..."
        sudo snap install kubectl --classic
    else
        echo -e "${RED}  Error: Cannot install kubectl automatically. Please install it manually:${NC}"
        echo "    curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
        echo "    chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
        echo "    or: sudo snap install kubectl --classic"
        return 1
    fi
    
    if command -v kubectl &> /dev/null; then
        echo "  ✓ kubectl installed successfully"
        return 0
    else
        echo -e "${YELLOW}  Warning: kubectl may not be in PATH. Adding ~/.local/bin to PATH...${NC}"
        export PATH="$HOME/.local/bin:$PATH"
        if command -v kubectl &> /dev/null; then
            echo "  ✓ kubectl found in ~/.local/bin"
            return 0
        else
            echo -e "${RED}  Error: kubectl installation failed or not found in PATH${NC}"
            return 1
        fi
    fi
}

check_and_install_helm() {
    if command -v helm &> /dev/null; then
        echo "  ✓ helm is installed ($(helm version --short 2>/dev/null || echo 'unknown'))"
        return 0
    fi
    
    echo "  helm not found. Installing..."
    
    # Use official Helm install script (works best)
    if command -v curl &> /dev/null; then
        echo "  Installing helm via official install script..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    else
        echo -e "${RED}  Error: Cannot install helm automatically. Please install it manually:${NC}"
        echo "    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
        return 1
    fi
    
    if command -v helm &> /dev/null; then
        echo "  ✓ helm installed successfully"
        return 0
    else
        echo -e "${YELLOW}  Warning: helm may not be in PATH. Adding ~/.local/bin to PATH...${NC}"
        export PATH="$HOME/.local/bin:$PATH"
        if command -v helm &> /dev/null; then
            echo "  ✓ helm found in ~/.local/bin"
            return 0
        else
            echo -e "${RED}  Error: helm installation failed or not found in PATH${NC}"
            return 1
        fi
    fi
}

# Check required tools
MISSING_TOOLS=0

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}  ✗ terraform is not installed${NC}"
    MISSING_TOOLS=1
else
    echo "  ✓ terraform is installed"
fi

if ! command -v az &> /dev/null; then
    echo -e "${RED}  ✗ az (Azure CLI) is not installed${NC}"
    MISSING_TOOLS=1
else
    echo "  ✓ Azure CLI is installed"
fi

if ! check_and_install_kubectl; then
    MISSING_TOOLS=1
fi

if ! check_and_install_helm; then
    MISSING_TOOLS=1
fi

# Ensure ~/.local/bin is in PATH for this session
export PATH="$HOME/.local/bin:$PATH"

if [ $MISSING_TOOLS -eq 1 ]; then
    echo -e "${RED}Error: Some prerequisites are missing. Please install them and try again.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}\n"

# Step 1: Initialize Terraform
echo -e "${YELLOW}Step 1: Initializing Terraform...${NC}"
cd "$TF_DIR" || exit 1
terraform init
echo -e "${GREEN}✓ Terraform initialized${NC}\n"

# Step 2: Create/Update Infrastructure
echo -e "${YELLOW}Step 2: Creating/Updating AKS infrastructure...${NC}"
echo "This will create/update the AKS cluster and related resources."
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 1
fi

terraform apply -auto-approve -target=azurerm_kubernetes_cluster.aks -target=azurerm_resource_group.rg -target=azurerm_kubernetes_cluster_node_pool.spot 2>&1 | tee terraform-apply.log

echo -e "${GREEN}✓ Infrastructure created/updated${NC}\n"

# Step 3: Get AKS credentials
echo -e "${YELLOW}Step 3: Getting AKS credentials...${NC}"
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
RG_NAME=$(terraform output -raw resource_group_name)

if [ -z "$CLUSTER_NAME" ] || [ -z "$RG_NAME" ]; then
    echo -e "${RED}Error: Could not get cluster name or resource group from Terraform outputs${NC}"
    exit 1
fi

echo "Cluster: $CLUSTER_NAME"
echo "Resource Group: $RG_NAME"

az aks get-credentials \
    --resource-group "$RG_NAME" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing

echo -e "${GREEN}✓ Credentials retrieved${NC}\n"

# Wait a moment for credentials to be written and API server to be ready
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
    echo -e "${RED}Error: Cannot connect to cluster after 10 minutes${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check cluster status:"
    echo "   az aks show --resource-group $RG_NAME --name $CLUSTER_NAME --query provisioningState"
    echo ""
    echo "2. Try connecting manually:"
    echo "   kubectl cluster-info"
    echo ""
    echo "3. If cluster is ready but kubectl fails, check credentials:"
    echo "   az aks get-credentials --resource-group $RG_NAME --name $CLUSTER_NAME --overwrite-existing"
    echo ""
    echo "4. Once connected, continue deployment manually:"
    echo "   helm repo add dify https://borispolonsky.github.io/dify-helm && helm repo update"
    echo "   helm upgrade --install dify dify/dify -f values.yaml --namespace dify --create-namespace --timeout 20m --atomic --wait"
    exit 1
fi

# Step 5: Add Helm repository
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

# Step 7: Deploy Dify with Helm
echo -e "${YELLOW}Step 7: Deploying Dify with Helm...${NC}"
echo "This will deploy Dify and all dependencies (Redis, PostgreSQL, etc.)"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 1
fi

VALUES_ARG=""
if [ -f "$VALUES_FILE" ]; then
    VALUES_ARG="-f $VALUES_FILE"
    echo "Using values file: $VALUES_FILE"
else
    echo "No values file specified, using chart defaults"
fi

helm upgrade --install "$RELEASE_NAME" "$HELM_CHART" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --timeout 20m \
    --atomic \
    --wait \
    $VALUES_ARG

echo -e "${GREEN}✓ Dify deployed${NC}\n"

# Step 8: Wait for services to be ready
echo -e "${YELLOW}Step 8: Waiting for services to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/"$RELEASE_NAME"-api -n "$NAMESPACE" || true
kubectl wait --for=condition=available --timeout=300s deployment/"$RELEASE_NAME"-web -n "$NAMESPACE" || true

echo -e "${GREEN}✓ Services are ready${NC}\n"

# Step 9: Display deployment status
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo "Cluster: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo ""

echo "Pods:"
kubectl get pods -n "$NAMESPACE"
echo ""

echo "Services:"
kubectl get svc -n "$NAMESPACE"
echo ""

echo "To get service URLs:"
echo "  kubectl get svc -n $NAMESPACE"
