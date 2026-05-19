{{- define "cilium.fullname" -}}
{{- printf "%s-cilium" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cilium.labels" -}}
app.kubernetes.io/name: cilium
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: service-mesh
kacho.cloud/component: cilium
kacho.cloud/phase: "10"
{{- end -}}

{{- define "cilium.trustDomain" -}}
{{- required "cilium.spiffe.trustDomain is required" .Values.spiffe.trustDomain -}}
{{- end -}}

{{/*
SPIFFE-ID per service helper.
Usage: {{ include "cilium.spiffeId" (dict "trustDomain" $trust "namespace" $ns "sa" $sa) }}
*/}}
{{- define "cilium.spiffeId" -}}
spiffe://{{ .trustDomain }}/ns/{{ .namespace }}/sa/{{ .sa }}
{{- end -}}

{{- define "cilium.serviceSpiffeId" -}}
{{- $td := index . 0 -}}
{{- $ns := index . 1 -}}
{{- $name := index . 2 -}}
spiffe://{{ $td }}/ns/{{ $ns }}/sa/{{ $name }}
{{- end -}}
