# Dream Games DevOps Case Study — Sıfırdan Çözüm Rehberi

> **Hedef kitle:** 5-6 yıllık DevOps deneyimi. Bu rehber, case study'yi kendin sıfırdan
> kurmak için yazılmıştır. Her adımda **"Case study ne istiyor?"** → **"Biz neden böyle
> yaptık?"** → **"Nasıl yapılır?"** akışı izlenir.
>
> **MacBook Air M4 (Apple Silicon) uyumludur.** VirtualBox M-serisi Mac'te çalışmaz.
> Bu rehber VirtualBox kullanmaz.
>
> ⚠️ **Güvenlik:** Şifre, token, Slack webhook, cloud credential asla dosyaya yazılmaz.
> Tüm secret'lar `kubectl create secret` veya environment variable ile yönetilir.

---

## İçindekiler

- [Bölüm 0 — Case Study Analizi ve Araçlar](#bölüm-0--case-study-analizi-ve-araçlar)
- [Bölüm 1 — Kendi Repo'nu Oluştur](#bölüm-1--kendi-repoyu-oluştur)
- [Bölüm 2 — Kubernetes Cluster (M4 Mac Uyumlu)](#bölüm-2--kubernetes-cluster-m4-mac-uyumlu)
- [Bölüm 3 — Network Altyapısı](#bölüm-3--network-altyapısı)
- [Bölüm 4 — Uygulama: Minimal Go Servisi](#bölüm-4--uygulama-minimal-go-servisi)
- [Bölüm 5 — Kubernetes Kaynakları](#bölüm-5--kubernetes-kaynakları)
- [Bölüm 6 — Jenkins CI/CD](#bölüm-6--jenkins-cicd)
- [Bölüm 7 — Monitoring Stack](#bölüm-7--monitoring-stack)
- [Bölüm 8 — Log Aggregation](#bölüm-8--log-aggregation)
- [Bölüm 9 — Admission Webhook](#bölüm-9--admission-webhook)
- [Bölüm 10 — İleri Senaryolar](#bölüm-10--i̇leri-senaryolar)
- [Bölüm 11 — Doğrulama ve Temizlik](#bölüm-11--doğrulama-ve-temizlik)

---

## Bölüm 0 — Case Study Analizi ve Araçlar

### Case Study Ne İstiyor?

Case study birkaç katmandan oluşuyor. Bunları önce anlayalım, sonra her birini çözelim:

| Katman | Gereksinim | Biz Ne Kullanacağız? |
|--------|-----------|---------------------|
| Kubernetes Cluster | Multi-node, production-grade | k3d (Docker içinde 3 node) |
| Uygulama | REST API, query param echo, Prometheus metrics | Minimal Go servisi (~60 satır) |
| Container Güvenliği | Non-root, resource limits | securityContext + resources |
| Yüksek Erişilebilirlik | replicas, PDB, topology spread | Deployment + PodDisruptionBudget |
| Otomatik Ölçekleme | HPA | metrics-server + HPA manifest |
| CI/CD | Build, test, scan, deploy pipeline | Jenkins on K8s |
| Monitoring | Prometheus + Grafana + AlertManager | kube-prometheus-stack (Helm) |
| Log Toplama | Structured JSON logs → Elasticsearch | Fluent Bit + ECK |
| Admission Webhook | Resource request zorunluluğu | Go webhook + TLS |
| İleri Senaryolar | KEDA, Canary, PriorityClass | Ek manifest'ler |

### Neden Bu Araçlar?

**k3d (K3s in Docker):**
- 📖 https://k3d.io/
- VirtualBox çalışmaz M4 Mac'te çünkü ARM64 mimarisinde x86 sanal makine yöneticisi desteklenmez
- k3d, K3s (hafif Kubernetes dağıtımı) container'larını Docker içinde çalıştırır → gerçek VM gerektirmez
- 1 master + 2 worker = case study'nin multi-node gereksinimini karşılar
- Laptop'ta 3-4 GB RAM yeterli (VirtualBox 6+ GB isterdi)

**Alternatifl:** OrbStack (`brew install orbstack`) → GUI ile tek tık K8s, ama tek node.
Case study worker node dağılımı istediği için k3d daha uygun.

### Gerekli Araçları Kur

```bash
# Homebrew (yoksa)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Container runtime (Docker Desktop veya OrbStack)
brew install --cask orbstack        # VEYA: brew install --cask docker

# K8s araçları
brew install k3d kubectl helm

# Uygulama geliştirme
brew install go

# İsteğe bağlı
brew install k9s    # Terminal K8s UI
```

Versiyon kontrolü:
```bash
k3d version      # v5.6+
kubectl version  # v1.28+
helm version     # v3.14+
go version       # go1.21+
```

📖 Resmi referanslar:
- k3d: https://k3d.io/v5.6.0/
- kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/
- Helm: https://helm.sh/docs/intro/install/
- Go: https://go.dev/doc/install

---

## Bölüm 1 — Kendi Repo'nu Oluştur

### Neden Sıfırdan?

Case study'nin amacı senin düşünce sürecini görmek. Var olan bir repo'yu klonlamak
yetkinliği değil, kopyalamayı gösterir. Kendi repo'nda her dosyanın neden orada olduğunu
savunabilirsin.

### Adım 1: Git Repo ve Dizin Yapısı

```bash
mkdir dreamgames-case && cd dreamgames-case
git init
git branch -M main

# Dizin yapısını oluştur
mkdir -p app
mkdir -p webhook
mkdir -p kubernetes/{namespaces,app,jenkins,webhook,metallb,ingress-nginx,monitoring/{grafana-dashboards,elasticsearch,fluent-bit},externaldns}
mkdir -p jenkins
mkdir -p step3-manifests
mkdir -p docs

# .gitignore
cat > .gitignore << 'EOF'
*.jar
*.class
target/
vendor/
__pycache__/
.DS_Store
*.env
*.key
*.crt
*.pem
kubeconfig
EOF
```

Dizin yapısının mantığı:

```
dreamgames-case/
├── app/                    # Uygulama kodu + Dockerfile
├── webhook/                # Go admission webhook kodu
├── kubernetes/             # Tüm K8s manifest'leri
│   ├── namespaces/         # Namespace + PSA etiketleri
│   ├── app/                # Deployment, Service, Ingress, HPA, PDB, NetworkPolicy
│   ├── metallb/            # IP havuzu tanımı
│   ├── ingress-nginx/      # Ingress controller değerleri
│   ├── jenkins/            # Jenkins PV, StorageClass, Helm values
│   ├── webhook/            # Webhook K8s kaynakları
│   └── monitoring/         # Prometheus stack + alerting + dashboards
├── jenkins/                # Jenkinsfile.build, Jenkinsfile.deploy
├── step3-manifests/        # KEDA, Canary, PriorityClass manifest'leri
└── docs/                   # Bu rehber dahil dökümantasyon
```

### Adım 2: GitHub'a Push Et

```bash
# GitHub'da yeni repo oluştur (github.com → New repository → dreamgames-case)
# Boş repo oluştur (README ekleme, biz ekleyeceğiz)

git remote add origin https://github.com/<kullanici>/dreamgames-case.git

echo "# Dream Games DevOps Case Study" > README.md
git add README.md
git commit -m "chore: initial repo structure"
git push -u origin main
```

---

## Bölüm 2 — Kubernetes Cluster (M4 Mac Uyumlu)

### Case Study Ne İstiyor?

Multi-node Kubernetes cluster: master node + en az 2 worker. Production ortamında
kubeadm ile bare-metal kurulum yapılır. MacBook'ta VirtualBox olmadığı için biz k3d
kullanıyoruz. Teknik kavramlar birebir aynı — sadece VM yerine Docker container.

### Neden kubeadm Öğrenmek Yerine k3d?

Production'da kubeadm kullanırsın. Case study'de **Kubernetes API ile çalışmak** değerlendirilir,
kubeadm komutları değil. k3d ile kurduğun cluster'a `kubectl` komutları birebir aynı çalışır.
Networking, RBAC, PSA, webhook, HPA — hepsi gerçek Kubernetes davranışı.

Kubeadm bilgisini göstermek istersen `ansible/roles/master/templates/kubeadm-config.yaml.j2`
gibi bir dosya hazırlayıp README'de açıklayabilirsin. Değerlendirici için önemli olan
**neden** o seçimleri yaptığını bilmek.

### Adım 3: k3d Cluster Oluştur

```bash
# K3s dahili load balancer ve traefik'i devre dışı bırak
# Bizim MetalLB ve Ingress-NGINX kullanacağız
k3d cluster create dreamgames \
  --agents 2 \
  --k3s-arg "--disable=traefik@server:0" \
  --k3s-arg "--disable=servicelb@server:0" \
  --no-lb \
  --wait

# kubeconfig al
export KUBECONFIG=$(k3d kubeconfig write dreamgames)
echo "export KUBECONFIG=$(k3d kubeconfig write dreamgames)" >> ~/.zshrc

# Doğrula
kubectl get nodes -o wide
```

Beklenen çıktı:
```
NAME                      STATUS   ROLES                  AGE   VERSION
k3d-dreamgames-server-0   Ready    control-plane,master   60s   v1.29.x
k3d-dreamgames-agent-0    Ready    <none>                 55s   v1.29.x
k3d-dreamgames-agent-1    Ready    <none>                 55s   v1.29.x
```

Worker node'lara label ekle (topology spread için):
```bash
kubectl label node k3d-dreamgames-agent-0 kubernetes.io/hostname=worker1
kubectl label node k3d-dreamgames-agent-1 kubernetes.io/hostname=worker2
```

### Neden `--disable=traefik` ve `--disable=servicelb`?

k3s varsayılan olarak Traefik (Ingress) ve ServiceLB gelir. Biz Ingress-NGINX ve MetalLB
kuracağız çünkü:
- Ingress-NGINX: daha yaygın, annotation ekosistemi daha zengin (canary, auth, rate limit)
- MetalLB: bare-metal için standart, IP havuzu yönetimi daha net
- İki Ingress controller aynı anda çalışırsa port çakışması yaşanır

### Adım 4: Metrics Server (HPA için zorunlu)

```bash
# HPA CPU/memory metriklerini ölçmek için metrics-server gerekir
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# k3d self-signed sertifika kullandığı için --kubelet-insecure-tls gerekir
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Doğrula (30 saniye bekle)
kubectl top nodes
```

📖 Resmi Dok: https://github.com/kubernetes-sigs/metrics-server

---

## Bölüm 3 — Network Altyapısı

### Case Study Ne İstiyor?

- Cluster dışından HTTP erişimi (Ingress)
- LoadBalancer tipi Service (bare-metal'de IP almak için MetalLB)
- Uygulama `app.example.com` gibi bir hostname üzerinden erişilebilir

### Neden MetalLB?

Cloud ortamında (GKE, EKS, AKS) `type: LoadBalancer` yazan bir Service'e bulut sağlayıcı
otomatik harici IP atar. Bare-metal'de (ve k3d'de) bu mekanizma yoktur — Service
`<pending>` durumunda kalır. MetalLB bu boşluğu doldurur: belirlediğin IP aralığından
servis'e IP atar.

📖 Resmi Dok: https://metallb.universe.tf/
📦 Repo: https://github.com/metallb/metallb

### Adım 5: MetalLB Kur

```bash
# Helm ile kur
helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm install metallb metallb/metallb \
  -n metallb-system --create-namespace \
  --wait --timeout 3m
```

k3d Docker ağ aralığını bul (MetalLB IP havuzu için):
```bash
docker network inspect k3d-dreamgames | grep -A2 '"Subnet"'
# Örnek çıktı: "Subnet": "172.18.0.0/16"
# Bu durumda 172.18.1.200-220 aralığı kullanılabilir
```

`kubernetes/metallb/ipaddresspool.yaml` dosyasını oluştur:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: local-pool
  namespace: metallb-system
spec:
  addresses:
    - 172.18.1.200-172.18.1.220   # docker network inspect ile bul
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

```bash
kubectl apply -f kubernetes/metallb/ipaddresspool.yaml
```

### Adım 6: Ingress-NGINX Kur

`kubernetes/ingress-nginx/values.yaml` dosyasını oluştur:
```yaml
controller:
  service:
    type: LoadBalancer
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true   # Prometheus scrape için
  config:
    use-forwarded-headers: "true"
    proxy-body-size: "10m"
```

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f kubernetes/ingress-nginx/values.yaml \
  --wait --timeout 3m

# LoadBalancer IP'sini al (MetalLB atamalı)
kubectl get svc -n ingress-nginx ingress-nginx-controller
# EXTERNAL-IP sütununda 172.18.1.200 gibi bir IP görünmeli
```

📖 Resmi Dok: https://kubernetes.github.io/ingress-nginx/deploy/

### Adım 7: /etc/hosts Ayarı

Ingress hostname'lerini yerel makinenizde çözümlemek için:
```bash
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "$INGRESS_IP  app.example.com monitoring.example.com jenkins.example.com" \
  | sudo tee -a /etc/hosts
```

k3d'de LoadBalancer IP'si host makineden erişilebilir (Docker ağı üzerinden).

---

## Bölüm 4 — Uygulama: Minimal Go Servisi

### Case Study Ne İstiyor?

> *"HTTP sunucusu, query param'larını JSON olarak döndürür, Prometheus metrikleri
> ve health endpoint'i sağlar."*

Case study genellikle **herhangi bir dilde** yazılmış basit bir uygulama kabul eder —
önemli olan Kubernetes entegrasyonu. Biz minimal bir Go servisi yazıyoruz çünkü:
- Go binary'si küçük → Docker imajı küçük (~10 MB scratch image)
- Hızlı başlar → readiness probe timeout sorunu olmaz
- Prometheus client kütüphanesi Go için çok olgun
- Docker multi-stage build güzel örnek olur

### Adım 8: Go Modülü ve Bağımlılıklar

```bash
cd app
go mod init github.com/<kullanici>/dreamgames-case/app
go get github.com/prometheus/client_golang/prometheus
go get github.com/prometheus/client_golang/prometheus/promhttp
```

### Adım 9: Uygulama Kodu

`app/main.go` dosyasını oluştur:
```go
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	requestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "echo_requests_total",
			Help: "Total number of echo requests",
		},
		[]string{"status"},
	)
	requestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "echo_request_duration_seconds",
			Help:    "Request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"path"},
	)
)

func init() {
	prometheus.MustRegister(requestsTotal, requestDuration)
}

func echoHandler(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	defer func() {
		requestDuration.WithLabelValues("/api/echo").Observe(time.Since(start).Seconds())
	}()

	// X-Request-Id: upstream header veya üret
	requestID := r.Header.Get("X-Request-Id")
	if requestID == "" {
		requestID = fmt.Sprintf("%d", time.Now().UnixNano())
	}
	w.Header().Set("X-Request-Id", requestID)
	w.Header().Set("Content-Type", "application/json")

	params := map[string]string{}
	for k, vs := range r.URL.Query() {
		if len(vs) > 0 {
			params[k] = vs[0]
		}
	}

	if err := json.NewEncoder(w).Encode(params); err != nil {
		requestsTotal.WithLabelValues("500").Inc()
		return
	}
	requestsTotal.WithLabelValues("200").Inc()
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"UP"}`))
}

func main() {
	appMux := http.NewServeMux()
	appMux.HandleFunc("/api/echo", echoHandler)
	appMux.HandleFunc("/health", healthHandler)

	// Metrics ve health ayrı portta (9090) → production best practice
	// Port 8080: uygulama trafiği (dışa açık)
	// Port 9090: operasyonel endpoint'ler (sadece cluster içi)
	mgmtMux := http.NewServeMux()
	mgmtMux.Handle("/metrics", promhttp.Handler())
	mgmtMux.HandleFunc("/health", healthHandler)
	mgmtMux.HandleFunc("/ready", healthHandler)

	go func() {
		log.Println("Management server :9090")
		if err := http.ListenAndServe(":9090", mgmtMux); err != nil {
			log.Fatal(err)
		}
	}()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("App server :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, appMux))
}
```

> ⚠️ Go'da `fmt` paketini import etmek gerekir. `main.go` dosyasının başına
> `"fmt"` ekle. Tam dosya:

`app/main.go` (tam ve çalışır hali):
```go
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	requestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "echo_requests_total", Help: "Total echo requests"},
		[]string{"status"},
	)
	requestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{Name: "echo_request_duration_seconds", Buckets: prometheus.DefBuckets},
		[]string{"path"},
	)
)

func init() { prometheus.MustRegister(requestsTotal, requestDuration) }

func echoHandler(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	defer requestDuration.WithLabelValues("/api/echo").Observe(time.Since(start).Seconds())

	requestID := r.Header.Get("X-Request-Id")
	if requestID == "" {
		requestID = fmt.Sprintf("%d", time.Now().UnixNano())
	}
	w.Header().Set("X-Request-Id", requestID)
	w.Header().Set("Content-Type", "application/json")

	params := map[string]string{}
	for k, vs := range r.URL.Query() {
		if len(vs) > 0 {
			params[k] = vs[0]
		}
	}
	json.NewEncoder(w).Encode(params)
	requestsTotal.WithLabelValues("200").Inc()
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"UP"}`))
}

func main() {
	appMux := http.NewServeMux()
	appMux.HandleFunc("/api/echo", echoHandler)
	appMux.HandleFunc("/health", healthHandler)

	mgmtMux := http.NewServeMux()
	mgmtMux.Handle("/metrics", promhttp.Handler())
	mgmtMux.HandleFunc("/health", healthHandler)
	mgmtMux.HandleFunc("/ready", healthHandler)

	go func() {
		log.Fatal(http.ListenAndServe(":9090", mgmtMux))
	}()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Fatal(http.ListenAndServe(":"+port, appMux))
}
```

### Neden İki Port?

- **8080** → uygulama trafiği: Ingress'ten gelen kullanıcı istekleri
- **9090** → yönetim trafiği: Prometheus scrape, health check, readiness probe

Neden ayıralım?
1. **Güvenlik:** 9090 NetworkPolicy ile sadece monitoring namespace'ten erişilebilir.
   Kullanıcılar `/metrics` endpoint'ini göremez.
2. **Bağımsız kesme:** Uygulamayı yeniden başlatmadan monitoring endpoint'ini
   kapatıp açabilirsin.
3. **Production standartı:** Spring Boot Actuator, Go pprof, Node.js `/metrics`
   hepsi ayrı port önerir.

### Adım 10: Dockerfile (Multi-stage)

`app/Dockerfile`:
```dockerfile
# Stage 1: Bağımlılıkları önbelleğe al (go.mod/go.sum değişmediğinde bu katman yeniden build olmaz)
FROM golang:1.21-alpine AS deps
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

# Stage 2: Binary derle
FROM deps AS builder
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /echo-server .

# Stage 3: Minimal runtime image
# scratch = boş base image, sadece binary + CA sertifikaları
FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /echo-server /echo-server
EXPOSE 8080 9090
ENTRYPOINT ["/echo-server"]
```

**Multi-stage build neden?**
- `golang:1.21-alpine` ~300 MB → runtime'da gereksiz (compiler, kütüphane başlıkları, paket yöneticisi)
- `scratch` base image → sadece binary var → ~8 MB imaj
- Küçük imaj = daha az saldırı yüzeyi, daha hızlı pull, daha az depolama
- 📖 Multi-stage: https://docs.docker.com/build/building/multi-stage/

### Adım 11: Local Test

```bash
cd app
go test ./...    # test yoksa "? no test files" normal
go build ./...   # derleme hatası var mı?

docker build -t echo-server:local .
docker run --rm -p 8080:8080 -p 9090:9090 echo-server:local

# Başka terminalde test et
curl 'http://localhost:8080/api/echo?hello=world&foo=bar'
# Beklenen: {"foo":"bar","hello":"world"}

curl 'http://localhost:9090/health'
# Beklenen: {"status":"UP"}

curl 'http://localhost:9090/metrics' | head -20
# Beklenen: # HELP echo_requests_total ...
```

### Adım 12: Docker Hub'a Push

```bash
# Docker Hub hesabın yoksa: https://hub.docker.com/signup
docker login

# Tag ve push
docker build -t <dockerhub_kullanici>/echo-server:1.0.0 .
docker push <dockerhub_kullanici>/echo-server:1.0.0
cd ..
```

> ⚠️ `:latest` tag kullanma! Mutable tag → farklı ortamlarda farklı imaj çalışabilir.
> Semantic versioning veya `<build>-<commit-hash>` formatı kullan.

---

## Bölüm 5 — Kubernetes Kaynakları

### Case Study Ne İstiyor?

- Namespace izolasyonu (Pod Security Admission)
- HA deployment (replicas, PDB, topology spread)
- Otomatik ölçekleme (HPA)
- Ağ güvenliği (NetworkPolicy)
- Sıfır kesintili güncelleme (rolling update)

### Adım 13: Namespace'ler ve Pod Security Admission

`kubernetes/namespaces/namespaces.yaml`:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    # PSA restricted: root ile çalışma, privilege escalation, host network yasak
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    # Prometheus node-exporter host network gerektirir → baseline
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: jenkins
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: webhook-system
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Neden `restricted` vs `baseline`?**

`restricted` en katı seviye: root olarak çalışmayı, `allowPrivilegeEscalation`, host
network ve PID namespace'ini tamamen yasaklar. Uygulamamız buna uyuyor çünkü sıradan
bir HTTP servisi hiçbir host kaynak erişimi gerektirmez.

`monitoring` namespace'i `baseline` çünkü Prometheus `node-exporter` host network
(`hostNetwork: true`) kullanmak zorunda — node metriklerini okumak için. PSA bu durumu
`baseline` ile kabul eder, `restricted` reddeder.

📖 PSA Resmi Dok: https://kubernetes.io/docs/concepts/security/pod-security-admission/

```bash
kubectl apply -f kubernetes/namespaces/namespaces.yaml
kubectl get ns --show-labels | grep -E "app|monitoring|jenkins|webhook"
```

### Adım 14: ServiceAccount

`kubernetes/app/serviceaccount.yaml`:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: echo-server
  namespace: app
automountServiceAccountToken: false
```

**Neden `automountServiceAccountToken: false`?**

Varsayılan olarak her pod, Kubernetes API'ye erişim sağlayan bir token alır
(`/var/run/secrets/kubernetes.io/serviceaccount/token`). Uygulamamız Kubernetes API'ye
hiç ihtiyaç duymaz. Bu token'ı silersek, pod ele geçirilse bile saldırgan cluster API'ye
erişemez. Saldırı yüzeyini sıfıra indiriyoruz.

📖 ServiceAccount: https://kubernetes.io/docs/concepts/security/service-accounts/

### Adım 15: Deployment

`kubernetes/app/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
  namespace: app
spec:
  replicas: 4
  selector:
    matchLabels:
      app: echo-server
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0    # güncelleme sırasında hiç pod kaldırılmaz
  template:
    metadata:
      labels:
        app: echo-server
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: echo-server
      # Pod'ları farklı node'lara yay (tek node çökmesine karşı)
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: echo-server
      containers:
        - name: echo-server
          image: <dockerhub_kullanici>/echo-server:1.0.0
          ports:
            - containerPort: 8080
              name: http
            - containerPort: 9090
              name: management
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
          # Readiness: trafik gelmeden önce hazır olmalı
          readinessProbe:
            httpGet:
              path: /ready
              port: 9090
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3
          # Liveness: pod dondu mu kontrol
          livenessProbe:
            httpGet:
              path: /health
              port: 9090
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 3
          # Graceful shutdown: Kubernetes terminate sinyali verince 5 sn bekle
          # Bu sürede uçuştaki istekler tamamlanır
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 5"]
          env:
            - name: PORT
              value: "8080"
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534    # nobody user
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
```

**Kritik kararların açıklaması:**

`maxUnavailable: 0` — Güncelleme sırasında mevcut pod'lar silinmeden önce yeni pod'lar
ayağa kalkar. `maxSurge: 1` → güncelleme sırasında toplam pod sayısı 4+1=5 olabilir.
Bu "sıfır kesintili güncelleme" sağlar.

`topologySpreadConstraints` — Pod'lar worker node'lara eşit dağıtılır. Eğer agent-0
çökerse agent-1'de en az 2 pod çalışır, servis devam eder. `DoNotSchedule` →
imkansız dağılım varsa pod'u schedule etme (pending bırak) — dağılımı zorla.

`readinessProbe` port 9090 — Prometheus metrics port'undan health check yapıyoruz.
Management port'u hazır değilse app port'u da hazır değildir. Uygulama tam başlamadan
trafik gelmez.

`preStop: sleep 5` — Kubernetes pod'u terminate etmeden önce `SIGTERM` gönderir ve
5 saniye bekler. Bu sürede yeni istekler gelmez (Service pod'u çoktan deregistered
etti), ama uçuştaki istekler tamamlanır. `terminationGracePeriodSeconds: 30` toplam
süre üst limiti.

`runAsNonRoot + allowPrivilegeEscalation: false + capabilities: drop ALL` — En katı
container güvenlik profili. Container'ın host'a zarar veremeyeceğini garanti eder.
PSA `restricted` bu alanları zorunlu kılar.

📖 Rolling Update: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment
📖 Probes: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
📖 TopologySpread: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/

### Adım 16: Service ve Ingress

`kubernetes/app/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: echo-server
  namespace: app
spec:
  selector:
    app: echo-server
  ports:
    - name: http
      port: 80
      targetPort: 8080
    - name: management
      port: 9090
      targetPort: 9090
```

`kubernetes/app/ingress.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo-server
  namespace: app
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
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
                name: echo-server
                port:
                  number: 80
```

### Adım 17: HPA (Horizontal Pod Autoscaler)

`kubernetes/app/hpa.yaml`:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: echo-server
  namespace: app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: echo-server
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
      stabilizationWindowSeconds: 300    # 5 dk stabilizasyon → ani ölçek küçültme yok
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Pods
          value: 4
          periodSeconds: 15
```

**Neden 4 minimum replica?**

PDB ile `maxUnavailable: 1` diyoruz. 4 pod olursa node drain sırasında 3 pod çalışır,
servis devam eder. 2 pod ile `maxUnavailable: 1` → drain sırasında tek pod kalır,
herhangi bir hata felaket olur.

**Neden `scaleDown.stabilizationWindowSeconds: 300`?**

HPA her 15 saniyede metrik toplar. Ani bir yük düşüşünde pod sayısını hemen azaltırsa:
1. Pod'lar terminate edilir (graceful ama yavaş)
2. Yük tekrar gelir
3. Yeni pod'lar schedule/start eder (10-30 saniye)
4. Bu sürede darboğaz yaşanır

5 dakika stabilizasyon penceresi → "yük gerçekten düştü mü?" diye bekler.

📖 HPA: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

### Adım 18: PodDisruptionBudget

`kubernetes/app/pdb.yaml`:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: echo-server
  namespace: app
spec:
  selector:
    matchLabels:
      app: echo-server
  maxUnavailable: 1
```

**Neden PDB?**

`kubectl drain node` komutu (node maintenance, upgrade) podları tahliye eder. PDB olmadan
Kubernetes tüm pod'ları aynı anda silebilir → servis kesintisi. PDB ile `maxUnavailable: 1`
→ `kubectl drain` en fazla 1 pod'u aynı anda kaldırır.

Cluster upgrade senaryosu: 4 pod × 2 node. Node 1 drain edildiğinde max 1 pod kaldırılır.
Yeni pod'lar schedule edilir. Node 1 upgrade tamamlanır. Node 2 drain edilir. Servis hiç
kesilmeden upgrade tamamlanır.

📖 PDB: https://kubernetes.io/docs/tasks/run-application/configure-pdb/

### Adım 19: NetworkPolicy (Sıfır Güven Ağ Modeli)

`kubernetes/app/networkpolicy.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: echo-server-default-deny
  namespace: app
spec:
  podSelector: {}    # namespace'teki tüm pod'lara uygula
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: echo-server-allow
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: echo-server
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Sadece ingress-nginx controller'dan gelen HTTP trafiği
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - port: 8080
          protocol: TCP
    # Sadece monitoring namespace'ten gelen metrics scrape
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - port: 9090
          protocol: TCP
  egress:
    # DNS çözümlemesi (CoreDNS)
    - to:
        - namespaceSelector: {}
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

**Neden default-deny?**

"Zero Trust Networking" prensibi: hiçbir şeye güvenme, her şeyi açıkça izinlendir.
Varsayılan olarak tüm pod-to-pod trafiği yasak. İzin verilen trafik listeyle belirlenir.

Pratik güvenlik etkisi: Eğer app namespace'deki bir pod güvenliği açığı nedeniyle
ele geçirilirse, saldırgan diğer namespace'lere (monitoring, jenkins, webhook-system)
erişemez. Network segmentasyonu lateral movement'ı önler.

📖 NetworkPolicy: https://kubernetes.io/docs/concepts/services-networking/network-policies/

### Adım 20: Tüm Kaynakları Deploy Et

```bash
kubectl apply -f kubernetes/namespaces/
kubectl apply -f kubernetes/app/

# Rollout durumunu izle
kubectl rollout status deployment/echo-server -n app --timeout=120s

# Pod dağılımını kontrol et (farklı node'larda mı?)
kubectl get pods -n app -o wide

# Smoke test
curl 'http://app.example.com/api/echo?hello=world'
# Beklenen: {"hello":"world"}
```

### Adım 21: Sıfır Kesintili Güncelleme Testi

```bash
# Terminal 1: Sürekli istek at, HTTP status kodunu izle
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" 'http://app.example.com/api/echo?x=1'
  sleep 0.3
done

# Terminal 2: Image'ı güncelle (yeni tag push et önce)
docker build -t <kullanici>/echo-server:1.0.1 app/
docker push <kullanici>/echo-server:1.0.1

kubectl set image deployment/echo-server \
  echo-server=<kullanici>/echo-server:1.0.1 -n app

kubectl rollout status deployment/echo-server -n app
```

Terminal 1'de sürekli `200` görünmeli. `maxUnavailable: 0` sayesinde güncelleme
sırasında bile aktif pod sayısı 4'ün altına inmez.

Rollback gerekirse:
```bash
kubectl rollout undo deployment/echo-server -n app
```

---

## Bölüm 6 — Jenkins CI/CD

### Case Study Ne İstiyor?

- Otomatik build pipeline: test → build → scan → push
- Otomatik deploy pipeline: manifest doğrulama → deploy → rollout verify
- Image vulnerability scanning
- Immutable image tag (`:latest` yasak)

### Adım 22: Jenkins için Persistent Storage

Jenkins konfigürasyonunun pod yeniden başlatmalarında kaybolmaması için PersistentVolume
gerekir. k3d ortamında `local-path` provisioner varsayılan olarak gelir:

`kubernetes/jenkins/storageclass.yaml` — k3d'de gerek yok, `local-path` zaten var.
Doğrula:
```bash
kubectl get storageclass
# local-path (default) olmalı
```

`kubernetes/jenkins/pvc.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pvc
  namespace: jenkins
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

### Adım 23: Jenkins Secrets (Asla Hardcode Etme)

```bash
# DockerHub token: https://hub.docker.com/settings/security → New Access Token
# GitHub token: https://github.com/settings/tokens → Fine-grained

kubectl create secret generic jenkins-credentials \
  --from-literal=admin-password="$(openssl rand -base64 24)" \
  --from-literal=dockerhub-user=<DOCKERHUB_KULLANICI> \
  --from-literal=dockerhub-token=<DOCKERHUB_TOKEN> \
  --from-literal=github-token=<GITHUB_TOKEN> \
  -n jenkins
```

> ⚠️ Bu komuttaki gerçek değerleri terminale girmeden önce şifre yöneticinden kopyala.
> `history -c` ile terminal geçmişini temizle. Secret değerleri Git'e asla commit etme.

### Adım 24: Jenkins Helm Values

`kubernetes/jenkins/values.yaml`:
```yaml
controller:
  serviceType: LoadBalancer    # MetalLB'den IP alır
  ingress:
    enabled: true
    hostName: jenkins.example.com
    ingressClassName: nginx

  # JCasC: Jenkins başlayınca otomatik konfigüre olur
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
                      description: "Docker Hub credentials"
                  - string:
                      scope: GLOBAL
                      id: "github-token"
                      secret: ${GITHUB_TOKEN}
                      description: "GitHub token"

  # Secrets'tan environment variable oku
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
    - workflow-aggregator:latest    # Pipeline plugin
    - docker-workflow:latest
    - kubernetes:latest
    - blueocean:latest

persistence:
  existingClaim: jenkins-pvc
```

**Neden JCasC (Jenkins Configuration as Code)?**

JCasC olmadan Jenkins'i her başlatmada UI üzerinden konfigüre etmen gerekir. JCasC ile:
- Tüm konfigürasyon Git'te → review edilebilir, rollback edilebilir
- `helm upgrade` → Jenkins otomatik güncellenir
- Disaster recovery: Jenkins pod'u sil → yeniden başlat → konfigürasyon geri gelir

📖 JCasC: https://www.jenkins.io/projects/jcasc/

```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update
kubectl apply -f kubernetes/jenkins/pvc.yaml
helm install jenkins jenkins/jenkins \
  -n jenkins --create-namespace \
  -f kubernetes/jenkins/values.yaml \
  --wait --timeout 5m

# Erişim
kubectl get svc -n jenkins jenkins
# jenkins.example.com veya LoadBalancer IP'si
```

### Adım 25: Build Pipeline (Jenkinsfile.build)

`jenkins/Jenkinsfile.build`:
```groovy
pipeline {
    agent any
    environment {
        REGISTRY = "docker.io"
        IMAGE_NAME = "<kullanici>/echo-server"
        // :latest KULLANMA — mutable tag güvenlik riski, hangi kod çalıştığı belli olmaz
        IMAGE_TAG = "${BUILD_NUMBER}-${GIT_COMMIT.take(7)}"
    }
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Test') {
            steps {
                dir('app') {
                    sh 'go test ./... -v -count=1'
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
            // Trivy: container image zafiyet taraması
            // HIGH ve CRITICAL seviyede CVE varsa pipeline durur
            steps {
                sh """
                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image \
                      --exit-code 1 \
                      --severity HIGH,CRITICAL \
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
                        echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker logout
                    """
                }
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

**Neden Trivy?**

Trivy, container imajlarındaki OS paket ve uygulama bağımlılıklarındaki bilinen güvenlik
açıklarını (CVE) tarar. `--exit-code 1` → HIGH/CRITICAL CVE bulunursa pipeline hata verir
ve imaj push edilmez. Böylece güvenlik açıklı kod production'a ulaşamaz.

📖 Trivy: https://aquasecurity.github.io/trivy/
📦 Trivy GitHub: https://github.com/aquasecurity/trivy

### Adım 26: Deploy Pipeline (Jenkinsfile.deploy)

`jenkins/Jenkinsfile.deploy`:
```groovy
pipeline {
    agent any
    parameters {
        string(name: 'IMAGE_TAG', description: 'Deploy edilecek image tag (örn: 42-abc1234)')
    }
    environment {
        IMAGE_NAME = "<kullanici>/echo-server"
        NAMESPACE = "app"
        DEPLOYMENT = "echo-server"
    }
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Validate Manifest') {
            // --dry-run=client: gerçek değişiklik yapmadan manifest'i doğrula
            steps {
                sh """
                    sed "s|IMAGE_TAG|${params.IMAGE_TAG}|g" \
                        kubernetes/app/deployment.yaml | \
                    kubectl apply --dry-run=client -f -
                """
            }
        }
        stage('Deploy') {
            steps {
                sh """
                    kubectl set image deployment/${DEPLOYMENT} \
                        ${DEPLOYMENT}=${IMAGE_NAME}:${params.IMAGE_TAG} \
                        -n ${NAMESPACE}
                """
            }
        }
        stage('Verify Rollout') {
            steps {
                script {
                    def result = sh(
                        script: "kubectl rollout status deployment/${DEPLOYMENT} -n ${NAMESPACE} --timeout=3m",
                        returnStatus: true
                    )
                    if (result != 0) {
                        sh "kubectl rollout undo deployment/${DEPLOYMENT} -n ${NAMESPACE}"
                        error("Rollout failed — automatic rollback executed")
                    }
                }
            }
        }
        stage('Smoke Test') {
            steps {
                sh """
                    sleep 5
                    curl -sf --max-time 10 \
                        'http://app.example.com/api/echo?smoke=true' | \
                    grep -q smoke || exit 1
                    echo "Smoke test passed"
                """
            }
        }
    }
}
```

---

## Bölüm 7 — Monitoring Stack

### Case Study Ne İstiyor?

- Prometheus: metrik toplama ve alerting
- Grafana: dashboard ve görselleştirme
- AlertManager: uyarı yönetimi (Slack vb.)
- Uygulama RED metrikleri (Rate, Error, Duration)
- Sistem metrikleri (node CPU/memory/disk)

### Neden kube-prometheus-stack?

Prometheus, Grafana, AlertManager, node-exporter, kube-state-metrics hepsini ayrı
ayrı deploy etmek yerine `kube-prometheus-stack` Helm chart'ı tümünü birlikte kurar,
ServiceMonitor CRD'leri ile otomatik scrape konfigürasyonu sağlar.

📖 kube-prometheus-stack: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
📖 Prometheus Operator: https://prometheus-operator.dev/

### Adım 27: Secret'lar (Asla Hardcode Etme)

```bash
# Grafana admin şifresi
kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)"

# Slack webhook (eğer AlertManager → Slack istiyorsan)
# Slack webhook oluştur: https://api.slack.com/messaging/webhooks
kubectl create secret generic alertmanager-slack-secret -n monitoring \
  --from-literal=webhookUrl='https://hooks.slack.com/services/...'
```

### Adım 28: kube-prometheus-stack Values

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
  # Secret'tan admin şifresini al
  admin:
    existingSecret: grafana-admin-secret
    userKey: admin-user
    passwordKey: admin-password
  # grafana_dashboard: "1" label'ı olan ConfigMap'leri otomatik yükle
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard

prometheus:
  prometheusSpec:
    # Tüm namespace'lerdeki ServiceMonitor'ları izle
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelector:
      matchLabels: {}
    ruleSelectorNilUsesHelmValues: false

alertmanager:
  alertmanagerSpec:
    externalUrl: "http://monitoring.example.com/alertmanager"
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ["alertname", "namespace"]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: "slack-notifications"
    receivers:
      - name: "slack-notifications"
        slack_configs:
          - api_url_secret:
              name: alertmanager-slack-secret
              key: webhookUrl
            channel: "#alerts"
            title: "{{ .GroupLabels.alertname }}"
            text: "{{ range .Alerts }}{{ .Annotations.description }}\n{{ end }}"
```

```bash
kubectl create namespace monitoring
kubectl apply -f kubernetes/namespaces/namespaces.yaml    # PSA etiketlerini uygula

kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f kubernetes/monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m
```

### Adım 29: PrometheusRule (Uyarı Kuralları)

`kubernetes/monitoring/alertmanager-rules.yaml`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dreamgames-app-alerts
  namespace: monitoring
  labels:
    prometheus: kube-prometheus
    role: alert-rules
spec:
  groups:
    - name: app.rules
      rules:
        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total{namespace="app"}[15m]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod {{ $labels.pod }} crash looping"
            description: "Pod {{ $labels.namespace }}/{{ $labels.pod }} yeniden başlıyor. Logları kontrol et: kubectl logs -n {{ $labels.namespace }} {{ $labels.pod }}"
            runbook: "1. kubectl describe pod -n app {{ $labels.pod }}\n2. kubectl logs -n app {{ $labels.pod }} --previous\n3. OOMKilled ise memory limit artır"

        - alert: HighRequestLatency
          expr: |
            histogram_quantile(0.95,
              sum(rate(echo_request_duration_seconds_bucket{namespace="app"}[5m])) by (le)
            ) > 1.0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "p95 latency > 1 saniye"
            description: "Son 5 dakikada p95 response time 1 saniyeyi aştı."
            runbook: "1. kubectl top pods -n app\n2. HPA durumunu kontrol et\n3. Hedef servis loglarına bak"

        - alert: HighErrorRate
          expr: |
            sum(rate(echo_requests_total{status=~"5..",namespace="app"}[5m])) /
            sum(rate(echo_requests_total{namespace="app"}[5m])) * 100 > 5
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "5xx hata oranı %5 üzerinde"
            description: "Son 5 dakikada HTTP 5xx oranı %{{ $value | printf \"%.1f\" }}."

        - alert: HPAMaxedOut
          expr: kube_horizontalpodautoscaler_status_current_replicas{namespace="app"} >= kube_horizontalpodautoscaler_spec_max_replicas{namespace="app"}
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "HPA maksimum replica sayısına ulaştı"
            description: "Kapasite planlaması gerekiyor. maxReplicas artırılmalı veya kaynak optimizasyonu yapılmalı."

        - alert: NodeHighCPU
          expr: 100 - (avg by(node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Node CPU kullanımı %85 üzerinde"
            description: "Node {{ $labels.node }} yüksek CPU kullanımı."

        - alert: NodeHighMemory
          expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Node bellek kullanımı %85 üzerinde"

        - alert: PodNotReady
          expr: kube_pod_status_ready{namespace="app",condition="true"} == 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod hazır değil: {{ $labels.pod }}"

        - alert: DeploymentReplicasMismatch
          expr: kube_deployment_spec_replicas{namespace="app"} != kube_deployment_status_available_replicas{namespace="app"}
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Deployment replica sayısı tutarsız"
```

```bash
kubectl apply -f kubernetes/monitoring/alertmanager-rules.yaml
kubectl get prometheusrule -n monitoring
```

### Adım 30: Grafana Dashboard

`kubernetes/monitoring/grafana-dashboards/app-metrics-configmap.yaml`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-app
  namespace: monitoring
  labels:
    grafana_dashboard: "1"    # Grafana sidecar bu label'ı izler, otomatik yükler
data:
  app-metrics.json: |
    {
      "title": "echo-server — RED Metrics",
      "uid": "dreamgames-echo",
      "schemaVersion": 38,
      "refresh": "30s",
      "time": { "from": "now-1h", "to": "now" },
      "panels": [
        {
          "id": 1,
          "title": "Request Rate (RPS)",
          "type": "timeseries",
          "gridPos": { "x": 0, "y": 0, "w": 8, "h": 8 },
          "targets": [{
            "expr": "sum(rate(echo_requests_total{namespace=\"app\"}[2m])) by (status)",
            "legendFormat": "status {{ status }}"
          }]
        },
        {
          "id": 2,
          "title": "Error Rate (5xx %)",
          "type": "timeseries",
          "gridPos": { "x": 8, "y": 0, "w": 8, "h": 8 },
          "targets": [{
            "expr": "sum(rate(echo_requests_total{status=\"500\",namespace=\"app\"}[2m])) / sum(rate(echo_requests_total{namespace=\"app\"}[2m])) * 100",
            "legendFormat": "5xx %"
          }]
        },
        {
          "id": 3,
          "title": "Latency Percentiles",
          "type": "timeseries",
          "gridPos": { "x": 16, "y": 0, "w": 8, "h": 8 },
          "targets": [
            {
              "expr": "histogram_quantile(0.50, sum(rate(echo_request_duration_seconds_bucket{namespace=\"app\"}[2m])) by (le))",
              "legendFormat": "p50"
            },
            {
              "expr": "histogram_quantile(0.95, sum(rate(echo_request_duration_seconds_bucket{namespace=\"app\"}[2m])) by (le))",
              "legendFormat": "p95"
            },
            {
              "expr": "histogram_quantile(0.99, sum(rate(echo_request_duration_seconds_bucket{namespace=\"app\"}[2m])) by (le))",
              "legendFormat": "p99"
            }
          ]
        },
        {
          "id": 4,
          "title": "HPA Current / Max Replicas",
          "type": "stat",
          "gridPos": { "x": 0, "y": 8, "w": 6, "h": 4 },
          "targets": [
            {
              "expr": "kube_horizontalpodautoscaler_status_current_replicas{namespace=\"app\"}",
              "legendFormat": "current"
            },
            {
              "expr": "kube_horizontalpodautoscaler_spec_max_replicas{namespace=\"app\"}",
              "legendFormat": "max"
            }
          ]
        },
        {
          "id": 5,
          "title": "Pod Restart Count (1h)",
          "type": "stat",
          "gridPos": { "x": 6, "y": 8, "w": 6, "h": 4 },
          "targets": [{
            "expr": "sum(increase(kube_pod_container_status_restarts_total{namespace=\"app\"}[1h]))",
            "legendFormat": "restarts"
          }]
        },
        {
          "id": 6,
          "title": "CPU Usage (millicores)",
          "type": "timeseries",
          "gridPos": { "x": 12, "y": 8, "w": 6, "h": 4 },
          "targets": [{
            "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"app\",container=\"echo-server\"}[2m])) by (pod) * 1000",
            "legendFormat": "{{ pod }}"
          }]
        },
        {
          "id": 7,
          "title": "Memory Usage",
          "type": "timeseries",
          "gridPos": { "x": 18, "y": 8, "w": 6, "h": 4 },
          "targets": [{
            "expr": "sum(container_memory_working_set_bytes{namespace=\"app\",container=\"echo-server\"}) by (pod)",
            "legendFormat": "{{ pod }}"
          }]
        }
      ]
    }
```

```bash
kubectl apply -f kubernetes/monitoring/grafana-dashboards/
# Grafana: http://monitoring.example.com/grafana → admin / <şifre>
```

---

## Bölüm 8 — Log Aggregation

### Case Study Ne İstiyor?

- Uygulama loglarının merkezi toplanması
- Yapısal (structured/JSON) log formatı
- Elasticsearch'te arama yapılabilir log

### Neden ECK + Fluent Bit?

- **ECK** (Elastic Cloud on Kubernetes): Elasticsearch'i K8s operator ile yönetir.
  Operator pattern: CRD ile cluster tanımla, operator lifecycle'ı yönetir.
- **Fluent Bit**: Her node'da DaemonSet olarak çalışır, tüm container loglarını okuyup
  Elasticsearch'e gönderir. Logstash'e göre çok daha hafif (~1 MB binary).

📖 ECK: https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-quickstart.html
📖 Fluent Bit: https://docs.fluentbit.io/manual/

### Adım 31: ECK Operator ve Elasticsearch

```bash
# ECK CRD ve operator kur
kubectl create -f https://download.elastic.co/downloads/eck/2.11.1/crds.yaml
kubectl apply  -f https://download.elastic.co/downloads/eck/2.11.1/operator.yaml
```

`kubernetes/monitoring/elasticsearch/elasticsearch.yaml`:
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
      count: 1    # dev için 1 node yeterli, prod'da 3+
      config:
        node.store.allow_mmap: false    # k3d'de mmap sorunlu
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
kubectl apply -f kubernetes/monitoring/elasticsearch/elasticsearch.yaml

# Hazır olana kadar bekle
kubectl get elasticsearch -n monitoring
# health: green beklenir (5-10 dakika sürebilir)
```

### Adım 32: Fluent Bit

`kubernetes/monitoring/fluent-bit/values.yaml`:
```yaml
daemonSetVolumes:
  - name: varlog
    hostPath:
      path: /var/log
  - name: varlibdockercontainers
    hostPath:
      path: /var/lib/docker/containers

daemonSetVolumeMounts:
  - name: varlog
    mountPath: /var/log
  - name: varlibdockercontainers
    mountPath: /var/lib/docker/containers
    readOnly: true

config:
  inputs: |
    [INPUT]
        Name tail
        Path /var/log/containers/echo-server*.log
        Parser docker
        Tag app.*
        Refresh_Interval 5

  filters: |
    [FILTER]
        Name kubernetes
        Match app.*
        Merge_Log On
        Keep_Log Off

  outputs: |
    [OUTPUT]
        Name es
        Match app.*
        Host dreamgames-es-http.monitoring.svc.cluster.local
        Port 9200
        HTTP_User elastic
        HTTP_Passwd ${ELASTIC_PASSWORD}
        tls On
        tls.verify Off
        Index app-logs
        Suppress_Type_Name On
```

```bash
# Elasticsearch şifresini al
ELASTIC_PASS=$(kubectl get secret dreamgames-es-elastic-user -n monitoring \
  -o jsonpath='{.data.elastic}' | base64 -d)

kubectl create secret generic elastic-credentials -n monitoring \
  --from-literal=ELASTIC_PASSWORD="$ELASTIC_PASS"

helm repo add fluent https://fluent.github.io/helm-charts
helm install fluent-bit fluent/fluent-bit \
  -n monitoring \
  -f kubernetes/monitoring/fluent-bit/values.yaml \
  --set envFrom[0].secretRef.name=elastic-credentials
```

---

## Bölüm 9 — Admission Webhook

### Case Study Ne İstiyor?

Her Deployment'ta `resources.requests.cpu` ve `resources.requests.memory` zorunlu olsun.
Eksik olan Deployment'lar reddedilsin.

### Neden Admission Webhook?

Kubernetes'te "policy as code" uygulamak için iki yol:
1. **OPA/Gatekeeper** veya **Kyverno** — hazır policy engine
2. **Custom webhook** — kendi Go/Python/Node.js sunucun

Case study custom webhook istiyor. Bu, Kubernetes Admission API'yi doğrudan anlaman
gerektiği anlamına geliyor.

Akış: `kubectl apply` → kube-apiserver → **ValidatingWebhookConfiguration** →
senin webhook sunucuna HTTP POST → izin ver/reddet → kube-apiserver manifest'i
cluster'a uygula veya hata dön.

📖 Admission Webhooks: https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/

### Adım 33: Go Webhook Kodu

```bash
mkdir webhook && cd webhook
go mod init github.com/<kullanici>/dreamgames-case/webhook
go get k8s.io/api/apps/v1@v0.29.0
go get k8s.io/apimachinery@v0.29.0
go get github.com/prometheus/client_golang/prometheus
go get github.com/prometheus/client_golang/prometheus/promhttp
```

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

	appsv1 "k8s.io/api/apps/v1"
	admissionv1 "k8s.io/api/admission/v1"
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
		[]string{"result"},
	)
	allowedNamespaces = map[string]bool{
		"app": true,
	}
)

func init() {
	_ = appsv1.AddToScheme(scheme)
	_ = admissionv1.AddToScheme(scheme)
	prometheus.MustRegister(validationsTotal)
}

func validateDeployment(deploy *appsv1.Deployment) (bool, string) {
	var violations []string

	checkContainers := func(containers []corev1.Container) {
		for _, c := range containers {
			if c.Resources.Requests.Cpu().IsZero() {
				violations = append(violations, fmt.Sprintf("container %q: resources.requests.cpu eksik", c.Name))
			}
			if c.Resources.Requests.Memory().IsZero() {
				violations = append(violations, fmt.Sprintf("container %q: resources.requests.memory eksik", c.Name))
			}
		}
	}

	checkContainers(deploy.Spec.Template.Spec.Containers)
	checkContainers(deploy.Spec.Template.Spec.InitContainers)

	if len(violations) > 0 {
		msg := "Deployment reddedildi — eksik resource request'ler:\n"
		for _, v := range violations {
			msg += "  - " + v + "\n"
		}
		return false, msg
	}
	return true, ""
}

func handleValidate(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "body okunamadı", http.StatusBadRequest)
		return
	}

	obj, gvk, err := codecs.UniversalDeserializer().Decode(body, nil, nil)
	if err != nil || gvk.Kind != "AdmissionReview" {
		http.Error(w, "AdmissionReview decode hatası", http.StatusBadRequest)
		return
	}

	review := obj.(*admissionv1.AdmissionReview)
	req := review.Request

	// Sadece izin verilen namespace'leri denetle
	if !allowedNamespaces[req.Namespace] {
		sendResponse(w, review, admissionResponse(req.UID, true, ""))
		return
	}

	var deploy appsv1.Deployment
	if err := json.Unmarshal(req.Object.Raw, &deploy); err != nil {
		sendResponse(w, review, admissionResponse(req.UID, true, ""))
		return
	}

	allowed, msg := validateDeployment(&deploy)
	if allowed {
		validationsTotal.WithLabelValues("allowed").Inc()
	} else {
		validationsTotal.WithLabelValues("rejected").Inc()
	}

	sendResponse(w, review, admissionResponse(req.UID, allowed, msg))
}

func admissionResponse(uid types.UID, allowed bool, msg string) *admissionv1.AdmissionResponse {
	resp := &admissionv1.AdmissionResponse{UID: uid, Allowed: allowed}
	if !allowed {
		resp.Result = &metav1.Status{
			Code:    422,
			Message: msg,
		}
	}
	return resp
}

func sendResponse(w http.ResponseWriter, review *admissionv1.AdmissionReview, resp *admissionv1.AdmissionResponse) {
	review.Response = resp
	review.Response.UID = review.Request.UID
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(review)
}

func main() {
	certFile := os.Getenv("TLS_CERT_FILE")
	keyFile  := os.Getenv("TLS_KEY_FILE")
	if certFile == "" { certFile = "/etc/webhook/certs/tls.crt" }
	if keyFile  == "" { keyFile  = "/etc/webhook/certs/tls.key" }

	// TLS sunucu (kube-apiserver buraya bağlanır)
	tlsCert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Fatalf("TLS sertifikası yüklenemedi: %v", err)
	}

	tlsServer := &http.Server{
		Addr: ":8443",
		TLSConfig: &tls.Config{Certificates: []tls.Certificate{tlsCert}},
	}
	http.HandleFunc("/validate", handleValidate)

	// Metrics sunucu (Prometheus buraya scrape eder, TLS gerektirmez)
	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		log.Fatal(http.ListenAndServe(":8080", mux))
	}()

	log.Println("Webhook sunucu başlatılıyor :8443 (TLS)")
	log.Fatal(tlsServer.ListenAndServeTLS("", ""))
}
```

> Not: `types.UID` için `k8s.io/apimachinery/pkg/types` import'u gerekir. Dosyanın
> tam import bloğuna ekle.

`webhook/Dockerfile`:
```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /webhook .

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /webhook /webhook
ENTRYPOINT ["/webhook"]
```

### Adım 34: TLS Sertifikası Oluştur

Webhook'un kube-apiserver ile TLS konuşması için self-signed sertifika yeterli, ama
`caBundle` alanına CA sertifikası yazılmalı.

`kubernetes/webhook/tls/generate-certs.sh`:
```bash
#!/bin/bash
set -e

NAMESPACE="webhook-system"
SERVICE="resource-webhook"
SECRET="resource-webhook-tls"

# Geçici dizin
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# CA oluştur
openssl genrsa -out "$TMPDIR/ca.key" 2048
openssl req -new -x509 -days 3650 -key "$TMPDIR/ca.key" \
  -subj "/CN=webhook-ca" -out "$TMPDIR/ca.crt"

# Webhook sertifikası oluştur
openssl genrsa -out "$TMPDIR/tls.key" 2048
openssl req -new -key "$TMPDIR/tls.key" \
  -subj "/CN=${SERVICE}.${NAMESPACE}.svc" \
  -out "$TMPDIR/tls.csr"

cat > "$TMPDIR/san.conf" << EOF
subjectAltName = DNS:${SERVICE}.${NAMESPACE}.svc,DNS:${SERVICE}.${NAMESPACE}.svc.cluster.local
EOF

openssl x509 -req -days 3650 \
  -in "$TMPDIR/tls.csr" \
  -CA "$TMPDIR/ca.crt" -CAkey "$TMPDIR/ca.key" -CAcreateserial \
  -extfile "$TMPDIR/san.conf" \
  -out "$TMPDIR/tls.crt"

# Secret oluştur (varsa güncelle)
kubectl create secret tls "$SECRET" \
  --cert="$TMPDIR/tls.crt" \
  --key="$TMPDIR/tls.key" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

# caBundle değerini al ve ValidatingWebhookConfiguration'a patch yap
CA_BUNDLE=$(base64 < "$TMPDIR/ca.crt" | tr -d '\n')
kubectl patch validatingwebhookconfiguration resource-requests-webhook \
  --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${CA_BUNDLE}\"}]"

echo "Sertifikalar oluşturuldu ve patch uygulandı."
```

### Adım 35: Webhook K8s Kaynakları

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
      serviceAccountName: resource-webhook
      containers:
        - name: resource-webhook
          image: <kullanici>/resource-webhook:1.0.0
          ports:
            - containerPort: 8443
              name: https
            - containerPort: 8080
              name: metrics
          volumeMounts:
            - name: certs
              mountPath: /etc/webhook/certs
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
```

`kubernetes/webhook/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: resource-webhook
  namespace: webhook-system
spec:
  selector:
    app: resource-webhook
  ports:
    - name: https
      port: 443
      targetPort: 8443
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
    timeoutSeconds: 5
    failurePolicy: Fail    # Webhook ulaşılamazsa deployment reddedilir
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: app
    rules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
    clientConfig:
      service:
        name: resource-webhook
        namespace: webhook-system
        path: /validate
      caBundle: ""    # generate-certs.sh tarafından doldurulur
```

```bash
kubectl create namespace webhook-system

# RBAC (webhook pod'una gerekli izinler)
cat > kubernetes/webhook/rbac.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: resource-webhook
  namespace: webhook-system
EOF
kubectl apply -f kubernetes/webhook/rbac.yaml

# Deploy sırasıyla yap
kubectl apply -f kubernetes/webhook/deployment.yaml
kubectl apply -f kubernetes/webhook/service.yaml
kubectl apply -f kubernetes/webhook/validatingwebhookconfiguration.yaml

# TLS sertifikası oluştur ve caBundle patch yap
chmod +x kubernetes/webhook/tls/generate-certs.sh
bash kubernetes/webhook/tls/generate-certs.sh

kubectl get pods -n webhook-system
```

### Neden `failurePolicy: Fail`?

Eğer webhook pod'u yanıt vermezse ne olacak?
- `Fail`: kube-apiserver webhook'a ulaşamazsa deployment'ı reddeder (güvenli taraf)
- `Ignore`: webhook yanıt vermezse deployment kabul edilir (güvensiz — policy devre dışı kalır)

Production'da `Fail` kullanılır çünkü "resource request zorunluluğu" bir güvenlik/
kapasite politikası. Webhook çöktüğünde bu politika atlanabilir olmamalı.

### Adım 36: Webhook Test

```bash
# Test 1: Resource request YOK → reddedilmeli
kubectl apply -n app -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bad-deploy
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
        - name: nginx
          image: nginx
          # resources: YOK → webhook reddeder
EOF

# Beklenen: "admission webhook denied the request"

# Test 2: Resource request VAR → kabul edilmeli
kubectl apply -n app -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: good-deploy
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
        - name: nginx
          image: nginx
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
EOF

# Beklenen: "deployment.apps/good-deploy created"

# Temizlik
kubectl delete deployment good-deploy -n app 2>/dev/null || true
```

---

## Bölüm 10 — İleri Senaryolar

### Senaryo A: KEDA ile Zamanlanmış Proaktif Ölçekleme

**Case Study Sorusu:** "Sabah 09:00'da yoğunluk var, önceden nasıl ölçeklenir?"

**Standart HPA problemi:** HPA reaktif — yoğunluk başladıktan sonra metrikleri ölçer,
threshold'u geçince ölçekler. Bu 2-5 dakika gecikme demek. Yeni pod'lar schedule +
start olurken kullanıcılar yavaş yanıt alır.

**KEDA çözümü:** CronTrigger ile 08:45'te minimum replica sayısını 12'ye çeker.
09:00 yoğunluğu başladığında pod'lar zaten hazır.

📖 KEDA: https://keda.sh/docs/latest/
📖 KEDA CronScaler: https://keda.sh/docs/latest/scalers/cron/
📦 KEDA GitHub: https://github.com/kedacore/keda

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda --namespace keda --create-namespace --wait

# Standart HPA'yı sil (KEDA ve HPA aynı Deployment'ı yönetemez)
kubectl delete hpa echo-server -n app
```

`step3-manifests/hpa-scheduled.yaml`:
```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: echo-server-scheduled
  namespace: app
spec:
  scaleTargetRef:
    name: echo-server
  minReplicaCount: 4
  maxReplicaCount: 16
  triggers:
    # CPU bazlı reaktif ölçekleme
    - type: cpu
      metricType: Utilization
      metadata:
        value: "70"
    # Sabah yoğunluğu öncesi proaktif ölçekleme (Türkiye saati UTC+3)
    - type: cron
      metadata:
        timezone: Europe/Istanbul
        start: "45 8 * * 1-5"    # Pazartesi-Cuma 08:45 → 12 pod hazır
        end:   "0 11 * * 1-5"   # 11:00'de normal'e dön
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
kubectl apply -f step3-manifests/hpa-scheduled.yaml
kubectl get scaledobject -n app
```

### Senaryo B: Canary Deployment

**Case Study Sorusu:** "Yeni versiyonu tüm kullanıcılara anında vermek yerine nasıl
kademeli açarsın?"

**Canary stratejisi:** Yeni versiyonu ayrı bir Deployment olarak deploy et, trafığin
%10'unu ona yönlendir. Grafana'da error rate ve latency artmıyorsa %50, %100'e çık.
Sorun çıkarsa canary Ingress'ini sil → %100 eski versiyona döner.

📖 Ingress-NGINX Canary: https://kubernetes.github.io/ingress-nginx/examples/canary/

`step3-manifests/canary-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server-canary
  namespace: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: echo-server-canary
  template:
    metadata:
      labels:
        app: echo-server-canary
    spec:
      containers:
        - name: echo-server
          image: <kullanici>/echo-server:2.0.0   # YENİ VERSİYON
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: echo-server-canary
  namespace: app
spec:
  selector:
    app: echo-server-canary
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo-server-canary
  namespace: app
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"   # %10 trafik
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
                name: echo-server-canary
                port:
                  number: 80
```

```bash
kubectl apply -f step3-manifests/canary-deployment.yaml

# Grafana'da hata rate'ini izle...

# %50'ye çıkar
kubectl annotate ingress echo-server-canary \
  nginx.ingress.kubernetes.io/canary-weight=50 -n app --overwrite

# Tam geçiş
kubectl annotate ingress echo-server-canary \
  nginx.ingress.kubernetes.io/canary-weight=100 -n app --overwrite

# Rollback: canary'yi sil → %100 eski versiyona döner
# kubectl delete ingress echo-server-canary -n app
```

### Senaryo C: PriorityClass ile Kaynak Preemption

**Case Study Sorusu:** "Cluster kaynak kıtlığındayken kritik uygulama mı, batch iş mi
önce çalışsın?"

📖 PriorityClass: https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/

`step3-manifests/priority-classes.yaml`:
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-realtime
value: 1000
globalDefault: false
description: "Gerçek zamanlı uygulamalar — kaynak kıtlığında batch'e önceliklidir"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority-batch
value: 100
globalDefault: false
description: "Batch işler — kaynak kıtlığında tahliye edilebilir"
```

`step3-manifests/app-x-deployment.yaml` (Gerçek zamanlı uygulama):
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
              cpu: 200m
              memory: 128Mi   # requests == limits → Guaranteed QoS (asla OOMKilled olmaz)
```

`step3-manifests/app-y-deployment.yaml` (Batch iş):
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
              cpu: 500m
              memory: 256Mi   # requests < limits → Burstable QoS (baskı altında tahliye edilebilir)
```

```bash
kubectl apply -f step3-manifests/priority-classes.yaml
kubectl apply -f step3-manifests/app-x-deployment.yaml
kubectl apply -f step3-manifests/app-y-deployment.yaml
kubectl get priorityclass
```

**QoS Sınıfları:**
- `Guaranteed`: requests == limits → en güçlü koruma, hiç tahliye edilmez
- `Burstable`: requests < limits → orta koruma
- `BestEffort`: requests ve limits yok → ilk tahliye edilecek

---

## Bölüm 11 — Doğrulama ve Temizlik

### Adım 37: Tam Sistem Doğrulaması

```bash
# Node'lar
kubectl get nodes -o wide
# 3 node Ready olmalı

# Pod'lar (Running olmayanları bul)
kubectl get pods -A | grep -Ev "Running|Completed|Succeeded"

# Uygulama
kubectl get pods -n app -o wide
# Pod'lar farklı node'larda mı? (topologySpread etkisi)

# HPA
kubectl describe hpa echo-server -n app
# Current Metrics: CPU kullanımı, replica sayısı

# PDB
kubectl get pdb -n app
# Disruptions Allowed: 1 (en az 3 pod ayakta)

# Smoke test
curl 'http://app.example.com/api/echo?test=123'
# Beklenen: {"test":"123"}

# X-Request-Id header kontrolü
curl -v 'http://app.example.com/api/echo?x=1' 2>&1 | grep X-Request-Id

# Webhook testi (resource request eksik → reddedilmeli)
kubectl apply -n app -f - << 'EOF' 2>&1 | grep -i "denied\|webhook"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webhook-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
        - name: test
          image: nginx
EOF

# Prometheus
curl -s 'http://monitoring.example.com/prometheus/-/healthy'
# Beklenen: Prometheus is Healthy.

# Grafana
echo "Grafana: http://monitoring.example.com/grafana"
echo "Şifre: $(kubectl get secret grafana-admin-secret -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)"

# Jenkins
echo "Jenkins: http://jenkins.example.com"
echo "Şifre: $(kubectl get secret jenkins-credentials -n jenkins -o jsonpath='{.data.admin-password}' | base64 -d)"
```

### Adım 38: Temizlik

```bash
# Cluster'ı sil (TÜM veri silinir)
k3d cluster delete dreamgames

# kubeconfig temizle
unset KUBECONFIG
# veya ~/.kube/config'den k3d satırlarını kaldır

# /etc/hosts temizle (macOS)
sudo sed -i '' '/example.com/d' /etc/hosts

# Docker imajları temizle (opsiyonel)
docker rmi $(docker images '<kullanici>/echo-server' -q) 2>/dev/null || true
```

---

## Özet: Case Study Değerlendirme Kriterleri

| Kriter | Çözüm | Dosya |
|--------|-------|-------|
| Multi-node K8s cluster | k3d (1 master + 2 worker) | Bu rehber Bölüm 2 |
| Uygulama: query param echo + metrics | Minimal Go servisi | `app/main.go` |
| Container güvenliği (non-root, caps drop) | securityContext | `kubernetes/app/deployment.yaml` |
| Yüksek erişilebilirlik | Replicas + PDB + topologySpread | `kubernetes/app/` |
| Sıfır kesintili güncelleme | RollingUpdate maxUnavailable:0 | `kubernetes/app/deployment.yaml` |
| Otomatik ölçekleme | HPA (CPU+memory) | `kubernetes/app/hpa.yaml` |
| Ağ güvenliği | NetworkPolicy default-deny | `kubernetes/app/networkpolicy.yaml` |
| CI/CD | Jenkins + Trivy scan + rollback | `jenkins/Jenkinsfile.*` |
| Monitoring | kube-prometheus-stack + alerts | `kubernetes/monitoring/` |
| Log aggregation | Fluent Bit + ECK | `kubernetes/monitoring/fluent-bit/` |
| Admission webhook | Go webhook + TLS | `webhook/` |
| Proaktif ölçekleme | KEDA CronTrigger | `step3-manifests/hpa-scheduled.yaml` |
| Canary deployment | Ingress-NGINX annotations | `step3-manifests/canary-deployment.yaml` |
| Kaynak yönetimi | PriorityClass + QoS | `step3-manifests/priority-*.yaml` |

---

## Referanslar

| Araç | Resmi Dökümantasyon |
|------|---------------------|
| k3d | https://k3d.io/ |
| kubectl | https://kubernetes.io/docs/reference/kubectl/ |
| Helm | https://helm.sh/docs/ |
| MetalLB | https://metallb.universe.tf/ |
| Ingress-NGINX | https://kubernetes.github.io/ingress-nginx/ |
| kube-prometheus-stack | https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack |
| KEDA | https://keda.sh/docs/latest/ |
| ECK | https://www.elastic.co/guide/en/cloud-on-k8s/current/ |
| Fluent Bit | https://docs.fluentbit.io/manual/ |
| Trivy | https://aquasecurity.github.io/trivy/ |
| Go Prometheus Client | https://pkg.go.dev/github.com/prometheus/client_golang |
| Kubernetes Admission Webhooks | https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/ |
| Pod Security Admission | https://kubernetes.io/docs/concepts/security/pod-security-admission/ |
| HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| PDB | https://kubernetes.io/docs/tasks/run-application/configure-pdb/ |
| NetworkPolicy | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| TopologySpreadConstraints | https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/ |
| PriorityClass | https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/ |
