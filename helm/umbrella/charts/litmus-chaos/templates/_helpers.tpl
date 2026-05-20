{{/*
Helper template for Litmus chaos subchart.
*/}}

{{- define "litmus-chaos.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "litmus-chaos.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "litmus-chaos.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "litmus-chaos.labels" -}}
app.kubernetes.io/name: {{ include "litmus-chaos.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
kacho.cloud/component: chaos-engineering
{{- end -}}

{{/*
Resolve OIDC issuer URL from umbrella top-level domain value.
*/}}
{{- define "litmus-chaos.oidcIssuerUrl" -}}
{{- $domain := dig "global" "kacho" "domain" "api.kacho.cloud" .Values -}}
{{- printf "https://hydra.%s" $domain -}}
{{- end -}}
