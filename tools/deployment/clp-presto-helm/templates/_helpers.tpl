{{/*
Chart name, overridable via `nameOverride`.
*/}}
{{- define "clp-presto.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified release name, overridable via `fullnameOverride`.
*/}}
{{- define "clp-presto.fullname" -}}
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
A resource name for one component, reserving the suffix before truncating to the 63-char limit.
@param {dict} root The root context.
@param {string} component The suffix, e.g. "coordinator".
*/}}
{{- define "clp-presto.componentFullname" -}}
{{- $suffix := printf "-%s" .component -}}
{{- $maxBaseLength := sub 63 (len $suffix) | int -}}
{{- $base := include "clp-presto.fullname" .root | trunc $maxBaseLength | trimSuffix "-" -}}
{{- printf "%s%s" $base $suffix -}}
{{- end }}

{{- define "clp-presto.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "clp-presto.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clp-presto.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "clp-presto.labels" -}}
helm.sh/chart: {{ include "clp-presto.chart" . }}
{{ include "clp-presto.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Resolves an image reference from `.Values.image.<component>`, requiring at least one of `tag` or
`digest`. Usage: `include "clp-presto.imageRef" (dict "root" . "component" "coordinator")`.
*/}}
{{- define "clp-presto.imageRef" -}}
{{- $img := index .root.Values.image .component -}}
{{- if not (or $img.tag $img.digest) -}}
  {{- fail (printf "image.%s requires \"tag\" or \"digest\"" .component) -}}
{{- end -}}
{{- $ref := $img.repository -}}
{{- if $img.tag -}}
  {{- $ref = printf "%s:%s" $ref $img.tag -}}
{{- end -}}
{{- if $img.digest -}}
  {{- $ref = printf "%s@%s" $ref $img.digest -}}
{{- end -}}
{{- $ref -}}
{{- end }}

{{/*
Renders a container's `image:` and `imagePullPolicy:`, so the component is named once.
@param {dict} root The root context.
@param {string} component A key under `.Values.image`.
*/}}
{{- define "clp-presto.imageSpec" -}}
{{- $img := index .root.Values.image .component -}}
image: {{ include "clp-presto.imageRef" (dict "root" .root "component" .component) | quote }}
imagePullPolicy: {{ $img.pullPolicy | quote }}
{{- end }}

{{/*
Renders a `resources:` block, omitting it entirely when neither requests nor limits are set.
@param {dict} . The component's `resources` value.
*/}}
{{- define "clp-presto.resources" -}}
{{- $config := . | default dict -}}
{{- if or $config.requests $config.limits }}
resources:
{{- with $config.requests }}
  requests:
    {{- toYaml . | nindent 4 }}
{{- end }}
{{- with $config.limits }}
  limits:
    {{- toYaml . | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Renders nodeSelector/tolerations/affinity for a component.
@param {dict} . The component's value block.
*/}}
{{- define "clp-presto.schedulingConfigs" -}}
{{- $config := . | default dict -}}
{{- with $config.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $config.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $config.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
The in-cluster URI of the coordinator's HTTP endpoint.
*/}}
{{/*
The `presto.version` both nodes announce. A worker whose value differs from the coordinator's still
registers and answers health checks, but is never counted in `activeWorkers`, so queries queue
forever. Deriving it from the chart makes the two agree by construction, which is why neither node
has to ask the other for it at startup.
@param {dict} . The root context.
*/}}
{{- define "clp-presto.prestoVersion" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version -}}
{{- end }}

{{- define "clp-presto.discoveryUri" -}}
{{- printf "http://%s:8889" (include "clp-presto.componentFullname" (dict "root" . "component" "coordinator")) -}}
{{- end }}

{{/*
Copies the connector plugin into the shared `presto-plugin` volume, then exits. The installer
image reads the target from a per-component environment variable.
@param {dict} root The root context.
@param {string} component "coordinator" or "worker".
*/}}
{{- define "clp-presto.installPluginInitContainer" -}}
{{- $component := .component -}}
- name: "install-clp-plugin"
  {{- include "clp-presto.imageSpec" (dict "root" .root "component" "connector") | nindent 2 }}
  env:
    - name: "{{ upper $component }}_PLUGIN_INSTALL_PATH"
      value: "/install/{{ $component }}"
  {{- include "clp-presto.resources" (index .root.Values $component).installPlugin.resources | nindent 2 }}
  volumeMounts:
    - name: "presto-plugin"
      mountPath: "/install/{{ $component }}"
{{- end }}

{{/*
Rolls the pods when the rendered config changes. Without this a `helm upgrade` that only touches
the ConfigMap leaves the running pods on their old config.
*/}}
{{- define "clp-presto.configChecksumAnnotation" -}}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- end }}

{{/*
The volumes shared by both components: the connector catalog, the full config map, and the
emptyDir the plugin is installed into.
@param {dict} root The root context.
@param {string} component "coordinator" or "worker".
*/}}
{{- define "clp-presto.commonVolumes" -}}
{{- $configName := include "clp-presto.componentFullname" (dict "root" .root "component" "config") -}}
- name: "presto-catalog"
  configMap:
    name: {{ $configName }}
    items:
      - key: "{{ .component }}-catalog-clp.properties"
        path: "clp.properties"
- name: "presto-config"
  configMap:
    name: {{ $configName }}
- name: "presto-plugin"
  emptyDir: {}
{{- end }}

{{/*
The PersistentVolumeClaim holding archives, shared by both components.
@param {dict} root The root context.
@param {string} requiredBy Text naming the setting that makes the claim mandatory.
*/}}
{{- define "clp-presto.archivesVolume" -}}
- name: "archives"
  persistentVolumeClaim:
    claimName: {{ required
      (printf "archiveStorage.fs.existingClaim is required when %s" .requiredBy)
      .root.Values.archiveStorage.fs.existingClaim | quote }}
{{- end }}
