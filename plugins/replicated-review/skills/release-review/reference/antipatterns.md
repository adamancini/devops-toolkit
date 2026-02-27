# Helm Chart Antipatterns

A catalog of common Helm chart antipatterns with detection heuristics, wrong/correct examples, and files to check. Each antipattern is a recurring design mistake that causes deployment failures, upgrade breakage, or portability problems across Kubernetes distributions.

---

## 1. Arrays as Top-Level Keys

**Problem:** Using YAML arrays for named entities makes it impossible to override a single item without replacing the entire array. Helm's `--set` and values merge cannot target array elements by name.

**Detection:** Look for top-level values keys whose value is a list of objects with a `name` field.

**Files to check:** `values.yaml`

### Wrong

```yaml
# values.yaml
servers:
  - name: primary
    host: db1.example.com
    port: 5432
  - name: replica
    host: db2.example.com
    port: 5432
```

Overriding just the replica host requires replacing the whole array:
```bash
# This replaces the entire array, losing the primary entry
helm install app ./chart --set servers[1].host=db3.example.com
```

### Correct

```yaml
# values.yaml
servers:
  primary:
    host: db1.example.com
    port: 5432
  replica:
    host: db2.example.com
    port: 5432
```

Now individual items can be overridden cleanly:
```bash
helm install app ./chart --set servers.replica.host=db3.example.com
```

### Exception

Arrays are acceptable for truly ordered/anonymous lists (e.g., `ingress.hosts`, `tolerations`, `env` vars) where items have no stable identity.

---

## 2. Hardcoded Namespaces

**Problem:** Hardcoding `metadata.namespace` in templates or including a `Namespace` resource forces users into a specific namespace. This breaks `helm install -n <namespace>` and conflicts with GitOps tools that manage namespaces separately.

**Detection:** Search templates for `namespace:` that is not `{{ .Release.Namespace }}`. Search for `kind: Namespace` resources.

**Files to check:** All files in `templates/`

### Wrong

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "app.fullname" . }}
  namespace: my-app-system
```

```yaml
# templates/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app-system
```

### Correct

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "app.fullname" . }}
  # No namespace field -- Helm sets it from the release namespace
```

If a namespace is required for cross-namespace references (e.g., ClusterRoleBinding subjects), use `{{ .Release.Namespace }}`:

```yaml
subjects:
  - kind: ServiceAccount
    name: {{ include "app.fullname" . }}
    namespace: {{ .Release.Namespace }}
```

### Exception

Charts that manage CRDs or cluster-scoped resources may legitimately create namespaces, but these should be optional and disabled by default.

---

## 3. Bitnami Dependencies

**Problem:** Direct dependencies on Bitnami Helm charts create operational risk. Bitnami charts are deprecated or replaced without notice, use non-standard image sources, and frequently introduce breaking changes between minor versions. Their charts also pull large dependency trees.

**Detection:** Check `Chart.yaml` dependencies for `repository: https://charts.bitnami.com/bitnami` or `repository: oci://registry-1.docker.io/bitnamicharts`. Check `Chart.lock` for Bitnami references.

**Files to check:** `Chart.yaml`, `Chart.lock`, `charts/` directory

### Wrong

```yaml
# Chart.yaml
dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: https://charts.bitnami.com/bitnami
  - name: redis
    version: "17.x.x"
    repository: https://charts.bitnami.com/bitnami
  - name: cassandra
    version: "10.x.x"
    repository: https://charts.bitnami.com/bitnami
```

### Correct

Use operator-based alternatives that are actively maintained and designed for production:

| Bitnami Chart | Recommended Alternative |
|---------------|------------------------|
| `postgresql` | CloudNativePG operator (`cnpg.io`) |
| `mysql` / `mariadb` | Percona XtraDB Cluster operator |
| `redis` | Redis operator (Spotahome) or Dragonfly |
| `cassandra` | K8ssandra operator |
| `mongodb` | Percona MongoDB operator or MongoDB Community operator |
| `kafka` | Strimzi operator |
| `elasticsearch` | ECK (Elastic Cloud on Kubernetes) |

```yaml
# Chart.yaml -- using CloudNativePG instead of Bitnami PostgreSQL
dependencies:
  - name: cloudnative-pg
    version: "0.22.x"
    repository: https://cloudnative-pg.github.io/charts
```

If an operator is overkill for the use case, use upstream community charts (e.g., `ghcr.io/cloudnative-pg/postgresql` images directly).

---

## 4. Platform-Specific External Services

**Problem:** Hard dependencies on cloud-provider-specific services (AWS RDS, Azure Database, GCP Cloud SQL) make charts non-portable. Charts distributed via Replicated must work on any Kubernetes distribution, including air-gapped bare-metal.

**Detection:** Search values and templates for cloud-specific annotations (e.g., `service.beta.kubernetes.io/aws-load-balancer-*`), IAM role ARNs, cloud provider hostnames (`*.rds.amazonaws.com`, `*.database.azure.com`), or provider-specific CRDs.

**Files to check:** `values.yaml`, `templates/`, KOTS config

### Wrong

```yaml
# values.yaml
database:
  host: mydb.us-east-1.rds.amazonaws.com
  port: 5432

service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-internal: "true"
```

### Correct

Provide an embedded database option and make external connection details configurable without assuming a provider:

```yaml
# values.yaml
database:
  embedded:
    enabled: true
  external:
    enabled: false
    host: ""
    port: 5432
    username: ""
    password: ""

service:
  type: ClusterIP
  annotations: {}
```

Cloud-specific annotations should be documented as examples, not defaults:

```yaml
# values.yaml comments
service:
  annotations: {}
  # AWS NLB example:
  #   service.beta.kubernetes.io/aws-load-balancer-type: nlb
  # Azure Internal LB example:
  #   service.beta.kubernetes.io/azure-load-balancer-internal: "true"
```

---

## 5. Template Naming Collisions

**Problem:** Generic named template names like `define "fullname"` or `define "labels"` collide when multiple charts or subcharts are composed together. Helm has a flat template namespace across all charts in a release.

**Detection:** Search `_helpers.tpl` for `define` blocks that do not include the chart name as a prefix.

**Files to check:** `templates/_helpers.tpl`, all files in `templates/`

### Wrong

```yaml
# templates/_helpers.tpl
{{- define "fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "labels" -}}
app: {{ include "fullname" . }}
{{- end }}
```

### Correct

```yaml
# templates/_helpers.tpl
{{- define "myapp.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "myapp.labels" -}}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

The convention is `<chart-name>.<template-name>`. This matches the output of `helm create`.

---

## 6. YAML Comments in Template Logic

**Problem:** YAML comments (`# ...`) containing template expressions are silently ignored by Helm. The intent is usually to comment out a value while preserving the template expression, but YAML strips comments before Go template evaluation. This leads to "commented-out" values that appear to be configurable but never render.

**Detection:** Search for lines matching `#.*\{\{.*\.Values` or `#.*\{\{.*include`.

**Files to check:** All files in `templates/`

### Wrong

```yaml
# templates/deployment.yaml
resources:
  limits:
    # memory: {{ .Values.resources.limits.memory }}
    cpu: {{ .Values.resources.limits.cpu }}
```

The memory line is a YAML comment and is stripped entirely. The template expression never evaluates.

### Correct

Use Go template comments to preserve commented-out logic:

```yaml
# templates/deployment.yaml
resources:
  limits:
    {{- /* memory: {{ .Values.resources.limits.memory }} */ -}}
    cpu: {{ .Values.resources.limits.cpu }}
```

Or use conditional logic to control inclusion:

```yaml
resources:
  limits:
    {{- if .Values.resources.limits.memory }}
    memory: {{ .Values.resources.limits.memory }}
    {{- end }}
    cpu: {{ .Values.resources.limits.cpu }}
```

---

## 7. Excessive Nesting

**Problem:** Deeply nested values paths (4+ levels) make charts difficult to configure, especially with `--set` flags. They also increase the risk of nil pointer errors when intermediate keys are missing.

**Detection:** Count nesting depth in `values.yaml`. Flag paths deeper than 4 levels. In templates, look for long accessor chains like `.Values.a.b.c.d.e`.

**Files to check:** `values.yaml`, all files in `templates/`

### Wrong

```yaml
# values.yaml
app:
  server:
    web:
      frontend:
        config:
          timeout: 30
          maxRetries: 3
```

```bash
# Painful to override
helm install app ./chart \
  --set app.server.web.frontend.config.timeout=60
```

### Correct

```yaml
# values.yaml
frontend:
  timeout: 30
  maxRetries: 3
```

If grouping is needed, keep it to 2-3 levels maximum and use flat keys within groups:

```yaml
# values.yaml
server:
  frontendTimeout: 30
  frontendMaxRetries: 3
  backendPoolSize: 10
```

### Nil-Safety

When deep nesting cannot be avoided, use `dig` in templates to prevent nil panics:

```yaml
timeout: {{ dig "app" "server" "web" "frontend" "config" "timeout" 30 .Values }}
```

---

## 8. Missing Resource Requests/Limits

**Problem:** Containers without resource requests and limits cause scheduling unpredictability, noisy-neighbor problems, and potential node OOM kills. Many production clusters enforce resource quotas that reject pods without requests/limits.

**Detection:** Search Deployment, StatefulSet, Job, CronJob, and DaemonSet templates for containers missing `resources:` blocks. Check init containers as well.

**Files to check:** All files in `templates/` containing workload resources

### Wrong

```yaml
# templates/deployment.yaml
containers:
  - name: app
    image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
    ports:
      - containerPort: 8080
    # No resources block at all
```

### Correct

```yaml
# templates/deployment.yaml
containers:
  - name: app
    image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
    ports:
      - containerPort: 8080
    resources:
      {{- toYaml .Values.resources | nindent 6 }}
```

```yaml
# values.yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

Apply the same pattern to init containers:

```yaml
initContainers:
  - name: db-migrate
    image: {{ .Values.migration.image.repository }}:{{ .Values.migration.image.tag }}
    resources:
      {{- toYaml .Values.migration.resources | nindent 6 }}
```

### Exception

BEAM/OTP applications (Elixir, Erlang) should omit CPU limits because the BEAM scheduler degrades under CPU throttling. Use CPU requests only, with memory limits for OOM protection.

---

## 9. Missing Security Contexts

**Problem:** Pods without security contexts run as root by default, violate Pod Security Standards, and are rejected by many production clusters that enforce `restricted` or `baseline` policies.

**Detection:** Check all workload templates for missing `securityContext` at the pod level and `securityContext` at the container level. Look for missing `runAsNonRoot`, `readOnlyRootFilesystem`, and `drop: [ALL]` capabilities.

**Files to check:** All files in `templates/` containing workload resources

### Wrong

```yaml
# templates/deployment.yaml
spec:
  containers:
    - name: app
      image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
      # No securityContext
```

### Correct

```yaml
# templates/deployment.yaml
spec:
  securityContext:
    {{- toYaml .Values.podSecurityContext | nindent 8 }}
  containers:
    - name: app
      image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
      securityContext:
        {{- toYaml .Values.securityContext | nindent 12 }}
```

```yaml
# values.yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

### Minimum Viable Security Context

If the application genuinely requires root or write access to the filesystem, document why and still set what you can:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  # readOnlyRootFilesystem: false  -- app writes to /tmp
  # runAsNonRoot: false  -- legacy app requires UID 0
```

---

## 10. Missing Standard Labels

**Problem:** Without standard Kubernetes labels, resources cannot be queried, filtered, or managed by tools like `kubectl`, Prometheus label selectors, or Helm itself during upgrades. Missing labels also break `helm upgrade` when selectors change.

**Detection:** Check all resources for the presence of `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/version`, and `app.kubernetes.io/managed-by`. Check that Deployment selectors use immutable labels.

**Files to check:** `templates/_helpers.tpl`, all files in `templates/`

### Wrong

```yaml
# templates/deployment.yaml
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  selector:
    matchLabels:
      app: my-app
```

### Correct

```yaml
# templates/_helpers.tpl
{{- define "myapp.labels" -}}
helm.sh/chart: {{ include "myapp.chart" . }}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

```yaml
# templates/deployment.yaml
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "myapp.selectorLabels" . | nindent 6 }}
```

Selector labels (`name` + `instance`) must be immutable -- never include `version` or `chart` in selectors.

---

## 11. Hardcoded Image Registries

**Problem:** Hardcoded image registries prevent air-gap deployments, proxy registry usage, and private registry overrides. Charts distributed via Replicated must support `proxy.replicated.com` and local registry rewriting.

**Detection:** Search `values.yaml` and templates for image references that do not separate `registry`, `repository`, and `tag` into distinct fields. Look for `image:` values containing a full `registry/repo:tag` string.

**Files to check:** `values.yaml`, all files in `templates/` containing `image:`

### Wrong

```yaml
# values.yaml
image: docker.io/myorg/myapp:latest

# or partially split but no registry field
image:
  repository: myorg/myapp
  tag: latest
```

### Correct

```yaml
# values.yaml
image:
  registry: docker.io
  repository: myorg/myapp
  tag: "1.2.3"
  pullPolicy: IfNotPresent

imagePullSecrets: []
```

```yaml
# templates/deployment.yaml
containers:
  - name: app
    image: "{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    imagePullPolicy: {{ .Values.image.pullPolicy }}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 8 }}
{{- end }}
```

For Replicated distribution, the default registry should be `proxy.replicated.com/<appslug>`:

```yaml
image:
  registry: proxy.replicated.com
  repository: myvendor/myapp
  tag: "1.2.3"
```

### Multiple Images

For charts with multiple images (init containers, sidecars), each image needs its own registry/repository/tag split:

```yaml
app:
  image:
    registry: docker.io
    repository: myorg/myapp
    tag: "1.2.3"

migration:
  image:
    registry: docker.io
    repository: myorg/myapp-migrate
    tag: "1.2.3"
```

---

## 12. Secrets in Environment Variables

**Problem:** Mounting secrets as environment variables exposes them in pod specs (`kubectl get pod -o yaml`), process listings (`/proc/<pid>/environ`), crash dumps, and log output from frameworks that dump environment on startup. Volume-mounted secrets are more secure and can be rotated without pod restarts.

**Detection:** Search Deployment/StatefulSet templates for `env:` blocks referencing Secrets directly via `valueFrom.secretKeyRef` or inline `value:` fields containing secret data. Check for secrets in `envFrom.secretRef` as well.

**Files to check:** All files in `templates/` containing workload resources, `values.yaml`

### Wrong

```yaml
# templates/deployment.yaml
containers:
  - name: app
    env:
      - name: DATABASE_PASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ include "app.fullname" . }}-db
            key: password
      - name: API_KEY
        valueFrom:
          secretKeyRef:
            name: {{ include "app.fullname" . }}-api
            key: key
```

### Correct

Mount secrets as files and configure the application to read from the file path:

```yaml
# templates/deployment.yaml
containers:
  - name: app
    env:
      - name: DATABASE_PASSWORD_FILE
        value: /secrets/db/password
      - name: API_KEY_FILE
        value: /secrets/api/key
    volumeMounts:
      - name: db-secret
        mountPath: /secrets/db
        readOnly: true
      - name: api-secret
        mountPath: /secrets/api
        readOnly: true
volumes:
  - name: db-secret
    secret:
      secretName: {{ include "app.fullname" . }}-db
  - name: api-secret
    secret:
      secretName: {{ include "app.fullname" . }}-api
```

### Pragmatic Approach

If the application does not support reading secrets from files (legacy apps), env var secrets are acceptable but should be documented. Prefer `envFrom` with a single Secret over multiple `valueFrom` entries to reduce the attack surface in the pod spec:

```yaml
envFrom:
  - secretRef:
      name: {{ include "app.fullname" . }}-env
```

### Detection Heuristic

Count the number of `secretKeyRef` entries in each container spec. More than 2-3 is a strong signal that secrets should be volume-mounted instead.
