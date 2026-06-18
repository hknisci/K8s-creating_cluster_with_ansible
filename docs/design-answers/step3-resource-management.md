# Step 3.1 — Resource Management: App X vs App Y

## Problem

Two applications share a fixed-size cluster. App X requires high availability and
performance (real-time). App Y handles batch jobs and can tolerate interruption.

## Solution

### PriorityClass-Based Preemption

```yaml
# App X: Guaranteed QoS + high PriorityClass
priorityClassName: high-priority-realtime   # value: 1000
resources:
  requests: { cpu: 500m, memory: 256Mi }
  limits:   { cpu: 500m, memory: 256Mi }  # requests == limits → Guaranteed QoS

# App Y: Burstable QoS + low PriorityClass
priorityClassName: low-priority-batch       # value: 100
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 1000m, memory: 512Mi }  # limits > requests → Burstable QoS
```

### How It Works Under Pressure

1. Scheduler tries to place App X pod → insufficient resources.
2. Kubernetes evaluates lower-priority pods (App Y) for preemption.
3. App Y pods are evicted to free space for App X.
4. App Y restarts when resources are available again (batch jobs handle this gracefully).

### QoS Class Eviction Order

Under memory pressure, pods are evicted in this order:
1. BestEffort (no requests/limits) → evicted first
2. Burstable (requests < limits) → App Y
3. Guaranteed (requests == limits) → App X → evicted last

### Sample Manifests

See: `step3-manifests/priority-classes.yaml`, `app-x-deployment.yaml`, `app-y-deployment.yaml`

### Reviewer Defense

> "I chose PriorityClass with Guaranteed QoS for App X because it guarantees the kubelet
> will never OOM-kill it before the node is completely exhausted. Burstable QoS for App Y
> means it can burst when resources are free, but it's the first candidate for eviction —
> which is acceptable for batch workloads that can restart safely."
