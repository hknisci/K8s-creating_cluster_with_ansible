# Step 3.3 — Deployment Strategy for Critical Applications

## Problem

A new version of a critical application must be deployed with minimum risk.
Any issues with the new version must not impact all users.

## Chosen Strategy: Canary Deployment

### Why Canary?

| Strategy | Risk | Rollback Speed | Resource Cost |
|----------|------|----------------|---------------|
| Rolling Update | Medium (all users eventually) | Slow (per-pod) | Low |
| Blue/Green | Low (switch is instant) | Instant | 2x resources |
| **Canary** | **Very Low (small % affected)** | **Fast (remove canary)** | **Low (~10% extra)** |

Canary is ideal because:
- Only a small percentage of users (e.g. 10%) see the new version initially.
- Issues affect a limited blast radius.
- We can observe metrics/errors for minutes before rolling forward.
- Resource cost is minimal vs. blue/green.

### Implementation with ingress-nginx

```yaml
# Canary ingress: 10% of traffic → new version
metadata:
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"
```

### Traffic Shift Steps

```
Step 1: Deploy canary (1 pod, 10% traffic)
         Monitor: error rate, p99 latency, business metrics
         Wait: 30 minutes

Step 2: If healthy → increase canary-weight to 30%
         Monitor another 30 minutes

Step 3: If healthy → increase to 50%, then 100%
         
Step 4: Delete stable deployment → canary becomes the only version
         Rename canary deployment to stable for next release

Rollback at any step: kubectl delete ingress query-param-app-canary
                      (instantly routes 100% back to stable)
```

### Header-Based Routing (for QA validation)

```yaml
nginx.ingress.kubernetes.io/canary-by-header: "X-Canary"
nginx.ingress.kubernetes.io/canary-by-header-value: "true"
```
This lets QA team test the canary with `curl -H "X-Canary: true"` before exposing to real users.

### Blue/Green Alternative

When rollback must be instant and resource cost is acceptable:
```bash
# Switch service selector from blue to green
kubectl patch service query-param-app \
  -p '{"spec":{"selector":{"track":"green"}}}'
# Rollback: switch back to blue
kubectl patch service query-param-app \
  -p '{"spec":{"selector":{"track":"blue"}}}'
```

**Sample manifests:** `step3-manifests/canary-deployment.yaml`, `blue-green-deployment.yaml`

## Reviewer Defense

> "I chose canary over blue/green because we don't have spare capacity to run a full
> duplicate environment. Canary with ingress-nginx weight annotations is simple, native
> to our existing ingress controller, and gives us full observability during the rollout.
> The key metric I watch during canary phase is the error rate delta between stable and
> canary pods in Grafana. If p99 latency or error rate increases by more than 5% vs
> baseline, I immediately delete the canary ingress — rollback in under 30 seconds."
