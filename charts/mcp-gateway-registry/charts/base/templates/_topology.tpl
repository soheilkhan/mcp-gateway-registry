{{- define "base.topology" -}}
{{- if not (or (eq .Values.global.environment "development") (eq .Values.global.environment "test")) }}
topologySpreadConstraints:
  - labelSelector:
      matchLabels:
        {{- include "template.selectorLabels" . | nindent 8 }}
    matchLabelKeys:
      - pod-template-hash
    maxSkew: {{ .Values.topology.hostSkew | default 1 }}
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
  - labelSelector:
      matchLabels:
        {{- include "template.selectorLabels" . | nindent 8 }}
    matchLabelKeys:
      - pod-template-hash
    maxSkew: {{ .Values.topology.zoneSkew | default 1 }}
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
{{- end }}
{{- end }}