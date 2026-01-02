## 1) Official Kubernetes v1.35 installation guides (kubeadm)

* **Installing kubeadm / kubelet / kubectl (v1.35)** ([Kubernetes][1])
* **Creating a cluster with kubeadm (v1.35)** ([Kubernetes][2])
* **Container runtimes (v1.35)** (prereqs like IP forwarding + containerd systemd cgroups) ([Kubernetes][3])

---

## 2) Build the cluster (Debian 12 on deb-vm1/2/3)

### A. On **ALL nodes (deb-vm1, deb-vm2, deb-vm3)**: prerequisites + containerd + Kubernetes packages

> Run these on each VM (you can SSH from VM1 to VM2/VM3 like you already set up).

```bash
# 0) become root for setup
sudo -i

# 1) Disable swap (kubelet fails when swap is on, unless explicitly configured)
swapoff -a
# Also remove any swap entries from /etc/fstab to persist across reboots
sed -i.bak '/\sswap\s/ s/^/#/' /etc/fstab
# (Kubeadm docs cover swap behavior and swapoff) 
# :contentReference[oaicite:3]{index=3}

# 2) Enable IPv4 forwarding (required for most cluster networking)
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
sysctl --system
sysctl net.ipv4.ip_forward
# :contentReference[oaicite:4]{index=4}

# 3) Install containerd (Debian package) and configure systemd cgroups
apt-get update
apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable systemd cgroups for runc (containerd 1.x uses the grpc.v1.cri path)
# Kubernetes docs show the exact config key(s) for containerd 1.x/2.x:
# :contentReference[oaicite:5]{index=5}
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Ensure CRI plugin is NOT disabled (docs mention checking disabled_plugins)
# :contentReference[oaicite:6]{index=6}
grep -n "disabled_plugins" -n /etc/containerd/config.toml || true

systemctl enable --now containerd
systemctl restart containerd

# 4) Install kubeadm/kubelet/kubectl from the official pkgs.k8s.io v1.35 repo
apt-get install -y apt-transport-https ca-certificates curl gpg
mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet
# :contentReference[oaicite:7]{index=7}
```

---

### B. On **deb-vm1 only (control-plane)**: initialize the cluster

Use VM1’s **private IP** (you already collect it as `ip_vm1` in your Azure script).

```bash
sudo -i

# Pick a Pod CIDR that matches your CNI choice.
# If you use Calico via Tigera operator quickstart defaults, 192.168.0.0/16 is common.
kubeadm init \
  --apiserver-advertise-address <VM1_PRIVATE_IP> \
  --pod-network-cidr 192.168.0.0/16
# kubeadm create-cluster guide: you must install a Pod network add-on after init
# :contentReference[oaicite:8]{index=8}

# Configure kubectl for your admin user (elnur)
su - elnur -c 'mkdir -p $HOME/.kube'
cp -i /etc/kubernetes/admin.conf /home/elnur/.kube/config
chown elnur:elnur /home/elnur/.kube/config
# :contentReference[oaicite:9]{index=9}
```

At the end, `kubeadm init` prints a **kubeadm join ...** command. **Copy it** (you’ll run it on VM2/VM3). ([Kubernetes][2])

---

### C. Install a CNI (network plugin) — required before CoreDNS becomes healthy

Kubernetes explicitly notes that **you must deploy a CNI-based Pod network add-on** and that **CoreDNS won’t start until networking is installed**. ([Kubernetes][2])

#### Option: Calico (Tigera Operator) (official Calico docs)

From **deb-vm1** as user `elnur` (kubectl configured):

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.2/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.2/manifests/custom-resources.yaml
# :contentReference[oaicite:12]{index=12}
```

Wait until system pods settle:

```bash
kubectl get pods -A
kubectl get nodes
```

---

### D. Join workers (deb-vm2, deb-vm3)

On **each worker**, run the exact join command printed by `kubeadm init`, e.g.:

```bash
sudo -i
kubeadm join <control-plane-host>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
# kubeadm init output tells you to do this on each node
# :contentReference[oaicite:13]{index=13}
```

Then back on **deb-vm1**:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

---

## 3) Quick sanity checks

* Nodes become `Ready` after CNI is installed and running. ([Kubernetes][2])
* If you ever change cgroup driver settings later, Kubernetes warns it’s a sensitive operation; avoid changing it after the node has joined unless you’re rebuilding. ([Kubernetes][3])

---

[1]: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/ "Installing kubeadm | Kubernetes"
[2]: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/ "Creating a cluster with kubeadm | Kubernetes"
[3]: https://kubernetes.io/docs/setup/production-environment/container-runtimes/ "Container Runtimes | Kubernetes"

