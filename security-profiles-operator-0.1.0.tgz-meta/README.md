[![CircleCI](https://dl.circleci.com/status-badge/img/gh/giantswarm/security-profiles-operator-app/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/giantswarm/security-profiles-operator-app/tree/main)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/giantswarm/security-profiles-operator-app/badge)](https://securityscorecards.dev/viewer/?uri=github.com/giantswarm/security-profiles-operator-app)

# security-profiles-operator

Giant Swarm offers a [security-profiles-operator](https://github.com/kubernetes-sigs/security-profiles-operator) App which can be installed in workload clusters.
Here, we define the security-profiles-operator chart with its templates and default configuration.

The Security Profiles Operator (SPO) is a Kubernetes controller that lets you manage Linux security profiles (Seccomp, AppArmor, and SELinux) as native Kubernetes custom resources. Instead of configuring nodes manually or baking profiles into images, you declare a `SeccompProfile`, `AppArmorProfile`, or `SELinuxProfile` and the operator distributes and enforces it across your cluster. This chart currently focuses on SELinux support.

## Installing

There are several ways to install this app onto a workload cluster.

- [Using GitOps to instantiate the App](https://docs.giantswarm.io/tutorials/continuous-deployment/apps/add-appcr/)
- By creating an [App resource](https://docs.giantswarm.io/reference/platform-api/crd/apps.application.giantswarm.io) using the platform API as explained in [Getting started with App Platform](https://docs.giantswarm.io/tutorials/fleet-management/app-platform/).

## Configuring

### values.yaml

**This is an example of a values file you could upload using our web interface.**

```yaml
# values.yaml

kyvernoPolicyExceptions:
  enabled: true

security-profiles-operator:
  selinux:
    enable: true
```

### Sample App CR and ConfigMap for the management cluster

If you have access to the Kubernetes API on the management cluster, you could create the App CR and ConfigMap directly.

See our [full reference on how to configure apps](https://docs.giantswarm.io/tutorials/fleet-management/app-platform/app-configuration/) for more details.

## Limitations

- SELinux `ProfileRecording` requires `auditd` to be running and logging AVC denials on the node. Without it, the operator cannot capture the access events needed to generate a profile.

## Credit

- https://github.com/kubernetes-sigs/security-profiles-operator
- https://github.com/SELinuxProject/refpolicy
