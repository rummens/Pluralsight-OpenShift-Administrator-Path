{{/*
Common labels
*/}}
{{- define "tracing-stack.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
TempoMonolithic OTLP service name. The Tempo Operator names the in-cluster
OTLP service "tempo-<TempoMonolithic name>", so the collector exports there.
*/}}
{{- define "tracing-stack.tempoService" -}}
tempo-{{ .Values.tempo.name }}
{{- end -}}

{{/*
Tempo gateway service name (present only when multitenancy is enabled).
*/}}
{{- define "tracing-stack.tempoGateway" -}}
tempo-{{ .Values.tempo.name }}-gateway
{{- end -}}
