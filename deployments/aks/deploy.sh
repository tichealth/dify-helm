#!/bin/bash
# Hybrid Deployment Script: Terraform + Helm for AKS
# Part of dify-helm repository: deployments/aks/
#
# Modes (mutually exclusive; first match wins):
#   (default)        Interactive: prompt before apply, then terraform apply + helm upgrade
#   --auto-approve   Non-interactive local run: no prompt, terraform apply + helm upgrade
#   --plan-stage     CI plan job: terraform plan -out=tfplan + helm diff, then exit
#   --apply-stage    CI apply job: terraform apply tfplan + helm upgrade (tfplan required)
#
# Scope: --db | --app | --all (default: --all)
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR"
HELM_REPO_NAME="dify"
HELM_CHART="dify/dify"
HELM_REPO_URL="https://borispolonsky.github.io/dify-helm"
NAMESPACE="dify"
RELEASE_NAME="dify"

MODE="interactive"   # interactive | auto | plan-stage | apply-stage
DEPLOY_MODE="all"    # all | app | db
VALUES_FILE="$SCRIPT_DIR/values.yaml"

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve) MODE="auto"; shift ;;
        --plan-stage)   MODE="plan-stage"; shift ;;
        --apply-stage)  MODE="apply-stage"; shift ;;
        --db)           DEPLOY_MODE="db"; shift ;;
        --app)          DEPLOY_MODE="app"; shift ;;
        --all)          DEPLOY_MODE="all"; shift ;;
        *)              [[ -f "$1" ]] && VALUES_FILE="$1"; shift ;;
    esac
done

is_plan()  { [ "$MODE" = "plan-stage" ]; }
is_apply() { [ "$MODE" = "apply-stage" ]; }

CERT_EMAIL="${CERT_EMAIL:-vivek.narayanan@tichealth.com.au}"

on_err() {
    echo -e "${RED}✗ Deployment failed.${NC}"
    [ -f "$TF_DIR/terraform-apply.log" ] && { echo ""; echo "Last 200 lines of terraform-apply.log:"; tail -n 200 "$TF_DIR/terraform-apply.log" || true; }
}
trap on_err ERR

echo -e "${GREEN}Dify AKS (Terraform + Helm) — mode=$MODE scope=$DEPLOY_MODE${NC}\n"

# ----- Prereqs ---------------------------------------------------------------
check_and_install_kubectl() {
    command -v kubectl &>/dev/null && return 0
    echo "  Installing kubectl..."
    if command -v curl &>/dev/null; then
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/kubectl 2>/dev/null || { mkdir -p ~/.local/bin; mv kubectl ~/.local/bin/kubectl; export PATH="$HOME/.local/bin:$PATH"; }
    elif command -v snap &>/dev/null; then
        sudo snap install kubectl --classic
    else
        echo -e "${RED}kubectl not found. Install manually.${NC}"; return 1
    fi
    command -v kubectl &>/dev/null || return 1
}
check_and_install_helm() {
    command -v helm &>/dev/null && return 0
    echo "  Installing helm..."
    curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    export PATH="$HOME/.local/bin:$PATH"
    command -v helm &>/dev/null
}

command -v terraform &>/dev/null || { echo -e "${RED}terraform required${NC}"; exit 1; }
command -v az        &>/dev/null || { echo -e "${RED}az (Azure CLI) required${NC}"; exit 1; }
check_and_install_kubectl || exit 1
check_and_install_helm    || exit 1
export PATH="$HOME/.local/bin:$PATH"

# ----- Terraform init --------------------------------------------------------
cd "$TF_DIR" || exit 1
echo -e "${YELLOW}Step 1: Terraform init${NC}"
if [ -f "backend.azurerm.tfvars" ]; then
    terraform init -reconfigure -backend-config=backend.azurerm.tfvars
else
    terraform init
fi
echo -e "${GREEN}✓ Terraform initialized${NC}\n"

# ----- Step 2: Terraform plan/apply (skip when --app) -----------------------
DB_TARGETS=(
    -target=azurerm_virtual_network.postgres
    -target=azurerm_subnet.postgres
    -target=azurerm_subnet.management
    -target=azurerm_private_dns_zone.postgres
    -target=azurerm_private_dns_zone_virtual_network_link.postgres
    -target=azurerm_private_dns_zone_virtual_network_link.aks
    -target=azurerm_network_security_group.management
    -target=azurerm_network_security_rule.management_ssh
    -target=azurerm_network_security_rule.management_rdp
    -target=azurerm_network_security_rule.management_to_postgres
    -target=azurerm_subnet_network_security_group_association.management
    -target=azurerm_postgresql_flexible_server.pg
    -target=azurerm_postgresql_flexible_server_database.db
    -target=azurerm_postgresql_flexible_server_database.plugin_db
    -target=azurerm_postgresql_flexible_server_configuration.require_secure_transport
    -target=azurerm_postgresql_flexible_server_configuration.azure_extensions
    -target=null_resource.create_extensions_dify
    -target=null_resource.create_extensions_plugin
    -target=azurerm_virtual_network_peering.postgres_to_aks
    -target=azurerm_virtual_network_peering.aks_to_postgres
)
[ "$DEPLOY_MODE" = "db" ] && TF_SCOPE=("${DB_TARGETS[@]}") || TF_SCOPE=()

if [ "$DEPLOY_MODE" != "app" ]; then
    echo -e "${YELLOW}Step 2: Terraform (${DEPLOY_MODE})${NC}"

    if [ "$MODE" = "interactive" ]; then
        read -p "Continue? (y/n) " -n 1 -r; echo
        [[ $REPLY =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 1; }
    fi

    if is_plan; then
        terraform plan -out=tfplan "${TF_SCOPE[@]}" 2>&1 | tee terraform-plan.log
        echo -e "${GREEN}✓ tfplan saved${NC}\n"
    elif is_apply; then
        [ -f tfplan ] || { echo -e "${RED}Error: tfplan not found (run --plan-stage first).${NC}"; exit 1; }
        terraform apply -auto-approve tfplan 2>&1 | tee terraform-apply.log
    else
        terraform apply -auto-approve "${TF_SCOPE[@]}" 2>&1 | tee terraform-apply.log
    fi
else
    echo -e "${YELLOW}Step 2: skipping Terraform (--app)${NC}\n"
fi

# ----- --db scope ends here --------------------------------------------------
if [ "$DEPLOY_MODE" = "db" ]; then
    if is_plan; then
        echo -e "${GREEN}✓ Plan stage complete (db scope).${NC}"
    else
        POSTGRES_FQDN=$(terraform output -raw postgresql_fqdn 2>/dev/null || echo "N/A")
        echo -e "${GREEN}DB complete.${NC} PostgreSQL FQDN: $POSTGRES_FQDN"
    fi
    exit 0
fi

# ----- Step 3: AKS credentials ----------------------------------------------
echo -e "${YELLOW}Step 3: Getting AKS credentials${NC}"
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
RG_NAME=$(terraform output -raw resource_group_name)
[ -z "$CLUSTER_NAME" ] || [ -z "$RG_NAME" ] && { echo -e "${RED}Could not read AKS outputs from Terraform state.${NC}"; exit 1; }
echo "Cluster: $CLUSTER_NAME   Resource Group: $RG_NAME"
az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing
echo -e "${GREEN}✓ Credentials${NC}\n"

# ----- Step 4: cluster connectivity (skip pre-apply waits for plan-stage) ---
echo -e "${YELLOW}Step 4: Verifying cluster connectivity${NC}"
if is_plan; then
    kubectl cluster-info >/dev/null 2>&1 || { echo -e "${RED}Cluster unreachable; cannot run helm diff.${NC}"; exit 1; }
    echo -e "${GREEN}✓ Cluster reachable${NC}\n"
else
    echo "Waiting up to 10 min for API server + a Ready node..."
    for i in $(seq 1 60); do
        kubectl cluster-info &>/dev/null && break
        [ $((i % 6)) -eq 0 ] && echo "  still waiting ($((i*10))s)"
        sleep 10
    done
    kubectl cluster-info >/dev/null 2>&1 || { echo -e "${RED}Cannot connect to cluster${NC}"; exit 1; }
    for i in $(seq 1 40); do
        READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
        [ "${READY:-0}" -ge 1 ] && break
        echo "  waiting for nodes ($((i*15))s)"
        sleep 15
    done
    [ "${READY:-0}" -lt 1 ] && { echo -e "${RED}No Ready nodes${NC}"; exit 1; }
    echo -e "${GREEN}✓ Cluster + nodes Ready${NC}\n"
fi

# ----- Step 5: Helm repos ----------------------------------------------------
echo -e "${YELLOW}Step 5: Helm repos${NC}"
helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"           >/dev/null 2>&1 || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add jetstack      https://charts.jetstack.io     >/dev/null 2>&1 || true
helm repo update >/dev/null
echo -e "${GREEN}✓ Helm repos ready${NC}\n"

# ----- Build helm arg arrays (single source of truth) ----------------------
INGRESS_ARGS=(
    --namespace ingress-nginx
    --set controller.replicaCount=1
    --set controller.autoscaling.enabled=false
    --set controller.updateStrategy.rollingUpdate.maxSurge=0
    --set controller.updateStrategy.rollingUpdate.maxUnavailable=1
    --set controller.resources.requests.cpu=25m
    --set controller.resources.requests.memory=90Mi
    --set controller.service.type=LoadBalancer
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
)
CERT_MANAGER_ARGS=( --namespace cert-manager --version v1.13.3 )

helm_op() {
    # $1 = release   $2 = chart   rest = chart-specific args
    local release="$1" chart="$2"; shift 2
    if is_plan; then
        helm diff upgrade "$release" "$chart" "$@" --allow-unreleased \
            > "helm-diff-${release}.log" || true
    else
        helm upgrade --install "$release" "$chart" "$@" --create-namespace
    fi
}

# ----- Step 6-9: ingress-nginx, cert-manager, ClusterIssuer ----------------
if is_plan; then
    echo -e "${YELLOW}Step 6-9 (plan): helm diff for ingress-nginx + cert-manager${NC}"
    helm_op ingress-nginx ingress-nginx/ingress-nginx "${INGRESS_ARGS[@]}"
    helm_op cert-manager  jetstack/cert-manager       "${CERT_MANAGER_ARGS[@]}"
else
    echo -e "${YELLOW}Step 6: namespace${NC}"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${YELLOW}Step 7: ingress-nginx${NC}"
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        "${INGRESS_ARGS[@]}" --create-namespace --wait --timeout 15m

    echo -e "${YELLOW}Step 8: cert-manager${NC}"
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml
    helm upgrade --install cert-manager jetstack/cert-manager \
        "${CERT_MANAGER_ARGS[@]}" --create-namespace --wait --timeout 5m

    if [ -f "$SCRIPT_DIR/coredns-patch.yaml" ]; then
        echo -e "${YELLOW}Step 8b: CoreDNS patch${NC}"
        kubectl apply -f "$SCRIPT_DIR/coredns-patch.yaml"
        kubectl -n kube-system rollout restart deployment coredns
        kubectl -n kube-system rollout status  deployment coredns --timeout=60s
    fi

    echo -e "${YELLOW}Step 9: ClusterIssuer${NC}"
    kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: letsencrypt-staging }
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${CERT_EMAIL}
    privateKeySecretRef: { name: letsencrypt-staging }
    solvers: [{ http01: { ingress: { class: nginx } } }]
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: letsencrypt-prod }
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${CERT_EMAIL}
    privateKeySecretRef: { name: letsencrypt-prod }
    solvers: [{ http01: { ingress: { class: nginx } } }]
EOF
    echo -e "${GREEN}✓ ClusterIssuer applied${NC}\n"
fi

# ----- Step 10: Dify ---------------------------------------------------------
echo -e "${YELLOW}Step 10: Dify Helm${NC}"

# Secrets: TF_VAR_* (CI/local) or terraform.tfvars
get_secret() {
    local env_var="$1" tfvars_key="$2" val="${!1:-}"
    if [[ -z "$val" && -f "$TF_DIR/terraform.tfvars" ]]; then
        val=$(grep -E "^${tfvars_key}\s*=" "$TF_DIR/terraform.tfvars" 2>/dev/null \
              | sed -n 's/^[^=]*=\s*"\(.*\)"\s*$/\1/p' | sed 's/\\"/"/g')
    fi
    printf '%s' "$val"
}
SECRETS_DIR=$(mktemp -d); trap 'rm -rf "$SECRETS_DIR"' EXIT

DIFY_ARGS=( --namespace "$NAMESPACE" --timeout 45m )
[[ -f "$VALUES_FILE" ]] && DIFY_ARGS+=( -f "$VALUES_FILE" )

POSTGRES_FQDN=$(terraform output -raw postgresql_fqdn 2>/dev/null || true)
[[ -n "$POSTGRES_FQDN" && "$POSTGRES_FQDN" != *"N/A"* ]] && \
    DIFY_ARGS+=( --set "externalPostgres.address=$POSTGRES_FQDN" )

add_secret_arg() {
    local env_var="$1" tfvars_key="$2" helm_key="$3" file
    local val; val=$(get_secret "$env_var" "$tfvars_key")
    [[ -z "$val" ]] && return
    file="$SECRETS_DIR/$tfvars_key"
    printf '%s' "$val" > "$file"
    DIFY_ARGS+=( --set-file "$helm_key=$file" )
}
add_secret_arg TF_VAR_postgresql_password postgresql_password externalPostgres.password
add_secret_arg TF_VAR_dify_secret_key     dify_secret_key     global.appSecretKey
add_secret_arg TF_VAR_redis_password      redis_password      redis.auth.password
add_secret_arg TF_VAR_qdrant_api_key      qdrant_api_key      externalQdrant.apiKey

# Ingress host: explicit override > project_name in tfvars
if [[ -n "${DIFY_INGRESS_HOST:-}" ]]; then
    INGRESS_HOST="$DIFY_INGRESS_HOST"
else
    PROJECT_NAME=$(grep -E '^project_name\s*=' "$TF_DIR/terraform.tfvars" 2>/dev/null \
                   | sed -n 's/.*=\s*"\([^"]*\)".*/\1/p' || true)
    case "$PROJECT_NAME" in
        *prod*) INGRESS_HOST="dify-prod.tichealth.com.au" ;;
        *dev*)  INGRESS_HOST="dify-dev.tichealth.com.au" ;;
        *test*) INGRESS_HOST="dify-test.tichealth.com.au" ;;
        *)      INGRESS_HOST="${PROJECT_NAME}.tichealth.com.au" ;;
    esac
fi
BASE_URL="https://$INGRESS_HOST"
DIFY_ARGS+=(
    --set "ingress.hosts[0].host=$INGRESS_HOST"
    --set "ingress.tls[0].hosts[0]=$INGRESS_HOST"
    --set "global.consoleWebDomain=$BASE_URL"
    --set "global.consoleApiDomain=$BASE_URL"
    --set "global.serviceApiDomain=$BASE_URL"
    --set "global.appApiDomain=$BASE_URL"
    --set "global.appWebDomain=$BASE_URL"
    --set "global.filesDomain=$BASE_URL"
    --set "global.triggerDomain=$BASE_URL"
)

if [[ -n "${PHOENIX_OTLP_ENDPOINT:-}" ]]; then
    DIFY_ARGS+=( --set api.otel.enabled=true --set "api.otel.baseEndpoint=${PHOENIX_OTLP_ENDPOINT}" )
    echo "OTEL: exporting to $PHOENIX_OTLP_ENDPOINT"
fi

if [ "$MODE" = "interactive" ]; then
    read -p "Continue with Dify upgrade? (y/n) " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 1; }
fi

if is_plan; then
    helm diff upgrade "$RELEASE_NAME" "$HELM_CHART" "${DIFY_ARGS[@]}" --allow-unreleased \
        > helm-diff-dify.log || true
    echo -e "${GREEN}✓ Helm diffs in helm-diff-*.log${NC}"
    echo -e "${GREEN}✓ Plan stage complete.${NC}"
    exit 0
fi

helm upgrade --install "$RELEASE_NAME" "$HELM_CHART" "${DIFY_ARGS[@]}" \
    --create-namespace --atomic --wait
echo -e "${GREEN}✓ Dify deployed${NC}\n"

kubectl wait --for=condition=available --timeout=300s deployment/"$RELEASE_NAME"-api -n "$NAMESPACE" || true
kubectl wait --for=condition=available --timeout=300s deployment/"$RELEASE_NAME"-web -n "$NAMESPACE" || true

[ -f "$SCRIPT_DIR/fix-nsg-rules.sh" ] && { chmod +x "$SCRIPT_DIR/fix-nsg-rules.sh"; "$SCRIPT_DIR/fix-nsg-rules.sh" || true; }

echo -e "\n${GREEN}Deployment complete.${NC}"
kubectl get pods -n "$NAMESPACE"

# LB IP for DNS
LB_IP=""
for i in $(seq 1 24); do
    LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    [[ -n "$LB_IP" && "$LB_IP" != "<pending>" ]] && break
    sleep 5
done
if [[ -n "$LB_IP" && "$LB_IP" != "<pending>" ]]; then
    echo -e "${GREEN}DNS: $INGRESS_HOST -> $LB_IP${NC}"
else
    echo -e "${YELLOW}LoadBalancer IP pending.${NC}"
fi
