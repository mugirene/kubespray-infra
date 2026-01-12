Awesome—here’s a clean **from-scratch Rook-Ceph setup** for your cluster:

* **3 control planes**: `control-plane-1..3`
* **3 workers**: `worker-node-1..3`
* **Each worker has** `/dev/sdb` (50 GB)
* **You already labeled workers** with `node-role.kubernetes.io/storage=rook`
* Goal: **MONs & MGR on control planes**, **OSDs on workers**

I’ll give you copy-pasteable commands and manifests, plus **why** each step matters.

---

# 0) Prereqs & sanity

### Why

Make sure the cluster is ready and the extra disks are clean for Ceph to own.

### Do (once)

```bash
# Check nodes/roles
kubectl get nodes -o wide

# Workers must have the label (you already did this; repeat if needed)
kubectl label node worker-node-1 node-role.kubernetes.io/storage=rook --overwrite
kubectl label node worker-node-2 node-role.kubernetes.io/storage=rook --overwrite
kubectl label node worker-node-3 node-role.kubernetes.io/storage=rook --overwrite
```

### Do (on each worker)

```bash
# See the disk
lsblk -o NAME,TYPE,SIZE,MOUNTPOINT

# Wipe ONLY /dev/sdb (so Rook can claim it)
sudo sgdisk --zap-all /dev/sdb || true
sudo wipefs -a /dev/sdb
```

---

# 1) Install the Rook operator

### Why

The operator is the control loop that deploys/monitors Ceph daemons and runs health checks.

### Do

```bash
helm repo add rook-release https://charts.rook.io/release
helm repo update

kubectl create ns rook-ceph || true
helm upgrade --install rook-ceph rook-release/rook-ceph -n rook-ceph
kubectl -n rook-ceph rollout status deploy/rook-ceph-operator
```

---

# 2) Create the Ceph cluster (MONs/MGR on control planes, OSDs on workers)

### Why

* **Placement** pins MONs & MGR to control-plane nodes (tolerates their taints).
* **OSD placement** pins storage to workers via your `storage=rook` label.
* **deviceFilter** ensures only `/dev/sdb` is used (one OSD per worker).

### Create `rook-ceph-cluster.yaml`

```yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.2
  dataDirHostPath: /var/lib/rook

  mon:
    count: 3
    allowMultiplePerNode: false
  mgr:
    count: 1
    allowMultiplePerNode: false

  dashboard:
    enabled: true
  crashCollector:
    disable: false

  # --- Placement rules ---
  placement:
    mon:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
          - matchExpressions:
            - key: node-role.kubernetes.io/master
              operator: Exists
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule
      # Add these two blocks:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values: ["rook-ceph-mon"]
          topologyKey: kubernetes.io/hostname
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: rook-ceph-mon

    # MGR on control planes (same reasoning)
    mgr:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
          - matchExpressions:
            - key: node-role.kubernetes.io/master
              operator: Exists
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule

    # OSDs on worker nodes you labeled for storage
    osd:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: node-role.kubernetes.io/storage
              operator: In
              values: ["rook"]

  # --- Storage picking (/dev/sdb on workers only) ---
  storage:
    useAllNodes: true
    useAllDevices: false
    deviceFilter: ^sdb$
    config:
      osdsPerDevice: "1"

  # Health checks are enabled by default; leaving block implicit
```

### Apply & watch

```bash
kubectl apply -f rook-ceph-cluster.yaml
kubectl -n rook-ceph get pods -w
```

**Expect:**

* `rook-ceph-mon-*` (3 pods) on control planes
* `rook-ceph-mgr-*` (1 pod) on control planes
* `rook-ceph-osd-prepare-*` jobs complete on workers, then `rook-ceph-osd-*` (3 pods) on workers

---

# 3) (Optional) Toolbox for quick status

### Why

Gives you `ceph` CLI inside the cluster to check health, OSDs, PGs, etc.

### Do

```bash
kubectl apply -f https://raw.githubusercontent.com/rook/rook/release-1.14/cluster/examples/kubernetes/ceph/toolbox.yaml
kubectl -n rook-ceph rollout status deploy/rook-ceph-tools

kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree
```

**Expect:** `HEALTH_OK` (or brief WARN while peering), **3 OSDs up/in**.

---

# 4) Create pools & StorageClasses (replica size = 3)

### Why

* **RBD** for block volumes (typical PVCs).
* **CephFS** for shared filesystem volumes.
* Replication **3** uses your 3 OSDs for fault-tolerance.

### Create `ceph-storage.yaml`

```yaml
# --- RBD (block volumes) ---
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: rbd-pool
  namespace: rook-ceph
spec:
  replicated:
    size: 3
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-rbd
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: rbd-pool
  imageFormat: "2"
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer

# --- CephFS (shared filesystem) ---
---
apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: cephfs
  namespace: rook-ceph
spec:
  metadataPool:
    replicated:
      size: 3
  dataPools:
    - replicated:
        size: 3
  preservePoolsOnDelete: false
  metadataServer:
    activeCount: 1
    activeStandby: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: cephfs
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

### Apply

```bash
kubectl apply -f ceph-storage.yaml

# (Optional) make RBD the default storage class
kubectl annotate storageclass ceph-rbd storageclass.kubernetes.io/is-default-class="true" --overwrite
```

---

# 5) Smoke test (PVC + Pod)

### Why

Confirms CSI + pool + OSD are provisioning and mounting volumes.

### Create `test-pvc-pod.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rbd-test-pvc
spec:
  accessModes: [ "ReadWriteOnce" ]
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: rbd-test-pod
spec:
  containers:
    - name: app
      image: busybox
      command: ["sh", "-c", "echo hello-ceph > /mnt/test/hello && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /mnt/test
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: rbd-test-pvc
```

### Apply & verify

```bash
kubectl apply -f test-pvc-pod.yaml
kubectl get pvc
kubectl get pod rbd-test-pod -w
kubectl exec -it rbd-test-pod -- cat /mnt/test/hello
# expect: hello-ceph
```

---

# 6) (Optional) Access the Ceph dashboard

### Why

UI view of health, pools, PGs, OSDs.

### Do

```bash
# Get dashboard svc (usually ClusterIP)
kubectl -n rook-ceph get svc | grep dashboard

# Port-forward locally (example)
kubectl -n rook-ceph port-forward svc/rook-ceph-mgr-dashboard 8443:8443
# open https://localhost:8443
```

Get the admin password:

```bash
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath='{.data.password}' | base64 -d; echo
```

---

# Troubleshooting (fast checklist)

* **OSD missing on a worker**

  * `lsblk` shows `/dev/sdb`?
  * `sudo wipefs -a /dev/sdb` rerun if needed
  * `kubectl -n rook-ceph logs -l app=rook-ceph-osd-prepare --tail=200`
* **MON won’t schedule on control planes**

  * Control-plane nodes tainted? (they are) → tolerations included above
  * Labels present? At least `node-role.kubernetes.io/control-plane` or `master`
* **Cluster HEALTH\_WARN after create**

  * Normal during peering; recheck `ceph -s` after a minute
* **Default SC conflict**

  * Remove old default annotation before setting `ceph-rbd`

---

That’s it. If you want, paste the output of:

```bash
kubectl -n rook-ceph get pods -o wide
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s
```

and I’ll sanity-check placement (MONs on control planes, OSDs on workers) and health.

Here’s the gist:

* **StorageClass (`s3-buckets`)**

  * Cluster-scoped *template* for S3 buckets.
  * Create it **once** per cluster. By itself it does nothing.

* **ObjectBucketClaim (OBC)**

  * Namespace-scoped *claim* that references the StorageClass.
  * **Creates a bucket** in your Ceph RGW and, in that namespace, a **Secret** (AWS keys) + **ConfigMap** (endpoint, bucket name).
  * Each namespace/app makes its own OBC → gets its **own creds**.
  * `reclaimPolicy` on the StorageClass applies (e.g., `Delete` vs `Retain`).

* **Can you use the StorageClass directly without an OBC?**

  * **No.** OBC is what triggers bucket provisioning and generates creds.

* **If you don’t want OBCs (manual route):**

  1. Create a `CephObjectStoreUser` (gets Access/Secret keys).
  2. Create/manage buckets yourself (AWS CLI or SDK).
  3. Distribute creds as Kubernetes Secrets to the namespaces/apps.

  * K8s won’t manage bucket lifecycle in this mode (no `reclaimPolicy` effect).

**When to choose what**

* Want K8s-native lifecycle + per-namespace creds? → **Use OBCs**.
* Already manage buckets/creds yourself or treating RGW like external S3? → **Manual route**.

