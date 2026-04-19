{{/* Chart name helpers */}}
{{- define "globomantics-website.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "globomantics-website.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "globomantics-website.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "globomantics-website.labels" -}}
app.kubernetes.io/name: {{ include "globomantics-website.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name (.Chart.Version | replace "+" "_") }}
{{- end -}}

{{- define "globomantics-website.selectorLabels" -}}
app.kubernetes.io/name: {{ include "globomantics-website.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

