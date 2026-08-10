# Teardown

Destroys an entire environment: AKS cluster, PostgreSQL server and all its data,
PVCs, LoadBalancer IPs, and the resource group when Terraform owns it.

> **This deletes data.** Take a PostgreSQL logical backup (`dify` and
> `dify_plugin`) and export anything you need from the app first. Terraform
> destroy is not reversible from state.

To rebuild afterwards, follow [README.md](./README.md#deploy) — or
[DEPLOY_UAT.md](./DEPLOY_UAT.md) if the backend and GitHub Environment also need
recreating.

## Preferred: the workflow

**Actions → Deploy or teardown Dify on AKS → Run workflow**

- `enabled`: checked
- `action`: `teardown`
- `environment`: the environment to destroy

Review the destroy plan before approving. Confirm the state key and resource
group match the environment you intended — this is the step that prevents
destroying Prod from a Dev-shaped run.

## Local fallback

`teardown.sh` uninstalls the Helm releases and runs `terraform destroy` against
whichever backend `backend.azurerm.tfvars` points at.

```bash
cd deployments/aks
cp environments/<environment>.tfvars terraform.tfvars
# Point backend.azurerm.tfvars at the matching state key.
az login
./teardown.sh              # add --auto-approve to skip the prompt
```

Verify the backend key before running. `teardown.sh` destroys whatever state it
initialises against, not whatever you last deployed.

## Verify it's gone

```bash
helm list -A
az group list --query "[?contains(name, 'dify')].{Name:name, Location:location}" -o table
```

Terraform does not delete a resource group it didn't create (Prod uses the
pre-existing `rg-cme-prod`). Remove leftovers explicitly if required:

```bash
az group delete --name <resource-group-name> --yes --no-wait
```

## After a rebuild

- The ingress LoadBalancer IP **changes**. Update the DNS A record for the
  environment hostname, then wait for cert-manager to reissue.
- Wait times: NSG rules 1-2 min, DNS propagation 5-10 min, certificate 2-5 min.
- `deploy.sh` applies NSG rules automatically (it runs `fix-nsg-rules.sh`).

If teardown itself fails, see
[TROUBLESHOOTING.md](./TROUBLESHOOTING.md#7-terraform-destroy-fails).
