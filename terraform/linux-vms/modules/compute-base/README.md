# Compute Base Module

## Overview

This module provides shared functionality for all compute resources (LXC
containers, Linux VMs, Windows VMs). It generates unique ED25519 SSH key
pairs for each instance and stores them in the configured SSH directory.

## Features

- ✅ **Unique SSH Keys**: Generates one ED25519 key pair per hostname
- ✅ **Secure Permissions**: Private keys (0600), public keys (0644)
- ✅ **Path Expansion**: Supports `~/.ssh` notation
- ✅ **Type Agnostic**: Works with LXC, Linux VMs, Windows VMs

## Usage

```text
module "ssh_keys" {
  source = "./modules/compute-base"

  instances = {
    "dns-1"  = { type = "lxc" }
    "web-01" = { type = "vm-linux" }
    "ad-dc"  = { type = "vm-windows" }
  }

  ssh_key_directory = "~/.ssh"
}
```

## Inputs

<!-- markdownlint-disable MD013 -->

| Name                | Description                                   | Type       | Default  | Required |
| ------------------- | --------------------------------------------- | ---------- | -------- | -------- |
| `instances`         | Map of compute instances (hostname => config) | `map(any)` | n/a      | yes      |
| `ssh_key_directory` | Directory to store SSH keys                   | `string`   | `~/.ssh` | no       |

<!-- markdownlint-enable MD013 -->

## Outputs

| Name                   | Description                                      |
| ---------------------- | ------------------------------------------------ |
| `public_keys`          | Map of hostnames to SSH public keys              |
| `private_keys_openssh` | Map of hostnames to SSH private keys (sensitive) |
| `ssh_key_paths`        | Map of hostnames to key file paths               |
| `ssh_key_directory`    | Resolved SSH key directory path                  |

## Generated Files

For each instance, this module creates:

```text
~/.ssh/
├── <hostname>_id_ed25519      # Private key (0600)
└── <hostname>_id_ed25519.pub  # Public key (0644)
```

Example for hostname `pihole-1`:

```text
~/.ssh/pihole-1_id_ed25519
~/.ssh/pihole-1_id_ed25519.pub
```

## Security

- **Private keys** are marked sensitive in Terraform state
- **File permissions** are enforced (0600 for private, 0644 for public)
- **ED25519 algorithm** provides strong cryptography with small key sizes
- **Unique keys per host** limits blast radius if a key is compromised

## Requirements

- Terraform >= 1.5.0
- Providers:
  - `hashicorp/tls` ~> 4.1
  - `hashicorp/local` ~> 2.5

## License

MIT License - See root LICENSE file for details
