Perfect 👍 Let’s document your setup with a **clear diagram** of your HA control plane.

---

## 📌 Kubernetes HA Control Plane Layout

```
                       ┌──────────────────────────-┐
                       │     External Clients      │
                       │ (kubectl, apps, ingress)  │
                       └───────────┬────────────-─-┘
                                   │
                                   ▼
                      ┌───────────────────────────┐
                      │   Load Balancer (HAProxy) │
                      │   Round-robin to apis     │
                      └────────────┬──────────────┘
                                   │
        ┌───────────------─────────┼──────────────────-----──┐
        ▼                          ▼                         ▼
┌─────────────-----┐      ┌─────────────-----┐      ┌─────────────-----┐
│   node1          │      │   node2          │      │   node3          │
│ ControlPlane     │      │ ControlPlane     │      │ ControlPlane     │
│ - kube-apiserver |      │ - kube-apiserver |      │ - kube-apiserver |
│ - etcd member    |      │ - etcd member    |      │ - etcd member    |
│ - controller mgr |      │ - controller mgr |      │ - controller mgr |
│ - scheduler      |      │ - scheduler      |      │ - scheduler      |
└─────────────-----┘      └─────────────-----┘      └─────────────-----┘

        ┌──────────────────────────────────────────┐
        │                ETCD Cluster              │
        │ (3-member quorum, RAFT consensus)        │
        └──────────────────────────────────────────┘

        ┌──────────────────────────────────────────┐
        │                 Workers                  │
        │ node4, node5, node6                      │
        │ - kubelet, kube-proxy                    │
        │ - run user workloads (pods, services)    │
        └──────────────────────────────────────────┘
```

---

## 📌 How it Works

* **Control Plane (node1–3):**

  * Each runs **API server, controller-manager, scheduler**, and is part of the **etcd cluster**.
  * **ETCD** stores cluster state and uses **RAFT consensus** for high availability.
  * **API servers** are fronted by a **Load Balancer** to provide a single entrypoint.

* **Workers (node4–6):**

  * Run workloads (Pods, Deployments, Services, etc.).
  * Managed by the control-plane via kubelet + kube-proxy.

---

## 📌 How to Check

1. **Cluster Nodes**

   ```bash
   kubectl get nodes -o wide
   ```

2. **Etcd Health**

   ```bash
   ETCDCTL_API=3 etcdctl endpoint health \
     --endpoints=https://192.168.10.171:2379,https://192.168.10.172:2379,https://192.168.10.173:2379 \
     --cacert=/etc/ssl/etcd/ssl/ca.pem \
     --cert=/etc/ssl/etcd/ssl/node-node1.pem \
     --key=/etc/ssl/etcd/ssl/node-node1-key.pem
   ```

3. **Check Leader**

   ```bash
   ETCDCTL_API=3 etcdctl endpoint status \
     --endpoints=https://192.168.10.171:2379,https://192.168.10.172:2379,https://192.168.10.173:2379 \
     --cacert=/etc/ssl/etcd/ssl/ca.pem \
     --cert=/etc/ssl/etcd/ssl/node-node1.pem \
     --key=/etc/ssl/etcd/ssl/node-node1-key.pem -w table
   ```

   * Output shows which node is the **leader** and the current **RAFT term**.

4. **Control Plane Components**

   ```bash
   kubectl get pods -n kube-system -o wide
   ```

---

## 📌 Key Points to Remember

* ETCD requires **quorum** (2/3) to make decisions.
* API servers are **stateless** and can be scaled horizontally.
* Labels help identify **roles** of each node (control-plane, etcd, worker).
* Load balancer is critical for **API HA**.

---

👉 Do you want me to also generate a **PNG architecture diagram** (cleaner than ASCII) that you can keep for your documentation?
