#!/usr/bin/env bash
# Generate cryptographically secure values for GitHub Actions Secrets.
# Run from repo root or from deployments/aks. Copy output into GitHub Secrets.
# Requires: openssl
#
# If you see "/usr/bin/env: 'bash\r': No such file or directory", the file has
# Windows line endings. Either run:  bash generate-secrets.sh
# or fix once:  sed -i 's/\r$//' generate-secrets.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "# Copy each value into GitHub: Settings → Secrets and variables → Actions → Secrets"
echo "# Do not commit this output."
echo ""
echo "DIFY_SECRET_KEY=$(openssl rand -base64 42 | tr -d '\n')"
echo "POSTGRESQL_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')"
echo "REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')"
echo "QDRANT_API_KEY=$(openssl rand -hex 32)"
echo ""
echo "# Optional: Azure Blob account key is from Azure (Storage Account → Access keys)."
echo "# AZURE_BLOB_ACCOUNT_KEY=..."
