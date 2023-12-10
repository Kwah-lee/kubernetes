#!/bin/bash

# Define the nodes
admin=192.168.10.9
masters=(192.168.10.10 192.168.10.11 192.168.10.12)
workers=(192.168.10.13 192.168.10.14)
storages=(192.168.10.15 192.168.10.16 192.168.10.17)

# Define the username
username="ubuntu"

# Define the SSH certificate name
certName=~/id_rsa

# Combine all nodes into a single array
nodes=($admin "${masters[@]}" "${workers[@]}" "${storages[@]}")

# Copy the public key to all nodes
for node in "${nodes[@]}"
do
    if [ "$node" != "$admin" ]; then
        ssh -i $certName $username@$node 'mkdir -p ~/.ssh'
        scp -i $certName $username@$admin:~/id_rsa.pub $username@$node:~/.ssh/authorized_keys
    fi
done

# Install necessary tools on all nodes
for node in "${nodes[@]}"
do
    ssh -i $certName $username@$node 'sudo apt-get update && sudo apt-get install -y curl apt-transport-https gnupg2'
    ssh -i $certName $username@$node 'curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -'
    ssh -i $certName $username@$node 'echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list'
    ssh -i $certName $username@$node 'sudo apt-get update && sudo apt-get install -y kubectl'
    ssh -i $certName $username@$node 'curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -'
    ssh -i $certName $username@$node 'echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list'
    ssh -i $certName $username@$node 'sudo apt-get update && sudo apt-get install -y helm'
done

# Install RKE2 on the admin node
ssh -i $certName $username@$admin 'curl -sfL https://get.rke2.io | sh -'
ssh -i $certName $username@$admin 'systemctl enable rke2-server.service'
ssh -i $certName $username@$admin 'systemctl start rke2-server.service'

# Get the RKE2 token from the admin node
while true; do
    token=$(ssh -i $certName $username@$admin 'sudo cat /var/lib/rancher/rke2/server/node-token' 2>/dev/null)
    if [[ -n "$token" ]]; then
        break
    fi
    echo "Waiting for RKE2 token..."
    sleep 5
done

# Install RKE2 on the master nodes
for node in "${masters[@]}"
do
    ssh -i $certName $username@$node "curl -sfL https://get.rke2.io | INSTALL_RKE2_EXEC='server --token $token --server https://$admin:9345' sh -"
    ssh -i $certName $username@$node 'systemctl enable rke2-server.service'
    ssh -i $certName $username@$node 'systemctl start rke2-server.service'
done

# Install RKE2 on the worker nodes
for node in "${workers[@]}"
do
    ssh -i $certName $username@$node "curl -sfL https://get.rke2.io | INSTALL_RKE2_EXEC='agent --token $token --server https://$admin:9345' sh -"
    ssh -i $certName $username@$node 'systemctl enable rke2-agent.service'
    ssh -i $certName $username@$node 'systemctl start rke2-agent.service'
done

# Wait for all nodes to be ready
ssh -i $certName $username@$admin 'kubectl wait --for=condition=Ready node --all --timeout=300s'

# Install Cilium
ssh -i $certName $username@$admin 'kubectl create namespace cilium'
ssh -i $certName $username@$admin 'helm repo add cilium https://helm.cilium.io/'
ssh -i $certName $username@$admin 'helm install cilium cilium/cilium --version 1.9.5 --namespace cilium'

# Wait for Cilium to be ready
while true; do
    status=$(ssh -i $certName $username@$admin 'kubectl -n cilium get pods -l k8s-app=cilium | grep -v NAME | awk '{print $3}'')
    if [[ "$status" == "Running" ]]; then
        break
    fi
    echo "Waiting for Cilium to be ready..."
    sleep 5
done

# Install MetalLB
ssh -i $certName $username@$admin 'kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/namespace.yaml'
ssh -i $certName $username@$admin 'kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/metallb.yaml'
ssh -i $certName $username@$admin 'kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"'

# Create the MetalLB config file
metallb_config=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.10.100-192.168.10.200  # Replace with your actual IP range
EOF
)

# Apply the MetalLB config
echo "$metallb_config" | ssh -i $certName $username@$admin 'kubectl apply -f -'


# Install Rancher
ssh -i $certName $username@$admin 'helm repo add rancher-latest https://releases.rancher.com/server-charts/latest'
ssh -i $certName $username@$admin 'kubectl create namespace cattle-system'
ssh -i $certName $username@$admin 'helm install rancher rancher-latest/rancher --namespace cattle-system --set hostname=rancher.kuale.io'  # Replace rancher.my.org with your actual hostname

# Wait for Rancher to be ready
while true; do
    status=$(ssh -i $certName $username@$admin 'kubectl -n cattle-system get pods -l app=rancher | grep -v NAME | awk '{print $3}'')
    if [[ "$status" == "Running" ]]; then
        break
    fi
    echo "Waiting for Rancher to be ready..."
    sleep 5
done

# Install Cert Manager
ssh -i $certName $username@$admin 'kubectl create namespace cert-manager'
ssh -i $certName $username@$admin 'kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.1.0/cert-manager.yaml -n cert-manager'

# Wait for Cert-Manager to be ready
while true; do
    status=$(ssh -i $certName $username@$admin 'kubectl -n cert-manager get pods -l app.kubernetes.io/instance=cert-manager | grep -v NAME | awk '{print $3}'')
    if [[ "$status" == "Running" ]]; then
        break
    fi
    echo "Waiting for Cert-Manager to be ready..."
    sleep 5
done


# Install Traefik
ssh -i $certName $username@$admin 'kubectl create namespace traefik'
ssh -i $certName $username@$admin 'helm repo add traefik https://helm.traefik.io/traefik'

# Download and modify the values file
ssh -i $certName $username@$admin 'wget https://raw.githubusercontent.com/JamesTurland/JimsGarage/main/Kubernetes/Traefik-PiHole/Helm/Traefik/values.yaml'
ssh -i $certName $username@$admin 'sed -i "s/placeholder-ip/192.168.1.100/g" values.yaml'  # Replace with your actual IP
ssh -i $certName $username@$admin 'sed -i "s/placeholder-lb/lb-config/g" values.yaml'  # Replace with your actual LB config

# Install Traefik with the modified values file
ssh -i $certName $username@$admin 'helm install traefik traefik/traefik -n traefik -f values.yaml'

# Wait for Traefik to be ready
while true; do
    status=$(ssh -i $certName $username@$admin 'kubectl -n traefik get pods -l app.kubernetes.io/name=traefik | grep -v NAME | awk '{print $3}'')
    if [[ "$status" == "Running" ]]; then
        break
    fi

# Create necessary namespaces
ssh -i $certName $username@$admin 'kubectl create namespace openebs'

# Install OpenEBS
ssh -i $certName $username@$admin 'kubectl apply -f https://openebs.github.io/charts/openebs-operator.yaml'

# Wait for OpenEBS to be ready
ssh -i $certName $username@$admin 'kubectl wait --for=condition=available --timeout=600s deployment -l openebs.io/component-name=maya-apiserver -n openebs'

# Get the names of the first three block devices
blockdevices=$(ssh -i $certName $username@$admin 'kubectl get blockdevice -n openebs -o jsonpath="{.items[*].metadata.name}"' | awk '{print $1,$2,$3}')

# Create a cStor pool
cstor_pool_config=$(cat <<EOF
apiVersion: openebs.io/v1alpha1
kind: StoragePoolClaim
metadata:
  name: cstor-disk
spec:
  name: cstor-disk
  type: disk
  poolSpec:
    poolType: mirrored
  blockDevices:
    blockDeviceList:
    - $blockdevices
EOF
)

# Apply the cStor pool config
echo "$cstor_pool_config" | ssh -i $certName $username@$admin 'cat > cstor-pool-config.yaml'
ssh -i $certName $username@$admin 'kubectl apply -f cstor-pool-config.yaml'

# ...

# Verify that the cStor pool pods are running
ssh -i $certName $username@$admin 'kubectl get pods -n openebs -l openebs.io/component-name=cstor-pool'


# Create a namespace for Authentik
ssh -i $certName $username@$admin 'kubectl create namespace authentik'

# Add Authentik Helm repository and update Helm repositories
ssh -i $certName $username@$admin 'helm repo add authentik https://charts.goauthentik.io'
ssh -i $certName $username@$admin 'helm repo update'

# Create values.yaml file with your custom values
authentik_values=$(cat <<EOF
# Your values.yaml content here
EOF
)

echo "$authentik_values" | ssh -i $certName $username@$admin 'cat > values.yaml'

# Install Authentik using your values.yaml file
ssh -i $certName $username@$admin 'helm install authentik authentik/authentik -n authentik -f values.yaml'

# Expose Rancher service as LoadBalancer
ssh -i $certName $username@$admin 'kubectl expose deployment rancher --name=rancher-lb --port=443 --type=LoadBalancer -n cattle-system'

# Wait for LoadBalancer to come online
while true; do
    status=$(ssh -i $certName $username@$admin 'kubectl get svc rancher-lb -n cattle-system -o jsonpath="{.status.loadBalancer.ingress[0].ip}"')
    if [[ -n "$status" ]]; then
        break
    fi
    echo "Waiting for LoadBalancer to come online..."
    sleep 5
done

# Get the IP of the LoadBalancer
rancher_lb_ip=$(ssh -i $certName $username@$admin 'kubectl get svc rancher-lb -n cattle-system -o jsonpath="{.status.loadBalancer.ingress[0].ip}"')

# Print completion message
echo "The script has completed successfully. You can access Rancher at https://$rancher_lb_ip. Please set the password manually."