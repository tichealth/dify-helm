# Dify Upgrade Guide for AKS Deployment

This guide documents how to upgrade Dify on AKS, ensuring compatibility with the official docker-compose.yaml configuration.

## Overview

When upgrading Dify versions, it's important to:
1. Match image versions with the official docker-compose.yaml
2. Ensure plugin daemon version compatibility
3. Verify configuration alignment
4. Test the deployment

## Version Compatibility Reference

### Dify 1.11.2 (Current)

Based on `dify/docker/docker-compose.yaml`:

- **API**: `langgenius/dify-api:1.11.2`
- **Web**: `langgenius/dify-web:1.11.2`
- **Sandbox**: `langgenius/dify-sandbox:0.2.12`
- **Plugin Daemon**: `langgenius/dify-plugin-daemon:0.5.2-local`

## Upgrade Steps

### 1. Check Current Version

```bash
cd dify-helm/deployments/aks

# Check current Helm values
helm get values dify -n dify | grep -A 1 "tag:"

# Check running pods
kubectl get pods -n dify -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}' | grep -E 'api|web|plugin'
```

### 2. Compare with docker-compose.yaml

Before upgrading, compare your `values.yaml` with the official `dify/docker/docker-compose.yaml` to ensure:
- Image versions match
- Plugin daemon version is compatible
- Configuration settings are aligned

```bash
# Check docker-compose.yaml versions
grep -E "langgenius/dify-(api|web|plugin-daemon|sandbox):" dify/docker/docker-compose.yaml
```

### 3. Update values.yaml

Edit `dify-helm/deployments/aks/values.yaml`:

```yaml
image:
  api:
    repository: langgenius/dify-api
    tag: "1.11.2"  # Update this
    pullPolicy: IfNotPresent
  web:
    repository: langgenius/dify-web
    tag: "1.11.2"  # Update this
    pullPolicy: IfNotPresent
  sandbox:
    repository: langgenius/dify-sandbox
    tag: "0.2.12"  # Match docker-compose.yaml version
    pullPolicy: IfNotPresent
  pluginDaemon:
    repository: langgenius/dify-plugin-daemon
    tag: "0.5.2-local"  # Match docker-compose.yaml version
    pullPolicy: IfNotPresent
```

### 4. Perform Helm Upgrade

```bash
cd dify-helm/deployments/aks

# Update Helm repository (if using external chart)
helm repo update dify

# Upgrade the release
helm upgrade dify dify/dify \
  -f values.yaml \
  --namespace dify \
  --timeout 20m \
  --wait
```

### 5. Verify the Upgrade

```bash
# Check pod images
kubectl get pods -n dify -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}' | grep -E 'api|web|plugin'

# Check pod status
kubectl get pods -n dify

# Check API logs for errors
kubectl logs -n dify -l app.kubernetes.io/component=api --tail=50 | grep -i error

# Get service URL
kubectl get svc -n dify dify
```

### 6. Rollback (if needed)

If the upgrade fails:

```bash
# List Helm revisions
helm history dify -n dify

# Rollback to previous revision
helm rollback dify <revision-number> -n dify

# Or rollback to last revision
helm rollback dify -n dify
```

## Important Notes

### Plugin Daemon Version

The plugin daemon version is critical for plugin functionality:
- Must match the version in `dify/docker/docker-compose.yaml`
- Current version for Dify 1.11.2: `0.5.2-local`
- Older versions (e.g., `0.1.1-local`) may cause plugin errors

### Storage Class

Ensure storage classes are correctly configured for Azure:
- API and Plugin Daemon need `azurefile` storage class (ReadWriteMany)
- PostgreSQL and Redis use default storage class (ReadWriteOnce)

### Resource Constraints

Monitor resource usage during upgrades:
- Plugin daemon requires 500m CPU request
- Ensure cluster has sufficient resources for rolling updates
- Check for Pending pods due to resource constraints

## Common Issues

### Issue: Plugin Installation Errors / 500 Errors on Triggers Endpoint

**Symptoms:**
- 404 errors from plugin daemon
- 500 errors on `/console/api/workspaces/current/triggers`
- Plugins not loading

**Root Cause:**
- This is a **known bug in Dify 1.11.2** - the API doesn't handle 404 responses from plugin daemon gracefully when plugins don't have triggers
- The API code raises an exception instead of returning an empty list
- This is an API code issue, not a deployment issue

**Solution:**
- **Workaround**: The errors are cosmetic - plugins still work for tools/models even if triggers endpoint fails
- Ensure plugin daemon version matches docker-compose.yaml (current: 0.5.2-local)
- Check plugin daemon pod is running: `kubectl get pods -n dify | grep plugin`
- Verify plugin daemon logs: `kubectl logs -n dify -l app.kubernetes.io/component=plugin-daemon --tail=50`
- **Note**: Upgrading plugin daemon won't fix this - it's an API code bug that needs to be fixed in a future Dify release

### Issue: Pods Pending Due to CPU

**Symptoms:**
- Pods stuck in Pending state
- Events show "Insufficient cpu"

**Solution:**
- Check cluster resources: `kubectl describe nodes`
- Wait for old pods to terminate
- Consider scaling the cluster or reducing resource requests

### Issue: Version Mismatch in UI

**Symptoms:**
- UI shows old version after upgrade
- Browser cache issues

**Solution:**
- Hard refresh browser: `Ctrl+Shift+R` (Windows) or `Cmd+Shift+R` (Mac)
- Clear browser cache
- Verify pods are running new version: `kubectl get pods -n dify -o jsonpath='{.items[*].spec.containers[0].image}'`

## Configuration Comparison Checklist

When upgrading, verify these match `dify/docker/docker-compose.yaml`:

- [ ] API image version
- [ ] Web image version  
- [ ] Sandbox image version
- [ ] Plugin daemon image version
- [ ] Plugin daemon authentication keys (serverKey, difyApiKey)
- [ ] PostgreSQL password (if using embedded)
- [ ] Redis password (if using embedded)
- [ ] Storage configuration
- [ ] Resource limits (optional, but recommended to match)

## Version History

| Dify Version | API/Web Tag | Plugin Daemon Tag | Sandbox Tag | Notes |
|-------------|-------------|-------------------|-------------|-------|
| 1.11.2      | 1.11.2      | 0.5.2-local       | 0.2.12      | Current (matches docker-compose.yaml) |
| 1.10.1      | 1.10.1      | 0.5.2-local       | 0.2.12      | Previous |
| 1.4.1       | 1.4.1       | 0.1.1-local       | 0.2.10      | Has constant variable bug |

## References

- Official docker-compose.yaml: `dify/docker/docker-compose.yaml`
- Dify Helm Chart: https://borispolonsky.github.io/dify-helm
- Dify Documentation: https://docs.dify.ai

## Related Documentation

- [HTTPS Setup Guide](./HTTPS_SETUP_GUIDE.md) - HTTPS/TLS configuration
- [Docker Compose Comparison](./DOCKER_COMPOSE_COMPARISON.md) - Configuration alignment
- [Cost Estimation](./COST_ESTIMATION.md) - Cost breakdown and optimization
