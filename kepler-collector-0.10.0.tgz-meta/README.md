# kepler-collector

A Kubernetes CronJob that turns capa e2e test failures into Mimir metrics and Loki logs for failure-triage dashboards.

## What it does

`kepler-collector` runs on Giant Swarm's CI/CD workload cluster (`gazelle-cicdprod`), where Tekton runs the `cluster-test-suites` e2e pipeline. On a schedule, it:

1. **Discovers** new capa crust-gather archives pushed to the registry after a failed e2e run (each failure produces a pair of archives: one snapshot of the ephemeral test workload cluster, one of the management cluster).
2. **Extracts** the cluster evidence from each archive pair — events, pod statuses, CAPI/CAPA conditions, controller logs — and builds a short, stable failure fingerprint from it.
3. **Classifies** the failure against a set of deterministic rules (no LLM anywhere in this pipeline) to attribute it to a symptom family and a suggested team.
4. **Emits** one record per failure to two places in a single pass: counters/gauges to **Mimir** for dashboard charts and alerts, and one detailed JSON line to **Loki** for the drill-down table.
5. Separately, reads **Tekton** PipelineRun/TaskRun data from the local Kubernetes API to compute denominators — so the dashboard can show failure *rates*, not just raw counts, plus a coverage ratio (failed runs with no matching archive, usually a teardown failure).

It's a single reconcile pass per invocation, not a long-running service — the Kubernetes CronJob provides the scheduling.

A few fixed design principles run through this implementation: exactly one record per failed provider/suite combo; idempotent processing (dedup on `wc_name` plus a stable failure signature, so a CronJob retry never double-counts); metric labels are kept to a small, fixed set of values — anything that could be almost any value (a signature, a run ID, raw error text) goes in the Loki line, never on a metric; and archives are processed one at a time, preferring to serve them directly from the registry over pulling a copy to disk.

## Status

Actively under development, built out task by task:

| Task | Status |
| --- | --- |
| Repo scaffold & config | Done |
| Access archives | Done (one known limitation, see below) |
| Extract + classify | Done (two known limitations, see below) |
| Emit metrics + logs | Done (package + tests) |
| Tekton denominators | Done (one known limitation, see below) |
| Wire failure pipeline (`main.go`) | Done (one known limitation, see below) |
| Wire Tekton denominators (`main.go`) | Done (one known limitation, see below) |

**Known limitations:**

- The archive pull-fallback path (used only when serving directly from the registry fails) doesn't currently produce a working client once serving a real pulled archive locally — see [`docs/pull-fallback-investigation.md`](docs/pull-fallback-investigation.md) for the full investigation. The primary path (serving directly from the registry) is unaffected and confirmed working against real archives.
- Controller ERROR/WARN log lines and MC bootstrap phase (`kind→flux→pivot→app`) aren't implemented yet — both need a failed-bootstrap archive to discover concrete markers against, and today's test suites only exercise WC cluster creation. See [`internal/extract/README.md`](internal/extract/README.md).
- `e2e_snapshot_coverage_ratio` is wired and emitted, but only as a coarse per-run ratio (this run's newly-discovered archive count divided by this run's newly-discovered failed-run count) — the exact per-run "gap" set (which specific failed run has no matching archive) isn't computed, since a Tekton TaskRun carries no archive `wc_name` to join on. See [`internal/tekton/README.md`](internal/tekton/README.md) and [`internal/emit/README.md`](internal/emit/README.md).
- Both pipelines (`main.go`'s `runFailurePipeline` and `runTektonPipeline`) are wired and tested against fakes at every external seam (registry, `crust-gather`, cluster access, Tekton API, emit), but haven't yet been run end-to-end against a real `crust-gather` binary or real cluster — that's the manual acceptance step, still open.
- **Resolved (2026-07-06):** the Atlas team (owners of the shared `alloy-events` OTLP pipeline) confirmed `OTLP_TENANT=giantswarm` is the correct tenant, and that `provider`/`classification` landing as Loki structured metadata rather than true index labels is fine as-is — no `loki-runtime` config change needed. `helm/kepler-collector/values.yaml`'s `config.otlpTenant` now defaults to `giantswarm` accordingly. Still not yet confirmed: an actual end-to-end run against the real `otlp-gateway` with this tenant — every real archive processed so far was emitted through `cmd/debugotlp` (a local stand-in), not the real gateway, since the tenant wasn't confirmed at the time. A direct Loki query for tenant `giantswarm` still shows zero ingested lines as of this writing.

## How it works

```text
internal/
  config/    env-var configuration, fails fast on anything required but unset
  record/    the shared Record type every other package produces/consumes
  archive/   discovers new capa archive pairs, serves them via crust-gather, tracks a watermark
  extract/   turns a served archive pair into a fully populated Record
  classify/  applies YAML rules to attribute a Record's classification/team
  emit/      sends a Record to Mimir (metrics) and Loki (logs) over OTLP, plus Tekton denominators
  tekton/    reads capa TaskRuns to capture per-run outcome/duration/trigger-source data
```

`main.go` and three files at the repo root wire these packages into the actual reconcile loop:

- `pipeline.go`'s `runFailurePipeline` discovers new archive pairs and runs each through serve → extract → classify → emit.
- `tekton_pipeline.go`'s `runTektonPipeline` lists new capa Tekton run outcomes, emits `e2e_capa_runs_total` for each, and sets the two per-run gauges (`e2e_distinct_signatures`, `e2e_snapshot_coverage_ratio`) from the failure pipeline's batch.
- `reconcile.go`'s `runReconcile` runs both of the above independently in one invocation - a total failure in one (e.g. registry unreachable) doesn't stop the other from running, since neither depends on the other's success.
- `pipeline.go`'s `run` guarantees the emitter is shut down exactly once regardless of how the run ends.

Every external dependency (registry, `crust-gather`, cluster access, the Tekton API, the emitter) is injected as a function/narrow interface, so all of this orchestration logic has its own tests that don't need a live registry, cluster, or `crust-gather` binary.

`internal/archive` shells out to the [`crust-gather`](https://github.com/crust-gather/crust-gather) binary (a Rust `kubectl` plugin, not a Go library) to serve an archive as a Kubernetes-API-compatible server, then talks to it with plain `client-go` — the same code path whether serving directly from the registry or from a locally pulled fallback copy.

## Requirements

- Go 1.26+
- [`crust-gather`](https://github.com/crust-gather/crust-gather) on `PATH` for anything that touches `internal/archive` beyond its unit tests (see `docs/pull-fallback-investigation.md` for how to install it)
- Docker, for building the deployable image

## Configuration

All configuration is via environment variables (`internal/config`). Anything not yet confirmed for the target environment has no default and fails startup fast rather than silently guessing.

| Variable | Default | Required |
| --- | --- | --- |
| `REGISTRY_REPO` | `crustgatherci.azurecr.io/snapshots` | |
| `OCI_AUTH_USERNAME` | — | Yes |
| `OCI_AUTH_PASSWORD` | — | Yes |
| `OTLP_ENDPOINT` | `http://otlp-gateway.kube-system.svc:4318` | |
| `OTLP_TENANT` | — | Yes |
| `POLL_INTERVAL` | `20m` | |
| `WATERMARK_CONFIGMAP_NAME` | — | Yes |
| `WATERMARK_CONFIGMAP_NAMESPACE` | — | Yes |
| `RULES_FILE` | — | Yes |
| `TEKTON_NAMESPACE` | `tekton-pipelines` | |
| `MC_NAME` | — (fallback only, see `internal/config/README.md`) | |
| `TEKTON_WATERMARK_CONFIGMAP_NAME` | — | Yes |

`RULES_FILE` points at a YAML file of ordered, first-match-wins classification rules — see [`internal/classify/README.md`](internal/classify/README.md) for the full format, and [`internal/classify/testdata/rules.yaml`](internal/classify/testdata/rules.yaml) for a working example.

## Building and running

```bash
make build   # local binary
make test    # unit tests
make lint    # golangci-lint (gosec + goconst enabled)
make run     # go run . (still requires the required env vars above)
```

Or via Docker:

```bash
docker build -t kepler-collector .
docker run --rm \
  -e OCI_AUTH_USERNAME=... -e OCI_AUTH_PASSWORD=... -e OTLP_TENANT=... \
  -e WATERMARK_CONFIGMAP_NAME=... -e WATERMARK_CONFIGMAP_NAMESPACE=... \
  -e TEKTON_WATERMARK_CONFIGMAP_NAME=... -e MC_NAME=... \
  -e RULES_FILE=/etc/kepler-collector/rules.yaml \
  kepler-collector
```

The image is a multi-stage build: the compiled Go binary plus a pinned `crust-gather` release, both installed into a `debian:bookworm-slim` runtime image, running as a non-root user (UID 1000) — `gazelle-cicdprod` enforces strict Pod Security Standards via Kyverno (confirmed live), which requires this.

## CI

The workflows under [`.github/workflows/`](.github/workflows/) (`zz_generated.*`) are generated by [`devctl`](https://github.com/giantswarm/devctl), Giant Swarm's standard repo-boilerplate generator — pre-commit checks, changelog/semantic-PR-title validation, dependency vulnerability fixes, secret scanning, an OSSF Scorecard run, a Helm values schema check, and release creation. They're regenerated by re-running `devctl gen`, not hand-edited.

## Logging

Structured JSON via [`micrologger`](https://github.com/giantswarm/micrologger) (+ [`microerror`](https://github.com/giantswarm/microerror) for error wrapping) — the standard across Giant Swarm's Go services. Not the standard library `log` package.

## Deployment

See [`helm/kepler-collector/`](helm/kepler-collector/) — the CronJob, ServiceAccount, and RBAC for reading Tekton PipelineRuns/TaskRuns and writing the watermark ConfigMaps.

**Optional first-deploy step: seed the watermark ConfigMaps.** Both watermarks (`WATERMARK_CONFIGMAP_NAME` for archives, `TEKTON_WATERMARK_CONFIGMAP_NAME` for Tekton runs) start out unset, and an unset watermark treats *everything currently in the registry/cluster* as new. On the very first run ever, that means a one-time backlog burst — every pre-existing archive and Tekton TaskRun gets counted as if it just happened now, rather than only genuinely new failures going forward. Every run after the first is unaffected (each watermark only ever looks at what's newer than its own last-saved position). If that first-run burst isn't acceptable, pre-create both ConfigMaps with a `LastCreated` of "now" before the CronJob's first scheduled run, so the collector only starts counting from deploy time forward.
