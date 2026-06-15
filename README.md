# Dream Games — DevOps Engineering Case Study

## Overview

Production-grade Kubernetes platform implementing all requirements of the Dream Games DevOps Case Study.
Local cluster on Vagrant/VirtualBox, Java application, Jenkins CI/CD, full observability stack, and custom admission webhook.

## Architecture

```
Developer
    │ git push
    ▼
GitHub → Jenkins (Node 3, worker2)
    ├── Jenkinsfile.build   → Docker build → DockerHub
    └── Jenkinsfile.deploy  → Ansible → kubectl apply
                                    │
                    ┌───────────────▼──────────────────┐
                    │         Kubernetes Cluster        │
                    │  (kubeadm 1.28, Calico, MetalLB)  │
                    │                                   │
                    │  ┌──────────────────────────┐     │
                    │  │  app namespace            │     │
                    │  │  query-param-app (4 pods) │     │
                    │  │  → worker1 + worker2      │     │
                    │  │  → Nginx Ingress          │     │
                    │  └──────────────────────────┘     │
                    │                                   │
                    │  monitoring: Prometheus, Grafana  │
                    │             ES, fluent-bit        │
                    │  jenkins:   Node 3 only, PVC      │
                    │  webhook-system: admission webhook│
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
│   ├── pom.xml
│   └── Dockerfile                     # Multi-stage Maven → JRE Alpine
├── kubernetes/
│   ├── namespaces/                    # All namespace definitions
│   ├── metallb/                       # LoadBalancer IP pool (192.168.56.200-220)
│   ├── ingress-nginx/values.yaml      # Helm values
│   ├── externaldns/                   # CoreDNS provider, RBAC, deployment
│   ├── jenkins/                       # Helm values (JCasC, Node 3, PV, LoadBalancer)
│   ├── monitoring/                    # kube-prometheus-stack, ECK, fluent-bit
│   │   ├── alertmanager-rules.yaml    # PodCrashLooping + app alerts
│   │   └── ingress-monitoring.yaml    # /grafana /prometheus /elasticsearch
│   ├── app/                           # Deployment, Service, Ingress, HPA, PDB
│   └── webhook/                       # Admission webhook manifests + TLS setup
├── webhook/                           # Go source: /validate /metrics, TLS
├── jenkins/
│   ├── Jenkinsfile.build              # Build + DockerHub push
│   └── Jenkinsfile.deploy             # Ansible deploy + rollout verify
├── step3-manifests/                   # Step 3: PriorityClass, canary, KEDA cron
├── docs/design-answers/               # Step 3 & 4 written design documents
└── [terraform/ gitops/ apps/]         # Bonus: GCP/GKE reference implementation
```

## Prerequisites

- Vagrant + VirtualBox
- Ansible (`pip install ansible`)
- kubectl, Helm 3

## Quick Start

### 1. Spin up the cluster

```bash
vagrant up
# This creates 3 VMs and runs ansible/site.yml automatically

# If running Ansible separately:
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
# MetalLB (LoadBalancer support)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml
kubectl wait --for=condition=available deployment -n metallb-system controller --timeout=90s
kubectl apply -f kubernetes/metallb/ipaddresspool.yaml

# Ingress-NGINX
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f kubernetes/ingress-nginx/values.yaml

# ExternalDNS
kubectl apply -f kubernetes/externaldns/rbac.yaml
kubectl apply -f kubernetes/externaldns/deployment.yaml

# Jenkins (Node 3 / worker2)
kubectl apply -f kubernetes/jenkins/pv.yaml
kubectl create secret generic jenkins-credentials \
  --from-literal=admin-password=YOUR_PASS \
  --from-literal=dockerhub-user=YOUR_USER \
  --from-literal=dockerhub-token=YOUR_TOKEN \
  --from-literal=github-user=YOUR_USER \
  --from-literal=github-token=YOUR_TOKEN \
  -n jenkins
helm repo add jenkins https://charts.jenkins.io
helm install jenkins jenkins/jenkins -n jenkins --create-namespace \
  -f kubernetes/jenkins/values.yaml

# Monitoring stack
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

# Application manifests
kubectl apply -f kubernetes/app/

# Test
curl http://app.example.com/api/echo?hello=world&foo=bar
# Response: {"hello":"world","foo":"bar"}
```

### 5. Deploy webhook

```bash
kubectl apply -f kubernetes/webhook/namespace.yaml
kubectl apply -f kubernetes/webhook/configmap.yaml
bash kubernetes/webhook/tls/generate-certs.sh
kubectl apply -f kubernetes/webhook/deployment.yaml
kubectl apply -f kubernetes/webhook/service.yaml
kubectl apply -f kubernetes/webhook/validatingwebhookconfiguration.yaml

# Test: deploy without resource requests → should be rejected
kubectl apply -f - <<EOF
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

## Access URLs

After `/etc/hosts` entry: `192.168.56.200 app.example.com monitoring.example.com jenkins.example.com`

| Service | URL |
|---------|-----|
| Application | http://app.example.com/api/echo?param=value |
| Jenkins | http://192.168.56.201:8080 |
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

**Problem:** stdout logging blocks main thread, degrades throughput.

**Solution:** Logback `AsyncAppender` wrapping `SizeAndTimeBasedRollingPolicy`.

```
Main thread → AsyncAppender (queue: 256, non-blocking)
                   │ async, separate thread
                   ▼
           RollingFileAppender
           /app/logs/app.2024-01-15.log
           maxFileSize: 1GB
           rotation: daily
           totalSizeCap: 10GB
```

Config: `app/src/main/resources/logback-spring.xml`

Fluent-bit reads from `/app/logs/*.log` (file input) and forwards to Elasticsearch.

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

## Assumptions

- VMs have internet access for package downloads
- DockerHub credentials stored in Jenkins Kubernetes Secrets
- DNS resolution for `*.example.com` added to `/etc/hosts` on local machine
- `master.ipv4_cidr_block` of 172.16.0.0/28 conflicts with no existing network
- Elasticsearch runs with `xpack.security.enabled: false` for simplicity (prod: TLS + auth)
- Jenkins `mac1.metal` licensing not applicable in this local setup (addressed in Step 4 docs)

## Kubernetes Cluster Spec

| Parameter | Value |
|-----------|-------|
| Kubernetes version | 1.28.x |
| Container runtime | containerd 1.7 |
| CNI | Calico v3.27 |
| Pod CIDR | 10.244.0.0/16 (custom) |
| Service CIDR | 10.96.0.0/12 (custom) |
| LoadBalancer | MetalLB v0.14 (192.168.56.200-220) |
| Node OS | Ubuntu 22.04 |

## Notes Section Requirements Coverage

| Requirement | Coverage |
|-------------|---------|
| Production-ready K8s cluster | kubeadm 1.28, Calico, private network, MetalLB |
| Jenkins deployment | Helm, JCasC, Node 3 nodeSelector, PVC, LoadBalancer |
| Prometheus, Grafana, ES, fluent-bit, AlertManager | kube-prometheus-stack + ECK + fluent-bit Helm |
| Application build stages | Jenkinsfile.build (test → build → docker → push) |
| Application deployment with Ansible | Jenkinsfile.deploy → deploy-app.yml |
