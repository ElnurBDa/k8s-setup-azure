# Basics
rg="Some"
loc="westeurope"

vnet="vnet-lab"
subnet="subnet-lab"
nsg="nsg-vm1-ssh"

# VMs
vm1="deb-vm1"   # public SSH entry
vm2="deb-vm2"   # private only
vm3="deb-vm3"   # private only

adminUser="elnur"

# 4 vCPU (8 GiB RAM)
size_master="Standard_F4s_v2"
# 2 vCPU (8 GiB RAM)
size_worker="Standard_D2s_v5"

# Debian image (works in most regions; if it fails, see the "Find Debian URN" section below)
image="Debian:debian-12:12:latest"

# Your SSH public key from 
sshkey=$(cat ~/.ssh/id_rsa.pub)


az network vnet create \
  -g "$rg" -n "$vnet" \
  --address-prefixes 10.20.0.0/16 \
  --subnet-name "$subnet" \
  --subnet-prefixes 10.20.1.0/24


az network nsg create -g "$rg" -n "$nsg"

az network nsg rule create \
  -g "$rg" --nsg-name "$nsg" -n "Allow-SSH" \
  --priority 1000 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 22

az vm create \
  -g "$rg" -n "$vm1" \
  --computer-name "$vm1" \
  --image "$image" \
  --size "$size_master" \
  --admin-username "$adminUser" \
  --ssh-key-values "$sshkey" \
  --vnet-name "$vnet" --subnet "$subnet" \
  --nsg "$nsg" \
  --public-ip-sku Standard

az vm create \
  -g "$rg" -n "$vm2" \
  --computer-name "$vm2" \
  --image "$image" \
  --size "$size_worker" \
  --admin-username "$adminUser" \
  --ssh-key-values "$sshkey" \
  --vnet-name "$vnet" --subnet "$subnet" \
  --public-ip-address ""

az vm create \
  -g "$rg" -n "$vm3" \
  --computer-name "$vm3" \
  --image "$image" \
  --size "$size_worker" \
  --admin-username "$adminUser" \
  --ssh-key-values "$sshkey" \
  --vnet-name "$vnet" --subnet "$subnet" \
  --public-ip-address ""

pubip=$(az vm show -d -g "$rg" -n "$vm1" --query publicIps -o tsv)

echo "VMs are setup!"
echo "VM1 public IP: $pubip"
az vm list-ip-addresses -g "$rg" -o table

echo "Configuring internal SSH and host resolution..."
# (No need to sleep 3 minutes; run-command can be retried, and VMs are already running)
# sleep 180

ip_vm1=$(az vm show -d -g "$rg" -n "$vm1" --query privateIps -o tsv)
ip_vm2=$(az vm show -d -g "$rg" -n "$vm2" --query privateIps -o tsv)
ip_vm3=$(az vm show -d -g "$rg" -n "$vm3" --query privateIps -o tsv)

hosts=$(cat <<EOF
$ip_vm1 $vm1
$ip_vm2 $vm2
$ip_vm3 $vm3
EOF
)

# Push /etc/hosts entries to all VMs (idempotent-ish: we append; you can change to replace if you want)
for vm in $vm1 $vm2 $vm3; do
  az vm run-command invoke \
    -g "$rg" -n "$vm" \
    --command-id RunShellScript \
    --scripts "
      set -e
      echo '$hosts' | sudo tee -a /etc/hosts >/dev/null
    "
done

# 1) Ensure ~/.ssh exists everywhere (including VM1)
for vm in $vm1 $vm2 $vm3; do
  az vm run-command invoke \
    -g "$rg" -n "$vm" \
    --command-id RunShellScript \
    --scripts "
      set -e
      mkdir -p ~/.ssh
      chmod 700 ~/.ssh
      touch ~/.ssh/authorized_keys
      chmod 600 ~/.ssh/authorized_keys
    "
done

# 2) Generate a cluster SSH key on VM1 (idempotent)
az vm run-command invoke \
  -g "$rg" -n "$vm1" \
  --command-id RunShellScript \
  --scripts "
    set -e
    user='$adminUser'
    home=\$(getent passwd \$user | cut -d: -f6)
    install -d -m 700 -o \$user -g \$user \$home/.ssh
    if [ ! -f \$home/.ssh/id_cluster ]; then
      sudo -u \$user ssh-keygen -t ed25519 -f \$home/.ssh/id_cluster -N ''
    fi
    ls -la \$home/.ssh
  "


# 3) Fetch VM1 cluster public key in a safe format (base64)
pubkey_b64=$(
  az vm run-command invoke \
    -g "$rg" -n "$vm1" \
    --command-id RunShellScript \
    --query "value[0].message" -o tsv \
    --scripts "
      set -e
      user='$adminUser'
      home=\$(getent passwd \$user | cut -d: -f6)
      echo __PUBKEY_B64_BEGIN__
      base64 -w0 \$home/.ssh/id_cluster.pub
      echo
      echo __PUBKEY_B64_END__
    " \
  | sed -n '/__PUBKEY_B64_BEGIN__/,/__PUBKEY_B64_END__/p' \
  | sed '1d;$d' \
  | tr -d '\r\n'
)

# 4) Install cluster public key on ALL nodes (VM1/2/3) into authorized_keys (no duplicates)
for vm in "$vm1" "$vm2" "$vm3"; do
  az vm run-command invoke \
    -g "$rg" -n "$vm" \
    --command-id RunShellScript \
    --scripts "
      set -e
      user='$adminUser'
      home=\$(getent passwd \$user | cut -d: -f6)
      install -d -m 700 -o \$user -g \$user \$home/.ssh
      touch \$home/.ssh/authorized_keys
      chown \$user:\$user \$home/.ssh/authorized_keys
      chmod 600 \$home/.ssh/authorized_keys
      key=\$(echo '$pubkey_b64' | base64 -d)
      grep -qxF \"\$key\" \$home/.ssh/authorized_keys || echo \"\$key\" >> \$home/.ssh/authorized_keys
    "
done


# 5) Configure VM1 SSH client to use cluster key + auto-accept host keys
az vm run-command invoke \
  -g "$rg" -n "$vm1" \
  --command-id RunShellScript \
  --scripts "
    set -e
    user='$adminUser'
    home=\$(getent passwd \$user | cut -d: -f6)
    cat > \$home/.ssh/config <<'CFG'
Host deb-vm*
  User $adminUser
  IdentityFile ~/.ssh/id_cluster
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
CFG
    chown $adminUser:$adminUser \$home/.ssh/config
    chmod 600 \$home/.ssh/config
  "

# 6) Update all VMs
for vm in "$vm1" "$vm2" "$vm3"; do
  az vm run-command invoke \
    -g "$rg" -n "$vm" \
    --command-id RunShellScript \
    --scripts "
      set -e
      apt update
      apt upgrade -y
      apt install btop vim wget -y
    "
done


echo "Internal SSH configured. From VM1 you should be able to:"
echo "  ssh deb-vm2"
echo "  ssh deb-vm3"

echo "start exploring!" 
echo "ssh $adminUser@$pubip"
