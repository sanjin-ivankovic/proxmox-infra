# proxmox-infra Documentation

Start here, then follow the link for what you need.

<!-- markdownlint-disable MD013 MD060 -->
| Document | What it covers |
| --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The three-phase IaC model (Terraform provisions, cloud-init bootstraps, Ansible configures) and how the layers fit together. |
| [ANSIBLE.md](ANSIBLE.md) | The Ansible layer: dynamic inventory, the Vault → `host_vars` → Komodo periphery secret flow, the Komodo operator runbook, troubleshooting, and the Make targets. |
| [TERRAFORM.md](TERRAFORM.md) | The Terraform layer's Make targets and provisioning workflow. |
<!-- markdownlint-enable MD013 MD060 -->

`docs/ANSIBLE.md` consolidates what used to live under `ansible/docs/`, and
`docs/TERRAFORM.md` what used to live under `terraform/docs/`. Per-area quick
starts remain in their own READMEs: [`ansible/README.md`](../ansible/README.md),
[`terraform/README.md`](../terraform/README.md), and
[`services/README.md`](../services/README.md).
