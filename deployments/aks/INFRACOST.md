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

## Notes
- This config points to `dify-tf-aks` and uses env var files.
- Update `dify-tf-aks/environments/*.tfvars` before running for accurate results.
