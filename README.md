# Giant Swarm App Catalog

The public Helm chart repository for apps maintained by [Giant Swarm](https://www.giantswarm.io).

Source: [giantswarm/giantswarm-catalog](https://github.com/giantswarm/giantswarm-catalog)

<!-- Keep full URL links because GitHub Pages renders this README as the public page. -->

## Usage

[Helm](https://helm.sh) must be installed to use the charts.
Refer to the [Helm documentation](https://helm.sh/docs/) to get started.

### OCI Registry

Current charts are available as OCI artifacts on `gsoci.azurecr.io`.
Some older and deprecated charts are only in the HTTP registry.

```console
helm install RELEASE-NAME oci://gsoci.azurecr.io/charts/giantswarm/<chart-name>
```

### HTTP Registry

The catalog also serves the HTTP registry format.

```console
helm repo add giantswarm-catalog https://giantswarm.github.io/giantswarm-catalog
helm repo update
helm search repo giantswarm-catalog
helm install RELEASE-NAME giantswarm-catalog/<chart-name>
```

The full chart index is [index.yaml](https://giantswarm.github.io/giantswarm-catalog/index.yaml).

## Giant Swarm Platform

On the Giant Swarm platform, this catalog is available as the `giantswarm` catalog.
Refer to the [app management documentation](https://docs.giantswarm.io/overview/fleet-management/app-management/) to install apps from it.

## Contributing

CI publishes charts to this repository automatically.
Open changes in the source repository of each chart on [GitHub](https://github.com/giantswarm).
