# **High Availability OpenShift API Setup (No Extra Hardware)**

## **Overview**

This setup provides a **highly available OpenShift API endpoint** using the existing control plane nodes without adding extra hardware.

* **API Endpoint:** `brd-hq-cluster.brd.rw`
* **Standard Port:** 6443
* **Floating VIP:** 192.168.10.177

**Components Used:**

* **HAProxy** – Load balances API traffic across all control plane nodes.
* **Keepalived** – Manages a floating VIP for failover.
* **iptables NAT** – Forwards traffic from VIP:6443 → HAProxy:8443.

---

## **Node Information**

| Node         | IP             | Role               |
| ------------ | -------------- | ------------------ |
| cp1          | 192.168.10.171 | MASTER (VIP owner) |
| cp2          | 192.168.10.172 | BACKUP             |
| cp3          | 192.168.10.173 | BACKUP             |
| Floating VIP | 192.168.10.177 | API endpoint       |

---

## **Step 1: Install Required Packages**

Run on **all control plane nodes**:

```bash
sudo apt update
sudo apt install -y haproxy keepalived iptables-persistent
```

---

## **Step 2: Configure HAProxy**

**File:** `/etc/haproxy/haproxy.cfg` (on all nodes)

```haproxy
frontend kube_api
    bind *:8443
    mode tcp
    default_backend kube_api_backend

backend kube_api_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server cp1 192.168.10.171:6443 check
    server cp2 192.168.10.172:6443 check
    server cp3 192.168.10.173:6443 check
```

**Enable and start HAProxy:**

```bash
sudo systemctl enable haproxy
sudo systemctl start haproxy
sudo ss -tlnp | grep 8443   # Verify it's listening
```

---

## **Step 3: Configure Keepalived**

### **cp1 (MASTER)**

**File:** `/etc/keepalived/keepalived.conf`

```text
vrrp_instance VI_1 {
    state MASTER
    interface ens160
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1234
    }
    virtual_ipaddress {
        192.168.10.177
    }
}
```

### **cp2 (BACKUP)**

```text
vrrp_instance VI_1 {
    state BACKUP
    interface ens160
    virtual_router_id 51
    priority 90
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1234
    }
    virtual_ipaddress {
        192.168.10.177
    }
}
```

### **cp3 (BACKUP)**

```text
vrrp_instance VI_1 {
    state BACKUP
    interface ens160
    virtual_router_id 51
    priority 80
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1234
    }
    virtual_ipaddress {
        192.168.10.177
    }
}
```

**Enable and start Keepalived on all nodes:**

```bash
sudo systemctl enable keepalived
sudo systemctl start keepalived
```

**Verify VIP:**

```bash
ip addr show | grep 192.168.10.177
```

---

## **Step 4: Set Up iptables NAT Forwarding**

On **all control plane nodes**, forward VIP port 6443 to HAProxy 8443:

```bash
sudo iptables -t nat -A PREROUTING -d 192.168.10.177 -p tcp --dport 6443 -j REDIRECT --to-port 8443
sudo netfilter-persistent save
```

---

## **Step 5: Testing the Setup**

1. Test API endpoint from a client:

```bash
curl -vk https://brd-hq-cluster.brd.rw:6443/healthz
```

* Should return `ok`.

2. Test failover:

```bash
sudo systemctl stop keepalived  # on cp1
```

* VIP should move to cp2 automatically.
* API traffic continues uninterrupted.

---

## **Step 6: Summary**

* **HAProxy** listens on 8443 and balances traffic to all control plane nodes.
* **Keepalived** manages floating VIP (192.168.10.177) with failover.
* **iptables NAT** ensures clients use standard port 6443.
* **No extra hardware needed**; fully HA OpenShift API endpoint.
Do you want me to do that?
