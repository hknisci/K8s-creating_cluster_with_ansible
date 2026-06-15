# Kubernetes Upgrade Strategy

## Active Support Band (June 2026)

The Kubernetes project maintains the three most recent minor releases. As of June 2026:

| Release | Status | End of Support |
|---------|--------|---------------|
| 1.36 | Latest | ~April 2027 |
| 1.35 | Supported | ~December 2026 |
| 1.34 | Supported | ~August 2026 |
| 1.32 | Used here | Already EoL — upgrade ASAP |

This cluster runs **1.32** (case study minimum is 1.28; 1.32 chosen for modern API stability). A production cluster should be on **1.34 or newer**.

## Version Skew Policy

```
kubeadm ≥ kubelet = kubectl
control plane ≤ kubelet + 2 minor versions
kube-apiserver ≤ kubectl + 1 minor version
```

Key rule: always upgrade **kubeadm first**, then the control plane, then workers. Never skip minor versions.

## Upgrade Path (1.28 → 1.36)

```
1.28 → 1.29 → 1.30 → 1.31 → 1.32 → 1.33 → 1.34 → 1.35 → 1.36
```

Each hop must be performed one minor version at a time.

## Step-by-Step Procedure (per minor version)

### 1. Update Ansible variables

```yaml
# ansible/group_vars/all.yml
kubernetes_version: "1.33.0"   # bump one minor at a time
```

### 2. Upgrade kubeadm on control plane

```bash
# On master node
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.33.0-1.0
sudo apt-mark hold kubeadm
kubeadm upgrade plan
```

### 3. Apply the upgrade

```bash
sudo kubeadm upgrade apply v1.33.0
```

### 4. Drain and upgrade master kubelet

```bash
kubectl drain master --ignore-daemonsets --delete-emptydir-data
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.33.0-1.0 kubectl=1.33.0-1.0
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
kubectl uncordon master
```

### 5. Upgrade workers (one at a time)

```bash
# On each worker:
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get install -y kubeadm=1.33.0-1.0 kubelet=1.33.0-1.0 kubectl=1.33.0-1.0
sudo apt-mark hold kubeadm kubelet kubectl
sudo kubeadm upgrade node
sudo systemctl daemon-reload && sudo systemctl restart kubelet

# From control plane:
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data
# (upgrade worker1 kubelet as above)
kubectl uncordon worker1
```

### 6. Verify

```bash
kubectl get nodes                          # all nodes show new version
kubectl get pods -A | grep -v Running     # no degraded pods
```

## Pre-Upgrade Checklist

- [ ] etcd backup taken (`etcdctl snapshot save`)
- [ ] All node PVs and data backed up
- [ ] PDB allows eviction during drain (check `maxUnavailable`)
- [ ] Verify API deprecations for target version (`kubectl deprecations`)
- [ ] Test upgrade in staging first
- [ ] Rollback plan documented (restore etcd snapshot)

## etcd Backup (before every upgrade)

```bash
# On master node
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify snapshot
etcdctl snapshot status /backup/etcd-$(date +%Y%m%d).db
```

Schedule this as a CronJob or add to Ansible `ansible/roles/master/tasks/etcd-backup.yml`.

## Production HA Note

This cluster has a **single control plane** (Vagrant PoC constraint). For real production:
- Minimum 3 control plane nodes for etcd quorum
- External or stacked etcd with odd node count (3 or 5)
- LoadBalancer in front of API servers (HAProxy, AWS NLB, etc.)
- Consider managed Kubernetes (EKS, GKE, AKS) to offload upgrade management

## Calico and CNI Compatibility

Calico must be upgraded alongside Kubernetes. Refer to the [Calico compatibility matrix](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements).

| K8s version | Calico version |
|-------------|---------------|
| 1.32.x | v3.29.x |
| 1.33.x | v3.29.x |
| 1.34.x | v3.29.x+ |
