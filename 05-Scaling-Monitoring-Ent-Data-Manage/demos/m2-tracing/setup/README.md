# Setup: Install the Tracing Stack Before Recording

The entire tracing infrastructure (operators, TempoMonolithic store, OTLP collector)
is installed ahead of time via the Helm chart in this repo. Run from the repo root:

```bash
# Install the Cluster Observability Operator first if not already present
# (needed for the UIPlugin that adds Observe -> Traces to the console)
oc get csv -n openshift-operators | grep cluster-observability

# Install the tracing stack
helm install tracing-stack \
  05-Scaling-Monitoring-Ent-Data-Manage/tracing-stack/ \
  --create-namespace --namespace globomantics

# Monitor the post-install job
oc -n globomantics logs job/tracing-wait-and-apply -f

# Confirm both operators are Succeeded before recording
oc get csv -n openshift-operators | egrep 'tempo|opentelemetry'

# Confirm store and collector pods are Running
oc -n globomantics get pods -l app.kubernetes.io/name=tempo-monolithic
oc -n globomantics get pods -l app.kubernetes.io/name=globomantics-otelcol-collector
```

The demo-root manifests (`tempo-operator-subscription.yaml`, `otel-operator-subscription.yaml`,
`tempomonolithic.yaml`, `otel-collector.yaml`) are the simplified display versions shown
on camera. They match the helm chart's naming but omit the multitenancy and hook scaffolding
that the chart manages automatically.

Note: `tempomonolithic.yaml` shown on screen is the simplified (non-multitenant) view for
teaching purposes. The chart actually deploys with `multitenancy.enabled=true` (required
for Observe → Traces to discover the instance in the OpenShift console).
