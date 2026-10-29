# LiveKit Stack Helm Chart

This umbrella chart deploys:
- LiveKit Server
- Ingress
- Egress

It is intended for users who want to install all LiveKit components together.

## Usage

```bash
helm dependency update livekit-stack/
helm install livekit livekit-stack/
