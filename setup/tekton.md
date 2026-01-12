NXDOMAIN there means the CoreDNS **rewrite isn’t in effect** (or it’s in the wrong place/order), so queries for `*.svc.cluster.local` aren’t being mapped to your real domain.

Here’s the quickest way to verify + fix it.

## 1) Inspect your CoreDNS Corefile

```bash
kubectl -n kube-system get cm coredns -o yaml | sed -n '1,120p'
```

You should see a block like `.:53 { ... }` with `kubernetes brd-hq-cluster.brd.rw ...`. If the two `rewrite` lines aren’t there **above** the `kubernetes` plugin, add them.

## 2) Edit CoreDNS and add the rewrites (above `kubernetes`)

```bash
kubectl -n kube-system edit cm coredns
```

Inside the main server block (`.:53 { ... }`), make it look like this (keep your other plugins as-is; just add the two `rewrite` lines **before** `kubernetes`):

```
.:53 {
    errors
    health
    ready

    # Map anything that assumes cluster.local to your real cluster domain.
    rewrite name suffix svc.cluster.local svc.brd-hq-cluster.brd.rw
    rewrite name suffix cluster.local    brd-hq-cluster.brd.rw

    kubernetes brd-hq-cluster.brd.rw in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }

    # ... keep the rest (forward, cache, loop, prometheus, etc.)
}
```

> Order matters: `rewrite` must be **before** `kubernetes` so the query is rewritten first.

## 3) Restart CoreDNS and confirm it’s healthy

```bash
kubectl -n kube-system rollout restart deploy/coredns
kubectl -n kube-system rollout status  deploy/coredns
kubectl -n kube-system logs deploy/coredns --tail=50
```

(If there’s a typo, CoreDNS will CrashLoop—fix the Corefile and restart again.)

## 4) Re-test DNS (both names)

```bash
# This should now resolve via the rewrite:
kubectl -n kube-system run dns-$RANDOM --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup kubernetes.default.svc.cluster.local

# And your actual FQDN should already work:
kubectl -n kube-system run dns-$RANDOM --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup kubernetes.default.svc.brd-hq-cluster.brd.rw
```

You should see an IP (the Kubernetes service ClusterIP) for both.

> Your DNS server `169.254.25.10` indicates **NodeLocal DNSCache** is in use; that’s fine. The rewrite happens in CoreDNS and NodeLocal just forwards—no extra changes needed.

---



Your **NodeLocal DNS** Corefile only serves these zones:

* `brd-hq-cluster.brd.rw:53` → forwards to CoreDNS `10.233.0.3`
* `in-addr.arpa:53`, `ip6.arpa:53` → forward to `10.233.0.3`
* `.:53` (default) → forwards to `/etc/resolv.conf` (external)

So queries for `*.svc.cluster.local` hit the **default `.:53`** block and get forwarded **outside the cluster**, which returns NXDOMAIN. The simplest, clean fix is to make NodeLocal **forward `cluster.local` to CoreDNS** (which already has the rewrite).

### Do this (no rewrite needed in NodeLocal)

1. **Edit NodeLocal’s ConfigMap**

```bash
kubectl -n kube-system edit cm nodelocaldns
```

2. **Add this new server block** (copy it next to your existing ones):

```
cluster.local:53 {
    errors
    cache 30
    reload
    loop
    bind 169.254.25.10
    forward . 10.233.0.3 {
        force_tcp
    }
    prometheus :9253
}
```

3. **Restart NodeLocal and test**

```bash
kubectl -n kube-system rollout restart ds/nodelocaldns
kubectl -n kube-system rollout status  ds/nodelocaldns

# now this should resolve via 169.254.25.10
kubectl -n kube-system run dns-$(date +%s) --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup kubernetes.default.svc.cluster.local
```

You should get the Kubernetes Service IP (e.g., `10.233.0.1`).
(Behind the scenes: NodeLocal forwards `cluster.local` → CoreDNS; CoreDNS **rewrites** to `...svc.brd-hq-cluster.brd.rw` and answers.)

---

### Then reinstall Tekton normally

With DNS fixed cluster-wide, Tekton’s defaults (which assume `cluster.local`) will work.

```bash
# Operator
kubectl apply -f https://storage.googleapis.com/tekton-releases/operator/latest/release.yaml
kubectl -n tekton-operator get pods

# Stack
cat <<'YAML' | kubectl apply -f -
apiVersion: operator.tekton.dev/v1alpha1
kind: TektonConfig
metadata: { name: config }
spec:
  profile: all
  targetNamespace: tekton-pipelines
YAML

kubectl -n tekton-pipelines get pods -w
```

### Quick Results check

```bash
kubectl -n tekton-pipelines get endpointslices -l kubernetes.io/service-name=tekton-results-api-service -o wide
kubectl -n tekton-pipelines run http-$RANDOM --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- \
  sh -lc 'curl -sSI http://tekton-results-api-service.tekton-pipelines.svc:8080/healthz && echo OK'
```

If you’d prefer to **automate** these DNS edits via GitOps (so they persist), say the word and I’ll give you a tiny Kustomize patch for both CoreDNS and NodeLocal.
