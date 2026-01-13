# Pod Status Summary

## Current Status (All Healthy ✅)

All pods in the `dify` namespace are Running and Ready:

| Pod Name | Status | Ready | Image | Notes |
|----------|--------|-------|-------|-------|
| dify-api-cdc75ccfc-d4xr7 | Running | ✅ | langgenius/dify-api:1.11.2 | Correct version |
| dify-beat-5cb779b94b-vqwvb | Running | ✅ | langgenius/dify-api:1.11.2 | Correct version |
| dify-plugin-daemon-757dc9f5f-nz7tv | Running | ✅ | langgenius/dify-plugin-daemon:0.5.2-local | **Updated to correct version** |
| dify-postgresql-primary-0 | Running | ✅ | docker.io/bitnamilegacy/postgresql:15.3.0-debian-11-r7 | Database |
| dify-postgresql-read-0 | Running | ✅ | docker.io/bitnamilegacy/postgresql:15.3.0-debian-11-r7 | Database replica |
| dify-proxy-79f4db97cc-2gbjm | Running | ✅ | nginx:latest | Nginx proxy |
| dify-redis-master-0 | Running | ✅ | docker.io/bitnamilegacy/redis:7.0.11-debian-11-r12 | Redis cache |
| dify-sandbox-5bcccdc7bb-6c2l6 | Running | ✅ | langgenius/dify-sandbox:0.2.10 | ⚠️ Shows 0.2.10 (values.yaml specifies 0.2.12 - requires helm upgrade) |
| dify-ssrf-proxy-5c5b9655b6-gsjqt | Running | ✅ | ubuntu/squid:latest | SSRF proxy |
| dify-web-6c7669df94-4lj9l | Running | ✅ | langgenius/dify-web:1.11.2 | Correct version |
| dify-worker-c5cc86696-s8dtf | Running | ✅ | langgenius/dify-api:1.11.2 | Correct version |

## Recent Changes

### Plugin Daemon Pod Update

**Status**: Successfully completed rolling update

**Timeline** (from events):
- 3m46s ago: Old pod `dify-plugin-daemon-6fc9d87d56-2vc2g` was terminated (part of rolling update)
- 3m40s ago: New pod `dify-plugin-daemon-757dc9f5f-nz7tv` was created
- 3m15s ago: New pod started successfully with image `langgenius/dify-plugin-daemon:0.5.2-local`

**Result**: ✅ Plugin daemon now running correct version (0.5.2-local) matching docker-compose.yaml

## Issues Found

### 1. Sandbox Image Version Mismatch

**Issue**: Sandbox pod shows image `0.2.10` but values.yaml specifies `0.2.12`

**Current State**: 
- Running pod: `langgenius/dify-sandbox:0.2.10`
- Expected: `langgenius/dify-sandbox:0.2.12` (per docker-compose.yaml)

**Impact**: Minor - may have bug fixes in 0.2.12

**Action**: Consider updating sandbox image if needed, but current deployment is functional

## No Error States

✅ **No pods in Error state**
✅ **No pods in CrashLoopBackOff**
✅ **No pods in Pending state**
✅ **No pods in ImagePullBackOff/ErrImagePull**
✅ **All pods are Ready (1/1)**

## Summary

- All 11 pods are Running and healthy
- Plugin daemon successfully updated to version 0.5.2-local
- No error states detected
- All critical components (API, Web, Worker, Plugin Daemon) are on correct versions
- One minor version mismatch: Sandbox showing 0.2.10 instead of 0.2.12 (non-critical)

## HTTPS Status

✅ **HTTPS is enabled and working**
- **Domain**: `dify-dev.tichealth.com.au`
- **Certificate**: Let's Encrypt (Production) - READY
- **Access**: `https://dify-dev.tichealth.com.au`

## Next Steps

1. ✅ Plugin daemon version is now correct - deployment is healthy
2. ✅ HTTPS is enabled and working
3. Optional: Update sandbox to 0.2.12 if needed (requires helm upgrade)
4. Continue monitoring for any new issues
