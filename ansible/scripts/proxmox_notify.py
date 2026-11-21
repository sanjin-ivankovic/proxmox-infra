"""Converge a webhook notification target and its matcher on PVE or PBS.

Both products share the proxmox-notify schema and API, under
cluster/notifications (PVE) and config/notifications (PBS). The declared
target and matcher come from ansible/configs/notifications.yml.

Header values, the body and secret values travel base64-encoded as
"name=<name>,value=<base64>" property strings. The API never returns secret
values, so the token is only sent when the target is created or when
--rotate-token is given; the doctor checks that the secret name exists.
"""

from __future__ import annotations

import base64
import binascii
import os
from pathlib import Path
from typing import Any, Callable

CONFIG = Path(__file__).resolve().parent.parent / "configs" / "notifications.yml"
TOKEN_ENV = "NTFY_BACKUPS_TOKEN"

Call = Callable[[str, str, "dict[str, Any] | None"], Any]
Change = Callable[[str, str, str, "dict[str, Any] | None"], None]


def _b64(text: str) -> str:
    return base64.b64encode(text.encode()).decode()


def _unb64(text: str) -> str:
    try:
        return base64.b64decode(text, validate=True).decode()
    except (binascii.Error, UnicodeDecodeError):
        return text


def _pairs(items: Any) -> dict[str, str]:
    """name -> decoded value from either property strings or objects."""
    out: dict[str, str] = {}
    for item in items or []:
        if isinstance(item, dict):
            name, value = item.get("name"), item.get("value", "")
        else:
            fields = dict(part.split("=", 1) for part in str(item).split(",") if "=" in part)
            name, value = fields.get("name"), fields.get("value", "")
        if name:
            out[name] = _unb64(value) if value else ""
    return out


def _endpoint_body(want: dict[str, Any]) -> dict[str, Any]:
    body: dict[str, Any] = {
        "url": want["url"],
        "method": want.get("method", "post"),
        "header": [f"name={k},value={_b64(v)}" for k, v in sorted(want.get("header", {}).items())],
    }
    if want.get("body"):
        body["body"] = _b64(want["body"])
    if want.get("comment"):
        body["comment"] = want["comment"]
    return body


def _secret(token: str) -> list[str]:
    return [f"name=token,value={_b64(token)}"]


def _endpoint_drift(want: dict[str, Any], have: dict[str, Any]) -> list[str]:
    drift = []
    for key in ("url", "method", "comment"):
        if (want.get(key) or ("post" if key == "method" else None)) != (have.get(key) or None):
            drift.append(f"{key}: {have.get(key)!r} -> {want.get(key)!r}")
    if want.get("header", {}) != _pairs(have.get("header")):
        drift.append("header differs")
    if (want.get("body") or "") != _unb64(have.get("body") or ""):
        drift.append("body differs")
    if "token" not in _pairs(have.get("secret")):
        drift.append("secret 'token' missing")
    return drift


def _as_list(value: Any) -> list[str]:
    if value in (None, ""):
        return []
    return sorted(value if isinstance(value, list) else str(value).split(","))


def _matcher_drift(want: dict[str, Any], have: dict[str, Any]) -> list[str]:
    drift = []
    for key in ("match-severity", "target"):
        if _as_list(want.get(key)) != _as_list(have.get(key)):
            drift.append(f"{key}: {_as_list(have.get(key))} -> {_as_list(want.get(key))}")
    if (want.get("comment") or None) != (have.get("comment") or None):
        drift.append(f"comment: {have.get('comment')!r} -> {want.get('comment')!r}")
    if have.get("disable"):
        drift.append("disable: true -> false")
    return drift


def load(load_yaml: Callable[[Path], dict[str, Any]]) -> dict[str, Any]:
    cfg = load_yaml(CONFIG)
    if cfg["matcher"]["name"] == cfg["endpoint"]["name"]:
        raise RuntimeError("matcher and endpoint need different names: PVE and PBS "
                           "keep targets and matchers in one name space")
    cfg["matcher"]["target"] = [cfg["endpoint"]["name"]]
    return cfg


def sync(call: Call, change: Change, base: str, cfg: dict[str, Any], rotate: bool,
         dry_run: bool) -> None:
    """Converge the declared webhook target, then the matcher that uses it."""
    ep, matcher = cfg["endpoint"], cfg["matcher"]
    name = ep["name"]
    token = os.environ.get(TOKEN_ENV, "")

    def need_token(why: str) -> list[str]:
        if not token and not dry_run:
            raise RuntimeError(f"{TOKEN_ENV} must be set to {why}")
        return _secret(token)

    live = {e["name"]: e for e in call("GET", f"{base}/endpoints/webhook", None) or []}
    if name not in live:
        change(f"+ webhook {name} -> {ep['url']}", "POST", f"{base}/endpoints/webhook",
               {"name": name, **_endpoint_body(ep),
                "secret": need_token(f"create webhook target {name}")})
    else:
        have = call("GET", f"{base}/endpoints/webhook/{name}", None) or {}
        drift = _endpoint_drift(ep, have)
        if drift or rotate:
            body = _endpoint_body(ep)
            if rotate or "secret 'token' missing" in drift:
                body["secret"] = need_token(f"set the secret of {name}")
            label = "; ".join(drift) or "token rotated"
            change(f"~ webhook {name}: {label}", "PUT", f"{base}/endpoints/webhook/{name}", body)

    mname = matcher["name"]
    want = {k: v for k, v in matcher.items() if k != "name"}
    live_m = {m["name"]: m for m in call("GET", f"{base}/matchers", None) or []}
    if mname not in live_m:
        change(f"+ matcher {mname} -> {', '.join(want['target'])}", "POST", f"{base}/matchers",
               {"name": mname, **want})
        return
    have_m = call("GET", f"{base}/matchers/{mname}", None) or {}
    drift = _matcher_drift(want, have_m)
    if drift:
        body = dict(want)
        if have_m.get("disable"):
            body["disable"] = False
        change(f"~ matcher {mname}: {'; '.join(drift)}", "PUT", f"{base}/matchers/{mname}", body)
