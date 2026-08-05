# Cost estimates

Current pricing comes from Infracost run against the tracked Terraform profiles.
Dated figures in older notes are not a deployment decision.

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

`infracost.yml` compares the tracked Dev, UAT, Lite Prod, and Full Prod profiles.
Provide dummy values for any required secret Terraform variables; they do not
affect the resource estimate. To estimate one profile only:

```bash
infracost breakdown --path . --terraform-var-file environments/uat.tfvars
```
