# RKE2 Deployment Script

This repository contains a Bash script for deploying RKE2 on a cluster of nodes. The script is designed to be run on a Linux system and assumes that the nodes in your cluster are running Ubuntu.

**Disclaimer**: This script is a work in progress and has not been fully tested. Use it at your own risk.

## Prerequisites

Before running the script, make sure you have the following:

- A Linux system with Bash. This will be the system where you run the script.
- A cluster of nodes running Ubuntu. The script supports the following types of nodes:
  - One admin node
  - Multiple master nodes
  - Multiple worker nodes
  - Multiple storage nodes
- SSH access to all nodes in the cluster. The script uses SSH to execute commands on the nodes.

## Usage

Follow these steps to use the script:

1. Clone this repository:
    ```
    git clone https://github.com/Kwah-lee/kubernetes.git
    cd kubernetes/rke2
    ```

2. Make the script executable:
    ```
    chmod +x rke2.sh
    ```

3. Run the script:
    ```
    ./rke2.sh
    ```

## Configuration

The script uses the following variables to define the cluster:

- `admin`: The IP address of the admin node.
- `masters`: An array of IP addresses for the master nodes.
- `workers`: An array of IP addresses for the worker nodes.
- `storages`: An array of IP addresses for the storage nodes.
- `username`: The username for SSH connections.
- `certName`: The path to the SSH certificate.

You can modify these variables in the script to match your cluster configuration.

## What the Script Does

Here's a brief overview of what the script does:

1. Defines the nodes in the cluster.
2. Copies the public SSH key to all nodes to enable password-less SSH connections.
3. Installs necessary tools on all nodes, including `curl`, `apt-transport-https`, `gnupg2`, `kubectl`, and `helm`.
4. Installs RKE2 on the admin node and starts the RKE2 server service.
5. Waits for the RKE2 token to be generated on the admin node.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[MIT](LICENSE)
