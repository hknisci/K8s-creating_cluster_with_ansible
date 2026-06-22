# Dream Games DevOps Case Study — Sıfırdan Çözüm Rehberi

> **Hedef kitle:** 5-6 yıllık DevOps deneyimi. Bu rehber case study PDF'inin **birebir sırasını**
> izler: Prerequisites → Step 1 (madde 1–7) → Step 2 (madde 1–4) → Step 3 (madde 1–4) →
> Step 4 (madde 1–3). Her bölümde **"Case study ne istiyor?"** → **"Neden böyle yaptık?"** →
> **"Nasıl yapılır?"** akışı vardır.
>
> **MacBook Air M4 (Apple Silicon) uyumludur.** VirtualBox M-serisi Mac'te çalışmaz.
> Bu rehber **Multipass** (gerçek hafif VM + Apple Virtualization framework) + **Ansible** +
> **kubeadm** kullanır — case study'nin beklediği production-grade yaklaşım, M4 uyumlu gerçek VM'lerle.
>
> ⚠️ **Güvenlik:** Şifre, token, Slack webhook, cloud credential **asla** dosyaya yazılmaz.
> Tüm secret'lar `kubectl create secret` veya environment variable ile yönetilir.
>
> ⚠️ **k3d/k3s/kind/minikube YASAK:** Case study açıkça *"Avoid tools like kind, minikube, or k3s"*
> diyor. k3d = K3s in Docker → elenme sebebi. Bu rehber **kubeadm** kullanır.
>
> ⚠️ **Kaynak modeli (2.9GB toplam):** master 1.5GB + worker1 700MB + worker2 700MB.
> Tüm stack 2.9GB'a aynı anda sığmaz → **faz faz** ilerlenir (bkz. [Kaynak Stratejisi](#kaynak-stratejisi-faz-faz-kurulum)).

---

## İçindekiler

- [Hazırlık: Gereksinimler, Araçlar ve Ortam](#hazırlık-gereksinimler-araçlar-ve-ortam)
- [Step 1: Uygulama, Cluster ve Platform Kurulumu](#step-1-uygulama-cluster-ve-platform-kurulumu)
  - [Step 1.1: Java Uygulaması](#step-11-java-uygulaması)
  - [Step 1.2: Dockerfile (Multi-stage)](#step-12-dockerfile-multi-stage)
  - [Step 1.3: Production Kubernetes Cluster](#step-13-production-kubernetes-cluster)
  - [Step 1.4: ExternalDNS](#step-14-externaldns)
  - [Step 1.5: Jenkins](#step-15-jenkins)
  - [Step 1.6: Monitoring Stack](#step-16-monitoring-stack)
  - [Step 1.7: Asenkron Dosya Logging](#step-17-asenkron-dosya-logging)
- [Step 2: Deployment ve Pipeline'lar](#step-2-deployment-ve-pipelinelar)
  - [Step 2.1: Uygulamayı Kubernetes'e Deploy Et](#step-21-uygulamayı-kubernetese-deploy-et)
  - [Step 2.2: Build Pipeline](#step-22-build-pipeline)
  - [Step 2.3: Deploy Pipeline (Ansible)](#step-23-deploy-pipeline-ansible)
  - [Step 2.4: Validation Webhook](#step-24-validation-webhook)
- [Step 3: Kaynak ve Ölçekleme Senaryoları](#step-3-kaynak-ve-ölçekleme-senaryoları)
  - [Step 3.1: App X / App Y Kaynak Yönetimi](#step-31-app-x--app-y-kaynak-yönetimi)
  - [Step 3.2: Zamanlı Ölçekleme + Node Scaling](#step-32-zamanlı-ölçekleme--node-scaling)
  - [Step 3.3: Kritik Uygulama Deployment Stratejisi](#step-33-kritik-uygulama-deployment-stratejisi)
  - [Step 3.4: Replica Veritabanı Ölçekleme](#step-34-replica-veritabanı-ölçekleme)
- [Step 4: Tasarım Soruları](#step-4-tasarım-soruları)
- [Doğrulama ve Temizlik](#doğrulama-ve-temizlik)
- [Kapsam Özeti](#kapsam-özeti)
- [Referanslar](#referanslar)

---

## Hazırlık: Gereksinimler, Araçlar ve Ortam

### Case Study Ne İstiyor? (Prerequisites)

> *"Vagrant, VirtualBox, Vagrant Cloud Account, DockerHub for Image Registry, Github for SCM.
> You can create 1 Master (Node 1), and 2 Worker Nodes (Node 2, Node 3) via Vagrantfile."*

Case study Vagrant + VirtualBox öneriyor. **VirtualBox Apple Silicon'da çalışmaz**, bu yüzden
M4 Mac'te eşdeğer bir çözüme geçiyoruz: **Multipass** ile 3 gerçek Ubuntu VM (1 master + 2 worker).
Mantık aynı — sadece VM sağlayıcı M4 uyumlusuyla değişti. Geriye kalan her şey (Ansible, kubeadm,
DockerHub, GitHub) case study'deki gibi.

**Neden Multipass, OrbStack/Vagrant değil?**

| Seçenek | M4 uyumu | kubeadm | Per-VM memory | Karar |
|---------|----------|---------|---------------|-------|
| VirtualBox + Vagrant | ❌ M-serisinde yok | — | — | Elenir |
| OrbStack Machines | ✅ | ⚠️ Container tabanlı, nested containerd sorunlu | Paylaşımlı | Uygun değil |
| **Multipass** | ✅ Apple Virtualization | ✅ Gerçek VM, sorunsuz | ✅ `--memory 1.5G` | **Seçildi** |
| Lima | ✅ | ✅ | ✅ (YAML) | Alternatif |

Multipass gerçek hafif VM'ler üretir (container değil) → kubeadm + containerd + kubelet
sorunsuz çalışır. Apple Virtualization framework kullandığı için M4-native ve hafiftir.

### Gerekli Araçlar

```bash
# Homebrew (paket yöneticisi)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Multipass (M4-native gerçek VM)
brew install --cask multipass

# K8s ve otomasyon araçları
brew install kubectl helm ansible

# Java + Maven (uygulama için)
brew install --cask temurin@21    # OpenJDK 21
brew install maven

# İsteğe bağlı: Go (webhook için), k9s (terminal K8s UI)
brew install go k9s
```

> ⚠️ **16GB Mac'te Docker Desktop KURMA / ÇALIŞTIRMA.** Apple Silicon'da Docker Desktop kendi
> Linux VM'ini çalıştırır ve arka planda **2-4GB RAM** tutar — bizim 2.9GB'lık Multipass cluster'ımızla
> birlikte makineyi boğar. Bu rehberde Docker Desktop'a **hiç ihtiyaç yok**: container imajları ya
> **master VM'inde containerd/nerdctl** ile ya da **cluster içinde Jenkins** ile build edilir. Eğer
> kuruluysa kapat: `osascript -e 'quit app "Docker Desktop"'; pkill -9 -f com.docker`

Versiyon kontrolü:
```bash
multipass version          # 1.13+
kubectl version --client   # v1.28+ (biz 1.32)
helm version               # v3.14+
ansible --version          # 2.15+
java -version              # 21+
mvn -version               # 3.9+
```

📖 Multipass: https://multipass.run/docs
📖 kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/
📖 Ansible: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html

### Kaynak Stratejisi (Faz Faz Kurulum)

⚠️ **2.9GB toplam RAM ile tüm stack aynı anda çalışmaz.** Worker'ların toplam kapasitesi
2 × 700MB = 1.4GB; bunun ~500MB'ı OS + kubelet + containerd + Calico + kube-proxy'ye gider.
Geriye ~900MB workload kapasitesi kalır. Jenkins (~700MB) + Elasticsearch (~700MB) +
Prometheus (~400MB) + 4 app pod (~512MB) toplamı bu bütçeyi kat kat aşar.

**Çözüm — faz faz ilerle:** Her bileşeni kur → çalıştığını **doğrula ve screenshot al** →
bir sonrakine geçmeden RAM'i boşalt. Böylece case study'nin **her** gereksinimini kanıtlarsın,
hepsini aynı anda ayakta tutmadan. Bu aynı zamanda DevOps olgunluğu gösterir (kaynak farkındalığı).

| Faz | Bileşen | ~RAM | Faz sonunda |
|-----|---------|------|-------------|
| 1 | Cluster + Calico + MetalLB + Ingress + metrics-server | sistem | **Kalır** (temel altyapı) |
| 2 | Uygulama (4 pod) | ~512MB | **Kalır** (çekirdek demo) |
| 3 | ExternalDNS | ~50MB | Kalır (hafif) |
| 4 | Jenkins + build/deploy pipeline | ~700MB | Doğrula → `helm uninstall jenkins` |
| 5 | Monitoring (Prometheus+Grafana+AlertManager) | ~600MB | Doğrula → gerekirse uninstall |
| 6 | Elasticsearch + fluent-bit | ~700MB | Doğrula → `kubectl delete elasticsearch` |
| 7 | Webhook (2 pod) | ~80MB | Kalır (hafif) |
| 8 | Step 3 manifest'leri | geçici | Doğrula → sil |

> 💡 Ağır faz (Jenkins/Monitoring/ES) çalışırken uygulamayı geçici küçült:
> `kubectl scale deployment query-param-app --replicas=1 -n app`
> Faz bitince geri büyüt: `kubectl scale deployment query-param-app --replicas=4 -n app`

### VM'leri Oluştur (master 1.5GB + 2× worker 700MB)

> ⚠️ **Host RAM'ini önce boşalt (16GB Mac için kritik).** En büyük gizli tüketici **Docker Desktop**:
> Apple Silicon'da kendi Linux VM'ini çalıştırır ve 2-4GB tutar — bu rehberde **gerek yok**, kapat:
> ```bash
> osascript -e 'quit app "Docker Desktop"' 2>/dev/null; pkill -9 -f com.docker 2>/dev/null
> ```
> Ayrıca Chrome/Slack/IDE gibi ağır uygulamaları kapat → toplam ~4-6GB boşalır. Multipass VM'leri
> (2.9GB) bundan sonra rahatça sığar. RAM'i ölçmek için: `vm_stat`.

**SSH anahtarı hazırla** (Ansible bağlantısı için):
```bash
# Yoksa oluştur
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

# Public key'i cloud-init dosyasına göm
cat > /tmp/cloud-init.yaml << EOF
ssh_authorized_keys:
  - $(cat ~/.ssh/id_ed25519.pub)
EOF
```

**VM'leri başlat** — memory değerleri tam istenildiği gibi:
```bash
# master: kubeadm control-plane → 2 vCPU şart, RAM 1.5G (resmi min 1700MB altında, bkz. not)
multipass launch 22.04 --name master  --cpus 2 --memory 1.5G --disk 12G --cloud-init /tmp/cloud-init.yaml

# worker'lar: kontrol-plane bileşeni yok → 700MB + 1 vCPU yeterli
multipass launch 22.04 --name worker1 --cpus 1 --memory 700M --disk 8G  --cloud-init /tmp/cloud-init.yaml
multipass launch 22.04 --name worker2 --cpus 1 --memory 700M --disk 8G  --cloud-init /tmp/cloud-init.yaml

# Toplam ek RAM: 1.5 + 0.7 + 0.7 = 2.9GB
```

> ⚠️ **master 1.5GB notu:** kubeadm resmi minimumu 1700MB'dir. 1.5GB ile preflight check
> hata verir → `--ignore-preflight-errors=Mem` ile bypass ediyoruz (Step 1.3 master role'ünde
> hazır). Control plane idle'da ~1.2GB kullanır; 1.5GB demo için yeterli ama dardır. Master
> kararsızsa (apiserver restart / NotReady) RAM'i yükselt:
> `multipass stop master && multipass set local.master.memory=1700M && multipass start master`

IP'leri al:
```bash
multipass list
# NAME      STATE     IPv4             IMAGE
# master    Running   192.168.252.2    Ubuntu 22.04 LTS
# worker1   Running   192.168.252.3    Ubuntu 22.04 LTS
# worker2   Running   192.168.252.4    Ubuntu 22.04 LTS
# ⚠️ IP'ler makineden makineye değişir — yukarıdaki senin GERÇEK IP'lerini göster!

# SSH testi (cloud-init key ile) — KENDİ IP'LERİNİ YAZ:
MASTER_IP=$(multipass info master | grep IPv4 | awk '{print $2}')
ssh ubuntu@$MASTER_IP "hostname && uname -m"   # → master, aarch64
```

📖 Multipass launch: https://multipass.run/docs/launch-command

### Kendi Repo'nu Oluştur

```bash
mkdir dreamgames-case && cd dreamgames-case
git init && git branch -M main

mkdir -p app/src/main/{java/com/dreamgames/{controller,filter},resources}
mkdir -p ansible/roles/{common,containerd,kubeadm,master,worker}/{tasks,templates,handlers}
mkdir -p ansible/{group_vars,inventory}
mkdir -p kubernetes/{namespaces,app,jenkins,webhook/tls,metallb,ingress-nginx,externaldns}
mkdir -p kubernetes/monitoring/{grafana-dashboards,elasticsearch,fluent-bit}
mkdir -p jenkins step3-manifests docs/design-answers webhook

cat > .gitignore << 'EOF'
target/
*.jar
*.class
.DS_Store
*.env
*.key
*.crt
*.pem
kubeconfig
vendor/
EOF
```

Dizin yapısı (case study mantığına göre):
```
dreamgames-case/
├── app/                # Step 1.1, 1.2, 1.7 — Spring Boot uygulaması + Dockerfile + logback
├── ansible/            # Step 1.3 — cluster kurulum; Step 2.3 — deploy playbook
├── kubernetes/         # Tüm K8s manifest'leri (GitOps yaklaşımı)
│   ├── app/            # Step 2.1 — Deployment, Service, Ingress, HPA, PDB, NetworkPolicy
│   ├── externaldns/    # Step 1.4
│   ├── jenkins/        # Step 1.5 — PV, Helm values (Node 3 pin'li)
│   ├── monitoring/     # Step 1.6 — kube-prometheus-stack + ES + fluent-bit + alert + dashboard
│   └── webhook/        # Step 2.4 — admission webhook kaynakları
├── jenkins/            # Step 2.2, 2.3 — Jenkinsfile.build, Jenkinsfile.deploy (Ansible çağırır)
├── step3-manifests/    # Step 3 — KEDA, Canary, PriorityClass
└── docs/design-answers/# Step 3-4 tasarım soruları yazılı yanıtlar
```

```bash
echo "# Dream Games DevOps Case Study" > README.md
git add . && git commit -m "chore: initial project structure"
git remote add origin https://github.com/<kullanici>/dreamgames-case.git
git push -u origin main
```

---

## Step 1: Uygulama, Cluster ve Platform Kurulumu

### Step 1.1: Java Uygulaması

#### Case Study Ne İstiyor?

> *"You can either use an existing Java project, such as sample-java-app, or develop a new
> Java application from scratch that prints the query string parameters of the service
> endpoint to the console."*

Sıfırdan bir Spring Boot uygulaması yazıyoruz: `/api/echo?param=value` çağrıldığında query
string parametrelerini **console'a yazar** ve JSON döner.

#### Nasıl Yapılır?

`app/pom.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.2.1</version>
  </parent>
  <groupId>com.dreamgames</groupId>
  <artifactId>query-param-app</artifactId>
  <version>1.0.0</version>
  <properties>
    <java.version>21</java.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>
    <dependency>
      <groupId>io.micrometer</groupId>
      <artifactId>micrometer-registry-prometheus</artifactId>
    </dependency>
    <dependency>
      <groupId>net.logstash.logback</groupId>
      <artifactId>logstash-logback-encoder</artifactId>
      <version>7.4</version>
    </dependency>
  </dependencies>
  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>
</project>
```

`app/src/main/java/com/dreamgames/QueryParamApplication.java`:
```java
package com.dreamgames;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class QueryParamApplication {
    public static void main(String[] args) {
        SpringApplication.run(QueryParamApplication.class, args);
    }
}
```

`app/src/main/java/com/dreamgames/controller/QueryParamController.java`:
```java
package com.dreamgames.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class QueryParamController {

    private static final Logger log = LoggerFactory.getLogger(QueryParamController.class);

    @GetMapping("/echo")
    public Map<String, String> echo(@RequestParam Map<String, String> params) {
        // Case study: "prints the query string parameters to the console"
        log.info("Query params: {}", params);
        System.out.println("Query params: " + params);
        return params;
    }
}
```

`app/src/main/resources/application.yml`:
```yaml
server:
  port: 8080

# Management port ayrı — güvenlik best practice
# Port 8080: uygulama trafiği (dışa açık, Ingress üzerinden)
# Port 9090: operasyonel endpoint'ler (sadece cluster içi, Prometheus scrape)
management:
  server:
    port: 9090
  endpoints:
    web:
      exposure:
        include: health,prometheus,info
  endpoint:
    health:
      probes:
        enabled: true          # /actuator/health/readiness ve /liveness aktif
      show-details: when-authorized

spring:
  application:
    name: query-param-app
```

> ℹ️ Logback dosya logging (async, 1GB, daily rotation) **Step 1.7'de** ekleniyor — case study
> bu gereksinimi 7. maddede istiyor, biz de oraya bıraktık. Şimdilik default stdout logging yeterli.

📖 Spring Boot Actuator: https://docs.spring.io/spring-boot/docs/3.2.1/reference/html/actuator.html
📖 Micrometer Prometheus: https://docs.micrometer.io/micrometer/reference/implementations/prometheus.html

---

### Step 1.2: Dockerfile (Multi-stage)

#### Case Study Ne İstiyor?

> *"Create a Dockerfile for the application using multi-stage builds.*
> *a. Provide strategies for accelerating the application build process.*
> *b. The image size for the container should be as compact as possible.*
> *c. Consider security best practices while creating a Dockerfile."*

#### Nasıl Yapılır?

`app/Dockerfile`:
```dockerfile
# Stage 1: Bağımlılıkları önbelleğe al (build acceleration — case study 2a)
# Sadece pom.xml kopyalanır → bağımlılıklar değişmedikçe bu katman cache'den gelir
FROM maven:3.9-eclipse-temurin-21-alpine AS deps
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q

# Stage 2: JAR derle
FROM deps AS builder
COPY src/ ./src/
RUN mvn clean package -DskipTests -q

# Stage 3: Minimal runtime (compact image — case study 2b)
# JRE-only Alpine: JDK yok, compiler yok, Maven yok → küçük imaj (~200MB)
FROM eclipse-temurin:21-jre-alpine AS runtime

# Non-root user (security — case study 2c)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
RUN mkdir -p /app/logs && chown -R appuser:appgroup /app
USER appuser

COPY --from=builder /app/target/*.jar app.jar

EXPOSE 8080 9090

# MaxRAMPercentage=60: 256Mi limit → ~150Mi heap (dar M4 ortamı için headroom bırakır)
# java.security.egd: daha hızlı JVM başlangıcı
ENTRYPOINT ["java", \
  "-XX:MaxRAMPercentage=60.0", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-jar", "app.jar"]
```

**Üç gereksinim nasıl karşılandı?**
- **2a (build acceleration):** `deps` katmanı sadece `pom.xml`'e bağlı → kod değişince bağımlılıklar
  yeniden indirilmez, cache'den gelir. Ayrıca BuildKit cache mount (`--mount=type=cache`) ve
  registry layer cache ile CI'da daha da hızlanır.
- **2b (compact):** Multi-stage → final imajda sadece JRE + JAR. JDK/Maven build katmanlarında kalır.
- **2c (security):** non-root user, minimal Alpine base (az CVE yüzeyi), sadece gerekli portlar.
  Step 2.2'de Trivy ile imaj taranır.

#### Local Build ve Test (Docker Desktop'sız — RAM dostu)

> ⚠️ **16GB Mac'te Docker Desktop kullanma.** Bunun yerine:
> 1. JAR'ı local'de Maven ile build et + JAR'ı doğrudan `java -jar` ile test et (container yok),
> 2. Container imajını **master VM'inin containerd'sinde nerdctl** ile build et — imaj doğrudan
>    cluster'ın `k8s.io` namespace'ine girer, registry'ye push gerekmez (`imagePullPolicy: IfNotPresent`).

**(a) JAR'ı local'de build et ve test et (Docker yok):**
```bash
cd app
mvn clean package -DskipTests          # JAR üret (sadece Java+Maven, RAM ~300MB)

# JAR'ı doğrudan çalıştır — container yok, Docker yok
java -jar target/*.jar &
APP_PID=$!

curl 'http://localhost:8080/api/echo?hello=world&foo=bar'   # → {"hello":"world","foo":"bar"}
curl 'http://localhost:9090/actuator/health'                # → {"status":"UP"}
curl 'http://localhost:9090/actuator/prometheus' | grep echo
kill $APP_PID                          # testi bitince kapat (RAM'i geri al)
cd ..
```

**(b) Container imajını master VM'inde build et (nerdctl, registry'siz):**
```bash
# Build context'i master VM'ine kopyala
multipass transfer -r app master:/home/ubuntu/app

# master'da nerdctl ile build → doğrudan k8s.io namespace'ine yaz
multipass exec master -- sudo nerdctl --namespace k8s.io build \
  -t dreamgames/query-param-app:1.0.0 /home/ubuntu/app

# Doğrula — imaj cluster'da hazır
multipass exec master -- sudo nerdctl --namespace k8s.io images | grep query-param-app
```
> nerdctl, kubeadm rolünde containerd ile birlikte kurulur (aşağıda Step 1.3). `k8s.io` namespace'ine
> yazılan imaj, pod'lar tarafından çekme (pull) gerekmeden kullanılabilir.

> **Alternatif — DockerHub'a push (case study "DockerHub for Image Registry" gereksinimi):** Bu, asıl
> CI akışında **Jenkins build pipeline** (Step 2.2) tarafından cluster içinde yapılır — local Docker'a
> gerek yok. Manuel push gerekirse master VM'inden: `multipass exec master -- sudo nerdctl --namespace
> k8s.io push dreamgames/query-param-app:1.0.0` (önce `nerdctl login`).

📖 Multi-stage builds: https://docs.docker.com/build/building/multi-stage/
📖 nerdctl: https://github.com/containerd/nerdctl
📖 eclipse-temurin: https://hub.docker.com/_/eclipse-temurin

---

### Step 1.3: Production Kubernetes Cluster

#### Case Study Ne İstiyor?

> *"Set up a production-ready Kubernetes cluster using tools like Kubeadm, Kubespray, or similar.*
> *Note: Avoid using tools like kind, minikube, or k3s.*
> *a. Ensure the Kubernetes version is 1.28 or higher.*
> *b. Use custom subnets of your choice for Pod and Service.*
> *c. Implementing the steps using the GitOps paradigm where applicable is highly desirable."*

#### Neden kubeadm? Neden k3s/k3d yasak?

k3s/k3d geliştirme ortamıdır; birçok K8s bileşeni sadeleştirilmiştir. kubeadm gerçek production
kurulumudur — tüm bileşenler (etcd, apiserver, controller-manager, scheduler) ayrı ayrı, gerçek
gibi. Değerlendirici "bu kişi gerçek cluster kurabiliyor mu?" sorusuna bakıyor.

> 🗂 **GitOps (1.3c):** Tüm manifest'ler Git'te. Değişiklik → `git push` → Ansible/Jenkins deploy
> eder. Bu rehber manifest'leri Git'te tutarak GitOps temelini kurar; ArgoCD/Flux eklenirse tam
> GitOps olur (case study "highly desirable" demiş, zorunlu değil).

#### Ansible Inventory ve Değişkenler

`ansible/inventory/hosts.ini` — IP'leri `multipass list` ile al, dosyayı düzenle:
```bash
# Gerçek IP'leri öğren
multipass list
# master    Running   192.168.252.2    ...
# worker1   Running   192.168.252.3    ...
# worker2   Running   192.168.252.4    ...
```

```ini
[master]
master  ansible_host=192.168.252.2  ansible_user=ubuntu  ansible_ssh_private_key_file=~/.ssh/id_ed25519

[workers]
worker1 ansible_host=192.168.252.3  ansible_user=ubuntu  ansible_ssh_private_key_file=~/.ssh/id_ed25519
worker2 ansible_host=192.168.252.4  ansible_user=ubuntu  ansible_ssh_private_key_file=~/.ssh/id_ed25519

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```
> ⚠️ **ÖNEMLİ:** Yukarıdaki `192.168.252.x` örnektir. `multipass list` çıktında gördüğün gerçek IP'leri kullan. Farklı bir subnet atanmış olabilir (örn. `192.168.64.x`).

`ansible/group_vars/all.yml`:
```yaml
kubernetes_version: "1.32.0"
calico_version: "v3.29.1"

# Case study 1.3b: custom subnets (default'lardan farklı seçildi)
pod_cidr: "10.244.0.0/16"      # Pod-to-pod ağı
service_cidr: "10.96.0.0/12"   # ClusterIP Service IP havuzu

api_server_address: "192.168.252.2"   # master VM IP'si
```

**Neden custom subnet?** Case study özellikle istiyor. Default'u değiştirmek "cluster ağını
anlıyorum" mesajı verir. Calico bu CIDR'ları bilmeli ki doğru route'ları programlasın.

#### Ansible Rolleri

`ansible/site.yml`:
```yaml
---
- name: Common + containerd (tüm node'lar)
  hosts: all
  become: true
  roles: [common, containerd]

- name: kubeadm paketleri (tüm node'lar)
  hosts: all
  become: true
  roles: [kubeadm]

- name: Master init
  hosts: master
  become: true
  roles: [master]

- name: Worker join
  hosts: workers
  become: true
  roles: [worker]
```

`ansible/roles/common/tasks/main.yml`:
```yaml
---
- name: Swap kapat (kubeadm gereksinimi)
  command: swapoff -a

- name: Swap kalıcı kapat
  replace:
    path: /etc/fstab
    regexp: '^([^#].*?\sswap\s+sw\s+.*)$'
    replace: '# \1'

- name: Kernel modülleri (containerd için)
  modprobe:
    name: "{{ item }}"
  loop: [overlay, br_netfilter]

- name: Modülleri kalıcı yap
  copy:
    dest: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

- name: Sysctl (K8s networking)
  sysctl:
    name: "{{ item.key }}"
    value: "{{ item.value }}"
    sysctl_set: true
    state: present
    reload: true
  loop:
    - { key: "net.bridge.bridge-nf-call-iptables",  value: "1" }
    - { key: "net.bridge.bridge-nf-call-ip6tables", value: "1" }
    - { key: "net.ipv4.ip_forward",                 value: "1" }
```

`ansible/roles/containerd/tasks/main.yml`:
```yaml
---
- name: containerd kur
  apt:
    name: containerd
    state: present
    update_cache: true

- name: Config dizini
  file:
    path: /etc/containerd
    state: directory

- name: Default config
  shell: containerd config default > /etc/containerd/config.toml

- name: SystemdCgroup aktif (kubeadm gereksinimi)
  replace:
    path: /etc/containerd/config.toml
    regexp: 'SystemdCgroup = false'
    replace: 'SystemdCgroup = true'
  notify: restart containerd

- name: containerd başlat
  systemd:
    name: containerd
    enabled: true
    state: started
```

`ansible/roles/containerd/handlers/main.yml`:
```yaml
---
- name: restart containerd
  systemd:
    name: containerd
    state: restarted
```

`ansible/roles/kubeadm/tasks/main.yml`:
```yaml
---
- name: Kubernetes apt key
  apt_key:
    url: https://pkgs.k8s.io/core:/stable:/v{{ kubernetes_version }}/deb/Release.key
    state: present

- name: Kubernetes repo
  apt_repository:
    repo: "deb https://pkgs.k8s.io/core:/stable:/v{{ kubernetes_version }}/deb/ /"
    state: present

- name: kubeadm/kubelet/kubectl kur
  apt:
    name: [kubeadm, kubelet, kubectl]
    state: present
    update_cache: true

- name: Paketleri hold et (otomatik upgrade engelle)
  dpkg_selections:
    name: "{{ item }}"
    selection: hold
  loop: [kubeadm, kubelet, kubectl]
```

`ansible/roles/master/tasks/main.yml`:
```yaml
---
- name: kubeadm config oluştur
  template:
    src: kubeadm-config.yaml.j2
    dest: /tmp/kubeadm-config.yaml

- name: Cluster zaten init edilmiş mi?
  stat:
    path: /etc/kubernetes/admin.conf
  register: kubeconfig_exists

# --ignore-preflight-errors=Mem: master 1.5GB < resmi min 1700MB → preflight bypass
- name: kubeadm init
  command: >
    kubeadm init --config=/tmp/kubeadm-config.yaml --upload-certs
    --ignore-preflight-errors=Mem
  when: not kubeconfig_exists.stat.exists
  register: kubeadm_output

- name: .kube dizini
  file:
    path: "{{ ansible_env.HOME }}/.kube"
    state: directory

- name: admin.conf kopyala
  copy:
    src: /etc/kubernetes/admin.conf
    dest: "{{ ansible_env.HOME }}/.kube/config"
    remote_src: true
    owner: "{{ ansible_user_id }}"
    mode: '0600'

- name: Calico CNI kur
  command: kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/{{ calico_version }}/manifests/calico.yaml
  environment:
    KUBECONFIG: "{{ ansible_env.HOME }}/.kube/config"
  when: not kubeconfig_exists.stat.exists

- name: Join command al
  command: kubeadm token create --print-join-command
  register: join_command
  changed_when: false

# Join command'a Mem bypass ekle (worker'lar 700MB) → dosyaya yaz
- name: Join command'ı dosyaya yaz
  copy:
    content: "{{ join_command.stdout }} --ignore-preflight-errors=Mem"
    dest: /tmp/join-command.sh
    mode: '0755'
```

`ansible/roles/master/templates/kubeadm-config.yaml.j2`:
```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "v{{ kubernetes_version }}.0"
controlPlaneEndpoint: "{{ api_server_endpoint }}"
networking:
  podSubnet: "{{ pod_cidr }}"        # Custom subnet — case study 1.3b
  serviceSubnet: "{{ service_cidr }}"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd                 # containerd SystemdCgroup ile eşleşmeli
```

`ansible/roles/worker/tasks/main.yml`:
```yaml
---
- name: Join command'ı master'dan çek
  fetch:
    src: /tmp/join-command.sh
    dest: /tmp/join-command.sh
    flat: true
  delegate_to: "{{ groups['master'][0] }}"

- name: Cluster'a worker olarak katıl
  command: bash /tmp/join-command.sh
  args:
    creates: /etc/kubernetes/kubelet.conf
```

#### Cluster'ı Kur (Faz 1 başlar)

```bash
# Bağlantı testi
ansible all -i ansible/inventory/hosts.ini -m ping

# Cluster kur (~10-15 dk)
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml -v

# kubeconfig'i yerele kopyala (MASTER_IP = multipass info master | grep IPv4)
MASTER_IP=$(multipass info master | grep IPv4 | awk '{print $2}')
ssh ubuntu@$MASTER_IP "cat ~/.kube/config" > ~/.kube/config-dreamgames
export KUBECONFIG=~/.kube/config-dreamgames
echo "export KUBECONFIG=~/.kube/config-dreamgames" >> ~/.zshrc

kubectl get nodes -o wide
```
Beklenen:
```
NAME      STATUS   ROLES           AGE   VERSION
master    Ready    control-plane   5m    v1.32.x
worker1   Ready    <none>          3m    v1.32.x
worker2   Ready    <none>          3m    v1.32.x
```

#### Metrics Server (HPA için)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Self-signed kubelet sertifikası için (lab ortamı):
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
sleep 30 && kubectl top nodes
```

#### Production Katmanı: MetalLB (Bare-metal LoadBalancer)

Bare-metal cluster'da `LoadBalancer` tipi Service IP alamaz. MetalLB bunu çözer — Jenkins (1.5d),
monitoring ve uygulama Ingress'i için gerekli. Bu yüzden "production-ready cluster"ın parçası.

`kubernetes/metallb/ipaddresspool.yaml`:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: local-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.252.200-192.168.252.220   # Multipass subnet aralığında boş IP'ler
    # ⚠️ Subnet'in seni bildir: multipass list → master IP'nin ilk 3 oktetini kullan
    # Örn. master 192.168.64.2 ise → 192.168.64.200-192.168.64.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: local-l2
  namespace: metallb-system
spec:
  ipAddressPools: [local-pool]
```
> IP aralığını `multipass list` subnet'ine göre ayarla (örn. `192.168.252.x` veya `192.168.64.x`).

```bash
helm repo add metallb https://metallb.github.io/metallb && helm repo update
helm install metallb metallb/metallb -n metallb-system --create-namespace --wait --timeout 3m
kubectl apply -f kubernetes/metallb/ipaddresspool.yaml
```

#### Production Katmanı: Ingress-NGINX

`kubernetes/ingress-nginx/values.yaml`:
```yaml
controller:
  service:
    type: LoadBalancer
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
  config:
    use-forwarded-headers: "true"
  resources:
    requests: { cpu: 100m, memory: 128Mi }
```

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f kubernetes/ingress-nginx/values.yaml --wait --timeout 3m

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"

# /etc/hosts'a ekle (case study: hostname erişimi)
echo "$INGRESS_IP  app.example.com monitoring.example.com jenkins.example.com" | sudo tee -a /etc/hosts
```

📖 kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
📖 Calico: https://docs.tigera.io/calico/latest/
📖 MetalLB: https://metallb.universe.tf/
📖 Ingress-NGINX: https://kubernetes.github.io/ingress-nginx/

---

### Step 1.4: ExternalDNS

#### Case Study Ne İstiyor?

> *"Deploy ExternalDNS on the cluster.*
> *a. Share your configuration.*
> *b. Ensure that the DNS name is automatically created for the newly created service objects.
>    Please share your Kubernetes manifest files."*

#### Nasıl Yapılır?

`kubernetes/externaldns/rbac.yaml`:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
  - apiGroups: [""]
    resources: ["services", "endpoints", "pods"]
    verbs: ["get", "watch", "list"]
  - apiGroups: ["extensions", "networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
  - kind: ServiceAccount
    name: external-dns
    namespace: kube-system
```

`kubernetes/externaldns/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: kube-system
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels: { app: external-dns }
  template:
    metadata:
      labels: { app: external-dns }
    spec:
      serviceAccountName: external-dns
      containers:
        - name: external-dns
          image: registry.k8s.io/external-dns/external-dns:v0.14.0
          args:
            - --source=service          # Service objelerini izle (1.4b)
            - --source=ingress          # Ingress objelerini izle
            - --provider=coredns        # Local cluster: cluster-internal CoreDNS
            - --registry=txt
            - --txt-owner-id=dreamgames
          env:
            - name: ETCD_URLS
              value: "http://etcd-dreamgames.kube-system.svc.cluster.local:2379"
          resources:
            requests: { cpu: 50m, memory: 64Mi }
```

> **Local cluster için neden CoreDNS provider?** AWS/GCP'de Route53/Cloud DNS kullanılır.
> Local'de CoreDNS (RFC2136/etcd backend) cluster-internal DNS kayıtlarını otomatik yönetir.
> Cloud'a taşırken sadece `--provider` ve credential değişir; manifest yapısı aynı kalır.
> `--source=service` sayesinde yeni Service oluşunca (1.4b) DNS kaydı otomatik açılır.

```bash
kubectl apply -f kubernetes/externaldns/rbac.yaml
kubectl apply -f kubernetes/externaldns/deployment.yaml
kubectl logs -n kube-system deploy/external-dns | head   # "Created/Updated record" satırları
```

📖 ExternalDNS: https://github.com/kubernetes-sigs/external-dns
📖 CoreDNS provider: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/coredns.md

---

### Step 1.5: Jenkins

#### Case Study Ne İstiyor?

> *"Deploy Jenkins on Kubernetes cluster.*
> *a. Jenkins should be installed exclusively on Node 3.*
> *b. Configuring Jenkins using a 'configuration as code' approach is preferred.*
> *c. Configuration of Jenkins should persist across restarts or upgrades.*
> *d. Jenkins should be accessible via its hostname using a LoadBalancer."*

> ⚠️ **Faz 4 başlar.** Bu fazdan önce uygulamayı küçült:
> `kubectl scale deployment query-param-app --replicas=1 -n app` (Step 2.1'i yaptıysan).

#### Jenkins PV (Node 3 = worker2 pin) — 1.5a + 1.5c

`kubernetes/jenkins/pv.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jenkins-pv
spec:
  capacity:
    storage: 20Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/jenkins
  nodeAffinity:                  # PV worker2'ye bağlı → veri kaybolmaz (1.5c persistence)
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values: [worker2]   # Node 3
```

```bash
multipass exec worker2 -- sudo mkdir -p /mnt/jenkins
multipass exec worker2 -- sudo chown 1000:1000 /mnt/jenkins
kubectl apply -f kubernetes/jenkins/pv.yaml
```

#### Jenkins Secrets (hardcode yasak!)

```bash
kubectl create namespace jenkins
# DockerHub token: https://hub.docker.com/settings/security
# GitHub token:    https://github.com/settings/tokens
kubectl create secret generic jenkins-credentials \
  --from-literal=admin-password="$(openssl rand -base64 24)" \
  --from-literal=dockerhub-user=<DOCKERHUB_USER> \
  --from-literal=dockerhub-token=<DOCKERHUB_TOKEN> \
  --from-literal=github-token=<GITHUB_TOKEN> \
  -n jenkins
```
> ⚠️ Değerleri şifre yöneticisinden kopyala; sonra `history -c` ile terminal geçmişini temizle.

#### Jenkins Helm Values — 1.5a/b/c/d hepsi

`kubernetes/jenkins/values.yaml`:
```yaml
controller:
  # 1.5a: Node 3 (worker2) üzerine pin
  nodeSelector:
    kubernetes.io/hostname: worker2

  # 1.5d: LoadBalancer + hostname erişimi
  serviceType: LoadBalancer
  ingress:
    enabled: true
    hostName: jenkins.example.com
    ingressClassName: nginx

  # Dar M4 ortamı için kaynak sınırı
  resources:
    requests: { cpu: 250m, memory: 512Mi }
    limits:   { cpu: 1000m, memory: 1Gi }

  # 1.5b: JCasC (Configuration as Code)
  JCasC:
    defaultConfig: true
    configScripts:
      credentials: |
        credentials:
          system:
            domainCredentials:
              - credentials:
                  - usernamePassword:
                      scope: GLOBAL
                      id: "dockerhub-creds"
                      username: ${DOCKERHUB_USER}
                      password: ${DOCKERHUB_TOKEN}
                  - string:
                      scope: GLOBAL
                      id: "github-token"
                      secret: ${GITHUB_TOKEN}

  containerEnv:
    - name: DOCKERHUB_USER
      valueFrom: { secretKeyRef: { name: jenkins-credentials, key: dockerhub-user } }
    - name: DOCKERHUB_TOKEN
      valueFrom: { secretKeyRef: { name: jenkins-credentials, key: dockerhub-token } }
    - name: GITHUB_TOKEN
      valueFrom: { secretKeyRef: { name: jenkins-credentials, key: github-token } }

  adminSecret: false
  existingSecret: jenkins-credentials
  existingSecretKey: admin-password

  installPlugins:
    - git:latest
    - workflow-aggregator:latest
    - docker-workflow:latest
    - kubernetes:latest
    - ansible:latest          # Step 2.3 deploy pipeline Ansible kullanır

# 1.5c: config persistence (restart/upgrade'de kaybolmaz)
persistence:
  enabled: true
  storageClass: local-storage
  size: 20Gi
```

```bash
helm repo add jenkins https://charts.jenkins.io && helm repo update
helm install jenkins jenkins/jenkins -n jenkins -f kubernetes/jenkins/values.yaml --wait --timeout 6m

# Node 3 (worker2) doğrula
kubectl get pod -n jenkins -o wide   # NODE sütunu = worker2

# LoadBalancer IP + hostname erişimi
kubectl get svc -n jenkins jenkins   # EXTERNAL-IP MetalLB'den gelmeli
# http://jenkins.example.com
```

**Neden nodeSelector: worker2?** Case study "exclusively on Node 3" diyor. Node 3 = worker2.
nodeSelector pod'u sadece worker2'ye schedule eder; PV de nodeAffinity ile worker2'ye bağlı →
Jenkins pod + verisi her zaman aynı node'da, restart'ta veri korunur.

> 💾 **Faz 4 sonu:** Build/deploy pipeline'larını (Step 2.2, 2.3) Jenkins ayaktayken oluştur ve
> çalıştır, screenshot al. Sonra RAM boşalt: `helm uninstall jenkins -n jenkins`
> (PV `Retain` olduğu için veri /mnt/jenkins'te kalır, tekrar kurunca geri gelir).

📖 Jenkins Helm: https://www.jenkins.io/doc/book/installing/kubernetes/
📖 JCasC: https://www.jenkins.io/projects/jcasc/

---

### Step 1.6: Monitoring Stack

#### Case Study Ne İstiyor?

> *"Deploy Prometheus, Elasticsearch, Grafana, fluent-bit, and AlertManager.*
> *a. Create custom Grafana dashboards to visualize Kubernetes and application metrics.*
> *b. Set up alert conditions in AlertManager, which are triggered when the pod restarts.*
> *c. Use a single hostname with a combination of different paths to access Prometheus,
>    Elasticsearch, and Grafana dashboards.*
> *d. Forward application logs to Elasticsearch."*

> ⚠️ **Faz 5-6.** Jenkins'i kapattıysan RAM hazır. ES ağırdır → kendi alt fazında çalıştır.

#### Monitoring Secrets

```bash
kubectl create namespace monitoring

kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)"

# Slack webhook (hardcode yasak): https://api.slack.com/messaging/webhooks
kubectl create secret generic alertmanager-slack-secret -n monitoring \
  --from-literal=webhookUrl='https://hooks.slack.com/services/...'
```

#### kube-prometheus-stack (Prometheus + Grafana + AlertManager)

`kubernetes/monitoring/kube-prometheus-stack-values.yaml`:
```yaml
grafana:
  ingress:
    enabled: true
    hosts: ["monitoring.example.com"]
    path: /grafana
    ingressClassName: nginx
  grafana.ini:
    server:
      root_url: "http://monitoring.example.com/grafana"
      serve_from_sub_path: true
  admin:
    existingSecret: grafana-admin-secret
    userKey: admin-user
    passwordKey: admin-password
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard       # Bu label'lı ConfigMap'ler otomatik yüklenir
  resources:
    requests: { cpu: 50m, memory: 128Mi }

prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    externalUrl: "http://monitoring.example.com/prometheus"
    routePrefix: /prometheus
    retention: 2h                      # Dar disk için kısa retention
    resources:
      requests: { cpu: 100m, memory: 384Mi }

alertmanager:
  alertmanagerSpec:
    resources:
      requests: { cpu: 25m, memory: 64Mi }
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ["alertname", "namespace"]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: "slack"
    receivers:
      - name: "slack"
        slack_configs:
          - api_url_secret:
              name: alertmanager-slack-secret
              key: webhookUrl
            channel: "#alerts"
            title: "{{ .GroupLabels.alertname }} — {{ .Status | toUpper }}"
            text: "{{ range .Alerts }}{{ .Annotations.description }}\n{{ end }}"
```

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f kubernetes/monitoring/kube-prometheus-stack-values.yaml --wait --timeout 10m
```

#### 1.6c: Tek Hostname — Çoklu Path Ingress

`kubernetes/monitoring/ingress-monitoring.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: monitoring-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: monitoring.example.com          # TEK hostname
      http:
        paths:
          - path: /grafana(/|$)(.*)
            pathType: ImplementationSpecific
            backend: { service: { name: kube-prometheus-stack-grafana, port: { number: 80 } } }
          - path: /prometheus(/|$)(.*)
            pathType: ImplementationSpecific
            backend: { service: { name: kube-prometheus-stack-prometheus, port: { number: 9090 } } }
          - path: /elasticsearch(/|$)(.*)
            pathType: ImplementationSpecific
            backend: { service: { name: elasticsearch-es-http, port: { number: 9200 } } }
```

```bash
kubectl apply -f kubernetes/monitoring/ingress-monitoring.yaml
# http://monitoring.example.com/grafana | /prometheus | /elasticsearch
```

#### 1.6b: Pod Restart Alert (+ ek kurallar)

`kubernetes/monitoring/alertmanager-rules.yaml`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dreamgames-alerts
  namespace: monitoring
  labels:
    prometheus: kube-prometheus
    role: alert-rules
spec:
  groups:
    - name: pod.rules
      rules:
        # Case study 1.6b: "alert when the pod restarts"
        - alert: PodRestarted
          expr: increase(kube_pod_container_status_restarts_total{namespace="app"}[5m]) > 0
          for: 0m
          labels: { severity: critical }
          annotations:
            summary: "Pod {{ $labels.pod }} yeniden başladı"
            description: "{{ $labels.namespace }}/{{ $labels.pod }} restart oldu."
            runbook: "kubectl logs -n {{ $labels.namespace }} {{ $labels.pod }} --previous"
        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total{namespace="app"}[15m]) > 0
          for: 5m
          labels: { severity: critical }
          annotations:
            summary: "Pod {{ $labels.pod }} crash looping"
        - alert: DeploymentReplicasMismatch
          expr: kube_deployment_spec_replicas{namespace="app"} != kube_deployment_status_available_replicas{namespace="app"}
          for: 5m
          labels: { severity: warning }
          annotations: { summary: "Deployment replica sayısı tutarsız" }
    - name: app.rules
      rules:
        - alert: HighRequestLatency
          expr: histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket{namespace="app"}[5m])) by (le)) > 1.0
          for: 5m
          labels: { severity: warning }
          annotations: { summary: "p95 latency 1 saniyeyi aştı" }
        - alert: HighErrorRate
          expr: |
            sum(rate(http_server_requests_seconds_count{namespace="app",status=~"5.."}[5m])) /
            sum(rate(http_server_requests_seconds_count{namespace="app"}[5m])) * 100 > 5
          for: 5m
          labels: { severity: critical }
          annotations: { summary: "5xx hata oranı %5 üzerinde" }
        - alert: HPAMaxedOut
          expr: |
            kube_horizontalpodautoscaler_status_current_replicas{namespace="app"} >=
            kube_horizontalpodautoscaler_spec_max_replicas{namespace="app"}
          for: 10m
          labels: { severity: warning }
          annotations: { summary: "HPA maksimuma ulaştı — kapasite artırılmalı" }
    - name: node.rules
      rules:
        - alert: NodeHighMemory
          expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
          for: 10m
          labels: { severity: warning }
          annotations: { summary: "Node bellek yüksek: {{ $labels.node }}" }
```

```bash
kubectl apply -f kubernetes/monitoring/alertmanager-rules.yaml
kubectl get prometheusrule -n monitoring

# Alert testini tetikle: bir pod'u öldür → PodRestarted ateşlenmeli
kubectl delete pod -n app -l app=query-param-app --field-selector status.phase=Running | head -1
```

#### 1.6a: Grafana Dashboards (K8s + App)

İki dashboard: cluster genel durum + uygulama RED metrikleri. `grafana_dashboard: "1"` label'ı
sayesinde Grafana sidecar otomatik yükler.

`kubernetes/monitoring/grafana-dashboards/k8s-overview-configmap.yaml`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-overview-dashboard
  namespace: monitoring
  labels: { grafana_dashboard: "1" }
data:
  k8s-overview.json: |
    {
      "title": "Kubernetes Cluster Overview", "uid": "k8s-overview",
      "schemaVersion": 38, "refresh": "30s",
      "panels": [
        { "id": 1, "title": "Pod Restarts (app)", "type": "stat",
          "gridPos": {"x":0,"y":0,"w":6,"h":4},
          "targets": [{"expr":"sum(increase(kube_pod_container_status_restarts_total{namespace=\"app\"}[1h]))"}] },
        { "id": 2, "title": "Node CPU %", "type": "timeseries",
          "gridPos": {"x":6,"y":0,"w":9,"h":4},
          "targets": [{"expr":"100 - (avg by(node)(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))*100)","legendFormat":"{{ node }}"}] },
        { "id": 3, "title": "Node Memory %", "type": "timeseries",
          "gridPos": {"x":15,"y":0,"w":9,"h":4},
          "targets": [{"expr":"(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)*100","legendFormat":"{{ instance }}"}] },
        { "id": 4, "title": "Running Pods", "type": "stat",
          "gridPos": {"x":0,"y":4,"w":4,"h":3},
          "targets": [{"expr":"count(kube_pod_status_phase{phase=\"Running\"})"}] }
      ]
    }
```

`kubernetes/monitoring/grafana-dashboards/app-metrics-configmap.yaml`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-metrics-dashboard
  namespace: monitoring
  labels: { grafana_dashboard: "1" }
data:
  app-metrics.json: |
    {
      "title": "query-param-app — RED Metrics", "uid": "dreamgames-app",
      "schemaVersion": 38, "refresh": "30s",
      "panels": [
        { "id":1,"title":"Request Rate (RPS)","type":"timeseries","gridPos":{"x":0,"y":0,"w":8,"h":8},
          "targets":[{"expr":"sum(rate(http_server_requests_seconds_count{namespace=\"app\"}[2m])) by (uri)","legendFormat":"{{ uri }}"}] },
        { "id":2,"title":"Error Rate (5xx %)","type":"timeseries","gridPos":{"x":8,"y":0,"w":8,"h":8},
          "targets":[{"expr":"sum(rate(http_server_requests_seconds_count{namespace=\"app\",status=~\"5..\"}[2m])) / sum(rate(http_server_requests_seconds_count{namespace=\"app\"}[2m]))*100","legendFormat":"5xx %"}] },
        { "id":3,"title":"Latency p50/p95/p99","type":"timeseries","gridPos":{"x":16,"y":0,"w":8,"h":8},
          "targets":[
            {"expr":"histogram_quantile(0.50, sum(rate(http_server_requests_seconds_bucket{namespace=\"app\"}[2m])) by (le))","legendFormat":"p50"},
            {"expr":"histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket{namespace=\"app\"}[2m])) by (le))","legendFormat":"p95"},
            {"expr":"histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket{namespace=\"app\"}[2m])) by (le))","legendFormat":"p99"}
          ] },
        { "id":4,"title":"HPA Current/Max","type":"stat","gridPos":{"x":0,"y":8,"w":6,"h":4},
          "targets":[
            {"expr":"kube_horizontalpodautoscaler_status_current_replicas{namespace=\"app\"}","legendFormat":"current"},
            {"expr":"kube_horizontalpodautoscaler_spec_max_replicas{namespace=\"app\"}","legendFormat":"max"}
          ] }
      ]
    }
```

```bash
kubectl apply -f kubernetes/monitoring/grafana-dashboards/
GRAFANA_PASS=$(kubectl get secret grafana-admin-secret -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)
echo "Grafana: http://monitoring.example.com/grafana  admin / $GRAFANA_PASS"
```

#### 1.6d: Elasticsearch (ECK) + Fluent Bit (Logları ES'e Forward)

```bash
# ECK Operator
kubectl create -f https://download.elastic.co/downloads/eck/2.11.1/crds.yaml
kubectl apply  -f https://download.elastic.co/downloads/eck/2.11.1/operator.yaml
```

`kubernetes/monitoring/elasticsearch/elasticsearch.yaml`:
```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
  namespace: monitoring
spec:
  version: 8.12.0
  nodeSets:
    - name: default
      count: 1
      config:
        node.store.allow_mmap: false
      podTemplate:
        spec:
          containers:
            - name: elasticsearch
              resources:
                requests: { memory: 1Gi, cpu: 250m }
                limits:   { memory: 1Gi }
              env:
                - name: ES_JAVA_OPTS
                  value: "-Xms512m -Xmx512m"
```

```bash
kubectl apply -f kubernetes/monitoring/elasticsearch/elasticsearch.yaml
kubectl get elasticsearch -n monitoring   # health: green (5-10 dk)

# ES şifresini fluent-bit için secret'a aktar
ELASTIC_PASS=$(kubectl get secret elasticsearch-es-elastic-user -n monitoring -o jsonpath='{.data.elastic}' | base64 -d)
kubectl create secret generic elastic-credentials -n monitoring --from-literal=ELASTIC_PASSWORD="$ELASTIC_PASS"
```

`kubernetes/monitoring/fluent-bit/values.yaml`:
```yaml
resources:
  requests: { cpu: 25m, memory: 64Mi }
config:
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/query-param-app*.log
        Parser            cri
        Tag               app.*
        Refresh_Interval  5
  filters: |
    [FILTER]
        Name    kubernetes
        Match   app.*
        Merge_Log On
  outputs: |
    [OUTPUT]
        Name            es
        Match           app.*
        Host            elasticsearch-es-http.monitoring.svc.cluster.local
        Port            9200
        HTTP_User       elastic
        HTTP_Passwd     ${ELASTIC_PASSWORD}
        tls             On
        tls.verify      Off
        Index           app-logs
        Suppress_Type_Name On
```

```bash
helm repo add fluent https://fluent.github.io/helm-charts && helm repo update
helm install fluent-bit fluent/fluent-bit -n monitoring \
  -f kubernetes/monitoring/fluent-bit/values.yaml \
  --set envFrom[0].secretRef.name=elastic-credentials

# Doğrula: ES'te app-logs index'i oluştu mu?
curl -sk -u elastic:$ELASTIC_PASS http://monitoring.example.com/elasticsearch/_cat/indices | grep app-logs
```

> 💾 **Faz 6 sonu:** Logların ES'e aktığını doğrula/screenshot al, sonra RAM boşalt:
> `helm uninstall fluent-bit -n monitoring && kubectl delete elasticsearch elasticsearch -n monitoring`

📖 kube-prometheus-stack: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
📖 ECK: https://www.elastic.co/guide/en/cloud-on-k8s/current/
📖 Fluent Bit: https://docs.fluentbit.io/manual/

---

### Step 1.7: Asenkron Dosya Logging

#### Case Study Ne İstiyor?

> *"Printing logs to stdout negatively impacts performance. Please explain how you would design
> and implement the following:*
> *a. Write application logs to a file asynchronously.*
> *b. Ensure the log file size does not exceed 1GB.*
> *c. Rotate log files daily."*

#### Tasarım Açıklaması

Senkron stdout logging: her log satırı I/O bekler → yüksek trafikte ana thread bloklanır, response
time artar. **Çözüm:** Logback `AsyncAppender` ile loglar bir kuyruğa yazılır, ayrı bir thread
dosyaya yazar → ana thread bloklanmaz. `SizeAndTimeBasedRollingPolicy` ile dosya 1GB'ı geçince
ve her gün yeni dosyaya döner. Fluent Bit bu dosyayı (veya container log'unu) okuyup ES'e taşır.

#### Nasıl Yapılır?

`app/src/main/resources/logback-spring.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <!-- Dosyaya yazan rolling appender -->
  <appender name="FILE_SYNC" class="ch.qos.logback.core.rolling.RollingFileAppender">
    <file>/app/logs/application.log</file>
    <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
      <!-- 7c: günlük rotation + 7b: 1GB boyut limiti -->
      <fileNamePattern>/app/logs/application.%d{yyyy-MM-dd}.%i.log.gz</fileNamePattern>
      <maxFileSize>1GB</maxFileSize>
      <maxHistory>30</maxHistory>
      <totalSizeCap>10GB</totalSizeCap>
    </rollingPolicy>
    <encoder class="net.logstash.logback.encoder.LogstashEncoder"/>
  </appender>

  <!-- 7a: AsyncAppender — log yazma ayrı thread'de, ana thread bloklanmaz -->
  <appender name="FILE_ASYNC" class="ch.qos.logback.classic.AsyncAppender">
    <queueSize>1024</queueSize>
    <discardingThreshold>0</discardingThreshold>
    <appender-ref ref="FILE_SYNC"/>
  </appender>

  <!-- stdout (geçiş dönemi / debug için; performans için kapatılabilir) -->
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder class="net.logstash.logback.encoder.LogstashEncoder"/>
  </appender>

  <root level="INFO">
    <appender-ref ref="FILE_ASYNC"/>
    <appender-ref ref="STDOUT"/>
  </root>
</configuration>
```

> **stdout'u tamamen kaldırmak isterseniz** (case study'nin "stdout performansı düşürüyor"
> gözlemi): `<root>`'tan `STDOUT` ref'ini çıkarın ve Fluent Bit'i app pod'una **sidecar** olarak
> ekleyip `/app/logs/application.log` dosyasını tail edin (emptyDir paylaşımlı volume). Böylece
> hiç stdout yazılmaz, sadece async dosya logging kalır.

Bu değişiklikten sonra imajı yeniden derle (Step 2.2 pipeline bunu Jenkins'te yapar; local'de
Docker Desktop'sız master VM'inde nerdctl ile):
```bash
cd app && mvn clean package -DskipTests && cd ..
multipass transfer -r app master:/home/ubuntu/app
multipass exec master -- sudo nerdctl --namespace k8s.io build -t dreamgames/query-param-app:1.1.0 /home/ubuntu/app
```

📖 Logback AsyncAppender: https://logback.qos.ch/manual/appenders.html#AsyncAppender
📖 SizeAndTimeBasedRollingPolicy: https://logback.qos.ch/manual/appenders.html#SizeAndTimeBasedRollingPolicy

---

## Step 2: Deployment ve Pipeline'lar

### Step 2.1: Uygulamayı Kubernetes'e Deploy Et

#### Case Study Ne İstiyor?

> *"The application should be deployed on both worker nodes with a minimum of 4 pods, and the
> service should be load-balanced using Nginx.*
> *a. Ensure that pods are evenly distributed across the nodes.*
> *b. Verify that the application starts receiving requests as soon as it is ready and is
>    restarted automatically if any issues arise."*

> ⚠️ **Faz 2.** Bu çekirdek demo kalıcı çalışır.

#### Namespace'ler + Pod Security Admission

`kubernetes/namespaces/namespaces.yaml`:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    pod-security.kubernetes.io/enforce: restricted   # root yasak, privilege escalation yasak
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    pod-security.kubernetes.io/enforce: baseline     # node-exporter hostNetwork ister
---
apiVersion: v1
kind: Namespace
metadata:
  name: jenkins
  labels:
    pod-security.kubernetes.io/enforce: baseline
---
apiVersion: v1
kind: Namespace
metadata:
  name: webhook-system
  labels:
    pod-security.kubernetes.io/enforce: restricted
```

`kubernetes/app/serviceaccount.yaml`:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: query-param-app
  namespace: app
automountServiceAccountToken: false   # Uygulama K8s API'ye erişmez → saldırı yüzeyi azalır
```

#### Deployment (4 pod, eşit dağılım, readiness, auto-restart)

`kubernetes/app/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: query-param-app
  namespace: app
spec:
  replicas: 4                       # Case study: minimum 4 pod
  selector:
    matchLabels: { app: query-param-app }
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0             # Zero-downtime (Step 2.3c)
  template:
    metadata:
      labels: { app: query-param-app }
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
        prometheus.io/path: "/actuator/prometheus"
    spec:
      serviceAccountName: query-param-app
      # 2.1a: pod'ları worker1 + worker2'ye eşit dağıt
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels: { app: query-param-app }
      containers:
        - name: query-param-app
          image: dreamgames/query-param-app:1.1.0
          ports:
            - { containerPort: 8080, name: http }
            - { containerPort: 9090, name: management }
          resources:
            requests: { cpu: 100m, memory: 128Mi }   # Dar M4 ortamı: 4×128Mi=512Mi
            limits:   { cpu: 500m, memory: 256Mi }
          # JVM yavaş boot edebilir (dar RAM) → startupProbe grace verir
          startupProbe:
            httpGet: { path: /actuator/health/readiness, port: 9090 }
            failureThreshold: 30
            periodSeconds: 5         # 150 sn boot süresi toleransı
          # 2.1b: hazır olana kadar trafik gelmesin
          readinessProbe:
            httpGet: { path: /actuator/health/readiness, port: 9090 }
            periodSeconds: 5
            failureThreshold: 3
          # 2.1b: cevap vermezse otomatik restart
          livenessProbe:
            httpGet: { path: /actuator/health/liveness, port: 9090 }
            periodSeconds: 10
            failureThreshold: 3
          lifecycle:
            preStop:
              exec: { command: ["sh", "-c", "sleep 5"] }   # uçuştaki istekler bitsin
          volumeMounts:
            - { name: logs, mountPath: /app/logs }
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            allowPrivilegeEscalation: false
            capabilities: { drop: ["ALL"] }
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        seccompProfile: { type: RuntimeDefault }
      volumes:
        - name: logs
          emptyDir: {}
```

#### Service (Nginx LB), HPA, PDB, Ingress, NetworkPolicy

`kubernetes/app/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: query-param-app
  namespace: app
spec:
  selector: { app: query-param-app }
  ports:
    - { name: http, port: 80, targetPort: 8080 }
    - { name: management, port: 9090, targetPort: 9090 }
```

`kubernetes/app/hpa.yaml`:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: query-param-app
  namespace: app
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: query-param-app }
  minReplicas: 4
  maxReplicas: 16
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
    - type: Resource
      resource: { name: memory, target: { type: Utilization, averageUtilization: 80 } }
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies: [{ type: Pods, value: 2, periodSeconds: 60 }]
```

`kubernetes/app/pdb.yaml`:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: query-param-app
  namespace: app
spec:
  selector:
    matchLabels: { app: query-param-app }
  maxUnavailable: 1
```

`kubernetes/app/ingress.yaml` (2.3b hostname Ingress):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: query-param-app
  namespace: app
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
spec:
  ingressClassName: nginx
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: query-param-app, port: { number: 80 } } }
```

`kubernetes/app/networkpolicy.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: app
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: query-param-app-allow
  namespace: app
spec:
  podSelector:
    matchLabels: { app: query-param-app }
  policyTypes: [Ingress, Egress]
  ingress:
    - from: [{ namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: ingress-nginx } } }]
      ports: [{ port: 8080 }]
    - from: [{ namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: monitoring } } }]
      ports: [{ port: 9090 }]
  egress:
    - to: [{ namespaceSelector: {} }]
      ports:
        - { port: 53, protocol: UDP }
        - { port: 53, protocol: TCP }
```

#### Deploy ve Doğrula

```bash
kubectl apply -f kubernetes/namespaces/namespaces.yaml
kubectl apply -f kubernetes/app/

kubectl rollout status deployment/query-param-app -n app --timeout=180s

# 2.1a: eşit dağılım — worker1 ve worker2'de pod olmalı
kubectl get pods -n app -o wide

# Nginx üzerinden load-balanced erişim
curl 'http://app.example.com/api/echo?hello=world'   # → {"hello":"world"}

# 2.1b: auto-restart testi — bir pod'u öldür, otomatik geri gelsin
kubectl delete pod -n app -l app=query-param-app | head -1
kubectl get pods -n app -w   # yeni pod Running olur
```

📖 topologySpreadConstraints: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
📖 Probes: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/

---

### Step 2.2: Build Pipeline

#### Case Study Ne İstiyor?

> *"Create a build pipeline for the application using a Jenkinsfile.*
> *a. Ensure that the built Container image is deployed to the Registry."*

#### Nasıl Yapılır?

`jenkins/Jenkinsfile.build`:
```groovy
pipeline {
    agent any
    environment {
        IMAGE_NAME = "dreamgames/query-param-app"
        // :latest KULLANMA — mutable tag, hangi kod çalıştığı bilinmez
        IMAGE_TAG  = "${BUILD_NUMBER}-${GIT_COMMIT.take(7)}"
    }
    stages {
        stage('Checkout') { steps { checkout scm } }
        stage('Unit Test') { steps { dir('app') { sh 'mvn clean test -q' } } }
        stage('Build JAR') { steps { dir('app') { sh 'mvn clean package -DskipTests -q' } } }
        stage('Build Image') { steps { dir('app') { sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ." } } }
        stage('Security Scan') {
            // Trivy: HIGH/CRITICAL CVE varsa pipeline durur, imaj push edilmez
            steps {
                sh """
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image --exit-code 1 \
                      --severity HIGH,CRITICAL --no-progress ${IMAGE_NAME}:${IMAGE_TAG}
                """
            }
        }
        stage('Push to Registry') {        // case study 2.2a
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh """
                        echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker logout
                    """
                }
            }
        }
    }
    post { always { sh "docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true" } }
}
```

Jenkins UI'da: **New Item → Pipeline → Pipeline script from SCM → Git → Script Path:
`jenkins/Jenkinsfile.build`**. Çalıştır → imaj DockerHub'a push olur.

📖 Jenkins Pipeline: https://www.jenkins.io/doc/book/pipeline/
📖 Trivy: https://aquasecurity.github.io/trivy/

---

### Step 2.3: Deploy Pipeline (Ansible)

#### Case Study Ne İstiyor?

> *"Create a deployment pipeline for the application using a Jenkinsfile.*
> *a. Use Ansible to apply Kubernetes manifests.*
> *b. The application should be accessible via its hostname using an Ingress.*
> *c. Describe your approach for achieving zero-downtime deployments."*

> ⚠️ **2.3a kritik:** Deploy `kubectl apply` ile değil, **Ansible** ile yapılmalı.

#### Ansible Deploy Playbook

`ansible/deploy-app.yml`:
```yaml
---
- name: Deploy query-param-app to Kubernetes
  hosts: master
  become: false
  vars:
    app_namespace: "{{ app_namespace | default('app') }}"
    docker_user:   "{{ docker_user | default('dreamgames') }}"
    image_tag:     "{{ image_tag | default('latest') }}"
  tasks:
    - name: Manifest'leri uygula (Ansible k8s modülü)
      kubernetes.core.k8s:
        state: present
        src: "{{ item }}"
      loop:
        - kubernetes/app/serviceaccount.yaml
        - kubernetes/app/service.yaml
        - kubernetes/app/hpa.yaml
        - kubernetes/app/pdb.yaml
        - kubernetes/app/ingress.yaml
        - kubernetes/app/networkpolicy.yaml

    - name: Deployment image'ını güncelle
      kubernetes.core.k8s:
        state: present
        definition:
          apiVersion: apps/v1
          kind: Deployment
          metadata: { name: query-param-app, namespace: "{{ app_namespace }}" }
          spec:
            template:
              spec:
                containers:
                  - name: query-param-app
                    image: "{{ docker_user }}/query-param-app:{{ image_tag }}"

    - name: Rollout durumu kontrol
      command: kubectl rollout status deployment/query-param-app -n {{ app_namespace }} --timeout=5m
      register: rollout_result
      failed_when: rollout_result.rc != 0

    - name: Rollback (rollout başarısızsa)
      command: kubectl rollout undo deployment/query-param-app -n {{ app_namespace }}
      when: rollout_result.rc != 0
```

#### Deploy Jenkinsfile

`jenkins/Jenkinsfile.deploy`:
```groovy
pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: ansible
    image: cytopia/ansible:2.15-tools
    command: ['sleep', '99d']
    resources: { requests: { cpu: 200m, memory: 256Mi } }
  - name: kubectl
    image: bitnami/kubectl:1.32
    command: ['sleep', '99d']
    resources: { requests: { cpu: 100m, memory: 128Mi } }
"""
        }
    }
    parameters {
        string(name: 'IMAGE_TAG', description: 'Deploy edilecek tag (örn: 42-abc1234)')
        choice(name: 'ENVIRONMENT', choices: ['app', 'staging'], description: 'Hedef namespace')
        booleanParam(name: 'DRY_RUN', defaultValue: false)
    }
    environment { KUBECONFIG = credentials('kubeconfig') }
    stages {
        stage('Checkout') { steps { checkout scm } }
        stage('Validate Manifests') {
            steps { container('kubectl') {
                sh "kubectl apply -f kubernetes/app/ --dry-run=client -n ${params.ENVIRONMENT}"
            } }
        }
        stage('Deploy via Ansible') {        // case study 2.3a
            steps { container('ansible') {
                sh """
                    ansible-playbook ansible/deploy-app.yml \
                      -i ansible/inventory/hosts.ini \
                      -e image_tag=${params.IMAGE_TAG} \
                      -e app_namespace=${params.ENVIRONMENT} \
                      ${params.DRY_RUN ? '--check' : ''}
                """
            } }
        }
        stage('Smoke Test') {
            when { not { expression { params.DRY_RUN } } }
            steps { sh "sleep 10 && curl -sf http://app.example.com/api/echo?smoke=true | grep smoke" }
        }
    }
    post {
        failure { container('kubectl') {
            sh "kubectl rollout undo deployment/query-param-app -n ${params.ENVIRONMENT} || true"
        } }
    }
}
```

```bash
# Jenkins deploy pipeline kubeconfig secret'ı (hardcode yasak)
kubectl create secret generic kubeconfig --from-file=config=$KUBECONFIG -n jenkins
```

#### 2.3c: Zero-Downtime Yaklaşımı

- `maxUnavailable: 0, maxSurge: 1` → önce yeni pod gelir, hazır olunca eski silinir → hiç kesinti yok.
- `readinessProbe` → yeni pod hazır olana kadar Service trafiği göndermez.
- `preStop: sleep 5` + `terminationGracePeriodSeconds: 30` → eski pod kapanırken uçuştaki istekler biter.
- `PodDisruptionBudget` → drain sırasında bile minimum pod ayakta.

Test:
```bash
# Terminal 1: sürekli istek
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://app.example.com/api/echo?x=1; sleep 0.3; done
# Terminal 2: yeni versiyona geç → Terminal 1'de hep 200 görünmeli, 0 hata
kubectl set image deployment/query-param-app query-param-app=dreamgames/query-param-app:1.1.0 -n app
```

**Neden Ansible, kubectl değil?** Case study istiyor; mantığı da var: Ansible idempotent,
playbook tekrar çalıştırılabilir, cluster dışından (kubeconfig ile) çalışır → Jenkins'in K8s
API'ye doğrudan erişmesi gerekmez.

📖 Ansible kubernetes.core: https://docs.ansible.com/ansible/latest/collections/kubernetes/core/

---

### Step 2.4: Validation Webhook

#### Case Study Ne İstiyor?

> *"Write a custom validation webhook that fails if a deployment does not specify required CPU
> and memory resource requests.*
> *a. Use a configmap to specify in which namespaces this validation webhook runs.*
> *b. Webhook should expose its metrics to Prometheus."*

> ⚠️ **Faz 7** (hafif, kalıcı). Namespace listesi **ConfigMap'ten** okunur — hardcode değil.

#### Go Webhook Kodu

`webhook/main.go`:
```go
package main

import (
    "crypto/tls"
    "encoding/json"
    "fmt"
    "io"
    "log"
    "net/http"
    "os"
    "strings"

    admissionv1 "k8s.io/api/admission/v1"
    appsv1 "k8s.io/api/apps/v1"
    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/apimachinery/pkg/runtime"
    "k8s.io/apimachinery/pkg/runtime/serializer"

    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    scheme = runtime.NewScheme()
    codecs = serializer.NewCodecFactory(scheme)

    validationsTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{Name: "webhook_validations_total"},
        []string{"result"}, // "allowed" | "rejected"
    )
)

func init() {
    _ = appsv1.AddToScheme(scheme)
    _ = admissionv1.AddToScheme(scheme)
    prometheus.MustRegister(validationsTotal)
}

// 2.4a: namespace listesini ConfigMap volume mount'tan oku (hardcode değil)
func allowedNamespaces() map[string]bool {
    ns := os.Getenv("WEBHOOK_NAMESPACES")
    if ns == "" {
        if data, err := os.ReadFile("/etc/webhook/namespaces"); err == nil {
            ns = string(data)
        }
    }
    if ns == "" {
        ns = "default,app"
    }
    result := make(map[string]bool)
    for _, n := range strings.Split(strings.TrimSpace(ns), ",") {
        result[strings.TrimSpace(n)] = true
    }
    return result
}

func checkContainers(containers []corev1.Container) []string {
    var v []string
    for _, c := range containers {
        if c.Resources.Requests.Cpu().IsZero() {
            v = append(v, fmt.Sprintf("container %q: resources.requests.cpu eksik", c.Name))
        }
        if c.Resources.Requests.Memory().IsZero() {
            v = append(v, fmt.Sprintf("container %q: resources.requests.memory eksik", c.Name))
        }
    }
    return v
}

func handleValidate(w http.ResponseWriter, r *http.Request) {
    body, _ := io.ReadAll(r.Body)
    obj, gvk, err := codecs.UniversalDeserializer().Decode(body, nil, nil)
    if err != nil || gvk.Kind != "AdmissionReview" {
        http.Error(w, "decode error", http.StatusBadRequest)
        return
    }
    review := obj.(*admissionv1.AdmissionReview)
    req := review.Request

    if !allowedNamespaces()[req.Namespace] {   // sadece izinli namespace'leri denetle
        respond(w, review, true, "")
        return
    }
    var deploy appsv1.Deployment
    if err := json.Unmarshal(req.Object.Raw, &deploy); err != nil {
        respond(w, review, true, "")
        return
    }
    var violations []string
    violations = append(violations, checkContainers(deploy.Spec.Template.Spec.Containers)...)
    violations = append(violations, checkContainers(deploy.Spec.Template.Spec.InitContainers)...)

    if len(violations) > 0 {
        validationsTotal.WithLabelValues("rejected").Inc()
        respond(w, review, false, "Reddedildi — eksik resource request:\n"+strings.Join(violations, "\n"))
    } else {
        validationsTotal.WithLabelValues("allowed").Inc()
        respond(w, review, true, "")
    }
}

func respond(w http.ResponseWriter, review *admissionv1.AdmissionReview, allowed bool, msg string) {
    resp := &admissionv1.AdmissionResponse{UID: review.Request.UID, Allowed: allowed}
    if !allowed {
        resp.Result = &metav1.Status{Code: 422, Message: msg}
    }
    review.Response = resp
    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(review)
}

func main() {
    // 2.4b: Prometheus metrics — TLS değil, düz HTTP :8080
    go func() {
        mux := http.NewServeMux()
        mux.Handle("/metrics", promhttp.Handler())
        log.Fatal(http.ListenAndServe(":8080", mux))
    }()

    // Validation endpoint — TLS :8443 (kube-apiserver TLS ister)
    cert, err := tls.LoadX509KeyPair("/etc/webhook/certs/tls.crt", "/etc/webhook/certs/tls.key")
    if err != nil {
        log.Fatalf("TLS yüklenemedi: %v", err)
    }
    http.HandleFunc("/validate", handleValidate)
    server := &http.Server{Addr: ":8443", TLSConfig: &tls.Config{Certificates: []tls.Certificate{cert}}}
    log.Println("Webhook :8443 (TLS validate), :8080 (metrics)")
    log.Fatal(server.ListenAndServeTLS("", ""))
}
```

`webhook/Dockerfile`:
```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /webhook .

FROM scratch
COPY --from=builder /webhook /webhook
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
USER 65534
ENTRYPOINT ["/webhook"]
```

```bash
cd webhook && go mod init webhook 2>/dev/null; go mod tidy
go vet ./... && go build ./... && cd ..
# Imajı master VM'inde build et (Docker Desktop yok) → doğrudan cluster containerd'sine
multipass transfer -r webhook master:/home/ubuntu/webhook
multipass exec master -- sudo nerdctl --namespace k8s.io build -t dreamgames/resource-webhook:1.0.0 /home/ubuntu/webhook
```

#### Webhook ConfigMap (2.4a) + Deployment

`kubernetes/webhook/configmap.yaml`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: webhook-config
  namespace: webhook-system
data:
  # Bu namespace'lerdeki Deployment'lar denetlenir. Güncelle → pod restart yeter (rebuild gerekmez)
  namespaces: "app,production,staging"
```

`kubernetes/webhook/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-webhook
  namespace: webhook-system
spec:
  replicas: 2
  selector:
    matchLabels: { app: resource-webhook }
  template:
    metadata:
      labels: { app: resource-webhook }
      annotations:
        prometheus.io/scrape: "true"     # 2.4b
        prometheus.io/port: "8080"
    spec:
      containers:
        - name: resource-webhook
          image: dreamgames/resource-webhook:1.0.0
          ports:
            - { containerPort: 8443, name: https }
            - { containerPort: 8080, name: metrics }
          volumeMounts:
            - { name: certs, mountPath: /etc/webhook/certs, readOnly: true }
            - { name: config, mountPath: /etc/webhook/namespaces, subPath: namespaces, readOnly: true }
          resources:
            requests: { cpu: 50m, memory: 32Mi }
            limits:   { cpu: 200m, memory: 128Mi }
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
      volumes:
        - name: certs
          secret: { secretName: resource-webhook-tls }
        - name: config
          configMap: { name: webhook-config }     # namespace listesi buradan gelir
```

`kubernetes/webhook/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: resource-webhook
  namespace: webhook-system
spec:
  selector: { app: resource-webhook }
  ports:
    - { name: https, port: 443, targetPort: 8443 }
    - { name: metrics, port: 8080, targetPort: 8080 }
```

`kubernetes/webhook/validatingwebhookconfiguration.yaml`:
```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: resource-requests-webhook
webhooks:
  - name: resource-requests.dreamgames.com
    admissionReviewVersions: ["v1"]
    sideEffects: None
    failurePolicy: Fail
    clientConfig:
      service: { name: resource-webhook, namespace: webhook-system, path: /validate, port: 443 }
      caBundle: ""        # generate-certs.sh dolduracak
    rules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
```

#### TLS + Deploy

`kubernetes/webhook/tls/generate-certs.sh`:
```bash
#!/bin/bash
set -e
NAMESPACE="webhook-system"; SERVICE="resource-webhook"
TMPDIR=$(mktemp -d); trap "rm -rf $TMPDIR" EXIT

openssl genrsa -out "$TMPDIR/ca.key" 2048
openssl req -new -x509 -days 3650 -key "$TMPDIR/ca.key" -subj "/CN=webhook-ca" -out "$TMPDIR/ca.crt"
openssl genrsa -out "$TMPDIR/tls.key" 2048
openssl req -new -key "$TMPDIR/tls.key" -subj "/CN=${SERVICE}.${NAMESPACE}.svc" -out "$TMPDIR/tls.csr"
cat > "$TMPDIR/san.conf" << EOF
subjectAltName = DNS:${SERVICE}.${NAMESPACE}.svc,DNS:${SERVICE}.${NAMESPACE}.svc.cluster.local
EOF
openssl x509 -req -days 3650 -in "$TMPDIR/tls.csr" -CA "$TMPDIR/ca.crt" -CAkey "$TMPDIR/ca.key" \
  -CAcreateserial -extfile "$TMPDIR/san.conf" -out "$TMPDIR/tls.crt"

kubectl create secret tls resource-webhook-tls --cert="$TMPDIR/tls.crt" --key="$TMPDIR/tls.key" \
  -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

CA_BUNDLE=$(base64 < "$TMPDIR/ca.crt" | tr -d '\n')
kubectl patch validatingwebhookconfiguration resource-requests-webhook --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${CA_BUNDLE}\"}]"
echo "Done."
```

```bash
kubectl apply -f kubernetes/webhook/configmap.yaml
kubectl apply -f kubernetes/webhook/deployment.yaml
kubectl apply -f kubernetes/webhook/service.yaml
kubectl apply -f kubernetes/webhook/validatingwebhookconfiguration.yaml
chmod +x kubernetes/webhook/tls/generate-certs.sh && bash kubernetes/webhook/tls/generate-certs.sh
kubectl get pods -n webhook-system   # 2 pod Running
```

**Test:**
```bash
# Kötü deploy (resource request yok → reddedilmeli)
kubectl apply -n app -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: bad-deploy }
spec:
  replicas: 1
  selector: { matchLabels: { app: bad } }
  template:
    metadata: { labels: { app: bad } }
    spec:
      containers:
        - { name: nginx, image: nginx }   # resources YOK
EOF
# Beklenen: admission webhook ... denied the request

# 2.4a esnekliği: namespace ekle (kod değişmeden!)
kubectl patch configmap webhook-config -n webhook-system --type=json \
  -p='[{"op":"replace","path":"/data/namespaces","value":"app,production,staging,test"}]'
kubectl rollout restart deployment/resource-webhook -n webhook-system
```

📖 Admission Webhooks: https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/
📖 Prometheus Go client: https://github.com/prometheus/client_golang

---

## Step 3: Kaynak ve Ölçekleme Senaryoları

> Bu adımlar manifest + tasarım açıklaması ister. Manifest'leri kısa süre apply edip doğrula,
> sonra sil (faz faz). Yazılı yanıtları `docs/design-answers/` altına da koy.

### Step 3.1: App X / App Y Kaynak Yönetimi

#### Case Study Ne İstiyor?

> *"Our cluster has a limited number of nodes... App X: real-time, high availability. App Y: batch,
> can be killed or paused. How would you ensure App X scales effectively under heavy load while
> considering limited resources and App Y? Please share your sample manifest file."*

#### Çözüm: PriorityClass + QoS

Node baskısında Kubernetes pod tahliye eder. Sıra: **BestEffort → Burstable → Guaranteed**.
App X'i **Guaranteed** (requests == limits) + yüksek **PriorityClass** yaparız → asla tahliye
edilmez, yer gerekirse scheduler App Y'yi (düşük priority, Burstable) evict eder.

`step3-manifests/priority-classes.yaml`:
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: high-priority-realtime }
value: 1000
globalDefault: false
description: "App X — gerçek zamanlı, tahliye edilemez"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: low-priority-batch }
value: 100
globalDefault: false
description: "App Y — batch, baskıda tahliye edilebilir"
```

`step3-manifests/app-x-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: app-realtime, namespace: app }
spec:
  replicas: 2
  selector: { matchLabels: { app: app-realtime } }
  template:
    metadata: { labels: { app: app-realtime } }
    spec:
      priorityClassName: high-priority-realtime
      containers:
        - name: app
          image: nginx:alpine
          resources:
            requests: { cpu: 200m, memory: 128Mi }
            limits:   { cpu: 200m, memory: 128Mi }   # requests==limits → Guaranteed QoS
```

`step3-manifests/app-y-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: app-batch, namespace: app }
spec:
  replicas: 4
  selector: { matchLabels: { app: app-batch } }
  template:
    metadata: { labels: { app: app-batch } }
    spec:
      priorityClassName: low-priority-batch
      containers:
        - name: app
          image: nginx:alpine
          resources:
            requests: { cpu: 100m, memory: 64Mi }
            limits:   { cpu: 500m, memory: 256Mi }   # requests<limits → Burstable QoS
```

```bash
kubectl apply -f step3-manifests/priority-classes.yaml
kubectl apply -f step3-manifests/app-x-deployment.yaml
kubectl apply -f step3-manifests/app-y-deployment.yaml
kubectl get pods -n app -o wide
# App X için HPA da eklenir (Step 2.1 HPA mantığı) → yük altında App X ölçeklenir,
# kaynak yetmezse App Y evict edilir.
```

📖 PriorityClass: https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/
📖 QoS: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/

---

### Step 3.2: Zamanlı Ölçekleme + Node Scaling

#### Case Study Ne İstiyor?

> *"Higher traffic during specific periods... users should not experience increased response times.*
> *a. How would you ensure the application scale-out and scale-in appropriately before and after
>    these periods?*
> *b. If there aren't enough nodes, how would you increase the number of nodes before peak times
>    without slowing down the system?"*

#### 3.2a: KEDA ile Proaktif (Zamanlı) Pod Ölçekleme

Standart HPA reaktiftir (yük başlayınca ölçekler, 2-5 dk gecikme). KEDA `CronTrigger` proaktiftir:
yoğunluk gelmeden önce pod sayısını artırır.

`step3-manifests/hpa-scheduled.yaml`:
```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: { name: query-param-app-scheduled, namespace: app }
spec:
  scaleTargetRef: { name: query-param-app }
  minReplicaCount: 4
  maxReplicaCount: 16
  triggers:
    - type: cpu                       # reaktif taban
      metricType: Utilization
      metadata: { value: "70" }
    - type: cron                      # proaktif: sabah yoğunluğu öncesi
      metadata:
        timezone: Europe/Istanbul
        start: "45 8 * * 1-5"         # Pzt-Cuma 08:45 → 12 pod hazır
        end:   "0 11 * * 1-5"
        desiredReplicas: "12"
    - type: cron                      # öğle yoğunluğu
      metadata:
        timezone: Europe/Istanbul
        start: "45 11 * * 1-5"
        end:   "15 13 * * 1-5"
        desiredReplicas: "8"
```

```bash
kubectl delete hpa query-param-app -n app   # KEDA ile HPA çakışır
helm repo add kedacore https://kedacore.github.io/charts && helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace --wait
kubectl apply -f step3-manifests/hpa-scheduled.yaml
```

#### 3.2b: Node'ları Peak Öncesi Artırma (Cluster Autoscaler / Karpenter)

Pod'lar arttığında node yetmezse **Cluster Autoscaler** otomatik node ekler. "Sistemi
yavaşlatmadan peak öncesi" için iki teknik:

1. **Pause-pod / overprovisioning:** Düşük öncelikli "balon" pod'lar boş node'larda yer tutar.
   Gerçek pod gelince balon evict olur, yeni node hazır beklerken anında schedule edilir.
2. **Scheduled scaling of the node group:** KEDA Cron veya CronJob ile peak'ten 15 dk önce node
   grubu min-size'ı artırılır (cloud'da ASG/MIG desired count; bare-metal'de hazır node'u join et).

`step3-manifests/overprovisioning.yaml` (balon pod örneği):
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: overprovisioning }
value: -10                            # negatif → en önce evict edilir
globalDefault: false
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: overprovisioning, namespace: kube-system }
spec:
  replicas: 2
  selector: { matchLabels: { app: overprovisioning } }
  template:
    metadata: { labels: { app: overprovisioning } }
    spec:
      priorityClassName: overprovisioning
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.9
          resources:
            requests: { cpu: 300m, memory: 300Mi }   # node'da yer "rezerve eder"
```

**Cloud'da (AWS örneği):** Cluster Autoscaler EC2 Auto Scaling Group'u yönetir. Peak öncesi
scheduled action ile ASG `desired` artırılır → node'lar warm bekler → pod gelince anında yerleşir.
Bare-metal'de fiziksel node hazır tutulur ve peak öncesi `kubeadm join` ile cluster'a alınır.

> 💡 Yazılı yanıtı `docs/design-answers/step3-autoscaling.md` altına genişlet.

📖 KEDA Cron: https://keda.sh/docs/latest/scalers/cron/
📖 Cluster Autoscaler: https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler

---

### Step 3.3: Kritik Uygulama Deployment Stratejisi

#### Case Study Ne İstiyor?

> *"Critical application, new version could impact users.*
> *a. What deployment strategy would you use to minimize risk? Explain how it mitigates issues.*
> *b. Describe how you would implement a traffic shift from old to new version."*

#### Çözüm: Canary Deployment (ingress-nginx canary-weight)

Canary: yeni versiyona önce **%10 trafik** → metrikleri izle → sorun yoksa kademeli artır →
%100. Risk minimize, çünkü hata sadece kullanıcıların küçük kısmını etkiler; anında geri alınır.

`step3-manifests/canary-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: query-param-app-canary, namespace: app }
spec:
  replicas: 2
  selector: { matchLabels: { app: query-param-app-canary } }
  template:
    metadata: { labels: { app: query-param-app-canary } }
    spec:
      containers:
        - name: query-param-app
          image: dreamgames/query-param-app:2.0.0       # YENİ versiyon
          resources:
            requests: { cpu: 100m, memory: 128Mi }
---
apiVersion: v1
kind: Service
metadata: { name: query-param-app-canary, namespace: app }
spec:
  selector: { app: query-param-app-canary }
  ports: [{ port: 80, targetPort: 8080 }]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: query-param-app-canary
  namespace: app
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"     # %10 trafik
spec:
  ingressClassName: nginx
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: query-param-app-canary, port: { number: 80 } } }
```

```bash
kubectl apply -f step3-manifests/canary-deployment.yaml
# Grafana'da canary hata oranı/latency izle → sorun yoksa kademeli artır:
kubectl annotate ingress query-param-app-canary -n app --overwrite nginx.ingress.kubernetes.io/canary-weight=50
kubectl annotate ingress query-param-app-canary -n app --overwrite nginx.ingress.kubernetes.io/canary-weight=100
# Rollback: canary ingress'i sil → %100 eski versiyon
kubectl delete ingress query-param-app-canary -n app
```

> 💡 Alternatifler: Blue-Green (anlık geçiş, hızlı rollback) ve Argo Rollouts (otomatik
> analiz + progressive delivery). Yazılı yanıt: `docs/design-answers/step3-deployment-strategy.md`.

📖 Canary (ingress-nginx): https://kubernetes.github.io/ingress-nginx/examples/canary/

---

### Step 3.4: Replica Veritabanı Ölçekleme

#### Case Study Ne İstiyor?

> *"Higher traffic increases load on replica databases. Users should not experience high response times.*
> *a. How would you ensure the replica instances scale out and in before and after peak times?*
> *b. How would you integrate newly created databases with the application?*
> *c. Describe a method to pre-fill memory on the replica databases before traffic spikes.*
> Note: Only write the code and explain your approach."*

#### Yaklaşım + Kod

**3.4a — Replica'ları peak öncesi ölçekle:** KEDA Cron ile read-replica StatefulSet'i (veya cloud'da
RDS read replica sayısı) peak'ten önce artır, sonra düşür.

`step3-manifests/db-replica-scaledobject.yaml`:
```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: { name: pg-read-replica-scaler, namespace: data }
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: pg-read-replica
  minReplicaCount: 2
  maxReplicaCount: 6
  triggers:
    - type: cron
      metadata:
        timezone: Europe/Istanbul
        start: "30 8 * * 1-5"        # peak öncesi 08:30 → 6 replica
        end:   "0 11 * * 1-5"
        desiredReplicas: "6"
    - type: prometheus               # ayrıca read QPS yüksekse reaktif ölçekle
      metadata:
        serverAddress: http://kube-prometheus-stack-prometheus.monitoring:9090
        query: sum(rate(pg_stat_database_xact_commit{datname="app"}[2m]))
        threshold: "5000"
```

**3.4b — Yeni replica'yı uygulamaya bağla:** Uygulama tekil IP'lere değil, **read Service /
connection pooler**'a bağlanır. Yeni replica `role=read` label'ıyla ayağa kalkınca Service
endpoint'lerine otomatik girer; **PgBouncer/ProxySQL** read trafiğini dağıtır → uygulama kodu değişmez.

`step3-manifests/db-read-service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata: { name: pg-read, namespace: data }
spec:
  selector: { app: postgres, role: read }   # tüm read-replica'ları kapsar
  ports: [{ port: 5432, targetPort: 5432 }]
# Uygulama DB_READ_HOST=pg-read.data.svc.cluster.local kullanır → yeni replica otomatik dahil
```

**3.4c — Cache pre-warming (peak öncesi belleği doldur):** Yeni replica soğuk başlar (cache boş) →
ilk sorgular yavaş. Peak'ten önce sık kullanılan sorguları çalıştırıp page cache + buffer pool'u
ısıt. PostgreSQL'de `pg_prewarm` extension'ı ideal.

`step3-manifests/db-prewarm-cronjob.yaml`:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata: { name: pg-prewarm, namespace: data }
spec:
  schedule: "20 8 * * 1-5"           # peak'ten 40 dk önce ısıt
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: prewarm
              image: postgres:16-alpine
              env:
                - name: PGPASSWORD
                  valueFrom: { secretKeyRef: { name: pg-credentials, key: password } }
              command: ["/bin/sh","-c"]
              args:
                - |
                  psql -h pg-read.data.svc.cluster.local -U app -d app -c \
                    "CREATE EXTENSION IF NOT EXISTS pg_prewarm;
                     SELECT pg_prewarm('hot_table_1');
                     SELECT pg_prewarm('hot_index_1');"
                  # Alternatif: sık sorguları çalıştırıp buffer pool'u doldur
                  psql -h pg-read.data.svc.cluster.local -U app -d app -c \
                    "SELECT count(*) FROM leaderboard WHERE season='current';"
```

> 💡 Detaylı yazılı yanıt: `docs/design-answers/step3-database-scaling.md`.

📖 pg_prewarm: https://www.postgresql.org/docs/current/pgprewarm.html
📖 KEDA Prometheus scaler: https://keda.sh/docs/latest/scalers/prometheus/

---

## Step 4: Tasarım Soruları

> Bu bölüm yazılı tasarım soruları — kod değil, düşünce süreci değerlendirilir. Her yanıtı
> `docs/design-answers/` altına ekle.

### Step 4.1: macOS → Cloud CI/CD Migrasyonu

#### Case Study Ne İstiyor?

> *"On-premises macOS build machines for Unity iOS/Android builds via Jenkins; too many jobs queued.*
> *a. Plan to move CI/CD to the cloud.*
> *b. How to handle building artifacts; developers should easily install/test releases.*
> *c. Licensing challenges and solutions."*

`docs/design-answers/step4-cloud-cicd.md`:
```
a. Cloud'a taşıma planı:
   - AWS EC2 Mac instances (mac2.metal, Apple Silicon) → Unity iOS/Android build
     - Dedicated host (Apple lisans kuralı: min 24 saat kiralama)
   - Jenkins Kubernetes agent veya GitHub Actions Runner Controller (ARC):
     - Her build için ephemeral runner → biter bitmez silinir → kuyruk tıkanmaz, sınırsız paralel
   - Build cache: S3/EFS üzerinde paylaşımlı Unity Library cache → tekrar derleme hızlanır

b. Artifact dağıtımı:
   - iOS IPA → TestFlight; Android APK/AAB → Firebase App Distribution / Play Internal Testing
   - Geliştirici link/QR alır, cihazına anında kurar
   - Versiyonlama: immutable build numarası + git SHA

c. Lisans zorlukları:
   - Xcode sadece macOS → EC2 Mac zorunlu (dedicated host maliyeti yönetilir: peak'te aç, sonra kapat)
   - Unity: floating license server veya per-build lisans
   - Apple code signing sertifikaları → AWS Secrets Manager + fastlane match (şifreli repo/S3)
```

### Step 4.2: iOS Build Otomasyonu

#### Case Study Ne İstiyor?

> *"iOS builds involve repetitive steps (code signing, building, testing, archiving, App Store
> submission). Describe the ideal way to automate the iOS app development lifecycle."*

`docs/design-answers/step4-ios-automation.md`:
```
Çözüm: fastlane
  1. match    → code signing sertifika/profilleri şifreli merkezi depodan çek (CI'da MATCH_PASSWORD)
  2. gym      → Xcode build + IPA archive (gym(scheme:"MyApp", configuration:"Release"))
  3. scan     → unit/UI testleri; başarısızsa pipeline durur
  4. pilot    → TestFlight'a yükle + test gruplarına dağıt
  5. deliver  → App Store submission (metadata, screenshot dahil)

Pipeline tetikleyici:
  - Her PR        → scan (test)
  - main branch   → gym + pilot (TestFlight)
  - tag v*.*.*    → deliver (App Store)
Faydası: manuel, hataya açık adımlar tek komuta iner; tekrarlanabilir, denetlenebilir.
```

### Step 4.3: AWS Kubernetes Disaster Recovery

#### Case Study Ne İstiyor?

> *"Disaster recovery plan for a Kubernetes cluster on AWS.*
> *a. Steps to ensure the cluster can recover from a failure.*
> *b. Consider data persistence, backup/restoration, and configuration management."*

`docs/design-answers/step4-aws-dr.md`:
```
Hedefler: RTO < 1 saat, RPO < 15 dk

Katman 1 — Konfigürasyon (config management):
  - Tüm manifest'ler Git'te (GitOps) → ArgoCD/Flux yeni cluster'ı Git'ten reconcile eder
  - Terraform → EKS altyapısını IaC ile yeniden oluşturur

Katman 2 — Veri (persistence + backup):
  - Velero: K8s resource + PVC snapshot → S3, her 15 dk (RPO 15 dk), S3 CRR ile cross-region
  - RDS: Multi-AZ + cross-region read replica → disaster'da promote
  - ElastiCache: backup + cross-region replica

Katman 3 — DNS failover:
  - Route53 health check + failover policy: primary us-east-1, secondary eu-west-1 (warm standby)

Katman 4 — Recovery prosedürü:
  1. Terraform apply → yeni EKS (15-20 dk)
  2. ArgoCD/Flux → manifest deploy (10 dk)
  3. Velero restore → PVC'ler S3'ten (5-10 dk)
  4. RDS replica promote (2-5 dk)
  5. Route53 güncelle (60-300 sn)
  Toplam RTO ~30-45 dk ✓
```

📖 fastlane: https://fastlane.tools/
📖 Velero: https://velero.io/docs/

---

## Doğrulama ve Temizlik

### Tam Sistem Doğrulaması

```bash
# Cluster
kubectl get nodes -o wide                      # 3 node Ready
kubectl get pods -n app -o wide                # 4 pod, worker1+worker2 dağılımı

# Uygulama
curl 'http://app.example.com/api/echo?hello=world&foo=bar'

# HPA / PDB
kubectl describe hpa query-param-app -n app
kubectl get pdb -n app

# Jenkins Node 3 (faz çalışıyorsa)
kubectl get pod -n jenkins -o wide             # NODE = worker2

# Monitoring (faz çalışıyorsa)
curl -s 'http://monitoring.example.com/prometheus/-/healthy'

# Webhook (resource request eksik → reddedilmeli)
kubectl apply -n app -f - << 'EOF' 2>&1 | grep -i "denied\|webhook"
apiVersion: apps/v1
kind: Deployment
metadata: { name: webhook-test }
spec:
  replicas: 1
  selector: { matchLabels: { app: t } }
  template:
    metadata: { labels: { app: t } }
    spec: { containers: [{ name: nginx, image: nginx }] }
EOF
```

### Temizlik

```bash
# Faz bazlı (RAM boşalt)
helm uninstall jenkins -n jenkins
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall fluent-bit -n monitoring
kubectl delete elasticsearch elasticsearch -n monitoring

# Tüm ortamı sil
multipass delete master worker1 worker2 && multipass purge
unset KUBECONFIG && rm -f ~/.kube/config-dreamgames
sudo sed -i '' '/example.com/d' /etc/hosts        # macOS
```

---

## Kapsam Özeti

| Madde | Gereksinim | Durum |
|-------|-----------|-------|
| 1.1 | Java app, query params console'a | ✅ Spring Boot /api/echo |
| 1.2 | Multi-stage Dockerfile | ✅ 3 stage |
| 1.2a | Build acceleration | ✅ Layer caching (pom.xml önce) |
| 1.2b | Compact image | ✅ JRE-only Alpine |
| 1.2c | Security best practices | ✅ non-root, minimal base, Trivy |
| 1.3 | kubeadm cluster | ✅ Ansible + kubeadm (Multipass VM) |
| 1.3a | K8s 1.28+ | ✅ 1.32 |
| 1.3b | Custom subnets | ✅ 10.244.0.0/16, 10.96.0.0/12 |
| 1.3c | GitOps | ✅ Manifest'ler Git'te (ArgoCD ekle = tam) |
| 1.4 | ExternalDNS | ✅ CoreDNS provider + RBAC + Deployment |
| 1.4b | Otomatik DNS / manifest | ✅ --source=service |
| 1.5a | Jenkins Node 3 | ✅ nodeSelector: worker2 + PV nodeAffinity |
| 1.5b | JCasC | ✅ |
| 1.5c | Config persistence | ✅ PV Retain + PVC |
| 1.5d | LoadBalancer hostname | ✅ MetalLB + Ingress |
| 1.6 | Prometheus+ES+Grafana+fluentbit+AlertManager | ✅ |
| 1.6a | K8s + app dashboard | ✅ 2 dashboard |
| 1.6b | Pod restart alert | ✅ PodRestarted/PodCrashLooping |
| 1.6c | Single hostname paths | ✅ /grafana /prometheus /elasticsearch |
| 1.6d | Logs → Elasticsearch | ✅ Fluent Bit |
| 1.7a | Async file logging | ✅ AsyncAppender |
| 1.7b | Max 1GB | ✅ SizeAndTimeBasedRollingPolicy |
| 1.7c | Daily rotation | ✅ |
| 2.1 | 4 pod, both workers, Nginx LB | ✅ |
| 2.1a | Even distribution | ✅ topologySpreadConstraints |
| 2.1b | Ready'de trafik + auto-restart | ✅ startup/readiness/liveness |
| 2.2 | Build pipeline | ✅ Trivy + immutable tag |
| 2.2a | Image → registry | ✅ DockerHub push |
| 2.3a | **Ansible** apply manifests | ✅ Jenkinsfile.deploy + deploy-app.yml |
| 2.3b | Ingress hostname | ✅ |
| 2.3c | Zero-downtime | ✅ maxUnavailable:0 + probes |
| 2.4 | Validation webhook | ✅ Go, resource request kontrol |
| 2.4a | **ConfigMap** namespaces | ✅ volume mount |
| 2.4b | Prometheus metrics | ✅ :8080 /metrics |
| 3.1 | App X/Y kaynak yönetimi | ✅ PriorityClass + QoS + manifest |
| 3.2a | Zamanlı scale-out/in | ✅ KEDA Cron |
| 3.2b | Peak öncesi node artırma | ✅ Cluster Autoscaler + overprovisioning |
| 3.3 | Risk azaltan deployment | ✅ Canary (+ blue-green/argo notu) |
| 3.4 | DB replica scaling | ✅ KEDA + read Service + pg_prewarm |
| 4.1 | Cloud CI/CD plan | ✅ design-answers |
| 4.2 | iOS automation | ✅ fastlane |
| 4.3 | AWS K8s DR | ✅ Velero+Route53+Terraform |

**Tahmini kapsama: ~95%.** Kalan: tam GitOps (ArgoCD/Flux live), gerçek cloud node autoscaler
(bare-metal'de simüle edildi) — ikisi de "highly desirable", zorunlu değil.

---

## Referanslar

| Araç | Dokümantasyon |
|------|--------------|
| Multipass | https://multipass.run/docs |
| kubeadm | https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ |
| Calico | https://docs.tigera.io/calico/latest/ |
| MetalLB | https://metallb.universe.tf/ |
| Ingress-NGINX | https://kubernetes.github.io/ingress-nginx/ |
| ExternalDNS | https://github.com/kubernetes-sigs/external-dns |
| Jenkins Helm | https://www.jenkins.io/doc/book/installing/kubernetes/ |
| JCasC | https://www.jenkins.io/projects/jcasc/ |
| kube-prometheus-stack | https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack |
| ECK | https://www.elastic.co/guide/en/cloud-on-k8s/current/ |
| Fluent Bit | https://docs.fluentbit.io/manual/ |
| Trivy | https://aquasecurity.github.io/trivy/ |
| KEDA | https://keda.sh/docs/latest/ |
| Cluster Autoscaler | https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler |
| Admission Webhooks | https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/ |
| PriorityClass | https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/ |
| pg_prewarm | https://www.postgresql.org/docs/current/pgprewarm.html |
| fastlane | https://fastlane.tools/ |
| Velero | https://velero.io/docs/ |
