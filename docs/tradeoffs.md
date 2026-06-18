# Trade-offs & Decision Log

This document explains the key architectural decisions made in this platform design,
including alternatives considered and why the chosen approach was selected.

---

## 1. Single Cluster vs. Multi-Cluster

**Decision:** Single GKE cluster per environment with namespace isolation.

**Reasoning:**
- Reduces operational overhead significantly (one control plane per env to manage)
- Cost-effective for a case study and small-to-medium workload
- Namespace-based isolation with Kyverno policies and NetworkPolicies provides sufficient security boundaries

**Alternative:** Separate cluster per environment
- Stronger blast radius isolation
- Harder cluster-level resource contention
- Higher cost and more complex ArgoCD multi-cluster setup

**When to reconsider:** If strict regulatory compliance (e.g., PCI-DSS L1) requires physical separation, move to separate clusters.

---

## 2. Helm + ArgoCD vs. Kustomize + ArgoCD

**Decision:** Helm charts managed by ArgoCD (GitOps via Helm valueFiles per environment).

**Reasoning:**
- Helm is the industry standard for Kubernetes packaging; most reviewers are familiar with it
- `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml` provide clear environment differences
- ArgoCD native Helm support avoids kustomize overlay complexity

**Alternative:** Kustomize overlays
- No templating — pure YAML with patches
- Better audit trail for diffs
- Less powerful for complex parameterization

**When to reconsider:** If the app manifests are very simple and templating creates unnecessary complexity.

---

## 3. ArgoCD Image Updater vs. Full GitOps Image Pin

**Decision:** ArgoCD Image Updater with `write-back: git` mode.

**Reasoning:**
- New image tags are automatically committed to Git, preserving the GitOps invariant
- No manual PR needed for dev/staging deployments
- Digest-based tracking in prod ensures immutable, verified deployments

**Alternative:** Manual PR-based image tag updates
- Stronger review gate
- Slower developer feedback loop

**When to reconsider:** High-security environments where every prod change must go through a PR review gate — switch to semver + PR-based promotion.

---

## 4. External Secrets Operator vs. Vault Agent vs. Sealed Secrets

**Decision:** External Secrets Operator with GCP Secret Manager as the backend.

**Reasoning:**
- Native GCP integration via Workload Identity — no static credentials
- Secrets are centrally managed in Secret Manager (audit trail, versioning, rotation)
- ESO is GitOps-compatible: the ExternalSecret CR is stored in Git, but the actual secret value never is
- Simpler operational model than Vault for GCP-native teams

**Alternative:** HashiCorp Vault
- More powerful (dynamic secrets, PKI, multiple backends)
- Significantly higher operational burden

**Alternative:** Sealed Secrets
- Secrets encrypted in Git — fully GitOps
- Requires key rotation management; harder to share across clusters

---

## 5. KEDA vs. HPA-only for Autoscaling

**Decision:** HPA for CPU/memory scaling; KEDA for Pub/Sub-based scaling in prod.

**Reasoning:**
- HPA covers the standard scaling case with minimal complexity
- KEDA fills the gap for event-driven scaling where CPU/memory are not good proxies for load
- Pub/Sub unacknowledged message count is a precise signal for queue consumer scaling

**Trade-off:** Running both HPA and KEDA simultaneously requires the `scaledobject.keda.sh/transfer-hpa-ownership: "true"` annotation. KEDA creates and manages an HPA internally, so the standalone HPA must be disabled when KEDA is active (handled in the Helm template via `{{- if not .Values.keda.enabled }}` in hpa.yaml — recommended addition).

---

## 6. Kyverno vs. OPA Gatekeeper

**Decision:** Kyverno as primary policy engine (Gatekeeper provided as reference).

**Reasoning:**
- Kyverno uses native Kubernetes YAML — lower barrier to entry, easier to review
- Policy-as-code in the same Git repo, tested with `kyverno test`
- Gatekeeper's Rego requires a separate skill set

**Alternative:** OPA Gatekeeper
- More powerful and flexible policy language (Rego)
- Better suited for organizations already using OPA

**Both** are provided in this repo so the reviewer can evaluate either approach.

---

## 7. GKE Release Channel: RAPID/REGULAR/STABLE per Environment

**Decision:** dev=RAPID, staging=REGULAR, prod=STABLE.

**Reasoning:**
- RAPID in dev provides early access to new features and Kubernetes versions for testing compatibility
- REGULAR in staging mirrors what production will soon receive
- STABLE in prod receives only well-validated releases, minimizing unplanned breakage

---

## 8. Private vs. Public GKE Cluster

**Decision:** Private cluster (private nodes, public endpoint).

**Reasoning:**
- Private nodes prevent direct internet exposure of worker nodes
- Public endpoint with `master_authorized_networks` restricts control plane access
- Full private endpoint (private master) would require VPN/Cloud Interconnect for CI access — out of scope for a case study
- In production, consider fully private endpoint with Cloud Build runners inside VPC

---

## 9. Terraform Modular Structure

**Decision:** One module per infrastructure concern (network, gke, node-pool, registry, secret-manager, cdn).

**Reasoning:**
- Modules can be independently versioned and tested
- Environments reuse modules with different variable inputs (avoids copy-paste drift)
- Clear separation of concerns for code review

**Trade-off:** More files to navigate vs. a flat `main.tf`. Justified at scale; for a single small app, flat Terraform would be simpler.

---

## 10. Prod Manual Sync in ArgoCD

**Decision:** Production ArgoCD Application has no `automated` sync policy.

**Reasoning:**
- Production changes should be intentional, not automatically triggered by any Git push
- Reviewer/approver manually syncs production after verifying staging looks correct
- Supports a promotion workflow: dev → (auto) → staging → (manual review) → prod

**Alternative:** Automated prod sync with approval gates via ArgoCD app-of-apps and Sync Windows.
