Here’s a clean, copy-pasteable **Ingress setup** for your registry at `registry.app.brd-hq-cluster.brd.rw`, with **TLS (internal-ca)** + **basic auth** and large-push settings.

## 1) Create the basic-auth secret (user `ci`, password `Brd2025@registry!`)

```bash
# Make an htpasswd entry (bcrypt) and store it in a Secret the Ingress will read
HTPASS=$(htpasswd -nbB ci 'Brd2025@registry!')
kubectl -n kube-system create secret generic registry-basic-auth \
  --from-literal=auth="$HTPASS" -o yaml --dry-run=client | kubectl apply -f -
```

## 2) Ingress manifest (save as `registry-ingress.yaml`)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: registry
  namespace: kube-system
  annotations:
    # TLS via cert-manager (uses your ClusterIssuer)
    cert-manager.io/cluster-issuer: internal-ca

    # Basic auth (tell NGINX this secret is an auth-file)
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: registry-basic-auth
    nginx.ingress.kubernetes.io/auth-secret-type: auth-file
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"

    # Registry-friendly upload settings
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"          # unlimited
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "900"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "900"
spec:
  ingressClassName: nginx
  tls:
  - hosts: ["registry.app.brd-hq-cluster.brd.rw"]
    # cert-manager will create/maintain this Secret
    secretName: registry-tls
  rules:
  - host: registry.app.brd-hq-cluster.brd.rw
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            # Your Service name from kube-system
            name: registry
            port:
              number: 5000
```

Apply it:

```bash
kubectl -n kube-system apply -f registry-ingress.yaml
kubectl -n kube-system get ingress registry
```

## 3) Quick verification

```bash
# Export your internal CA once (if you don't already have it locally as ca.crt)
CA_SECRET=$(kubectl get clusterissuer internal-ca -o jsonpath='{.spec.ca.secretName}')
kubectl -n cert-manager get secret "$CA_SECRET" -o jsonpath='{.data.tls\.crt}' | base64 -d > ca.crt

# Expect 200 OK (means TLS+auth are correct)
curl --cacert ./ca.crt -i -u 'ci:Brd2025@registry!' https://registry.app.brd-hq-cluster.brd.rw/v2/
```

## 4) Notes & common gotchas

* **413 on push** → already handled by `proxy-body-size: "0"` and buffering off.
* **401** → ensure the secret is in `kube-system` and contains exactly one `ci:$2y$…` line:

  ```bash
  kubectl -n kube-system get secret registry-basic-auth -o jsonpath='{.data.auth}' | base64 -d | cat -A
  ```
* **x509** on clients → install `ca.crt` into Docker/containerd trust for the exact host, then restart the runtime.

If you want, I can also drop the containerd `hosts.toml` and `imagePullSecret` snippet so cluster nodes/pods can pull from this registry smoothly.
