# Helm Chart Architecture Review: [VENDOR_NAME]

**Date:** [YYYY-MM-DD] | **Reviewer:** [CRE_NAME] | **Chart Version:** [vX.Y.Z]

---

## Summary

[2-3 sentences describing the application and overall assessment]

**Status:** [✅ Production-Ready / ⚠️ Needs Work / ❌ Blocked]

**Critical Issues:** [X] | **High Priority:** [X] | **Medium:** [X]

---

## Replicated Platform Integration

### Required Components

| Component | Status | Issue |
| :---- | :---- | :---- |
| Replicated SDK | [✅/❌] | [version or missing reason] |
| kind: HelmChart (v1beta2) | [✅/❌] | [notes if not v1beta2] |
| Preflight Checks | [✅/⚠️/❌] | [missing: disk, memory, k8s version, etc.] |
| Support Bundle | [✅/⚠️/❌] | [missing: logs, db checks, etc.] |
| Image Components (registry/repo/tag) | [✅/❌] | [hardcoded registry, missing split] |
| ImagePullSecrets | [✅/❌] | [not configurable] |
| Backup Hooks (if stateful) | [✅/❌/N/A] | [missing pre/post hooks] |
| Embedded Cluster Config | [✅/❌/N/A] | [extensions, overrides, node roles] |

**Air-gap Ready:** [✅ Yes / ❌ No - [reason]]

---

## Critical Antipatterns

### Arrays as Top-Level Keys

```
❌ CURRENT:
servers:
  - name: foo
    port: 80

✅ FIX TO:
servers:
  foo:
    port: 80
```

**Found in:** [list files/paths or "None"]

### Blocked Dependencies

- **Bitnami Charts:** [list if found or "None"]
- **Cloud-Specific:** [list AWS/Azure/GCP dependencies or "None"]

### Template Issues / Things to look for

- **[example] Declare template and helper functions properly**
  - helper functions should be prefixed (aka namespaced) with a chart or component name to prevent collisions with other helper functions from other charts
  - [list examples of found code, suggest improvements, or omit]
- **[example] Don't write namespaces into manifest templates**
  - Avoid adding namespace fields or resources into chart templates (Helm handles this, and all resources are installed into only one namespace)
  - [list examples, or omit]
- **YAML comments in logic:** [list or "None"]

### KOTS Templating Issues

- **YAML quoting**: [single vs double quotes with repl{{ }} or "None"]
- **Boolean comparisons**: [ConfigOptionEquals using "1" vs "true" or "None"]
- **optionalValues merge**: [recursiveMerge: true present or "None"]
- **builder key**: [static values only, all images included or "None"]

---

## Findings

### Critical (Fix Before Production)

**[C1] [Title]** - `path/to/file.yaml:123`

```
Current: [problematic code]
Fix: [corrected code]
```

*Why:* [explanation] *Impact:* [what breaks]

---

### High Priority (Fix Before GA)

**[H1] [Title]** - `path/to/file.yaml:456`

```
Current: [problematic code]
Fix: [corrected code]
```

*Why:* [explanation]

---

### Medium Priority (Recommended)

**[M1] [Title]** - [brief description]

---

## Replicated Release Integration

### HelmChart CR Assessment

| Check | Status | Notes |
| :---- | :---- | :---- |
| apiVersion: kots.io/v1beta2 | [✅/❌] | [notes] |
| Template function syntax correct | [✅/⚠️/❌] | [quoting, boolean, type issues] |
| optionalValues use recursiveMerge | [✅/⚠️/❌] | [list entries missing it] |
| Air-gap image rewriting | [✅/⚠️/❌] | [HasLocalRegistry patterns] |
| builder key covers all images | [✅/⚠️/❌] | [missing images] |
| exclude field logic correct | [✅/N/A] | [notes] |

### Config CR Assessment

| Check | Status | Notes |
| :---- | :---- | :---- |
| Boolean fields use type: bool | [✅/⚠️/❌] | [notes] |
| Required fields have defaults | [✅/⚠️/❌] | [missing defaults] |
| Conditional when clauses correct | [✅/⚠️/❌] | [notes] |
| Hidden generated secrets use value: not default: | [✅/⚠️/N/A] | [notes] |

---

## Action Items

### Must Fix

1. [C1] [Title] - [small/medium/large effort]
2. [C2] [Title] - [effort]
3. [H1] [Title] - [effort]

### Should Fix (Before GA)

1. [H2] [Title] - [effort]
2. [M1] [Title] - [effort]

### Optional Improvements

1. [M2] [Title]

---

## Next Steps

1. **Vendor Fixes** - Target: [date]
2. **Follow-up Review** - Target: [date]
3. **Testing** - Air-gap, KOTS integration
4. **Production Ready** - Target: [date]

---

## Notes

**Contacts:** [Vendor eng lead, email] **Installation Target:** [EC / Helm CLI / KOTS] **Environment:** [Customer cluster types]
