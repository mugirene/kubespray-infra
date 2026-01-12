Perfect. We’ll wire your **private registry** into the CI so Kaniko can push images to:

`https://registry.app.brd-hq-cluster.brd.rw/`
(auth: `ci` / `Brd2025@registry!`)

Below is a tidy set of manifests + a couple of one-liners to create the secret **without putting the password in Git**.

---

# 00-sa-rbac.yaml — CI ServiceAccount & minimal RBAC

Purpose: the SA Tekton uses to run your Pipeline; RBAC lets it create PipelineRuns and read pod logs.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-ci
  namespace: tekton-pipelines
  labels:
    app.kubernetes.io/name: tekton-ci
    app.kubernetes.io/part-of: ci
    brd.rw/category: ci
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tekton-ci-pipelineruns
  namespace: tekton-pipelines
  labels:
    app.kubernetes.io/name: tekton-ci
    brd.rw/category: ci
rules:
- apiGroups: ["tekton.dev"]
  resources: ["pipelineruns"]
  verbs: ["create","get","list","watch"]
- apiGroups: [""]
  resources: ["pods","pods/log"]
  verbs: ["get","list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tekton-ci-pipelineruns
  namespace: tekton-pipelines
  labels:
    app.kubernetes.io/name: tekton-ci
    brd.rw/category: ci
subjects:
- kind: ServiceAccount
  name: tekton-ci
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: tekton-ci-pipelineruns
```

Apply:

```bash
kubectl apply -f 00-sa-rbac.yaml
```

---

# (No YAML) Create the **registry secret** *securely*

Purpose: credentials for pushing to your private registry. We keep it **out of Git**.

```bash
kubectl -n tekton-pipelines create secret docker-registry registry-cred \
  --docker-server=registry.app.brd-hq-cluster.brd.rw \
  --docker-username='ci' \
  --docker-password='Brd2025@registry!' \
  --docker-email='dev@brd.rw' \
  --dry-run=client -o yaml | kubectl apply -f -

# Make Tekton/creds-init also use it for pushes (not just image pulls)
kubectl -n tekton-pipelines annotate secret registry-cred \
  tekton.dev/docker-0='https://registry.app.brd-hq-cluster.brd.rw' --overwrite

# Attach the secret to the CI ServiceAccount for both pulling and pushing
kubectl -n tekton-pipelines patch sa tekton-ci -p \
  '{"imagePullSecrets":[{"name":"registry-cred"}],"secrets":[{"name":"registry-cred"}]}'
```

> If your registry TLS uses a private CA and Kaniko errors on certificates, tell me—we’ll add the CA bundle to the Kaniko container rather than disabling TLS.

---

# 03-pipeline-minimal.yaml — Clone → Test → Build+Push

Purpose: your basic CI that builds and pushes to **your** registry.

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: app-ci
  namespace: tekton-pipelines
  labels:
    app.kubernetes.io/name: app-ci
    app.kubernetes.io/part-of: ci
    brd.rw/category: ci
spec:
  params:
  - name: git_url
  - name: git_rev
  - name: image          # e.g., registry.app.brd-hq-cluster.brd.rw/ci/app
  - name: context        # .
  - name: dockerfile     # ./Dockerfile
  - name: tag            # e.g., v0.1.0 or commit SHA
  workspaces:
  - name: ws
  tasks:
  - name: clone
    workspaces: [{ name: ws, workspace: ws }]
    params:
    - { name: git_url, value: $(params.git_url) }
    - { name: git_rev, value: $(params.git_rev) }
    taskSpec:
      params: [{ name: git_url }, { name: git_rev }]
      workspaces: [{ name: ws }]
      steps:
      - name: git
        image: alpine/git:2.45.2
        script: |
          set -e
          git clone "$(params.git_url)" src
          cd src && git checkout "$(params.git_rev)"
          cp -R . "$(workspaces.ws.path)/src"
  - name: test
    runAfter: [clone]
    workspaces: [{ name: ws, workspace: ws }]
    taskSpec:
      workspaces: [{ name: ws }]
      steps:
      - name: run-tests
        image: alpine:3.20
        script: |
          echo "Running tests…"; sleep 2; echo "OK"
  - name: build
    runAfter: [test]
    params:
    - { name: image, value: $(params.image) }
    - { name: tag, value: $(params.tag) }
    - { name: context, value: $(params.context) }
    - { name: dockerfile, value: $(params.dockerfile) }
    workspaces: [{ name: ws, workspace: ws }]
    taskSpec:
      params:
      - { name: image } - { name: tag } - { name: context } - { name: dockerfile }
      workspaces: [{ name: ws }]
      steps:
      - name: kaniko
        image: gcr.io/kaniko-project/executor:v1.23.2
        # Tell Kaniko to read auth from the SA-mounted docker config
        env: [{ name: DOCKER_CONFIG, value: /tekton/home/.docker/ }]
        script: |
          set -e
          /kaniko/executor \
            --context="$(workspaces.ws.path)/src/$(params.context)" \
            --dockerfile="$(workspaces.ws.path)/src/$(params.dockerfile)" \
            --destination="$(params.image):$(params.tag)" \
            --snapshotMode=redo
```

Apply:

```bash
kubectl apply -f 03-pipeline-minimal.yaml
```

---

# 05-pipelinerun-sample.yaml — One-off smoke test

Purpose: run the pipeline once to confirm it clones, “tests”, and **pushes** to your registry.

```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: app-ci-run-1
  namespace: tekton-pipelines
  labels:
    brd.rw/category: ci
spec:
  serviceAccountName: tekton-ci
  pipelineRef: { name: app-ci }
  params:
  - { name: git_url,  value: https://github.com/example/app.git }   # change
  - { name: git_rev,  value: main }
  - { name: image,    value: registry.app.brd-hq-cluster.brd.rw/ci/app }  # <— your registry
  - { name: context,  value: . }
  - { name: dockerfile, value: ./Dockerfile }
  - { name: tag,      value: v0.1.0 }
  workspaces:
  - name: ws
    emptyDir: {}
```

Apply & watch:

```bash
kubectl apply -f 05-pipelinerun-sample.yaml
kubectl -n tekton-pipelines logs -f -l tekton.dev/pipelineRun=app-ci-run-1 --all-containers
```

---

## What each piece does (quick)

* **ServiceAccount + RBAC:** lets Tekton create runs and read logs—nothing more.
* **registry-cred Secret:** holds `ci`/password for `registry.app.brd-hq-cluster.brd.rw`; we annotate it so Tekton’s creds-init feeds Kaniko.
* **Pipeline:** clones your repo, runs a placeholder test, builds & pushes with Kaniko using that secret.
* **PipelineRun:** single invocation to verify everything works end-to-end.

---

### Optional next steps

* Want **GitOps auto-deploy** (Argo CD)? I’ll swap in the `app-ci-gitops` pipeline that commits the new image tag to your GitOps repo.
* Prefer **webhook-based CI**? I’ll add Triggers + an Ingress so GitHub/GitLab can call it on push.

Give me:

* your **app repo URL**, and
* the image path you want (e.g., `registry.app.brd-hq-cluster.brd.rw/platform/app`),

and I’ll pre-fill those values for you.
