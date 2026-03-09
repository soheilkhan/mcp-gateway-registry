{{- define "base.affinity" -}}
{{- if not (or (eq .Values.global.environment "development") (eq .Values.global.environment "test")) }}
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
          - key: karpenter.sh/nodepool
            operator: In
            values:
              - {{ include "template.fullname" . }}
{{- end }}
{{- end }}