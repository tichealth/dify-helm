# How to Get Dify Public Endpoint (IP Address & Domain)

This guide shows you how to find the public IP address and domain name for accessing Dify from the internet.

## Quick Answer

**Domain (HTTPS):** `https://dify-dev.tichealth.com.au/apps`

**To find the IP address:**
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Look for the `EXTERNAL-IP` column (e.g., `<ingress-lb-ip>`)

---

## Method 1: Get nginx-ingress LoadBalancer IP (Recommended)

The Dify application is accessible through the nginx-ingress LoadBalancer. Get its IP:

```bash
# Get the LoadBalancer IP
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Output example:
# NAME                       TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)                      AGE
# ingress-nginx-controller   LoadBalancer   10.0.123.45    <ingress-lb-ip>    80:31234/TCP,443:31235/TCP   5d
```

The `EXTERNAL-IP` is the public IP address accessible from the internet.

**Note:** You can access Dify via:
- **Domain (recommended)**: `https://dify-dev.tichealth.com.au` (uses HTTPS/TLS)
- **IP address (HTTP only)**: `http://<ingress-lb-ip>` (no HTTPS, may not work if SSL redirect is enabled)

---

## Method 2: Get IP from Ingress Resource

```bash
# Get ingress details
kubectl get ingress -n dify

# Get detailed ingress information including IP
kubectl get ingress -n dify -o wide

# Get full ingress details (shows IP in status)
kubectl describe ingress -n dify
```

The ingress status will show the LoadBalancer IP address.

---

## Method 3: Azure Portal

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Kubernetes services** → Your AKS cluster
3. Go to **Services and ingresses** → **Services**
4. Find `ingress-nginx-controller` in the `ingress-nginx` namespace
5. The **External IP** column shows the public IP address

---

## Method 4: Azure CLI

```bash
# Get LoadBalancer service details
az aks show \
  --resource-group <your-resource-group> \
  --name <your-aks-cluster-name> \
  --query "servicePrincipalProfile"

# Or get the service directly via kubectl (if you have access)
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

---

## Method 5: DNS Lookup

If DNS is configured, you can resolve the domain to get the IP:

```bash
# Resolve domain to IP
nslookup dify-dev.tichealth.com.au

# Or using dig
dig +short dify-dev.tichealth.com.au

# Or using host
host dify-dev.tichealth.com.au
```

**Expected output:**
```
dify-dev.tichealth.com.au has address <ingress-lb-ip>
```

---

## Access Methods

### Option 1: Domain Name (Recommended - HTTPS)

**URL:** `https://dify-dev.tichealth.com.au/apps`

**Benefits:**
- ✅ HTTPS/TLS encryption (secure)
- ✅ Valid SSL certificate (Let's Encrypt)
- ✅ Auto-redirects HTTP to HTTPS
- ✅ Professional domain name

**Requirements:**
- DNS A record pointing to the LoadBalancer IP
- Valid SSL certificate (managed by cert-manager)

---

### Option 2: IP Address (HTTP Only)

**URL:** `http://<ingress-lb-ip>/apps` (replace with your actual IP)

**Limitations:**
- ❌ No HTTPS (insecure)
- ❌ May not work if SSL redirect is enabled
- ❌ No valid SSL certificate
- ⚠️ Not recommended for production

**Note:** If SSL redirect is enabled, accessing via IP will redirect to HTTPS, which may fail because the certificate is for the domain, not the IP.

---

## Verify Endpoint is Accessible

### Test HTTPS (Domain)

```bash
# Test HTTPS endpoint
curl -I https://dify-dev.tichealth.com.au

# Expected output:
# HTTP/2 200
# ...
```

### Test HTTP (IP - if redirect disabled)

```bash
# Test HTTP endpoint via IP
curl -I http://<ingress-lb-ip>

# Note: This may redirect to HTTPS if SSL redirect is enabled
```

### Test from Browser

1. Open browser
2. Navigate to: `https://dify-dev.tichealth.com.au/apps`
3. You should see the Dify login page
4. Check for the padlock icon (🔒) indicating HTTPS is working

---

## Complete Endpoint Information

After deployment, you have:

| Item | Value | How to Get |
|------|-------|------------|
| **Domain** | `dify-dev.tichealth.com.au` | From `values.yaml` → `ingress.hosts[0].host` |
| **IP Address** | `<ingress-lb-ip>` | `kubectl get svc -n ingress-nginx ingress-nginx-controller` |
| **HTTPS URL** | `https://dify-dev.tichealth.com.au/apps` | Domain + HTTPS |
| **HTTP URL** | `http://<ingress-lb-ip>` | IP + HTTP (not recommended) |
| **Port** | `443` (HTTPS), `80` (HTTP) | Standard ports |
| **SSL Certificate** | Let's Encrypt | Managed by cert-manager |

---

## Troubleshooting

### If IP is `<pending>`

The LoadBalancer is still being provisioned. Wait a few minutes:

```bash
# Watch the service until IP is assigned
kubectl get svc -n ingress-nginx ingress-nginx-controller -w
```

### If domain doesn't resolve

1. **Check DNS A record:**
   ```bash
   nslookup dify-dev.tichealth.com.au
   ```

2. **Verify DNS points to LoadBalancer IP:**
  - DNS A record: `dify-dev` → `<ingress-lb-ip>` (your LoadBalancer IP)
   - DNS provider: Your DNS provider for `tichealth.com.au`

3. **Check DNS propagation:**
   ```bash
   dig dify-dev.tichealth.com.au
   ```

### If HTTPS doesn't work

1. **Check certificate status:**
   ```bash
   kubectl get certificate -n dify
   kubectl describe certificate -n dify
   ```

2. **Check cert-manager:**
   ```bash
   kubectl get pods -n cert-manager
   ```

3. **Check ingress:**
   ```bash
   kubectl get ingress -n dify
   kubectl describe ingress -n dify
   ```

### If connection times out

1. **Verify LoadBalancer is running:**
   ```bash
   kubectl get svc -n ingress-nginx ingress-nginx-controller
   ```

2. **Check ingress controller pods:**
   ```bash
   kubectl get pods -n ingress-nginx
   ```

3. **Check firewall rules:**
   - Ensure Azure NSG allows traffic on ports 80 and 443
   - Check if any firewall is blocking the LoadBalancer IP

---

## Quick Reference Commands

```bash
# Get LoadBalancer IP
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Get domain from ingress
kubectl get ingress -n dify -o jsonpath='{.items[0].spec.rules[0].host}'

# Test HTTPS endpoint
curl -I https://dify-dev.tichealth.com.au

# Resolve domain to IP
nslookup dify-dev.tichealth.com.au

# Check certificate
kubectl get certificate -n dify
```

---

## Architecture Overview

```
Internet
   │
   │ HTTPS (443) or HTTP (80)
   ▼
nginx-ingress LoadBalancer (<ingress-lb-ip>)
   │
   │ TLS Termination
   ▼
Kubernetes Ingress (dify-dev.tichealth.com.au)
   │
   │ HTTP (80)
   ▼
Dify Service (ClusterIP)
   │
   │
   ▼
Dify Pods (web, api, worker, etc.)
```

---

## Notes

- **IP Address Changes**: The LoadBalancer IP may change if you delete and recreate the nginx-ingress service. Update your DNS A record if this happens.
- **Static IP**: For a static IP, you can configure the LoadBalancer with a reserved IP address in Azure.
- **Multiple Environments**: Each environment (dev/test/prod) will have its own LoadBalancer IP and domain.
- **Cost**: The LoadBalancer costs ~$18-25/month (Standard SKU).

---

## References

- [HTTPS Setup Guide](./HTTPS_SETUP_GUIDE.md)
- [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Azure Load Balancer Pricing](https://azure.microsoft.com/pricing/details/load-balancer/)
