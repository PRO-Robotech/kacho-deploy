{{/*
Helper templates для clickhouse subchart (KAC-127 Phase 9).
*/}}

{{- define "clickhouse.fullname" -}}
{{- printf "%s-clickhouse" .Release.Name -}}
{{- end -}}

{{- define "clickhouse.keeper.fullname" -}}
{{- printf "%s-clickhouse-keeper" .Release.Name -}}
{{- end -}}

{{- define "clickhouse.labels" -}}
app.kubernetes.io/name: clickhouse
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: audit-olap
kacho.cloud/component: audit-clickhouse
{{- end -}}

{{- define "clickhouse.selectorLabels" -}}
app.kubernetes.io/name: clickhouse
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "clickhouse.keeper.labels" -}}
app.kubernetes.io/name: clickhouse-keeper
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
kacho.cloud/component: audit-clickhouse-keeper
{{- end -}}

{{- define "clickhouse.keeper.selectorLabels" -}}
app.kubernetes.io/name: clickhouse-keeper
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ClickHouse server connect DSN — service-discovery format.
*/}}
{{- define "clickhouse.serviceDNS" -}}
{{- printf "%s.%s.svc.cluster.local" (include "clickhouse.fullname" .) .Release.Namespace -}}
{{- end -}}
