[![CircleCI](https://dl.circleci.com/status-badge/img/gh/giantswarm/rancher-fleet/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/giantswarm/rancher-fleet/tree/main)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/giantswarm/rancher-fleet/badge)](https://securityscorecards.dev/viewer/?uri=github.com/giantswarm/rancher-fleet)

# rancher-fleet chart

Giant Swarm offers a rancher-fleet App which can be installed in workload clusters. It tracks the upstream [rancher-fleet](https://github.com/rancher/fleet) chart.

## Installing

When installing the chart, you **must** provide two values which are required for the app to work:

- the URL of the Kubernetes API of the cluster where the app will be installed.
- the CA bundle of the Kubernetes API of the cluster where the app will be installed.

These can be obtained from the cluster's kubeconfig file:

```bash
kubectl config view -o json --raw | jq -r '.clusters[0].cluster.server'
kubectl config view -o json --raw | jq -r '.clusters[0].cluster.["certificate-authority-data"]' | base64 --decode
```

The API URL should be provided as the `apiServerURL` value, and the CA bundle should be provided as the `apiServerCA` value.

See our [full reference on how to configure apps](https://docs.giantswarm.io/tutorials/fleet-management/app-platform/app-configuration/) for more details.

## Credit

- https://github.com/rancher/fleet
