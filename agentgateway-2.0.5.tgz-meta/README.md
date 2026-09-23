[![CircleCI](https://dl.circleci.com/status-badge/img/gh/giantswarm/agentgateway/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/giantswarm/agentgateway/tree/main)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/giantswarm/agentgateway/badge)](https://securityscorecards.dev/viewer/?uri=github.com/giantswarm/agentgateway)

# agentgateway

Giant Swarm packaging of the upstream [agentgateway](https://agentgateway.dev)
controller — the kgateway-based control plane plus data-plane proxy that fronts
MCP and agent traffic on the Giant Swarm Agent Platform.

This is a **vendored chart repo**: the upstream chart is pulled verbatim by
`vendir` and re-published, unmodified except for Giant Swarm defaults, to the
Giant Swarm app catalog (`gsoci.azurecr.io/charts/giantswarm`).

Since `2.0.0` the chart is **flattened**: the upstream files sit at the chart
root, so consumers set upstream keys at the top level (`controller.*`) with no
`agentgateway.*` nesting. See [UPGRADE.md](UPGRADE.md) to move from `1.x`. The
`1.x` line continues on the `release-1.x` branch.

## Layout

| Path | Contents |
|---|---|
| `helm/agentgateway/` | The published chart. Upstream files, vendored by `vendir` (pinned in `vendir.lock.yml`), plus the Giant Swarm delta re-applied by `sync/sync.sh`. Do not edit a vendored file by hand. |
| `helm/agentgateway/crds/` | The `agentgateway.dev` CRDs, vendored from the upstream `agentgateway-crds` chart. App-owned, see below. |
| `helm/agentgateway-crds/` | The same CRDs as a chart of their own, for consumers that let Helm own the CRD lifecycle. Install it *instead of* relying on the `crds/` dir above. Its `values.schema.json` is hand-written and permissive; the generated schema hook covers `helm/agentgateway` only. |
| `sync/` | The re-vendor entrypoint (`sync.sh`) and the Giant Swarm delta (`patches/`). |
| `diffs/` | Generated. One patch file per file we change, so a version bump shows the whole delta from upstream. |
| `vendor/` | Generated, git-ignored. The pristine upstream artifacts `diffs/` is measured against. |

## App-owned CRDs

The controller chart ships **no** CRDs. They live in this chart's `crds/`
directory, making agentgateway an **app-owned-CRDs** component: it owns its CRD
version and ships them alongside the app instead of via a separate CRD bundle.

Two consequences follow:

- Helm never upgrades `crds/`-dir CRDs on its own. The Giant Swarm agentic
  platform meta-package therefore applies this chart with Flux
  `crds: CreateReplace`, which replaces the live CRDs atomically on every
  release.
- The `AgentgatewayBackend` (~919 KB) and `AgentgatewayPolicy` (~645 KB) CRDs
  exceed the 256 KB client-side-apply limit, so server-side replace
  (`CreateReplace`) is the only viable delivery path.

Each vendored CRD carries `helm.sh/resource-policy: keep` (injected by
`make sync`). The annotation stops a `helm uninstall`/prune from
cascade-deleting every agentgateway custom resource in the cluster. The
`agentgateway-crds` chart is the alternative for consumers that want Helm to
own the CRD lifecycle; do not use both at once.

## Updating the upstream chart

Bump the two versions in `vendir.yml`, then:

```bash
make sync
```

`sync/sync.sh` fetches the pristine upstream artifacts into `vendor/`, flattens
them onto the two charts, re-applies the Giant Swarm delta from `sync/patches/`,
and rewrites `diffs/`.

Then read `diffs/helm__agentgateway__values.yaml.patch`. `values.yaml` is
repo-owned in full (it holds the Giant Swarm defaults, the Renovate markers and
the `# @schema` annotations), so a new upstream key does not arrive on its own:
port it into `sync/patches/values/values.yaml` and run `make sync` again.

`make verify-sync` fails the PR when the tree does not match what `make sync`
produces. CI runs it on every change under `helm/`, `sync/` or `vendir.yml`.

### The Giant Swarm delta

| Patch | What it does |
|---|---|
| `sync/patches/values/` | Copies the repo-owned `values.yaml` over the vendored one. |
| `sync/patches/chart-label/` | Strips trailing non-alphanumerics from the `helm.sh/chart` label. The label now carries our own chart version, and a branch build's long git-replaced version can otherwise truncate into an invalid label. |
| `sync/patches/team-label/` | Adds `application.giantswarm.io/team` to the upstream common-labels helper. app-build-suite's Giant Swarm validator (C0001) requires it in `templates/_helpers.tpl`, which the 1.x wrapper owned and the flattened chart takes from upstream. |
| `sync/patches/chart-yaml/` | Keeps both charts' `appVersion` in step with the vendored versions. |
| `sync/patches/crds/` | Writes the pristine CRDs into both delivery paths and injects `helm.sh/resource-policy: keep`. |

Each patch either copies a repo-owned file or asserts on the exact upstream text
it rewrites, so an upstream change that invalidates it fails `make sync` instead
of passing silently.

## Image tags

`appVersion` is the upstream release (`sync/patches/chart-yaml` keeps it in step
with `vendir.yml`), and the chart's own `version` is this repo's line. That is
what the two fields mean, and the chart jobs set architect's
`override_app_version: false` so app-build-suite does not stamp the chart
version over `appVersion` at package time. The generated chart jobs get it
through `gen.ci.keepChartAppVersion`; the `agentgateway-crds` jobs in
`.circleci/custom.yml` set it directly.

Both image tags are still pinned in `values.yaml` and bumped by Renovate from a
marker comment, rather than left to the `.Chart.AppVersion` fallback in the
upstream template. The pin is the explicit contract: it does not depend on a CI
parameter staying set, and `make verify-sync` keeps both tags equal to the
vendored version, so the tag and `appVersion` cannot drift apart.

The 1.x wrapper needed neither, because the fallback read the *subchart's*
`Chart.yaml`, which app-build-suite never rewrote. The flattened chart has only
one.
