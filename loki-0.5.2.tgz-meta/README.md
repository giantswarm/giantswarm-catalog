# loki-app chart

[![CircleCI](https://circleci.com/gh/giantswarm/loki-app.svg?style=shield)](https://circleci.com/gh/giantswarm/loki-app)

Giant Swarm offers Loki as a [managed app](https://docs.giantswarm.io/changes/managed-apps/). This chart provides a distributed loki setup based on this
[upstream chart](https://github.com/grafana/helm-charts/tree/main/charts/loki-distributed).
It tunes some options from upstream to make the chart easier to deploy.

This chart is meant to be used with S3 compatible storage only. Access to the S3
storage must be ensured for the chart to work.
* Check [below](#deploying-on-aws) to see what configuration you need on the AWS side.
* or [below](#deploying-on-azure) to see what configuration you need on the Azure side.

⚠️ Make sure to read (upgrade guide)[https://github.com/giantswarm/loki-app/blob/master/UPGRADE.md] to check breaking changes before performing an upgrade


## Requirements

* You need to ensure that pods deployed can access S3 storage (as explained above).
* On Giant Swarm clusters, you *have to* run a release that is based on `helm 3`.
  This means you need at least:
  * v12.1.2 for Azure
  * v12.5.1 for AWS
  * v12.3.1 for KVM.

## General recommendations

The number of `replicas` in the [default values file](https://github.com/giantswarm/loki-app/blob/master/helm/loki/values.yaml) are generally considered safe.
If you reduce the number of `replicas` below the default recommended values, expect undefined behaviour and problems.

## Prepare config file

1. Create app config file
Grab the included [sample config file](https://github.com/giantswarm/loki-app/blob/master/sample_configs/values-gs.yaml)
or [azure sample config file](https://github.com/giantswarm/loki-app/blob/master/sample_configs/values-gs-azure.yaml),
read the comments for options and adjust to your needs. To check all available
options, please consult the [full `values.yaml` file](https://github.com/giantswarm/loki-app/blob/master/helm/loki/values.yaml).

2. update `nodeSelectorTerms` to match your nodes (if unsure, `kubectl describe nodes [one worker node] | grep machine-`
should give you the right id for `machine-deployment` or `machine-pool` depending on your provider). Beware, there's 2 places to update! (obsolete with SSD)

3. update `gateway.ingress.hosts.host` and `gateway.ingress.tls.host` 

#### Multi-tenant setup

1. The default GiantSwarm template is prepared for multi-tenancy.
In multi tenant setups<a name="multi-tenant-config"></a>, you can enable [loki-multi-tenant-proxy](https://github.com/k8spin/loki-multi-tenant-proxy)
to manage credentials for different tenants.

Enable the deployment of loki-multi-tenant-proxy by setting `multiTenantAuth.enabled` to `true`.

Write down your credentials in `multiTenantAuth.credentials`.
They should be formatted in your values file like this:

```yaml
multiTenantAuth:
  enabled: true
  credentials: |-
    users:
      - username: Tenant1
        password: 1tnaneT
        orgid: tenant-1
      - username: Tenant2
        password: 2tnaneT
        orgid: tenant-2
```

2. In single tenant setups<a name="single-tenant-config"></a> with simple basic auth logins you want to use the
`gateway.basicAuth.existingSecret` config option.
To create the secret with necessary users and passwords use the following commands:

```bash
echo "passwd01" | htpasswd -i -c.htpasswd user01
echo "passwd02" | htpasswd -i .htpasswd user02
echo "passwd03" | htpasswd -i .htpasswd user03

kubectl -n loki create secret generic loki-basic-auth --from-file=.htpasswd
```
Then, set `gateway.basicAuth.existingSecret` to `loki-basic-auth`.


## Deploying on AWS

The recommended deployment mode is using S3 storage mode. Assuming your cluster
has `kiam` (https://github.com/uswitch/kiam), `cert-manager` and `external-dns` included, you should be good to use
the instructions below to setup S3 bucket and the necessary permissions in your
AWS account.

Make sure to create this config for the *cluster* where you are deploying Loki, and not at installation-level.

#### Prepare AWS S3 storage.
Create a new private S3 bucket based in the same region
as your instances. Ex. `gs-loki-storage`.
* encryption is not required, but strongly recommended: Loki won't encrypt your data
* consider creating private VPC endpoint for S3 - traffic volume might be
  considerable and this might save you some money for the transfer fees,
* it is recommended to use S3 bucket class for frequent access (`S3 standard`),
* create a retention policy for the bucket; currently, loki won't delete
  files in S3 for you ([check here](https://grafana.com/docs/loki/latest/operations/storage/retention/)
  and [here](https://grafana.com/docs/loki/latest/operations/storage/table-manager/)).
* CLI procedure:
```bash
# prepare environment
export CLUSTER_NAME=zj88t
export NODEPOOL_ID=oy9v0
export REGION=eu-central-1
export BUCKET_NAME=gs-loki-storage-"$CLUSTER_NAME" # must be globally unique
export AWS_PROFILE=gorilla-atlas # your AWS CLI profile
export LOKI_POLICY="$BUCKET_NAME"-policy
export LOKI_ROLE="$BUCKET_NAME"-role

# create bucket
aws --profile="$AWS_PROFILE" s3 mb s3://"$BUCKET_NAME" --region "$REGION"
```

#### Prepare AWS role.
* Create an IAM Policy in IAM. If you want to use AWS WebUI, copy/paste the contents of `POLICY_DOC` variable.
```bash
# Create policy
POLICY_DOC='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject" ],
            "Resource": [
                "arn:aws:s3:::'"$BUCKET_NAME"'",
                "arn:aws:s3:::'"$BUCKET_NAME"'/*"
            ]
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "s3:GetAccessPoint",
                "s3:GetAccountPublicAccessBlock",
                "s3:ListAccessPoints"
            ],
            "Resource": "*"
        }
    ]
}'
aws --profile="$AWS_PROFILE" iam create-policy --policy-name "$LOKI_POLICY" --policy-document "$POLICY_DOC"
```
* create a new IAM Role that allows the necessary instances (k8s masters in the
  case of using `kiam`) to access resources from the policy. Set trust to allow
  the Role used by `kiam` to claim the S3 access role.
  If you want to use AWS WebUI, copy/paste the contents of `POLICY_DOC` variable.
```bash
# Create role
PRINCIPAL_ARN="$(aws --profile="$AWS_PROFILE" iam get-role --role-name "$CLUSTER_NAME"-IAMManager-Role | sed -n 's/.*Arn.*"\(arn:.*\)".*/\1/p')"
ROLE_DOC='{
    "Version": "2012-10-17",
    "Statement": [
        {
        "Effect": "Allow",
        "Principal": {
            "AWS": "'"$PRINCIPAL_ARN"'"
        },
        "Action": "sts:AssumeRole"
        }
    ]
}'
aws --profile="$AWS_PROFILE" iam create-role --role-name "$LOKI_ROLE" --assume-role-policy-document "$ROLE_DOC"
# Attach the policy to the role
LOKI_POLICY_ARN="${PRINCIPAL_ARN%:role/*}:policy/$LOKI_POLICY"
aws --profile="$AWS_PROFILE" iam attach-role-policy --policy-arn "$LOKI_POLICY_ARN" --role-name "$LOKI_ROLE"
```

#### Prepare the namespace
Currently, you have to manually pre-create the namespace and annotate it with
IAM Roles required for pods running in the namespace:

```bash
kubectl create ns loki
LOKI_ROLE_ARN="${PRINCIPAL_ARN%:role/*}:role/$LOKI_ROLE"
kubectl annotate ns loki iam.amazonaws.com/permitted="$LOKI_ROLE_ARN"
```

#### Install the app

* Fill in the values from previous step in your config (`values.yaml`) file:
  * role annotation for S3
  * cluster ID
  * node pool ID
  * and your custom setup

* Install the app using your values.
  Don't forget to use the same namespace as you prepared above for the installation.

## Deploying on Azure

#### Gather data
Find the 'Subscription name' (usually named after your installation) name and the 'Resource group' of your cluster (usually named after cluster id) inside your 'Azure subscription'
* list subscriptions:
```
az account list -otable
export SUBSCRIPTION_NAME="your subscription"
```
* list resource groups:
```
az group list --subscription "$SUBSCRIPTION_NAME" -otable
export RESOURCE_GROUP="your resource group"
```

#### object storage setup
1. Create 'Storage Account' on Azure ([How-to](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-create)) ['Create storage account'](https://portal.azure.com/#create/Microsoft.StorageAccount)
    * 'Account kind' should be 'BlobStorage'
    * Example with Azure CLI:
```
# Chose your storage account name
export STORAGE_ACCOUNT_NAME="loki$RESOURCE_GROUP"
# then create it
az storage account create \
     --subscription "$SUBSCRIPTION_NAME" \
     --name "$STORAGE_ACCOUNT_NAME" \
     --resource-group "$RESOURCE_GROUP" \
     --sku Standard_GRS \
     --encryption-services blob \
     --https-only true \
     --kind BlobStorage \
     --access-tier Hot
```
(It may be required to set the location using the `--location` flag.)

2. Create a 'Blob service' 'Container' in your storage account
    * Example on how to do it with Powershell in Azure portal:
```
export CONTAINER_NAME="$STORAGE_ACCOUNT_NAME"container
az storage container create \
     --subscription "$SUBSCRIPTION_NAME" \
     -n "$CONTAINER_NAME" \
     --public-access off \
     --account-name "$STORAGE_ACCOUNT_NAME"
```

3. Go to the 'Access keys' page of your 'Storage account'
    * Use the 'Storage account name' for `azure_storage.account_name`
    * Use the name of the 'Blob service' 'Container' for `azure_storage.blob_container_name`
    * Use one of the keys for `azure.storage_key`
    * With azure CLI
```
az storage account keys list \
     --subscription "$SUBSCRIPTION_NAME" \
     --account-name "$STORAGE_ACCOUNT_NAME" \
| jq -r '.[]|select(.keyName=="key1").value'
```

#### Install the app

* Fill in the values from previous step in your config (`values.yaml`) file:
  * cluster ID
  * node pool ID
  * and your custom setup

* Install the app using your values.



## Testing your deployment

### Reading data with logcli

1. Install latest logcli from https://github.com/grafana/loki/releases

2. Here are a few test queries for Loki, that you should adapt with your URL and credentials:

  * test from WAN
```
# List all streams
logcli --username=Tenant1 --password=1tnaneT --addr="http://loki.nx4tn.k8s.gauss.eu-west-1.aws.gigantic.io" series '{}'
```

  * Test with a port-forward to the gateway:
```
k port-forward -n loki svc/loki-gateway 8080:80
logcli --username=Tenant1 --password=1tnaneT --addr="http://localhost:8080" series '{}'
```

  * You can also test direct access to querier
```
# port-forward querier to local port 3100
k port-forward -n loki svc/loki-querier 3100:3100
# or loki-query-frontend-xxxx port 3100 accepts the same queries

# List all streams
# Note that we use "org-id" rather than "username/password" when we bypass the gateway
$ logcli --org-id="tenant-1" --addr="http://localhost:3100" series '{}'
http://localhost:3100/loki/api/v1/series?end=1654091687961363182&match=%7B%7D&start=1654088087961363182
```

### Ingesting data with promtail

* Get promtail from https://github.com/grafana/loki/releases
* Create basic promtail config file `promtail-test.yml`:
```yaml
---
server:
  disable: true
positions:
  filename: /tmp/promtail_test_positions.yaml
clients:
  - url: http://localhost:8080/loki/api/v1/push
    # tenant_id: tenant-1
    basic_auth:
      username: Tenant1
      password: 1tnaneT
scrape_configs:
  - job_name: logfile
    static_configs:
      - targets:
          - localhost
        labels:
          job: logfile
          host: local
          __path__: /tmp/lokitest.log
```
* If you want to bypass the gateway, you can port-forward Loki distributor to localhost:3100
```
k port-forward -n loki svc/loki-distributor 3100:3100
# Don't forget to change your promtail URL, and use tenant_id rather than basic_auth!
```
* Launch promtail
```
promtail --config.file=promtail-test.yml --inspect
```
* Add data to your log file
```
(while true ; do echo "test log line $(date)"; sleep 1; done ) >> /tmp/lokitest.log
```
* Query loki with `logcli` and see your data

## Source code origin

The source code in `helm/loki` is a git-subtree coming from the
<https://github.com/giantswarm/grafana-helm-charts-upstream>. Giant Swarm uses that
repository to track and adjust or charts maintained by Grafana Labs.

Notes specific to upstream upgrade can be found in (UPGRADE.md)[https://github.com/giantswarm/loki-app/blob/master/UPGRADE.md]

## Links

- [Loki demo for Giant Swarm customers (YouTube)](https://www.youtube.com/watch?v=KeJwfOiVA7o)
- [Part 1: How the Cloud-Native Stack Helps Writing Minimal Microservices (blog series)](https://www.giantswarm.io/blog/how-the-cloud-native-stack-helps-writing-minimal-microservices/)
- [Achieving cloud-native observability with open-source (on demand demo and slides)](https://www.giantswarm.io/on-demand-webinar-achieving-cloud-native-observability-with-open-source)
- [The radical way Giant Swarm handles Service Level Objectives](https://www.giantswarm.io/blog/the-radical-way-giant-swarm-handles-service-level-objectives)

## Credit

* <https://github.com/grafana/helm-charts/tree/main/charts/loki-distributed>
