{{/*
Expand the name of the chart.
*/}}
{{- define "template.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "template.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "template.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "template.labels" -}}
helm.sh/chart: {{ include "template.chart" . }}
{{ include "template.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "template.selectorLabels" -}}
app.kubernetes.io/name: {{ include "template.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "template.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "template.fullname" .) (default .Values.serviceAccount.name .Values.serviceAccount.role) }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Convert all the secret references in the yaml config to external secret format
These templates below search for values starting with ssm:/ and replace them with hashed versions
The hashed version is a reference to the secret.  The long regex is used to quote any values coming from SSM
which may have yaml breaking formatting.
*/}}

{{- define "template.searchString" -}}
{{- printf "\\bssm:\\S*\\b" -}}
{{- end -}}

{{- define "template.hashString" -}}
{{- $hash := trimPrefix "ssm:" . | sha256sum | trunc 16 -}}
{{- $hash -}}
{{- end -}}

{{- define "template.regexFindAndReplaceAll" -}}
{{- $input := .Input -}}
{{- $sorted := (regexFindAll .Regex .Input -1) -}}
{{- range $sorted -}}
  {{- $hashed := include "template.hashString" . -}}
  {{- $replace := "" -}}
  {{- if hasPrefix "ssm:binary:" . -}}
    {{- $replace = printf "!!binary {{ .SECRET_REF_%s }}" $hashed -}}
  {{- else if hasPrefix "ssm:quote:" . -}}
    {{- $replace = printf "{{ .SECRET_REF_%s | quote }}" $hashed -}}
  {{- else -}}
    {{- $replace = printf "{{ .SECRET_REF_%s }}" $hashed -}}
  {{- end -}}
  {{- $pattern := printf "\\b(%s)\\b" . -}}
  {{- $input = regexReplaceAll $pattern $input $replace -}}
{{- end -}}
{{- $input -}}
{{- end -}}

{{/*
Helper to convert yaml to ingress tag format
*/}}
{{- define "template.ingressTags" -}}
{{- $result := "" -}}
{{- range $key, $value := . -}}
{{- if $result -}}
{{- $result = printf "%s, %s=%s" $result $key $value -}}
{{- else -}}
{{- $result = printf "%s=%s" $key $value -}}
{{- end -}}
{{- end -}}
{{- $result -}}
{{- end }}

{{/*
Helper to generate the external hostname
*/}}
{{- define "template.externalHostname" -}}
{{ .Release.Name }}.eks-{{ .Values.global.clusterKey }}.{{ .Values.global.businessUnit }}-{{ .Values.global.environment }}-{{ .Values.global.regionCode }}.zetaglobal.io
{{- end }}

{{- define "template.safeAccountId" -}}
{{- if eq (typeOf .) "string" -}}{{- . -}}{{- else -}}{{- . | int -}}{{- end -}}
{{- end -}}

{{/*
Helper to generate pullThroughCache automagic
*/}}
{{- define "template.imageResolver" -}}
{{- $account := .global.accountId -}}
{{- if ne .global.environment "prod" -}}
{{- $account = .global.defaultEcrAccount -}}
{{- end -}}
{{- if .image.internal -}}{{- include "template.safeAccountId" $account -}}.dkr.ecr.{{ .global.region }}.amazonaws.com/{{ .image.repository }}{{- else -}}{{ .image.repository }}{{- end -}}
{{- end }}

{{/*
Helper to support clusters with bad naming
*/}}
{{- define "template.clusterName" -}}
{{- if hasPrefix "cluster" .Values.global.clusterKey -}}
{{ .Values.global.environment }}-{{ .Values.global.clusterKey }}
{{- else -}}
{{ .Values.global.businessUnit }}-{{ .Values.global.environment }}-{{ .Values.global.clusterKey }}
{{- end -}}
{{- end -}}

{{/*
Helper to check if a range has a key
*/}}
{{- define "template.rangeHasPath" -}}
  {{- $keyPresent := false -}}
  {{- range . }}
    {{- if .path }}
      {{- $keyPresent = true -}}
    {{- end }}
  {{- end }}
  {{- $keyPresent -}}
{{- end }}