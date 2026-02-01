# CheckMK Agent Deployment

Automated deployment of CheckMK monitoring agents to LXC containers and VMs
using Ansible.

## Features

- ✅ **Automated agent installation** - Downloads and installs CheckMK agent
- ✅ **TLS encryption** - Automatic registration with encrypted communication
- ✅ **Docker monitoring** - Optional Docker container monitoring plugin
- ✅ **Idempotent** - Safe to run multiple times
- ✅ **Vault-secured** - Credentials stored in Ansible Vault
- ✅ **Selective deployment** - Deploy to all, groups, or individual hosts

## Prerequisites

1. **Ansible Vault password** configured at `../vault_pass`
2. **CheckMK server** running and accessible
3. **Inventory** configured for your LXC containers and VMs
4. **SSH access** to target hosts

## Quick Start

### 1. Add CheckMK Password to Vault

```bash
# Edit vault file
cd ../inventory/group_vars/all/
ansible-vault edit vault.yml --vault-password-file ../../../.vault_pass

# Add this line:
vault_checkmk_admin_password: "YOUR_CMK_PASSWORD"
```

### 2. Deploy to All Hosts

```bash
cd monitoring/
make deploy-all
```

### 3. Deploy to Specific Host

```bash
make deploy-host HOST=semaphore
```

## Usage

### Deploy Agents

```bash
# Deploy to all hosts (LXC + VMs)
make deploy-all

# Deploy to LXC containers only
make deploy-lxc

# Deploy to VMs only
make deploy-vms

# Deploy to specific host
make deploy-host HOST=semaphore

# Dry-run (check what would change)
make check
```

### Remove Agents

```bash
# Remove from all hosts
make remove-all

# Remove from specific host
make remove-host HOST=semaphore
```

## Configuration

### Global Settings

Edit `../inventory/group_vars/all/checkmk.yml`:

```text
checkmk_server_host: "10.40.0.14"
checkmk_server_fqdn: "checkmk.example.com"
checkmk_enable_tls: true
checkmk_enable_docker_monitoring: true
```

### Per-Host Override

In your inventory file, add host-specific variables:

```text
[lxc_containers]
semaphore ansible_host=10.40.0.12 checkmk_enable_docker_monitoring=true
gitlab ansible_host=10.40.0.15 checkmk_enable_docker_monitoring=false
```

## What Gets Deployed

1. **CheckMK Agent** - Main monitoring agent (listens on port 6556)
2. **TLS Registration** - Encrypted communication with CheckMK server
3. **Docker Plugin** (optional) - Monitors Docker containers
4. **System Service** - Systemd socket for automatic startup

## Integration with Semaphore

### Option 1: Manual Trigger

1. Go to Semaphore UI: `http://<semaphore-ip>:3000`
2. Create new template:
   - **Name**: Deploy CheckMK Agent
   - **Playbook**: `playbooks/monitoring/deploy-checkmk-agent.yml`
   - **Inventory**: Select appropriate inventory
   - **Vault Password**: Configure in Semaphore
3. Run the template

### Option 2: GitLab CI/CD Integration

Add to `.gitlab-ci.yml` in your proxmox-infra repository:

```text
deploy-monitoring-agent:
  stage: deploy
  script:
    - cd ansible/monitoring
    - make deploy-all
  when: manual
  only:
    - main
```

## Troubleshooting

### Agent Registration Fails

Check firewall rules allow traffic:

- **From**: Monitored hosts → CheckMK server
- **Port**: 8000 (agent receiver)

### TLS Certificate Issues

Add `--trust-cert` flag in `roles/checkmk_agent/defaults/main.yml`:

```text
checkmk_trust_cert: true
```

### Docker Plugin Not Working

Ensure Docker is installed and user is in docker group:

```bash
# On target host
sudo usermod -aG docker check-mk-agent
sudo systemctl restart check-mk-agent.socket
```

## Verification

After deployment, verify on target host:

```bash
# Check agent status
systemctl status check-mk-agent.socket

# Test agent locally
check_mk_agent

# Check registration
sudo cmk-agent-ctl status

# Test from CheckMK server
telnet <host-ip> 6556
```

## Directory Structure

```text
monitoring/
├── Makefile           # Deployment automation
└── README.md          # This file

../roles/checkmk_agent/
├── defaults/main.yml  # Default variables
├── tasks/
│   ├── main.yml       # Main installation tasks
│   ├── debian.yml     # Debian/Ubuntu specifics
│   ├── docker-plugin.yml  # Docker monitoring
│   └── register-tls.yml   # TLS registration
├── handlers/main.yml  # Service restart handlers
└── meta/main.yml      # Role metadata

../playbooks/monitoring/
├── deploy-checkmk-agent.yml  # Deployment playbook
└── remove-checkmk-agent.yml  # Removal playbook
```

## Next Steps

1. **Add hosts to CheckMK UI** - After deployment, add hosts in CheckMK
web interface
2. **Service discovery** - Run service discovery in CheckMK for each host
3. **Configure alerts** - Set up notification rules in CheckMK
4. **Create dashboards** - Build monitoring dashboards

## Support

For issues or questions, check:

- CheckMK logs: `docker logs checkmk`
- Agent logs: `journalctl -u check-mk-agent.socket`
- Ansible verbose: Add `-vvv` to playbook commands
