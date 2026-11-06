# common_authorized_keys

Declarative SSH `authorized_keys` management for a host service account.

## Why this role exists

Neither existing mechanism can add a key to an already-provisioned host:

- `common_users` copies root's `authorized_keys` once, at bootstrap
  (`remote_src`), so it cannot express a key list.
- Terraform's `deploy_public_keys` sits inside `initialization`, which the LXC
  module (`terraform/lxc/modules/lxc-instance/main.tf`) lists in
  `lifecycle.ignore_changes` (alongside `prevent_destroy = true`). Adding a key
  there produces **no diff** for existing containers — it only affects newly
  created ones.

## Variables

| Variable | Default | Description |
| --- | --- | --- |
| `common_authorized_keys_user` | `{{ user }}` | Managed account |
| `common_authorized_keys_keys` | `[]` | List of `{comment, key, state}` |
| `common_authorized_keys_exclusive` | `false` | Remove keys not listed |

## Usage

```yaml
- role: common_authorized_keys
  vars:
    common_authorized_keys_keys:
      - comment: semaphore-automation
        key: "{{ semaphore_automation_public_key }}"
```

## Notes

`exclusive` is **not loop-aware** — under a loop it applies per iteration, so
each key would wipe the previous one and only the last would survive. The role
therefore has two mutually exclusive task paths: a loop for the normal case, and
a single call passing every key newline-joined when `exclusive` is true.

`exclusive: true` with nothing to authorize would strip every key from the host.
Since `common_ssh` has already disabled password auth and root login, that
leaves the Proxmox console as the only way back in — so the role asserts against
it before touching anything.

Keys with `state: absent` are excluded from the exclusive batch; `state`
defaults to `present` when omitted.
