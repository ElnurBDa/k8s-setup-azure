# To expose a NodePort service via sub sub domain
## Step 1 — Open port 80 (and optionally 443) on VM1 NSG

```bash
rg="SocarTI"
nsg="nsg-vm1-ssh"

az network nsg rule create \
  -g "$rg" --nsg-name "$nsg" -n "Allow-HTTP" \
  --priority 1010 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet \
  --destination-port-ranges 80

az network nsg rule create \
  -g "$rg" --nsg-name "$nsg" -n "Allow-HTTPS" \
  --priority 1020 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet \
  --destination-port-ranges 443
```
(HTTPS Optional)

## Step 2 — DNS wildcard record

Wildcard for the “dev” zone
Type: A
Name: *.dev
Value: VM1_PUBLIC_IP

## Step 3 — Install NGINX on VM1 (host-level proxy)

on VM1
```bash
sudo apt install -y nginx
```

## Step 4 — Configure NGINX to route node-port hostnames → NodeIP:NodePort

```bash
sudo tee /etc/nginx/conf.d/nodeport-router-maps.conf >/dev/null <<'NGINX'
# Build backend directly from Host header
map $host $backend {
  default "";

  # deb-vm1-30080.dev.elnurbda.com -> 10.20.1.4:30080
  ~^deb-vm1-(3[0-2][0-9][0-9][0-9])\.dev\.elnurbda\.com$ 10.20.1.4:$1;

  # deb-vm2-30080.dev.elnurbda.com -> 10.20.1.5:30080
  ~^deb-vm2-(3[0-2][0-9][0-9][0-9])\.dev\.elnurbda\.com$ 10.20.1.5:$1;

  # deb-vm3-30080.dev.elnurbda.com -> 10.20.1.6:30080
  ~^deb-vm3-(3[0-2][0-9][0-9][0-9])\.dev\.elnurbda\.com$ 10.20.1.6:$1;
}
NGINX


sudo tee /etc/nginx/sites-available/nodeport-router.conf >/dev/null <<'NGINX'
server {
  listen 80;

  server_name ~\.dev\.elnurbda\.com$;

  location / {
    # If no backend matched → 404
    if ($backend = "") { return 404; }

    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;

    proxy_pass http://$backend;
  }
}
NGINX


sudo ln -sf /etc/nginx/sites-available/nodeport-router.conf /etc/nginx/sites-enabled/nodeport-router.conf

sudo nginx -t
sudo systemctl reload nginx


```

## Step 5 — Create a test app in Kubernetes exposed via NodePort

```bash
kubectl create deploy hello --image=nginxdemos/hello
kubectl expose deploy hello --port 80 --type NodePort
kubectl get svc hello

```

or

```bash
SVC=nginx-svc; NS=default; \
NODE=$(kubectl get pod -l run=nginx -n $NS -o jsonpath='{.items[0].spec.nodeName}'); \
PORT=$(kubectl get svc $SVC -n $NS -o jsonpath='{.spec.ports[0].nodePort}'); \
echo "http://$NODE-$PORT.dev.elnurbda.com"
```
