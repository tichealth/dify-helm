# Infracost Usage

Location: `dify-helm/deployments/aks`

## Setup
1. Install Infracost CLI: https://www.infracost.io/docs/
2. Set your API key:

```bash
export INFRACOST_API_KEY="<your_api_key>"
```

## Run cost estimates

From `dify-helm/deployments/aks`:

```bash
infracost breakdown --config-file infracost.yml
```

To save a report:

```bash
infracost breakdown --config-file infracost.yml --out-file infracost-report.json
```

## Configuration

The `infracost.yml` is self-contained and points to this directory:
- **Dev**: Uses `terraform.tfvars` (git-ignored, contains actual values)
- **Test/Prod**: Uses example files from `environments/*.tfvars.example`

For accurate test/prod estimates, create actual tfvars files:
```bash
cp environments/test.tfvars.example environments/test.tfvars
cp environments/prod.tfvars.example environments/prod.tfvars
# Then fill in real values (these files should be git-ignored)
```

Then update `infracost.yml` to use the actual files instead of `.example` files.
