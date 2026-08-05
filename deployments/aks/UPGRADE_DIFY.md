# Upgrade Dify (application)

Application upgrades are a **values change plus a normal deploy** — never a
hand-rolled `helm upgrade`. `deploy.sh` pins the chart version, layers the
environment overlay, and injects secrets; running Helm directly skips all three.

For Kubernetes cluster upgrades see [UPGRADE_KUBERNETES.md](./UPGRADE_KUBERNETES.md).

## What controls the version

| Thing | Where | Current |
| --- | --- | --- |
| Helm chart | `DIFY_CHART_VERSION` in `deploy.sh` | `0.37.0` |
| API / Web image | `image.api.tag` / `image.web.tag` in `values.yaml` | `1.12.1` |
| Plugin daemon | `image.pluginDaemon.tag` in `values.yaml` | `0.5.3-local` |
| Sandbox | `image.sandbox.tag` in `values.yaml` | `0.2.12` |

Chart `0.37.0` advertises app `1.14.2`, but the AKS values deliberately pin
`1.12.1`. Chart bumps and image bumps are **separate, separately tested changes**.

## Upgrade procedure

### 1. Pick the target versions

Cross-check the tags against the upstream `dify/docker/docker-compose.yaml` for
the release you're moving to — the plugin daemon and sandbox tags must match the
API/Web version, or plugins fail to load.

### 2. Edit `values.yaml`

```yaml
image:
  api:
    tag: "<new-version>"
  web:
    tag: "<new-version>"
  sandbox:
    tag: "<matching-sandbox-tag>"
  pluginDaemon:
    tag: "<matching-plugin-tag>"
```

If the chart itself is moving, also update `DIFY_CHART_VERSION` in `deploy.sh`.

### 3. Deploy to UAT first

**Actions → Deploy or teardown Dify on AKS → Run workflow**, with
`environment: uat` and `deploy_mode: app`. Review the Helm diff in the plan job
before approving.

Local equivalent:

```bash
cd deployments/aks
./deploy.sh --app --auto-approve
```

### 4. Validate on UAT

```bash
kubectl get pods -n dify
kubectl get pods -n dify -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
kubectl logs -n dify -l app.kubernetes.io/component=api --tail=50 | grep -i error
```

Run the acceptance checklist in [DEPLOY_UAT.md](./DEPLOY_UAT.md#acceptance-checklist):
login, streaming chat, workflow execution, file upload, plugins, and a
knowledge-base index/retrieve.

### 5. Promote the same artifacts to Prod

Commit the values change, then run the workflow with `environment: lite-prod`
(or `prod-full`) and `deploy_mode: app`. Promote the **exact** versions accepted
in UAT — do not change tags between the two runs.

## Rollback

```bash
helm history dify -n dify
helm rollback dify <revision-number> -n dify
```

Then revert the `values.yaml` change in git so the next deploy doesn't
reintroduce the bad version.

Rollback only reverts the Kubernetes release. If the new version applied
database migrations, restore PostgreSQL from the pre-upgrade backup — always
take one before a major version jump.

## Things that bite

- **Plugin daemon mismatch.** The tag must match the API version's
  docker-compose pairing. A stale daemon causes 404s from the plugin endpoints.
- **Pods Pending on CPU.** Single-node clusters have little headroom during a
  rolling update. Check `kubectl describe nodes`; wait for old pods to terminate.
- **Storage classes.** API and plugin daemon need `azurefile` (ReadWriteMany);
  Redis uses the default class (ReadWriteOnce). Don't change these during an
  application upgrade.
- **Stale UI after upgrade.** Hard-refresh the browser before assuming the
  deploy failed; confirm with the pod-image command in step 4.

## Version history

| Dify | API/Web | Plugin daemon | Sandbox | Notes |
| --- | --- | --- | --- | --- |
| 1.12.1 | 1.12.1 | 0.5.3-local | 0.2.12 | Current (see `values.yaml`) |
| 1.11.2 | 1.11.2 | 0.5.2-local | 0.2.12 | Previous |
| 1.10.1 | 1.10.1 | 0.5.2-local | 0.2.12 | Older |
| 1.4.1 | 1.4.1 | 0.1.1-local | 0.2.10 | Has constant-variable bug |

## References

- Upstream compose file: `dify/docker/docker-compose.yaml`
- Chart repo: https://borispolonsky.github.io/dify-helm
- Dify docs: https://docs.dify.ai
