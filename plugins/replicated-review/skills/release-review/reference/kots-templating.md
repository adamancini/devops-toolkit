# KOTS/Replicated Templating Reference

A reference for how Replicated KOTS template functions interact with Helm chart rendering. Covers the rendering pipeline, quoting rules, type coercion, and common patterns for HelmChart custom resources.

---

## 1. The Rendering Pipeline

KOTS processes HelmChart custom resources in three phases:

```
Phase 1: Go template rendering
   KOTS evaluates repl{{ }} and {{repl }} expressions as Go templates.
   Output: a string with all template functions resolved.

Phase 2: YAML parsing
   The rendered string is parsed as YAML.
   Output: a Go data structure (maps, slices, scalars).

Phase 3: Helm value injection
   Parsed values are passed to `helm template` / `helm upgrade`.
   Output: rendered Kubernetes manifests.
```

**Key implication:** Go template syntax rules apply *before* YAML rules. Quoting, escaping, and type handling must account for both layers. A value that looks correct as YAML may fail at the Go template phase.

---

## 2. YAML Quoting Rules

When a `repl{{ }}` expression contains double-quoted arguments and lives inside a YAML string value, always use single-quoted YAML strings.

```yaml
# WRONG -- backslash-escaped quotes break Go template parsing
HOST: "redis://:repl{{ ConfigOption \"valkey_password\" }}@redis:6379"
# Error: "unexpected \ in operand"

# RIGHT -- single-quoted YAML lets inner double quotes pass through
HOST: 'redis://:repl{{ ConfigOption "valkey_password" }}@redis:6379'
```

**Rule:** Single-quote any YAML value that contains `repl{{ }}` with inner double-quoted function arguments. This applies to `values`, `optionalValues`, connection strings, and annotation values.

---

## 3. Boolean Config Values: "0"/"1" Not true/false

KOTS `bool` type config items store values as the strings `"0"` and `"1"`, not YAML or Go booleans.

```yaml
# kots-config.yaml
- name: feature_enabled
  type: bool
  default: false    # stored as "0"

# HelmChart values -- compare against "1"
feature:
  enabled: repl{{ ConfigOptionEquals "feature_enabled" "1" }}

# WRONG -- these never match:
enabled: repl{{ ConfigOptionEquals "feature_enabled" "true" }}
enabled: repl{{ ConfigOptionEquals "feature_enabled" true }}
enabled: repl{{ ConfigOptionEquals "feature_enabled" 1 }}
```

`ConfigOptionEquals` returns Go booleans (`true`/`false`), which render as unquoted YAML booleans. This works correctly for Helm `enabled:` fields.

---

## 4. String-to-Bool Type Coercion

When `ConfigOptionEquals` renders `true` or `false`, KOTS strips surrounding quotes. The output is a bare YAML boolean, not a string.

This is usually correct for `enabled:` fields. It breaks when:

- The Helm chart expects a **string** (e.g., annotation values like `"false"`)
- You need the literal quoted string `"true"` preserved

```yaml
# Renders as: annotation_value: false  (boolean, not string)
annotation_value: repl{{ ConfigOptionEquals "feature_enabled" "1" }}
```

**Mitigation:** If the chart needs a quoted string, use `ConfigOption` and handle quoting at the Helm template level with `| quote`.

### The Truthiness Bug

A more insidious coercion problem occurs when KOTS converts a boolean value to a string during HelmChart CR value resolution. The boolean `false` becomes the string `"false"`, and in Go templates a non-empty string is truthy:

```yaml
# HelmChart CR -- KOTS renders this as the string "false", not boolean false
rook:
  enabled: repl{{ ConfigOptionEquals "rook_enabled" "1" }}
```

```yaml
# Chart template -- BROKEN: "false" (string) is truthy, block renders
{{- if .Values.rook.enabled }}
  # This renders even when rook is disabled!
{{- end }}
```

This causes both conditional branches to render simultaneously, leading to YAML parse errors or resource conflicts. The chart works correctly with standalone Helm (where booleans stay booleans) but breaks inside KOTS.

**Fix:** Use explicit boolean comparison in chart templates instead of bare truthiness checks:

```yaml
# WRONG -- bare truthiness, breaks with string coercion:
{{- if .Values.rook.enabled }}

# CORRECT -- explicit comparison, safe:
{{- if eq .Values.rook.enabled true }}

# ALSO CORRECT -- handles both string and boolean:
{{- if and .Values.rook.enabled (ne .Values.rook.enabled "false") }}
```

**Detection:** Search chart templates for bare `{{- if .Values.<key>.enabled }}` patterns where the value flows through a KOTS HelmChart CR. Any boolean value set via `repl{{ ConfigOptionEquals ... }}` is at risk.

---

## 5. optionalValues and recursiveMerge

By default, `optionalValues` performs a **shallow merge** -- only first-level keys are merged. Nested keys are overwritten entirely by the base `values.yaml`.

```yaml
# WRONG -- nested keys under gitea.config.cache get overwritten
optionalValues:
  - when: 'repl{{ ConfigOptionEquals "cache_enabled" "1" }}'
    values:
      gitea:
        config:
          cache:
            ADAPTER: redis

# RIGHT -- recursiveMerge preserves nested keys
optionalValues:
  - when: 'repl{{ ConfigOptionEquals "cache_enabled" "1" }}'
    recursiveMerge: true
    values:
      gitea:
        config:
          cache:
            ADAPTER: redis
```

**Rule:** Always use `recursiveMerge: true` on every `optionalValues` entry unless you intentionally want to replace the entire subtree.

Reference: [KOTS Issue #866](https://github.com/replicatedhq/kots/issues/866)

---

## 6. repl{{ }} vs {{repl }} Syntax

Both syntaxes invoke Replicated template functions, but they are not interchangeable:

| Context | Syntax | Example |
|---------|--------|---------|
| HelmChart `spec.values` | `repl{{ }}` | `enabled: repl{{ ConfigOptionEquals "x" "1" }}` |
| HelmChart `spec.optionalValues[].when` | Either (quoted) | `when: 'repl{{ ConfigOptionEquals "x" "1" }}'` |
| HelmChart `spec.exclude` | Either (quoted) | `exclude: 'repl{{ ConfigOptionEquals "x" "y" }}'` |
| KOTS Config `when` clauses | Either (quoted) | `when: 'repl{{ ConfigOptionEquals "x" "1" }}'` |
| `statusInformers` | `{{repl }}` | `'{{repl if ConfigOptionEquals "x" "1"}}...{{repl end}}'` |
| `kots.io/when` annotations | `{{repl }}` | `'{{repl ConfigOptionEquals "x" "y" }}'` |
| Raw K8s manifest values | `{{repl }}` | `'{{repl ConfigOption "name" }}'` |

**Key difference:** `{{repl }}` is required for Go template **control flow** (`if`/`end`/`range`/`with`). The `repl{{ }}` prefix syntax only works for **expressions** that return values.

---

## 7. Release.IsInstall / Release.IsUpgrade Are Broken Under KOTS

KOTS uses `helm template` internally, not `helm install`/`helm upgrade`. Consequently:

- `.Release.IsInstall` is always `true`
- `.Release.IsUpgrade` is always `false`

Do not use these in Helm templates distributed via KOTS. Use KOTS-level mechanisms instead:
- Config options for install-vs-upgrade logic
- `optionalValues` with `when` conditions
- `kots.io/when` annotations

Reference: [Community: Helm Release.IsInstall and IsUpgrade are inaccurate](https://community.replicated.com/t/helm-release-isinstall-and-isupgrade-are-inaccurate/1189)

---

## 8. lookup() Not Supported

Because KOTS renders charts with `helm template` (no cluster connection), the Helm `lookup()` function always returns empty. Charts using `lookup()` for secret preservation or resource detection behave as if those resources do not exist.

**Alternative for secret generation under KOTS:**

```yaml
# kots-config.yaml -- generates once, persists across upgrades
- name: app_secret_key
  type: password
  hidden: true
  value: '{{repl RandomString 32}}'
```

Use `value:` (not `default:`) with `hidden: true` so the value is set once on first install and preserved across upgrades.

Reference: [Community: Is the Helm lookup() function supported?](https://community.replicated.com/t/is-the-helm-lookup-function-supported/1060)

---

## 9. Air-Gap Image Rewriting Patterns

Three patterns exist for rewriting image references when `HasLocalRegistry` is true.

### Pattern 1: Separate registry/repository fields (preferred)

```yaml
image:
  registry: '{{repl HasLocalRegistry | ternary LocalRegistryHost "quay.io" }}'
  repository: '{{repl HasLocalRegistry | ternary LocalRegistryNamespace "jetstack" }}/cert-manager-controller'
```

### Pattern 2: Combined repository with `print`

```yaml
image:
  repository: repl{{ HasLocalRegistry | ternary (print LocalRegistryHost "/cloudnative-pg/postgresql") "ghcr.io/cloudnative-pg/postgresql" }}
```

### Pattern 3: Multi-expression concatenation

```yaml
image:
  repository: '{{repl HasLocalRegistry | ternary LocalRegistryHost "ghcr.io" }}/{{repl HasLocalRegistry | ternary LocalRegistryNamespace "wg-easy" }}/wg-easy'
```

### Critical Rules

- **Image name uniqueness:** KOTS strips paths and keeps only `name:tag` when pushing to local registries. Two images named `postgres:16` from different source registries will collide. Use distinct image names.
- **`spec.builder` must be static:** The `builder` key must contain hardcoded upstream image locations (no template functions) so air-gap bundles include all images.
- **`ImagePullSecretName`:** Add to every Pod spec for private registry auth.

---

## 10. Type Conversion Functions

Config values are always strings. Convert when Helm expects specific types:

```yaml
# Integer (port numbers, replica counts)
port: repl{{ ConfigOption "vpn_port" | ParseInt }}

# Boolean from string config (not a bool-type config item)
deploy: repl{{ ConfigOption "deploy_feature" | ParseBool }}

# File content with YAML block scalar
cert: repl{{ print `|`}}repl{{ ConfigOptionData `tls_cert` | nindent 12 }}
```

**Notes:**
- `ConfigOptionData` (not `ConfigOption`) is required for `file` type config items.
- The `repl{{ print | }}` trick emits a YAML literal block scalar indicator before file content.
- `ParseInt` returns an unquoted integer in YAML; `ParseBool` returns an unquoted boolean.

---

## 11. Embedded vs External Database Toggle Pattern

A standard pattern for charts supporting both embedded and external databases:

```yaml
# HelmChart spec.values
postgres:
  embedded:
    enabled: 'repl{{ ConfigOptionNotEquals "postgres_external" "1" }}'
  external:
    enabled: repl{{ ConfigOptionEquals "postgres_external" "1" }}

# optionalValues -- inject external details only when external is selected
optionalValues:
  - when: 'repl{{ ConfigOptionEquals "postgres_external" "1" }}'
    recursiveMerge: true
    values:
      postgres:
        external:
          host: repl{{ ConfigOption "external_postgres_host" }}
          password: repl{{ ConfigOption "external_postgres_password" }}
```

To skip the embedded database chart entirely, use `exclude` on its HelmChart CR:

```yaml
# Separate HelmChart CR for the database subchart
exclude: 'repl{{ ConfigOptionEquals "postgres_external" "1" }}'
```

Use `ConfigOptionNotEquals` for inverse conditions -- it is cleaner than `not (ConfigOptionEquals ...)`.

---

## 12. Builder Key Requirements

The `spec.builder` key in HelmChart CRs defines the values used during air-gap bundle building. It must contain:

- **Static/hardcoded** upstream image locations (no template functions)
- All images that the chart may reference under any configuration
- The superset of all optional images (even if disabled by default)

```yaml
spec:
  builder:
    image:
      registry: docker.io
      repository: myorg/myapp
      tag: "1.2.3"
    redis:
      image:
        registry: docker.io
        repository: redis
        tag: "7.2"
```

If the builder key is missing or incomplete, air-gap bundles will be missing images, causing `ImagePullBackOff` failures in disconnected environments.

---

## 13. LicenseFieldValue Returns Strings

`LicenseFieldValue` always returns a string regardless of the license field type. Pipe through conversion functions:

```yaml
# WRONG -- compares a string, not a boolean
premium:
  enabled: repl{{ LicenseFieldValue "premium_feature" }}

# RIGHT -- convert to boolean
premium:
  enabled: repl{{ LicenseFieldValue "premium_feature" | ParseBool }}

# RIGHT -- convert to integer
maxNodes: repl{{ LicenseFieldValue "max_nodes" | ParseInt }}
```

---

## 14. Deleting Values with "null"

To delete a key from the chart's `values.yaml` during KOTS deployment, set it to the quoted string `"null"`:

```yaml
# CORRECT -- deletes the key from values
unwantedKey: "null"

# WRONG -- YAML null type, does not trigger deletion
unwantedKey: null
```

The quoted string `"null"` is a Helm-specific convention that removes the key from the merged values.

---

## 15. Raw YAML Textarea Pattern

When accepting arbitrary YAML from users (node selectors, labels, annotations), use `type: textarea` and handle the empty case:

```yaml
# kots-config.yaml
- name: custom_annotations
  type: textarea
  default: ""

# HelmChart values -- empty guard prevents broken YAML
annotations: 'repl{{ if ConfigOptionEquals "custom_annotations" "" }}{}repl{{ else }}repl{{ ConfigOption "custom_annotations" | nindent 6 }}repl{{end}}'
```

Without the empty-case guard, an empty textarea renders as bare `""`, which breaks YAML mapping expectations downstream.

Reference: [Community: Configuring Helm Charts with Raw YAML Data in KOTS](https://community.replicated.com/t/configuring-helm-charts-with-raw-yaml-data-in-kots/1554)

---

## Supplemental: The Four-Way Contract

When distributing Helm charts via Replicated, four artifacts must stay in sync:

```
values.yaml  <->  KOTS Config  <->  KOTS HelmChart  <->  development-values.yaml
    (1)               (2)               (3)                     (4)
```

1. **Chart `values.yaml`** -- schema and defaults Helm expects
2. **`kots-config.yaml`** -- Admin Console UI (field types, defaults, conditionals)
3. **HelmChart CR `spec.values`** -- maps KOTS config to Helm values
4. **`development-values.yaml`** -- headless/CI testing without Admin Console

Every config option in (2) needs a mapping in (3) that produces values matching (1)'s schema. A mismatch between any pair causes deployment failures.

## Supplemental: KOTS Template Functions Do Not Work Inside Helm Charts

KOTS template functions (`ConfigOption`, `HasLocalRegistry`, etc.) are never evaluated inside Helm chart template files (`.tpl`, `templates/*.yaml`). They only work in KOTS custom resources: HelmChart CR, Config, Application, SupportBundle, etc.

The HelmChart CR is the bridge -- it maps KOTS-rendered values into the chart's `values.yaml`. The Helm chart itself should be a standard chart that works with `helm install`.

## Supplemental: Generated Defaults Are Ephemeral

Default values for config items (especially generated ones like certificates from `genCA`/`genSignedCert`) are recalculated each time application configuration is modified. TLS cert/key pairs can become mismatched after a config change.

**Fix:** For values that must persist, use `value:` (not `default:`) with `hidden: true`:

```yaml
- name: app_secret_key
  type: password
  hidden: true
  value: '{{repl RandomString 32}}'
```

Reference: [KOTS Issue #518](https://github.com/replicatedhq/kots/issues/518)
