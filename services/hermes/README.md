# Hermes Agent (NousResearch) — Telegram gateway

Single-container deployment of the [Hermes Agent][hermes] on the `hermes` LXC
(10.10.0.17), run in **gateway mode** as a long-running Telegram bot. The model
provider is the homelab LiteLLM proxy (`https://litellm.example.com`, model
`gpt-5.4`) via Hermes's OpenAI-compatible "custom" provider.

Migrated from a native uv/systemd install (the retired `hermes_agent` Ansible
role) to this Komodo-deployed container.

[hermes]: https://hermes-agent.nousresearch.com/docs/user-guide/docker

## What Komodo deploys

Komodo Core reconciles the `hermes` stack in
[`komodo/stacks.toml`](../../komodo/stacks.toml) by asking the periphery agent
on the host to run `docker compose up -d` against
[`docker-compose.yml`](docker-compose.yml). Stack env values come from
[`komodo/variables.toml`](../../komodo/variables.toml) (non-secret pins) and the
host's periphery `[secrets]` block — see
[`host_vars/hermes.yml`](../../ansible/inventory/host_vars/hermes.yml) and
[`../../docs/ANSIBLE.md#secrets`](../../docs/ANSIBLE.md#secrets).

## Config and secrets

- [`config.yaml`](config.yaml) is committed and **non-secret** (provider, model,
  agent + gateway settings). It is bind-mounted read-only to
  `/opt/data/config.yaml`. The LiteLLM api_key is **not** in it — it is injected
  via the `OPENAI_API_KEY` env (the `vault_hermes_litellm_api_key` periphery
  secret). `base_url` has **no** `/v1`; Hermes appends the OpenAI path itself.
- `TELEGRAM_BOT_TOKEN` is the `vault_hermes_telegram_bot_token` periphery
  secret; `TELEGRAM_ALLOWED_USERS` is a non-secret allowlist (the gateway
  denies everyone else by default).
- Data dir: `${APPDATA_DIR}/hermes` (= `/srv/docker/appdata/hermes`) →
  `/opt/data`. The container runs as the non-root `hermes` user; `PUID`/`PGID`
  are set to `1000:1000`, so the host data dir must be owned by `1000:1000`.

> If the `custom` provider does not pick up its key from `OPENAI_API_KEY`, the
> fallback is to render `config.yaml` on the host (with the key from Vault, mode
> 0600) and drop the read-only bind. Confirmed working = a Telegram reply.

## Ports and auth

- **8642** (OpenAI-compatible gateway API/health) is **not** published — a
  telegram-only gateway does not need it.
- **9119** (web dashboard) **is** published. The dashboard authenticates
  callers itself via the image's built-in basic_auth
  (`HERMES_DASHBOARD_BASIC_AUTH_{USERNAME,PASSWORD_HASH}`) — that is the sole
  gate. The `hermes.example.com` route in argo-apps
  (`apps/infra/external-services`) carries **no** SSO middleware, and the host
  is LAN-only (not on the cloudflared tunnel). Do **not** expose 9119 beyond
  the LAN; the dashboard reads/writes `.env` and the credential pool.

## Verify

```bash
docker logs hermes          # s6 supervises `gateway run`; provider init succeeds
docker port hermes          # 9119 published
```

A clean start shows the gateway connecting to Telegram. Send a message from an
allowed user (see `TELEGRAM_ALLOWED_USERS`) and confirm a reply. The dashboard
is reachable at `https://hermes.example.com` after a basic_auth sign-in.
