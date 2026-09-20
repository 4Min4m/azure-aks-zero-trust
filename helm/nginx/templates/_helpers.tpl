{{- define "nginx-app.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "nginx-app.labels" -}}
app: {{ include "nginx-app.name" . }}
app.kubernetes.io/name: {{ include "nginx-app.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
