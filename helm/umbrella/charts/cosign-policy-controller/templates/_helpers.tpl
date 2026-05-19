{{- define "cosign-policy.fullname" -}}
{{- printf "%s-cosign-policy" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cosign-policy.labels" -}}
app.kubernetes.io/name: cosign-policy-controller
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: admission-control
kacho.cloud/component: cosign-policy
kacho.cloud/phase: "10"
{{- end -}}
