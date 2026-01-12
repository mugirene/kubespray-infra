Getting Started

If you need to install a new kubernetes cluster you can use my Ansible Playbook to install one.
k3s

If you want to get metrics from your k3s servers, you will need to provide some additional flags to k3s.

Additional k3s flags used in the video:

extra_server_args: "--no-deploy servicelb --no-deploy traefik --kube-controller-manager-arg bind-address=0.0.0.0 --kube-proxy-arg metrics-bind-address=0.0.0.0 --kube-scheduler-arg bind-address=0.0.0.0 --etcd-expose-metrics true --kubelet-arg containerd=/run/k3s/containerd/containerd.sock"

helm

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

Install helm

The helm chart we will be using to install Grafana, Preometheus, and Alert Manager is kube-prometheus-stack
Installing

Verify you can communicate with your cluster

kubectl get nodes

	

NAME     STATUS   ROLES                       AGE   VERSION
k3s-01   Ready    control-plane,etcd,master   10h   v1.23.4+k3s1
k3s-02   Ready    control-plane,etcd,master   10h   v1.23.4+k3s1
k3s-03   Ready    control-plane,etcd,master   10h   v1.23.4+k3s1
k3s-04   Ready    <none>                      10h   v1.23.4+k3s1
k3s-05   Ready    <none>                      10h   v1.23.4+k3s1

Verify helm is installed

helm version

	

version.BuildInfo{Version:"v3.8.0", GitCommit:"d14138609b01886f544b2025f5000351c9eb092e", GitTreeState:"clean", GoVersion:"go1.17.5"}

Add helm repo

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

Update repo

helm repo update

Create a Kubernetes Namespace

kubectl create namespace monitoring

Echo username and password to a file

echo -n 'adminuser' > ./admin-user # change your username
echo -n 'p@ssword!' > ./admin-password # change your password

Create a Kubernetes Secret

 kubectl create secret generic grafana-admin-credentials --from-file=./admin-user --from-file=admin-password -n monitoring

You should see
	

secret/grafana-admin-credentials created

Verify your secret

kubectl describe secret -n monitoring grafana-admin-credentials

You should see
	

Name:         grafana-admin-credentials
Namespace:    monitoring
Labels:       <none>
Annotations:  <none>

Type:  Opaque

Data
====
admin-password:  9 bytes
admin-user:      9 bytes

Verify the username

kubectl get secret -n monitoring grafana-admin-credentials -o jsonpath="{.data.admin-user}" | base64 --decode

You should see
	

adminuser%

Verify password

kubectl get secret -n monitoring grafana-admin-credentials -o jsonpath="{.data.admin-password}" | base64 --decode

	

p@ssword!%

Remove username and password file from filesystem

rm admin-user && rm admin-password

Create a values file to hold our helm values

nano values.yaml

paste in values from here

Create our kube-prometheus-stack

helm install -n monitoring prometheus prometheus-community/kube-prometheus-stack -f values.yaml

Port Forwarding Grafana UI

(be sure to change the pod name to one that matches yours)

kubectl port-forward -n monitoring grafana-fcc55c57f-fhjfr 52222:3000

Visit Grafana

http://localhost:52222

If you make changes to your values.yaml you can deploy these changes by running

helm upgrade -n monitoring prometheus prometheus-community/kube-prometheus-stack -f values.yaml
