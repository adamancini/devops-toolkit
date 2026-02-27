# Replicated CRE Helm Chart Architecture Runbook

## Overview

This document provides a comprehensive procedure for Replicated Customer Reliability Engineers (CREs) to perform Helm Chart Architecture Reviews for vendor applications. The goal is to ensure charts follow best practices and are properly integrated with the Replicated platform.

## Review Outcomes

1. **Avoid Common Antipatterns**: Identify and recommend fixes for patterns that impede usability or maintainability
2. **Ensure Replicated Platform Integration**: Verify all necessary Replicated components are present and properly configured

## References

- [Postgres vs CloudNativePG](https://docs.google.com/document/d/1h92cNkSEuItmY8egaVRLiVfTHSSiDVECbCMYC7045pI/edit?tab=t)
- [Customer/Vendor Best Practices](https://docs.google.com/document/d/1Rw2VAKm8Ey2Odm7TsaJd2TloWpxE1mus49GEKQtwEr4/edit?tab=t.0)
- [Observed Challenges for Helm](https://docs.google.com/document/d/1vSWclyw1VNado0BL9adHggxjONc8LvVlNDQqchwJ0ZM/edit?tab=t.0)

---

## 1. Initial Information Gathering

### What to Request from the Vendor

When starting a Helm Chart Architecture Review, request the following from the vendor:

#### Required Assets

- [ ] **Helm Chart(s)** - All charts including main application chart and any subcharts
- [ ] **Release Assets** - Any additional manifests, scripts, or configuration files
- [ ] **Default Values** - Complete `values.yaml` with all configuration options that would be needed to successfully install the application
- [ ] **Documentation** - Installation guides, configuration references, upgrade procedures

#### Environment Context

- [ ] **Target Customer Environments**
      - What type of Kubernetes clusters? (EKS, GKE, AKS, on-prem, etc.)
      - Cluster size and node specifications
      - Network policies or restrictions

- [ ] **Air Gap Requirements**
      - Will customers deploy in air-gapped environments?
      - Image registry strategy for air-gap

- [ ] **Installation Method**
      - Embedded Cluster only?
      - Helm CLI support required?
      - KOTS/Existing-Cluster is actively discouraged in favor of Helm CLI installers

#### Outstanding Items

- [ ] **Known Missing Features** - Items needed but not yet included in packaging
- [ ] **Future Roadmap** - Planned additions or changes
- [ ] **Customer-Specific Requirements** - Special use cases or constraints

---

## 2. Expected Components Checklist

### Replicated Platform Integration

#### Required Components

- [ ] **Replicated SDK Helm Chart**
      - Included as dependency in `Chart.yaml`
      - Properly configured in templates
      - Latest stable version

- [ ] **kind: HelmChart**
      - Must be present in all Replicated release (even helm-cli only)
      - Expected for some Vendor Portal features to work (Security Center, Helm Airgap instructions)
      - Uses `apiVersion: kots.io/v1beta2` (not v1beta1)
      - No KOTS `repl{{...}}` template functions in Helm chart templates

- [ ] **Preflight Checks**
      - Defined for critical requirements (disk, memory, CPU, network)
      - Checks for required Kubernetes versions
      - Validates storage class availability
      - Tests connectivity to external dependencies

- [ ] **Support Bundle Collectors**
      - Custom collectors for application logs
      - Database connectivity checks
      - Configuration snapshots
      - Pod and service status

#### Image Configuration

- [ ] **Separate Repository/Registry/Image/Tag Components**
      - **(Strongly Suggested for first-party charts)**

```yaml
image:
  registry: docker.io
  repository: mycompany/myapp
  tag: v1.2.3
```

      - Separate Repo and Registry elements make it easier to just override the registry portion
      - Enables Replicated image registry proxy injection
      - Supports air-gap scenarios

- [ ] **ImagePullSecrets**
      - Should create a Secret from `global.replicated.dockerconfigjson` that gets injected by the registry when a customer pulls
      - Allow for a secret name to be provided by the customer for overrides

#### Backup and Recovery

- [ ] **Velero Backup Hooks** (if using stateful components)
      - Pre-backup hooks for database dumps
      - Post-restore hooks for data recovery
      - Backup annotations on relevant PVCs

- [ ] **Disaster Recovery Documentation**
      - Backup procedures
      - Restore procedures
      - RTO/RPO specifications

---

## 3. Antipatterns to Identify and Fix

#### Creating literal Namespace resources and hardcoding `metadata.namespace` in resources

**Antipattern:**

```yaml
# charts/super-cool/chart/templates/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: super-cool

# charts/super-cool/chart/templates/deployment.yaml
apiVersion: v1
kind: Deployment
metadata:
  name: nginx
  namespace: super-cool
```

**Problems:**

* Generally, the client needs to be in charge of what namespace resources are created in.
* If you don't specify a namespace in your manifests, then the client is free to do things like:
  * e.g. `helm install super-cool --namespace other-ns --create-namespace` will create the `other-ns` namespace and deploy `super-cool` chart to `other-ns`
  * Admin Console / KOTS will deploy the application to the same namespace that the KOTS pod runs in, by default - for Embedded Cluster end-customers, they are not expected to have to know about namespaces, etc.
  * Some vendors may insist that their application relies on having a particular namespacing structure, either to comply with their end-customers policies or by developer guidelines/policy.  In this case, making the namespace field a value that can be overridden, but supply sane defaults, is the best compromise.
  * You can use the `.Release` values like `.Release.namespace` to use the namespace evaluated at runtime

**Correct Pattern:**

```yaml
# charts/super-cool/chart/templates/deployment.yaml
apiVersion: v1
kind: Deployment
metadata:
  name: nginx
  namespace: {{ .Release.namespace }}
```

**Benefits:**

* Allows the client to specify the installation namespace
* The namespace resource itself isn't managed by Helm templates, so the namespace lifecycle isn't affected by helm operations - this may be important for multi-tenant & managed clusters

#### Arrays as Top-Level Values Keys

**Antipattern:**

```yaml
servers:
  - name: foo
    port: 80
  - name: bar
    port: 81
```

**Problems:**

- Cannot use `--set` to override specific elements
- Fragile: reordering breaks overrides
- Not indexable by key

**Correct Pattern:**

```yaml
servers:
  foo:
    port: 80
  bar:
    port: 81
```

**Benefits:**

- Easy override: `--set servers.foo.port=8080`
- Order-independent
- Indexable and maintainable

#### Excessive Nesting

**Antipattern:**

```yaml
app:
  server:
    web:
      frontend:
        config:
          timeout: 30
```

**Problems:**

* Excessive levels of nesting can lead to really long statements like `Values.app.server.web.frontend.config.timeout`
* Makes visually identifying a value more complex the longer a statement gets
* Sometimes unavoidable, but probably points to chart logic that could be handled by a helper function or partial template, or by wrapping a third-party chart with a first-party chart wrapper that makes it easier to map simple values statements into a more complex values schema.

**Correct Pattern:**

```yaml
webServerTimeout: 30
# or
webServer:
  timeout: 30
```

#### Bitnami Charts

**Discouraged:**

- Direct dependency on Bitnami charts
- Bitnami PostgreSQL, MySQL, Redis, etc.
- Historically, have problems with major upgrades due to the way that Helm handles (rather, doesn't handle) CRDs

**Why:** Bitnami public charts and images have been deprecated and will no longer be available in the future.

**Alternatives:**

- CloudNativePG for PostgreSQL
- Percona operators for MySQL
- Redis operator or vendored Redis chart
- Any first-party option from a recognized software vendor
- A library chart pattern like `bjw-s/common-template`

#### Platform-Specific External Services

**Discouraged:**

- Hard dependencies on AWS RDS, Azure Database, GCS, etc.
- Cloud provider-specific storage classes as only option
- Load balancer types that only work in specific clouds

**Correct Pattern:**

- Support for both external and in-cluster databases
- Configurable storage class with sensible defaults
- Support for NodePort, ClusterIP, and LoadBalancer services
- Bring-your-own Ingress or Gateway
- **S3:** MinIO has moved from an foss model to a closed/commercial model - there are some other open source alternatives like SeaweedFS and Rook/Ceph

#### Avoid Template Naming Collisions

From the Helm docs:

> *Template names are global. As a result of this, if two templates are declared with the same name the last occurrence will be the one that is used. Since templates in subcharts are compiled together with top-level templates, it is best to name your templates with chart specific names. A popular naming convention is to prefix each defined template with the name of the chart: {{ define "mychart.labels" }}.*

**Antipattern:**

```yaml
{{- define "fullname" -}}
{{/* ... */}}
{{ end -}}
```

**Correct Pattern:**

```yaml
{{- define "myapp.fullname" -}}
{{/* ... */}}
{{ end -}}
```

#### YAML Comments in Template Logic

**Antipattern:**

```yaml
# memory: {{ required "maxMem must be set" .Values.maxMem | quote }}
```

**Problem:** YAML comments are retained during rendering, causing errors

**Correct Pattern:**

```yaml
{{- /*
memory: {{ required "maxMem must be set" .Values.maxMem | quote }}
*/ -}}
```

### Naming Conventions

**Use:**

- camelCase for values keys
- Lowercase with hyphens for resource names

**Avoid:**

- snake_case in values
- Mixed case in resource names

#### KOTS Templating Gotchas

When reviewing HelmChart custom resources, check for these common issues:

- **YAML quoting with template functions**: Use single-quoted YAML strings when `repl{{ }}` expressions contain inner double quotes. Double-quoted strings with backslash escapes cause "unexpected \\ in operand" errors because KOTS processes Go templates before YAML parsing.

  ```yaml
  # Wrong
  HOST: "redis://:repl{{ ConfigOption \"password\" }}@redis:6379"

  # Correct
  HOST: 'redis://:repl{{ ConfigOption "password" }}@redis:6379'
  ```

- **Boolean config values**: KOTS `bool` config items store values as strings `"0"` and `"1"`, not `true`/`false`. Always compare with `ConfigOptionEquals "field" "1"`.

- **optionalValues merge behavior**: Always use `recursiveMerge: true` on `optionalValues` entries. Without it, nested keys are overwritten entirely by the base `values.yaml`.

- **repl{{ }} vs {{repl }}**: Use `repl{{ }}` for value expressions in `spec.values`. Use `{{repl }}` for Go template control flow (`if`/`end`) in statusInformers, annotations, and raw manifests.

- **Release.IsInstall / Release.IsUpgrade**: Always wrong under KOTS (IsInstall=true, IsUpgrade=false). Do not use in Helm templates distributed via KOTS.

- **lookup() function**: Not supported under KOTS (returns empty). Use Replicated `RandomString` in kots-config.yaml for secret generation instead.

- **builder key**: Must contain static/hardcoded values only (no template functions). Required for air-gap image discovery.

- **Type conversions**: Config values are always strings. Use `ParseInt` for ports/replicas, `ParseBool` for boolean strings, `ConfigOptionData` (not `ConfigOption`) for file-type config items.

- **Unquoted `when` clauses in Config CR**: Always single-quote `when` values that contain `repl{{ }}` expressions. Unquoted values work in most cases but are fragile and inconsistent with other KOTS CR contexts. <!-- added: 2026-02-27 -->

  ```yaml
  # Wrong -- unquoted, fragile:
  when: repl{{ (ConfigOptionEquals "feature_enabled" "1")}}

  # Correct -- single-quoted, consistent:
  when: 'repl{{ ConfigOptionEquals "feature_enabled" "1" }}'
  ```

---

## 4. Patterns Requiring Deep Investigation

### Helm Hooks

<!-- added: 2026-02-27 -->

**Questions to Answer:**

- Are Helm hooks used? If so, what are their purposes?
- Do hooks reference CRD-managed resources (e.g., operator CRs)?
- What is the `hook-delete-policy`?
- Do hooks use `pre-install` only, or do they also include `pre-upgrade`?

**Antipattern: Hooks on Operator-Managed CRs**

Using `helm.sh/hook: pre-install` with `helm.sh/hook-delete-policy: hook-succeeded` on CRD-based resources (e.g., CNPG `Cluster`, K8ssandraCluster, MinIO `Tenant`) is destructive. Helm will delete the CR immediately after it is created successfully, which causes the operator to tear down the managed workload.

```yaml
# WRONG -- Helm will delete this Cluster CR after it is created:
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  annotations:
    "helm.sh/hook": pre-install
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  instances: 3
  ...
```

```yaml
# CORRECT -- Operator CRs should be regular Helm-managed resources:
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres
  labels:
    {{- include "app.labels" . | nindent 4 }}
spec:
  instances: {{ .Values.postgres.instances }}
  ...
```

**Antipattern: Conditional Hooks Inside `with` Blocks**

Placing hook annotations inside a `{{- with .Values.annotations }}` block means hooks are only active when the user provides custom annotations. This creates a latent trap: the chart works fine by default, but adding any annotation activates destructive hook behavior.

```yaml
# DANGEROUS -- hooks activate only when annotations are set:
{{- with .Values.annotations }}
annotations:
  {{- toYaml . | nindent 4 }}
  "helm.sh/hook": pre-install
  "helm.sh/hook-delete-policy": hook-succeeded
{{- end }}
```

Always review hooks for unintended interaction with conditional template blocks.

### Secrets Management

**Questions to Answer:**

- How are secrets created and managed?
- Are secrets templated securely?
- Can secrets be provided externally (e.g., from sealed secrets, vault)?
- Are there default/placeholder secrets that need rotation?

**Best Practices:**

- Support for external secret providers
- Generate random secrets if not provided
- Clear documentation on secret rotation

### Certificate Management

**Questions to Answer:**

- How are TLS certificates managed?
- Can customers provide their own certificates?
- Is cert-manager integration available?
- Are certificates automatically rotated?

**Best Practices:**

- Support for custom certificates via values
- Taking TLS certs in via values can blow up a large umbrella chart's Helm Secret past 1MB etcd limit
  - for large charts, consider spinning TLS cert creation out to a separate chart, or for helm installs have the user do `kubectl create secret` as appropriate and take only a Secret name
- Optional cert-manager integration
- Self-signed certificate generation for testing
- Clear documentation on certificate lifecycle

### Database Configuration

**Questions to Answer:**

- In-cluster database supported?
- External database connection supported?
- Are migrations handled properly?
- Backup/restore procedures defined?

**Best Practices:**

- Support both in-cluster and external databases
- Use CloudNativePG or similar operators (not Bitnami)
- Include database migration jobs
- Document backup and restore procedures
- Configure Velero with appropriate backup hooks and resource annotations

### Optional Components

**Questions to Answer:**

- Which components are optional?
- How are optional components enabled/disabled?
- Are dependencies properly configured with conditions/tags?

**Best Practices:**

- Use `.enabled` flags for optional components
- Condition-based dependency management
- Clear documentation of minimal vs. full deployments

### Storage Requirements

**Questions to Answer:**

- What are the PVC requirements?
- Which storage classes are supported?
- Are volume sizes configurable?
- Is there a migration path for data?

**Best Practices:**

- Configurable storage class
- Configurable volume sizes with sensible defaults
- Support for resizing volumes
- Backup/restore of persistent data

### Ingress and Networking

**Questions to Answer:**

- How is external access configured?
- Which ingress controllers are supported?
- Are network policies defined?
- Is service mesh support required?
  - Note: asking an end customer to install something like Istio can be difficult at cluster scope

**Best Practices:**

- Support multiple ingress controllers
- Configurable service types (ClusterIP, NodePort, LoadBalancer)
- Optional network policies
- Document port requirements

### Cross-Referencing Checks

<!-- added: 2026-02-27 -->

These checks validate consistency across the four-way contract (values.yaml, KOTS Config, HelmChart CR, development-values.yaml).

#### Orphan Values in HelmChart CR

Values set in the HelmChart CR `spec.values` that the chart's templates never read are silently ignored. This often indicates a schema mismatch between the HelmChart CR and the chart.

**Detection:** For each top-level key in HelmChart CR `spec.values`, verify that the chart's templates or subcharts actually reference `.Values.<key>`. Pay special attention to `enabled` flags at the wrong nesting level (e.g., `postgres.enabled` vs `postgres.embedded.enabled`).

```yaml
# WRONG -- HelmChart CR sets postgres.enabled but chart reads postgres.embedded.enabled:
spec:
  values:
    postgres:
      enabled: repl{{ ConfigOptionEquals "postgres_enabled" "1" }}
      embedded:
        enabled: 'repl{{ ConfigOptionNotEquals "postgres_external" "1" }}'

# CORRECT -- only set values the chart actually reads:
spec:
  values:
    postgres:
      embedded:
        enabled: 'repl{{ and (ConfigOptionEquals "postgres_enabled" "1") (ConfigOptionNotEquals "postgres_external" "1") }}'
      external:
        enabled: repl{{ and (ConfigOptionEquals "postgres_enabled" "1") (ConfigOptionEquals "postgres_external" "1") }}
```

#### Subchart Image Air-Gap Coverage

When a chart includes subcharts, every subchart image must be covered by air-gap rewriting patterns in the HelmChart CR. Subcharts have their own default image references that are not automatically proxied.

**Detection:** Extract subchart archives from `charts/` and check their `values.yaml` for `image.repository` fields. Verify each image has a corresponding override in the HelmChart CR with `HasLocalRegistry` / `LocalRegistryHost` patterns.

Common misses:
- Third-party subcharts pulled via `helm dependency update` (NFS server, Redis, etc.)
- Init container images defined in subchart templates
- Sidecar images injected by subchart logic

#### Config Item `when` Guard Completeness

Every KOTS Config item that belongs to an optional component should have a `when` clause gating its visibility on the parent component's `enabled` toggle. Missing guards clutter the Admin Console with irrelevant fields.

**Detection:** For each config group associated with an optional component (e.g., Cassandra, PostgreSQL, MinIO), verify that all items except the master `enabled` toggle have a `when` clause referencing that toggle.

```yaml
# WRONG -- credential fields visible even when component is disabled:
- name: cassandra_user
  title: Cassandra Superuser
  type: text
  default: cassandra

# CORRECT:
- name: cassandra_user
  title: Cassandra Superuser
  type: text
  default: cassandra
  when: 'repl{{ ConfigOptionEquals "cassandra_enabled" "1" }}'
```

#### Template Hardcoded Values

Templates that hardcode values instead of reading from `.Values.*` create a disconnect where the HelmChart CR and KOTS Config expose a setting, but the chart ignores it.

**Detection:** For each configurable field in the HelmChart CR, grep the corresponding template to verify it reads from `.Values`.

```yaml
# WRONG -- template ignores .Values.postgres.embedded.instances:
spec:
  instances: 1

# CORRECT:
spec:
  instances: {{ .Values.postgres.embedded.instances | default 1 }}
```

---

## 5. General Kubernetes Architecture

### Resource Configuration

- [ ] Resource requests and limits defined
      - CPU limits are not always necessary and [sometimes harmful](https://home.robusta.dev/blog/stop-using-cpu-limits)
      - CPU Requests should be defined
      - Memory requests and limits should be defined
      - Don't forget Jobs, CronJobs, and initContainers!
      - Consider that Kubernetes supports [priorityClasses](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/#priorityclass) for QoS
      - Consider that podDisruptionBudgets can interfere with some operations that might be required during maintenance or upgrades e.g. EC must drain pods, and PDBs can interfere with the cluster upgrade operator if it is unable to drain pods protected by PDBs
        1. we **have** received support cases for this issue

### High Availability

- [ ] Multiple replicas for stateless components
- [ ] Anti-affinity rules for pod distribution
- [ ] Topology spread constraints
- [ ] Readiness and liveness probes configured
- [ ] Consider stateful application PVC requirements for HA clusters
      - Are applications using application clustering or do we need replicated storage?  Generally, using an in-app clustering mechanism is preferred over shipping replicated storage like Rook-Ceph

### Security

- [ ] SecurityContext defined (runAsNonRoot, drop capabilities, etc.)
      - Example openshift-compliant `securityContext` that passes the `restricted-v2` SCC on OpenShift and compiles with the `restricted` Pod Security Standard in upstream k8s
      - **Don't set `runAsUser` or `runAsGroup` explicitly** - OpenShift's restricted SCC allocates UIDs/GIDs from a namespace-specific range. Hardcoding values will likely fail admission.
      - **`readOnlyRootFilesystem: true`** is technically optional for the restricted SCC but strongly recommended. If your app needs to write temp files, add an `emptyDir` volume at `/tmp`.

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: your-image:tag
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        readOnlyRootFilesystem: true
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
```

- [ ] Pod Security Standards compliance
- [ ] RBAC minimal permissions
      - [Replicated SDK minimum RBAC is described here](https://docs.replicated.com/vendor/replicated-sdk-customizing#install-the-sdk-with-custom-rbac)
- [ ] Network policies (if applicable)
- [ ] Prefer that secrets not exposed in environment variables (use volumes)
      - always include a way for an end-user to provide their own secrets managed out of band of the release (support External Secrets Providers like vault, SOPS, Sealed Secrets, etc.)

### Observability

- [ ] Metrics endpoints exposed (Prometheus format)
- [ ] ServiceMonitor resources (if using Prometheus Operator)
- [ ] Structured logging configuration
- [ ] Health check endpoints

---

## 6. Common Labels

All resources should include these recommended labels:

```yaml
metadata:
  labels:
    app.kubernetes.io/name: {{ template "myapp.name" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
    helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
```

Optional but useful:

```yaml
    app.kubernetes.io/component: frontend
    app.kubernetes.io/part-of: my-application
```

Here's a helper function definition for `_helpers.tpl`:

```yaml
{{/*
Common labels
*/}}
{{- define "myapp.labels" -}}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "myapp.chart" . }}
{{- end }}

{{/*
Chart name and version for helm.sh/chart label
*/}}
{{- define "myapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels (subset for matchLabels)
*/}}
{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

Usage in a template:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "myapp.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "myapp.selectorLabels" . | nindent 8 }}
```

A few notes:

* Separated out `selectorLabels` since you can't use version/chart labels in `matchLabels` (they're immutable after creation and would break upgrades)
* Added the `trunc 63` to the chart helper since label values have a 63 character limit
* The `AppVersion` check prevents empty labels if it's not set in `Chart.yaml`
* There should be allowances for an end-user to supply their own labels and annotations in addition to what a vendor would configure - they may have their own policies about labeling or need annotations for things like cost allocation, monitoring systems like datadog, etc.
* TODO: insert example: end-user supplied values

---

## 7. Testing and Validation

### Pre-Review Testing

- [ ] `helm lint` passes without errors
- [ ] `helm template` renders correctly
- [ ] Install on test cluster succeeds
- [ ] Application functions as expected
- [ ] Uninstall is clean (no orphaned resources for `helm uninstall` - EC has `reset` subcommand)

### Air Gap Testing

- [ ] All images can be relocated to private registry
- [ ] Image pull secrets work correctly
- [ ] No internet-dependent init containers or jobs
- [ ] No runtime package installation (`apk add`, `apt-get`, `yum`) in containers, init containers, or Jobs
- [ ] Helm chart can be packaged and deployed offline

#### Runtime Package Installation in Air-Gap <!-- added: 2026-02-27 -->

Containers, init containers, and Jobs that install packages at runtime (e.g., `apk add curl jq`) will fail in air-gap environments where package repositories are unreachable. This is a common pattern in setup Jobs that need tools like `curl` or `jq`.

```yaml
# WRONG -- fails in air-gap:
command:
  - sh
  - -c
  - |
    apk add --no-cache curl jq
    curl -sf http://service/api ...

# CORRECT -- use a pre-built image with required tools:
image: curlimages/curl:latest   # or build a custom image
command:
  - sh
  - -c
  - |
    curl -sf http://service/api ...

# ALTERNATIVE -- use wget (built into Alpine/BusyBox) with shell-based parsing:
command:
  - sh
  - -c
  - |
    wget -qO- http://service/api ...
```

**Detection:** Search Jobs and init containers for `apk add`, `apt-get install`, `yum install`, or `pip install` commands.

### KOTS Integration Testing

- [ ] KOTS application installs successfully
- [ ] Admin console displays configuration correctly
- [ ] Preflight checks run and report accurately
- [ ] Support bundle collects relevant data
- [ ] Backup/restore functions correctly

#### Embedded Cluster Considerations

- [ ] **EmbeddedClusterConfig CR** present and valid
- [ ] Extensions configured appropriately
- [ ] No unsupported overrides without justification
- [ ] Node role configuration reviewed
- [ ] Ingress options hidden on EC (built-in ingress controller)
- [ ] Distribution-specific conditionals used where needed (`ne Distribution "embedded-cluster"`)
- [ ] Storage considerations reviewed (built-in OpenEBS)

---

## 8. Review Deliverable Structure

### [Deliverable Template](https://docs.google.com/document/d/1J5_0grPa6DXjWtJGXla9kzOF_JX8wyv5mpvX3EQzoeM/edit?tab=t.0#heading=h.yry4152dwurd)

### Executive Summary

```markdown
## Helm Chart Architecture Review: [Vendor Name] [Application Name]

**Review Date:** YYYY-MM-DD
**Reviewer:** [CRE Name]
**Chart Version:** vX.Y.Z
**Status:** Approved / Approved with Recommendations / Changes Required

### Overview
[Brief description of the application and chart structure]

### Key Findings
- [Major finding 1]
- [Major finding 2]
- [Major finding 3]

### Recommendation Summary
- **Critical Issues:** [count] - Must be fixed before production
- **High Priority:** [count] - Should be fixed before GA
- **Medium Priority:** [count] - Recommended for improved usability
- **Low Priority:** [count] - Nice to have improvements
```

### Detailed Findings

For each finding, include:

````markdown
#### [Issue Title]

**Severity:** Critical / High / Medium / Low
**Category:** Antipattern / Security / Performance / Usability / Replicated Integration
**Location:** `path/to/file.yaml:123`

**Current Implementation:**
```yaml
# Show the problematic code
```

**Issue:** [Explain why this is a problem]

**Recommendation:**
```yaml
# Show the corrected code
```

**Impact:**
- [What breaks if not fixed]
- [What improves when fixed]

**Resources:**
- [Link to documentation]
- [Link to example]
````

### Replicated Platform Integration Checklist

Include the completed checklist from Section 2 showing which components are present and which are missing.

### Priority Action Items

```markdown
## Action Items for [Vendor Name]

### Critical (Before Production)
1. [ ] Convert top-level arrays to maps in values.yaml
2. [ ] Add Replicated SDK chart dependency
3. [ ] Configure image registry components for air-gap support

### High Priority (Before GA)
1. [ ] Remove Bitnami chart dependencies
2. [ ] Add preflight checks for system requirements
3. [ ] Implement backup hooks for stateful components

### Medium Priority (Recommended)
1. [ ] Add network policies
2. [ ] Improve resource requests/limits
3. [ ] Add Pod disruption budgets

### Low Priority (Nice to Have)
1. [ ] Add ServiceMonitor resources
2. [ ] Improve documentation
3. [ ] Add more granular configuration options
```

### Follow-Up Plan

```markdown
## Next Steps

1. **Vendor Action:** Address critical and high priority items
2. **CRE Review:** Schedule follow-up review in [X weeks]
3. **Testing:** Perform installation testing after changes
4. **Documentation:** Update installation guides with findings
5. **Handoff:** Brief assigned TAM/CSM on requirements

**Target Production-Ready Date:** YYYY-MM-DD
```

---

## 10. Additional Resources

- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Replicated Helm Documentation](https://docs.replicated.com/vendor/helm-overview)
- [Kubernetes Documentation](https://kubernetes.io/docs/concepts/)
- [CloudNativePG Documentation](https://cloudnative-pg.io/)

---

## Appendix: Quick Reference

### Common Values.yaml Structure

```yaml
# Global settings
global:
  imageRegistry: docker.io
  imagePullSecrets: []
  storageClass: ""

# Component configuration (use maps, not arrays)
components:
  frontend:
    enabled: true
    replicas: 2
    image:
      repository: myapp/frontend
      tag: v1.0.0
      pullPolicy: IfNotPresent
    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 512Mi
        cpu: 500m
  backend:
    enabled: true
    replicas: 3
    image:
      repository: myapp/backend
      tag: v1.0.0
    resources:
      requests:
        memory: 512Mi
        cpu: 250m

# Database configuration
database:
  # Use external database
  external:
    enabled: false
    host: ""
    port: 5432
    name: myapp
    username: ""
    password: ""

  # Use in-cluster database (CloudNativePG)
  embedded:
    enabled: true
    storageClass: ""
    storageSize: 10Gi
    replicas: 3

# Ingress configuration
ingress:
  enabled: true
  className: nginx
  annotations: {}
  hosts:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: myapp-tls
      hosts:
        - myapp.example.com

# Replicated SDK
replicated:
  integration:
    enabled: true
    licenseID: ""
```

### Common Chart.yaml Structure

```yaml
apiVersion: v2
name: myapp
description: My Application Helm Chart
type: application
version: 1.0.0
appVersion: "1.0.0"

dependencies:
  # Replicated SDK (required)
  - name: replicated
    repository: oci://registry.replicated.com/library
    version: 1.0.0-beta.22
    condition: replicated.integration.enabled

  # Database (CloudNativePG, not Bitnami)
  - name: cloudnative-pg
    repository: https://cloudnative-pg.github.io/charts
    version: 0.18.0
    condition: database.embedded.enabled

  # Other dependencies
  - name: redis
    repository: https://charts.example.com
    version: 7.0.0
    condition: redis.enabled

maintainers:
  - name: Engineering Team
    email: eng@example.com

keywords:
  - application
  - replicated
  - kubernetes
```

---

## Changelog

- **2026-02-27**: Added findings from StorageBox review (second pass): unquoted `when` clause antipattern in KOTS Config CR (Section 3), runtime package installation air-gap check and detection heuristic (Section 7).
- **2026-02-27**: Added findings from StorageBox review: Helm Hooks section (hooks on operator-managed CRs, conditional hook trap), Cross-Referencing Checks section (orphan values, subchart image air-gap coverage, Config item when-guard completeness, template hardcoded values).
- **2026-02-27**: Initial import from CRE Helm Chart Architecture Runbook. Added KOTS templating gotchas section. Added Embedded Cluster review items.
