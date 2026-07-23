{{/*
Expand the name of the chart.
*/}}
{{- define "go-web-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "go-web-app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "go-web-app.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{/*
Labels
*/}}
{{- define "go-web-app.labels" -}}
app.kubernetes.io/name: {{ include "go-web-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}