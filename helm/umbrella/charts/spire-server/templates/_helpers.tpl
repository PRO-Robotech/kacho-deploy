{{/*
KAC-127 Phase 10 — SPIRE Server helpers.
Configurable: всё через .Values; ничего хардкоженного.
*/}}

{{- define "spire-server.fullname" -}}
{{- printf "%s-spire-server" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "spire-server.labels" -}}
app.kubernetes.io/name: spire-server
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: workload-identity-server
app.kubernetes.io/part-of: spire
kacho.cloud/component: spire-server
kacho.cloud/phase: "10"
{{- end -}}

{{- define "spire-server.selectorLabels" -}}
app.kubernetes.io/name: spire-server
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "spire-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "spire-server.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Trust domain — configurable parameter. Каждый env имеет свой trust-domain.
*/}}
{{- define "spire-server.trustDomain" -}}
{{- required "spire.server.trustDomain (or .Values.trustDomain) is required — set per env: kacho.dev.cloud | kacho.staging.cloud | kacho.cloud" .Values.trustDomain -}}
{{- end -}}
