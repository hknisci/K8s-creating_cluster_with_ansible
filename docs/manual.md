# Dream Games DevOps Case Study — Manuel Uygulama Rehberi

> Bu rehber, Dream Games DevOps Case Study'sini MacBook (macOS) üzerinden sıfırdan
> kendiniz adım adım uygulamanız için yazılmıştır. Her adımda ilgili repo dosyasına
> referans, resmi dokümantasyon linki ve copy-paste hazır komutlar bulunur.

---

## İçindekiler

- [Bölüm 0 — Gereksinimler ve Ön Hazırlık](#bölüm-0--gereksinimler-ve-ön-hazırlık)
- [Bölüm 1 — Altyapı Kurulumu](#bölüm-1--altyapı-kurulumu)
  - [Adım 1: Repo Klonlama](#adım-1-repo-klonlama-ve-yapı-tanıma)
  - [Adım 2: Vagrant ile VM'leri Oluştur](#adım-2-vagrant-ile-vmleri-oluştur)
  - [Adım 3: Ansible Rollerini Anlamak](#adım-3-ansible-rollerini-anlamak)
  - [Adım 4: kubeadm Config Template](#adım-4-kubeadm-config-template)
  - [Adım 5: KUBECONFIG Ayarı](#adım-5-kubeconfig-ayarı)
  - [Adım 6: MetalLB Kurulumu](#adım-6-metallb-kurulumu)
  - [Adım 7: Ingress-NGINX Kurulumu](#adım-7-ingress-nginx-kurulumu)
  - [Adım 8: /etc/hosts ve ExternalDNS](#adım-8-etchosts-ve-externaldns-ayarı)
- [Bölüm 2 — Java Uygulaması Geliştirme](#bölüm-2--java-uygulaması-geliştirme)
  - [Adım 9: Spring Boot Projesini Anlamak](#adım-9-spring-boot-projesini-anlamak)
  - [Adım 10: Yapılandırma Dosyaları](#adım-10-yapılandırma-dosyaları)
  - [Adım 11: MDC Request Correlation Filter](#adım-11-mdc-request-correlation-filter)
  - [Adım 12: Dockerfile — Çok Aşamalı Build](#adım-12-dockerfile--çok-aşamalı-build)
- [Bölüm 3 — Kubernetes'e Deployment](#bölüm-3--kubernetese-deployment)
  - [Adım 13: Namespace'leri Oluştur](#adım-13-namespaceleri-oluştur)
  - [Adım 14: ServiceAccount Oluştur](#adım-14-serviceaccount-oluştur)
  - [Adım 15: Deployment Manifest](#adım-15-deployment-manifest)
  - [Adım 16: Service, Ingress, HPA, PDB](#adım-16-service-ingress-hpa-pdb)
  - [Adım 17: NetworkPolicy](#adım-17-networkpolicy)
  - [Adım 18: Tüm Manifest'leri Uygula](#adım-18-tüm-manifestleri-uygula)
  - [Adım 19: Sıfır Kesintili Güncelleme Testi](#adım-19-sıfır-kesintili-güncelleme-testi)
- [Bölüm 4 — Jenkins CI/CD](#bölüm-4--jenkins-cicd)
  - [Adım 20: Jenkins PV ve StorageClass](#adım-20-jenkins-pv-ve-storageclass)
  - [Adım 21: Jenkins Secrets Oluştur](#adım-21-jenkins-secrets-oluştur)
  - [Adım 22: Jenkins Helm Kurulumu](#adım-22-jenkins-helm-kurulumu)
  - [Adım 23: kubeconfig Secret Ekle](#adım-23-kubeconfig-secret-ekle)
  - [Adım 24: Build Pipeline](#adım-24-build-pipeline-jenkinfilesbuild)
  - [Adım 25: Deploy Pipeline](#adım-25-deploy-pipeline-jenkinsfiledeploy)
- [Bölüm 5 — Monitoring Stack](#bölüm-5--monitoring-stack)
  - [Adım 26: Grafana Admin Secret](#adım-26-grafana-admin-secret)
  - [Adım 27: AlertManager Slack Secret](#adım-27-alertmanager-slack-secret)
  - [Adım 28: kube-prometheus-stack Kurulumu](#adım-28-kube-prometheus-stack-kurulumu)
  - [Adım 29: AlertManager Kuralları](#adım-29-alertmanager-kuralları)
  - [Adım 30: Grafana Dashboard](#adım-30-grafana-dashboard)
  - [Adım 31: ECK ve Fluent-bit](#adım-31-eck-elasticsearch-ve-fluent-bit)
- [Bölüm 6 — Admission Webhook](#bölüm-6--admission-webhook)
  - [Adım 32: Go Webhook Kodunu Anlamak](#adım-32-go-webhook-kodunu-anlamak)
  - [Adım 33: Webhook Docker Image Build](#adım-33-webhook-docker-image-build)
  - [Adım 34: Webhook K8s Kaynaklarını Deploy Et](#adım-34-webhook-kubernetes-kaynaklarını-deploy-et)
  - [Adım 35: caBundle Patch](#adım-35-cabundle-patch--neden-kritik)
  - [Adım 36: Webhook Test](#adım-36-webhook-test)
- [Bölüm 7 — İleri Senaryolar (Adım 3)](#bölüm-7--i̇leri-senaryolar-adım-3)
  - [Adım 37: KEDA ile Zamanlanmış Ölçekleme](#adım-37-keda-ile-zamanlanmış-ölçekleme)
  - [Adım 38: Canary Deployment](#adım-38-canary-deployment)
  - [Adım 39: PriorityClass ile Kaynak Yönetimi](#adım-39-priorityclass-ile-kaynak-yönetimi)
- [Bölüm 8 — Doğrulama ve Temizlik](#bölüm-8--doğrulama-ve-temizlik)
  - [Adım 40: Tam Sistem Doğrulaması](#adım-40-tam-sistem-doğrulaması)
  - [Adım 41: Temizlik](#adım-41-temizlik)

---

## Referans Simgeleri

Bu rehberde her adımda şu simgeler kullanılır:

| Simge | Anlamı |
|-------|--------|
| 📖 | Resmi dokümantasyon linki |
| 📦 | Kaynak kodu / GitHub repo linki |
| 🗺 | Bu repodaki ilgili dosya |
| ⚠️ | Dikkat edilmesi gereken önemli not |
| ✅ | Beklenen başarılı çıktı |

---

## Bölüm 0 — Gereksinimler ve Ön Hazırlık

### macOS'a Araçları Kurma

Önce Homebrew paket yöneticisini kurun:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

📖 https://brew.sh

Ardından tüm gerekli araçları kurun:

```bash
# VirtualBox (Intel Mac için)
brew install --cask virtualbox

# Vagrant
brew install --cask vagrant

# Ansible
pip3 install ansible
# veya: brew install ansible

# kubectl
brew install kubectl

# Helm
brew install helm

# Docker Desktop
brew install --cask docker

# Java 21 (Eclipse Temurin)
brew install --cask temurin@21

# Maven
brew install maven

# Go
brew install go
```

Kurulumları doğrulayın:

```bash
vagrant --version        # Vagrant 2.4.x
ansible --version        # ansible [core 2.15.x]
kubectl version --client # v1.32.x
helm version             # v3.14.x
docker --version         # Docker 24.x.x
java --version           # openjdk 21.x.x
mvn --version            # Apache Maven 3.9.x
go version               # go1.21.x
```

### Referans Linkleri

| Araç | Resmi Dokümantasyon |
|------|---------------------|
| VirtualBox | https://www.virtualbox.org/wiki/Downloads |
| Vagrant | https://developer.hashicorp.com/vagrant/docs/installation |
| Ansible | https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html |
| kubectl | https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/ |
| Helm | https://helm.sh/docs/intro/install/ |
| Docker Desktop | https://docs.docker.com/desktop/install/mac-install/ |
| Java (Temurin) | https://adoptium.net/temurin/releases/ |
| Maven | https://maven.apache.org/install.html |
| Go | https://go.dev/doc/install |

### ⚠️ Apple Silicon (M1/M2/M3) Notu

VirtualBox, Apple Silicon mimarisinde çalışmaz. Alternatifler:

- **VMware Fusion** (ücretsiz kişisel kullanım): https://www.vmware.com/products/fusion.html
- **UTM** (ücretsiz, QEMU tabanlı): https://mac.getutm.app

VMware Fusion veya UTM kullanıyorsanız `Vagrantfile` içindeki `provider "virtualbox"` bloğunu ilgili provider ile değiştirmeniz gerekir.

---

## Bölüm 1 — Altyapı Kurulumu

### Adım 1: Repo Klonlama ve Yapı Tanıma

```bash
git clone https://github.com/hknisci/K8s-creating_cluster_with_ansible.git
cd K8s-creating_cluster_with_ansible
git checkout clean/devops-case-study
```

Repo yapısına genel bakış:

```
.
├── Vagrantfile                   # 3 VM tanımı (master + 2 worker)
├── Makefile                      # Kısayol komutları (make up, make verify, ...)
├── ansible/
│   ├── site.yml                  # Ana playbook
│   ├── inventory/hosts.ini       # VM IP ve SSH bilgileri
│   ├── group_vars/all.yml        # Sürüm değişkenleri (K8s 1.32, Calico v3.29.1)
│   ├── roles/common/             # swap kapatma, kernel modülleri, sysctl
│   ├── roles/containerd/         # containerd kurulumu
│   ├── roles/kubeadm/            # kubeadm/kubelet/kubectl kurulumu
│   ├── roles/master/             # cluster init, Calico, join token
│   └── roles/worker/             # cluster'a katılma, node etiketleme
├── app/                          # Java Spring Boot uygulaması
├── webhook/                      # Go admission webhook
├── jenkins/                      # CI/CD pipeline'ları
├── kubernetes/                   # Tüm K8s manifest dosyaları
├── step3-manifests/              # Adım 3: KEDA, canary, priorityclass
└── docs/                         # Tasarım kararları ve bu rehber
```

---

### Adım 2: Vagrant ile VM'leri Oluştur

📖 https://developer.hashicorp.com/vagrant/docs/cli/up  
🗺 [`Vagrantfile`](../Vagrantfile)

Vagrantfile 3 VM tanımlar:

| VM | IP | CPU | RAM | Rol |
|----|-----|-----|-----|-----|
| master | 192.168.56.10 | 2 | 2 GB | Control plane |
| worker1 | 192.168.56.11 | 2 | 2 GB | Worker node |
| worker2 | 192.168.56.12 | 2 | 2 GB | Worker node + Jenkins |

VM'leri başlatın (ilk kez çalıştırıyorsanız Ubuntu 22.04 box'ı indirir, ~2 GB):

```bash
vagrant up
```

worker2 ayağa kalkınca Ansible otomatik çalışır ve tüm cluster bootstrap edilir (~10-15 dk).

Durum kontrolü:

```bash
vagrant status
```

✅ Beklenen çıktı:
```
master   running (virtualbox)
worker1  running (virtualbox)
worker2  running (virtualbox)
```

VM'lere SSH ile bağlanma:

```bash
vagrant ssh master
vagrant ssh worker1
vagrant ssh worker2
```

⚠️ Eğer Ansible manuel çalıştırmak isterseniz (VM'ler ayakta, Ansible atlandıysa):

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml -v
```

---

### Adım 3: Ansible Rollerini Anlamak

📖 https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html  
🗺 [`ansible/site.yml`](../ansible/site.yml) | [`ansible/inventory/hosts.ini`](../ansible/inventory/hosts.ini) | [`ansible/group_vars/all.yml`](../ansible/group_vars/all.yml)

Ansible rol sırası:

```
common      → swap kapatma, kernel modülleri (overlay, br_netfilter), sysctl
containerd  → Docker GPG key, containerd 1.7.23, SystemdCgroup
kubeadm     → K8s repo, kubeadm/kubelet/kubectl 1.32.0, dpkg hold
master      → kubeadm init, Calico CNI, join token
worker      → cluster'a katılma, node etiketi (node-role.kubernetes.io/worker)
```

Sürüm değişkenleri (`ansible/group_vars/all.yml`):

```yaml
kubernetes_version: "1.32.0"
calico_version: "v3.29.1"
containerd_version: "1.7.23"
api_server_address: "192.168.56.10"
pod_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"
```

Sadece belirli bir rol yeniden çalıştırma:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags containerd
```

---

### Adım 4: kubeadm Config Template

📖 https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/#config-file  
🗺 [`ansible/roles/master/templates/kubeadm-config.yaml.j2`](../ansible/roles/master/templates/kubeadm-config.yaml.j2)

Neden `kubeadm init --config=` yerine CLI args?

- **Tekrarlanabilirlik**: Aynı config dosyası her zaman aynı cluster üretir
- **Audit log**: CLI'da olmayan `apiServer.extraArgs` parametrelerini ayarlayabilirsiniz
- **IaC**: YAML dosyası versiyonlanabilir ve incelenebilir

Template'in oluşturduğu config (`/tmp/kubeadm-config.yaml`):

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "1.32.0"
clusterName: "dreamgames-cluster"
controlPlaneEndpoint: "192.168.56.10:6443"
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
apiServer:
  certSANs: ["192.168.56.10", "master", "127.0.0.1"]
  extraArgs:
    - audit-log-path: /var/log/kubernetes/audit.log
    - audit-log-maxage: "30"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
containerLogMaxSize: "50Mi"
```

---

### Adım 5: KUBECONFIG Ayarı

```bash
# master'dan kubeconfig'i yerel makineye kopyala
vagrant ssh master -c "cat ~/.kube/config" > ~/.kube/config-dreamgames

# kubectl'e bu config'i kullanmasını söyle
export KUBECONFIG=~/.kube/config-dreamgames

# Her terminal oturumunda otomatik yüklemek için ~/.zshrc veya ~/.bash_profile'a ekle:
# echo 'export KUBECONFIG=~/.kube/config-dreamgames' >> ~/.zshrc
```

Cluster'ı doğrulayın:

```bash
kubectl get nodes -o wide
```

✅ Beklenen çıktı:
```
NAME      STATUS   ROLES           AGE   VERSION   INTERNAL-IP
master    Ready    control-plane   5m    v1.32.0   192.168.56.10
worker1   Ready    worker          3m    v1.32.0   192.168.56.11
worker2   Ready    worker          3m    v1.32.0   192.168.56.12
```

---

### Adım 6: MetalLB Kurulumu

📖 https://metallb.universe.tf/installation/  
📦 https://github.com/metallb/metallb  
🗺 [`kubernetes/metallb/ipaddresspool.yaml`](../kubernetes/metallb/ipaddresspool.yaml)

**Neden MetalLB gerekli?**  
Bulut ortamında `type: LoadBalancer` tipi Service'ler otomatik IP alır. Bare-metal (Vagrant) ortamında bu mekanizma yoktur — MetalLB bunu ARP/L2 protokolüyle simüle eder.

```bash
# MetalLB native manifest
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml

# MetalLB pod'larının hazır olmasını bekle
kubectl wait --for=condition=available deployment -n metallb-system controller --timeout=90s

# IP havuzu ve L2Advertisement tanımla
kubectl apply -f kubernetes/metallb/ipaddresspool.yaml
```

Bu konfigürasyon Vagrant'ın private network aralığından (192.168.56.200-220) IP atar.

---

### Adım 7: Ingress-NGINX Kurulumu

📖 https://kubernetes.github.io/ingress-nginx/deploy/  
📦 https://github.com/kubernetes/ingress-nginx  
🗺 [`kubernetes/ingress-nginx/values.yaml`](../kubernetes/ingress-nginx/values.yaml)

⚠️ MetalLB'yi **önce** kurmanız gerekir — Ingress Controller bir LoadBalancer IP isteyecek.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f kubernetes/ingress-nginx/values.yaml \
  --wait --timeout 3m
```

LoadBalancer IP'sini kontrol edin:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

✅ EXTERNAL-IP sütununda `192.168.56.200` görünmeli.

---

### Adım 8: /etc/hosts ve ExternalDNS Ayarı

📖 https://github.com/kubernetes-sigs/external-dns  
🗺 [`kubernetes/externaldns/deployment.yaml`](../kubernetes/externaldns/deployment.yaml)

macOS'ta yerel DNS çözümlemesi için `/etc/hosts` dosyasını düzenleyin:

```bash
sudo nano /etc/hosts
```

Şu satırları ekleyin:

```
192.168.56.200  app.example.com monitoring.example.com
192.168.56.201  jenkins.example.com
```

Kaydetmek için: `Ctrl+O`, `Enter`, `Ctrl+X`

ExternalDNS'i cluster'a deploy edin (embedded etcd pod ile birlikte):

```bash
kubectl apply -f kubernetes/externaldns/rbac.yaml
kubectl apply -f kubernetes/externaldns/deployment.yaml
```

**Neden embedded etcd?** ExternalDNS'in `coredns` provider'ı bir etcd backend'e ihtiyaç duyar. Gerçek üretim ortamında Route53, Cloudflare veya başka managed DNS kullanılır; burada tek-pod etcd, case study için yeterlidir.

---

## Bölüm 2 — Java Uygulaması Geliştirme

### Adım 9: Spring Boot Projesini Anlamak

📖 https://docs.spring.io/spring-boot/docs/3.2.1/reference/html/  
📖 https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html  
📖 https://micrometer.io/docs/registry/prometheus  
🗺 [`app/pom.xml`](../app/pom.xml) | [`app/src/main/java/com/dreamgames/controller/QueryParamController.java`](../app/src/main/java/com/dreamgames/controller/QueryParamController.java)

**Temel bağımlılıklar (pom.xml):**

| Bağımlılık | Amaç |
|-----------|-------|
| `spring-boot-starter-web` | HTTP endpoint'leri |
| `spring-boot-starter-actuator` | `/actuator/health`, `/actuator/prometheus` |
| `micrometer-registry-prometheus` | Prometheus metrik formatı |
| `logstash-logback-encoder` | JSON yapılandırmalı log formatı |

**Ana endpoint:**

```
GET /api/echo?param1=val1&param2=val2
→ {"param1":"val1","param2":"val2"}
```

**Prometheus metriği:** `app_echo_requests_total` — her `/api/echo` isteğinde 1 artar.

Local olarak çalıştırma:

```bash
cd app
mvn spring-boot:run
curl 'http://localhost:8080/api/echo?hello=world'
# → {"hello":"world"}
```

---

### Adım 10: Yapılandırma Dosyaları

📖 https://docs.spring.io/spring-boot/docs/current/reference/html/application-properties.html  
📖 https://github.com/logfellow/logstash-logback-encoder  
🗺 [`app/src/main/resources/application.yml`](../app/src/main/resources/application.yml) | [`app/src/main/resources/logback-spring.xml`](../app/src/main/resources/logback-spring.xml)

**İki ayrı port neden gerekli?**

```yaml
server:
  port: 8080            # → uygulama HTTP trafiği (kullanıcı istekleri)
management:
  server:
    port: 9090          # → actuator endpoint'leri (health, prometheus)
```

Port 9090 dışarıya açılmaz; yalnızca Prometheus ve K8s probe'ları erişir. Bu sayede `curl http://app.example.com/actuator/prometheus` isteği dışarıdan çalışmaz — güvenlik.

**`health.show-details: when-authorized`** — Yetkisiz istekte `{"status":"UP"}` döner; detaylar (disk, DB bağlantısı, vb.) yalnızca kimlik doğrulaması yapılmış isteklerde görünür.

**Logback AsyncAppender:**

```
HTTP isteği
    │
    ▼
Main Thread → log.info("...") → AsyncAppender (kuyruk: 256)
                                         │  ayrı thread
                                         ▼
                               RollingFileAppender
                               /app/logs/query-param-app.log
                               (JSON format, gzip rotasyon)
```

Yüksek trafik altında log yazma işlemi ana thread'i bloklamaz.

---

### Adım 11: MDC Request Correlation Filter

📖 https://logback.qos.ch/manual/mdc.html  
🗺 [`app/src/main/java/com/dreamgames/filter/RequestIdFilter.java`](../app/src/main/java/com/dreamgames/filter/RequestIdFilter.java)

**Neden gerekli?**

Yüzlerce eş zamanlı istek varken tek bir isteğe ait tüm log satırlarını bulmak için her isteğe benzersiz bir ID atanır. Bu ID tüm log satırlarına otomatik eklenir.

**Akış:**

```
HTTP isteği gelir
    ↓
RequestIdFilter çalışır:
  1. "X-Request-Id" header var mı? → Varsa onu kullan
  2. Yoksa → UUID oluştur (12 karakter hex)
  3. MDC.put("requestId", id) → logback bu değeri her log satırına ekler
  4. HTTP response'a "X-Request-Id" header'ı ekle
    ↓
Controller çalışır → log.info("...") → JSON'da "requestId" alanı otomatik
    ↓
Finally bloğu: MDC.remove("requestId")
```

Test:

```bash
curl -v http://localhost:8080/api/echo?x=1 2>&1 | grep -i x-request-id
```

✅ `< X-Request-Id: a3f8b2c1d9e4` gibi bir değer görünmeli.

Log'da ilgili satırı bulmak:

```bash
grep "a3f8b2c1d9e4" /app/logs/query-param-app.log
```

---

### Adım 12: Dockerfile — Çok Aşamalı Build

📖 https://docs.docker.com/build/building/multi-stage/  
📖 https://hub.docker.com/_/eclipse-temurin  
🗺 [`app/Dockerfile`](../app/Dockerfile)

**3 aşamalı build:**

```dockerfile
# Aşama 1: Bağımlılıkları önbelleğe al
FROM maven:3.9-eclipse-temurin-21-alpine AS deps
RUN mvn dependency:go-offline   # → sonraki build'lerde bu katman değişmez

# Aşama 2: JAR oluştur
FROM deps AS builder
RUN mvn package -DskipTests

# Aşama 3: Sadece çalıştırma için (JRE, JDK değil)
FROM eclipse-temurin:21-jre-alpine AS runtime
# Root olmayan kullanıcı oluştur
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
```

**`-XX:MaxRAMPercentage=75.0`** — Container'a ayrılan belleğin %75'ini JVM heap olarak kullan. 512 MiB limit varsa ~384 MiB heap olur. Sabit `-Xmx` yerine bu kullanılır çünkü farklı ortamlarda (test, prod) container boyutu değişebilir.

Local build ve test:

```bash
cd app

# Unit testleri çalıştır
mvn clean test

# JAR oluştur
mvn clean package -DskipTests

# Docker image oluştur
docker build -t dreamgames/query-param-app:local .

# Container olarak çalıştır
docker run -p 8080:8080 -p 9090:9090 \
  -e SPRING_PROFILES_ACTIVE=prod \
  dreamgames/query-param-app:local

# Farklı terminal'de test et
curl 'http://localhost:8080/api/echo?hello=world'
# ✅ → {"hello":"world"}

curl 'http://localhost:9090/actuator/health'
# ✅ → {"status":"UP"}

curl 'http://localhost:9090/actuator/prometheus' | grep app_echo
# ✅ → app_echo_requests_total{...} 1.0
```

---

## Bölüm 3 — Kubernetes'e Deployment

### Adım 13: Namespace'leri Oluştur

📖 https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/  
📖 https://kubernetes.io/docs/concepts/security/pod-security-admission/  
🗺 [`kubernetes/namespaces/namespaces.yaml`](../kubernetes/namespaces/namespaces.yaml)

**Pod Security Admission (PSA) seviyeleri:**

| Namespace | PSA Seviyesi | Ne engeller? |
|-----------|-------------|--------------|
| app | restricted | root çalışma, privilege escalation, host ağı, hostPath |
| webhook-system | restricted | aynısı |
| monitoring | baseline | sadece en tehlikeli özellikler |
| jenkins | baseline | aynısı |

```bash
kubectl apply -f kubernetes/namespaces/namespaces.yaml

# PSA etiketlerini doğrula
kubectl get ns --show-labels | grep -E "app|monitoring|jenkins|webhook"
```

✅ `pod-security.kubernetes.io/enforce=restricted` etiketleri görünmeli.

---

### Adım 14: ServiceAccount Oluştur

📖 https://kubernetes.io/docs/concepts/security/service-accounts/  
🗺 [`kubernetes/app/serviceaccount.yaml`](../kubernetes/app/serviceaccount.yaml)

```bash
kubectl apply -f kubernetes/app/serviceaccount.yaml
```

**`automountServiceAccountToken: false` neden önemli?**

Varsayılan olarak her pod, Kubernetes API'ye erişmek için otomatik bir token alır. Uygulama API'yi kullanmıyorsa bu token gereksiz saldırı yüzeyidir. `false` yaparak bu riski ortadan kaldırırız.

---

### Adım 15: Deployment Manifest

📖 https://kubernetes.io/docs/concepts/workloads/controllers/deployment/  
📖 https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/  
📖 https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/  
🗺 [`kubernetes/app/deployment.yaml`](../kubernetes/app/deployment.yaml)

**Kritik konfigürasyonlar ve açıklamaları:**

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1         # Güncelleme sırasında 1 fazladan pod başlatılır
    maxUnavailable: 0   # Hiçbir pod kaldırılmadan önce yeni pod hazır olmalı
```

→ Sıfır kesintili güncelleme sağlar. Yeni pod önce `Ready` olur, sonra eski pod silinir.

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname   # Node bazında dağıt
    whenUnsatisfiable: DoNotSchedule
```

→ 4 pod: 2'si worker1'de, 2'si worker2'de. Bir node çöktüğünde 2 pod hayatta kalır.

```yaml
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 9090          # management port!
  initialDelaySeconds: 20
```

→ Spring Boot readiness endpoint'i `UP` dönene kadar trafik gelmez.

```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 5"]
terminationGracePeriodSeconds: 30
```

→ Kubernetes "pod'u durdur" sinyali gönderince önce 5 sn beklenir. Bu sürede load balancer pod'u listeden çıkarır ve uçuştaki (in-flight) HTTP istekleri tamamlanır.

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  seccompProfile:
    type: RuntimeDefault   # seccomp filtresi: tehlikeli syscall'ları engeller
containers:
  - securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: [ALL]        # Tüm Linux capability'leri kaldır
```

---

### Adım 16: Service, Ingress, HPA, PDB

📖 Services: https://kubernetes.io/docs/concepts/services-networking/service/  
📖 HPA: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/  
📖 PDB: https://kubernetes.io/docs/tasks/run-application/configure-pdb/  
🗺 [`kubernetes/app/service.yaml`](../kubernetes/app/service.yaml) | [`kubernetes/app/ingress.yaml`](../kubernetes/app/ingress.yaml) | [`kubernetes/app/hpa.yaml`](../kubernetes/app/hpa.yaml) | [`kubernetes/app/pdb.yaml`](../kubernetes/app/pdb.yaml)

**HPA konfigürasyonu:**

```yaml
minReplicas: 4
maxReplicas: 16
metrics:
  - CPU kullanımı > %70 → ölçek büyüt
  - Bellek kullanımı > %80 → ölçek büyüt
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300   # 5 dk bekle, ani scale-down engellenir
  scaleUp:
    stabilizationWindowSeconds: 30    # 30 sn bekle, gereksiz spike'larda ölçekleme olmaz
```

**PDB (Pod Disruption Budget):**

```yaml
maxUnavailable: 1
```

`kubectl drain worker1` çalıştırıldığında sistem aynı anda en fazla 1 pod kaldırır. 4 pod varsa 3'ü çalışmaya devam eder.

---

### Adım 17: NetworkPolicy

📖 https://kubernetes.io/docs/concepts/services-networking/network-policies/  
🗺 [`kubernetes/app/networkpolicy.yaml`](../kubernetes/app/networkpolicy.yaml)

**Varsayılan-kapat (default-deny) politikası:**

```yaml
policyTypes: [Ingress, Egress]    # Her ikisi de varsayılan kapalı
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-nginx
    ports: [8080]   # Sadece Nginx → uygulama (HTTP)
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: monitoring
    ports: [9090]   # Sadece Prometheus → actuator (metrics)
egress:
  - ports: [53/UDP, 53/TCP]       # Sadece DNS çözümleme
```

Uygulamalar arası network güvenliği: `app` namespace'indeki bir pod ele geçirilse bile cluster içinde serbestçe dolaşamaz.

---

### Adım 18: Tüm Manifest'leri Uygula

```bash
# Tüm app manifest'lerini uygula (ServiceAccount, Deployment, Service, Ingress, HPA, PDB, NetworkPolicy)
kubectl apply -f kubernetes/app/

# Rollout tamamlanana kadar bekle
kubectl rollout status deployment/query-param-app -n app --timeout=120s

# Pod dağılımını kontrol et (worker1 ve worker2'de eşit olmalı)
kubectl get pods -n app -o wide

# HPA durumu
kubectl describe hpa query-param-app -n app

# Uygulama testi
curl 'http://app.example.com/api/echo?hello=world'
# ✅ → {"hello":"world"}

# requestId header testi
curl -v http://app.example.com/api/echo 2>&1 | grep -i x-request-id
# ✅ → X-Request-Id: a3f8b2c1d9e4
```

---

### Adım 19: Sıfır Kesintili Güncelleme Testi

📖 https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/

İki terminal açın:

```bash
# Terminal 1: Sürekli istek gönder, HTTP durum kodunu yaz
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" http://app.example.com/api/echo?x=1
  sleep 0.5
done
```

```bash
# Terminal 2: Image güncelle (v2.0.0 mevcut olmayabilir; sadece tag değişimini test için)
kubectl set image deployment/query-param-app \
  query-param-app=dreamgames/query-param-app:1.0.0 \
  -n app

kubectl rollout status deployment/query-param-app -n app
```

✅ Terminal 1'de sürekli `200` görünmeli, hiç `503` veya `000` olmamalı.

Rollback (gerekirse):

```bash
kubectl rollout undo deployment/query-param-app -n app
```

---

## Bölüm 4 — Jenkins CI/CD

### Adım 20: Jenkins PV ve StorageClass

📖 https://kubernetes.io/docs/concepts/storage/persistent-volumes/  
🗺 [`kubernetes/jenkins/storageclass.yaml`](../kubernetes/jenkins/storageclass.yaml) | [`kubernetes/jenkins/pv.yaml`](../kubernetes/jenkins/pv.yaml)

Jenkins'in verilerini (job geçmişi, plugin'ler, credential'lar) kalıcı saklamak için:

```bash
# worker2 üzerinde Jenkins için dizin oluştur
vagrant ssh worker2 -c "sudo mkdir -p /mnt/jenkins && sudo chown 1000:1000 /mnt/jenkins"

# StorageClass ve PV oluştur
kubectl apply -f kubernetes/jenkins/storageclass.yaml
kubectl apply -f kubernetes/jenkins/pv.yaml

# Kontrol
kubectl get pv jenkins-pv
```

✅ STATUS: `Available` görünmeli.

---

### Adım 21: Jenkins Secrets Oluştur

⚠️ Şifre ve token'ları **asla** YAML dosyasına yazmayın ve Git'e commit etmeyin!

**DockerHub erişim token'ı oluşturma:**
1. https://hub.docker.com/settings/security adresine gidin
2. "New Access Token" → "Read & Write" izni → token'ı kopyalayın

**GitHub erişim token'ı oluşturma:**
1. https://github.com/settings/tokens adresine gidin
2. "Fine-grained tokens" → repo erişimi → token'ı kopyalayın

```bash
kubectl create secret generic jenkins-credentials \
  --from-literal=admin-password=<GÜÇLÜ_BİR_ŞİFRE_YAZIN> \
  --from-literal=dockerhub-user=<DOCKERHUB_KULLANICI_ADI> \
  --from-literal=dockerhub-token=<DOCKERHUB_TOKEN> \
  --from-literal=github-user=<GITHUB_KULLANICI_ADI> \
  --from-literal=github-token=<GITHUB_TOKEN> \
  -n jenkins
```

Secret'ın oluştuğunu doğrulayın (değerleri göstermez):

```bash
kubectl describe secret jenkins-credentials -n jenkins
```

---

### Adım 22: Jenkins Helm Kurulumu

📖 https://www.jenkins.io/doc/book/installing/kubernetes/  
📦 https://artifacthub.io/packages/helm/jenkinsci/jenkins  
📖 JCasC: https://www.jenkins.io/projects/jcasc/  
🗺 [`kubernetes/jenkins/values.yaml`](../kubernetes/jenkins/values.yaml)

**JCasC (Jenkins Configuration as Code) ne sağlar?**

Jenkins başladığında `values.yaml` içindeki `JCasC` bloğu otomatik çalışır:
- Admin kullanıcısını oluşturur
- DockerHub ve GitHub credential'larını yükler
- Maven ve JDK tool tanımlarını yapar
- Pipeline job'larını tanımlar

```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update

helm install jenkins jenkins/jenkins \
  -n jenkins --create-namespace \
  -f kubernetes/jenkins/values.yaml \
  --wait --timeout 5m
```

Jenkins'e erişim:

```bash
# LoadBalancer IP'sini öğren
kubectl get svc jenkins -n jenkins

# Erişim: http://jenkins.example.com:8080
# Kullanıcı: admin  /  Şifre: values.yaml'da belirlediğiniz
```

---

### Adım 23: kubeconfig Secret Ekle

Deploy pipeline'ı, Kubernetes cluster'ına `kubectl` ile bağlanmak için kubeconfig'e ihtiyaç duyar:

```bash
kubectl create secret generic kubeconfig \
  --from-file=config=$KUBECONFIG \
  -n jenkins

# Jenkins'i yeniden başlat (yeni secret'ı okusun)
kubectl rollout restart deployment/jenkins -n jenkins
kubectl rollout status deployment/jenkins -n jenkins
```

---

### Adım 24: Build Pipeline (Jenkinsfile.build)

📖 https://www.jenkins.io/doc/book/pipeline/  
📖 Aqua Trivy: https://aquasecurity.github.io/trivy/latest/docs/  
📦 https://github.com/aquasecurity/trivy  
🗺 [`jenkins/Jenkinsfile.build`](../jenkins/Jenkinsfile.build)

**Pipeline aşamaları:**

```
Checkout → Unit Tests → Build JAR → Docker Build → Image Scan → Docker Push → Tag Release
```

**Önemli kararlar:**

1. **`:latest` tag yok.** `IMAGE_TAG = "${BUILD_NUMBER}-${GIT_COMMIT[0..7]}"` format kullanılır.
   Örnek: `42-a3f8b2c`. `:latest` mutable (değişken) bir tag olduğu için hangi versiyon olduğu belirsizdir.

2. **Trivy image scan.** Build'den sonra, push'dan önce:
   ```groovy
   docker run aquasec/trivy:latest image \
     --exit-code 1 \
     --severity HIGH,CRITICAL \
     ${DOCKER_IMAGE}:${IMAGE_TAG}
   ```
   HIGH veya CRITICAL zafiyet varsa `exit-code 1` döner ve pipeline durur — imaj DockerHub'a gönderilmez.

Jenkins'te pipeline oluşturma:
1. Jenkins UI'da: **New Item** → İsim girin → **Pipeline** → OK
2. **Pipeline** sekmesinde: Definition → **Pipeline script from SCM**
3. SCM: **Git** → Repository URL → Branch: `*/clean/devops-case-study`
4. Script Path: `jenkins/Jenkinsfile.build`
5. Save

---

### Adım 25: Deploy Pipeline (Jenkinsfile.deploy)

🗺 [`jenkins/Jenkinsfile.deploy`](../jenkins/Jenkinsfile.deploy)

**Pipeline aşamaları:**

```
Checkout → Validate Manifests → Deploy via Ansible → Verify Rollout → Smoke Test
```

**Rollback mekanizması:**

```groovy
post {
  failure {
    sh "kubectl rollout undo deployment/query-param-app -n ${params.ENVIRONMENT}"
  }
}
```

Deploy başarısız olursa pipeline otomatik olarak `kubectl rollout undo` çalıştırır ve önceki versiyona döner.

**`--dry-run=client` aşaması** — manifest'leri cluster'a uygulamadan önce YAML sözdizimini ve API uyumluluğunu kontrol eder. Hatalı manifest bulunursa deploy aşamasına geçilmez.

---

## Bölüm 5 — Monitoring Stack

### Adım 26: Grafana Admin Secret

⚠️ Şifreyi YAML'a yazmayın:

```bash
kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=<GÜÇLÜ_ŞİFRE>
```

---

### Adım 27: AlertManager Slack Secret

Slack Webhook URL oluşturma: https://api.slack.com/messaging/webhooks → "Create an app" → "Incoming Webhooks"

⚠️ Webhook URL bir token içerir, asla Git'e commit etmeyin:

```bash
kubectl create secret generic alertmanager-slack-secret -n monitoring \
  --from-literal=webhookUrl=https://hooks.slack.com/services/T.../B.../...
```

---

### Adım 28: kube-prometheus-stack Kurulumu

📖 https://prometheus-operator.dev/  
📖 https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack  
📖 Grafana: https://grafana.com/docs/grafana/latest/  
🗺 [`kubernetes/monitoring/kube-prometheus-stack-values.yaml`](../kubernetes/monitoring/kube-prometheus-stack-values.yaml)

**kube-prometheus-stack şunları içerir:**
- Prometheus (metrics toplayıcı)
- Grafana (görselleştirme)
- AlertManager (bildirim yöneticisi)
- kube-state-metrics (K8s obje metrikleri)
- node-exporter (node CPU/bellek/disk metrikleri)
- Prometheus Operator (PrometheusRule CRD desteği)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f kubernetes/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m

# İzleme ingress'ini de uygula
kubectl apply -f kubernetes/monitoring/ingress-monitoring.yaml
```

Grafana'ya eriş: http://monitoring.example.com/grafana  
Kullanıcı: `admin` / Şifre: yukarıda belirlediğiniz

---

### Adım 29: AlertManager Kuralları

📖 PrometheusRule CRD: https://prometheus-operator.dev/docs/operator/api/#monitoring.coreos.com/v1.PrometheusRule  
📖 PromQL öğrenmek için: https://prometheus.io/docs/prometheus/latest/querying/basics/  
🗺 [`kubernetes/monitoring/alertmanager-rules.yaml`](../kubernetes/monitoring/alertmanager-rules.yaml)

```bash
kubectl apply -f kubernetes/monitoring/alertmanager-rules.yaml

# Kuralların yüklendiğini doğrula
kubectl get prometheusrule -n monitoring
```

✅ `dreamgames-app-alerts` görünmeli.

**Tanımlı alert kuralları:**

| Alert | Tetikleyici | Önem |
|-------|-------------|------|
| PodCrashLooping | 5 dk içinde restart > 0 | warning |
| PodNotReady | 5 dk hazır değil | critical |
| DeploymentReplicasMismatch | İstenilen != mevcut replica | critical |
| HighRequestLatency | p95 gecikme > 1 sn | warning |
| HighErrorRate | 5xx oranı > %5 | critical |
| HPAMaxedOut | HPA max replica'ya ulaştı | warning |
| NodeHighCPU | Node CPU > %85 | warning |
| NodeHighMemory | Node bellek > %85 | warning |
| NodeDiskPressure | DiskPressure condition = true | critical |
| PVCNearFull | PVC kullanımı > %85 | warning |
| ElasticsearchDiskHigh | ES disk boş < %15 | critical |
| ElasticsearchClusterRed | ES cluster rengi kırmızı | critical |

Her alert'te `runbook` annotation var — ne yapılacağı belirtiyor.

---

### Adım 30: Grafana Dashboard

📖 https://grafana.com/docs/grafana/latest/dashboards/  
🗺 [`kubernetes/monitoring/grafana-dashboards/app-metrics-configmap.yaml`](../kubernetes/monitoring/grafana-dashboards/app-metrics-configmap.yaml)

```bash
kubectl apply -f kubernetes/monitoring/grafana-dashboards/
```

`grafana_dashboard: "1"` label'ı sayesinde Grafana sidecar container bu ConfigMap'i otomatik tespit eder ve dashboard'u yükler.

Grafana UI'da dashboard konumu: **Dashboards → Browse → "query-param-app — RED Metrics"**

Dashboard içerikleri:
- **R** (Rate): İstek/saniye, URI bazlı
- **E** (Errors): 5xx hata oranı yüzdesi
- **D** (Duration): Gecikme p50 / p95 / p99
- **JVM**: Heap kullanımı, GC pause süresi, thread sayısı
- **Altyapı**: HPA replica durumu, pod CPU ve bellek

---

### Adım 31: ECK (Elasticsearch) ve Fluent-bit

📖 ECK: https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-quickstart.html  
📖 Fluent Bit: https://docs.fluentbit.io/manual/  
📦 ECK GitHub: https://github.com/elastic/cloud-on-k8s  
🗺 [`kubernetes/monitoring/elasticsearch/`](../kubernetes/monitoring/elasticsearch/) | [`kubernetes/monitoring/fluent-bit/values.yaml`](../kubernetes/monitoring/fluent-bit/values.yaml)

**Log akışı:**

```
Uygulama pod'u → /app/logs/query-param-app.log (JSON)
                           ↓
                    Fluent-bit (DaemonSet)
                    input: tail /app/logs/*.log
                           ↓
                    Elasticsearch (ECK)
                    index: app-logs-YYYY.MM.DD
```

```bash
# ECK Operator kurulumu
kubectl create -f https://download.elastic.co/downloads/eck/2.11.1/crds.yaml
kubectl apply  -f https://download.elastic.co/downloads/eck/2.11.1/operator.yaml

# Elasticsearch cluster oluştur
kubectl apply -f kubernetes/monitoring/elasticsearch/eck-operator.yaml

# Hazır olmasını bekle (birkaç dakika sürebilir)
kubectl get elasticsearch -n monitoring
# ✅ health: green beklenir

# Fluent-bit kurulumu
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
helm install fluent-bit fluent/fluent-bit \
  -n monitoring \
  -f kubernetes/monitoring/fluent-bit/values.yaml
```

---

## Bölüm 6 — Admission Webhook

### Adım 32: Go Webhook Kodunu Anlamak

📖 Admission Webhooks: https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/  
📦 Prometheus Go client: https://github.com/prometheus/client_golang  
🗺 [`webhook/main.go`](../webhook/main.go)

**Webhook nasıl çalışır?**

```
kubectl apply -f bad-deploy.yaml
        ↓
kube-apiserver
        ↓ HTTPS POST /validate
resource-webhook:8443
        ↓
validateDeployment() fonksiyonu:
  1. Namespace allowed listesinde mi? → Hayırsa: izin ver (pas geç)
  2. AdmissionReview JSON → appsv1.Deployment decode et
  3. initContainers döngüsü: resources.requests.cpu ve .memory var mı?
  4. containers döngüsü: aynı kontrol
  5. Eksik varsa → violations listesi → AdmissionResponse{Allowed: false}
        ↓
kube-apiserver: "Error: admission webhook denied the request"
```

**İki HTTP sunucu neden var?**

```
:8443 (TLS)  → /validate  → kube-apiserver buraya çağrı yapar (TLS zorunlu)
:8080 (HTTP) → /metrics   → Prometheus TLS olmadan scrape eder (basit)
```

**Prometheus metrikleri (webhook):**

```
webhook_validations_total   → işlenen toplam review sayısı
webhook_rejections_total    → reddedilen deployment sayısı
webhook_errors_total        → işleme hatası sayısı
webhook_request_duration_seconds → istek süre histogramı
```

---

### Adım 33: Webhook Docker Image Build

📖 Go multi-stage Dockerfile: https://docs.docker.com/language/golang/build-images/  
🗺 [`webhook/Dockerfile`](../webhook/Dockerfile) | [`webhook/main.go`](../webhook/main.go)

```bash
cd webhook

# Bağımlılıkları temizle ve doğrula
go mod tidy

# Kod kalitesi kontrolü
go vet ./...

# Derleme (hata var mı?)
go build ./...
# ✅ Hata mesajı olmadan tamamlanmalı

# Unit testler
go test ./... -v

# Docker image oluştur
docker build -t dreamgames/resource-webhook:1.0.0 .

# DockerHub'a gönder
docker push dreamgames/resource-webhook:1.0.0

cd ..
```

**`scratch` base image:** Yalnızca Go binary ve CA sertifikaları içerir. Final image boyutu ~5 MB. Karşılaştırma: Ubuntu base olsaydı ~200 MB.

---

### Adım 34: Webhook Kubernetes Kaynaklarını Deploy Et

🗺 [`kubernetes/webhook/`](../kubernetes/webhook/) klasörü

⚠️ **Sıra önemlidir.** Önce RBAC ve sertifika, sonra pod, en son webhook konfigürasyonu.

```bash
# ServiceAccount, ClusterRole, ClusterRoleBinding
kubectl apply -f kubernetes/webhook/rbac.yaml

# Namespace listesi ConfigMap (hangi namespace'lerde enforce edilsin)
kubectl apply -f kubernetes/webhook/configmap.yaml

# TLS sertifika oluştur (self-signed CA + server cert) ve caBundle'ı patch et
bash kubernetes/webhook/tls/generate-certs.sh

# Webhook pod'larını deploy et
kubectl apply -f kubernetes/webhook/deployment.yaml
kubectl apply -f kubernetes/webhook/service.yaml
kubectl apply -f kubernetes/webhook/networkpolicy.yaml

# ValidatingWebhookConfiguration'ı son uygula (pod hazır olmalı)
kubectl apply -f kubernetes/webhook/validatingwebhookconfiguration.yaml

# Kontrol
kubectl get pods -n webhook-system
# ✅ 2 pod Running olmalı
```

---

### Adım 35: caBundle Patch — Neden Kritik?

📖 https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/#contacting-the-webhook

`generate-certs.sh` scripti bunu otomatik yapar. Ama ne yaptığını anlamak için:

```
kube-apiserver → webhook'a HTTPS bağlantısı kurar
kube-apiserver → webhook'un sertifikasını doğrulamak için CA'ya ihtiyaç duyar
CA sertifikası → ValidatingWebhookConfiguration.webhooks[0].clientConfig.caBundle alanına yazılır
```

Manuel patch:

```bash
CA_BUNDLE=$(kubectl get secret resource-webhook-tls -n webhook-system \
  -o jsonpath='{.data.ca\.crt}')

kubectl patch validatingwebhookconfiguration resource-requests-webhook \
  --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${CA_BUNDLE}\"}]"
```

caBundle'ın dolu olduğunu doğrulayın:

```bash
kubectl get validatingwebhookconfiguration resource-requests-webhook \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c
# ✅ 0'dan büyük bir sayı görünmeli (örn: 1816)
```

---

### Adım 36: Webhook Test

```bash
# Test 1 — Kötü deployment: resources YOK → reddedilmeli
cat <<'EOF' | kubectl apply -f -
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
          # resources eksik → webhook reddeder
EOF

# ✅ Beklenen çıktı:
# Error from server: admission webhook "resource-requests.dreamgames.com" denied the request:
# Deployment "bad-deploy" rejected — resource requests required:
# container "bad": missing resource requests (cpu and memory required)
```

```bash
# Test 2 — İyi deployment: resources VAR → kabul edilmeli
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: good-deploy
  namespace: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: good
  template:
    metadata:
      labels:
        app: good
    spec:
      containers:
        - name: good
          image: nginx
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
EOF

# ✅ Beklenen çıktı:
# deployment.apps/good-deploy created
```

```bash
# Temizlik
kubectl delete deployment good-deploy -n app 2>/dev/null || true
```

---

## Bölüm 7 — İleri Senaryolar (Adım 3)

### Adım 37: KEDA ile Zamanlanmış Ölçekleme

📖 https://keda.sh/docs/latest/  
📖 KEDA CronScaler: https://keda.sh/docs/latest/scalers/cron/  
📦 https://github.com/kedacore/keda  
🗺 [`step3-manifests/hpa-scheduled.yaml`](../step3-manifests/hpa-scheduled.yaml) | [`docs/design-answers/step3-autoscaling.md`](design-answers/step3-autoscaling.md)

**Standart HPA vs KEDA CronTrigger:**

| | Standart HPA | KEDA CronTrigger |
|--|-------------|------------------|
| Ölçekleme zamanı | Yoğunluk başladıktan sonra | Yoğunluktan önce (proaktif) |
| Yükleme süresi | Pod başlama + JVM warmup (~30 sn) | Yoğunluktan önce hazır |
| Kullanım senaryosu | Beklenmeyen spike'lar | Sabah-akşam düzenli trafik |

```bash
# KEDA kurulumu
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda \
  --namespace keda --create-namespace

# ⚠️ Standart HPA ve KEDA ScaledObject aynı anda olamaz — çakışır
kubectl delete hpa query-param-app -n app

# KEDA ScaledObject uygula
kubectl apply -f step3-manifests/hpa-scheduled.yaml

# Kontrol
kubectl get scaledobject -n app
kubectl get hpa -n app   # KEDA kendi HPA'sını oluşturur
```

---

### Adım 38: Canary Deployment

📖 https://kubernetes.github.io/ingress-nginx/examples/canary/  
🗺 [`step3-manifests/canary-deployment.yaml`](../step3-manifests/canary-deployment.yaml) | [`docs/design-answers/step3-deployment-strategy.md`](design-answers/step3-deployment-strategy.md)

**Canary deployment akışı:**

```
v1 (stable, 4 replicas)  ──────────── %90 trafik
v2 (canary, 1 replica)   ──────────── %10 trafik
                    ↓ Grafana'da hata oranı izle (15-30 dk)
                    ↓ Sorun yoksa → canary-weight=50
                    ↓ Sorun yoksa → canary-weight=100
                    ↓ v1 Deployment'ı sil
```

```bash
# Canary deployment ve ingress uygula
kubectl apply -f step3-manifests/canary-deployment.yaml

# Trafik ağırlığını artır (%10 → %50)
kubectl annotate ingress query-param-app-canary \
  nginx.ingress.kubernetes.io/canary-weight=50 \
  -n app --overwrite

# Tam geçiş (%100 canary)
kubectl annotate ingress query-param-app-canary \
  nginx.ingress.kubernetes.io/canary-weight=100 \
  -n app --overwrite

# Rollback: canary ingress'i sil → %100 trafik v1'e döner
kubectl delete ingress query-param-app-canary -n app
```

---

### Adım 39: PriorityClass ile Kaynak Yönetimi

📖 https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/  
📖 QoS sınıfları: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/  
🗺 [`step3-manifests/priority-classes.yaml`](../step3-manifests/priority-classes.yaml)

**Senaryo:** Aynı cluster'da gerçek zamanlı App X ve batch işlemci App Y var. Node baskı altında kaldığında hangisi önce tahliye edilir?

**Çözüm: PriorityClass**

```yaml
# App X: Gerçek zamanlı — yüksek öncelik
kind: PriorityClass
metadata:
  name: high-priority-realtime
value: 1000   # Yüksek değer = yüksek öncelik

# App Y: Batch — düşük öncelik
kind: PriorityClass
metadata:
  name: low-priority-batch
value: 100
```

Node dolduğunda scheduler, App Y pod'larını tahliye ederek App X için yer açar.

**QoS sınıfları (tahliye sırası):**
1. `BestEffort` (request/limit yok) → ilk tahliye
2. `Burstable` (request < limit) → ikinci
3. `Guaranteed` (request == limit) → son tahliye

```bash
kubectl apply -f step3-manifests/priority-classes.yaml
kubectl apply -f step3-manifests/app-x-deployment.yaml
kubectl apply -f step3-manifests/app-y-deployment.yaml

kubectl get priorityclass
# ✅ high-priority-realtime (1000) ve low-priority-batch (100) görünmeli
```

---

## Bölüm 8 — Doğrulama ve Temizlik

### Adım 40: Tam Sistem Doğrulaması

🗺 [`Makefile`](../Makefile)

Tek komutla tüm kontroller:

```bash
make verify
```

Detaylı manuel kontroller:

```bash
# Node'lar
kubectl get nodes -o wide
# ✅ master, worker1, worker2 — STATUS: Ready

# Tüm pod'lar (Running olmayan varsa listele)
kubectl get pods -A | grep -Ev "Running|Completed|Evicted" | grep -v "^NAMESPACE"
# ✅ Çıktı boş olmalı (tüm pod'lar Running/Completed)

# App pod dağılımı (worker1 + worker2)
kubectl get pods -n app -o wide
# ✅ 4 pod: 2 worker1'de, 2 worker2'de

# HPA durumu
kubectl describe hpa query-param-app -n app
# ✅ Replicas: 4, Conditions: ScalingActive=True

# PDB durumu
kubectl get pdb -n app
# ✅ DISRUPTIONS ALLOWED: 1

# Kaynak kullanımı
kubectl top nodes
kubectl top pods -n app --sort-by=cpu

# Uygulama endpoint testi
curl 'http://app.example.com/api/echo?hello=world'
# ✅ {"hello":"world"}

# requestId header testi
curl -v http://app.example.com/api/echo 2>&1 | grep -i x-request-id
# ✅ X-Request-Id: (12 karakter hex)

# Prometheus sağlık kontrolü
curl http://monitoring.example.com/prometheus/-/healthy
# ✅ Prometheus is Healthy.

# Webhook metrikleri
kubectl port-forward svc/resource-webhook 8080:8080 -n webhook-system &
curl http://localhost:8080/metrics | grep webhook_
# Ctrl+C ile port-forward'u durdur
kill %1
```

---

### Adım 41: Temizlik

⚠️ `vagrant destroy -f` geri **alınamaz** — tüm VM verileri kalıcı olarak silinir.

```bash
# Tüm VM'leri sil
vagrant destroy -f

# kubeconfig'i sil
rm ~/.kube/config-dreamgames

# KUBECONFIG ortam değişkenini temizle
unset KUBECONFIG

# macOS'ta /etc/hosts temizleme
# ⚠️ macOS'ta sed -i için '' (boş string) gereklidir — Linux'taki -i'dan farklı
sudo sed -i '' '/example\.com/d' /etc/hosts

# Vagrant box'ını da kaldırmak istiyorsanız (disk alanı için):
vagrant box remove bento/ubuntu-22.04
```

---

## Referanslar — Tüm Resmi Linkler

### Araçlar

| Araç | Resmi Kaynak |
|------|-------------|
| Vagrant | https://developer.hashicorp.com/vagrant/docs |
| VirtualBox | https://www.virtualbox.org/manual/ |
| Ansible | https://docs.ansible.com/ansible/latest/ |
| kubectl | https://kubernetes.io/docs/reference/kubectl/ |
| Helm | https://helm.sh/docs/ |
| kubeadm | https://kubernetes.io/docs/reference/setup-tools/kubeadm/ |

### Kubernetes Kavramları

| Kavram | Resmi Kaynak |
|--------|-------------|
| Deployment | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| Service | https://kubernetes.io/docs/concepts/services-networking/service/ |
| Ingress | https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| PDB | https://kubernetes.io/docs/tasks/run-application/configure-pdb/ |
| NetworkPolicy | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| Pod Security Admission | https://kubernetes.io/docs/concepts/security/pod-security-admission/ |
| ServiceAccount | https://kubernetes.io/docs/concepts/security/service-accounts/ |
| PriorityClass | https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/ |
| TopologySpreadConstraints | https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/ |
| Admission Webhooks | https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/ |

### Uygulama ve CI/CD

| Bileşen | Resmi Kaynak |
|---------|-------------|
| Spring Boot 3.2 | https://docs.spring.io/spring-boot/docs/3.2.1/reference/html/ |
| Spring Actuator | https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html |
| Micrometer Prometheus | https://micrometer.io/docs/registry/prometheus |
| Logstash Logback Encoder | https://github.com/logfellow/logstash-logback-encoder |
| Logback MDC | https://logback.qos.ch/manual/mdc.html |
| Docker multi-stage builds | https://docs.docker.com/build/building/multi-stage/ |
| eclipse-temurin | https://hub.docker.com/_/eclipse-temurin |
| Jenkins Pipeline | https://www.jenkins.io/doc/book/pipeline/ |
| JCasC | https://www.jenkins.io/projects/jcasc/ |
| Aqua Trivy | https://aquasecurity.github.io/trivy/latest/docs/ |

### Monitoring ve Observability

| Bileşen | Resmi Kaynak |
|---------|-------------|
| Prometheus Operator | https://prometheus-operator.dev/ |
| kube-prometheus-stack | https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack |
| PromQL | https://prometheus.io/docs/prometheus/latest/querying/basics/ |
| Grafana | https://grafana.com/docs/grafana/latest/ |
| ECK (Elastic on K8s) | https://www.elastic.co/guide/en/cloud-on-k8s/current/ |
| Fluent Bit | https://docs.fluentbit.io/manual/ |
| Slack Webhooks | https://api.slack.com/messaging/webhooks |

### İleri Senaryolar

| Bileşen | Resmi Kaynak |
|---------|-------------|
| KEDA | https://keda.sh/docs/latest/ |
| KEDA CronScaler | https://keda.sh/docs/latest/scalers/cron/ |
| MetalLB | https://metallb.universe.tf/ |
| ExternalDNS | https://github.com/kubernetes-sigs/external-dns |
| Ingress-NGINX Canary | https://kubernetes.github.io/ingress-nginx/examples/canary/ |

---

*Bu rehber, `clean/devops-case-study` branch'indeki tüm implementasyonu referans alır.*  
*Sorularınız için repo'nun GitHub sayfasından issue açabilirsiniz.*
