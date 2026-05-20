{{- define "spiffe-csi.fullname" -}}
{{- printf "%s-spiffe-csi" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "spiffe-csi.labels" -}}
app.kubernetes.io/name: spiffe-csi-driver
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
kacho.cloud/component: spiffe-csi
kacho.cloud/phase: "10"
{{- end -}}

{{- define "spiffe-csi.selectorLabels" -}}
app.kubernetes.io/name: spiffe-csi-driver
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
