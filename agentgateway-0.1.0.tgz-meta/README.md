[![CircleCI](https://dl.circleci.com/status-badge/img/gh/giantswarm/agentgateway/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/giantswarm/agentgateway/tree/main)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/giantswarm/agentgateway/badge)](https://securityscorecards.dev/viewer/?uri=github.com/giantswarm/agentgateway)

# agentgateway

Giant Swarm packaging of the upstream [agentgateway](https://agentgateway.dev)
controller — the kgateway-based control plane plus data-plane proxy that fronts
MCP and agent traffic on the Giant Swarm agentic platform.

This is a **vendored chart repo**: the upstream chart is pulled verbatim by
`vendir` and re-published, unmodified except for Giant Swarm defaults, to the
Giant Swarm app catalog (`gsoci.azurecr.io/charts/giantswarm`).

## Layout

| Path | Contents |
|---|---|
| `helm/agentgateway/` | Wrapper chart. Adds Giant Swarm defaults (gsoci-mirrored images, restricted-PSS security contexts) on top of the vendored upstream chart. |
| `helm/agentgateway/charts/agentgateway/` | Upstream controller chart, vendored by `vendir` (pinned in `vendir.lock.yml`). Do not edit by hand — run `make sync`. |
| `helm/agentgateway/crds/` | The `agentgateway.dev` CRDs (`AgentgatewayBackend`, `AgentgatewayPolicy`, `AgentgatewayParameters`), vendored from the upstream `agentgateway-crds` chart. |

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
cascade-deleting every agentgateway custom resource in the cluster.

## Updating the upstream chart

```bash
make sync
```

This runs `vendir sync` (re-vendors the controller chart and CRDs at the
versions pinned in `vendir.lock.yml`) and re-injects the
`helm.sh/resource-policy: keep` annotation into each CRD. Bump the pinned
versions in `vendir.yml`, run `make sync`, then `cd helm/agentgateway &&
helm dependency update` to refresh `Chart.lock`.
