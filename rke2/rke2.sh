#!/bin/bash

# Install ShellCheck if it's not already installed
if ! command -v shellcheck &> /dev/null; then
    echo "ShellCheck is not installed. Installing now..."
    sudo apt-get install shellcheck -y
fi

# Run ShellCheck on this script
shellcheck "$0"

# Define a global error handler
function handleError {
  echo "Error occurred on line $1 of the script"
  exit 1
}

# Set the error handler
trap 'handleError $LINENO' ERR

# Enable the errtrace shell option
set -o errtrace

# Define the nodes
# admin: the node that will act as the admin
# masters: the nodes that will act as the master nodes
# workers: the nodes that will act as the worker nodes
# storages: the nodes that will act as the storage nodes
admin=192.168.10.9
masters=(192.168.10.10 192.168.10.11 192.168.10.12)
workers=(192.168.10.13 192.168.10.14)
storages=(192.168.10.15 192.168.10.16 192.168.10.17)

# Define the username that will be used for SSH connections
username="ubuntu"

# Define the SSH certificate name
certName=~/id_rsa

# Combine all nodes into a single array
nodes=($admin "${masters[@]}" "${workers[@]}" "${storages[@]}")

# Copy the public key to all nodes
for node in "${nodes[@]}"
do
    # Skip the admin node
    if [ "$node" != "$admin" ]; then
        # Create the .ssh directory on the node if it doesn't exist
        ssh -i $certName $username@$node 'mkdir -p ~/.ssh'
        
        # Check if the public key is already in the authorized_keys file
        if ! ssh -i $certName $username@$node 'grep -q "$(cat ~/id_rsa.pub)" ~/.ssh/authorized_keys'; then
            # Copy the public key to the node's authorized_keys file
            scp -i $certName $username@$admin:~/id_rsa.pub $username@$node:~/.ssh/authorized_keys
        fi
    fi
done

# Install necessary tools on all nodes
for node in "${nodes[@]}"
do
    # Update the package lists for upgrades and new package installations
    ssh -i $certName $username@$node 'sudo apt-get update'

    # Install curl if it's not already installed
    if ! ssh -i $certName $username@$node 'command -v curl &> /dev/null'; then
        ssh -i $certName $username@$node 'sudo apt-get install -y curl'
    fi

    # Install apt-transport-https if it's not already installed
    if ! ssh -i $certName $username@$node 'dpkg -s apt-transport-https &> /dev/null'; then
        ssh -i $certName $username@$node 'sudo apt-get install -y apt-transport-https'
    fi

    # Install gnupg2 if it's not already installed
    if ! ssh -i $certName $username@$node 'command -v gpg2 &> /dev/null'; then
        ssh -i $certName $username@$node 'sudo apt-get install -y gnupg2'
    fi

    # Add the Google Cloud public signing key
    ssh -i $certName $username@$node 'curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -'

    # Add the Kubernetes apt repository if it's not already added
    if ! ssh -i $certName $username@$node 'grep -q "deb https://apt.kubernetes.io/ kubernetes-xenial main" /etc/apt/sources.list.d/kubernetes.list'; then
        ssh -i $certName $username@$node 'echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list'
    fi

    # Update the package lists
    ssh -i $certName $username@$node 'sudo apt-get update'
done

# Install RKE2 on the admin node
# Check if RKE2 is already installed
if ! ssh -i $certName $username@$admin 'command -v rke2 &> /dev/null'; then
    # Download and install RKE2
    ssh -i $certName $username@$admin 'curl -sfL https://get.rke2.io | sh -'
fi

# Check if the RKE2 service is already enabled
if ! ssh -i $certName $username@$admin 'systemctl is-enabled rke2-server.service &> /dev/null'; then
    # Enable the RKE2 service to start on boot
    ssh -i $certName $username@$admin 'systemctl enable rke2-server.service'
fi

# Check if the RKE2 service is already active
if ! ssh -i $certName $username@$admin 'systemctl is-active rke2-server.service &> /dev/null'; then
    # Start the RKE2 service
    ssh -i $certName $username@$admin 'systemctl start rke2-server.service'
fi

# Get the RKE2 token from the admin node
# This loop will keep trying to get the token until it succeeds
while true; do
    # Try to get the token
    token=$(ssh -i $certName $username@$admin 'sudo cat /var/lib/rancher/rke2/server/node-token' 2>/dev/null)
    # If the token is not empty, break the loop
    if [[ -n "$token" ]]; then
        break
    fi
    # If the token is empty, print a message and wait for 5 seconds before trying again
    echo "Waiting for RKE2 token..."
    sleep 5
done

# Install RKE2 on the master nodes
for node in "${masters[@]}"
do
    # Check if RKE2 is already installed
    if ! ssh -i $certName $username@$node 'command -v rke2 &> /dev/null'; then
        # Download and install RKE2
        ssh -i $certName $username@$node "curl -sfL https://get.rke2.io | INSTALL_RKE2_EXEC='server --token $token --server https://$admin:9345' sh -"
    fi

    # Check if the RKE2 service is already enabled
    if ! ssh -i $certName $username@$node 'systemctl is-enabled rke2-server.service &> /dev/null'; then
        # Enable the RKE2 service to start on boot
        ssh -i $certName $username@$node 'systemctl enable rke2-server.service'
    fi

    # Check if the RKE2 service is already active
    if ! ssh -i $certName $username@$node 'systemctl is-active rke2-server.service &> /dev/null'; then
        # Start the RKE2 service
        ssh -i $certName $username@$node 'systemctl start rke2-server.service'
    fi
done

# Install RKE2 on the worker nodes
for node in "${workers[@]}"
do
    # Check if RKE2 is already installed
    if ! ssh -i $certName $username@$node 'command -v rke2 &> /dev/null'; then
        # Download and install RKE2
        ssh -i $certName $username@$node "curl -sfL https://get.rke2.io | INSTALL_RKE2_EXEC='agent --token $token --server https://$admin:9345' sh -"
    fi

    # Check if the RKE2 agent service is already enabled
    if ! ssh -i $certName $username@$node 'systemctl is-enabled rke2-agent.service &> /dev/null'; then
        # Enable the RKE2 agent service to start on boot
        ssh -i $certName $username@$node 'systemctl enable rke2-agent.service'
    fi

    # Check if the RKE2 agent service is already active
    if ! ssh -i $certName $username@$node 'systemctl is-active rke2-agent.service &> /dev/null'; then
        # Start the RKE2 agent service immediately
        ssh -i $certName $username@$node 'systemctl start rke2-agent.service'
    fi
done

# Wait for all nodes to be ready
# This command blocks until all nodes are in the 'Ready' state or until the timeout is reached
ssh -i $certName $username@$admin 'kubectl wait --for=condition=Ready node --all --timeout=300s'

# Install Cilium
# Cilium is a networking and network policy plugin for Kubernetes
# Check if the Cilium namespace already exists
if ! ssh -i $certName $username@$admin 'kubectl get namespace cilium &> /dev/null'; then
    # Create a new namespace for Cilium
    ssh -i $certName $username@$admin 'kubectl create namespace cilium'
fi

# Check if the Cilium Helm repository already exists
if ! ssh -i $certName $username@$admin 'helm repo list | grep cilium &> /dev/null'; then
    # Add the Cilium Helm repository
    ssh -i $certName $username@$admin 'helm repo add cilium https://helm.cilium.io/'
fi

# Check if Cilium is already installed
if ! ssh -i $certName $username@$admin 'helm list -n cilium | grep cilium &> /dev/null'; then
    # Install Cilium using Helm
    ssh -i $certName $username@$admin 'helm install cilium cilium/cilium --version 1.9.5 --namespace cilium'
fi

# Wait for Cilium to be ready
# This loop checks the status of the Cilium pods every 5 seconds
# Once all Cilium pods are in the 'Running' state, the loop breaks
while true; do
    status=$(ssh -i $certName $username@$admin 'kubectl -n cilium get pods -l k8s-app=cilium | grep -v NAME | awk '{print $3}'')
    if [[ "$status" == "Running" ]]; then
        break
    fi
    echo "Waiting for Cilium to be ready..."
    sleep 5
done

# Install MetalLB
# MetalLB is a load balancer for bare metal Kubernetes clusters
# It allows you to assign external IP addresses to services
# Check if the MetalLB namespace already exists
if ! ssh -i $certName $username@$admin 'kubectl get namespace metallb-system &> /dev/null'; then
    # Install the MetalLB namespace and the MetalLB components
    ssh -i $certName $username@$admin 'kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/namespace.yaml'
    ssh -i $certName $username@$admin 'kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/metallb.yaml'
fi

# Check if the MetalLB secret already exists
if ! ssh -i $certName $username@$admin 'kubectl get secret -n metallb-system memberlist &> /dev/null'; then
    # Create a secret for the MetalLB speaker component
    ssh -i $certName $username@$admin 'kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"'
fi

# Create the MetalLB config file
# This file defines the IP range that MetalLB can use to assign external IP addresses
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

# Check if the MetalLB config already exists
if ! ssh -i $certName $username@$admin 'kubectl get configmap -n metallb-system config &> /dev/null'; then
    # Apply the MetalLB config
    # This command sends the MetalLB configuration to the Kubernetes cluster
    echo "$metallb_config" | ssh -i $certName $username@$admin 'kubectl apply -f -'
fi

# Install Rancher
# Rancher is a complete software stack for teams adopting containers
# It addresses the operational and security challenges of managing multiple Kubernetes clusters
# Check if the Rancher Helm repository already exists
if ! ssh -i $certName $username@$admin 'helm repo list | grep rancher-latest &> /dev/null'; then
    # Add the Rancher Helm repository
    ssh -i $certName $username@$admin 'helm repo add rancher-latest https://releases.rancher.com/server-charts/latest'
fi

# Check if the Rancher namespace already exists
if ! ssh -i $certName $username@$admin 'kubectl get namespace cattle-system &> /dev/null'; then
    # Create a new namespace for Rancher
    ssh -i $certName $username@$admin 'kubectl create namespace cattle-system'
fi

# Check if Rancher is already installed
if ! ssh -i $certName $username@$admin 'helm list -n cattle-system | grep rancher &> /dev/null'; then
    # Install Rancher using Helm
    ssh -i $certName $username@$admin 'helm install rancher rancher-latest/rancher --namespace cattle-system --set hostname=rancher.kuale.io'  # Replace rancher.my.org with your actual hostname
fi

# Wait for Rancher to be ready
# This loop checks the status of the Rancher pods every 5 seconds
# Once all Rancher pods are in the 'Running' state, the loop breaks
while true; do
    status=$(ssh -i $certName $username@$admin 'kubectl -n cattle-system get pods -l app=rancher | grep -v NAME | awk '{print $3}'')
    if [[ "$status" == "Running" ]]; then
        break
    fi
    echo "Waiting for Rancher to be ready..."
    sleep 5
done

# Install Cert Manager
# Cert Manager is a native Kubernetes certificate management controller
# It can help with issuing certificates from a variety of sources, like Let’s Encrypt, HashiCorp Vault, Venafi, a simple signing key pair, or self signed
# Check if the Cert-Manager namespace already exists
if ! ssh -i $certName $username@$admin 'kubectl get namespace cert-manager &> /dev/null'; then
    # Create a namespace for Cert-Manager
    ssh -i $certName $username@$admin 'kubectl create namespace cert-manager'
    # Install Cert-Manager
    ssh -i $certName $username@$admin 'kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.1.0/cert-manager.yaml -n cert-manager'
fi

# Wait for Cert-Manager to be ready
# This loop checks the status of the Cert-Manager pods every 5 seconds
# Once all Cert-Manager pods are in the 'Running' state, the loop breaks
while true; do


# Install Traefik
# Check if the Traefik namespace already exists
if ! ssh -i $certName $username@$admin 'kubectl get namespace traefik'; then
    ssh -i $certName $username@$admin 'kubectl create namespace traefik'
fi

# Add the Traefik Helm repository
# No need to check if it already exists because 'helm repo add' is idempotent
ssh -i $certName $username@$admin 'helm repo add traefik https://helm.traefik.io/traefik'

# Download and modify the values file
# Check if the values file already exists
if ! ssh -i $certName $username@$admin 'test -f values.yaml'; then
    ssh -i $certName $username@$admin 'wget https://raw.githubusercontent.com/Kwah-lee/kubernetes/main/traefik/values.yml'
    ssh -i $certName $username@$admin 'sed -i "s/placeholder-ip/192.168.1.100/g" values.yaml'  # Replace with your actual IP
    ssh -i $certName $username@$admin 'sed -i "s/placeholder-lb/lb-config/g" values.yaml'  # Replace with your actual LB config
fi

# Install Traefik using the modified values file
# Check if Traefik is already installed
if ! ssh -i $certName $username@$admin 'helm list -n traefik | grep traefik'; then
    ssh -i $certName $username@$admin 'helm install traefik traefik/traefik -n traefik -f values.yaml'
fi

# Wait for Traefik to be ready
# This loop checks the status of the Traefik pods every 5 seconds
# Once all Traefik pods are in the 'Running' state, the loop breaks
while true; do
    status=$(ssh -i $certName $username@$admin 'kubectl -n traefik get pods -l app.kubernetes.io/name=traefik | grep -v NAME | awk '{print $3}'')
    if [[ "$status" == "Running" ]]; then
        break
    fi
    echo "Waiting for Traefik to be ready..."
    sleep 5
done

# Create necessary namespaces
# Check if the openebs namespace already exists
if ! ssh -i $certName $username@$admin 'kubectl get namespace openebs'; then
    ssh -i $certName $username@$admin 'kubectl create namespace openebs'
fi

# Install OpenEBS
# Check if OpenEBS is already installed
if ! ssh -i $certName $username@$admin 'kubectl get deployment -n openebs maya-apiserver'; then
    ssh -i $certName $username@$admin 'kubectl apply -f https://openebs.github.io/charts/openebs-operator.yaml'
fi

# Wait for OpenEBS to be ready
# This command blocks until the OpenEBS Maya API server is available or until the timeout is reached
ssh -i $certName $username@$admin 'kubectl wait --for=condition=available --timeout=600s deployment -l openebs.io/component-name=maya-apiserver -n openebs'

# Get the names of the first three block devices
# These block devices will be used to create a cStor pool
blockdevices=$(ssh -i $certName $username@$admin 'kubectl get blockdevice -n openebs -o jsonpath="{.items[*].metadata.name}"' | awk '{print $1,$2,$3}')

# Create a cStor pool
# Check if the cStor pool already exists
if ! ssh -i $certName $username@$admin 'kubectl get spc cstor-disk'; then
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
    # This command sends the cStor pool configuration to the Kubernetes cluster
    echo "$cstor_pool_config" | ssh -i $certName $username@$admin 'cat > cstor-pool-config.yaml'
    ssh -i $certName $username@$admin 'kubectl apply -f cstor-pool-config.yaml'
fi

# Verify that the cStor pool pods are running
# This command lists the cStor pool pods and their statuses
ssh -i $certName $username@$admin 'kubectl get pods -n openebs -l openebs.io/component-name=cstor-pool'

# Create a namespace for Authentik
# Authentik is an open-source Identity Provider focused on versatility and configurability
ssh -i $certName $username@$admin 'kubectl create namespace authentik'

# Add Authentik Helm repository and update Helm repositories
ssh -i $certName $username@$admin 'helm repo add authentik https://charts.goauthentik.io'
ssh -i $certName $username@$admin 'helm repo update'

# Create values.yaml file with your custom values
# This file is used to customize the installation of Authentik
authentik_values=$(cat <<EOF
# Your values.yaml content here
EOF
)

echo "$authentik_values" | ssh -i $certName $username@$admin 'cat > values.yaml'

# Install Authentik using your values.yaml file
ssh -i $certName $username@$admin 'helm install authentik authentik/authentik -n authentik -f values.yaml'

# Expose Rancher service as LoadBalancer
# This command creates a new service that exposes the Rancher deployment as a LoadBalancer
ssh -i $certName $username@$admin 'kubectl expose deployment rancher --name=rancher-lb --port=443 --type=LoadBalancer -n cattle-system'

# Wait for LoadBalancer to come online
# This loop checks the status of the LoadBalancer every 5 seconds
# Once the LoadBalancer is online, the loop breaks
while true; do
    status=$(ssh -i $certName $username@$admin 'kubectl get svc rancher-lb -n cattle-system -o jsonpath="{.status.loadBalancer.ingress[0].ip}"')
    if [[ -n "$status" ]]; then
        break
    fi
    echo "Waiting for LoadBalancer to come online..."
    sleep 5
done

# Get the IP of the LoadBalancer
# This command retrieves the IP address of the LoadBalancer
rancher_lb_ip=$(ssh -i $certName $username@$admin 'kubectl get svc rancher-lb -n cattle-system -o jsonpath="{.status.loadBalancer.ingress[0].ip}"')

# Print completion message
# This message indicates that the script has completed successfully and provides the URL to access Rancher
echo "The script has completed successfully. You can access Rancher at https://$rancher_lb_ip. Please set the password manually."
