# Step 4.3 — Kubernetes Disaster Recovery on AWS

## RTO / RPO Targets

| Tier | RTO (Recovery Time) | RPO (Data Loss) |
|------|--------------------|-----------------| 
| Critical services | < 1 hour | < 15 minutes |
| Non-critical | < 4 hours | < 1 hour |

## Architecture

```
Primary Region (eu-west-1)          DR Region (eu-central-1)
EKS Cluster (active)                EKS Cluster (warm standby)
    │                                    │
    ├── RDS Multi-AZ                ├── RDS Read Replica → promoted on failover
    ├── S3 (CRR to DR region)       ├── S3 (replicated)
    ├── Velero → S3 backups         └── Route53 health check switches DNS
    └── GitOps (ArgoCD)                 (ArgoCD syncs same Git repo)
```

## a) Steps to Recover from Failure

### 1. Cluster Configuration — GitOps (ArgoCD)

All K8s manifests are in Git. On failover:
```bash
# Install ArgoCD on DR cluster
kubectl apply -k gitops/argocd/install/
# Bootstrap app-of-apps
kubectl apply -f gitops/argocd/applications/app-of-apps.yaml
# ArgoCD syncs all applications from Git → cluster rebuilt in minutes
```

### 2. Persistent Data — Velero Backups

```bash
# Install Velero with S3 backend (replication to DR region via S3 CRR)
velero install \
  --provider aws \
  --bucket dreamgames-velero-backups \
  --backup-location-config region=eu-west-1 \
  --use-volume-snapshots=true

# Scheduled backup: every 15 minutes
velero schedule create prod-backup \
  --schedule "*/15 * * * *" \
  --ttl 720h \
  --include-namespaces app,monitoring
```

On DR cluster:
```bash
velero restore create --from-backup prod-backup-TIMESTAMP
```

### 3. Database Recovery

```
Primary RDS fails
    → Route53 health check detects failure
    → DNS failover to RDS read replica in DR region
    → Promote read replica: aws rds promote-read-replica
    → Read replica becomes new primary (< 5 min promotion time)
    → Application connection string uses Route53 CNAME (no code change)
```

### 4. DNS Failover

```yaml
# Route53 health check on primary ALB
# If health check fails for 3 consecutive checks (30s), failover to DR
Type: A
RoutingPolicy: Failover
Primary: eu-west-1 ALB
Secondary: eu-central-1 ALB (warm standby)
TTL: 60s    # low TTL for fast failover
```

## b) Data Persistence, Backup & Configuration Management

| Concern | Solution |
|---------|---------|
| Kubernetes state | Velero snapshots every 15 min → S3 (cross-region replicated) |
| Database | RDS Multi-AZ (same region) + cross-region read replica |
| Container images | ECR replication rules → DR region |
| Secrets | AWS Secrets Manager (replication policy across regions) |
| Configuration | GitOps (ArgoCD) — Git is the DR config store |
| Certificates | cert-manager → Let's Encrypt (re-issues on DR cluster) |

## Disaster Recovery Runbook

```bash
# Step 1: Confirm primary failure
aws eks describe-cluster --name prod-cluster --region eu-west-1

# Step 2: Switch Route53 to DR
aws route53 change-resource-record-sets --hosted-zone-id Z... \
  --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{...DR ALB...}}]}'

# Step 3: Restore latest Velero backup on DR cluster
velero restore create dr-restore --from-schedule prod-backup --wait

# Step 4: Promote RDS read replica
aws rds promote-read-replica --db-instance-identifier prod-replica-dr --region eu-central-1

# Step 5: Verify application health
curl https://app.example.com/actuator/health
```

## Reviewer Defense

> "The core principle is 'GitOps as DR config store': because all K8s manifests are in
> Git and ArgoCD can bootstrap a cluster from scratch, cluster configuration recovery
> is just installing ArgoCD and pointing it at the same repo. Velero handles the stateful
> parts — PVCs and namespace snapshots — stored in S3 with cross-region replication so
> backups survive a region failure. RDS cross-region read replica with Route53 failover
> achieves RPO < 15 minutes with no application changes."
