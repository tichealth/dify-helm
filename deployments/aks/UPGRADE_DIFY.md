# Upgrade Dify (application)

Application upgrades are a **values change plus a normal deploy** — never a
hand-rolled `helm upgrade`. `deploy.sh` pins the chart version, layers the
environment overlay, and injects secrets; running Helm directly skips all three.

For Kubernetes cluster upgrades see [UPGRADE_KUBERNETES.md](./UPGRADE_KUBERNETES.md).

## What controls the version

| Thing | Where | Dev / UAT / Prod |
| --- | --- | --- |
| Helm chart | `DIFY_CHART_VERSION` in `deploy.sh` | `0.37.0` |
| API / Web image | `image.api.tag` / `image.web.tag` | `1.14.2` |
| Plugin daemon | `image.pluginDaemon.tag` | `0.6.1-local` |
| Sandbox | `image.sandbox.tag` | `0.2.15` |

Chart bumps and image bumps are **separate, separately tested changes**.

A version being staged is pinned in `values-uat.yaml`; the settled version lives
in `values.yaml`. Both files are passed to Helm with the overlay last, so the
overlay wins for UAT only. Keeping a staged version out of `values.yaml` is what
stops an unrelated dev or prod deploy from picking it up by accident.

The four image tags move **as a set**. They are the pairing published in the
matching `dify/docker/docker-compose.yaml`, and a plugin daemon that doesn't
match the API version returns 404 from the plugin endpoints.

## Upgrade procedure

### 1. Pick the target versions

Cross-check the tags against the upstream `dify/docker/docker-compose.yaml` for
the release you're moving to — the plugin daemon and sandbox tags must match the
API/Web version, or plugins fail to load.

Prefer a target the **released** chart already supports. Check what the chart's
own defaults are before inventing a pairing: if they match the compose file for
your target, the upgrade needs no chart change at all, which removes an entire
class of risk. Only reach for an unreleased chart when the target genuinely
needs template changes that no tag contains.

### 2. Stage the versions in `values-uat.yaml`

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
That one is global — `deploy.sh` is shared by every environment — so a chart bump
cannot be staged in UAT the way image tags can. Land it in its own change.

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

### 5. Rehearse the migrations against real data

A greenfield UAT runs migrations against an empty schema, which proves nothing
about Dev and Prod. Restore a Dev PostgreSQL snapshot into the UAT server, point
UAT at it, and run the upgrade again. This is where a multi-release jump will
fail if it is going to.

### 6. Promote to Dev, then Prod

Move the `image:` block out of `values-uat.yaml` into `values.yaml` and commit —
that is the promotion. Take a PITR restore point first, then run the workflow
with `deploy_mode: app` for Dev, validate, then `lite-prod` (or `prod-full`).

Promote the **exact** versions accepted in UAT; do not change tags between runs.

## Rollback

```bash
helm history dify -n dify
helm rollback dify <revision-number> -n dify
```

Then revert the tag change in git — in `values-uat.yaml` if the version is still
staged, in `values.yaml` if it was already promoted — so the next deploy doesn't
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
- **`--atomic --wait --timeout 45m`.** If any pod never goes Ready, the whole
  release rolls back — but only after burning up to 45 minutes first.

## Version history

| Dify | API/Web | Plugin daemon | Sandbox | Notes |
| --- | --- | --- | --- | --- |
| 1.14.2 | 1.14.2 | 0.6.1-local | 0.2.15 | Live in `values.yaml`; chart `0.37.0`; compose pairing from tag `1.14.2` |
| 1.12.1 | 1.12.1 | 0.5.3-local | 0.2.12 | Previous |
| 1.11.2 | 1.11.2 | 0.5.2-local | 0.2.12 | Previous |
| 1.10.1 | 1.10.1 | 0.5.2-local | 0.2.12 | Older |
| 1.4.1 | 1.4.1 | 0.1.1-local | 0.2.10 | Has constant-variable bug |

## Looking further ahead: Dify 1.16.x

Dify 1.16.1 needs chart changes that **no released chart tag contains**. They are
merged on upstream `master` but unreleased, and `Chart.yaml` there still claims
`0.37.0` / appVersion `1.14.2`. Wait for upstream to cut a tag rather than
deploying its `master`. When that tag lands, expect to handle:

- **`pluginDaemon.auth.difyApiKey` moved to `api.auth.internalApiKey`.** Neither
  chart's `values.schema.json` rejects unknown keys, so the old path in
  `deploy.sh` and `values.yaml` will be **silently ignored** and the key falls
  back to the chart's published default. No error, no failed deploy.
- **`agentBackend` and `localSandbox` default to `enabled: true`.** Two extra
  Deployments with no resource requests. The chart also omits the Squid forward
  proxy that upstream's compose file puts in front of the sandbox, so enabling it
  as shipped puts a code-execution sandbox on the flat pod network. Set both to
  `false` unless Agent v2 is being adopted deliberately.
- **Image pairing** for 1.16.1 is api/web `1.16.1`, sandbox `0.2.15`, plugin
  daemon `0.6.3-local`.

## References

- Upstream compose file: `dify/docker/docker-compose.yaml`
- Chart repo: https://borispolonsky.github.io/dify-helm
- Dify docs: https://docs.dify.ai
