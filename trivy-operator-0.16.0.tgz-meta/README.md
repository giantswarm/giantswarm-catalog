[![CircleCI](https://circleci.com/gh/giantswarm/trivy-operator-app.svg?style=shield)](https://circleci.com/gh/giantswarm/trivy-operator-app)

# Trivy Operator

Giant Swarm offers an app for Aqua Security's [Trivy Operator][trivy-operator-upstream], which can be installed in workload clusters. It is part of our [managed security solution][managed-security], but can also be installed independently.

Trivy Operator is an in-cluster component which runs vulnerability scans, Kubernetes CIS and NSA benchmarks, and other types of policy and best practice validation scans using [Trivy][trivy-aqua]. It replaces a previous project, called [Starboard][starboard], which has now been fully deprecated along with our [Starboard App][starboard-app].

The results of these scans are saved in the cluster in the form of Kubernetes custom resources named `VulnerabilityReport`, `ConfigAuditReport`, and other types of reports.

Results of each scan type can be retrieved from the cluster, for example using `kubectl`:

```shell
$ kubectl get vulnerabilityreports
NAMESPACE   NAME    REPOSITORY   TAG   SCANNER   AGE
...
```

You can also export the data from these reports to Prometheus to use in alerts and Grafana dashboards using our [`starboard-exporter`][starboard-exporter].

This repository contains our packaging and Giant Swarm-specific configuration of the upstream charts.

## Installing

To install this app onto a workload cluster, deploy its chart with a Flux `HelmRelease` in your organization namespace on the management cluster, as explained in [Deploying an application via a Flux HelmRelease][helmrelease-guide]. The chart is published at `oci://gsoci.azurecr.io/charts/giantswarm/trivy-operator`.

The quickest way is [`kubectl gs deploy chart`][kubectl-gs-deploy-chart], which creates the `OCIRepository` and `HelmRelease` for you:

```shell
kubectl gs deploy chart \
  --chart-name trivy-operator \
  --organization ORGANIZATION \
  --target-cluster CLUSTER \
  --target-namespace NAMESPACE \
  --values-file values.yaml
```

If you still deploy this app with a Giant Swarm `App` resource, that API is deprecated. See [App Platform deprecation][app-platform-deprecation] for how to migrate to a `HelmRelease`.

### Scanning Backend

To perform vulnerability scans and produce reports, Trivy Operator needs a vulnerability scanner.

If deploying Trivy Operator as part of our managed security bundle, a Trivy server will be automatically installed for you.

If installing Trivy Operator independently, we recommend first installing our [Trivy app][trivy-app] in your cluster to serve as the vulnerability scanner for Trivy Operator, or using another existing Trivy instance.

Alternatively, you can configure Trivy Operator to use Standalone mode, which creates a new instance of the Trivy scanner per-scan. This is very inefficient and can lead to throttling by the backing vulnerability database. To do it anyway, set `trivy.mode` to `Standalone` in `values.yaml`.

In either case, please note that the Trivy version set by `trivy.imageRef` must be the same version as your Trivy backend (even if the actual image is not the same), as Trivy Operator uses that value internally to determine the API format to use for Trivy.

### Configuration

Set chart values inline in the `HelmRelease` under `spec.values`, or keep them in a `ConfigMap` or `Secret` in the same namespace and reference it from `spec.valuesFrom`. With `kubectl gs deploy chart`, use `--values-file` and `--values-from`, as described in its [configuration section][kubectl-gs-deploy-chart-config]. See the Flux [HelmRelease values reference][flux-helmrelease-values] for how values from several sources are merged.

The available values and their defaults are in [`helm/trivy-operator/values.yaml`](helm/trivy-operator/values.yaml).

## Credit

- [`trivy-operator`][trivy-operator-upstream]

[app-platform-deprecation]: https://docs.giantswarm.io/overview/fleet-management/app-management/app-platform-deprecation/
[flux-helmrelease-values]: https://fluxcd.io/flux/components/helm/helmreleases/#values
[helmrelease-guide]: https://docs.giantswarm.io/tutorials/fleet-management/app-platform/deploy-app-helmrelease/
[kubectl-gs-deploy-chart]: https://docs.giantswarm.io/reference/kubectl-gs/deploy-chart/
[kubectl-gs-deploy-chart-config]: https://docs.giantswarm.io/reference/kubectl-gs/deploy-chart/#configuration
[managed-security]: https://docs.giantswarm.io/overview/security/platform-security/
[starboard]: https://github.com/aquasecurity/starboard
[starboard-app]: https://github.com/giantswarm/starboard-app
[starboard-exporter]: https://github.com/giantswarm/starboard-exporter
[trivy-app]: https://github.com/giantswarm/trivy-app/
[trivy-aqua]: https://github.com/aquasecurity/trivy
[trivy-operator-upstream]: https://github.com/aquasecurity/trivy-operator
