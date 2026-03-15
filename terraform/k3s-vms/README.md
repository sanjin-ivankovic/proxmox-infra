# K3s VMs - Terraform Project (Dormant)

> **Status**: This is a dormant/skeleton project. It is not currently active
> but contains the structure and templates needed to deploy a K3s Kubernetes
> cluster on Proxmox VE using cloud-init Linux VMs.

## Overview

This project provisions Linux VMs configured for K3s cluster deployment.
It builds on the same patterns as `linux-vms/` but adds K3s-specific
role assignment (master/worker) and inventory generation.

## Prerequisites

- Proxmox VE with cloud-init templates
- Terraform >= 1.5.0
- R2 backend credentials configured

## Quick Start

1. Copy and configure instance definitions:

   ```bash
   cp instances/k3s-vms.auto.tfvars.example instances/k3s-vms.auto.tfvars
   ```

2. Configure secrets:

   ```bash
   cp terraform.tfvars.example terraform.tfvars.secret
   ```

3. Deploy:

   ```bash
   make setup
   make deploy
   ```

## Ansible Integration

After Terraform provisioning, use the Ansible playbooks in
`ansible/k3s/` and `ansible/playbooks/k3s/` to bootstrap and
configure the K3s cluster.
