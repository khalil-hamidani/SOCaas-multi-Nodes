{{- define "socaas.name" -}}
{{- default .Chart.Name .Values.global.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "socaas.fullname" -}}
{{- default .Release.Name .Values.global.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "socaas.labels" -}}
app.kubernetes.io/name: {{ include "socaas.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: socaas
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "socaas.siemNodeSelector" -}}
{{- toYaml .Values.scheduling.siemNodeSelector -}}
{{- end -}}

{{- define "socaas.soarNodeSelector" -}}
{{- toYaml .Values.scheduling.soarNodeSelector -}}
{{- end -}}
