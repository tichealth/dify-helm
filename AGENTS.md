# Working conventions

## Shell

Use **WSL bash** for everything. The Windows shell here is an old PowerShell that
doesn't accept `&&` as a separator, and `helm`, `kubectl`, and the `deploy.sh`
toolchain are installed inside WSL, not on the Windows PATH.

```bash
bash -lc '<command>'
```

Repo path inside WSL is `/mnt/c/Vivek/TicHealth/dify-helm`.

Quoting nests badly when a complex command is passed from PowerShell through to
bash. If a one-liner starts fighting the quoting, write the script to `/tmp` and
run it from there rather than escaping harder.

## Never write scratch files into the working tree

Verification scripts, rendered manifests, diffs, and logs go in `/tmp`. They must
not be created inside the repo, even with the intent of deleting them afterwards
— a run that fails partway leaves them behind, and some land in paths `.gitignore`
doesn't cover.

## Verifying chart changes without deploying

`deploy.sh` installs the **published** chart from
`https://borispolonsky.github.io/dify-helm`, pinned by `DIFY_CHART_VERSION`. The
`charts/` directory in this repo is the upstream fork and is *not* what gets
deployed. To check a values change, render the released chart that the target
environment actually uses:

```bash
bash -lc '
set -e
rm -rf /tmp/cc && mkdir -p /tmp/cc
cd /mnt/c/Vivek/TicHealth/dify-helm
git archive dify-0.37.0 charts/dify | tar -x -C /tmp/cc
mkdir -p /tmp/cc/charts/dify/charts
cp charts/dify/charts/*.tgz /tmp/cc/charts/dify/charts/

cd deployments/aks
helm template dify /tmp/cc/charts/dify \
  -f values.yaml -f values-uat.yaml \
  --set externalPostgres.address=pg.example.com \
  > /tmp/render-uat.yaml
grep -oE "langgenius/[a-z-]+:[^\"]+" /tmp/render-uat.yaml | sort -u
'
```

Render **both** with and without the environment overlay. The overlay is how a
version is staged in one environment, so the point of the check is confirming
that the other environments did *not* move.

The subchart `.tgz` files under `charts/dify/charts/` are gitignored. If they're
absent, `helm dependency build charts/dify` fetches them per `Chart.lock`.

Also run `bash -n deployments/aks/deploy.sh` after editing the deploy script.
It's `set -euo pipefail`, so a reference to a variable that no longer exists
fails the deploy at runtime rather than at parse time.
