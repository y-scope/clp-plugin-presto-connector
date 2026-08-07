{{/*
The name of the ConfigMap holding this chart's CLP-specific configuration. The Presto subchart
interpolates this same name inside its templated volumes, reading it from `.Values.global`.
*/}}
{{- define "clp-presto.configMapName" -}}
{{- printf "%s-clp-config" .Release.Name -}}
{{- end }}

{{- define "clp-presto.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}
