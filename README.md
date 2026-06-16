# Dream Games — DevOps Engineering Case Study

## Overview

Production-grade Kubernetes platform implementing all requirements of the Dream Games DevOps Case Study.
Local cluster on Vagrant/VirtualBox, Java Spring Boot application, Jenkins CI/CD, full observability stack, and custom admission webhook.

## Architecture

```
Developer
    │ git push
    ▼
GitHub → Jenkins (Node 3, worker2)
    ├── Jenkinsfile.build   → mvn test → docker build → Trivy scan → DockerHub
    └── Jenkinsfile.deploy  → Ansible → kubectl apply → rollout verify → smoke test
                                    │
                    ┌───────────────▼──────────────────┐
                    │         Kubernetes Cluster        │
                    │  (kubeadm 1.32, Calico, MetalLB)  │
                    │                                   │
                    │  ┌──────────────────────────┐     │
                    │  │  app namespace            │     │
                    │  │  query-param-app (4 pods) │     │
                    │  │  → worker1 + worker2      │     │
                    │  │  → Nginx Ingress          │     │
                    │  │  → NetworkPolicy (default │     │
                    │  │    deny, allow ingress-   │     │
                    │  │    nginx + monitoring)    │     │
                    │  └──────────────────────────┘     │
                    │                                   │
                    │  monitoring: Prometheus, Grafana  │
                    │             ES, fluent-bit        │
                    │  jenkins:   Node 3 only, PVC      │
                    │  webhook-system: admission webhook│
                    │  PSA: restricted/baseline on all  │
                    └───────────────────────────────────┘
```

## Repository Structure

```
.
├── Vagrantfile                        # 1 master + 2 workers (Ubuntu 22.04)
├── ansible/
│   ├── inventory/hosts.ini            # Vagrant IPs
│   ├── group_vars/all.yml             # K8s version, CIDRs, versions
│   ├── roles/                         # common, containerd, kubeadm, master, worker
│   ├── site.yml                       # Full cluster bootstrap
│   └── deploy-app.yml                 # App deployment (called by Jenkins)
├── app/                               # Java Spring Boot application
│   ├── src/main/java/com/dreamgames/controller/QueryParamController.java
│   ├── src/main/resources/logback-spring.xml   # Async file logging
│   ├── src/test/                      # Unit tests (WebMvcTest)
│   ├── pom.xml
│   └── Dockerfile                     # Multi-stage Maven → JRE Alpine
├── kubernetes/
│   ├── namespaces/                    # All namespace definitions
│   ├── metallb/                       # LoadBalancer IP pool (192.168.56.200-220)
│   ├── ingress-nginx/values.yaml      # Helm values
│   ├── externaldns/                   # etcd + ExternalDNS (coredns provider)
│   ├── jenkins/                       # Helm values (JCasC, Node 3, PV, LoadBalancer)
│   ├── monitoring/                    # kube-prometheus-stack, ECK, fluent-bit
│   │   ├── alertmanager-rules.yaml    # PodCrashLooping + app alerts
│   │   └── ingress-monitoring.yaml    # /grafana /prometheus /elasticsearch
│   ├── app/                           # Deployment, ServiceAccount, Service, Ingress, HPA, PDB
│   └── webhook/                       # Admission webhook manifests + TLS setup
├── webhook/                           # Go source: /validate (TLS:8443) /metrics (HTTP:8080)
├── jenkins/
│   ├── Jenkinsfile.build              # Build + DockerHub push
│   └── Jenkinsfile.deploy             # Ansible deploy + rollout verify
├── step3-manifests/                   # Step 3: PriorityClass, canary, KEDA cron
└── docs/design-answers/               # Step 3 & 4 written design documents
```

## Prerequisites

- Vagrant + VirtualBox
- Ansible 2.15+ (`pip install ansible`)
- kubectl, Helm 3

## Quick Start

### 1. Spin up the cluster

```bash
vagrant up
# Creates 3 VMs and runs ansible/site.yml automatically

# If running Ansible manually:
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml
```

### 2. Get kubeconfig

```bash
vagrant ssh master -c "cat ~/.kube/config" > ~/.kube/config-dreamgames
export KUBECONFIG=~/.kube/config-dreamgames
kubectl get nodes   # master, worker1, worker2 all Ready
```

### 3. Install platform components (in order)

```bash
# MetalLB (LoadBalancer support for bare-metal)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml
kubectl wait --for=condition=available deployment -n metallb-system controller --timeout=90s
kubectl apply -f kubernetes/metallb/ipaddresspool.yaml

# Ingress-NGINX
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f kubernetes/ingress-nginx/values.yaml

# ExternalDNS (deploys lightweight etcd + ExternalDNS with coredns provider)
kubectl apply -f kubernetes/externaldns/rbac.yaml
kubectl apply -f kubernetes/externaldns/deployment.yaml

# Jenkins (Node 3 / worker2)
kubectl apply -f kubernetes/jenkins/storageclass.yaml
kubectl apply -f kubernetes/jenkins/pv.yaml
# Create secrets (never hardcoded — use your actual values)
kubectl create secret generic jenkins-credentials \
  --from-literal=admin-password=<STRONG_PASSWORD> \
  --from-literal=dockerhub-user=<YOUR_DOCKERHUB_USER> \
  --from-literal=dockerhub-token=<YOUR_DOCKERHUB_TOKEN> \
  --from-literal=github-user=<YOUR_GITHUB_USER> \
  --from-literal=github-token=<YOUR_GITHUB_TOKEN> \
  -n jenkins
helm repo add jenkins https://charts.jenkins.io
helm install jenkins jenkins/jenkins -n jenkins --create-namespace \
  -f kubernetes/jenkins/values.yaml

# Add kubeconfig for Jenkins deploy pipeline
kubectl create secret generic kubeconfig \
  --from-file=config=${KUBECONFIG} -n jenkins

# Monitoring stack
kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=<STRONG_PASSWORD>
kubectl create secret generic alertmanager-slack-secret -n monitoring \
  --from-literal=webhookUrl=<YOUR_SLACK_WEBHOOK_URL>
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f kubernetes/monitoring/kube-prometheus-stack-values.yaml
kubectl apply -f kubernetes/monitoring/alertmanager-rules.yaml
kubectl apply -f kubernetes/monitoring/grafana-dashboards/

# Elasticsearch (ECK)
kubectl create -f https://download.elastic.co/downloads/eck/2.11.1/crds.yaml
kubectl apply  -f https://download.elastic.co/downloads/eck/2.11.1/operator.yaml
kubectl apply  -f kubernetes/monitoring/elasticsearch/eck-operator.yaml

# Fluent-bit
helm repo add fluent https://fluent.github.io/helm-charts
helm install fluent-bit fluent/fluent-bit \
  -n monitoring \
  -f kubernetes/monitoring/fluent-bit/values.yaml

# Monitoring ingress
kubectl apply -f kubernetes/monitoring/ingress-monitoring.yaml
```

### 4. Deploy application

```bash
# Namespaces
kubectl apply -f kubernetes/namespaces/namespaces.yaml

# Application manifests (ServiceAccount + Deployment + Service + Ingress + HPA + PDB)
kubectl apply -f kubernetes/app/

# Test
curl 'http://app.example.com/api/echo?hello=world&foo=bar'
# Response: {"hello":"world","foo":"bar"}
```

### 5. Deploy webhook

```bash
kubectl apply -f kubernetes/webhook/namespace.yaml
kubectl apply -f kubernetes/webhook/rbac.yaml
kubectl apply -f kubernetes/webhook/configmap.yaml

# Generate TLS certs and create the secret
bash kubernetes/webhook/tls/generate-certs.sh

kubectl apply -f kubernetes/webhook/deployment.yaml
kubectl apply -f kubernetes/webhook/service.yaml
kubectl apply -f kubernetes/webhook/validatingwebhookconfiguration.yaml

# Patch caBundle (required — webhook won't work without this)
CA_BUNDLE=$(kubectl get secret resource-webhook-tls -n webhook-system \
  -o jsonpath='{.data.ca\.crt}')
kubectl patch validatingwebhookconfiguration resource-requests-webhook \
  --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${CA_BUNDLE}\"}]"

# Test: deploy without resource requests → should be rejected
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bad-deploy
  namespace: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bad
  template:
    metadata:
      labels:
        app: bad
    spec:
      containers:
        - name: bad
          image: nginx
          # No resources → webhook rejects this
EOF
```

### Local DNS setup

Add to `/etc/hosts` on your local machine:

```
192.168.56.200  app.example.com monitoring.example.com
192.168.56.201  jenkins.example.com
```

## Access URLs

| Service | URL |
|---------|-----|
| Application | http://app.example.com/api/echo?param=value |
| Jenkins | http://jenkins.example.com:8080 |
| Grafana | http://monitoring.example.com/grafana |
| Prometheus | http://monitoring.example.com/prometheus |
| Elasticsearch | http://monitoring.example.com/elasticsearch |

## CI/CD Flow

```
Developer pushes to GitHub
    │
    ▼
Jenkins Build Pipeline (Jenkinsfile.build)
  ① checkout → ② mvn test → ③ mvn package
  ④ docker build → ⑤ docker push (DockerHub, tag: BUILD_NUM-GIT_SHA)
    │
    ▼
Jenkins Deploy Pipeline (Jenkinsfile.deploy)
  ① ansible-playbook deploy-app.yml -e image_tag=<tag>
  ② kubectl rollout status (waits for zero-downtime rollout)
  ③ smoke test: GET /api/echo → 200 OK
  ④ auto-rollback on failure: kubectl rollout undo
```

### Zero-Downtime Deployment

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1          # 1 extra pod spins up first
    maxUnavailable: 0    # no pod removed until new one is Ready
+ readinessProbe: waits for Spring Boot readiness endpoint
+ lifecycle.preStop: sleep 5 (drains in-flight requests)
+ terminationGracePeriodSeconds: 30
```

## Application — Log Design (Step 1.7)

**Problem:** stdout logging blocks main thread under high request load.

**Solution:** Logback `AsyncAppender` wrapping `SizeAndTimeBasedRollingPolicy`.

```
Main thread → AsyncAppender (queue: 256, non-blocking, discardingThreshold: 0)
                   │ async, separate thread
                   ▼
           RollingFileAppender
           /app/logs/app.YYYY-MM-DD.log
           maxFileSize: 1GB
           rotation: daily
           totalSizeCap: 10GB
```

Config: `app/src/main/resources/logback-spring.xml`

Fluent-bit reads from `/app/logs/*.log` (file tail input) and forwards to Elasticsearch.

## HPA vs KEDA (Step 3.2)

`kubernetes/app/hpa.yaml` is the default autoscaler (CPU 70% + memory 80%).

`step3-manifests/hpa-scheduled.yaml` replaces it with KEDA CronTrigger for pre-emptive scaling before peak hours. **Do not apply both simultaneously** — delete the standalone HPA before applying KEDA:

```bash
kubectl delete hpa query-param-app -n app
kubectl apply -f step3-manifests/hpa-scheduled.yaml
```

## Step 3 — Design Decisions

See `docs/design-answers/` for full writeups with manifests and reviewer defenses:

| Step | Topic | Doc |
|------|-------|-----|
| 3.1 | App X (HA) vs App Y (batch) on limited nodes | [step3-resource-management.md](docs/design-answers/step3-resource-management.md) |
| 3.2 | Scheduled autoscaling before peak | [step3-autoscaling.md](docs/design-answers/step3-autoscaling.md) |
| 3.3 | Canary deployment for critical apps | [step3-deployment-strategy.md](docs/design-answers/step3-deployment-strategy.md) |
| 3.4 | DB replica scaling + cache pre-warm | [step3-database-scaling.md](docs/design-answers/step3-database-scaling.md) |

## Step 4 — Design Decisions

| Step | Topic | Doc |
|------|-------|-----|
| 4.1 | Move macOS CI/CD to cloud (AWS EC2 Mac) | [step4-cloud-cicd.md](docs/design-answers/step4-cloud-cicd.md) |
| 4.2 | iOS build automation with fastlane | [step4-ios-automation.md](docs/design-answers/step4-ios-automation.md) |
| 4.3 | AWS Kubernetes disaster recovery | [step4-aws-dr.md](docs/design-answers/step4-aws-dr.md) |

## Kubernetes Cluster Spec

| Parameter | Value |
|-----------|-------|
| Kubernetes version | 1.32.x |
| Container runtime | containerd 1.7.23 |
| CNI | Calico v3.29.1 |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |
| LoadBalancer | MetalLB v0.14 (192.168.56.200-220) |
| Node OS | Ubuntu 22.04 |
| Jenkins node | worker2 (Node 3), hostPath PV, 20Gi |
| Pod Security Admission | app/webhook-system: restricted; monitoring/jenkins: baseline |

## Requirements Coverage

| Requirement | Coverage |
|-------------|---------|
| Production-ready K8s cluster | kubeadm 1.32, Calico, private network, MetalLB |
| Jenkins deployment | Helm, JCasC, Node 3 nodeSelector, PVC, LoadBalancer |
| Prometheus, Grafana, ES, fluent-bit, AlertManager | kube-prometheus-stack + ECK + fluent-bit Helm |
| Application build stages | Jenkinsfile.build (test → Trivy scan → docker → push) |
| Application deployment with Ansible | Jenkinsfile.deploy → ansible/deploy-app.yml |
| Async log design | Logback AsyncAppender + SizeAndTimeBasedRollingPolicy + MDC requestId |
| Custom admission webhook | Go, /validate (TLS), /metrics (HTTP), ConfigMap allow-list, initContainers check |
| ExternalDNS | coredns provider with embedded etcd pod |
| NetworkPolicy | Default-deny ingress+egress; app, webhook-system namespaces isolated |
| Image security | No mutable :latest tag; Trivy HIGH/CRITICAL scan before push |

## How to Verify

Run `make verify` after the cluster is up. It checks nodes, pod health, app smoke test, webhook rejection, HPA, and PDB in one command.

Manual acceptance tests per step:

**Step 1 — Cluster:**
```bash
kubectl get nodes                        # master, worker1, worker2 — all Ready
curl 'http://app.example.com/api/echo?hello=world'  # → {"hello":"world"}
cd app && mvn clean test                 # unit tests pass
```

**Step 2 — Rolling update (zero downtime):**
```bash
# Update image tag in deployment.yaml, then:
kubectl apply -f kubernetes/app/deployment.yaml
kubectl rollout status deployment/query-param-app -n app
# While rolling: curl loop should see no connection errors
```

**Webhook:**
```bash
kubectl apply -f test/bad-deploy.yaml 2>&1 | grep -i "rejected\|denied"
# Must print: admission webhook rejected — missing resource requests
```

**Monitoring:**
```bash
curl http://monitoring.example.com/prometheus/-/healthy   # 200 OK
curl http://monitoring.example.com/grafana/api/health     # {"database":"ok"}
kubectl get prometheusrule -n monitoring                  # dreamgames-app-alerts
```

**Request correlation:**
```bash
curl -v http://app.example.com/api/echo?x=1 2>&1 | grep X-Request-Id
# Response header: X-Request-Id: <12-char hex>
```

## How to Destroy

```bash
vagrant destroy -f

# Remove kubeconfig
rm ~/.kube/config-dreamgames
unset KUBECONFIG

# Remove /etc/hosts entries added in setup
sudo sed -i '/app.example.com\|monitoring.example.com\|jenkins.example.com/d' /etc/hosts
```

## Known Limitations

| Limitation | Impact | Mitigation in real prod |
|-----------|--------|------------------------|
| Single control plane (no HA) | Master failure = cluster down | 3 control plane nodes + stacked/external etcd |
| Vagrant/VirtualBox only | MetalLB IP pool 192.168.56.x only reachable from host | Cloud LB (AWS ELB, GCP GLBC) in real infra |
| Self-signed TLS certs | Browser warnings; curl needs `-k` | cert-manager + Let's Encrypt or corporate CA |
| ExternalDNS uses embedded single-node etcd | etcd pod failure = DNS loss | Managed DNS (Route53, Cloudflare) in prod |
| K8s 1.32 — active support ends ~mid 2026 | Will need upgrade | Upgrade to 1.34/1.35/1.36 per [upgrade strategy](docs/upgrade-strategy.md) |
| Jenkins on single worker2 node | Jenkins failure = no CI | Jenkins HA or cloud CI (GitHub Actions, GitLab CI) |
| No etcd backup configured | Control plane data loss on master failure | Scheduled etcd snapshots to object storage |

## Why This Design

**kubeadm vs kubespray / k3s:**
kubeadm matches what production on-prem/bare-metal teams actually use; it exposes every control plane parameter explicitly (audit logs, OIDC, encryption at rest). kubespray adds abstraction cost; k3s hides too much for a case study that requires demonstrating deep K8s knowledge.

**MetalLB vs NodePort / ExternalIPs:**
MetalLB gives a realistic LoadBalancer IP that mirrors cloud behavior. NodePort requires port management; ExternalIPs are static and not HA. This lets Jenkins deploy via a single stable IP exactly like a cloud LB.

**ECK vs Helm Elasticsearch chart:**
ECK (Elastic Cloud on Kubernetes) handles rolling upgrades, TLS, and keystore management automatically. The community Helm chart requires manual cert rotation and has no operator-level health management.

**Go webhook vs OPA/Kyverno/VAP:**
A hand-written Go webhook demonstrates admission controller internals (TLS, AdmissionReview wire format, caBundle patching). OPA/Kyverno would be the production choice for policy-as-code at scale, but they hide the mechanism the case study is testing.

**KEDA CronTrigger vs CronJob patching:**
KEDA integrates with HPA and Kubernetes autoscaling primitives. CronJob patching (kubectl patch deployment) is fragile and doesn't interact with the existing HPA min/max replicas correctly.

## Upgrade Strategy

See [docs/upgrade-strategy.md](docs/upgrade-strategy.md) for the full one-minor-at-a-time procedure, version skew policy, etcd backup steps, and Calico compatibility matrix.
