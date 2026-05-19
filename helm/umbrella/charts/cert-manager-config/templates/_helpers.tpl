{{/*
KAC-127 Phase 11 — Common helper templates.
*/}}

{{/*
Resolve effective kacho domain: prefer global.kacho.domain if set, else fall
back to local kacho.domain. Top-level umbrella `--set kacho.domain=...` sets
global, so this resolves correctly out of the box.
*/}}
{{- define "kacho.domain" -}}
{{- if and .Values.global .Values.global.kacho .Values.global.kacho.domain -}}
{{- .Values.global.kacho.domain -}}
{{- else -}}
{{- .Values.kacho.domain -}}
{{- end -}}
{{- end -}}
