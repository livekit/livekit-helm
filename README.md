
LiveKit's helm charts are published on S3.

## Installing helm

Add it to your helm repo with:

```shell
helm repo add livekit https://helm.livekit.io
```

Customize values in values-sample.yaml

Then install the chart

```shell
helm install <instance_name> livekit/livekit-server --namespace <namespace> --values values.yaml
```

## For LiveKit Helm developers

Publishing requires helm-s3 plugin

```shell
helm plugin install https://github.com/hypnoglow/helm-s3.git
AWS_REGION=us-east-1 helm repo add livekit s3://livekit-helm

./deploy.sh
```
