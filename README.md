# GCP / GKE / GitOps Platform

A production-grade reference platform demonstrating Kubernetes infrastructure design, GitOps deployment, secret management, autoscaling, and security governance on GCP.

## Overview

This repository implements a complete DevOps platform for a Node.js Express application across `dev`, `staging`, and `prod` environments. It covers every layer of the stack: infrastructure provisioning (Terraform), container packaging (Docker / Artifact Registry), GitOps deployment (ArgoCD + Helm), secret management (GCP Secret Manager + ESO), autoscaling (HPA + KEDA), and policy enforcement (Kyverno).

## Architecture

```
Developer → GitLab CI → Artifact Registry
                    ↓ terraform apply
              GCP (VPC / GKE / Secret Manager / Cloud CDN)
                    ↓ ArgoCD watches Git
              GKE Cluster
              ├── ArgoCD (App of Apps)
              ├── External Secrets Operator
              ├── KEDA
              └── Workloads
                  ├── dev-nodejs-express
                  ├── staging-nodejs-express
                  └── prod-nodejs-express
                         ↑ Slack notifications
```

See [`docs/architecture.md`](docs/architecture.md) for the full Mermaid diagram, component breakdown, secret flow, image update flow, and KEDA scaling diagram.

## Repository Structure

```
.
├── README.md
├── docs/
│   ├── architecture.md          # Mermaid diagrams + component breakdown
│   ├── assumptions.md           # 23 numbered assumptions with impact analysis
│   └── tradeoffs.md             # 10 architectural decision records (ADRs)
├── terraform/
│   ├── versions.tf              # Provider version pins
│   ├── environments/
│   │   ├── dev/                 # Dev tfvars + backend (GCS)
│   │   ├── staging/             # Staging tfvars + backend
│   │   └── prod/                # Prod tfvars + backend (+ CDN)
│   └── modules/
│       ├── network/             # VPC, subnet, NAT, firewall
│       ├── gke/                 # Private GKE cluster, Workload Identity
│       ├── node-pool/           # Autoscaling node pool, shielded nodes
│       ├── registry/            # Artifact Registry + cleanup policies
│       ├── secret-manager/      # Secrets + ESO service account (WI)
│       └── cdn/                 # Cloud CDN + GCS static assets
├── gitops/
│   ├── argocd/
│   │   ├── install/             # Kustomize install (ArgoCD v2.9.3)
│   │   ├── applications/        # App of Apps + per-env Applications
│   │   └── notifications/       # Slack notification config + ESO secret ref
│   ├── environments/            # Namespace manifests with PSA labels
│   └── projects/                # ArgoCD AppProject with RBAC
├── apps/nodejs-express/
│   ├── src/                     # Express app (health, metrics endpoints)
│   ├── Dockerfile               # Multi-stage, non-root, minimal Alpine
│   ├── package.json
│   └── helm/
│       ├── Chart.yaml
│       ├── values.yaml          # Base values (prod defaults)
│       ├── values-dev.yaml      # Dev overrides
│       ├── values-staging.yaml  # Staging overrides
│       ├── values-prod.yaml     # Prod overrides (KEDA enabled)
│       └── templates/           # deployment, service, ingress, hpa, pdb,
│                                #   externalsecret, configmap, networkpolicy,
│                                #   keda-scaledobject, serviceaccount
├── ci/
│   ├── gitlab-ci.yml            # Primary: validate→lint→scan→build→plan→apply
│   └── github-actions.yml       # Alternative: equivalent GH Actions pipeline
├── policies/
│   ├── kyverno/                 # require-resources, disallow-latest, probes, non-root
│   └── gatekeeper/              # OPA alternative: ConstraintTemplate + Constraint
└── scripts/
    ├── validate.sh              # Local validation runner
    └── local-test.sh            # Docker build + endpoint smoke test
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.6 | Infrastructure provisioning |
| Google Cloud SDK | latest | GCP authentication |
| kubectl | >= 1.28 | Kubernetes CLI |
| Helm | >= 3.13 | Chart packaging / templating |
| ArgoCD CLI | >= 2.9 | GitOps management |
| Docker | >= 24 | Container build |

## How to Provision Infrastructure

### 1. Authenticate to GCP

```bash
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Create Terraform State Bucket

```bash
gsutil mb -l europe-west1 gs://YOUR_PROJECT_ID-terraform-state
gsutil versioning set on gs://YOUR_PROJECT_ID-terraform-state
```

### 3. Update tfvars

Edit `terraform/environments/dev/terraform.tfvars` and replace `YOUR_PROJECT_ID`.

### 4. Run Terraform

```bash
cd terraform/environments/dev
terraform init \
  -backend-config="bucket=YOUR_PROJECT_ID-terraform-state" \
  -backend-config="prefix=dev/terraform.tfstate"
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Repeat for `staging` and `prod`.

### 5. Get GKE Credentials

```bash
gcloud container clusters get-credentials dev-gke-cluster \
  --region europe-west1 --project YOUR_PROJECT_ID
```

## How to Deploy Platform Components

### Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -k gitops/argocd/install/
kubectl wait --for=condition=available deployment -n argocd --all --timeout=180s
```

### Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"=\
"dev-eso-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com"
```

### Configure ClusterSecretStore

```bash
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-store
spec:
  provider:
    gcpsm:
      projectID: YOUR_PROJECT_ID
      auth:
        workloadIdentity:
          clusterLocation: europe-west1
          clusterName: dev-gke-cluster
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
EOF
```

### Install KEDA (prod only)

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm upgrade --install keda kedacore/keda -n keda --create-namespace
```

### Bootstrap App of Apps

```bash
kubectl apply -f gitops/argocd/projects/platform-project.yaml
kubectl apply -f gitops/argocd/applications/app-of-apps.yaml
```

## How Application Deployment Works

1. **Developer** pushes code to a feature branch.
2. **GitLab CI** validates, lints, runs security scans, builds the Docker image, and pushes to Artifact Registry with a `git-sha` tag.
3. **ArgoCD Image Updater** polls Artifact Registry (every 2 min), detects the new tag, and commits an updated image tag back to Git.
4. **ArgoCD** detects the Git change and performs a Helm sync (rolling update, zero-downtime).
5. On successful sync, **ArgoCD Notifications** posts a Slack message to `#deployments`.

### Environment Promotion

```
dev (auto-sync, newest-build)
  └──→ [CI passes, image tagged] ──→ staging (auto-sync, semver)
                                         └──→ [manual review] ──→ prod (manual sync, digest)
```

## Image Update Flow

| Environment | Strategy | Trigger |
|-------------|----------|---------|
| dev | `newest-build` | Any new image pushed |
| staging | `semver` | Tagged releases (e.g. `v1.2.3`) |
| prod | `digest` | Immutable SHA digest — verified by reviewer |

ArgoCD Image Updater writes back via a Git commit to `values-*.yaml`, preserving full GitOps auditability.

## Secret Management

Secrets are **never** stored in Git. The flow:

1. Create secret in **GCP Secret Manager**: `gcloud secrets create nodejs-express-prod/database-url --data-file=-`
2. **ExternalSecret CR** (in Git) declares which Secret Manager keys to sync.
3. **External Secrets Operator** authenticates via Workload Identity and materializes a Kubernetes Secret.
4. The Helm `Deployment` mounts the secret via `envFrom.secretRef`.

See `apps/nodejs-express/helm/templates/externalsecret.yaml` and `gitops/argocd/notifications/secret-reference.yaml`.

## Scaling

### HPA (CPU / Memory)

Configured via `values.yaml` `autoscaling` block. Active in staging and prod. Scales between `minReplicas` and `maxReplicas` based on CPU utilization (default: 70%).

### KEDA (Pub/Sub)

Active in prod when `keda.enabled: true` (see `values-prod.yaml`). Scales based on unacknowledged message count in a GCP Pub/Sub subscription.

```yaml
# values-prod.yaml excerpt
keda:
  enabled: true
  pubsub:
    subscriptionName: nodejs-express-prod-sub
    threshold: "50"      # scale up when > 50 unacknowledged msgs
    minReplicas: 3
    maxReplicas: 20
    cooldownPeriod: 60
    pollingInterval: 30
```

**KEDA vs HPA:** KEDA is preferred when the scaling signal is external (queue depth, event count) rather than resource consumption. Both cannot own the same Deployment simultaneously — the KEDA ScaledObject takes ownership of the HPA via the `transfer-hpa-ownership` annotation.

## Security and Governance

| Control | Implementation |
|---------|---------------|
| Non-root containers | `securityContext.runAsNonRoot: true` (Kyverno enforced) |
| No privilege escalation | `allowPrivilegeEscalation: false` (Kyverno enforced) |
| Capability dropping | `capabilities.drop: [ALL]` |
| Read-only root filesystem | `readOnlyRootFilesystem: true` (+ emptyDir /tmp) |
| Image tag policy | `latest` blocked in staging/prod by Kyverno |
| Resource limits | Required by Kyverno ClusterPolicy |
| Network isolation | NetworkPolicy per-namespace (ingress-nginx + monitoring only) |
| Pod Security Admission | Namespace labeled `enforce: restricted` |
| GKE private nodes | No direct internet exposure of worker nodes |
| Workload Identity | No service account key files; all GCP auth via WI |
| Secret management | Zero secrets in Git; all via GCP Secret Manager + ESO |
| Shielded nodes | Secure boot + integrity monitoring enabled |
| Binary Authorization | Enforced in prod (PROJECT_SINGLETON_POLICY_ENFORCE) |

## Assumptions

See [`docs/assumptions.md`](docs/assumptions.md) for the full list of 23 assumptions.

Key assumptions:
- GCP project ID must be set in each `terraform.tfvars` (replace `YOUR_PROJECT_ID`)
- Terraform state bucket must be created before running `terraform init`
- ArgoCD Image Updater needs write access to this repository (deploy key or PAT)

## Trade-offs

See [`docs/tradeoffs.md`](docs/tradeoffs.md) for 10 architectural decision records covering:
single vs. multi-cluster, Helm vs. Kustomize, ESO vs. Vault, KEDA vs. HPA, Kyverno vs. Gatekeeper, and more.

## Future Improvements

- [ ] Multi-cluster ArgoCD setup for stronger environment isolation
- [ ] Terragrunt for DRY environment configuration
- [ ] Crossplane for Kubernetes-native infrastructure provisioning
- [ ] VPN / Cloud Interconnect for fully private GKE endpoint
- [ ] Istio service mesh for mTLS, traffic management, and observability
- [ ] Automated cost reporting via GCP Billing export + BigQuery
- [ ] SLO/SLA dashboard with Google Cloud Monitoring SLOs
- [ ] Chaos engineering with Chaos Mesh or Litmus
- [ ] GitLab environments + deployment tracking integration
- [ ] OCI Helm chart storage in Artifact Registry

## How to Explain in a Review

> "This platform separates concerns across three layers: infrastructure (Terraform modules), platform (ArgoCD + ESO + KEDA), and application (Helm charts). Every environment difference is encoded in `values-<env>.yaml`, never in templates. Secrets never touch Git — they exist in Secret Manager and are bridged to Kubernetes via External Secrets Operator using Workload Identity, no static credentials anywhere. Autoscaling has two layers: HPA for CPU/memory, and KEDA for Pub/Sub event-driven scaling in production. ArgoCD Image Updater closes the GitOps loop by writing image tag changes back to Git, keeping the repository the single source of truth. Kyverno policies enforce security baselines at admission time so they can't be accidentally bypassed."
