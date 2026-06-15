# Step 3.2 — Scheduled & Predictive Autoscaling

## Problem

Application traffic spikes at predictable times. We need to scale OUT before the spike
and scale IN after, without degrading performance. Cluster nodes may also need to scale.

## Application Scaling: KEDA CronTrigger

KEDA's CronTrigger pre-scales pods on a schedule, before traffic arrives.
This avoids the "cold start" penalty of reactive HPA.

```yaml
# Pods scale to 12 at 08:45, before 09:00 peak (15 min warm-up window)
triggers:
  - type: cron
    metadata:
      timezone: "Europe/Istanbul"
      start: "45 8 * * 1-5"
      end:   "00 18 * * 1-5"
      desiredReplicas: "12"
  # CPU-based HPA as safety net for unexpected spikes
  - type: cpu
    metadata:
      type: Utilization
      value: "70"
```

**Why KEDA over plain HPA for scheduling?**
- HPA is reactive (scales on current metrics, always lags behind spikes)
- KEDA CronTrigger is predictive (scales before the spike based on schedule)
- Both can run simultaneously: KEDA sets minimum, HPA adds capacity if CPU spikes anyway

## Node Scaling: Cluster Autoscaler

For on-premises physical nodes, we use a customized Cluster Autoscaler with a
**machine controller backend** (e.g., bare-metal provisioner or a simple Ansible hook):

```
Peak approaches → KEDA schedules pods → pods go Pending (no node capacity)
       → Cluster Autoscaler detects pending pods
       → Triggers node provisioning script (Ansible/API)
       → New node joins cluster
       → Pods scheduled on new node
```

For the case study's Vagrant setup:
1. Pre-provision additional Vagrant VMs but keep them `halt`-ed.
2. A CronJob runs before peak: `vagrant up worker3` → `kubeadm join`.
3. After peak: `kubectl drain worker3 --ignore-daemonsets` → `vagrant halt worker3`.

**Sample manifests:** `step3-manifests/hpa-scheduled.yaml`

## Reviewer Defense

> "KEDA CronTrigger is the right tool here because we KNOW when traffic spikes happen.
> Reactive HPA will always under-provision during the initial burst window. By scaling
> 15 minutes early, pods are warm and ready. The CPU-based trigger acts as a safety net
> for unexpected spikes. For nodes, the Cluster Autoscaler + pre-provisioned-but-offline
> VMs gives us fast scale-out without running excess capacity during off-peak hours."
