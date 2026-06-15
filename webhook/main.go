package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	admissionv1 "k8s.io/api/admission/v1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	scheme = runtime.NewScheme()
	codecs = serializer.NewCodecFactory(scheme)

	validatedTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "webhook_validations_total",
		Help: "Total number of admission reviews processed",
	})
	rejectedTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "webhook_rejections_total",
		Help: "Total number of admission reviews rejected",
	})
	errorsTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "webhook_errors_total",
		Help: "Total number of webhook processing errors",
	})
	durationHist = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "webhook_request_duration_seconds",
		Help:    "Webhook request processing duration",
		Buckets: prometheus.DefBuckets,
	})
)

func allowedNamespaces() map[string]bool {
	ns := os.Getenv("WEBHOOK_NAMESPACES")
	if ns == "" {
		data, err := os.ReadFile("/etc/webhook/namespaces")
		if err == nil {
			ns = string(data)
		}
	}
	if ns == "" {
		ns = "default,app,production"
	}
	result := make(map[string]bool)
	for _, n := range strings.Split(strings.TrimSpace(ns), ",") {
		result[strings.TrimSpace(n)] = true
	}
	return result
}

func validateDeployment(ar *admissionv1.AdmissionReview) *admissionv1.AdmissionResponse {
	start := time.Now()
	defer func() {
		durationHist.Observe(time.Since(start).Seconds())
	}()

	validatedTotal.Inc()

	req := ar.Request
	namespace := req.Namespace

	if !allowedNamespaces()[namespace] {
		return &admissionv1.AdmissionResponse{
			UID:     req.UID,
			Allowed: true,
		}
	}

	var deployment appsv1.Deployment
	if _, _, err := codecs.UniversalDeserializer().Decode(req.Object.Raw, nil, &deployment); err != nil {
		errorsTotal.Inc()
		return &admissionv1.AdmissionResponse{
			UID:     req.UID,
			Allowed: false,
			Result: &metav1.Status{
				Message: fmt.Sprintf("could not decode deployment: %v", err),
				Code:    400,
			},
		}
	}

	var violations []string
	for _, container := range deployment.Spec.Template.Spec.Containers {
		if container.Resources.Requests == nil {
			violations = append(violations, fmt.Sprintf(
				"container %q: missing resource requests (cpu and memory required)", container.Name))
			continue
		}
		if _, ok := container.Resources.Requests[corev1.ResourceCPU]; !ok {
			violations = append(violations, fmt.Sprintf(
				"container %q: missing cpu request", container.Name))
		}
		if _, ok := container.Resources.Requests[corev1.ResourceMemory]; !ok {
			violations = append(violations, fmt.Sprintf(
				"container %q: missing memory request", container.Name))
		}
	}

	if len(violations) > 0 {
		rejectedTotal.Inc()
		msg := fmt.Sprintf("Deployment %q rejected — resource requests required:\n%s",
			deployment.Name, strings.Join(violations, "\n"))
		log.Printf("REJECT ns=%s deploy=%s violations=%v", namespace, deployment.Name, violations)
		return &admissionv1.AdmissionResponse{
			UID:     req.UID,
			Allowed: false,
			Result: &metav1.Status{
				Message: msg,
				Code:    422,
			},
		}
	}

	log.Printf("ALLOW ns=%s deploy=%s", namespace, deployment.Name)
	return &admissionv1.AdmissionResponse{
		UID:     req.UID,
		Allowed: true,
	}
}

func handleValidate(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "failed to read body", http.StatusBadRequest)
		return
	}

	if r.Header.Get("Content-Type") != "application/json" {
		http.Error(w, "expected Content-Type: application/json", http.StatusUnsupportedMediaType)
		return
	}

	var ar admissionv1.AdmissionReview
	if _, _, err := codecs.UniversalDeserializer().Decode(body, nil, &ar); err != nil {
		http.Error(w, fmt.Sprintf("could not decode admission review: %v", err), http.StatusBadRequest)
		return
	}

	ar.Response = validateDeployment(&ar)

	resp, err := json.Marshal(ar)
	if err != nil {
		http.Error(w, fmt.Sprintf("could not marshal response: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(resp)
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

func main() {
	tlsCert := os.Getenv("TLS_CERT_FILE")
	tlsKey := os.Getenv("TLS_KEY_FILE")
	if tlsCert == "" {
		tlsCert = "/etc/webhook/tls/tls.crt"
	}
	if tlsKey == "" {
		tlsKey = "/etc/webhook/tls/tls.key"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/validate", handleValidate)
	mux.HandleFunc("/health", handleHealth)

	server := &http.Server{
		Addr:         ":8443",
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	// Metrics served on plain HTTP port so Prometheus can scrape without TLS
	metricsMux := http.NewServeMux()
	metricsMux.Handle("/metrics", promhttp.Handler())
	metricsMux.HandleFunc("/health", handleHealth)
	metricsServer := &http.Server{
		Addr:         ":8080",
		Handler:      metricsMux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("Starting metrics server on :8080 (HTTP)")
		if err := metricsServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Metrics server failed: %v", err)
		}
	}()

	go func() {
		log.Printf("Starting webhook server on :8443 (TLS)")
		if err := server.ListenAndServeTLS(tlsCert, tlsKey); err != nil && err != http.ErrServerClosed {
			log.Fatalf("ListenAndServeTLS failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down servers...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = metricsServer.Shutdown(ctx)
	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}
	log.Println("Servers exited")
}
