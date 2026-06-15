# Assumptions

This document captures assumptions made during the design and implementation of this platform.
These should be reviewed and confirmed before production use.

## Infrastructure Assumptions

| # | Assumption | Impact if Wrong |
|---|------------|----------------|
| A1 | A single GCP project is used per environment (or one shared project with namespace isolation) | IAM design and billing separation may need to change |
| A2 | GCP region is `europe-west1` | Update `region` variables in all tfvars files |
| A3 | Terraform state bucket exists and is named `PROJECT_ID-terraform-state` | Create bucket first or update backend config |
| A4 | A CI service account (`ci-runner@PROJECT_ID.iam.gserviceaccount.com`) exists with Artifact Registry Writer role | Create SA and grant permissions |
| A5 | Private GKE cluster nodes access internet via Cloud NAT | If no NAT required, remove nat module from network |
| A6 | `europe-west1` supports all required machine types (`e2-standard-2/4`) | Check GCP machine type availability in target region |

## Application Assumptions

| # | Assumption | Impact if Wrong |
|---|------------|----------------|
| A7 | Application listens on port 3000 | Update `containerPort`, Service `targetPort`, and health probe paths |
| A8 | Health endpoints exist at `/health/live` and `/health/ready` | Update probe paths in values.yaml |
| A9 | Application can run as UID 1001 non-root | Review security context if app requires root |
| A10 | Application secrets are: `DATABASE_URL`, `API_KEY` | Update ExternalSecret data map in values.yaml |
| A11 | Application is stateless and supports horizontal scaling | Stateful apps need PVC/StatefulSet design |

## GitOps & CI/CD Assumptions

| # | Assumption | Impact if Wrong |
|---|------------|----------------|
| A12 | This repository is the single source of truth for both Terraform and Helm/ArgoCD | Separate IaC repo may require split ArgoCD source configs |
| A13 | ArgoCD is installed in the same cluster it deploys to (in-cluster mode) | Multi-cluster setup needs ArgoCD cluster registration |
| A14 | ArgoCD Image Updater has write access to this Git repository | Add deploy key or OAuth app credential in ArgoCD Image Updater config |
| A15 | GitLab CI runners have Docker-in-Docker capability | Update runner configuration if DinD not available |
| A16 | Workload Identity Federation is configured for GitHub Actions | Configure WIF if using GitHub Actions pipeline |

## Security Assumptions

| # | Assumption | Impact if Wrong |
|---|------------|----------------|
| A17 | Kyverno is installed in the cluster before deploying workloads | Policies won't enforce; install Kyverno first |
| A18 | External Secrets Operator is installed in `external-secrets` namespace | ExternalSecrets won't reconcile |
| A19 | Slack token is stored in Secret Manager as `argocd/slack-token` | ArgoCD Notifications will fail silently |
| A20 | All namespaces labeled with `environment: dev/staging/prod` | Kyverno policies won't match |

## Scaling Assumptions

| # | Assumption | Impact if Wrong |
|---|------------|----------------|
| A21 | KEDA is only enabled in prod (controlled via `keda.enabled` in values-prod.yaml) | Enable in other envs if needed |
| A22 | Pub/Sub subscription name is `nodejs-express-prod-sub` | Update `keda.pubsub.subscriptionName` in values-prod.yaml |
| A23 | GKE Workload Identity is used for KEDA Pub/Sub authentication (no SA key) | If WI not available, configure KEDA TriggerAuthentication with a mounted SA key |
