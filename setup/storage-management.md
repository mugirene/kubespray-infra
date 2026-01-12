I’d go with **Option A: split out dedicated LVs** (at least for `/var/lib/containerd`, optionally `/var/lib/kubelet`). It’s the most production-friendly and avoids the OS competing with images/logs. Extending `/` to ~98 GiB works, but you lose flexibility and still risk starving the OS if images spike.

## My recommendation (given you have ~49 GiB free in `ubuntu-vg`)

Per worker, one at a time (cordon → drain → change → uncordon):

### A1) Move **containerd** to its own LV (e.g., 40 GiB)

This takes the heavy image layers off `/`.

```bash
# 0) Safely take node out
kubectl cordon worker-node-<N>
kubectl drain worker-node-<N> --ignore-daemonsets --delete-emptydir-data

# 1) Create LV & filesystem
sudo lvcreate -L 40G -n containerd-lv ubuntu-vg
sudo mkfs.ext4 /dev/ubuntu-vg/containerd-lv

# 2) Stop services and migrate data
sudo systemctl stop kubelet containerd
sudo mkdir -p /var/lib/containerd
sudo mount /dev/ubuntu-vg/containerd-lv /mnt
sudo rsync -aHXS /var/lib/containerd/ /mnt/
sudo umount /mnt
sudo mount /dev/ubuntu-vg/containerd-lv /var/lib/containerd

# 3) Persist mount
UUID=$(sudo blkid -s UUID -o value /dev/ubuntu-vg/containerd-lv)
echo "UUID=$UUID /var/lib/containerd ext4 defaults 0 2" | sudo tee -a /etc/fstab

# 4) Start services and verify
sudo systemctl start containerd kubelet
df -hT /var/lib/containerd

# 5) Bring node back
kubectl uncordon worker-node-<N>
```

### A2) (Optional) Move **kubelet** to its own LV (e.g., 8–10 GiB)

This isolates pod logs/emptyDir/writable layers; if you build on nodes, it helps.

```bash
# create, format, and mount similar to above
sudo lvcreate -L 10G -n kubelet-lv ubuntu-vg
sudo mkfs.ext4 /dev/ubuntu-vg/kubelet-lv

sudo systemctl stop kubelet
sudo mkdir -p /var/lib/kubelet
sudo mount /dev/ubuntu-vg/kubelet-lv /mnt
sudo rsync -aHXS /var/lib/kubelet/ /mnt/
sudo umount /mnt
sudo mount /dev/ubuntu-vg/kubelet-lv /var/lib/kubelet
UUID=$(sudo blkid -s UUID -o value /dev/ubuntu-vg/kubelet-lv)
echo "UUID=$UUID /var/lib/kubelet ext4 defaults 0 2" | sudo tee -a /etc/fstab
sudo systemctl start kubelet
df -hT /var/lib/kubelet
```

> Keep a few GiB **free in the VG** (don’t use 100% right now) so you can grow one of these LVs later without downtime.

### Why this is better than just growing `/`:

* **Isolation:** OS can’t be starved by image churn or logs.
* **Control:** You can independently grow containerd/kubelet if builds grow.
* **Safer rollouts:** If something fills `/var/lib/containerd`, your root FS is unaffected.

---

## If you need a quick fix right now

Grow `/` to ~98 GiB and call it a day (fastest):

```bash
kubectl cordon worker-node-<N>
kubectl drain worker-node-<N> --ignore-daemonsets --delete-emptydir-data

sudo lvextend -l +100%FREE -r /dev/ubuntu-vg/ubuntu-lv
df -hT /

kubectl uncordon worker-node-<N>
```

Trade-off: no isolation; you consume all VG free space immediately.

---

## Regardless of node layout — fix the CI eviction root cause

Your Tekton build was evicted because it used a lot of **ephemeral-storage** with **request=0**. Do both:

1. **Requests/limits** on the build step:

```yaml
resources:
  requests:
    cpu: "2"
    memory: "4Gi"
    ephemeral-storage: "12Gi"
  limits:
    memory: "8Gi"
    ephemeral-storage: "20Gi"
```

2. **Write heavy data to your PVC workspace**, not node disk:

* Kaniko: `--cache=true --cache-dir=$(workspaces.shared-workspace.path)/.kaniko-cache`
* Buildah: set `CONTAINERS_STORAGE=$(workspaces.shared-workspace.path)/.buildah`

This keeps node disk steady even during big builds.

---

If you want, tell me which route you’re taking (A1 only, A1+A2, or the quick grow), and I’ll give you a copy-paste runbook for all three workers with your exact node names.
