# Kubernetes Worker Node High Availability (HA)

## 1. Overview

Your cluster includes **3 worker nodes**:

* **node4**
* **node5**
* **node6**

This provides redundancy for workloads: if one worker fails, Kubernetes reschedules pods on the remaining nodes, ensuring service continuity.

---

## 2. How Worker HA Works

* **Workload Replication**: Apps should run with multiple replicas (via Deployments/StatefulSets).
* **Scheduler Distribution**: The Kubernetes scheduler spreads pods across available workers.
* **Failover**: If a worker goes down, pods are rescheduled to healthy workers.
* **Load Balancing**: Services route traffic only to healthy pods/nodes.

---

## 3. Key HA Configurations

To ensure true HA, apply the following practices:

1. **Replicas**

   * Always run >1 replica for critical apps.
   * Example:

     ```yaml
     replicas: 3
     ```

2. **Pod Distribution**

   * Use `PodAntiAffinity` or `TopologySpreadConstraints` to avoid replicas landing on the same worker.

3. **Pod Disruption Budgets (PDBs)**

   * Prevent all replicas of an app from being drained during maintenance.

4. **Node Labels & Taints**

   * Workers are labeled `node-role.kubernetes.io/worker=worker`.
   * Additional labels can indicate special roles (e.g., `storage=true`, `gpu=true`).

5. **Storage HA**

   * Persistent storage must be accessible from multiple nodes (e.g., CSI, Ceph, Longhorn).

6. **Load Balancing**

   * Cluster networking ensures traffic only hits healthy pods.
   * External load balancers should stop sending traffic to unhealthy nodes.

---

## 4. How to Check Worker HA

* **Node Health**

  ```bash
  kubectl get nodes -o wide
  ```
* **Pod Distribution**

  ```bash
  kubectl get pods -o wide -n <namespace>
  ```
* **Disruption Budgets**

  ```bash
  kubectl get pdb -A
  ```
* **Simulate Failure**

  * Drain a worker and confirm workloads reschedule:

    ```bash
    kubectl drain node4 --ignore-daemonsets --delete-emptydir-data
    ```

---

## 5. Worker HA Diagram

```
          +-------------------+       +-------------------+       +-------------------+
          |      node4        |       |      node5        |       |      node6        |
          |   Worker Node     |       |   Worker Node     |       |   Worker Node     |
          |   (Pods + Kubelet)|       |   (Pods + Kubelet)|       |   (Pods + Kubelet)|
          +-------------------+       +-------------------+       +-------------------+
                   |                           |                           |
                   +-----------+---------------+---------------+-----------+
                               |   Kubernetes Scheduler + LB   |
                               +-------------------------------+
```

---

## 6. Summary

* To achieve **real HA**, ensure workloads have replicas, spreading rules, PDBs, and HA storage.
* Regularly check node health and test failover by draining nodes.

---
