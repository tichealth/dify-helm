# Changes to Propagate from Dev to Other Environments

This document lists all changes made in the dev environment (`dify-helm/deployments/aks`) that should be propagated to test and production environments.

## ✅ Changes Made in Dev Environment

### 1. HTTPS/TLS Configuration

**Files Modified:**
- `values.yaml` - Added ingress configuration, changed service type to ClusterIP

**Changes:**
```yaml
# Service Configuration
service:
  type: ClusterIP  # Changed from LoadBalancer - Ingress handles external access
  port: 80

# Ingress Configuration (HTTPS/TLS enabled)
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
  hosts:
    - host: dify-dev.tichealth.com.au  # Update for each environment
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: dify-tls
      hosts:
        - dify-dev.tichealth.com.au  # Update for each environment
```

**Action Required:**
- [ ] Add ingress configuration to test environment `values.yaml`
- [ ] Add ingress configuration to prod environment `values.yaml`
- [ ] Update hostnames for each environment (e.g., `dify-test.tichealth.com.au`, `dify-prod.tichealth.com.au`)
- [ ] Ensure nginx-ingress controller is installed in test/prod clusters
- [ ] Ensure cert-manager is installed in test/prod clusters
- [ ] Create ClusterIssuers (letsencrypt-prod) in test/prod clusters

**Cost Impact:** +$18-25/month per environment (nginx-ingress LoadBalancer)

---

### 2. CoreDNS Configuration

**Files Added:**
- `coredns-patch.yaml` - CoreDNS configuration using external DNS servers

**Changes:**
- CoreDNS forward DNS changed from `/etc/resolv.conf` to external DNS servers (8.8.8.8, 1.1.1.1)
- This ensures faster DNS resolution and bypasses Azure DNS propagation delays

**Action Required:**
- [ ] Copy `coredns-patch.yaml` to test environment
- [ ] Copy `coredns-patch.yaml` to prod environment
- [ ] Apply CoreDNS patch in test cluster: `kubectl apply -f coredns-patch.yaml`
- [ ] Apply CoreDNS patch in prod cluster: `kubectl apply -f coredns-patch.yaml`
- [ ] Restart CoreDNS pods in test: `kubectl delete pods -n kube-system -l k8s-app=kube-dns`
- [ ] Restart CoreDNS pods in prod: `kubectl delete pods -n kube-system -l k8s-app=kube-dns`

**Note:** This is optional but recommended for faster DNS resolution during certificate challenges.

---

### 3. Image Version Updates

**Files Modified:**
- `values.yaml` - Updated image tags

**Changes:**
```yaml
image:
  api:
    tag: "1.11.2"  # Updated from 1.4.1
  web:
    tag: "1.11.2"  # Updated from 1.4.1
  sandbox:
    tag: "0.2.12"  # Updated from 0.2.1
  pluginDaemon:
    tag: "0.5.2-local"  # Updated from 0.1.1-local
```

**Action Required:**
- [ ] Update image tags in test environment `values.yaml`
- [ ] Update image tags in prod environment `values.yaml`
- [ ] Test upgrades in test environment first
- [ ] Follow upgrade procedures in [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)

**Benefits:**
- Fixed timezone parameter bug (constant type variables)
- Latest features and bug fixes
- Plugin daemon compatibility improvements

---

### 4. Storage Class Configuration

**Files Modified:**
- `values.yaml` - Updated storage classes for ReadWriteMany volumes

**Changes:**
```yaml
api:
  persistence:
    persistentVolumeClaim:
      storageClass: "azurefile"  # Changed from default (disk.csi.azure.com)

pluginDaemon:
  persistence:
    persistentVolumeClaim:
      storageClass: "azurefile"  # Changed from default (disk.csi.azure.com)
```

**Action Required:**
- [ ] Update storage classes in test environment `values.yaml`
- [ ] Update storage classes in prod environment `values.yaml`
- [ ] Verify `azurefile` storage class exists in test/prod clusters
- [ ] If PVCs already exist, may need to delete and recreate them

**Note:** `azurefile` storage class supports `ReadWriteMany` access mode required by Dify API and Plugin Daemon.

---

### 5. Documentation Updates

**Files Added/Updated:**
- `README.md` - Updated with HTTPS status
- `HTTPS_SETUP_GUIDE.md` - Complete HTTPS setup guide (consolidated)
- `COST_SUMMARY_2026-01-24.md` - Cost summary (Dev/Test/Prod)
- `COST_OPTIMIZATIONS_2026-01-24.md` - Cost optimization recommendations
- `INFRACOST.md` - Infracost usage
- `CHANGELOG.md` - Deployment changes history
- `DOCUMENTATION_INDEX.md` - Documentation navigation
- `CHANGES_TO_PROPAGATE.md` - This file

**Action Required:**
- [ ] Copy documentation files to test/prod environment directories (if separate)
- [ ] Update environment-specific details (hostnames, costs, etc.)
- [ ] Review and adapt documentation for each environment's specific needs

---

## 📋 Propagation Checklist

### Test Environment

#### Infrastructure
- [ ] Install nginx-ingress controller
- [ ] Install cert-manager
- [ ] Create ClusterIssuers (letsencrypt-prod, letsencrypt-staging)
- [ ] Apply CoreDNS patch (`coredns-patch.yaml`)
- [ ] Verify `azurefile` storage class exists

#### Application Configuration
- [ ] Update `values.yaml` with HTTPS/ingress configuration
- [ ] Update `values.yaml` with image versions (1.11.2, 0.5.2-local, 0.2.12)
- [ ] Update `values.yaml` with storage class (`azurefile`)
- [ ] Update hostname to `dify-test.tichealth.com.au` (or appropriate domain)
- [ ] Configure DNS A record for test domain

#### Deployment
- [ ] Deploy/upgrade Helm release with updated values
- [ ] Verify certificate issuance
- [ ] Test HTTPS access
- [ ] Verify all pods are running correctly

#### Documentation
- [ ] Copy relevant documentation files
- [ ] Update environment-specific details

---

### Production Environment

#### Infrastructure
- [ ] Install nginx-ingress controller
- [ ] Install cert-manager
- [ ] Create ClusterIssuers (letsencrypt-prod only - no staging)
- [ ] Apply CoreDNS patch (`coredns-patch.yaml`)
- [ ] Verify `azurefile` storage class exists

#### Application Configuration
- [ ] Update `values.yaml` with HTTPS/ingress configuration
- [ ] Update `values.yaml` with image versions (1.11.2, 0.5.2-local, 0.2.12)
- [ ] Update `values.yaml` with storage class (`azurefile`)
- [ ] Update hostname to `dify-prod.tichealth.com.au` (or appropriate domain)
- [ ] Configure DNS A record for production domain
- [ ] Review and adjust resource limits/requests for production workload

#### Deployment
- [ ] **Test in test environment first** ✅
- [ ] Plan maintenance window for production upgrade
- [ ] Deploy/upgrade Helm release with updated values
- [ ] Verify certificate issuance
- [ ] Test HTTPS access
- [ ] Verify all pods are running correctly
- [ ] Monitor for 24-48 hours after deployment

#### Documentation
- [ ] Copy relevant documentation files
- [ ] Update environment-specific details
- [ ] Document production-specific configurations

---

## 🔄 Recommended Propagation Order

1. **Test Environment First** (Low risk, validates changes)
   - Apply all changes
   - Test thoroughly
   - Monitor for 1-2 weeks

2. **Production Environment** (After test validation)
   - Apply all changes
   - Use maintenance window
   - Monitor closely for 24-48 hours

---

## ⚠️ Important Notes

### HTTPS Configuration
- Each environment needs its own nginx-ingress LoadBalancer (~$18-25/month each)
- Each environment needs its own DNS A record
- Certificates are issued per domain (separate for dev/test/prod)

### Image Versions
- Always test upgrades in test environment first
- Follow upgrade procedures in [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)
- Have rollback plan ready

### Storage Classes
- If PVCs already exist with different storage class, they may need to be deleted and recreated
- **Warning**: This will cause data loss if not backed up first
- Consider backing up data before changing storage classes

### CoreDNS Patch
- This is optional but recommended
- Improves DNS resolution speed
- Helps with certificate challenges
- Can be applied without downtime (rolling restart)

---

## 📝 Environment-Specific Considerations

### Test Environment
- Can use `letsencrypt-staging` ClusterIssuer for testing
- Lower resource requirements acceptable
- Can tolerate brief downtime during upgrades

### Production Environment
- **Must** use `letsencrypt-prod` ClusterIssuer (trusted certificates)
- Higher resource requirements
- Plan maintenance windows for upgrades
- Implement monitoring and alerting
- Have rollback procedures ready

---

## 🔗 Related Documentation

- [HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md) - Complete HTTPS setup instructions
- [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md) - Version upgrade procedures
- [COST_SUMMARY_2026-01-24.md](./COST_SUMMARY_2026-01-24.md) - Cost summary (Dev/Test/Prod)
- [COST_OPTIMIZATIONS_2026-01-24.md](./COST_OPTIMIZATIONS_2026-01-24.md) - Cost optimizations
- [INFRACOST.md](./INFRACOST.md) - Exact estimates
- [README.md](./README.md) - Main documentation

---

## ✅ Verification Steps

After propagating changes to each environment:

```bash
# 1. Check certificate status
kubectl get certificate -n dify

# 2. Check ingress
kubectl get ingress -n dify

# 3. Check all pods
kubectl get pods -n dify

# 4. Test HTTPS
curl -I https://dify-<env>.tichealth.com.au

# 5. Check DNS resolution from cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup dify-<env>.tichealth.com.au
```

---

**Last Updated:** January 13, 2026  
**Status:** Ready for propagation to test and production environments
