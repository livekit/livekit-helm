{{/*
Expand the name of the chart.
*/}}
{{- define "livekit-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "livekit-server.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "livekit-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "livekit-server.labels" -}}
helm.sh/chart: {{ include "livekit-server.chart" . }}
{{ include "livekit-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "livekit-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "livekit-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "livekit-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "livekit-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the service monitor to use
*/}}
{{- define "livekit-server.serviceMonitorName" -}}
{{- if .Values.serviceMonitor.create }}
{{- default (include "livekit-server.fullname" .) .Values.serviceMonitor.name }}
{{- else }}
{{- default "default" .Values.serviceMonitor.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the service monitor secret to use
*/}}
{{- define "livekit-server.serviceMonitorSecretName" -}}
{{- default (print (include "livekit-server.fullname" .) "-service-monitor-secret") .Values.serviceMonitor.secretName }}
{{- end }}

{{/*
Load prometheus port from old or new config
*/}}
{{- define "livekit-server.prometheus_port" -}}
{{- if or .Values.livekit.prometheus_port (and .Values.livekit.prometheus .Values.livekit.prometheus.port) }}
{{- default .Values.livekit.prometheus_port .Values.livekit.prometheus.port }}
{{- end }}
{{- end }}
