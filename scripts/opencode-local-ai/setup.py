#!/usr/bin/env python3
"""Traegt den LiteLLM-Provider (Gateway auf mystorage) in eine opencode.json ein.

Modelle = die vier Gruppen, die der Virtual Key "litellm opencode key" freigibt
(llm-stack/rotate-keys.py). Weitere, schon vorhandene Modelle unter provider.litellm bleiben.

Key: aus mykeyvault (run.sh setzt OPENCODE_LITELLM_KEY via `ai-rem run --secret`) ->
<ziel-dir>/secrets/litellm-api-key (0600), Referenz per {file:...}. Nie Klartext in der opencode.json.
"""
import argparse
import difflib
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request

SECRET_NAME = "litellm-api-key"
PLACEHOLDERS = {"", "DEIN_KEY", "HIER_DER_ECHTE_KEY"}
# Eigener Env-Name: ein LITELLM_API_KEY aus der Shell (anderer Key) darf nicht durchrutschen.
KEY_ENV = "OPENCODE_LITELLM_KEY"
MODELS = {
    "private-general": ("Private General (lokal, nie Cloud)", 262144),
    "private-coder": ("Private Coder (lokal mit Thinking, nie Cloud)", 262144),
    "cloud-general": ("Cloud General (gpt-oss-120b via OpenRouter)", 131072),
    "cloud-coder": ("Cloud Coder (qwen3-coder-next via OpenRouter)", 262144),
}


def load(path):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return {"$schema": "https://opencode.ai/config.json"}
    with open(path) as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            sys.exit(f"FEHLER: {path} ist kein gueltiges JSON ({e}) - bitte erst reparieren.")


def provider_block(old, base_url, secret_path):
    models = dict((old or {}).get("models") or {})
    for mid, (name, ctx) in MODELS.items():
        models[mid] = {"name": name, "limit": {"context": ctx, "output": 32768}}
    return {
        "npm": "@ai-sdk/openai-compatible",
        "name": "LiteLLM (mystorage)",
        "options": {"baseURL": base_url, "apiKey": "{file:%s}" % secret_path},
        "models": models,
    }


def check_key(base_url, key):
    if not key:
        return "missing"
    req = urllib.request.Request(base_url.rstrip("/") + "/models",
                                 headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return "ok" if r.status == 200 else "unknown"
    except urllib.error.HTTPError as e:
        return "rejected" if e.code in (401, 403) else "unknown"
    except Exception:
        return "unreachable"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="check", choices=["check", "apply"])
    ap.add_argument("--set-default", default="false")
    ap.add_argument("--target", required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--vault-item", default="litellm opencode key")
    ap.add_argument("--run-dir", required=True)
    a = ap.parse_args()

    target = os.path.expanduser(a.target)
    secret_path = os.path.join(os.path.dirname(target), "secrets", SECRET_NAME)
    set_default = a.set_default.strip().lower() in ("1", "true", "yes", "ja")
    report_path = os.path.join(a.run_dir, "report.txt")
    lines = []

    cfg = load(target)
    new = json.loads(json.dumps(cfg))
    if a.model not in MODELS:
        sys.exit(f"FEHLER: model={a.model} - erlaubt sind {', '.join(MODELS)} (Whitelist des opencode-Keys).")
    prov = new.setdefault("provider", {})
    prov["litellm"] = provider_block(prov.get("litellm"), a.base_url, secret_path)
    if set_default:
        new["model"] = f"litellm/{a.model}"

    old_txt = json.dumps(cfg, indent=2, ensure_ascii=False).splitlines()
    new_txt = json.dumps(new, indent=2, ensure_ascii=False).splitlines()
    diff = list(difflib.unified_diff(old_txt, new_txt, target, target + " (neu)", lineterm=""))
    cfg_changed = bool(diff)

    # Key: Env hat Vorrang, sonst vorhandene Secret-Datei
    env_key = os.environ.get(KEY_ENV, "").strip()
    if env_key in PLACEHOLDERS:
        env_key = ""
    file_key = ""
    if os.path.exists(secret_path):
        with open(secret_path) as f:
            file_key = f.read().strip()
    key = env_key or file_key
    secret_changed = bool(env_key) and env_key != file_key

    lines.append(f"Ziel:     {target}")
    lines.append(f"Provider: litellm -> {a.base_url}  Modelle: {', '.join(MODELS)}"
                 + (f"  Default: litellm/{a.model}" if set_default else ""))
    lines.append(f"Secret:   {secret_path} "
                 + (f"(wird aus Vault-Item '{a.vault_item}' aktualisiert)" if secret_changed
                    else "(vorhanden)" if file_key else "(FEHLT)"))
    lines.append("")
    lines.append("\n".join(diff) if diff else "Config: keine Aenderung noetig.")

    applied = False
    if a.mode == "apply":
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if cfg_changed:
            if os.path.exists(target):
                bak = f"{target}.bak-{time.strftime('%Y%m%d%H%M%S')}"
                shutil.copy2(target, bak)
                lines.append(f"\nBackup:   {bak}")
            with open(target, "w") as f:
                json.dump(new, f, indent=2, ensure_ascii=False)
                f.write("\n")
        if secret_changed:
            os.makedirs(os.path.dirname(secret_path), mode=0o700, exist_ok=True)
            fd = os.open(secret_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as f:
                f.write(env_key + "\n")
            os.chmod(secret_path, 0o600)
        applied = cfg_changed or secret_changed
        lines.append("-> geschrieben" if applied else "-> nichts zu schreiben")

    key_status = check_key(a.base_url, key)
    lines.append("")
    lines.append({
        "ok": "Key-Check: OK - LiteLLM erreichbar, Key gueltig.",
        "rejected": "Key-Check: LiteLLM erreichbar, Key ABGELEHNT (401/403).",
        "missing": f"Key-Check: kein Key - Vault-Item '{a.vault_item}' in mykeyvault anlegen "
                   "(oder vault_item=<name> angeben) und erneut mode=apply ausfuehren. "
                   "Braucht ai-rem mit Admin-Geraete-Token (`ai-rem install --pair`).",
        "unreachable": f"Key-Check: {a.base_url} nicht erreichbar (Netz/VPN?).",
        "unknown": "Key-Check: unerwartete Antwort vom LiteLLM.",
    }[key_status])
    if applied:
        lines.append("Danach: `opencode service restart` (falls Hintergrund-Dienst), "
                     "dann in opencode /models -> " + a.model)
    elif a.mode == "check" and (cfg_changed or secret_changed):
        lines.append("Hinweis: mode=apply ausfuehren, um die Aenderungen zu schreiben.")

    report = "\n".join(lines) + "\n"
    with open(report_path, "w") as f:
        f.write(report)
    with open(os.path.join(a.run_dir, "outputs.json"), "w") as f:
        json.dump({"report": report_path,
                   "changed": cfg_changed or secret_changed,
                   "applied": applied,
                   "key_status": key_status}, f)
    print(f"opencode-local-ai (mode={a.mode})")
    print(report, end="")


if __name__ == "__main__":
    main()
