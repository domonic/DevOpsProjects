# EKS Cluster Migration — Blue/Green Strategy

A complete guide to migrating workloads from an existing EKS cluster (blue) to a newly provisioned cluster (green) with zero or minimal downtime.

---

## When to Migrate vs. In-Place Upgrade

| Scenario | Approach |
|----------|----------|
| Minor version bump (1.29 → 1.30) | In-place upgrade (`upgrade.py`) |
| Major architecture change (new VPC, different instance types, Graviton migration) | Cluster migration |
| Skipping multiple versions where in-place is risky | Cluster migration |
| Changing cluster configuration that can't be modified post-creation (encryption, service CIDR, private/public endpoint) | Cluster migration |
| Compliance requirement for immutable infrastructure | Cluster migration |
| Disaster recovery validation | Cluster migration |

---

## Considerations & Prerequisites

### Networking

- **VPC design**: Decide whether the new cluster lives in the same VPC (simpler service discovery, shared subnets) or a new VPC (full isolation, requires peering/transit gateway during migration).
- **Pod CIDR overlap**: If both clusters run simultaneously in the same VPC, ensure pod CIDRs don't overlap. Use custom networking with the VPC CNI or distinct secondary CIDRs.
- **DNS propagation**: If using Route 53 weighted routing for traffic shifting, TTLs must be low (30–60s) before cutover begins.
- **Security groups**: The new cluster's node and pod security groups must allow communication with shared dependencies (RDS, ElastiCache, etc.) during and after migration.
- **Load balancers**: External ALBs/NLBs may need target group switching or weighted target groups. Internal service-to-service traffic may rely on service mesh or DNS.

### Stateful Workloads

- **PersistentVolumes (EBS)**: EBS volumes are AZ-bound. If the new cluster uses different AZs, you'll need to snapshot and restore. Same-AZ migration can reattach volumes directly.
- **EFS**: Shared across AZs and clusters — no migration needed, just mount in the new cluster.
- **Databases**: If running in-cluster databases (not recommended for production), plan data export/import. Managed services (RDS, DynamoDB) are external and unaffected.
- **StatefulSets**: Require careful ordering — scale down in old cluster, verify data persistence, scale up in new cluster.

### IAM & Security

- **IRSA (IAM Roles for Service Accounts)**: OIDC provider is cluster-specific. You must create a new OIDC provider for the new cluster and update IAM role trust policies to trust both providers during migration.
- **Pod Identity**: If using EKS Pod Identity instead of IRSA, create new pod identity associations for the new cluster.
- **Secrets**: Migrate Kubernetes secrets or (better) ensure workloads pull from external stores (Secrets Manager, Parameter Store, HashiCorp Vault).
- **Network policies**: Calico/Cilium policies need to be reapplied. Validate they work with the new cluster's CNI configuration.
- **KMS encryption**: If the new cluster uses a different KMS key for envelope encryption, secrets encrypted at rest in etcd won't be portable via raw etcd backup.

### Workload Compatibility

- **API deprecations**: If jumping multiple versions, audit manifests for removed APIs. Use `kubectl convert` or `pluto` to detect deprecated resources.
- **Admission webhooks**: Ensure webhook endpoints are reachable from the new cluster's control plane.
- **CRDs and operators**: Operators must be installed on the new cluster before deploying workloads that depend on their CRDs.
- **Helm releases**: Helm state lives in-cluster (Secrets or ConfigMaps). Re-install charts on the new cluster rather than migrating Helm state.
- **Service mesh**: Istio/Linkerd control planes need fresh installation. Sidecar injection will happen naturally on new deployments.

### Observability

- **Logging**: Ensure FluentBit/Fluentd DaemonSets are deployed on the new cluster and shipping to the same log destination.
- **Metrics**: Prometheus/Grafana stacks need to be deployed. Historical metrics stay with the old cluster's storage.
- **Tracing**: Verify trace collector endpoints are reachable from the new cluster.
- **Alerts**: Duplicate alerting rules or use infrastructure-as-code to deploy them to both clusters.

### DNS & Traffic Management

- **External DNS**: If using ExternalDNS, both clusters will try to manage the same DNS records. Use ownership TXT records or disable ExternalDNS on the old cluster during migration.
- **Weighted routing**: Route 53 weighted records or ALB weighted target groups allow gradual traffic shifting (canary migration).
- **Service discovery**: Internal services using CoreDNS resolve within the cluster. Cross-cluster calls need explicit endpoints or a service mesh with multi-cluster support.

---

## Migration Workflow

```
┌─────────────────────────────────────────────────────────┐
│              Phase 1: Provision New Cluster              │
│  Create EKS cluster, node groups, configure networking  │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│            Phase 2: Deploy Platform Layer               │
│  Install CNI, CSI drivers, ingress, cert-manager,       │
│  monitoring, operators, CRDs, policy engines            │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│            Phase 3: Deploy Workloads                    │
│  Apply manifests / Helm charts / ArgoCD sync            │
│  Validate pods are healthy (no traffic yet)             │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│            Phase 4: Smoke Test & Validation             │
│  Run integration tests against new cluster              │
│  Verify connectivity to external dependencies           │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│            Phase 5: Traffic Shifting                    │
│  Gradually shift traffic: 10% → 25% → 50% → 100%      │
│  Monitor error rates, latency, pod health               │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│            Phase 6: Decommission Old Cluster            │
│  Drain remaining traffic, scale down nodes,             │
│  delete old cluster after bake period                   │
└─────────────────────────────────────────────────────────┘
```

---

## Phase Details

### Phase 1: Provision New Cluster

- Use IaC (Terraform) to create the new cluster with the desired Kubernetes version, configuration, and node groups.
- Ensure the new cluster's VPC/subnets allow connectivity to shared resources.
- Create the OIDC provider for IRSA.
- Configure cluster logging (audit, API server, authenticator).

### Phase 2: Deploy Platform Layer

Install in this order (dependencies flow downward):

1. **Storage**: EBS CSI driver, EFS CSI driver
2. **Networking**: AWS Load Balancer Controller, ExternalDNS (disabled or pointed at staging records)
3. **Security**: cert-manager, Sealed Secrets or External Secrets Operator, OPA/Kyverno
4. **Observability**: Prometheus stack, FluentBit, OTEL collector
5. **Service mesh** (if applicable): Istio/Linkerd control plane
6. **Operators & CRDs**: Any custom operators your workloads depend on

### Phase 3: Deploy Workloads

- Apply workload manifests via your GitOps tool (ArgoCD, Flux) pointed at the new cluster, or run Helm installs.
- For stateful workloads:
  - Snapshot EBS volumes from old cluster, create new volumes from snapshots in the correct AZs.
  - Mount EFS access points (no migration needed).
- Verify all pods reach `Running` state and readiness probes pass.
- At this point, no external traffic is hitting the new cluster.

### Phase 4: Smoke Test & Validation

- Run integration/E2E test suites against the new cluster's internal endpoints.
- Verify:
  - Database connectivity (RDS, DynamoDB, ElastiCache)
  - External API calls (third-party services, SaaS)
  - Inter-service communication
  - Secret retrieval (Secrets Manager, Vault)
  - Persistent storage read/write
- Check that monitoring dashboards show healthy metrics.

### Phase 5: Traffic Shifting

#### Option A: DNS-Based (Route 53 Weighted Records)

```
Old cluster ALB: weight 90  →  weight 75  →  weight 50  →  weight 0
New cluster ALB: weight 10  →  weight 25  →  weight 50  →  weight 100
```

- Set TTL to 30–60 seconds before starting.
- Monitor error rates at each step. Roll back by flipping weights if issues arise.

#### Option B: ALB Weighted Target Groups

- Register new cluster's target group with the existing ALB.
- Shift weight gradually using `modify-rule` with forward action weights.
- Advantage: no DNS propagation delay.

#### Option C: Service Mesh Multi-Cluster

- If running Istio with multi-cluster, use traffic policies to shift at the mesh level.
- Most granular control (per-service shifting).

#### Rollback

At any point during traffic shifting:
- Shift all traffic back to the old cluster (weight 100 / 0).
- The old cluster remains fully operational until Phase 6.

### Phase 6: Decommission Old Cluster

- Wait for a bake period (24–72 hours at 100% on new cluster) to confirm stability.
- Drain any remaining connections.
- Remove old cluster's DNS records and target groups.
- Delete the old EKS cluster, node groups, and associated resources.
- Clean up old OIDC provider and IAM role trust policies.
- Remove old cluster from monitoring/alerting.

---

## Automation Approach

A migration script would orchestrate phases 3–5. Phases 1–2 are best handled by IaC (Terraform/CDK) since they involve infrastructure provisioning.

The script would:

1. **Export workload manifests** from the old cluster (or reference them from Git — preferred).
2. **Apply manifests** to the new cluster.
3. **Wait for readiness** across all deployments.
4. **Run smoke tests** (configurable test command).
5. **Shift traffic** incrementally with health checks between steps.
6. **Report status** and provide rollback instructions.

```bash
python migrate.py \
  --source-cluster old-cluster \
  --target-cluster new-cluster \
  --region eu-west-2 \
  --traffic-strategy weighted-dns \
  --hosted-zone-id Z1234567890 \
  --record-name app.example.com \
  --steps 10,25,50,100 \
  --health-check-interval 300
```

---

## Checklist

```
[ ] New cluster provisioned with correct version and config
[ ] VPC connectivity verified (new cluster → shared resources)
[ ] OIDC provider created, IAM roles trust both clusters
[ ] Platform layer deployed and healthy
[ ] Workloads deployed, all pods Running/Ready
[ ] Smoke tests passing
[ ] Monitoring and alerting active on new cluster
[ ] DNS TTLs lowered
[ ] Traffic shifted incrementally with monitoring at each step
[ ] Bake period completed (24–72 hours)
[ ] Old cluster decommissioned
[ ] Old IAM/OIDC/DNS resources cleaned up
```

---

## Key Differences from In-Place Upgrade

| Aspect | In-Place Upgrade | Cluster Migration |
|--------|-----------------|-------------------|
| Downtime risk | Low (rolling) | Near-zero (blue/green) |
| Rollback speed | Slow (downgrade not supported) | Instant (shift traffic back) |
| Complexity | Low | High |
| Infrastructure cost | Same | 2x during migration window |
| Config changes | Limited to mutable settings | Full flexibility |
| Version skipping | Not supported | Supported (fresh cluster) |
