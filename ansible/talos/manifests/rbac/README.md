# Talos Kubernetes RBAC Patches

This directory contains RBAC patches required for proper Talos Linux cluster operation.

## Overview

Talos Linux uses Node Authorization mode, which restricts what nodes (kubelets) can access in the Kubernetes API. By default, nodes cannot list all other nodes, which causes warning messages and may break some CNI plugins and monitoring tools.

## Patches

### `node-reader.yaml`

**Purpose**: Allow nodes to list/watch other nodes in the cluster

**Problem it solves**:
```
User "system:node:talos-xxx-yyy" cannot list resource "nodes"
in API group "" at the cluster scope: node "talos-xxx-yyy"
cannot list all nodes, only its own node object
```

**What it does**:
- Creates ClusterRole `system:node-reader` with permissions to get/list/watch nodes
- Creates ClusterRoleBinding to bind this role to the `system:nodes` group
- All nodes are members of `system:nodes` group by default

**Required by**:
- CNI plugins (Cilium, Calico) for node-aware networking
- Storage drivers (Longhorn, OpenEBS) for node affinity
- Monitoring tools that need node topology information
- Node health checks and diagnostics

**Security**: Safe - only grants read-only access to node resources

## Usage

### Automatic Application (Recommended)

The RBAC patches are automatically applied during cluster deployment:

```bash
cd /home/user/projects/proxmox-infra/ansible/talos

# Full deployment (includes RBAC patches)
make deploy-full

# Or using tags
make run-tags TAGS="deployment"
```

### Manual Application

Apply RBAC patches to an existing cluster:

```bash
cd /home/user/projects/proxmox-infra/ansible/talos

# Apply RBAC patches
make apply-rbac
```

### Using Ansible Directly

```bash
cd /home/user/projects/proxmox-infra/ansible

ansible-playbook -i talos/inventory/hosts.yml \
  playbooks/talos/04-apply-rbac.yml
```

### Using kubectl Directly

```bash
export KUBECONFIG=/home/user/projects/proxmox-infra/ansible/talos/configs/kubeconfig

kubectl apply -f /home/user/projects/proxmox-infra/ansible/talos/manifests/rbac/node-reader.yaml
```

## Verification

Check if the RBAC patches are applied:

```bash
export KUBECONFIG=/home/user/projects/proxmox-infra/ansible/talos/configs/kubeconfig

# Check ClusterRole
kubectl get clusterrole system:node-reader

# Check ClusterRoleBinding
kubectl get clusterrolebinding system:node-reader

# View details
kubectl describe clusterrole system:node-reader
kubectl describe clusterrolebinding system:node-reader
```

## Troubleshooting

### Errors Still Appearing

If you still see "cannot list nodes" errors after applying the patch:

1. **Check if RBAC was applied successfully**:
   ```bash
   kubectl get clusterrolebinding system:node-reader
   ```

2. **Verify binding subjects**:
   ```bash
   kubectl get clusterrolebinding system:node-reader -o yaml | grep -A 5 subjects
   ```
   Should show: `name: system:nodes`

3. **Check kubelet logs** (wait 2-3 minutes for kubelets to refresh):
   ```bash
   # From a control plane node
   talosctl logs kubelet -n <node-ip>
   ```

4. **Restart kubelets** (if errors persist):
   ```bash
   talosctl service kubelet restart -n <node-ip>
   ```

### Remove RBAC Patches

If needed, remove the RBAC patches:

```bash
export KUBECONFIG=/home/user/projects/proxmox-infra/ansible/talos/configs/kubeconfig

kubectl delete clusterrolebinding system:node-reader
kubectl delete clusterrole system:node-reader
```

## References

- [Kubernetes Node Authorization](https://kubernetes.io/docs/reference/access-authn-authz/node/)
- [Talos Linux RBAC](https://www.talos.dev/latest/kubernetes-guides/configuration/rbac/)
- [RBAC ClusterRole and ClusterRoleBinding](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

## Maintenance

This directory is managed by Ansible automation. Manual changes should be avoided.

If you need to add new RBAC patches:

1. Create a new YAML file in this directory (e.g., `custom-patch.yaml`)
2. Update `/ansible/playbooks/talos/04-apply-rbac.yml` to include the new patch
3. Test the patch: `make apply-rbac`
4. Document the patch in this README
