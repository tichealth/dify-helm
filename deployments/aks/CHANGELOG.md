# Changelog

## 2026-01-13 - HTTPS Enabled

### Added
- ✅ HTTPS/TLS enabled with Let's Encrypt certificates
- ✅ nginx-ingress controller installed
- ✅ cert-manager installed and configured
- ✅ CoreDNS configured to use external DNS servers (8.8.8.8, 1.1.1.1)
- ✅ Ingress resource configured for `dify-dev.tichealth.com.au`
- ✅ Certificate auto-renewal enabled

### Changed
- Service type changed from `LoadBalancer` to `ClusterIP` (Ingress handles external access)
- CoreDNS forward DNS changed from `/etc/resolv.conf` to external DNS servers
- `values.yaml` updated with ingress configuration

### Documentation
- Consolidated all HTTPS-related documentation into `HTTPS_SETUP_GUIDE.md`
- Updated `README.md` with current HTTPS status
- Updated `COST_ESTIMATION.md` to include HTTPS costs
- Created `DOCUMENTATION_INDEX.md` for easy navigation
- Removed redundant documentation files (7 files consolidated)

### Current Status
- **Domain**: `dify-dev.tichealth.com.au`
- **Certificate**: Let's Encrypt (Production) - READY
- **Valid Until**: April 13, 2026
- **Auto-renewal**: Enabled

## 2026-01-13 - Plugin Daemon Upgrade

### Changed
- Plugin daemon version upgraded from `0.1.1-local` to `0.5.2-local`
- Matches docker-compose.yaml version for Dify 1.11.2

## 2026-01-13 - Dify Version Upgrade

### Changed
- Dify API/Web upgraded from `1.4.1` to `1.11.2`
- Sandbox upgraded to `0.2.12` (values.yaml)
- Fixed timezone parameter bug in workflow tools

### Fixed
- Timezone parameter validation bug (constant type variables)
- Storage class configuration for ReadWriteMany volumes
- Plugin daemon version compatibility
