Absolutely—let’s add an **S3-compatible Object Store (RGW)** to your existing Rook-Ceph cluster. Below is a compact, copy-paste “apply pack” that:

* Creates a **CephObjectStore** (replicated across your 3 OSDs)
* Pins **RGW pods to worker nodes** (`node-role.kubernetes.io/storage=rook`)
* Lets you provision **buckets dynamically** (ObjectBucketClaim), **or** create a **named S3 user**
* Shows quick ways to **access S3** (internal svc, NodePort, or Ingress)
* Includes a quick **AWS CLI test**

---

## 1) Create the S3 Object Store (RGW)

Save as `ceph-objectstore.yaml` and apply.

```yaml
apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: s3-store
  namespace: rook-ceph
spec:
  metadataPool:
    replicated:
      size: 3
  dataPool:
    replicated:
      size: 3
  preservePoolsOnDelete: true
  gateway:
    port: 80
    securePort: 443
    instances: 2
    placement:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: node-role.kubernetes.io/storage
              operator: In
              values: ["rook"]
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            rgw: s3-store
```

```bash
kubectl apply -f ceph-objectstore.yaml
kubectl -n rook-ceph get pods -l app=rook-ceph-rgw -o wide
# Expect two pods like: rook-ceph-rgw-s3-store-...
```

---

## 2) Choose how you want credentials/buckets

You can use **either** (A) dynamic buckets via OBC **or** (B) a named user (static creds). You can also do both.

### (A) Dynamic buckets via StorageClass + OBC

```yaml
# s3-bucket-sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: s3-buckets
provisioner: rook-ceph.ceph.rook.io/bucket
parameters:
  objectStoreName: s3-store
  objectStoreNamespace: rook-ceph
  region: us-east-1
reclaimPolicy: Delete
---
# s3-demo-obc.yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: demo-bucket
  namespace: default
spec:
  storageClassName: s3-buckets
  generateBucketName: demo-bkt
```

```bash
kubectl apply -f s3-bucket-sc.yaml
kubectl apply -f s3-demo-obc.yaml
```

This creates in `default`:

* a **Secret** with `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
* a **ConfigMap** with `BUCKET_HOST`, `BUCKET_NAME`, etc.

Get them:

```bash
kubectl get secret demo-bucket -n default -o yaml | sed -n 's/^[[:space:]]*//p' | grep -E 'AWS_|Endpoint'
kubectl get configmap demo-bucket -n default -o yaml | sed -n 's/^[[:space:]]*//p'
```

### (B) Named S3 user (static creds)

```yaml
# s3-user.yaml
apiVersion: ceph.rook.io/v1
kind: CephObjectStoreUser
metadata:
  name: app-user
  namespace: rook-ceph
spec:
  store: s3-store
  displayName: "App User"
```

```bash
kubectl apply -f s3-user.yaml
kubectl -n rook-ceph get secret rook-ceph-object-user-s3-store-app-user \
  -o jsonpath='{.data.AccessKey}' | base64 -d; echo
kubectl -n rook-ceph get secret rook-ceph-object-user-s3-store-app-user \
  -o jsonpath='{.data.SecretKey}' | base64 -d; echo
```

**In-cluster endpoint:**

```
http://rook-ceph-rgw-s3-store.rook-ceph.svc.cluster.local
```

---

## 3) Reach S3 from outside the cluster (pick one)

**NodePort (quick):**

```bash
kubectl -n rook-ceph patch svc rook-ceph-rgw-s3-store \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"rgw","port":80,"targetPort":80,"nodePort":30080}]}}'
# Then use:  http://<any_worker_node_IP>:30080
```

**Ingress (clean, TLS):** adjust for your controller/host.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: s3-store
  namespace: rook-ceph
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
spec:
  ingressClassName: nginx
  tls:
  - hosts: ["s3.example.local"]
    secretName: s3-tls
  rules:
  - host: s3.example.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: rook-ceph-rgw-s3-store
            port:
              number: 80
```

---

## 4) Quick AWS CLI smoke test

Use the **OBC secret** or **named user** keys:

```bash
export AWS_ACCESS_KEY_ID=<key>
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_EC2_METADATA_DISABLED=true

# Pick your endpoint:
export S3_ENDPOINT=http://<worker_ip>:30080   # NodePort
# or: http://rook-ceph-rgw-s3-store.rook-ceph.svc.cluster.local  (in-cluster)
# or: https://s3.example.local                 # Ingress (TLS)

aws --endpoint-url "$S3_ENDPOINT" s3 mb s3://quick-check
aws --endpoint-url "$S3_ENDPOINT" s3 cp /etc/hosts s3://quick-check/hosts.txt
aws --endpoint-url "$S3_ENDPOINT" s3 ls s3://quick-check
```

---

## Notes & tips

* **Placement** in the `CephObjectStore` keeps RGW strictly on **workers** (same as your OSDs).
* **Replicated size = 3** leverages your three OSDs for resilience.
* Want **per-bucket quotas**, **lifecycle**, or **bucket notifications** (Kafka/NATS/Webhook)? Say the word and I’ll add examples.
* If you later add more worker capacity, bump `gateway.instances` for higher S3 throughput.

If you want, I can package all of this (object store + OBC SC + example OBC + named user + optional NodePort/Ingress) into a single file tailored to your domain/IPs.
