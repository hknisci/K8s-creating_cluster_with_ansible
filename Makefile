.PHONY: up verify build test clean webhook-build lint

# ── Cluster lifecycle ──────────────────────────────────────────────────────────
up:
	vagrant up

clean:
	vagrant destroy -f

# ── Build ──────────────────────────────────────────────────────────────────────
build:
	cd app && mvn clean package -DskipTests -q

test:
	cd app && mvn clean test -q
	cd webhook && go test ./... -count=1

webhook-build:
	cd webhook && docker build -t dreamgames/resource-webhook:local .

lint:
	cd app && mvn checkstyle:check -q
	cd webhook && go vet ./...

# ── Cluster verification (requires running cluster + KUBECONFIG set) ───────────
verify: _check-kubeconfig
	@echo "=== Nodes ==="
	kubectl get nodes -o wide
	@echo ""
	@echo "=== Unhealthy pods (any namespace) ==="
	@kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded' \
	  --no-headers 2>/dev/null | grep -v "^$$" || echo "  All pods healthy"
	@echo ""
	@echo "=== App smoke test ==="
	@curl -sf --max-time 5 \
	  "$$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
	       -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/api/echo?smoke=true" \
	  | grep -q "smoke" && echo "  /api/echo OK" || echo "  WARNING: /api/echo failed"
	@echo ""
	@echo "=== Webhook rejection test ==="
	@kubectl apply -f test/bad-deploy.yaml 2>&1 | grep -q "rejected\|denied\|forbidden" \
	  && echo "  Webhook REJECTED bad deploy (correct)" \
	  || echo "  WARNING: webhook did not reject bad deploy"
	@echo ""
	@echo "=== HPA status ==="
	kubectl get hpa -n app
	@echo ""
	@echo "=== PDB status ==="
	kubectl get pdb -n app
	@echo ""
	@echo "=== All checks complete ==="

_check-kubeconfig:
	@kubectl cluster-info > /dev/null 2>&1 || \
	  (echo "ERROR: kubectl cannot reach cluster. Set KUBECONFIG correctly." && exit 1)
