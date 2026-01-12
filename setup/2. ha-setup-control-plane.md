# **Kubernetes Control Plane HA Setup Documentation**

## **1. Cluster Topology**

* **Control Plane Nodes (HA):**

  * `node1` (etcd1)
  * `node2` (etcd2)
  * `node3` (etcd3)
* **Worker Nodes:**

  * `node4`, `node5`, `node6`
* **etcd Cluster:** Stacked on control-plane nodes (systemd service, not pods)
* **Networking:** Calico for CNI, NodeLocalDNS enabled
* **Kubernetes Version:** v1.33.4

---

## **2. Installation Method**

* **Tool Used:** Kubespray
* **Inventory Setup:**

  * Defined control-plane, etcd, and worker nodes in YAML inventory.
  * etcd stacked on control-plane nodes for HA.
* **Components Deployed:**

  * **kube-apiserver, kube-controller-manager, kube-scheduler** on all control-plane nodes
  * **etcd** as systemd service (`/usr/local/bin/etcd`)
* **TLS Certificates:** Used for securing etcd client and peer communication
* **Systemd Service:** etcd is running as a service:

  ```bash
  sudo systemctl status etcd
  ```

---

## **3. How it Works**

* **High Availability (HA):**

  * Three control-plane nodes provide redundancy.
  * etcd cluster maintains quorum; can tolerate **1 node failure**.
  * kube-apiserver can failover automatically between control-plane nodes.
* **etcd Cluster:**

  * Provides distributed key-value storage for Kubernetes state.
  * Each control-plane node runs an etcd member (stacked etcd).
* **Leader Election:**

  * One etcd node acts as leader, others are followers.
  * Leader handles all writes, followers replicate data.

---

## **4. Health Checks**

* **Check Control Plane Nodes:**

  ```bash
  kubectl get nodes
  kubectl get pods -n kube-system
  ```
* **Check etcd Status (systemd):**

  ```bash
  sudo systemctl status etcd
  ```
* **Check etcd Cluster Members:**

  ```bash
  sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://<node-ip>:2379 \
    --cacert=/etc/ssl/etcd/ssl/ca.pem \
    --cert=/etc/ssl/etcd/ssl/node-node1.pem \
    --key=/etc/ssl/etcd/ssl/node-node1-key.pem
  ```
* **Check etcd Endpoint Health:**

  ```bash
  sudo ETCDCTL_API=3 etcdctl endpoint health \
    --endpoints=https://192.168.10.171:2379,https://192.168.10.172:2379,https://192.168.10.173:2379 \
    --cacert=/etc/ssl/etcd/ssl/ca.pem \
    --cert=/etc/ssl/etcd/ssl/node-node1.pem \
    --key=/etc/ssl/etcd/ssl/node-node1-key.pem
  ```
* **Check etcd Leader:**

  ```bash
  sudo ETCDCTL_API=3 etcdctl endpoint status \
    --write-out=table \
    --endpoints=https://192.168.10.171:2379,https://192.168.10.172:2379,https://192.168.10.173:2379 \
    --cacert=/etc/ssl/etcd/ssl/ca.pem \
    --cert=/etc/ssl/etcd/ssl/node-node1.pem \
    --key=/etc/ssl/etcd/ssl/node-node1-key.pem
  ```

  * The `isLeader` column shows which etcd member is currently the leader.

---

## **5. Important Notes**

* **Stacked etcd (systemd) is different from static pod etcd:**

  * Pods not visible in `kube-system` namespace.
  * All checks must use `etcdctl` against systemd service endpoints.
* **TLS Certificates:** Essential for secure communication.

  * Node certs: `/etc/ssl/etcd/ssl/node-node*.pem`
  * CA cert: `/etc/ssl/etcd/ssl/ca.pem`
* **HA Quorum:** With 3 nodes, quorum is 2. Losing 2 nodes will break the cluster.
* **Restarting etcd:**

  ```bash
  sudo systemctl restart etcd
  sudo systemctl status etcd
  ```

---

## **6. Diagram of Control Plane HA**

```
+--------------------+       +--------------------+       +--------------------+
|   node1 (etcd1)    |<----->|   node2 (etcd2)    |<----->|   node3 (etcd3)    |
| kube-apiserver      |       | kube-apiserver      |       | kube-apiserver      |
| kube-controller     |       | kube-controller     |       | kube-controller     |
| kube-scheduler      |       | kube-scheduler      |       | kube-scheduler      |
| etcd (leader/follower) |   | etcd (follower)    |       | etcd (follower)    |
+--------------------+       +--------------------+       +--------------------+

                 HA Control Plane (quorum=2, tolerate 1 failure)

                  +-----------------+     +-----------------+     +-----------------+
                  |   node4         |     |   node5         |     |   node6         |
                  |   Worker        |     |   Worker        |     |   Worker        |
                  +-----------------+     +-----------------+     +-----------------+
```

* **Note:** One of the etcd nodes acts as the leader; the other two replicate data.
* Worker nodes only run workloads; no control-plane components.
