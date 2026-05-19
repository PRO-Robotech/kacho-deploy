{{- define "kafka-connect.fullname" -}}
{{- printf "%s-kafka-connect" .Release.Name -}}
{{- end -}}

{{- define "kafka-connect.labels" -}}
app.kubernetes.io/name: kafka-connect
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
kacho.cloud/component: audit-s3-sink
{{- end -}}

{{- define "kafka-connect.selectorLabels" -}}
app.kubernetes.io/name: kafka-connect
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
