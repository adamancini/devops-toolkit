# Embedded Cluster Reference

A reference for reviewing Helm charts and Replicated releases targeting Embedded Cluster (EC) deployments. Covers the EmbeddedClusterConfig CR, built-in components, extension management, node roles, and patterns for charts that must work on both EC and existing-cluster installs.

---

## 1. EmbeddedClusterConfig CR

The `EmbeddedClusterConfig` custom resource defines the cluster configuration for Embedded Cluster installations. It is included in the Replicated release alongside other KOTS manifests.

```yaml
apiVersion: embeddedcluster.replicated.com/v1beta1
kind: EmbeddedClusterConfig
metadata:
  name: appslug
spec:
  version: "1.x.x"                    # EC version to use
  roles:
    controller:
      name: management
      description: "Management node"
      labels:
        management: "true"
    custom:
      - name: worker
        description: "Worker node"
        labels:
          worker: "true"
  extensions:
    helm:
      - name: openebs
        chartname: openebs/openebs
        version: "3.x.x"
        namespace: openebs
        values: |
          localprovisioner:
            hostpathClass:
              isDefaultClass: true
  unsupportedOverrides:
    k0s: |
      config:
        spec:
          network:
            podCIDR: 10.244.0.0/16
```

### Key Fields

| Field | Purpose |
|-------|---------|
| `spec.version` | EC release version; determines k0s version and bundled component versions |
| `spec.roles` | Node role definitions (controller, controller+worker, custom) |
| `spec.extensions.helm` | Helm charts deployed as cluster infrastructure extensions |
| `spec.unsupportedOverrides` | Direct k0s configuration overrides (use with caution) |

---

## 2. Extensions

Extensions are Helm charts deployed alongside the cluster infrastructure during EC installation. They provide storage, ingress, backup, and registry capabilities.

### Available Extensions

| Extension | Purpose | Default Status |
|-----------|---------|---------------|
| `openebs` | Local PV storage provisioner | Built-in, enabled by default |
| `registry` | In-cluster container registry for air-gap | Built-in for air-gap installs |
| `ingress-nginx` | Ingress controller | Built-in, enabled by default |
| `velero` | Backup and restore | Optional, user-configured |

### Extension Configuration

Extensions are configured through the `spec.extensions.helm` array. Each entry specifies a chart, version, namespace, and values override:

```yaml
spec:
  extensions:
    helm:
      - name: ingress-nginx
        chartname: ingress-nginx/ingress-nginx
        version: "4.8.x"
        namespace: ingress-nginx
        values: |
          controller:
            service:
              type: NodePort
              nodePorts:
                http: 80
                https: 443
```

### Extension Ordering

Extensions are installed in the order listed. Dependencies matter: if a chart needs a storage class, `openebs` must appear before it in the list.

---

## 3. Unsupported Overrides

Unsupported overrides allow direct modification of the k0s configuration. They are called "unsupported" because they bypass the tested/validated EC configuration path.

### What They Are

Raw k0s config YAML injected into the cluster bootstrap configuration. They can modify networking (CNI, pod CIDR, service CIDR), kubelet arguments, API server flags, and other low-level cluster settings.

```yaml
spec:
  unsupportedOverrides:
    k0s: |
      config:
        spec:
          network:
            provider: custom
            podCIDR: 10.244.0.0/16
            serviceCIDR: 10.96.0.0/12
```

### Risks

- **No upgrade path validation.** Overrides are not tested against EC version upgrades and may break during cluster updates.
- **Support implications.** Replicated support may not be able to troubleshoot clusters with unsupported overrides.
- **Silent breakage.** k0s config changes can conflict with EC's expected state, causing subtle failures in networking, DNS, or storage.

### When Acceptable

- **Network CIDR conflicts.** When the default pod/service CIDRs overlap with the customer's existing network.
- **Corporate proxy configuration.** Injecting HTTP_PROXY/NO_PROXY environment variables for kubelet.
- **Specific compliance requirements.** Audit logging, API server flags mandated by security policy.

Always document the override, its purpose, and the EC versions it has been tested against.

---

## 4. Node Roles

EC supports three types of node roles that control workload scheduling.

### Controller

Management-plane-only nodes. Run etcd, API server, controller-manager, and scheduler. Application workloads are not scheduled here by default.

```yaml
roles:
  controller:
    name: management
    description: "Runs control plane components only"
```

### Controller + Worker

Combined nodes that run both control plane and application workloads. This is the default for single-node EC installations.

For single-node installs, the node is implicitly controller+worker. No explicit role configuration is needed.

### Custom Roles

Application-defined worker roles with specific labels for workload targeting:

```yaml
roles:
  custom:
    - name: gpu-worker
      description: "GPU-accelerated worker nodes"
      labels:
        gpu: "true"
        node-role.kubernetes.io/gpu: ""
    - name: storage-worker
      description: "Nodes with local NVMe storage"
      labels:
        storage: "true"
```

Charts can use these labels in `nodeSelector` or `nodeAffinity` rules:

```yaml
# values.yaml
nodeSelector:
  gpu: "true"
```

### Review Considerations

- Verify that charts using `nodeSelector` or `nodeAffinity` document which EC roles they require.
- Check that the EmbeddedClusterConfig defines roles matching the labels the chart expects.
- Single-node installs must work without any custom role labels (all workloads on one node).

---

## 5. Built-in Components and Chart Design Impact

EC bundles several infrastructure components that affect how application Helm charts should be designed.

### Ingress Controller (nginx)

EC includes ingress-nginx by default. Charts should not install their own ingress controller on EC.

**Impact on chart design:**
- Hide ingress class name configuration on EC (it is always `nginx`)
- Do not allow users to select ingress class when running on EC
- Ingress resources should work without specifying `ingressClassName` on EC (the built-in controller is the default)

```yaml
# kots-config.yaml -- hide ingress class on EC
- name: ingress_class_name
  type: text
  title: Ingress Class Name
  default: "nginx"
  when: 'repl{{ ne Distribution "embedded-cluster" }}'
```

**Port configuration:** EC's ingress-nginx typically uses NodePort with ports 80/443 mapped directly. LoadBalancer service type is not applicable on bare-metal EC installs without MetalLB.

### Storage (OpenEBS)

EC includes OpenEBS with local PV provisioner by default, providing a `local-path` (or `openebs-hostpath`) storage class.

**Impact on chart design:**
- Do not assume a specific storage class name; make it configurable
- Local PV storage is node-local and does not support ReadWriteMany (RWX) access mode
- StatefulSets with local PVs are pinned to their node; pod rescheduling requires manual PV migration
- Storage class defaults should work on EC without user configuration

```yaml
# values.yaml
persistence:
  storageClass: ""   # empty string uses the cluster default
  size: 10Gi
  accessModes:
    - ReadWriteOnce
```

### Registry (Air-Gap)

EC includes a built-in container registry for air-gap installations. Images are pushed to this registry during installation and are available to the cluster without external network access.

**Impact on chart design:**
- Image references must support rewriting via `HasLocalRegistry` / `LocalRegistryHost` in the HelmChart CR
- All images must be listed in the `spec.builder` key for air-gap bundle inclusion
- `imagePullSecrets` must reference `ImagePullSecretName` for local registry auth

---

## 6. Distribution-Specific Conditionals

Use the `Distribution` template function to detect EC and conditionally show/hide configuration.

### The Pattern

```yaml
when: 'repl{{ ne Distribution "embedded-cluster" }}'
```

This evaluates to `true` on all distributions *except* Embedded Cluster. Use it to hide configuration that EC manages automatically.

### Common Applications

**Hide ingress configuration on EC:**

```yaml
# kots-config.yaml
- name: ingress_type
  title: Ingress Type
  type: select_one
  when: 'repl{{ ne Distribution "embedded-cluster" }}'
  items:
    - name: ingress_controller
      title: Ingress Controller
    - name: load_balancer
      title: Load Balancer
```

**Hide ingress class and annotation fields on EC:**

```yaml
- name: ingress_class_name
  type: text
  title: Ingress Class Name
  default: "nginx"
  when: 'repl{{ and (ne Distribution "embedded-cluster") (ConfigOptionEquals "ingress_type" "ingress_controller") }}'

- name: ingress_annotations
  type: textarea
  title: Ingress Annotations
  when: 'repl{{ and (ne Distribution "embedded-cluster") (ConfigOptionEquals "ingress_type" "ingress_controller") }}'
```

**Hide load balancer options on EC:**

```yaml
- name: load_balancer_port
  title: Load Balancer Port
  type: text
  when: 'repl{{ and (ne Distribution "embedded-cluster") (ConfigOptionEquals "ingress_type" "load_balancer") }}'
```

### Compound Conditions

Combine `Distribution` checks with config option checks using `and`/`or`:

```yaml
when: 'repl{{ and (ne Distribution "embedded-cluster") (ConfigOptionEquals "feature_x" "1") }}'
```

---

## 7. Dual-Mode Charts: EC and Existing Cluster

Charts distributed via Replicated often need to work on both EC and Helm CLI / existing cluster installs. Key considerations:

### Ingress Strategy

| Concern | Embedded Cluster | Existing Cluster |
|---------|-----------------|-----------------|
| Ingress controller | Built-in nginx | User-provided (may be Traefik, HAProxy, etc.) |
| Ingress class | Fixed: `nginx` | Configurable |
| Service type | ClusterIP behind built-in ingress | ClusterIP, LoadBalancer, or NodePort |
| TLS | User configures at ingress level | User configures at ingress or LB level |

**Pattern:** Default to ingress-based access. On EC, use the built-in ingress controller with a sane default. On existing clusters, expose ingress class, annotations, and service type as configurable options.

### Storage Strategy

| Concern | Embedded Cluster | Existing Cluster |
|---------|-----------------|-----------------|
| Default storage class | OpenEBS local PV | Varies (EBS gp3, Longhorn, Rook-Ceph, etc.) |
| RWX support | No (unless added) | Depends on CSI driver |
| Dynamic provisioning | Yes (local PV) | Usually yes |

**Pattern:** Use empty `storageClass` to pick the cluster default. Do not hardcode storage class names. Document RWX requirements if the chart needs them (EC will need an additional storage extension).

### Registry and Image Pulling

| Concern | Embedded Cluster (Air-Gap) | Existing Cluster |
|---------|---------------------------|-----------------|
| Image source | Built-in local registry | Direct pull or proxy.replicated.com |
| Image pull secrets | `ImagePullSecretName` | User-configured or Replicated proxy secret |

**Pattern:** Always support `imagePullSecrets` and registry overrides in values. Use `HasLocalRegistry` ternary patterns in the HelmChart CR for air-gap image rewriting.

### Configuration Visibility

Use `Distribution` checks to hide EC-managed settings from the Admin Console while keeping them available for existing-cluster installs. The chart's `values.yaml` should have sensible defaults for both scenarios without requiring Distribution-aware logic in the Helm templates themselves.

```yaml
# HelmChart CR -- set EC-specific defaults
values:
  ingress:
    className: repl{{ eq Distribution "embedded-cluster" | ternary "nginx" (ConfigOption "ingress_class_name") }}
```

### Testing Checklist

When reviewing dual-mode charts, verify:

- [ ] Chart installs on EC single-node without custom configuration
- [ ] Chart installs on an existing cluster (EKS/GKE/AKS/k3s) with appropriate values
- [ ] Ingress works on EC with the built-in nginx controller
- [ ] Ingress works on existing clusters with user-specified ingress class
- [ ] Air-gap install pulls all images from the local registry
- [ ] Storage claims use the cluster default storage class (no hardcoded class name)
- [ ] Config options managed by EC are hidden in the Admin Console on EC installs
- [ ] Node role labels match between EmbeddedClusterConfig and chart nodeSelector/affinity rules
