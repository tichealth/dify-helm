# HTTPS Setup Guide for Dify on AKS

Complete guide for enabling and managing HTTPS/TLS for your Dify deployment on Azure Kubernetes Service (AKS).

## Current Status

✅ **HTTPS is enabled and working**

- **Domain**: `dify-dev.tichealth.com.au`
- **Certificate**: Let's Encrypt (Production)
- **Status**: READY
- **Valid Until**: April 13, 2026 (auto-renewal enabled)
- **Auto-renewal**: Enabled (renews 30 days before expiration)

## Overview

HTTPS is configured using:
1. **Nginx Ingress Controller** - Routes traffic and terminates TLS
2. **cert-manager** - Automatically manages TLS certificates from Let's Encrypt
3. **Kubernetes Ingress** - Configures routing and TLS termination
4. **CoreDNS** - Configured to use external DNS servers (8.8.8.8, 1.1.1.1) for faster resolution

## Architecture

```
Internet → nginx-ingress LoadBalancer (52.154.66.82) → Ingress (TLS) → Dify Service (ClusterIP) → Dify Pods
```

## Prerequisites

- AKS cluster with cluster-admin permissions
- A domain name with DNS access
- nginx-ingress controller installed
- cert-manager installed

## Installation Steps

### Step 1: Install Nginx Ingress Controller

```bash
# Add the ingress-nginx Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install nginx-ingress controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
  --wait --timeout 5m
```

Get the LoadBalancer IP:
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Note the EXTERNAL-IP (e.g., 52.154.66.82)
```

### Step 2: Install cert-manager

```bash
# Add cert-manager Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.3 \
  --wait --timeout 5m

# Verify installation
kubectl get pods -n cert-manager
```

### Step 3: Create ClusterIssuer for Let's Encrypt

```bash
# Replace email with your actual email
EMAIL="vivek.narayanan@tichealth.com.au"

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: $EMAIL
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
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### Step 4: Configure CoreDNS for Faster DNS Resolution

**Important**: CoreDNS has been configured to use external DNS servers (8.8.8.8, 1.1.1.1) instead of Azure's internal resolver. This ensures faster DNS resolution and bypasses Azure DNS propagation delays.

The configuration is saved in `coredns-patch.yaml`. If you need to reapply it:

```bash
kubectl apply -f coredns-patch.yaml
kubectl delete pods -n kube-system -l k8s-app=kube-dns
```

### Step 5: Update values.yaml

Update `dify-helm/deployments/aks/values.yaml`:

```yaml
# Service Configuration - Use ClusterIP (Ingress handles external access)
service:
  type: ClusterIP  # Changed from LoadBalancer
  port: 80

# Ingress Configuration - Enable and configure
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Use "letsencrypt-staging" for testing
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
  hosts:
    - host: dify-dev.tichealth.com.au  # Replace with your domain
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: dify-tls
      hosts:
        - dify-dev.tichealth.com.au  # Replace with your domain
```

### Step 6: Configure DNS

Create an A record in your DNS provider:

- **Name**: `dify-dev` (or your subdomain)
- **Type**: `A`
- **Value**: `52.154.66.82` (nginx-ingress LoadBalancer IP)
- **TTL**: `300` (or default)

### Step 7: Deploy the Updated Configuration

```bash
cd dify-helm/deployments/aks

# Upgrade the Helm release
helm upgrade dify dify/dify \
  -f values.yaml \
  --namespace dify \
  --timeout 20m \
  --wait
```

### Step 8: Verify HTTPS

```bash
# Check certificate status
kubectl get certificate -n dify
# Should show: READY: True

# Check certificate details
kubectl describe certificate dify-tls -n dify

# Test HTTPS
curl -I https://dify-dev.tichealth.com.au
# Should return HTTP 200 or 307 (redirect)
```

## Current Configuration

- **Domain**: `dify-dev.tichealth.com.au`
- **Ingress LoadBalancer IP**: `52.154.66.82`
- **Certificate**: Let's Encrypt (Production)
- **Certificate Status**: READY
- **Auto-renewal**: Enabled (renews 30 days before expiration)

## Troubleshooting

### Certificate Not Issuing

**Symptoms**: Certificate shows `READY: False`, challenges pending

**Common Causes**:
1. DNS not resolving from within the cluster
2. DNS not configured or not propagated
3. Challenge endpoint not accessible

**Solutions**:

1. **Check DNS resolution from cluster**:
   ```bash
   kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup dify-dev.tichealth.com.au
   # Should return: 52.154.66.82
   ```

2. **If DNS doesn't resolve from cluster**:
   - Verify DNS A record is configured correctly
   - Wait for DNS propagation (5-15 minutes)
   - Restart CoreDNS pods: `kubectl delete pods -n kube-system -l k8s-app=kube-dns`
   - Verify CoreDNS is using external DNS (check `coredns-patch.yaml`)

3. **Check certificate status**:
   ```bash
   kubectl describe certificate dify-tls -n dify
   kubectl get challenges -n dify
   kubectl describe challenge -n dify
   ```

4. **Check cert-manager logs**:
   ```bash
   kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager --tail=50
   ```

5. **Manually retry** (if needed):
   ```bash
   kubectl delete challenge -n dify --all
   kubectl delete certificaterequest -n dify --all
   # cert-manager will automatically retry
   ```

### DNS Not Resolving from Cluster

**Issue**: DNS works externally but not from within the cluster

**Solution**: CoreDNS has been configured to use external DNS servers. If it's not working:

```bash
# Verify CoreDNS config
kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'

# Should show: forward . 8.8.8.8 1.1.1.1

# If not, reapply the patch
kubectl apply -f coredns-patch.yaml
kubectl delete pods -n kube-system -l k8s-app=kube-dns
```

### Self-Signed Certificate Error

**Symptom**: Browser/curl shows "self-signed certificate" error

**Cause**: Certificate not issued yet or nginx-ingress serving default fake certificate

**Solution**:
1. Wait for certificate to be issued (usually 2-5 minutes after DNS resolves)
2. Check certificate status: `kubectl get certificate -n dify`
3. Once `READY: True`, the error will disappear

### Challenge Endpoint Not Accessible

**Symptom**: Challenge fails with connection errors

**Solution**:
1. Verify DNS A record points to nginx-ingress LoadBalancer IP
2. Test challenge endpoint externally:
   ```bash
   curl http://dify-dev.tichealth.com.au/.well-known/acme-challenge/test
   ```
3. Check ingress: `kubectl get ingress -n dify`
4. Verify nginx-ingress controller is running: `kubectl get pods -n ingress-nginx`

## Certificate Management

### Check Certificate Status

```bash
# Current status
kubectl get certificate -n dify

# Detailed information
kubectl describe certificate dify-tls -n dify

# View certificate details
kubectl get secret dify-tls -n dify -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -E 'Issuer|Subject|Not Before|Not After'
```

### Auto-Renewal

cert-manager automatically renews certificates 30 days before expiration. No action needed.

### Manual Renewal (if needed)

```bash
# Delete the certificate secret to force renewal
kubectl delete secret dify-tls -n dify
# cert-manager will automatically create a new certificate
```

### Using Staging vs Production Certificates

- **Staging**: Use for testing, higher rate limits, certificates not trusted by browsers
- **Production**: Use for real certificates, trusted by browsers

Switch by updating `values.yaml`:
```yaml
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-staging"  # or "letsencrypt-prod"
```

Then redeploy:
```bash
helm upgrade dify dify/dify -f values.yaml --namespace dify
```

## DNS Configuration

### Current Setup

- **Domain**: `dify-dev.tichealth.com.au`
- **A Record**: `dify-dev` → `52.154.66.82`
- **DNS Provider**: Your DNS provider for `tichealth.com.au`

### Verify DNS

```bash
# External resolution
dig dify-dev.tichealth.com.au
# or
nslookup dify-dev.tichealth.com.au

# From cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup dify-dev.tichealth.com.au
```

### DNS Propagation

- **Typical**: 5-15 minutes
- **Maximum**: Up to 48 hours (rare)
- **CoreDNS Fix**: Using external DNS servers (8.8.8.8, 1.1.1.1) bypasses Azure DNS delays

## Cost Impact

Enabling HTTPS adds:
- **nginx-ingress LoadBalancer**: ~$18-25/month
- **cert-manager**: No additional cost (runs as pods)
- **Total Additional Cost**: ~$18-25/month

**Note**: The old Dify LoadBalancer service was changed to ClusterIP, so there's no duplicate LoadBalancer cost.

## Verification Commands

```bash
# 1. Check certificate status
kubectl get certificate -n dify

# 2. Check ingress
kubectl get ingress -n dify

# 3. Check DNS resolution (external)
dig dify-dev.tichealth.com.au

# 4. Check DNS resolution (from cluster)
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup dify-dev.tichealth.com.au

# 5. Test HTTPS
curl -I https://dify-dev.tichealth.com.au

# 6. View certificate details
curl -v https://dify-dev.tichealth.com.au 2>&1 | grep -E 'subject|issuer|CN='
```

## Access URLs

- **HTTPS**: `https://dify-dev.tichealth.com.au` ✅
- **HTTP**: `http://dify-dev.tichealth.com.au` (redirects to HTTPS)

## Maintenance

### Certificate Renewal

Certificates auto-renew 30 days before expiration. Monitor renewal:

```bash
# Check certificate expiration
kubectl get certificate dify-tls -n dify -o jsonpath='{.status.notAfter}'

# Check renewal time
kubectl get certificate dify-tls -n dify -o jsonpath='{.status.renewalTime}'
```

### Update Domain

To change the domain:

1. Update `values.yaml` with new domain
2. Create new DNS A record
3. Redeploy: `helm upgrade dify dify/dify -f values.yaml --namespace dify`
4. New certificate will be issued automatically

## References

- [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt](https://letsencrypt.org/)
- [CoreDNS Configuration](https://coredns.io/manual/toc/)
