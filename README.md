# Kubernetes Setup on Azure

This project automates the creation of a 3-node Kubernetes cluster on Microsoft Azure using Debian 12 VMs.

## Overview

The setup creates:
- **1 control-plane node** (`deb-vm1`) - 4 vCPU, 8 GiB RAM, with public IP for SSH access
- **2 worker nodes** (`deb-vm2`, `deb-vm3`) - 2 vCPU, 8 GiB RAM each, private IPs only

All nodes are deployed in the same virtual network (`10.20.0.0/16`) with internal SSH key-based authentication configured.

## Files

- **`setup.sh`** - Azure CLI script that provisions the VMs, network infrastructure, and configures SSH access between nodes
- **`K8S.MD`** - Detailed step-by-step guide for installing Kubernetes v1.35 using kubeadm on the provisioned VMs

## Prerequisites

- Azure CLI installed and authenticated
- Appropriate Azure subscription and permissions
- SSH public key for VM access

## Usage

1. Review and customize variables in `setup.sh` (resource group, location, SSH key, etc.)
2. Run the setup script:
   ```bash
   bash setup.sh
   ```
3. SSH into the control-plane node using the displayed public IP
4. Follow the instructions in `K8S.MD` to install and configure Kubernetes

## What Gets Created

- Virtual network and subnet
- Network security group (SSH access allowed)
- 3 Debian 12 VMs with internal hostname resolution
- SSH key-based authentication between all nodes
- Basic system updates and tools (btop, vim, wget)

After running `setup.sh`, you'll have a ready-to-configure infrastructure for a Kubernetes cluster. The actual Kubernetes installation steps are documented in `K8S.MD`.

## Yes, LLM helped in producing the setup.sh and K8S.MD
But after several tries and errors `:)`
So it will help me in future...
