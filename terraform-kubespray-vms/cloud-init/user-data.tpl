#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ${hostname}
    username: ubuntu
    password: "${password_hash}"

  ssh:
    install-server: true
    allow-pw: true
    authorized-keys:
      - ${ssh_public_key}

  locale: en_US.UTF-8
  keyboard:
    layout: us

  network:
    version: 2
    ethernets:
      nic0:
        match:
          name: "e*"
        set-name: ens160
        addresses:
          - ${ip}/${prefix}
        gateway4: ${gateway}
        nameservers:
          addresses: [${dns_list}]

  storage:
    layout:
      name: direct

  packages:
    - open-vm-tools
    - qemu-guest-agent
    - ca-certificates
    - curl

  late-commands:
    - curtin in-target --target=/target -- bash -lc "swapoff -a && sed -i.bak '/ swap / s/^/#/' /etc/fstab"
    - curtin in-target --target=/target -- bash -lc "cat >/etc/modules-load.d/k8s.conf <<EOF2
overlay
br_netfilter
EOF2"
    - curtin in-target --target=/target -- bash -lc "modprobe overlay && modprobe br_netfilter"
    - curtin in-target --target=/target -- bash -lc "cat >/etc/sysctl.d/k8s.conf <<EOF2
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF2"
    - curtin in-target --target=/target -- bash -lc "sysctl --system"

