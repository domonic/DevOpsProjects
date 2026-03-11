# Troubleshooting EKS Upgrade Failures: Admission Webhook Deadlocks During Control Plane Bootstrap

## Issue Description

EKS cluster upgrades fail or experience extended readyz failures during control plane bootstrap. The kube-apiserver becomes deadlocked when admission webhooks (Gatekeeper ValidatingAdmissionPolicies or Kyverno mutating webhooks) block critical API server operations required for initialization. This prevents the cluster from completing the upgrade process.

&nbsp;

## Root Cause

During Kubernetes version upgrades, the kube-apiserver must complete several critical initialization tasks:

1. Create coordination leases for leader election
2. Update system ConfigMaps (e.g., `kube-system/extension-apiserver-authentication`)
3. Complete post-start hooks
4. Establish connectivity with etcd

When admission webhooks intercept these operations, a circular dependency deadlock can occur:

- **Gatekeeper scenario**: ValidatingAdmissionPolicies reference Custom Resource Definitions (CRDs) that require etcd access to validate. The API server cannot reach etcd to fetch these CRDs while simultaneously being blocked by the webhook from completing its own initialization.

- **Kyverno scenario**: Mutating webhooks attempt to validate or modify resources during bootstrap, but the webhook controller may not be compatible with the new Kubernetes version or fails to respond properly, blocking critical control plane operations.

The webhook blocks the API server → The API server cannot initialize → The webhook cannot function properly → Deadlock.

&nbsp;

## Symptoms

- Cluster upgrade stuck in "Updating" state for extended periods (30+ minutes or more)
- API server readyz health checks failing continuously
- Pods unable to schedule or update during upgrade
- Control plane logs showing admission webhook denials for system resources
- Timeout errors when attempting to access the cluster during upgrade

&nbsp;

## Troubleshooting Steps

### 1. Check Cluster Upgrade Status

```bash
aws eks describe-cluster --name <CLUSTER_NAME> --query 'cluster.status'
```

If the cluster shows `UPDATING` for an extended period, proceed with investigation.

&nbsp;

### 2. Review Control Plane Logs

Query the control plane audit logs for webhook-related denials:

```bash
fields @timestamp, verb, objectRef.resource, objectRef.name, objectRef.namespace, responseStatus.code, responseStatus.message
| filter @logStream like /audit/
| filter responseStatus.code >= 400
| filter responseStatus.message like /webhook/ or responseStatus.message like /admission/
| sort @timestamp desc
| limit 100
```

Look for patterns showing repeated denials of critical resources:
- Leases in `kube-system` namespace
- ConfigMaps like `extension-apiserver-authentication`
- Service IP repairs
- API server coordination resources

&nbsp;

### 3. Identify Active Admission Webhooks

#### List ValidatingAdmissionPolicies (Gatekeeper)

```bash
kubectl get validatingadmissionpolicies
```

Common problematic policies:
- `gatekeeper-k8spspprivilegedcontainer`
- `gatekeeper-k8spspallowprivilegeescalationcontainer`
- `gatekeeper-k8spspreadonlyrootfilesystem`

#### Inspect Policy Configuration

```bash
kubectl get validatingadmissionpolicy <POLICY_NAME> -o yaml
```

Check if the policy has namespace exclusions:

```yaml
spec:
  matchConstraints:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: NotIn
        values:
        - kube-system
        - kube-public
        - kube-node-lease
```

If `namespaceSelector` is missing or doesn't exclude system namespaces, this is likely the cause.

&nbsp;

#### List Mutating Webhooks (Kyverno)

```bash
kubectl get mutatingwebhookconfigurations
```

Common Kyverno webhooks:
- `kyverno-policy-mutating-webhook-cfg`
- `kyverno-resource-mutating-webhook-cfg`
- `kyverno-verify-mutating-webhook-cfg`

#### Inspect Webhook Configuration

```bash
kubectl get mutatingwebhookconfigurations <WEBHOOK_NAME> -o yaml
```

Check the `failurePolicy` and `namespaceSelector`:

```yaml
webhooks:
- name: mutate.kyverno.svc
  failurePolicy: Fail  # ⚠️ Blocks operations if webhook fails
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: NotIn
      values:
      - kube-system  # Should exclude system namespaces
```

&nbsp;

### 4. Check Webhook Controller Status

#### For Gatekeeper

```bash
kubectl get pods -n gatekeeper-system
kubectl logs -n gatekeeper-system deployment/gatekeeper-controller-manager --tail=100
```

#### For Kyverno

```bash
kubectl get pods -n kyverno
kubectl logs -n kyverno deployment/kyverno-admission-controller --tail=100
```

Look for errors related to:
- API version compatibility issues
- CRD access failures
- Timeout errors
- Connection refused errors

&nbsp;

### 5. Verify CRD Accessibility (Gatekeeper)

Check if the CRDs referenced by policies are accessible:

```bash
kubectl get crds | grep k8spsp
```

Expected CRDs:
- `k8spspreadonlyrootfilesystem.constraints.gatekeeper.sh`
- `k8spspallowprivilegeescalationcontainer.constraints.gatekeeper.sh`
- `k8spspprivilegedcontainer.constraints.gatekeeper.sh`

Attempt to describe a CRD:

```bash
kubectl get K8sPSPPrivilegedContainer
```

If this command hangs or times out during upgrade, it confirms the deadlock scenario.

&nbsp;

### 6. Review Control Plane Audit Logs for Specific Denials

Query for lease creation failures:

```bash
fields @timestamp, user.username, verb, objectRef.name, responseStatus.message
| filter @logStream like /audit/
| filter objectRef.resource = "leases"
| filter objectRef.namespace = "kube-system"
| filter responseStatus.code >= 400
| sort @timestamp desc
```

Query for ConfigMap update failures:

```bash
fields @timestamp, verb, objectRef.name, responseStatus.message
| filter @logStream like /audit/
| filter objectRef.resource = "configmaps"
| filter objectRef.name = "extension-apiserver-authentication"
| filter responseStatus.code >= 400
| sort @timestamp desc
```

&nbsp;

## Resolution

### Option 1: Configure Namespace Exclusions for Gatekeeper Policies

Add namespace selectors to exclude system namespaces from policy enforcement.

#### Method A: Patch Existing Policies

```bash
kubectl patch validatingadmissionpolicy gatekeeper-k8spspprivilegedcontainer --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/matchConstraints/namespaceSelector",
    "value": {
      "matchExpressions": [
        {
          "key": "kubernetes.io/metadata.name",
          "operator": "NotIn",
          "values": ["kube-system", "kube-public", "kube-node-lease"]
        }
      ]
    }
  }
]'

kubectl patch validatingadmissionpolicy gatekeeper-k8spspallowprivilegeescalationcontainer --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/matchConstraints/namespaceSelector",
    "value": {
      "matchExpressions": [
        {
          "key": "kubernetes.io/metadata.name",
          "operator": "NotIn",
          "values": ["kube-system", "kube-public", "kube-node-lease"]
        }
      ]
    }
  }
]'

kubectl patch validatingadmissionpolicy gatekeeper-k8spspreadonlyrootfilesystem --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/matchConstraints/namespaceSelector",
    "value": {
      "matchExpressions": [
        {
          "key": "kubernetes.io/metadata.name",
          "operator": "NotIn",
          "values": ["kube-system", "kube-public", "kube-node-lease"]
        }
      ]
    }
  }
]'
```

⚠️ **Note:** If the gatekeeper-controller-manager is running, these patches should persist. If changes don't persist, check the underlying Constraint resources.

&nbsp;

#### Method B: Update Constraint Resources

If patching policies doesn't persist, edit the Constraint resources directly:

```bash
kubectl get constraints
kubectl edit <CONSTRAINT_TYPE> <CONSTRAINT_NAME>
```

Add or update the namespace exclusions:

```yaml
spec:
  match:
    excludedNamespaces:
    - kube-system
    - kube-public
    - kube-node-lease
```

&nbsp;

#### Method C: Configure Gatekeeper Config (Global Exclusion)

Create or update the Gatekeeper Config to exclude system namespaces globally:

```yaml
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: gatekeeper-system
spec:
  match:
  - excludedNamespaces:
    - kube-system
    - kube-public
    - kube-node-lease
    processes: ["*"]
```

Apply the configuration:

```bash
kubectl apply -f gatekeeper-config.yaml
```

&nbsp;

### Option 2: Temporarily Disable Kyverno During Upgrade

If the cluster is stuck during upgrade, temporarily scale down the Kyverno admission controller:

```bash
kubectl scale deployment kyverno-admission-controller -n kyverno --replicas=0
```

This removes the mutating webhooks and allows the upgrade to proceed. Monitor the upgrade status:

```bash
aws eks describe-cluster --name <CLUSTER_NAME> --query 'cluster.{Status:status,Version:version}'
```

Once the upgrade completes successfully, scale Kyverno back up:

```bash
kubectl scale deployment kyverno-admission-controller -n kyverno --replicas=1
```

&nbsp;

### Option 3: Configure Kyverno Webhook Exclusions (Preventive)

Update Kyverno webhook configurations to exclude system namespaces:

```bash
kubectl edit mutatingwebhookconfiguration kyverno-resource-mutating-webhook-cfg
```

Add namespace selector to each webhook:

```yaml
webhooks:
- name: mutate.kyverno.svc
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: NotIn
      values:
      - kube-system
      - kube-public
      - kube-node-lease
  failurePolicy: Ignore  # Consider changing from Fail to Ignore for non-critical policies
```

Repeat for:
- `kyverno-policy-mutating-webhook-cfg`
- `kyverno-verify-mutating-webhook-cfg`

&nbsp;

### Option 4: Update Webhook Failure Policy

For non-critical policies, configure webhooks to fail open:

```bash
kubectl patch mutatingwebhookconfiguration <WEBHOOK_NAME> --type='json' -p='[
  {
    "op": "replace",
    "path": "/webhooks/0/failurePolicy",
    "value": "Ignore"
  }
]'
```

⚠️ **Note:** Only use `failurePolicy: Ignore` for policies where security requirements allow operations to proceed if the webhook is unavailable.

&nbsp;

## Verification

### Confirm Policy Updates

```bash
kubectl get validatingadmissionpolicy <POLICY_NAME> -o jsonpath='{.spec.matchConstraints.namespaceSelector}'
```

Expected output:

```json
{"matchExpressions":[{"key":"kubernetes.io/metadata.name","operator":"NotIn","values":["kube-system","kube-public","kube-node-lease"]}]}
```

&nbsp;

### Test System Namespace Operations

Create a test lease in kube-system to verify it's not blocked:

```bash
kubectl create lease test-lease -n kube-system
kubectl delete lease test-lease -n kube-system
```

If these commands complete without webhook denials, the configuration is correct.

&nbsp;

### Monitor Upgrade Progress

```bash
aws eks describe-cluster --name <CLUSTER_NAME> --query 'cluster.{Status:status,Version:version,Health:health}'
```

Watch for status to change from `UPDATING` to `ACTIVE`.

&nbsp;

### Check API Server Health

```bash
kubectl get --raw='/readyz?verbose'
```

All checks should return `ok`.

&nbsp;

## Prevention and Best Practices

### 1. Review Webhook Compatibility Before Upgrades

- Check if your Gatekeeper version supports the target Kubernetes version
- Check if your Kyverno version supports the target Kubernetes version
- Review release notes for both the Kubernetes version and admission controller versions

&nbsp;

### 2. Update Admission Controllers Before EKS Upgrades

Ensure admission controllers are running versions compatible with the target Kubernetes version:

```bash
# Check current versions
kubectl get deployment -n gatekeeper-system gatekeeper-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment -n kyverno kyverno-admission-controller -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Consult compatibility matrices:
- [Gatekeeper Compatibility](https://open-policy-agent.github.io/gatekeeper/website/docs/operations/#kubernetes-version-compatibility)
- [Kyverno Compatibility](https://kyverno.io/docs/installation/#compatibility-matrix)

&nbsp;

### 3. Configure Namespace Exclusions by Default

Always exclude system namespaces from admission policies:

```yaml
# For Gatekeeper policies
spec:
  matchConstraints:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: NotIn
        values:
        - kube-system
        - kube-public
        - kube-node-lease

# For Kyverno policies
spec:
  rules:
  - exclude:
      any:
      - resources:
          namespaces:
          - kube-system
          - kube-public
          - kube-node-lease
```

&nbsp;

### 4. Use Appropriate Failure Policies

Configure `failurePolicy` based on policy criticality:

- **Critical security policies**: `failurePolicy: Fail` (blocks operations if webhook unavailable)
- **Non-critical policies**: `failurePolicy: Ignore` (allows operations to proceed)

```yaml
webhooks:
- name: critical-security-policy
  failurePolicy: Fail
- name: best-practice-policy
  failurePolicy: Ignore
```

&nbsp;

### 5. Test Upgrades in Non-Production Environments

- Validate the upgrade process in staging clusters before production
- Test with the same admission controller configurations
- Monitor for webhook-related issues during test upgrades

&nbsp;

### 6. Monitor Webhook Health

Regularly check webhook configurations and operational status:

```bash
# List all webhooks
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations

# Check webhook endpoints
kubectl get validatingwebhookconfiguration <NAME> -o jsonpath='{.webhooks[*].clientConfig.service}'
kubectl get mutatingwebhookconfiguration <NAME> -o jsonpath='{.webhooks[*].clientConfig.service}'

# Verify webhook pods are healthy
kubectl get pods -n gatekeeper-system
kubectl get pods -n kyverno
```

&nbsp;

## Key Concepts

**Admission Webhooks**: Intercept requests to the Kubernetes API server before persistence, allowing validation or mutation of resources. They run after authentication and authorization but before the object is persisted to etcd.

**ValidatingAdmissionPolicy**: A Kubernetes-native admission control mechanism (introduced in 1.26, GA in 1.30) that validates resources using CEL (Common Expression Language) expressions. Gatekeeper uses this for policy enforcement.

**Mutating Webhooks**: Modify resources before they are persisted. Kyverno uses these to apply mutations, generate resources, and verify images.

**Failure Policy**: Determines webhook behavior when the webhook backend is unavailable:
- `Fail`: Reject the request (fail closed)
- `Ignore`: Allow the request to proceed (fail open)

**Namespace Selector**: Filters which namespaces a webhook applies to, allowing exclusion of system namespaces from policy enforcement.

**Bootstrap Deadlock**: A circular dependency where the API server cannot complete initialization because webhooks block critical operations, but the webhooks cannot function properly because the API server hasn't initialized.

&nbsp;

## Related AWS Documentation

- [EKS Cluster Upgrades](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html)
- [EKS Best Practices - Admission Controllers](https://aws.github.io/aws-eks-best-practices/security/docs/iam/#admission-controllers)
- [Kubernetes Admission Webhooks Best Practices](https://kubernetes.io/docs/concepts/cluster-administration/admission-webhooks-good-practices/)
- [Gatekeeper - Failing Closed and Cluster Availability](https://open-policy-agent.github.io/gatekeeper/website/docs/failing-closed/#cluster-control-plane-availability)
- [Gatekeeper - Webhook Limit Scope](https://open-policy-agent.github.io/gatekeeper/website/docs/operations/#webhook-limit-scope)
- [Kyverno Installation Guide](https://kyverno.io/docs/installation/)
- [Kyverno - Resource Filters](https://kyverno.io/docs/installation/customization/#resource-filters)
