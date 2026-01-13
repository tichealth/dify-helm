# Docker Compose vs Helm Configuration Comparison

This document compares the docker-compose.yaml configuration with the Helm chart configuration to identify any missing settings.

## Key Finding: Plugin Daemon Version

**Important**: The plugin daemon version was updated from `0.1.1-local` to `0.5.2-local` to match docker-compose.yaml. This is now aligned.

## Version Comparison (Dify 1.11.2)

| Component | docker-compose.yaml | Helm values.yaml | Status |
|-----------|---------------------|------------------|--------|
| API | `1.11.2` | `1.11.2` | ✅ Match |
| Web | `1.11.2` | `1.11.2` | ✅ Match |
| Sandbox | `0.2.12` | `0.2.12` | ✅ Match |
| Plugin Daemon | `0.5.2-local` | `0.5.2-local` | ✅ Match |

## Configuration Differences

### Plugin Daemon Authentication Keys

**docker-compose.yaml:**
- `SERVER_KEY`: `${PLUGIN_DAEMON_KEY:-lYkiYYT6owG+71oLerGzA7GXCgOT++6ovaezWAjpCjf+Sjc3ZtU+qUEi}`
- `DIFY_INNER_API_KEY`: `${PLUGIN_DIFY_INNER_API_KEY:-QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1}`

**Helm values.yaml:**
- `pluginDaemon.auth.serverKey`: `lYkiYYT6owG+71oLerGzA7GXCgOT++6ovaezWAjpCjf+Sjc3ZtU+qUEi`
- `pluginDaemon.auth.difyApiKey`: `QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1`

✅ **Status**: Keys match

### API Configuration

**docker-compose.yaml:**
- `INNER_API_KEY_FOR_PLUGIN`: `${PLUGIN_DIFY_INNER_API_KEY:-QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1}`
- `PLUGIN_DAEMON_URL`: `${PLUGIN_DAEMON_URL:-http://plugin_daemon:5002}`

**Helm chart:**
- Automatically set from `pluginDaemon.auth.difyApiKey` via credentials template
- Service name: `dify-plugin-daemon:5002`

✅ **Status**: Configuration is equivalent (Helm uses service names instead of container names)

## Known Issues

### 500 Error on Triggers Endpoint

**Issue**: `/console/api/workspaces/current/triggers` returns 500 errors when plugins don't have triggers.

**Root Cause**: This is a bug in Dify 1.11.2 API code - it doesn't handle 404 responses from plugin daemon gracefully.

**Impact**: 
- Errors are cosmetic - plugins still work for tools/models
- The triggers endpoint fails but doesn't affect core plugin functionality

**Note**: This issue exists in both docker-compose and Helm deployments when using Dify 1.11.2. If it's not occurring in your docker-compose setup, it may be because:
1. You haven't installed a plugin without triggers
2. The triggers endpoint isn't being called frequently
3. Different plugin versions behave differently

## Configuration Alignment Status

All critical configurations are now aligned between docker-compose.yaml and Helm values.yaml:

- ✅ Image versions match
- ✅ Plugin daemon version matches (0.5.2-local)
- ✅ Authentication keys match
- ✅ Service URLs configured correctly (Helm uses Kubernetes service names)

## Next Steps

1. **Monitor**: Watch for any other configuration differences
2. **Test**: Verify plugin functionality works as expected
3. **Report**: If the 500 error persists and differs from docker-compose behavior, check:
   - Plugin versions installed
   - Frequency of triggers endpoint calls
   - API logs for additional context

## References

- docker-compose.yaml: `dify/docker/docker-compose.yaml`
- Helm values.yaml: `dify-helm/deployments/aks/values.yaml`
- [Upgrade Guide](./UPGRADE_GUIDE.md) - Version upgrade procedures
- [HTTPS Setup Guide](./HTTPS_SETUP_GUIDE.md) - HTTPS/TLS configuration
