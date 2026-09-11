
LiveKit's helm charts are published on S3.

## Installing helm

Add it to your helm repo with:

```shell
helm repo add livekit https://helm.livekit.io
```

Customize values in values-sample.yaml

### Per-node media VIPs (`instances`)

One room stays on one SFU. Direct ICE therefore needs one advertised address
per LiveKit node. Set `instances` to create one DaemonSet and ConfigMap per
node, each with its own `rtc.node_ip`. TURN/TLS stays on the shared
`*-turn` Service.

```yaml
instances:
  - name: lk-0
    node_ip: 203.0.113.10
    nodeSelector:
      kubernetes.io/hostname: k8s-worker-livekit-0
  - name: lk-1
    node_ip: 203.0.113.11
    nodeSelector:
      kubernetes.io/hostname: k8s-worker-livekit-1
```

Leave `instances` empty for a single shared config (previous behaviour).

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
