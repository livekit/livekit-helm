# Make liveness and readiness probes independently configurable

Closes #116.

## Summary

The chart previously hardcoded identical `livenessProbe` and `readinessProbe`
definitions in `templates/deployment.yaml`, both pointing at `GET /` on the
`http` port. This made it impossible for operators to diverge readiness from
liveness, which in turn blocked any kind of graceful drain: anything that
caused the readiness check to fail (intentionally, during shutdown) would also
fail liveness and kill the pod, terminating in-flight WebRTC sessions.

This PR exposes both probes as fully structured blocks in `values.yaml` so
operators can override them independently. The defaults render to the same
endpoint as before (`GET /` on the `http` named port), with explicit, sensible
threshold/timing fields.

## Changes

- `livekit-server/values.yaml`: New top-level `livenessProbe` and
  `readinessProbe` blocks with sensible defaults. Comment block explains why
  they should not share a definition and how to use the readiness override
  for graceful shutdown.
- `livekit-server/templates/deployment.yaml`: Hardcoded probe definitions
  replaced with `{{- with .Values.livenessProbe }} ... {{- toYaml . | nindent
  12 }} {{- end }}` (same for readinessProbe). Setting either value to `null`
  cleanly omits that probe from the rendered Deployment.
- `server-sample.yaml`: Added a commented-out readiness override snippet so
  the override pattern is discoverable from the sample values file.
- `livekit-server/tests/probe_configuration_test.yaml` (new): helm-unittest
  suite covering five scenarios. Details in the Testing section below.
- `livekit-server/tests/upgrade_compatibility_test.yaml` (new): helm-unittest
  suite that locks in the rendered before-vs-after delta with default values.

## Default behavior vs prior chart

Before: the chart relied on Kubernetes implicit probe defaults
(`failureThreshold: 3`, `periodSeconds: 10`, `timeoutSeconds: 1`,
`initialDelaySeconds: 0`) for both probes.

After: the chart sets those values explicitly, with one intentional
behavioral delta:

| Field                                    | Before (implicit) | After (explicit) | Behavioral change? |
|------------------------------------------|-------------------|------------------|--------------------|
| `livenessProbe.failureThreshold`         | 3                 | 3                | No                 |
| `livenessProbe.periodSeconds`            | 10                | 10               | No                 |
| `livenessProbe.timeoutSeconds`           | 1                 | 1                | No                 |
| **`livenessProbe.initialDelaySeconds`**  | **0**             | **10**           | **Yes (lenient)**  |
| `readinessProbe.failureThreshold`        | 3                 | 3                | No                 |
| `readinessProbe.periodSeconds`           | 10                | 10               | No                 |
| `readinessProbe.timeoutSeconds`          | 1                 | 1                | No                 |
| `readinessProbe.initialDelaySeconds`     | 0                 | 0                | No                 |

The single behavioral delta is `livenessProbe.initialDelaySeconds: 0 -> 10`.
Replacing implicit Kubernetes defaults with explicit chart values means
picking opinionated numbers for every operator who does not override them,
so this choice deserves to be deliberate rather than incidental. 10 seconds
covers a realistic worst case for cold-start work: image pull on a node that
does not already have the layer cached, the livekit-server process startup
itself, configmap mount and environment population, and any redis or other
dependency handshake when configured. The value also lines up with the
initialDelaySeconds defaults used by production-grade Helm charts in the
broader community (Bitnami, the prometheus-community charts, and similar)
for HTTP-served workloads, so operators familiar with those will not be
surprised. The choice is strictly safer than the prior implicit 0: the
kubelet's first liveness probe now lands 10 seconds later, never sooner,
so no pod can be killed earlier than the prior chart would have killed it,
and the chart's existing 30-seconds-of-failures-before-kill margin
(`failureThreshold=3` with `periodSeconds=10`) is preserved after the
initial delay window. Operators who explicitly prefer the prior timing
can set `livenessProbe.initialDelaySeconds: 0` in their values.

> Earlier draft of this PR set `readinessProbe.failureThreshold: 1` to favor
> fast pod-removal during graceful shutdown. That was reverted to match the
> Kubernetes implicit default of 3, on the rationale that operators with
> drain-aware readiness endpoints can opt down to 1 explicitly via override,
> while operators on the default endpoint should not see faster pod-flap on
> transient blips after upgrade. The decision is reflected in
> `tests/upgrade_compatibility_test.yaml` which asserts no `failureThreshold`
> change in the rendered output.

## Backwards compatibility

- No values keys were removed or renamed.
- The new `livenessProbe` / `readinessProbe` keys did not exist before, so no
  existing user could already have them set.
- Helm upgrade will trigger a one-time Deployment rollout because the
  rendered probe spec has additional explicit fields (each of which matches
  the Kubernetes implicit default the rollout was already using). The
  upgrade-compatibility test suite documents this exactly.

## Testing

Tests are written for the [helm-unittest][hu] plugin
(`helm plugin install https://github.com/helm-unittest/helm-unittest`).

[hu]: https://github.com/helm-unittest/helm-unittest

### Scenarios covered

`tests/probe_configuration_test.yaml` (10 tests):

- **Scenario A - default values** (5 tests): liveness and readiness each
  target `GET /` on the `http` named port; both `failureThreshold` defaults
  are 3; the two probes are independently rendered, proven by their
  different default `initialDelaySeconds` values.
- **Scenario B - partial override** (1 test, 10 assertions): setting
  `readinessProbe.httpGet.path`, `readinessProbe.failureThreshold`, and
  `livenessProbe.failureThreshold` overrides only those leaves; all other
  defaults on both probes survive.
- **Scenario C - both probes nulled out** (1 test): setting both to `null`
  via a values file omits both fields from the rendered Deployment, with the
  rest of the container spec (name, image, ports) intact.
- **Scenario D - mixed null** (2 tests): liveness null with readiness at
  default omits liveness only and vice versa.
- **Scenario E - custom `livekit.port`** (1 test): overriding `livekit.port`
  changes the container's HTTP port number but probes still reference the
  named port `http`, documenting that operators do not need to touch probe
  port references when changing `livekit.port`.

`tests/upgrade_compatibility_test.yaml` (3 tests): asserts the exact set of
explicit probe fields rendered after the change, asserts each rendered field
matches the Kubernetes implicit default except the documented liveness
`initialDelaySeconds` delta, and asserts non-probe fields (image, ports,
container name, hostNetwork, dnsPolicy, terminationGracePeriodSeconds) are
unchanged. The header comments include the full diff captured at commit time
and a copy-paste reproduction recipe.

### Coverage gaps (out of scope for this PR)

- **No live-cluster install test** of the new probe values. The repo's
  existing `ct install` matrix does run `helm install` on microk8s, which
  would catch a chart that fails to render or apply, but it does not assert
  runtime probe behavior (e.g., that `/` actually returns 200 from
  livekit-server). Runtime probe behavior is unchanged from prior chart.
- **No test for the graceful-shutdown drain endpoint behavior itself**.
  This PR exposes the configuration surface; the SIGTERM/drain endpoint
  belongs in livekit-server. See "Path Considered But Not Taken" below.
- **No test for non-httpGet probe types** (`tcpSocket`, `exec`,
  `grpc`). `toYaml` is type-agnostic so an operator override of any of
  these should render correctly, but no assertion locks that in.
- **No test for `livenessProbe: {}` (empty map)** as distinct from
  `livenessProbe: ~` (null). Both should result in the field being omitted
  because Go templates treat both as falsy under `{{- with }}`, but only
  null is asserted.
- **No test for override conflicts**, e.g., setting `livenessProbe.tcpSocket`
  while leaving the default `httpGet` block intact. Helm's value-merge
  cannot deep-replace a sibling key, so the rendered probe would contain
  both `httpGet` and `tcpSocket`, which Kubernetes rejects. Operators
  switching probe types must replace the entire block. This footgun is
  documented in the values.yaml comment but not test-asserted.
- **No test for `successThreshold`**, which K8s allows on readiness probes
  but is not in the chart defaults.
- **No `startupProbe` support added**. Operators who need one can add it
  via a chart values addition in a follow-up; this PR is scoped to the
  liveness/readiness pairing called out in #116.
- **No CI step yet runs `helm unittest`** in this repo. The current CI
  workflow runs `ct lint` and `ct install` only. To wire these tests into
  CI, a maintainer would add a step similar to:

  ```yaml
  - name: Install helm-unittest plugin
    run: helm plugin install https://github.com/helm-unittest/helm-unittest

  - name: Run helm unittest
    run: helm unittest livekit-server/
  ```

  inserted after the existing "Set up Helm" step (CI uses Helm v3.11.2;
  Helm v4 users locally may need `--verify=false` on the plugin install).
  I have intentionally not modified the workflow file in this PR to keep
  the chart-change diff focused; happy to add the CI step in this PR or a
  follow-up if maintainers prefer.
- **No snapshot tests**. helm-unittest supports `matchSnapshot` for full-doc
  comparison; I have not added any because the explicit-field assertions in
  `upgrade_compatibility_test.yaml` are easier to read and maintain when
  unrelated chart changes (image tag bump, label addition) inevitably arrive.

### Running the tests

```
$ helm unittest livekit-server/                                  # full suite
$ helm unittest -f 'tests/probe_configuration_test.yaml' livekit-server/   # one file
$ helm unittest -f 'tests/upgrade_compatibility_test.yaml' livekit-server/ # one file
```

Test names are scenario-prefixed (`A1.`, `B1.`, `C1.`, `D1.`, `D2.`, `E1.`)
so a failure line points at the exact scenario it broke.

### Local verification

```
$ helm lint livekit-server/
==> Linting livekit-server/
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed

$ helm unittest livekit-server/
### Chart [ livekit-server ] livekit-server/
 PASS  liveness and readiness probe configuration	livekit-server/tests/probe_configuration_test.yaml
 PASS  upgrade compatibility - default-values render before vs after	livekit-server/tests/upgrade_compatibility_test.yaml

Charts:      1 passed, 1 total
Test Suites: 2 passed, 2 total
Tests:       13 passed, 13 total
Snapshot:    0 passed, 0 total

$ helm template lk-test livekit-server/ | head -120
[renders cleanly; full output identical to prior chart's render except for the
documented probe field additions]
```

`helm template` was verified to produce output identical to the previous chart
for default values, except for the probe-field additions documented in the
table above.

## Path Considered But Not Taken

This PR implements operator-configurable probes (Path B). A more complete fix
(Path A) would require server-side support: a separate `/ready` endpoint in
livekit-server itself that returns a non-200 response when the process has
received SIGTERM but is still draining active sessions. The current PR gives
operators the configuration surface to point readinessProbe at such an
endpoint when it exists upstream, without requiring server-side changes to
land first.

Path B was chosen because:

- It is mergeable independently without coordinating across repos.
- It unblocks operators who can implement the SIGTERM behavior externally
  (for example via a `lifecycle.preStop` hook or a sidecar that drains state
  and flips its own readiness endpoint to 503).
- It does not break existing deployments.
- It is the minimum change that addresses the configuration limitation
  called out in #116.

A follow-up issue in livekit/livekit tracking the server-side endpoint work
would be the right place to capture Path A.
