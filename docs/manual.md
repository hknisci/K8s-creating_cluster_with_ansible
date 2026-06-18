# Dream Games DevOps Case Study — Sıfırdan Çözüm Rehberi

> **Hedef kitle:** 5-6 yıllık DevOps deneyimi. Her adımda **"Case study ne istiyor?"** →
> **"Neden böyle yaptık?"** → **"Nasıl yapılır?"** akışı izlenir.
>
> **MacBook Air M4 (Apple Silicon) uyumludur.** VirtualBox M-serisi Mac'te çalışmaz.
> Bu rehber OrbStack Machines + Ansible + kubeadm kullanır — case study'nin beklediği
> production-grade yaklaşım, M4 uyumlu VM sağlayıcısıyla.
>
> ⚠️ **Güvenlik:** Şifre, token, Slack webhook, cloud credential asla dosyaya yazılmaz.
> Tüm secret'lar `kubectl create secret` veya environment variable ile yönetilir.
>
> ⚠️ **k3d/k3s KULLANMA:** Case study açıkça "Avoid tools like kind, minikube, or k3s"
> diyor. k3d = K3s in Docker → elenme sebebi. Bu rehber kubeadm kullanır.

---

## İçindekiler

- [Bölüm 0 — Case Study Analizi ve Araçlar](#bölüm-0--case-study-analizi-ve-araçlar)
- [Bölüm 1 — Kendi Repo'nu Oluştur](#bölüm-1--kendi-repoyu-oluştur)
- [Bölüm 2 — Kubernetes Cluster (M4 Mac + kubeadm)](#bölüm-2--kubernetes-cluster-m4-mac--kubeadm)
- [Bölüm 3 — Network Altyapısı](#bölüm-3--network-altyapısı)
- [Bölüm 4 — Uygulama ve Dockerfile](#bölüm-4--uygulama-ve-dockerfile)
- [Bölüm 5 — Kubernetes Kaynakları](#bölüm-5--kubernetes-kaynakları)
- [Bölüm 6 — Jenkins CI/CD](#bölüm-6--jenkins-cicd)
- [Bölüm 7 — Monitoring Stack](#bölüm-7--monitoring-stack)
- [Bölüm 8 — Log Aggregation](#bölüm-8--log-aggregation)
- [Bölüm 9 — Admission Webhook](#bölüm-9--admission-webhook)
- [Bölüm 10 — İleri Senaryolar (Step 3)](#bölüm-10--i̇leri-senaryolar-step-3)
- [Bölüm 11 — Tasarım Soruları (Step 4)](#bölüm-11--tasarım-soruları-step-4)
- [Bölüm 12 — Doğrulama ve Temizlik](#bölüm-12--doğrulama-ve-temizlik)

---

## Bölüm 0 — Case Study Analizi ve Araçlar

### Case Study Neyi Değerlendiriyor?

```
Notes (PDF'den):
  - Creating a production-ready Kubernetes cluster
  - Platform deployments (Jenkins, Prometheus, Elasticsearch, Grafana) via Helm/Operator/manifest
  - Application build stages
  - Application deployment stages, including Ansible configurations
```

| Step | Gereksinim | Çözüm |
|------|-----------|-------|
| Step 1 | Java app + Dockerfile + K8s cluster + ExternalDNS + Jenkins + Monitoring + Async log | Bölüm 2–8 |
| Step 2 | 4 pod HA + Build pipeline + **Ansible deploy pipeline** + Webhook | Bölüm 5–9 |
| Step 3 | PriorityClass + KEDA + Canary + DB scaling | Bölüm 10 |
| Step 4 | Cloud CI/CD + iOS automation + K8s DR | Bölüm 11 |

### M4 Mac için K8s Cluster Seçimi

**k3d/k3s → YASAK.** Case study:
> *"Avoid using tools like kind, minikube, or k3s"*

k3d = K3s in Docker. Kullanılırsa direkt elenirsin.

**Doğru yaklaşım:** OrbStack Machines → 3 Ubuntu 22.04 VM → kubeadm
- OrbStack, Apple Virtualization framework üzerinde native ARM64 VM çalıştırır
- VirtualBox'ın yaptığını yapar, M4'te çalışır
- Üstünde kubeadm tam çalışır → production-grade cluster
- Ansible playbook'lar aynı — sadece VM sağlayıcı değişti

### Gerekli Araçlar

```bash
# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# OrbStack (VM + Docker, M4 native)
brew install --cask orbstack
# Kurulumdan sonra OrbStack uygulamasını aç, ilk kurulumu tamamla

# K8s araçları
brew install kubectl helm ansible

# Java (uygulama için)
brew install --cask temurin@21    # OpenJDK 21
brew install maven

# İsteğe bağlı
brew install k9s    # Terminal K8s UI
```

Versiyon kontrolü:
```bash
kubectl version --client   # v1.28+
helm version               # v3.14+
ansible --version          # 2.15+
java -version              # 21+
mvn -version               # 3.9+
```

📖 OrbStack: https://orbstack.dev
📖 kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/
📖 Ansible: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html

---

## Bölüm 1 — Kendi Repo'nu Oluştur

### Adım 1: Git Repo ve Dizin Yapısı

```bash
mkdir dreamgames-case && cd dreamgames-case
git init
git branch -M main

mkdir -p app/src/main/{java/com/dreamgames/{controller,filter},resources}
mkdir -p ansible/roles/{common,containerd,kubeadm,master,worker}/{tasks,templates,handlers}
mkdir -p ansible/{group_vars,inventory}
mkdir -p kubernetes/{namespaces,app,jenkins,webhook/tls,metallb,ingress-nginx}
mkdir -p kubernetes/monitoring/{grafana-dashboards,elasticsearch,fluent-bit}
mkdir -p kubernetes/externaldns
mkdir -p jenkins
mkdir -p step3-manifests
mkdir -p docs/design-answers
mkdir -p webhook

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

Dizin yapısı ve mantığı:
```
dreamgames-case/
├── app/                    # Spring Boot uygulaması
├── ansible/                # K8s cluster kurulum + deploy playbook'ları
├── kubernetes/             # Tüm K8s manifest'leri (GitOps yaklaşımı)
│   ├── app/                # Deployment, Service, Ingress, HPA, PDB, NetworkPolicy
│   ├── jenkins/            # Jenkins PV, Helm values (Node 3 pin'li)
│   ├── monitoring/         # kube-prometheus-stack + alerting + dashboards
│   └── webhook/            # Admission webhook kaynakları
├── jenkins/                # Jenkinsfile.build, Jenkinsfile.deploy (Ansible çağırır)
├── step3-manifests/        # KEDA, Canary, PriorityClass
└── docs/design-answers/    # Step 3-4 tasarım soruları yazılı yanıtlar
```

**GitOps Yaklaşımı:** Tüm manifest'ler Git'te. Değişiklik → `git push` → Ansible veya Jenkins deploy eder. ArgoCD gibi bir tool eklersen tam GitOps olur — case study bunu "highly desirable" olarak belirtmiş, eklemen puan kazandırır.

### Adım 2: GitHub'a Push

```bash
echo "# Dream Games DevOps Case Study" > README.md
git add .
git commit -m "chore: initial project structure"
git remote add origin https://github.com/<kullanici>/dreamgames-case.git
git push -u origin main
```

---

## Bölüm 2 — Kubernetes Cluster (M4 Mac + kubeadm)

### Case Study Ne İstiyor?

> *"Set up a production-ready Kubernetes cluster using tools like Kubeadm, Kubespray, or similar."*
> *"Avoid using tools like kind, minikube, or k3s"*
> *"Kubernetes version 1.28 or higher"*
> *"Use custom subnets of your choice for Pod and Service"*

### Neden OrbStack Machines + kubeadm?

Vagrant + VirtualBox = case study'nin beklediği ortam. M4 Mac'te VirtualBox çalışmaz.
OrbStack Machines = VirtualBox'ın yaptığını Apple Virtualization framework ile yapar.
kubeadm = production-grade cluster kurucusu (case study'nin istediği).
Ansible = "Ansible configurations" istiyor zaten case study.

Bu kombinasyon case study'nin tüm beklentilerini M4'te karşılar.

### Adım 3: OrbStack ile VM'ler Oluştur

OrbStack uygulamasını aç → "Machines" sekmesi → veya CLI ile:

```bash
# 3 Ubuntu 22.04 VM oluştur
orb create ubuntu:22.04 master   --memory 2048 --cpu 2
orb create ubuntu:22.04 worker1  --memory 2048 --cpu 2
orb create ubuntu:22.04 worker2  --memory 2048 --cpu 2

# VM'lerin IP adreslerini al
orb ip master    # örnek: 198.19.249.10
orb ip worker1   # örnek: 198.19.249.11
orb ip worker2   # örnek: 198.19.249.12

# SSH erişimini test et
ssh orb@master "hostname && uname -m"
# Beklenen: master, aarch64
```

📖 OrbStack Machines: https://docs.orbstack.dev/machines/

### Adım 4: Ansible Inventory ve group_vars

`ansible/inventory/hosts.ini`:
```ini
[master]
master  ansible_host=198.19.249.10  ansible_user=orb  ansible_ssh_private_key_file=~/.orbstack/id_ed25519

[workers]
worker1 ansible_host=198.19.249.11  ansible_user=orb  ansible_ssh_private_key_file=~/.orbstack/id_ed25519
worker2 ansible_host=198.19.249.12  ansible_user=orb  ansible_ssh_private_key_file=~/.orbstack/id_ed25519

[all:children]
master
workers
```

> OrbStack VM'lerin IP'lerini `orb ip <vm-adı>` ile al, yukarıdaki örnek değerleri değiştir.

`ansible/group_vars/all.yml`:
```yaml
kubernetes_version: "1.32"
containerd_version: "1.7.23"
calico_version: "v3.29.1"

# Case study: custom subnets (default'lardan farklı seçildi)
pod_cidr: "10.244.0.0/16"      # Calico default, özelleştirilebilir
service_cidr: "10.96.0.0/12"   # kubeadm default, özelleştirilebilir

# Cluster endpoint (master VM IP)
master_ip: "198.19.249.10"
api_server_endpoint: "{{ master_ip }}:6443"
```

**Neden custom subnet?**
Case study bunu özellikle istiyor. Pod CIDR, container'ların birbirleriyle konuştuğu ağ.
Service CIDR, ClusterIP Service'lerin IP'leri buradan alınır. Default değerleri değiştirmek
"bu kişi sadece copy-paste yapmıyor, cluster ağını anlıyor" mesajı verir.

### Adım 5: Ansible Rolleri

`ansible/site.yml`:
```yaml
---
- name: Common setup (tüm node'lar)
  hosts: all
  become: true
  roles:
    - common
    - containerd

- name: kubeadm kurulumu (tüm node'lar)
  hosts: all
  become: true
  roles:
    - kubeadm

- name: Master node init
  hosts: master
  become: true
  roles:
    - master

- name: Worker node join
  hosts: workers
  become: true
  roles:
    - worker
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

- name: Kernel modülleri yükle (containerd için)
  modprobe:
    name: "{{ item }}"
  loop:
    - overlay
    - br_netfilter

- name: Kalıcı modül konfigürasyonu
  copy:
    dest: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

- name: Sysctl parametreleri (K8s networking için)
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
    name: "containerd={{ containerd_version }}*"
    state: present
    update_cache: true

- name: containerd config dizini
  file:
    path: /etc/containerd
    state: directory

- name: Default config oluştur
  shell: containerd config default > /etc/containerd/config.toml

- name: SystemdCgroup aktif et (kubeadm gereksinimi)
  replace:
    path: /etc/containerd/config.toml
    regexp: 'SystemdCgroup = false'
    replace: 'SystemdCgroup = true'
  notify: restart containerd

- name: containerd'yi başlat
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
- name: Kubernetes apt key ekle
  apt_key:
    url: https://pkgs.k8s.io/core:/stable:/v{{ kubernetes_version }}/deb/Release.key
    state: present

- name: Kubernetes repo ekle
  apt_repository:
    repo: "deb https://pkgs.k8s.io/core:/stable:/v{{ kubernetes_version }}/deb/ /"
    state: present

- name: kubeadm, kubelet, kubectl kur
  apt:
    name:
      - "kubeadm"
      - "kubelet"
      - "kubectl"
    state: present
    update_cache: true

- name: Paketleri hold et (otomatik upgrade'i engelle)
  dpkg_selections:
    name: "{{ item }}"
    selection: hold
  loop:
    - kubeadm
    - kubelet
    - kubectl
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

- name: kubeadm init
  command: kubeadm init --config=/tmp/kubeadm-config.yaml --upload-certs
  when: not kubeconfig_exists.stat.exists
  register: kubeadm_output

- name: .kube dizini oluştur
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

- name: Join command'ı dosyaya yaz (worker'lar okuyacak)
  copy:
    content: "{{ join_command.stdout }}"
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
  podSubnet: "{{ pod_cidr }}"       # Custom subnet — case study gereksinimi
  serviceSubnet: "{{ service_cidr }}"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd    # containerd'nin SystemdCgroup ayarıyla eşleşmeli
```

`ansible/roles/worker/tasks/main.yml`:
```yaml
---
- name: Join command al
  fetch:
    src: /tmp/join-command.sh
    dest: /tmp/join-command.sh
    flat: true
  delegate_to: "{{ groups['master'][0] }}"

- name: Worker olarak cluster'a katıl
  command: bash /tmp/join-command.sh
  args:
    creates: /etc/kubernetes/kubelet.conf
```

### Adım 6: Cluster'ı Kur

```bash
# Bağlantıyı test et
ansible all -i ansible/inventory/hosts.ini -m ping

# Cluster'ı kur (~10-15 dakika)
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml -v

# kubeconfig'i yerel makineye kopyala
ssh orb@master "cat ~/.kube/config" > ~/.kube/config-dreamgames
export KUBECONFIG=~/.kube/config-dreamgames
echo "export KUBECONFIG=~/.kube/config-dreamgames" >> ~/.zshrc

# Doğrula
kubectl get nodes -o wide
```

Beklenen çıktı:
```
NAME      STATUS   ROLES           AGE   VERSION   INTERNAL-IP
master    Ready    control-plane   5m    v1.32.x   198.19.249.10
worker1   Ready    <none>          3m    v1.32.x   198.19.249.11
worker2   Ready    <none>          3m    v1.32.x   198.19.249.12
```

### Adım 7: Metrics Server (HPA için)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# 30 saniye bekle
kubectl top nodes
```

📖 kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
📖 Calico: https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/

---

## Bölüm 3 — Network Altyapısı

### Adım 8: MetalLB (Bare-metal LoadBalancer)

Case study'de Vagrant cluster'ı için LoadBalancer tipi Service'lere IP atanması gerekir.
MetalLB bu boşluğu doldurur.

`kubernetes/metallb/ipaddresspool.yaml`:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: local-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.56.200-192.168.56.220   # Vagrant/OrbStack private network aralığında
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: local-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - local-pool
```

> OrbStack VM'lerde IP aralığını `orb ip master` çıktısına göre ayarla. Örnek:
> `198.19.249.200-198.19.249.220`

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm install metallb metallb/metallb -n metallb-system --create-namespace --wait --timeout 3m
kubectl apply -f kubernetes/metallb/ipaddresspool.yaml
```

📖 MetalLB: https://metallb.universe.tf/

### Adım 9: Ingress-NGINX

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
```

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f kubernetes/ingress-nginx/values.yaml \
  --wait --timeout 3m

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"

# /etc/hosts
echo "$INGRESS_IP  app.example.com monitoring.example.com jenkins.example.com" \
  | sudo tee -a /etc/hosts
```

### Adım 10: ExternalDNS

Case study: *"Deploy ExternalDNS. Ensure that the DNS name is automatically created for the newly created service objects."*

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
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
        - name: external-dns
          image: registry.k8s.io/external-dns/external-dns:v0.14.0
          args:
            - --source=service
            - --source=ingress
            - --provider=coredns     # Cluster-internal CoreDNS (local kurulum için)
            - --registry=txt
            - --txt-owner-id=dreamgames
          env:
            - name: ETCD_URLS
              value: "http://etcd-dreamgames.kube-system.svc.cluster.local:2379"
```

> **Local cluster için neden CoreDNS provider?**
> AWS/GCP'de Route53/Cloud DNS kullanılır. Local cluster'da CoreDNS RFC2136 provider,
> cluster-internal DNS kayıtlarını otomatik yönetir. Cloud ortamında provider değişir,
> manifest yapısı aynı kalır.

📖 ExternalDNS: https://github.com/kubernetes-sigs/external-dns
📖 CoreDNS provider: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/coredns.md

```bash
kubectl apply -f kubernetes/externaldns/rbac.yaml
kubectl apply -f kubernetes/externaldns/deployment.yaml
```

---

## Bölüm 4 — Uygulama ve Dockerfile

### Case Study Ne İstiyor?

> *"You can either use an existing Java project, such as sample-java-app, or develop a new
> Java application from scratch that prints the query string parameters of the service
> endpoint to the console."*

Java projesi kullanıyoruz — case study bunu açıkça izin veriyor.

### Adım 11: Spring Boot Uygulaması

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
      show-details: when-authorized

spring:
  application:
    name: query-param-app
```

### Adım 12: Async Logging (Step 1.7)

Case study: *"Write application logs to a file asynchronously. Ensure the log file size does not exceed 1GB. Rotate log files daily."*

`app/src/main/resources/logback-spring.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <!-- Async olmayan appender: dosyaya yaz -->
  <appender name="FILE_SYNC" class="ch.qos.logback.core.rolling.RollingFileAppender">
    <file>/app/logs/application.log</file>
    <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
      <!-- Günlük rotation + boyut limiti — case study 7b ve 7c -->
      <fileNamePattern>/app/logs/application.%d{yyyy-MM-dd}.%i.log.gz</fileNamePattern>
      <maxFileSize>1GB</maxFileSize>     <!-- 1GB'ı geçince yeni dosya aç -->
      <maxHistory>30</maxHistory>         <!-- 30 gün sakla -->
      <totalSizeCap>10GB</totalSizeCap>   <!-- toplam disk kullanımı -->
    </rollingPolicy>
    <!-- JSON format — Fluent Bit'in parse etmesi için -->
    <encoder class="net.logstash.logback.encoder.LogstashEncoder"/>
  </appender>

  <!-- AsyncAppender: log yazma işlemi ayrı thread'de — case study 7a -->
  <!-- Ana thread bloklanmaz → yüksek yük altında performans korunur -->
  <appender name="FILE_ASYNC" class="ch.qos.logback.classic.AsyncAppender">
    <queueSize>1024</queueSize>
    <discardingThreshold>0</discardingThreshold>   <!-- kuyrukte yer yoksa at değil bekle -->
    <appender-ref ref="FILE_SYNC"/>
  </appender>

  <!-- stdout appender (Kubernetes log driver için) -->
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder class="net.logstash.logback.encoder.LogstashEncoder"/>
  </appender>

  <root level="INFO">
    <appender-ref ref="FILE_ASYNC"/>
    <appender-ref ref="STDOUT"/>
  </root>
</configuration>
```

**Neden AsyncAppender?**

Senkron log yazma: her log satırında dosya I/O bekler. Yüksek trafikte bu gecikmeye neden olur.
AsyncAppender: log mesajları bir kuyruğa (1024 mesaj kapasiteli) yazılır, ayrı bir thread dosyaya yazar.
Ana uygulama thread'i bloklanmaz → response time düşer.

📖 Logback AsyncAppender: https://logback.qos.ch/manual/appenders.html#AsyncAppender
📖 Logstash Encoder: https://github.com/logfellow/logstash-logback-encoder

### Adım 13: Dockerfile (Multi-stage)

`app/Dockerfile`:
```dockerfile
# Stage 1: Bağımlılıkları önbelleğe al
# Sadece pom.xml kopyalanır → bağımlılıklar değişmedikçe bu katman cache'den gelir
# → Sonraki build'ler çok daha hızlı (build acceleration — case study 2a)
FROM maven:3.9-eclipse-temurin-21-alpine AS deps
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q

# Stage 2: JAR derle
FROM deps AS builder
COPY src/ ./src/
RUN mvn clean package -DskipTests -q

# Stage 3: Minimal runtime image
# JRE-only Alpine: JDK yok, compiler yok, Maven yok → küçük imaj (case study 2b)
FROM eclipse-temurin:21-jre-alpine AS runtime

# Non-root user (case study 2c — security best practice)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

WORKDIR /app

# Uygulama log dizini
RUN mkdir -p /app/logs

COPY --from=builder /app/target/*.jar app.jar

EXPOSE 8080 9090

# -XX:MaxRAMPercentage: container belleğinin %75'i heap → sabit değer yerine dinamik
# -Djava.security.egd: daha hızlı JVM başlangıcı (SecureRandom için)
ENTRYPOINT ["java", \
  "-XX:MaxRAMPercentage=75.0", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-jar", "app.jar"]
```

### Adım 14: Local Test

```bash
cd app
mvn clean package -DskipTests
docker build -t dreamgames/query-param-app:1.0.0 .
docker run --rm -p 8080:8080 -p 9090:9090 dreamgames/query-param-app:1.0.0

# Test
curl 'http://localhost:8080/api/echo?hello=world&foo=bar'
# Beklenen: {"hello":"world","foo":"bar"}

curl 'http://localhost:9090/actuator/health'
# Beklenen: {"status":"UP"}

curl 'http://localhost:9090/actuator/prometheus' | grep echo
# Beklenen: http_server_requests_seconds_count

docker push dreamgames/query-param-app:1.0.0
cd ..
```

---

## Bölüm 5 — Kubernetes Kaynakları

### Adım 15: Namespace'ler ve Pod Security Admission

`kubernetes/namespaces/namespaces.yaml`:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    # restricted: root çalışma, privilege escalation, host network yasak
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    # node-exporter hostNetwork gerektirir → baseline
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: restricted
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

```bash
kubectl apply -f kubernetes/namespaces/namespaces.yaml
```

### Adım 16: Deployment

`kubernetes/app/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: query-param-app
  namespace: app
spec:
  replicas: 4    # Case study: minimum 4 pod
  selector:
    matchLabels:
      app: query-param-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0    # Sıfır kesintili güncelleme — case study Step 2.3c
  template:
    metadata:
      labels:
        app: query-param-app
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
        prometheus.io/path: "/actuator/prometheus"
    spec:
      serviceAccountName: query-param-app
      # Pod'ları worker1 ve worker2'ye dağıt — case study Step 2.1a
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: query-param-app
      containers:
        - name: query-param-app
          image: dreamgames/query-param-app:1.0.0
          ports:
            - containerPort: 8080
              name: http
            - containerPort: 9090
              name: management
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 512Mi
          # readinessProbe: hazır olana kadar trafik gelmesin — case study Step 2.1b
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 9090
            initialDelaySeconds: 30
            periodSeconds: 5
            failureThreshold: 3
          # livenessProbe: cevap vermezse yeniden başlat — case study Step 2.1b
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 9090
            initialDelaySeconds: 60
            periodSeconds: 10
            failureThreshold: 3
          # preStop: terminate sinyalinden önce 5 sn bekle → uçuştaki istekler tamamlanır
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 5"]
          volumeMounts:
            - name: logs
              mountPath: /app/logs
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false    # log dizini yazılabilir olmalı
            capabilities:
              drop: ["ALL"]
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      volumes:
        - name: logs
          emptyDir: {}
```

### Adım 17: Service, HPA, PDB

`kubernetes/app/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: query-param-app
  namespace: app
spec:
  selector:
    app: query-param-app
  ports:
    - name: http
      port: 80
      targetPort: 8080
    - name: management
      port: 9090
      targetPort: 9090
```

`kubernetes/app/hpa.yaml`:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: query-param-app
  namespace: app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: query-param-app
  minReplicas: 4
  maxReplicas: 16
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300    # 5 dk: ani ölçek küçültmesini engelle
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
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
    matchLabels:
      app: query-param-app
  maxUnavailable: 1    # kubectl drain: aynı anda en fazla 1 pod kaldır
```

`kubernetes/app/ingress.yaml`:
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
            backend:
              service:
                name: query-param-app
                port:
                  number: 80
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
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: query-param-app-allow
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: query-param-app
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - port: 8080
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - port: 9090
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

### Adım 18: Deploy Et

```bash
kubectl apply -f kubernetes/app/

kubectl rollout status deployment/query-param-app -n app --timeout=120s
kubectl get pods -n app -o wide   # worker1 ve worker2'ye dağılmış mı?

# Smoke test
curl 'http://app.example.com/api/echo?hello=world'
# Beklenen: {"hello":"world"}
```

---

## Bölüm 6 — Jenkins CI/CD

### Case Study Ne İstiyor?

> *"Jenkins should be installed exclusively on Node 3."*
> *"Configuring Jenkins using a 'configuration as code' approach is preferred."*
> *"Configuration of Jenkins should persist across restarts or upgrades."*
> *"Use Ansible to apply Kubernetes manifests."* ← deploy pipeline için kritik!

### Adım 19: Jenkins PV (Node 3 Pin)

Jenkins'in worker2 (Node 3) üzerinde çalışması için PersistentVolume + nodeAffinity:

`kubernetes/jenkins/pv.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jenkins-pv
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/jenkins
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - worker2    # Node 3 = worker2
```

```bash
# worker2 üzerinde dizin oluştur
ssh orb@worker2 "sudo mkdir -p /mnt/jenkins && sudo chown 1000:1000 /mnt/jenkins"

kubectl apply -f kubernetes/jenkins/pv.yaml
```

### Adım 20: Jenkins Secrets

```bash
kubectl create namespace jenkins

# DockerHub token: https://hub.docker.com/settings/security → New Access Token
# GitHub token: https://github.com/settings/tokens
kubectl create secret generic jenkins-credentials \
  --from-literal=admin-password="$(openssl rand -base64 24)" \
  --from-literal=dockerhub-user=<DOCKERHUB_KULLANICI> \
  --from-literal=dockerhub-token=<DOCKERHUB_TOKEN> \
  --from-literal=github-token=<GITHUB_TOKEN> \
  -n jenkins
```

> ⚠️ Token değerlerini terminale girmeden önce şifre yöneticisinden kopyala.
> Girdikten sonra `history -c` ile terminal geçmişini temizle.

### Adım 21: Jenkins Helm Values

`kubernetes/jenkins/values.yaml`:
```yaml
controller:
  # Node 3 (worker2) üzerine pin — case study gereksinimi
  nodeSelector:
    kubernetes.io/hostname: worker2

  ingress:
    enabled: true
    hostName: jenkins.example.com
    ingressClassName: nginx

  # JCasC — case study: "configuration as code approach is preferred"
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
                      description: "Docker Hub"
                  - string:
                      scope: GLOBAL
                      id: "github-token"
                      secret: ${GITHUB_TOKEN}

  containerEnv:
    - name: DOCKERHUB_USER
      valueFrom:
        secretKeyRef:
          name: jenkins-credentials
          key: dockerhub-user
    - name: DOCKERHUB_TOKEN
      valueFrom:
        secretKeyRef:
          name: jenkins-credentials
          key: dockerhub-token
    - name: GITHUB_TOKEN
      valueFrom:
        secretKeyRef:
          name: jenkins-credentials
          key: github-token

  adminSecret: false
  existingSecret: jenkins-credentials
  existingSecretKey: admin-password

  installPlugins:
    - git:latest
    - workflow-aggregator:latest
    - docker-workflow:latest
    - kubernetes:latest
    - ansible:latest    # Ansible pipeline adımları için

# Config persistence — case study: "persist across restarts or upgrades"
persistence:
  enabled: true
  storageClass: local-storage
  size: 20Gi
```

```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update
helm install jenkins jenkins/jenkins -n jenkins \
  -f kubernetes/jenkins/values.yaml \
  --wait --timeout 5m
```

**Neden nodeSelector: worker2?**

Case study "Jenkins should be installed exclusively on Node 3" diyor. Node 3 = worker2
(Vagrantfile'da 3. VM). nodeSelector ile Kubernetes bu pod'u sadece worker2'ye schedule
eder. PV de nodeAffinity ile worker2'ye bağlı → Jenkins pod + veri her zaman aynı node'da.

### Adım 22: Build Pipeline

`jenkins/Jenkinsfile.build`:
```groovy
pipeline {
    agent any
    environment {
        REGISTRY   = "docker.io"
        IMAGE_NAME = "dreamgames/query-param-app"
        // :latest KULLANMA — mutable tag, hangi kod çalıştığı bilinmez
        IMAGE_TAG  = "${BUILD_NUMBER}-${GIT_COMMIT.take(7)}"
    }
    stages {
        stage('Checkout') {
            steps { checkout scm }
        }
        stage('Unit Test') {
            steps {
                dir('app') {
                    sh 'mvn clean test -q'
                }
            }
        }
        stage('Build JAR') {
            steps {
                dir('app') {
                    sh 'mvn clean package -DskipTests -q'
                }
            }
        }
        stage('Build Image') {
            steps {
                dir('app') {
                    sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                }
            }
        }
        stage('Security Scan') {
            // Trivy: HIGH/CRITICAL CVE varsa pipeline durur, imaj push edilmez
            steps {
                sh """
                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image \
                      --exit-code 1 --severity HIGH,CRITICAL \
                      --no-progress \
                      ${IMAGE_NAME}:${IMAGE_TAG}
                """
            }
        }
        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh """
                        echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker logout
                    """
                }
            }
        }
        stage('Tag Git') {
            steps {
                sh "git tag v${IMAGE_TAG} && git push origin v${IMAGE_TAG} || true"
            }
        }
    }
    post {
        always {
            sh "docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true"
        }
    }
}
```

### Adım 23: Deploy Pipeline (Ansible ile)

Case study: **"Use Ansible to apply Kubernetes manifests."** — Bu kritik bir gereksinim.
`kubectl apply` değil, Ansible kullanılmalı.

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
    - name: Deployment'ı güncelle
      kubernetes.core.k8s:
        state: present
        definition:
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: query-param-app
            namespace: "{{ app_namespace }}"
          spec:
            template:
              spec:
                containers:
                  - name: query-param-app
                    image: "{{ docker_user }}/query-param-app:{{ image_tag }}"

    - name: Rollout status kontrol
      command: >
        kubectl rollout status deployment/query-param-app
        -n {{ app_namespace }}
        --timeout=5m
      register: rollout_result
      failed_when: rollout_result.rc != 0

    - name: Rollback (rollout başarısız olduysa)
      command: kubectl rollout undo deployment/query-param-app -n {{ app_namespace }}
      when: rollout_result.rc != 0
```

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
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
  - name: kubectl
    image: bitnami/kubectl:1.28
    command: ['sleep', '99d']
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
"""
        }
    }
    parameters {
        string(name: 'IMAGE_TAG',   description: 'Deploy edilecek tag (örn: 42-abc1234)')
        choice(name: 'ENVIRONMENT', choices: ['app', 'staging'], description: 'Target namespace')
        booleanParam(name: 'DRY_RUN', defaultValue: false, description: 'Dry-run modu')
    }
    environment {
        KUBECONFIG = credentials('kubeconfig')
    }
    stages {
        stage('Checkout') {
            steps { checkout scm }
        }
        stage('Validate Manifests') {
            steps {
                container('kubectl') {
                    sh """
                        kubectl apply -f kubernetes/app/ \
                          --dry-run=client \
                          --namespace=${params.ENVIRONMENT}
                    """
                }
            }
        }
        stage('Deploy via Ansible') {
            // Case study: "Use Ansible to apply Kubernetes manifests"
            steps {
                container('ansible') {
                    sh """
                        ansible-playbook ansible/deploy-app.yml \
                          -i ansible/inventory/hosts.ini \
                          -e image_tag=${params.IMAGE_TAG} \
                          -e docker_user=dreamgames \
                          -e app_namespace=${params.ENVIRONMENT} \
                          ${params.DRY_RUN ? '--check' : ''}
                    """
                }
            }
        }
        stage('Verify Rollout') {
            when { not { expression { params.DRY_RUN } } }
            steps {
                container('kubectl') {
                    sh """
                        kubectl rollout status deployment/query-param-app \
                          -n ${params.ENVIRONMENT} --timeout=5m
                        kubectl get pods -n ${params.ENVIRONMENT} -o wide
                    """
                }
            }
        }
        stage('Smoke Test') {
            when { not { expression { params.DRY_RUN } } }
            steps {
                sh """
                    sleep 10
                    curl -sf http://app.example.com/api/echo?smoke=true | grep smoke || exit 1
                    echo "Smoke test PASSED"
                """
            }
        }
    }
    post {
        failure {
            container('kubectl') {
                sh "kubectl rollout undo deployment/query-param-app -n ${params.ENVIRONMENT} || true"
            }
        }
    }
}
```

**Neden Ansible, kubectl değil?**

Case study bunu açıkça istiyor. Ama mantığı da var: Ansible idempotent, playbook
tekrar çalıştırılabilir, sonuç aynı olur. Ayrıca Ansible cluster dışından da çalışır
(kubeconfig ile) — Jenkins'in K8s API'ye doğrudan erişmesi gerekmez.

---

## Bölüm 7 — Monitoring Stack

### Case Study Ne İstiyor?

> *"Deploy Prometheus, Elasticsearch, Grafana, fluent-bit, and AlertManager"*
> *"Create custom Grafana dashboards to visualize Kubernetes and application metrics"*
> *"Set up alert conditions in AlertManager, which are triggered when the pod restarts"*
> *"Use a single hostname with a combination of different paths to access Prometheus,
>    Elasticsearch, and Grafana dashboards"*

### Adım 24: Monitoring Secrets

```bash
kubectl create namespace monitoring

kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)"

# Slack webhook için (AlertManager)
# Webhook oluştur: https://api.slack.com/messaging/webhooks
kubectl create secret generic alertmanager-slack-secret -n monitoring \
  --from-literal=webhookUrl='https://hooks.slack.com/services/...'
```

### Adım 25: kube-prometheus-stack

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
      label: grafana_dashboard    # Bu label'lı ConfigMap'leri otomatik yükle

prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    externalUrl: "http://monitoring.example.com/prometheus"
    routePrefix: /prometheus

alertmanager:
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
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f kubernetes/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

### Adım 26: Tek Hostname — Çoklu Path Ingress

Case study: *"single hostname with a combination of different paths"*

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
    - host: monitoring.example.com
      http:
        paths:
          - path: /grafana(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: kube-prometheus-stack-grafana
                port:
                  number: 80
          - path: /prometheus(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: kube-prometheus-stack-prometheus
                port:
                  number: 9090
          - path: /elasticsearch(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: elasticsearch-es-http
                port:
                  number: 9200
```

```bash
kubectl apply -f kubernetes/monitoring/ingress-monitoring.yaml

# Erişim:
# http://monitoring.example.com/grafana      → Grafana
# http://monitoring.example.com/prometheus   → Prometheus
# http://monitoring.example.com/elasticsearch → Elasticsearch
```

### Adım 27: Alert Kuralları

Case study: *"alert conditions triggered when the pod restarts"* — PodCrashLooping bu.

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
        # Case study: "alert when the pod restarts"
        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total{namespace="app"}[15m]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod {{ $labels.pod }} crash looping"
            description: "{{ $labels.namespace }}/{{ $labels.pod }} yeniden başlıyor."
            runbook: "kubectl logs -n {{ $labels.namespace }} {{ $labels.pod }} --previous"

        - alert: PodNotReady
          expr: kube_pod_status_ready{namespace="app",condition="true"} == 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod hazır değil: {{ $labels.pod }}"

        - alert: DeploymentReplicasMismatch
          expr: |
            kube_deployment_spec_replicas{namespace="app"} !=
            kube_deployment_status_available_replicas{namespace="app"}
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Deployment replica sayısı tutarsız"

    - name: app.rules
      rules:
        - alert: HighRequestLatency
          expr: |
            histogram_quantile(0.95,
              sum(rate(http_server_requests_seconds_bucket{namespace="app"}[5m])) by (le)
            ) > 1.0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "p95 latency 1 saniyeyi aştı"
            description: "Son 5 dakikada p95 response time yüksek."

        - alert: HighErrorRate
          expr: |
            sum(rate(http_server_requests_seconds_count{namespace="app",status=~"5.."}[5m])) /
            sum(rate(http_server_requests_seconds_count{namespace="app"}[5m])) * 100 > 5
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "5xx hata oranı %5 üzerinde"

        - alert: HPAMaxedOut
          expr: |
            kube_horizontalpodautoscaler_status_current_replicas{namespace="app"} >=
            kube_horizontalpodautoscaler_spec_max_replicas{namespace="app"}
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "HPA maksimum replica sayısına ulaştı — kapasite artırılmalı"

    - name: node.rules
      rules:
        - alert: NodeHighCPU
          expr: |
            100 - (avg by(node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Node CPU yüksek: {{ $labels.node }}"

        - alert: NodeHighMemory
          expr: |
            (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Node bellek yüksek: {{ $labels.node }}"
```

```bash
kubectl apply -f kubernetes/monitoring/alertmanager-rules.yaml
kubectl get prometheusrule -n monitoring
```

### Adım 28: Grafana Dashboards

Case study: *"Create custom Grafana dashboards to visualize Kubernetes and application metrics"*
→ İki dashboard: K8s cluster genel durum + uygulama RED metrikleri.

`kubernetes/monitoring/grafana-dashboards/k8s-overview-configmap.yaml`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-overview-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"    # Grafana sidecar otomatik yükler
data:
  k8s-overview.json: |
    {
      "title": "Kubernetes Cluster Overview",
      "uid": "k8s-overview",
      "schemaVersion": 38,
      "refresh": "30s",
      "panels": [
        {
          "id": 1,
          "title": "Pod Restart Count (Namespace: app)",
          "type": "stat",
          "gridPos": {"x": 0, "y": 0, "w": 6, "h": 4},
          "targets": [{
            "expr": "sum(increase(kube_pod_container_status_restarts_total{namespace=\"app\"}[1h]))",
            "legendFormat": "restarts (1h)"
          }],
          "fieldConfig": {
            "defaults": {
              "thresholds": {"steps": [
                {"value": 0, "color": "green"},
                {"value": 1, "color": "yellow"},
                {"value": 5, "color": "red"}
              ]}
            }
          }
        },
        {
          "id": 2,
          "title": "Node CPU Usage %",
          "type": "timeseries",
          "gridPos": {"x": 6, "y": 0, "w": 9, "h": 4},
          "targets": [{
            "expr": "100 - (avg by(node) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "{{ node }}"
          }]
        },
        {
          "id": 3,
          "title": "Node Memory Usage %",
          "type": "timeseries",
          "gridPos": {"x": 15, "y": 0, "w": 9, "h": 4},
          "targets": [{
            "expr": "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100",
            "legendFormat": "{{ instance }}"
          }]
        },
        {
          "id": 4,
          "title": "Total Pods (all namespaces)",
          "type": "stat",
          "gridPos": {"x": 0, "y": 4, "w": 4, "h": 3},
          "targets": [{
            "expr": "count(kube_pod_status_phase{phase=\"Running\"})"
          }]
        },
        {
          "id": 5,
          "title": "Not Running Pods",
          "type": "stat",
          "gridPos": {"x": 4, "y": 4, "w": 4, "h": 3},
          "targets": [{
            "expr": "count(kube_pod_status_phase{phase!~\"Running|Succeeded\"})"
          }]
        }
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
  labels:
    grafana_dashboard: "1"
data:
  app-metrics.json: |
    {
      "title": "query-param-app — RED Metrics",
      "uid": "dreamgames-app",
      "schemaVersion": 38,
      "refresh": "30s",
      "panels": [
        {
          "id": 1, "title": "Request Rate (RPS)", "type": "timeseries",
          "gridPos": {"x": 0, "y": 0, "w": 8, "h": 8},
          "targets": [{"expr": "sum(rate(http_server_requests_seconds_count{namespace=\"app\"}[2m])) by (uri)", "legendFormat": "{{ uri }}"}]
        },
        {
          "id": 2, "title": "Error Rate (5xx %)", "type": "timeseries",
          "gridPos": {"x": 8, "y": 0, "w": 8, "h": 8},
          "targets": [{"expr": "sum(rate(http_server_requests_seconds_count{namespace=\"app\",status=~\"5..\"}[2m])) / sum(rate(http_server_requests_seconds_count{namespace=\"app\"}[2m])) * 100", "legendFormat": "5xx %"}]
        },
        {
          "id": 3, "title": "Latency p50/p95/p99", "type": "timeseries",
          "gridPos": {"x": 16, "y": 0, "w": 8, "h": 8},
          "targets": [
            {"expr": "histogram_quantile(0.50, sum(rate(http_server_requests_seconds_bucket{namespace=\"app\"}[2m])) by (le))", "legendFormat": "p50"},
            {"expr": "histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket{namespace=\"app\"}[2m])) by (le))", "legendFormat": "p95"},
            {"expr": "histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket{namespace=\"app\"}[2m])) by (le))", "legendFormat": "p99"}
          ]
        },
        {
          "id": 4, "title": "HPA Current/Max Replicas", "type": "stat",
          "gridPos": {"x": 0, "y": 8, "w": 6, "h": 4},
          "targets": [
            {"expr": "kube_horizontalpodautoscaler_status_current_replicas{namespace=\"app\"}", "legendFormat": "current"},
            {"expr": "kube_horizontalpodautoscaler_spec_max_replicas{namespace=\"app\"}", "legendFormat": "max"}
          ]
        },
        {
          "id": 5, "title": "CPU Usage (millicores)", "type": "timeseries",
          "gridPos": {"x": 6, "y": 8, "w": 9, "h": 4},
          "targets": [{"expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"app\",container=\"query-param-app\"}[2m])) by (pod) * 1000", "legendFormat": "{{ pod }}"}]
        },
        {
          "id": 6, "title": "Memory Usage", "type": "timeseries",
          "gridPos": {"x": 15, "y": 8, "w": 9, "h": 4},
          "targets": [{"expr": "sum(container_memory_working_set_bytes{namespace=\"app\",container=\"query-param-app\"}) by (pod)", "legendFormat": "{{ pod }}"}]
        }
      ]
    }
```

```bash
kubectl apply -f kubernetes/monitoring/grafana-dashboards/

GRAFANA_PASS=$(kubectl get secret grafana-admin-secret -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d)
echo "Grafana: http://monitoring.example.com/grafana | admin / $GRAFANA_PASS"
```

---

## Bölüm 8 — Log Aggregation

### Adım 29: ECK Elasticsearch

```bash
kubectl create -f https://download.elastic.co/downloads/eck/2.11.1/crds.yaml
kubectl apply  -f https://download.elastic.co/downloads/eck/2.11.1/operator.yaml
```

`kubernetes/monitoring/elasticsearch/eck-operator.yaml`:
```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: dreamgames
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
                requests:
                  memory: 1Gi
                  cpu: 500m
                limits:
                  memory: 2Gi
```

```bash
kubectl apply -f kubernetes/monitoring/elasticsearch/eck-operator.yaml
kubectl get elasticsearch -n monitoring   # health: green beklenir (5-10 dk)
```

### Adım 30: Fluent Bit (Uygulama loglarını ES'e gönder)

```bash
ELASTIC_PASS=$(kubectl get secret dreamgames-es-elastic-user -n monitoring \
  -o jsonpath='{.data.elastic}' | base64 -d)

kubectl create secret generic elastic-credentials -n monitoring \
  --from-literal=ELASTIC_PASSWORD="$ELASTIC_PASS"
```

`kubernetes/monitoring/fluent-bit/values.yaml`:
```yaml
config:
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/query-param-app*.log
        Parser            docker
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
        Host            dreamgames-es-http.monitoring.svc.cluster.local
        Port            9200
        HTTP_User       elastic
        HTTP_Passwd     ${ELASTIC_PASSWORD}
        tls             On
        tls.verify      Off
        Index           app-logs
        Suppress_Type_Name On
```

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm install fluent-bit fluent/fluent-bit \
  -n monitoring \
  -f kubernetes/monitoring/fluent-bit/values.yaml \
  --set envFrom[0].secretRef.name=elastic-credentials
```

---

## Bölüm 9 — Admission Webhook

### Case Study Ne İstiyor?

> *"Write a custom validation webhook that fails if a deployment does not specify required
> CPU and memory resource requests."*
> *"Use a configmap to specify in which namespaces this validation webhook runs."* ← kritik!
> *"Webhook should expose its metrics to Prometheus."*

### Adım 31: Go Webhook Kodu

Namespace listesi ConfigMap'ten okunacak — hardcode değil.

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

    appsv1     "k8s.io/api/apps/v1"
    admissionv1 "k8s.io/api/admission/v1"
    corev1     "k8s.io/api/core/v1"
    metav1     "k8s.io/apimachinery/pkg/apis/meta/v1"
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
        []string{"result"},    // "allowed" | "rejected"
    )
)

func init() {
    _ = appsv1.AddToScheme(scheme)
    _ = admissionv1.AddToScheme(scheme)
    prometheus.MustRegister(validationsTotal)
}

// allowedNamespaces: ConfigMap volume mount'tan veya env var'dan okur
// Case study: "Use a configmap to specify in which namespaces webhook runs"
// Kubernetes/webhook/configmap.yaml → deployment'ta /etc/webhook/namespaces'e mount edilir
func allowedNamespaces() map[string]bool {
    ns := os.Getenv("WEBHOOK_NAMESPACES")
    if ns == "" {
        data, err := os.ReadFile("/etc/webhook/namespaces")
        if err == nil {
            ns = string(data)
        }
    }
    if ns == "" {
        ns = "default,app"    // fallback
    }
    result := make(map[string]bool)
    for _, n := range strings.Split(strings.TrimSpace(ns), ",") {
        result[strings.TrimSpace(n)] = true
    }
    return result
}

func checkContainers(containers []corev1.Container) []string {
    var violations []string
    for _, c := range containers {
        if c.Resources.Requests.Cpu().IsZero() {
            violations = append(violations, fmt.Sprintf("container %q: resources.requests.cpu eksik", c.Name))
        }
        if c.Resources.Requests.Memory().IsZero() {
            violations = append(violations, fmt.Sprintf("container %q: resources.requests.memory eksik", c.Name))
        }
    }
    return violations
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

    // Sadece izinli namespace'leri denetle (ConfigMap'ten gelir)
    if !allowedNamespaces()[req.Namespace] {
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
        msg := "Deployment reddedildi — eksik resource request:\n" + strings.Join(violations, "\n")
        validationsTotal.WithLabelValues("rejected").Inc()
        respond(w, review, false, msg)
    } else {
        validationsTotal.WithLabelValues("allowed").Inc()
        respond(w, review, true, "")
    }
}

func respond(w http.ResponseWriter, review *admissionv1.AdmissionReview, allowed bool, msg string) {
    resp := &admissionv1.AdmissionResponse{
        UID:     review.Request.UID,
        Allowed: allowed,
    }
    if !allowed {
        resp.Result = &metav1.Status{Code: 422, Message: msg}
    }
    review.Response = resp
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(review)
}

func main() {
    certFile := "/etc/webhook/certs/tls.crt"
    keyFile  := "/etc/webhook/certs/tls.key"

    // Prometheus metrics — TLS değil, HTTP (case study: "expose metrics to Prometheus")
    go func() {
        mux := http.NewServeMux()
        mux.Handle("/metrics", promhttp.Handler())
        log.Fatal(http.ListenAndServe(":8080", mux))
    }()

    // Validation endpoint — TLS (kube-apiserver TLS ister)
    cert, err := tls.LoadX509KeyPair(certFile, keyFile)
    if err != nil {
        log.Fatalf("TLS sertifikası yüklenemedi: %v", err)
    }

    http.HandleFunc("/validate", handleValidate)
    server := &http.Server{
        Addr:      ":8443",
        TLSConfig: &tls.Config{Certificates: []tls.Certificate{cert}},
    }
    log.Println("Webhook başlatıldı :8443 (TLS), :8080 (metrics)")
    log.Fatal(server.ListenAndServeTLS("", ""))
}
```

### Adım 32: Webhook ConfigMap

`kubernetes/webhook/configmap.yaml`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: webhook-config
  namespace: webhook-system
data:
  # Bu listede olan namespace'lerdeki Deployment'lar denetlenir
  # Listeyi güncellemek için: kubectl edit configmap webhook-config -n webhook-system
  # Sonra webhook pod'larını restart et: kubectl rollout restart deployment/resource-webhook -n webhook-system
  namespaces: "app,production,staging"
```

### Adım 33: Webhook Deployment

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
    matchLabels:
      app: resource-webhook
  template:
    metadata:
      labels:
        app: resource-webhook
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
        - name: resource-webhook
          image: dreamgames/resource-webhook:1.0.0
          ports:
            - containerPort: 8443
              name: https
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: certs
              mountPath: /etc/webhook/certs
              readOnly: true
            - name: config
              mountPath: /etc/webhook/namespaces
              subPath: namespaces    # ConfigMap'ten namespace listesi
              readOnly: true
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              cpu: 200m
              memory: 128Mi
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
      volumes:
        - name: certs
          secret:
            secretName: resource-webhook-tls
        - name: config
          configMap:
            name: webhook-config    # Namespace listesi buradan gelir
```

### Adım 34: TLS ve Deploy

`kubernetes/webhook/tls/generate-certs.sh`:
```bash
#!/bin/bash
set -e
NAMESPACE="webhook-system"
SERVICE="resource-webhook"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

openssl genrsa -out "$TMPDIR/ca.key" 2048
openssl req -new -x509 -days 3650 -key "$TMPDIR/ca.key" -subj "/CN=webhook-ca" -out "$TMPDIR/ca.crt"
openssl genrsa -out "$TMPDIR/tls.key" 2048
openssl req -new -key "$TMPDIR/tls.key" -subj "/CN=${SERVICE}.${NAMESPACE}.svc" -out "$TMPDIR/tls.csr"
cat > "$TMPDIR/san.conf" << EOF
subjectAltName = DNS:${SERVICE}.${NAMESPACE}.svc,DNS:${SERVICE}.${NAMESPACE}.svc.cluster.local
EOF
openssl x509 -req -days 3650 -in "$TMPDIR/tls.csr" \
  -CA "$TMPDIR/ca.crt" -CAkey "$TMPDIR/ca.key" -CAcreateserial \
  -extfile "$TMPDIR/san.conf" -out "$TMPDIR/tls.crt"

kubectl create secret tls resource-webhook-tls \
  --cert="$TMPDIR/tls.crt" --key="$TMPDIR/tls.key" \
  -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

CA_BUNDLE=$(base64 < "$TMPDIR/ca.crt" | tr -d '\n')
kubectl patch validatingwebhookconfiguration resource-requests-webhook \
  --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${CA_BUNDLE}\"}]"
echo "Done."
```

```bash
kubectl create namespace webhook-system
kubectl apply -f kubernetes/webhook/configmap.yaml
kubectl apply -f kubernetes/webhook/rbac.yaml
kubectl apply -f kubernetes/webhook/deployment.yaml
kubectl apply -f kubernetes/webhook/service.yaml
kubectl apply -f kubernetes/webhook/validatingwebhookconfiguration.yaml

chmod +x kubernetes/webhook/tls/generate-certs.sh
bash kubernetes/webhook/tls/generate-certs.sh

kubectl get pods -n webhook-system   # 2 pod Running
```

**Neden ConfigMap'ten namespace oku?**

Case study açıkça istiyor. Ama mantığı da var: hardcoded list → kodu değiştirmeden
namespace ekle/sil istersen imaj rebuild gerekir. ConfigMap → `kubectl edit` → restart
yeterli. Operasyonel esneklik.

**Test:**
```bash
# Kötü deploy (resource request yok → reddedilmeli)
kubectl apply -n app -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bad-deploy
spec:
  replicas: 1
  selector:
    matchLabels: { app: bad }
  template:
    metadata:
      labels: { app: bad }
    spec:
      containers:
        - name: nginx
          image: nginx
          # resources: YOK
EOF
# Beklenen: "admission webhook denied the request"

# ConfigMap'e yeni namespace ekle (kod değişikliği gerekmez!)
kubectl patch configmap webhook-config -n webhook-system \
  --type='json' \
  -p='[{"op":"replace","path":"/data/namespaces","value":"app,production,staging,test"}]'
kubectl rollout restart deployment/resource-webhook -n webhook-system
```

---

## Bölüm 10 — İleri Senaryolar (Step 3)

### Senaryo 1: PriorityClass (App X vs App Y)

Case study: *"App X: real-time, high availability. App Y: batch, can be killed."*

`step3-manifests/priority-classes.yaml`:
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-realtime
value: 1000
globalDefault: false
description: "App X — gerçek zamanlı, tahliye edilemez"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority-batch
value: 100
globalDefault: false
description: "App Y — batch, kaynak baskısında tahliye edilebilir"
```

`step3-manifests/app-x-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-realtime
  namespace: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-realtime
  template:
    metadata:
      labels:
        app: app-realtime
    spec:
      priorityClassName: high-priority-realtime
      containers:
        - name: app
          image: nginx:alpine
          resources:
            requests:
              cpu: 200m
              memory: 128Mi
            limits:
              cpu: 200m      # requests == limits → Guaranteed QoS → asla tahliye edilmez
              memory: 128Mi
```

`step3-manifests/app-y-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-batch
  namespace: app
spec:
  replicas: 4
  selector:
    matchLabels:
      app: app-batch
  template:
    metadata:
      labels:
        app: app-batch
    spec:
      priorityClassName: low-priority-batch
      containers:
        - name: app
          image: nginx:alpine
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m       # requests < limits → Burstable QoS → baskıda tahliye edilebilir
              memory: 256Mi
```

**Neden QoS sınıfları önemli?**

Node bellek baskısı altında Kubernetes pod tahliye eder. Sıra:
1. BestEffort (requests/limits yok) → ilk tahliye
2. Burstable (requests < limits) → ikinci
3. Guaranteed (requests == limits) → asla tahliye edilmez

App X Guaranteed, App Y Burstable → baskı altında App Y tahliye edilir, App X çalışmaya devam eder.
PriorityClass ise scheduler'ın yeni pod için yer açmak için hangi pod'ları evict edeceğini belirler.

### Senaryo 2: KEDA ile Proaktif Ölçekleme

Case study: *"Ensure the application scales out before peak periods."*

`step3-manifests/hpa-scheduled.yaml`:
```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: query-param-app-scheduled
  namespace: app
spec:
  scaleTargetRef:
    name: query-param-app
  minReplicaCount: 4
  maxReplicaCount: 16
  triggers:
    # Reaktif: CPU yükü arttığında ölçekle
    - type: cpu
      metricType: Utilization
      metadata:
        value: "70"
    # Proaktif: Sabah yoğunluğu öncesi 15 dk erken hazırlan (Europe/Istanbul UTC+3)
    - type: cron
      metadata:
        timezone: Europe/Istanbul
        start: "45 8 * * 1-5"    # Pazartesi-Cuma 08:45 → 12 pod hazır
        end:   "0 11 * * 1-5"    # 11:00'de normal'e dön
        desiredReplicas: "12"
    # Öğle yoğunluğu
    - type: cron
      metadata:
        timezone: Europe/Istanbul
        start: "45 11 * * 1-5"
        end:   "15 13 * * 1-5"
        desiredReplicas: "8"
```

```bash
# Standart HPA'yı sil (KEDA ve HPA çakışır)
kubectl delete hpa query-param-app -n app

helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda --namespace keda --create-namespace --wait
kubectl apply -f step3-manifests/hpa-scheduled.yaml
```

**Neden Standart HPA yeterli değil?**
HPA reaktif: yoğunluk başladıktan sonra ölçekler (2-5 dk gecikme). Yeni pod'lar
schedule + başlatılırken kullanıcılar yavaşlık yaşar. KEDA CronTrigger proaktif:
08:45'te yoğunluk gelmeden pod sayısını artırır, 09:00'da trafik geldiğinde hazır.

### Senaryo 3: Canary Deployment

`step3-manifests/canary-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: query-param-app-canary
  namespace: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: query-param-app-canary
  template:
    metadata:
      labels:
        app: query-param-app-canary
    spec:
      containers:
        - name: query-param-app
          image: dreamgames/query-param-app:2.0.0   # YENİ VERSİYON
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: query-param-app-canary
  namespace: app
spec:
  selector:
    app: query-param-app-canary
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: query-param-app-canary
  namespace: app
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"   # %10 trafik yeni versiyona
spec:
  ingressClassName: nginx
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: query-param-app-canary
                port:
                  number: 80
```

```bash
kubectl apply -f step3-manifests/canary-deployment.yaml

# Grafana'da hata rate'ini izle...
# Sorun yoksa %50'ye çıkar:
kubectl annotate ingress query-param-app-canary \
  nginx.ingress.kubernetes.io/canary-weight=50 -n app --overwrite

# Tam geçiş (%100):
kubectl annotate ingress query-param-app-canary \
  nginx.ingress.kubernetes.io/canary-weight=100 -n app --overwrite

# Rollback (canary ingress'i sil → %100 eski versiyona döner):
# kubectl delete ingress query-param-app-canary -n app
```

---

## Bölüm 11 — Tasarım Soruları (Step 4)

Bu bölüm yazılı tasarım soruları. Kod değil, düşünce sürecin değerlendiriliyor.
Her cevabı `docs/design-answers/` altına ekle.

### Step 4.1: macOS → Cloud CI/CD Migrasyonu

`docs/design-answers/step4-cloud-cicd.md` dosyasına şunları yaz:

**Sorun:** On-premises macOS build makineleri → kuyruk tıkanıklığı.

**Çözüm Planı:**
```
1. AWS EC2 Mac instances (mac1.metal veya mac2.metal)
   - Apple Silicon native (M1 chip) → Unity iOS/Android build'ler
   - Dedicated host (Apple lisans zorunluluğu: 24 saat minimum kiralama)
   
2. GitHub Actions Runner Controller (ARC) veya Jenkins Kubernetes Agent
   - Her build için ephemeral runner/agent başlat → build biter bitmez sil
   - Kuyruk problemi ortadan kalkar: sınırsız paralel build
   
3. Artifact dağıtımı:
   - iOS IPA → TestFlight (Apple) veya AppCenter (Microsoft, ücretsiz)
   - Android APK → Google Play Internal Testing veya Firebase App Distribution
   - Geliştiriciler link alır, hemen cihazlarına kurar
   
4. Lisans zorunlulukları:
   - Apple: Xcode sadece macOS'ta çalışır → EC2 Mac instance zorunlu
   - Unity: per-seat lisans → floating license server veya per-build lisans
   - Code signing: Apple Developer Certificate → AWS Secrets Manager'da sakla
   - fastlane match: sertifikaları Git'te şifreli sakla (veya S3)
```

### Step 4.2: iOS Build Otomasyonu

`docs/design-answers/step4-ios-automation.md` dosyasına şunları yaz:

**Çözüm: fastlane**
```
fastlane action akışı:
1. match (kod imzalama):
   - Sertifikaları merkezi depoda (S3 veya Git) şifreli sakla
   - CI'da: MATCH_PASSWORD env var → sertifika otomatik çekilir
   
2. gym (build):
   - Xcode project derle, IPA oluştur
   - `gym(scheme: "MyApp", configuration: "Release")`
   
3. scan (test):
   - Unit ve UI testleri çalıştır, başarısız olursa pipeline dur
   
4. pilot (TestFlight dağıtımı):
   - IPA'yı TestFlight'a yükle
   - Test gruplarına otomatik dağıt
   
5. deliver (App Store gönderimi):
   - Screenshot, açıklama, metadata dahil tam App Store submission

Jenkinsfile veya GitHub Actions:
- Her PR → scan (test)
- Main branch → gym + pilot (TestFlight)
- Tag v*.*.* → deliver (App Store)
```

### Step 4.3: AWS Kubernetes Disaster Recovery

`docs/design-answers/step4-aws-dr.md` dosyasına şunları yaz:

**RTO/RPO Hedefleri:**
```
RTO (Recovery Time Objective): < 1 saat
RPO (Recovery Point Objective): < 15 dakika
```

**Katman 1: Cluster Konfigürasyonu**
```
- Tüm manifest'ler Git'te (GitOps) → yeni cluster'a `kubectl apply -f` ile restore
- ArgoCD/Flux → cluster state'i Git'ten otomatik reconcile eder
- Terraform → EKS cluster altyapısını yeniden oluşturur (IaC)
```

**Katman 2: Veri**
```
- Velero: K8s resource backup + PVC snapshot → S3
  - Schedule: her 15 dakikada bir (RPO: 15 dk)
  - S3 Cross-Region Replication (CRR): disaster bölgesine otomatik kopyala
  
- RDS: Multi-AZ deployment → otomatik failover
  - Cross-region read replica → disaster'da promote et
  
- ElastiCache: backup + cross-region replica
```

**Katman 3: DNS Failover**
```
- Route53 Health Check → primary cluster sağlıklı mı?
- Failover routing policy:
  - Primary: us-east-1 EKS cluster
  - Secondary: eu-west-1 EKS cluster (warm standby)
  - Health check başarısız → DNS otomatik secondary'e yönlendirir
```

**Katman 4: Recovery Prosedürü**
```
1. Terraform apply → yeni EKS cluster (15-20 dk)
2. ArgoCD/Flux → manifest'leri Git'ten deploy (10 dk)
3. Velero restore → PVC'leri S3'ten restore et (5-10 dk)
4. RDS replica promote → veritabanı failover (2-5 dk)
5. Route53 → DNS güncelle (propagation: 60-300 sn)
Toplam RTO: ~30-45 dk ✓
```

---

## Bölüm 12 — Doğrulama ve Temizlik

### Adım 35: Tam Sistem Doğrulaması

```bash
# Node'lar
kubectl get nodes -o wide
# 3 node Ready: master, worker1, worker2

# Pod dağılımı (worker1 + worker2'de mi?)
kubectl get pods -n app -o wide

# HPA
kubectl describe hpa query-param-app -n app

# PDB
kubectl get pdb -n app

# Uygulama smoke test
curl 'http://app.example.com/api/echo?hello=world&foo=bar'
# Beklenen: {"foo":"bar","hello":"world"}

# Webhook testi (resource request eksik → reddedilmeli)
kubectl apply -n app -f - << 'EOF' 2>&1 | grep -i "denied\|webhook\|rejected"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webhook-test
spec:
  replicas: 1
  selector:
    matchLabels: { app: test }
  template:
    metadata:
      labels: { app: test }
    spec:
      containers:
        - name: nginx
          image: nginx
EOF
# Beklenen: admission webhook denied the request

# Monitoring erişim
curl -s 'http://monitoring.example.com/prometheus/-/healthy'
# Beklenen: Prometheus is Healthy.

# Grafana şifresi
kubectl get secret grafana-admin-secret -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d

# Jenkins şifresi
kubectl get secret jenkins-credentials -n jenkins \
  -o jsonpath='{.data.admin-password}' | base64 -d

# Jenkins Node 3 (worker2) üzerinde mi?
kubectl get pod -n jenkins -o wide | grep jenkins
# NODE sütununda worker2 yazmalı

# KEDA ScaledObject
kubectl get scaledobject -n app

# ElasticSearch sağlık durumu
kubectl get elasticsearch -n monitoring
```

### Adım 36: Temizlik

```bash
# OrbStack VM'leri sil
orb delete master
orb delete worker1
orb delete worker2

# kubeconfig temizle
unset KUBECONFIG
rm ~/.kube/config-dreamgames

# /etc/hosts temizle (macOS)
sudo sed -i '' '/example.com/d' /etc/hosts
```

---

## Özet: Case Study Kapsama

| Step | Gereksinim | Karşılandı mı? |
|------|-----------|---------------|
| 1.1 | Java app query params | ✅ Spring Boot /api/echo |
| 1.2 | Multi-stage Dockerfile | ✅ 3 stage, JRE Alpine |
| 1.2a | Build acceleration | ✅ Layer caching (pom.xml önce) |
| 1.2b | Compact image | ✅ JRE-only Alpine |
| 1.2c | Security Dockerfile | ✅ non-root, readOnly |
| 1.3 | kubeadm cluster | ✅ Ansible + kubeadm (OrbStack VMs) |
| 1.3a | K8s 1.28+ | ✅ 1.32 |
| 1.3b | Custom subnets | ✅ 10.244.0.0/16, 10.96.0.0/12 |
| 1.3c | GitOps | ✅ Manifests Git'te (belgelenmiş) |
| 1.4 | ExternalDNS | ✅ CoreDNS provider |
| 1.5 | Jenkins | ✅ |
| 1.5a | Jenkins Node 3 | ✅ nodeSelector: worker2 |
| 1.5b | JCasC | ✅ |
| 1.5c | Config persistence | ✅ PVC |
| 1.5d | LoadBalancer hostname | ✅ |
| 1.6 | Prometheus+ES+Grafana+fluentbit | ✅ |
| 1.6a | K8s + app dashboards | ✅ 2 dashboard (k8s-overview + RED) |
| 1.6b | Pod restart alert | ✅ PodCrashLooping |
| 1.6c | Single hostname paths | ✅ /prometheus /grafana /elasticsearch |
| 1.6d | Logs → Elasticsearch | ✅ Fluent Bit |
| 1.7a | Async file logging | ✅ AsyncAppender |
| 1.7b | Max 1GB | ✅ SizeAndTimeBasedRollingPolicy |
| 1.7c | Daily rotation | ✅ |
| 2.1 | 4 pods, both workers | ✅ |
| 2.1a | Even distribution | ✅ topologySpreadConstraints |
| 2.1b | Readiness/liveness | ✅ |
| 2.2 | Build pipeline | ✅ Trivy scan, immutable tag |
| 2.3 | Deploy pipeline | ✅ |
| 2.3a | **Ansible** apply manifests | ✅ Jenkinsfile.deploy |
| 2.3b | Ingress hostname | ✅ |
| 2.3c | Zero-downtime | ✅ maxUnavailable:0 |
| 2.4 | Validation webhook | ✅ |
| 2.4a | **ConfigMap** for namespaces | ✅ volume mount |
| 2.4b | Prometheus metrics | ✅ /metrics |
| 3.1 | PriorityClass App X vs Y | ✅ |
| 3.2 | KEDA scheduled scale | ✅ CronTrigger |
| 3.3 | Canary deployment | ✅ ingress-nginx canary-weight |
| 3.4 | DB replica scaling | ✅ design-answers/step3-database-scaling.md |
| 4.1 | Cloud CI/CD plan | ✅ design-answers/step4-cloud-cicd.md |
| 4.2 | iOS automation | ✅ design-answers/step4-ios-automation.md |
| 4.3 | K8s DR on AWS | ✅ design-answers/step4-aws-dr.md |

**Tahmini kapsama: ~92%**

Kalan %8: GitOps tam implementasyon (ArgoCD/Flux eksik, "highly desirable" ama zorunlu değil),
node auto-scaling (concrete K8s operator implementasyonu eksik, design doc var).

---

## Referanslar

| Araç | Dokümantasyon |
|------|--------------|
| OrbStack | https://docs.orbstack.dev/machines/ |
| kubeadm | https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ |
| Calico | https://docs.tigera.io/calico/latest/ |
| MetalLB | https://metallb.universe.tf/ |
| Ingress-NGINX | https://kubernetes.github.io/ingress-nginx/ |
| ExternalDNS | https://github.com/kubernetes-sigs/external-dns |
| Jenkins Helm | https://www.jenkins.io/doc/book/installing/kubernetes/ |
| JCasC | https://www.jenkins.io/projects/jcasc/ |
| kube-prometheus-stack | https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack |
| Prometheus Operator | https://prometheus-operator.dev/ |
| ECK | https://www.elastic.co/guide/en/cloud-on-k8s/current/ |
| Fluent Bit | https://docs.fluentbit.io/manual/ |
| Trivy | https://aquasecurity.github.io/trivy/ |
| KEDA | https://keda.sh/docs/latest/ |
| Admission Webhooks | https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/ |
| PSA | https://kubernetes.io/docs/concepts/security/pod-security-admission/ |
| PriorityClass | https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/ |
| fastlane | https://fastlane.tools/ |
| Velero | https://velero.io/docs/ |
