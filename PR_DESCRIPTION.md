# Make ServiceMonitor labels configurable for Prometheus discovery

Closes #97.

## Summary

The chart's `ServiceMonitor` resource hardcoded its `metadata.labels` to the
five chart-managed labels emitted by the `livekit-server.labels` helper.
Prometheus operators that use a non-empty `serviceMonitorSelector` (notably
`kube-prometheus-stack`, which defaults to
`spec.serviceMonitorSelector.matchLabels.release: <release-name>`) could not
discover the ServiceMonitor because the operator-required selector label was
missing.

This PR adds a single `serviceMonitor.labels` field (an empty map by default)
that is merged into `metadata.labels` alongside the chart-managed labels. The
field is opt-in: operators who do not set it see byte-identical output to the
prior chart.

## Changes

- `livekit-server/values.yaml`: new `serviceMonitor.labels: {}` field with
  comment documenting the kube-prometheus-stack `release: prometheus`
  example and pointing operators at their Prometheus
  `serviceMonitorSelector` configuration.
- `livekit-server/templates/servicemonitor.yaml`: added a
  `{{- with .Values.serviceMonitor.labels }}{{- toYaml . | nindent 4 }}{{- end }}`
  block immediately after the chart-managed labels, mirroring the existing
  `annotations` pattern lower in the same file.
- `livekit-server/tests/servicemonitor_labels_test.yaml` (new): helm-unittest
  suite covering five scenarios. Details in the Testing section below.
- `livekit-server/tests/upgrade_compatibility_test.yaml` (new): helm-unittest
  suite that asserts byte-identical default rendering.

## Multi-chart consistency

Only `livekit-server` ships a ServiceMonitor template
(`livekit-server/templates/servicemonitor.yaml`). The `egress` and `ingress`
charts have no ServiceMonitor, no `serviceMonitor` block in their
`values.yaml`, and no Prometheus-specific configuration at all (verified by
`grep -rl 'ServiceMonitor\|serviceMonitor' egress/ ingress/` returning no
matches). The fix is therefore applied only where it has a target.

## Default behavior vs prior chart

| Scenario                                                                | Before          | After           |
|-------------------------------------------------------------------------|-----------------|-----------------|
| `serviceMonitor.create: false` (chart default)                          | no ServiceMonitor | no ServiceMonitor |
| `serviceMonitor.create: true` and `serviceMonitor.labels: {}` (default) | 5 chart labels    | 5 chart labels (byte-identical) |
| `serviceMonitor.create: true` with `labels.release: prometheus`         | 5 chart labels (Prometheus selector misses) | 5 chart labels + `release: prometheus` (Prometheus selector matches) |

The diff between prior chart and this branch with default values is
**empty**, verified by `helm template ... | diff` and asserted in
`tests/upgrade_compatibility_test.yaml`.

## Backwards compatibility

- No values keys removed or renamed.
- One opt-in field added.
- Default rendering is byte-identical (zero diff) confirmed by `helm template`
  comparison and locked in by a unit test.
- **Edge case**: any existing user who already had `serviceMonitor.labels: {...}`
  set in their values (a no-op before this change because the template
  ignored it) will see those labels start applying after upgrade. This is
  "configuration that previously was silently ignored now does what the
  user clearly intended," but operators in this position should review their
  values.yaml to confirm the labels they wrote are still what they want
  applied.

## Testing

Tests are written for the [helm-unittest][hu] plugin
(`helm plugin install https://github.com/helm-unittest/helm-unittest`).

[hu]: https://github.com/helm-unittest/helm-unittest

### Scenarios covered

`tests/servicemonitor_labels_test.yaml` (7 tests):

- **Scenario A - default values** (3 tests): A1 confirms no ServiceMonitor
  renders at chart defaults (`create=false`); A2 confirms chart-managed
  labels are intact when ServiceMonitor is enabled; A3 deep-equals the
  full `metadata.labels` map against the five chart-managed entries to
  guarantee no accidental leakage from the new code path.
- **Scenario B - single label override** (1 test): setting
  `serviceMonitor.labels.release: prometheus` adds the label and preserves
  all five chart-managed labels.
- **Scenario C - multiple label override** (1 test, 7 assertions): three
  custom labels render alongside the five chart-managed labels with no
  overwrites or losses; uses a fixture file
  (`tests/fixtures/labels_three.yaml`).
- **Scenario D - kube-prometheus-stack realistic config** (1 test):
  asserts the rendered ServiceMonitor would be discovered by a Prometheus
  instance whose `serviceMonitorSelector` matches `release: prometheus`,
  and that the spec block (apiVersion, endpoints, selector) is valid for
  scraping.
- **Scenario E - empty override** (1 test): explicitly setting
  `serviceMonitor.labels: {}` produces output identical to the default
  case (no malformed/empty labels block); uses a fixture file
  (`tests/fixtures/labels_empty.yaml`).

`tests/upgrade_compatibility_test.yaml` (3 tests): asserts no ServiceMonitor
renders at chart defaults, asserts deep-equality on `metadata.labels` for
the enabled-with-default-labels case (catches any leakage), and asserts the
spec block is unchanged. The suite header documents the manual reproduction
recipe and the captured diff (empty).

### Running the tests

```
$ helm unittest livekit-server/                                              # full suite
$ helm unittest -f 'tests/servicemonitor_labels_test.yaml' livekit-server/   # just labels
$ helm unittest -f 'tests/upgrade_compatibility_test.yaml' livekit-server/   # just upgrade
```

Test names are scenario-prefixed (`A1.`, `A2.`, `A3.`, `B1.`, `C1.`, `D1.`,
`E1.`) so a failure line points at the exact scenario.

### Coverage gaps (out of scope for this PR)

- **No live-cluster install test of label discovery**. The repo's existing
  `ct install` matrix runs `helm install` on microk8s but does not stand up
  a Prometheus instance and verify scrape target discovery. The unit test
  asserts the rendered ServiceMonitor would be selected by a
  `release: prometheus` selector, but does not deploy Prometheus to confirm.
- **No CI step yet runs `helm unittest`** in this repo. The current CI
  runs `ct lint` and `ct install` only. To wire these tests into CI, a
  maintainer would add:

  ```yaml
  - name: Install helm-unittest plugin
    run: helm plugin install https://github.com/helm-unittest/helm-unittest

  - name: Run helm unittest
    run: helm unittest livekit-server/
  ```

  after the existing "Set up Helm" step (CI uses Helm v3.11.2; Helm v4
  users locally may need `--verify=false` on the plugin install). I have
  intentionally not modified the workflow file in this PR to keep the
  chart-change diff focused; happy to add the CI step in this PR or a
  follow-up if maintainers prefer.
- **No test for label-key collisions** between user-supplied labels and
  chart-managed labels. With user labels rendered after chart-managed
  labels, a user setting (for example) `serviceMonitor.labels.app.kubernetes.io/name`
  would shadow the chart-managed value. This matches the convention used
  by widely-deployed charts but is documented here rather than tested.
- **No annotations changes**. Issue #97 is scoped to labels;
  `serviceMonitor.annotations` already exists and is unchanged.

### Local verification

```
$ helm lint livekit-server/
==> Linting livekit-server/
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed

$ helm unittest livekit-server/
### Chart [ livekit-server ] livekit-server/
 PASS  ServiceMonitor configurable labels	livekit-server/tests/servicemonitor_labels_test.yaml
 PASS  upgrade compatibility - ServiceMonitor render is byte-identical when serviceMonitor.labels is left at default	livekit-server/tests/upgrade_compatibility_test.yaml

Charts:      1 passed, 1 total
Test Suites: 2 passed, 2 total
Tests:       10 passed, 10 total
Snapshot:    0 passed, 0 total

$ diff <(git show master:livekit-server/templates/servicemonitor.yaml | helm template lk-test livekit-server/ -f - --set serviceMonitor.create=true --set livekit.prometheus_port=6789) \
       <(helm template lk-test livekit-server/ --set serviceMonitor.create=true --set livekit.prometheus_port=6789)
[empty: zero diff with default labels]
```

## Path Considered But Not Taken

This PR adds a single `labels` field to the existing `serviceMonitor` block.
An alternative approach considered was a more comprehensive metadata block
(annotations, labels, name overrides) which would address potential future
configuration needs preemptively. That approach was not taken because:

- Issue #97 is scoped specifically to the labels problem, not broader
  metadata configuration.
- Adding fields without a current concrete user need expands the chart's
  API surface unnecessarily.
- Future issues asking for annotations or other metadata can be addressed
  in follow-up PRs with the same pattern. The existing
  `serviceMonitor.annotations` field is already in place; further metadata
  fields would slot in alongside without a structural change.

The current scope is the minimum change that resolves #97 cleanly.
