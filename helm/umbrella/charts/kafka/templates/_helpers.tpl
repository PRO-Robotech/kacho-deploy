{{/*
Helper templates для kafka subchart (KAC-127 Phase 9).
*/}}

{{- define "kafka.fullname" -}}
{{- printf "%s-kafka" .Release.Name -}}
{{- end -}}

{{- define "kafka.labels" -}}
app.kubernetes.io/name: kafka
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: audit-broker
kacho.cloud/component: audit-kafka
{{- end -}}

{{- define "kafka.selectorLabels" -}}
app.kubernetes.io/name: kafka
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Bootstrap servers DNS — service-name + cluster-domain. Format:
  <release>-kafka-bootstrap.<namespace>.svc.cluster.local:9092
Используется kacho-iam clients для подключения.
*/}}
{{- define "kafka.bootstrapServers" -}}
{{- printf "%s-bootstrap.%s.svc.cluster.local:%d" (include "kafka.fullname" .) .Release.Namespace (int .Values.listeners.client.port) -}}
{{- end -}}
