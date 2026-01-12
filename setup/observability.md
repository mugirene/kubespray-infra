Absolutely, malaika — here’s a **step-by-step summary of everything you did** to build your full **observability stack** in Kubernetes using **Helm** (both metrics and logs).

I’ll capture every relevant step you ran or configured 👇

---

## 🧱 1️⃣ — Cluster & Storage Preparation

1. **Running environment:**

   * Open-source Kubernetes (deployed via **Kubespray**).
   * Using **Rook-Ceph** for persistent storage.

2. **Checked existing storage classes:**

   ```bash
   kubectl get storageclass
   ```

   Found:

   ```
   ceph-rbd (default)
   cephfs
   s3-buckets
   ```

3. **Created “retain” versions** so data isn’t deleted if PVCs are removed:

   ```bash
   kubectl get sc ceph-rbd -o yaml \
     | sed 's/name: ceph-rbd/name: ceph-rbd-retain/' \
     | sed 's/reclaimPolicy: Delete/reclaimPolicy: Retain/' \
     | kubectl apply -f -
   kubectl get sc cephfs -o yaml \
     | sed 's/name: cephfs/name: cephfs-retain/' \
     | sed 's/reclaimPolicy: Delete/reclaimPolicy: Retain/' \
     | kubectl apply -f -
   ```

4. **Cleaned up default annotations** so only one class is default:

   ```bash
   kubectl annotate storageclass ceph-rbd-retain storageclass.kubernetes.io/is-default-class="false" --overwrite
   kubectl annotate storageclass ceph-rbd storageclass.kubernetes.io/is-default-class="true" --overwrite
   ```

   ✅ `ceph-rbd` = default,
   ✅ `ceph-rbd-retain` = used for Prometheus/Grafana/Loki persistence.

---

## 📊 2️⃣ — Metrics Monitoring (Prometheus + Grafana)

1. **Created namespace:**

   ```bash
   kubectl create namespace observability
   ```

2. **(Optional) Created Grafana admin secret:**

   ```bash
   kubectl -n observability create secret generic grafana-admin-credentials \
     --from-literal=admin-user='adminuser' \
     --from-literal=admin-password='p@ssword!'
   ```

3. **Created `values-kps.yaml`:**

   ```yaml
   grafana:
     enabled: true
     persistence:
       enabled: true
       type: pvc
       size: 10Gi
       storageClassName: ceph-rbd-retain
     admin:
       existingSecret: grafana-admin-credentials
       userKey: admin-user
       passwordKey: admin-password
     service:
       type: ClusterIP

   alertmanager:
     enabled: false

   prometheus:
     prometheusSpec:
       retention: 15d
       storageSpec:
         volumeClaimTemplate:
           spec:
             storageClassName: ceph-rbd-retain
             accessModes: ["ReadWriteOnce"]
             resources:
               requests:
                 storage: 60Gi
   ```

4. **Pulled kube-prometheus-stack from the OCI registry (since `helm repo add` was failing):**

   ```bash
   export VER=79.0.0
   helm pull oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack --version $VER
   ```

5. **Installed using Helm (namespace observability):**

   ```bash
   helm upgrade --install prometheus kube-prometheus-stack-$VER.tgz \
     -n observability -f values-kps.yaml
   ```

6. **Verified:**

   ```bash
   kubectl get pods,pvc -n observability
   ```

7. **Accessed UIs via port-forward:**

   ```bash
   # Prometheus
   kubectl -n observability port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090

   # Grafana
   kubectl -n observability port-forward svc/prometheus-grafana 3000:80
   ```

   * Opened [http://localhost:9090](http://localhost:9090) → queried `up`.
   * Opened [http://localhost:3000](http://localhost:3000) → logged in with secret creds.

---

## 📜 3️⃣ — Log Aggregation (Loki + Promtail)

1. **Created `values-loki.yaml`:**

   ```yaml
   loki:
     auth_enabled: false
     storage:
       type: filesystem
     persistence:
       enabled: true
       storageClassName: ceph-rbd-retain
       size: 100Gi
     limits_config:
       retention_period: 168h
     compactor:
       retention_enabled: true

   singleBinary:
     replicas: 1

   gateway:
     enabled: false

   promtail:
     enabled: true
     resources:
       requests:
         cpu: 50m
         memory: 128Mi
     config:
       clients:
         - url: http://loki:3100/loki/api/v1/push
       snippets:
         pipelineStages:
           - cri: {}
   ```

2. **Installed Loki from the Grafana OCI registry:**

   ```bash
   helm show chart oci://ghcr.io/grafana/helm-charts/loki   # (to check version)
   export LOKI_VER=<version you selected>
   helm pull oci://ghcr.io/grafana/helm-charts/loki --version $LOKI_VER
   helm upgrade --install loki loki-$LOKI_VER.tgz \
     -n observability -f values-loki.yaml
   ```

3. **Verified deployment:**

   ```bash
   kubectl get pods,pvc -n observability
   ```

   * Saw `loki-*` pods running.
   * PVC bound to `ceph-rbd-retain` (~100Gi).

4. **Checked Loki API (optional):**

   ```bash
   kubectl -n observability port-forward svc/loki 3100:3100
   curl http://localhost:3100/loki/api/v1/labels
   ```

---

## 📈 4️⃣ — Grafana Integration

1. **In Grafana UI → Connections → Data sources → Add data source → Loki**

   * URL: `http://loki.observability.svc.cluster.local:3100`
   * Saved and tested: *“Data source is working.”*

2. **Explored logs in Grafana → Explore tab → Loki source**

   * Example queries:

     ```
     {namespace="default"}
     {pod=~"prometheus-.*"}
     ```

3. **Confirmed full persistence:**

   * Deleted a test pod → logs & metrics still visible.
   * Verified PVCs retained data on restart.

---

## 🧠 Final Architecture Summary

| Component      | Function             | Persistence (PVC) | StorageClass    | Namespace     |
| -------------- | -------------------- | ----------------- | --------------- | ------------- |
| **Prometheus** | Metrics store        | ✅ 60 Gi           | ceph-rbd-retain | observability |
| **Grafana**    | Dashboards / UI      | ✅ 10 Gi           | ceph-rbd-retain | observability |
| **Loki**       | Log storage          | ✅ 100 Gi          | ceph-rbd-retain | observability |
| **Promtail**   | Log shipper (agents) | ❌ (ephemeral)     | —               | observability |

---

You now have a **complete open-source observability stack**:

* Metrics, logs, and dashboards — all persisted on Ceph PVCs.
* Survive pod deletion, node restarts, or Helm upgrades.
* Accessed via Grafana with both Prometheus and Loki integrated.

Would you like me to add **automatic provisioning** of the Loki data source and default dashboards directly in Grafana’s Helm values (so you never have to add them manually)?
