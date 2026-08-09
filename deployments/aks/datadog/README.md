# Datadog log collection

Container log collection for Dify on AKS, via the Datadog Operator.

All commands are bash inside WSL — see [WSL.md](../../../WSL.md).

## What this does, and what it does not

```text
Dify containers -> stdout/stderr -> /var/log/pods -> node Agent -> Datadog
Dify OTLP traces -> Phoenix                              (unchanged)
Dify workflow/chat history -> PostgreSQL                  (unrelated)
```

The node Agent tails the container runtime logs that kubelet already writes under
`/var/log/pods` and already rotates. That means **no log PVC, no disk archival, and
no file logging inside Dify**.

Setting Dify's `LOG_FILE` would be actively wrong. In Dify 1.14.2,
`api/extensions/ext_logging.py` appends the stdout handler unconditionally and only
*adds* a `RotatingFileHandler` when `LOG_FILE` is set, so file logging duplicates
every line rather than replacing it.

The "Logs" screen inside Dify is a different thing again: workflow runs, node
executions, messages, conversations, and token usage stored in PostgreSQL. Datadog
does not replace or reduce those records, and database retention is a separate
piece of work.

## Deliberately switched off

| Feature | Why |
| --- | --- |
| `clusterChecks` | Collects no application logs; costs CPU on a 2 vCPU node |
| `orchestratorExplorer` | Collects no application logs, and adds a process-agent container to the DaemonSet |
| `apm` | Dify already exports OTLP traces to Phoenix. Datadog APM would duplicate transport and ship prompt/completion content to a third party — needs a privacy review first |

`admissionController` is left at its default (enabled), which is why
`DD_ADMISSION_CONTROLLER_ADD_AKS_SELECTORS=true` is set on the Cluster Agent.
Without it the webhook errors while reconciling against AKS-managed pods. Datadog
includes that variable in every AKS example regardless of enabled features.

## Resource budget

Both clusters are a single `Standard_D2s_v5`. Dev reports 1900m CPU and 5931580Ki
— that is **5792Mi**, not the 5929Mi you get by dividing by 1000 instead of 1024.
Everything outside the `dify` namespace (AKS system pods, ingress-nginx,
cert-manager) holds 1002m/1340Mi of it.

| | CPU requests | Memory requests |
| --- | --- | --- |
| node Agent | 150m | 256Mi |
| Cluster Agent | 100m | 256Mi |
| Operator | 50m | 128Mi |
| **Total** | **300m** | **640Mi** |

Dev only fits this after the resource trim in `../values.yaml`, which took Dify's
CPU requests from 775m to 500m and the node from 93% to 79% of allocatable requests.
UAT had ~348m spare and needed no trim.

The margin afterwards is thin, and worth stating plainly: the trim frees 398m but
the Agents reserve 300m, so dev settles at ~1802m/98m spare on CPU and ~5180Mi/612Mi
spare on memory. That is *less* free CPU than dev had before the trim. It fits
because `maxSurge: 0` means no Dify component ever needs room for a second pod —
removing those overrides and installing Datadog are mutually exclusive on this node.

The Operator chart ships `resources: {}`, so without `operator-values.yaml` the
Operator pod would run BestEffort — first to be evicted, and invisible to the
scheduler. That is why it is pinned explicitly.

## Install

`deploy.sh` handles this automatically whenever `DATADOG_API_KEY` is set, following
the same optional-feature pattern as `PHOENIX_OTLP_ENDPOINT`: no key means the
Datadog step is skipped and the environment is untouched.

In CI the key comes from a `DATADOG_API_KEY` **Environment secret** on `dev` and
`uat`, passed through `setup-aks` into the job environment — see
[GITHUB_ACTIONS.md](../GITHUB_ACTIONS.md#e-optional-datadog-log-collection). It is
never written to a values file or committed. Locally, export it in the shell before
running `deploy.sh`.

`deploy.sh` creates the Secret with `--from-file` rather than `--from-literal`, so
the key never appears in process arguments on the runner.

Manual equivalent, if you need to install outside the pipeline:

```bash
CTX=dify-aks-9764   # UAT: dify-uat-aks-1df2

kubectl --context "$CTX" create namespace datadog --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

printf '%s' "$DATADOG_API_KEY" > /tmp/api-key
kubectl --context "$CTX" -n datadog create secret generic datadog-secret \
  --from-file=api-key=/tmp/api-key --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -
rm -f /tmp/api-key

helm --kube-context "$CTX" repo add datadog https://helm.datadoghq.com
helm --kube-context "$CTX" repo update datadog
helm --kube-context "$CTX" upgrade --install datadog-operator datadog/datadog-operator \
  -n datadog --version 2.25.1 -f operator-values.yaml --create-namespace --wait

kubectl --context "$CTX" wait --for=condition=established --timeout=120s \
  crd/datadogagents.datadoghq.com

kubectl --context "$CTX" apply -f datadog-agent-dev.yaml
```

The `kubectl wait` matters: the `DatadogAgent` custom resource cannot be applied
until the Operator's CRD is established, and without the wait a fresh install
fails with `no matches for kind "DatadogAgent"`.

## Verify

```bash
CTX=dify-aks-9764

kubectl --context "$CTX" -n datadog get pods
kubectl --context "$CTX" -n datadog get datadogagent datadog -o yaml | tail -40
kubectl --context "$CTX" describe node | grep -A 12 Allocated
```

Expect one Operator pod, one node Agent pod, and one Cluster Agent pod. Then check
the Agent's own view of log collection:

```bash
AGENT=$(kubectl --context "$CTX" -n datadog get pods -l agent.datadoghq.com/component=agent -o name | head -1)
kubectl --context "$CTX" -n datadog exec "$AGENT" -c agent -- agent status
```

The `Logs Agent` section should list tailed files and report no errors. In the
Datadog UI, filter Logs by `cluster_name` — Dev and UAT must appear as separate
values, never merged.

## Pre-flight assumptions

Both clusters currently satisfy these; re-check after any AKS upgrade.

- **Kubelet serving certificate rotation is enabled.** Verify with
  `kubectl get nodes -L kubernetes.azure.com/kubelet-serving-ca`; the value must be
  `cluster`. If it is absent, the Agent cannot reach the kubelet and needs extra
  `global.kubelet.hostCAPath` configuration.
- **Agent version supports the cluster.** Kubernetes 1.33+ requires Agent 7.67.0+.
  Both clusters run 1.35.6.

## Removal

```bash
CTX=dify-aks-9764
kubectl --context "$CTX" delete -f datadog-agent-dev.yaml
helm --kube-context "$CTX" uninstall datadog-operator -n datadog
kubectl --context "$CTX" delete namespace datadog
```

Deleting the `DatadogAgent` resource alone is enough to stop all collection and
free the ~300m; the Operator is harmless on its own.

## Open items

- `containerCollectAll: true` collects every namespace. That is the deliberate
  starting point on a single-node cluster, but exclusions should be added from
  evidence once real log volume is visible.
- Unified service tagging is not configured yet. API, worker, and beat share one
  image, so without explicit `service` tags Datadog treats them as the same
  service.
- `LOG_OUTPUT_FORMAT=json` is not set yet on Dify. Until it is, tracebacks arrive
  as one event per line.
- Long-term retention belongs in a Datadog log archive to Azure blob storage, not
  on AKS disk.
