#!/bin/bash

# ensure YAML files are copied and updated to fit your needs
# expected location ~/Helm/Authentik/
# run script from home directory

# offical deocumentation can be gound https://github.com/goauthentik/

# Step 1: Check for dependencies
# Helm
if ! command -v helm version &> /dev/null
then
    echo -e " \033[31;5mHelm not found, installing\033[0m"
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
else
    echo -e " \033[32;5mHelm already installed\033[0m"
fi
#Kubectl
if ! command -v kubectl version &> /dev/null
then
    echo -e " \033[31;5mKubectl not found, installing\033[0m"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
else
    echo -e " \033[32;5mKubectl already installed\033[0m"
fi

# Step 2: Add Helm charts
helm repo add authentik https://charts.goauthentik.io
helm repo update

# Step 3: Create Authentik namespace
kubectl create namespace authentik

# Step 4: Install Authentik
helm install --namespace=authentik authentik authentik/authentik -f ~/Helm/Authentik/values.yaml

# Step 5: Check deployment
kubectl get svc -n authentik
kubectl get pods -n authentik

# Step 6: Apply Middleware
kubectl apply -f ~/Helm/Authentik/default-headers.yaml

# Step 7: Apply Ingress
kubectl apply -f ~/Helm/Authentik/ingress.yaml

echo -e " \033[32;5mScript finished\033[0m"