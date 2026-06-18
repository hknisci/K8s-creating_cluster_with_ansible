# Step 3.4 — Replica Database Scaling & Cache Pre-Warm

## Problem

Traffic spikes increase load on replica databases. We need to:
a) Scale replicas before/during peak
b) Integrate new replicas with the application automatically
c) Pre-fill memory on replicas before traffic arrives

## a) Scaling Replica Instances

For Kubernetes-managed replicas (e.g., Redis cluster or MySQL with operator):

```yaml
# HPA on replica statefulset (custom metrics: queries/sec from Prometheus)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: mysql-replicas
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: mysql-replica
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: External
      external:
        metric:
          name: mysql_queries_per_second
          selector:
            matchLabels:
              role: replica
        target:
          type: AverageValue
          averageValue: "1000"
```

Alternatively, use KEDA with a Prometheus trigger for exact query rate:
```yaml
triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus.monitoring.svc:9090
      metricName: mysql_replica_queries_per_second
      threshold: "1000"
      query: sum(rate(mysql_global_status_queries[2m]))
```

## b) Integrating New Replicas with the Application

Use Kubernetes **headless Service** for replica discovery:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-replica
spec:
  clusterIP: None          # Headless: returns individual pod IPs
  selector:
    role: replica
  ports:
    - port: 3306
```

Application connection pool (e.g., HikariCP) uses the headless service DNS:
```yaml
spring:
  datasource:
    read-url: jdbc:mysql://mysql-replica.app.svc.cluster.local:3306/db
```

When a new replica pod starts and passes readiness probe, it automatically
appears in the headless service DNS — no application restart needed.

## c) Pre-Fill Memory (Cache Warm-Up)

Before peak traffic, run a warm-up Job that replays recent popular queries:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-cache-warmup
spec:
  schedule: "30 8 * * 1-5"    # 08:30 — before 09:00 peak
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: warmup
              image: dreamgames/db-warmup:latest
              command:
                - /bin/sh
                - -c
                - |
                  # Replay top-100 queries from slow query log
                  # This loads hot data into InnoDB buffer pool
                  mysql -h mysql-replica.app.svc.cluster.local \
                    -e "SELECT * FROM hot_table WHERE created_at > NOW() - INTERVAL 1 DAY LIMIT 10000"
              resources:
                requests:
                  cpu: 200m
                  memory: 256Mi
                limits:
                  cpu: 500m
                  memory: 512Mi
```

**Strategy:** Identify top-N queries from the previous day's slow query log.
Re-execute them against replicas 30 minutes before peak. This loads hot rows
into the InnoDB buffer pool, reducing cache miss rate during the spike.

## Reviewer Defense

> "For replica scaling, I prefer Prometheus-based KEDA triggers because they give us
> exact query rate as the scaling signal — much more accurate than CPU. For integration,
> the headless service pattern means zero application changes when a new replica starts:
> DNS automatically includes it once the readiness probe passes. The warmup CronJob is
> a pre-peak ritual — it costs CPU for 5-10 minutes but saves orders of magnitude in
> user-facing latency during the actual peak."
