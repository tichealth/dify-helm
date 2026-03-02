# Documentation Index

Single index for Dify AKS deployment docs.

## Deploy and run

| Doc | Purpose |
|-----|--------|
| [README.md](./README.md) | Entry point, quick start, config files, verification |
| [PROD_DEPLOY.md](./PROD_DEPLOY.md) | Deploy: environments (dev, test, lite-prod, prod-full), local deploy, secrets, checklist |
| [DEPLOYMENT_MODES.md](./DEPLOYMENT_MODES.md) | `deploy.sh` modes: `--all`, `--app`, `--db` and when to use them |
| [LITE_PROD_VS_PROD.md](./LITE_PROD_VS_PROD.md) | Lite prod vs full prod: cost, scalability, migration (no data loss) |
| [TEARDOWN_AND_REDEPLOY.md](./TEARDOWN_AND_REDEPLOY.md) | Teardown and full redeploy steps |
| [GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md) | GitHub Secrets for the deploy/teardown workflow |

## Operations and troubleshooting

| Doc | Purpose |
|-----|--------|
| [OPERATIONS.md](./OPERATIONS.md) | How to get: PostgreSQL FQDN, Dify endpoint (IP/domain), Azure Blob key |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Stuck deployment and DNS (NXDOMAIN) fixes |
| [HTTPS_SETUP_GUIDE.md](./HTTPS_SETUP_GUIDE.md) | HTTPS/TLS setup, cert-manager, DNS |

## Infrastructure and cost

| Doc | Purpose |
|-----|--------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Architecture (Azure, AKS, Dify), environment comparison |
| [COST_SUMMARY_2026-01-24.md](./COST_SUMMARY_2026-01-24.md) | Monthly cost estimates (Dev/Test/Prod) |
| [COST_OPTIMIZATIONS_2026-01-24.md](./COST_OPTIMIZATIONS_2026-01-24.md) | Cost optimization ideas |
| [INFRACOST.md](./INFRACOST.md) | Run Infracost for exact cost from Terraform |

## PostgreSQL and advanced

| Doc | Purpose |
|-----|--------|
| [POSTGRESQL_ARCHITECTURE.md](./POSTGRESQL_ARCHITECTURE.md) | PostgreSQL: in-cluster vs Azure Flexible |
| [POSTGRESQL_CONFIGURATION.md](./POSTGRESQL_CONFIGURATION.md) | PostgreSQL configuration options |
| [MIGRATION_TO_PRIVATE_SUBNET.md](./MIGRATION_TO_PRIVATE_SUBNET.md) | Moving PostgreSQL to private subnet (VNet) |
| [MANAGEMENT_SUBNET_GUIDE.md](./MANAGEMENT_SUBNET_GUIDE.md) | Management subnet, jumpbox, DB access |

## Upgrade and reference

| Doc | Purpose |
|-----|--------|
| [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md) | Upgrading Dify versions on AKS |
| [DOCKER_COMPOSE_COMPARISON.md](./DOCKER_COMPOSE_COMPARISON.md) | Helm vs docker-compose config alignment |
| [CHANGELOG.md](./CHANGELOG.md) | Deployment changes over time |
| [CHANGES_TO_PROPAGATE.md](./CHANGES_TO_PROPAGATE.md) | Checklist: propagate dev changes to test/prod |

## Quick reference

- **Deploy:** `./deploy.sh` or `./deploy.sh --app --auto-approve` — see [DEPLOYMENT_MODES.md](./DEPLOYMENT_MODES.md).
- **Env files:** `environments/dev.tfvars`, `environments/test.tfvars`, `environments/lite-prod.tfvars`, `environments/prod-full.tfvars` — secrets via [GITHUB_ACTIONS_SECRETS.md](./GITHUB_ACTIONS_SECRETS.md) or local `terraform.tfvars`.
- **Stuck or DNS:** [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
- **Endpoints/keys:** [OPERATIONS.md](./OPERATIONS.md).
