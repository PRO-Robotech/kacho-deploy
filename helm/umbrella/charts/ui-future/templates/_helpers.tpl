{{- define "ui.hostName" -}}
{{- default .Values.name .Values.host.name -}}
{{- end -}}

{{- define "ui.dashboardName" -}}
{{- default "ui-dashboard" .Values.dashboard.name -}}
{{- end -}}

{{- define "ui.hostImage" -}}
{{- default .Values.image .Values.host.image -}}
{{- end -}}

{{- define "ui.hostImagePullPolicy" -}}
{{- default .Values.imagePullPolicy .Values.host.imagePullPolicy -}}
{{- end -}}

{{- define "ui.dashboardImage" -}}
{{- if .Values.dashboard.image -}}
{{- .Values.dashboard.image -}}
{{- else -}}
{{- $hostImage := include "ui.hostImage" . -}}
{{- if contains "host" $hostImage -}}
{{- replace "host" "dashboard" $hostImage -}}
{{- else -}}
{{- "kacho-ui-future-dashboard:dev" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "ui.dashboardImagePullPolicy" -}}
{{- default (include "ui.hostImagePullPolicy" .) .Values.dashboard.imagePullPolicy -}}
{{- end -}}

{{- define "ui.hostPort" -}}
{{- default .Values.port .Values.host.port -}}
{{- end -}}

{{- define "ui.hostReplicas" -}}
{{- default .Values.replicas .Values.host.replicas -}}
{{- end -}}

{{- define "ui.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "ui.hostSelectorLabels" -}}
app: {{ include "ui.hostName" . }}
app.kubernetes.io/name: {{ include "ui.hostName" . }}
app.kubernetes.io/component: host
{{- end -}}

{{- define "ui.dashboardSelectorLabels" -}}
app: {{ include "ui.dashboardName" . }}
app.kubernetes.io/name: {{ include "ui.dashboardName" . }}
app.kubernetes.io/component: dashboard-remote
{{- end -}}

{{- define "ui.hostResources" -}}
{{- if .Values.host.resources }}
{{- toYaml .Values.host.resources }}
{{- else }}
{{- toYaml .Values.resources }}
{{- end }}
{{- end -}}
