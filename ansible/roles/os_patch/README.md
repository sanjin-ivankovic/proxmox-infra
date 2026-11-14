# os_patch

Gated OS patching for a **single host**: preflight → snapshot → apt → reboot →
verify → report.

Fleet concerns — HA pair ordering, waves, exclusions — belong to the calling
playbook (`playbooks/hosts/patch.yml`), not here.

## Why not `common_system`

`common_system` also runs `apt dist-upgrade`, but its apt task is entangled with
package installs and OS version asserts, which is why `KOMODO_UPGRADE_SKIP_TAGS`
exists to skip it. This role has `dependencies: []` so patching never triggers a
provisioning side effect.

## Safety defaults

- `os_patch_reboot_allowed: false` — a reboot is opt-in per run.
- `os_patch_snapshot_enabled: false` — snapshots need the Proxmox API options.
- Preflight refuses to patch a host with failed units or under
  `os_patch_min_free_disk_mb` free on `/`.
- Verify **asserts**; a failure stops the calling wave before it reaches an HA
  partner. Failed units are compared against the pre-patch set, so it fires on
  units patching broke rather than ones already failing.

## Key variables

| Variable | Default | Description |
| --- | --- | --- |
| `os_patch_reboot_allowed` | `false` | Permit a reboot when required |
| `os_patch_snapshot_enabled` | `false` | Snapshot before patching |
| `os_patch_min_free_disk_mb` | `512` | Preflight disk gate |
| `os_patch_docker_settle_timeout` | `180` | Container recovery wait |
| `os_patch_report_dir` | `/var/log/os-patch` | Run reports |

Snapshots additionally need `vmid` (emitted by the dynamic inventory) plus
`os_patch_proxmox_api_url`, `_token_id` and `_token_secret`.

## Patching semaphore itself

`semaphore` is excluded from the automated waves: it runs the automation, so a
reboot kills the task mid-flight and leaves the fleet half-patched with no
report. It is also in no `patch_*` group, so `make -C ansible patch-hosts
HOST=semaphore` resolves to zero hosts and patches nothing. Patch the
Semaphore LXC by hand over SSH (`apt update && apt full-upgrade`, reboot
when no task is running) until a dedicated play exists.

Patching stays on the installed Debian release; a release upgrade is
separate manual work.
