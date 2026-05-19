{{- define "spire-agent.fullname" -}}
{{- printf "%s-spire-agent" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "spire-agent.labels" -}}
app.kubernetes.io/name: spire-agent
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: workload-identity-agent
app.kubernetes.io/part-of: spire
kacho.cloud/component: spire-agent
kacho.cloud/phase: "10"
{{- end -}}

{{- define "spire-agent.selectorLabels" -}}
app.kubernetes.io/name: spire-agent
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "spire-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "spire-agent.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "spire-agent.trustDomain" -}}
{{- required "spire.agent.trustDomain (or .Values.trustDomain) is required" .Values.trustDomain -}}
{{- end -}}
