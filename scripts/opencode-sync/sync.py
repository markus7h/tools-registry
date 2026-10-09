#!/usr/bin/env python3
"""Uebersetzt Plugins des tools-registry-Marketplace in opencode-MCP-Eintraege.

opencode kennt keinen Plugin-Marketplace; dieses Script liest marketplace.json +
plugins/<name>/.claude-plugin/plugin.json und schreibt die mcpServers als
"mcp"-Eintraege in eine opencode.json (global oder projekt-lokal).

Werte fuer ${user_config.X} kommen (in dieser Reihenfolge) aus:
  1. Werte-Datei (default ~/.config/opencode/tools-registry.json)
  2. Claude Code pluginConfigs["<name>@tools-registry"] in ~/.claude/settings.json
  3. userConfig-Default im plugin.json
Secrets landen nie im Klartext in opencode.json: literale Werte geheimer Felder
werden in eine chmod-600-Datei geschrieben und per {file:...} referenziert.
"""
import argparse
import json
import os
import re
import shutil
import sys
import time
import urllib.request

MARKETPLACE = "tools-registry"
DEFAULT_SOURCE = "https://raw.githubusercontent.com/markus7h/tools-registry/main"
# Von `ai-rem install --client opencode` verwaltet (setzt u.a. AI_REM_CLIENT=opencode).
MANAGED_ELSEWHERE = {"ai-rem": "ai-rem install", "mykeyvault": "ai-rem install"}
SECRET_NAME = re.compile(r"token|secret|password|passwd|api_?key", re.I)
PLACEHOLDER = re.compile(r"\$\{user_config\.([A-Za-z0-9_]+)\}")
REFERENCE = re.compile(r"^\{(file|env):.+\}$")


def read_source(source, rel):
    if re.match(r"^https?://", source):
        with urllib.request.urlopen(f"{source.rstrip('/')}/{rel}", timeout=15) as r:
            return json.loads(r.read().decode("utf-8"))
    with open(os.path.join(os.path.expanduser(source), rel)) as f:
        return json.load(f)


def load_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return json.load(f)


def claude_plugin_values(name):
    settings = load_json(os.path.expanduser("~/.claude/settings.json"), {})
    cfg = settings.get("pluginConfigs", {}).get(f"{name}@{MARKETPLACE}", {})
    return cfg.get("options", cfg) if isinstance(cfg, dict) else {}


def is_secret(field, spec):
    return bool(spec.get("sensitive")) or bool(SECRET_NAME.search(field))


def secret_ref(secrets_dir, plugin, field, value, apply):
    """Literal-Secret -> chmod-600-Datei, Rueckgabe {file:...}-Referenz."""
    path = os.path.join(secrets_dir, f"{plugin}.{field}")
    if apply:
        os.makedirs(secrets_dir, mode=0o700, exist_ok=True)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(value)
        os.chmod(path, 0o600)
    return "{file:" + path + "}"


def resolve_values(name, manifest, user_values, secrets_dir, apply, notes):
    claude = claude_plugin_values(name)
    resolved, missing = {}, []
    for field, spec in (manifest.get("userConfig") or {}).items():
        value = user_values.get(field)
        origin = "Werte-Datei"
        if value in (None, ""):
            value, origin = claude.get(field), "Claude-Code-pluginConfigs"
        if value in (None, ""):
            value, origin = spec.get("default"), "Default"
        if value in (None, ""):
            missing.append(field)
            continue
        value = str(value)
        if is_secret(field, spec) and not REFERENCE.match(value):
            value = secret_ref(secrets_dir, name, field, value, apply)
            notes.append(f"{name}.{field}: Secret ({origin}) -> {value}")
        elif origin == "Default" and value.startswith("/home/") and sys.platform == "darwin":
            notes.append(f"{name}.{field}: Linux-Default {value} auf macOS — in der Werte-Datei ueberschreiben")
        resolved[field] = value
    return resolved, missing


def substitute(obj, values):
    if isinstance(obj, str):
        unknown = [m for m in PLACEHOLDER.findall(obj) if m not in values]
        if unknown:
            raise KeyError(unknown[0])
        if "${" in PLACEHOLDER.sub("", obj):
            raise ValueError(f"nicht unterstuetzter Platzhalter in {obj!r}")
        return PLACEHOLDER.sub(lambda m: values[m.group(1)], obj)
    if isinstance(obj, list):
        return [substitute(x, values) for x in obj]
    if isinstance(obj, dict):
        return {k: substitute(v, values) for k, v in obj.items()}
    return obj


def to_opencode(server, extra_env):
    """Claude-mcpServers-Eintrag -> opencode-mcp-Eintrag."""
    kind = server.get("type", "stdio")
    if kind in ("http", "sse"):
        entry = {"type": "remote", "url": server["url"]}
        if server.get("headers"):
            entry["headers"] = server["headers"]
    else:
        cmd = server["command"]
        # Desktop-App startet ohne Login-Shell-PATH -> Kommando absolut aufloesen.
        if not os.path.isabs(cmd):
            cmd = shutil.which(cmd) or cmd
        entry = {"type": "local", "command": [cmd, *server.get("args", [])]}
        env = {**server.get("env", {}), **extra_env}
        if env:
            entry["environment"] = env
    entry["enabled"] = True
    return entry


def check_paths(entry, notes, name):
    for arg in entry.get("command", [])[1:]:
        if arg.startswith("/") and not os.path.exists(arg):
            notes.append(f"{name}: Pfad existiert nicht: {arg}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", default="check")
    p.add_argument("--plugins", default="")
    p.add_argument("--target", required=True)
    p.add_argument("--values", required=True)
    p.add_argument("--source", default=DEFAULT_SOURCE)
    p.add_argument("--run-dir", required=True)
    a = p.parse_args()

    if a.mode not in ("check", "apply"):
        print(f"ERROR: mode muss check oder apply sein, nicht {a.mode!r}", file=sys.stderr)
        sys.exit(2)
    apply = a.mode == "apply"
    target = os.path.expanduser(a.target)
    values_cfg = load_json(os.path.expanduser(a.values), {}).get("plugins", {})
    secrets_dir = os.path.join(os.path.dirname(target), "secrets")

    catalog = {pl["name"]: pl for pl in read_source(a.source, ".claude-plugin/marketplace.json")["plugins"]}
    if a.plugins.strip() == "all":
        wanted = [n for n in catalog if n not in MANAGED_ELSEWHERE]
    elif a.plugins.strip():
        wanted = [n.strip() for n in a.plugins.split(",") if n.strip()]
    else:
        wanted = list(values_cfg)
    if not wanted:
        print(f"ERROR: keine Plugins gewaehlt — plugins=<a,b> oder 'all' angeben oder "
              f"{a.values} anlegen. Katalog: {', '.join(catalog)}", file=sys.stderr)
        sys.exit(2)

    try:
        config = load_json(target, {"$schema": "https://opencode.ai/config.json"})
    except json.JSONDecodeError as e:
        print(f"ERROR: {target} ist kein reines JSON ({e}) — Kommentare (JSONC) werden nicht unterstuetzt",
              file=sys.stderr)
        sys.exit(2)
    mcp = config.setdefault("mcp", {})
    # opencode 2.x: mcp.servers.<name> mit "disabled"; 1.x (und von 2.x migriert):
    # flach mcp.<name> mit "enabled". Das Layout der Ziel-Datei gewinnt.
    v2 = isinstance(mcp.get("servers"), dict)
    servers = mcp["servers"] if v2 else mcp

    lines, notes, changes, skipped = [], [], [], []
    for name in wanted:
        if name not in catalog:
            skipped.append(f"{name}: nicht im Katalog")
            continue
        if name in MANAGED_ELSEWHERE and a.plugins.strip() != name:
            skipped.append(f"{name}: wird von `{MANAGED_ELSEWHERE[name]}` verwaltet")
            continue
        manifest = read_source(a.source, f"{catalog[name]['source'].lstrip('./')}/.claude-plugin/plugin.json")
        user_values = dict(values_cfg.get(name, {}))
        extra_env = user_values.pop("_environment", {})
        values, missing = resolve_values(name, manifest, user_values, secrets_dir, apply, notes)
        if missing:
            skipped.append(f"{name}: Werte fehlen: {', '.join(missing)} (in {a.values} unter plugins.{name} setzen)")
            continue
        for server_name, server in (manifest.get("mcpServers") or {}).items():
            try:
                entry = to_opencode(substitute(server, values), extra_env)
            except (KeyError, ValueError) as e:
                skipped.append(f"{name}: {e}")
                continue
            check_paths(entry, notes, server_name)
            current = servers.get(server_name)
            flag = "disabled" if v2 else "enabled"
            if v2:
                del entry["enabled"]
                if server_name in mcp:
                    notes.append(f"{server_name}: flacher Alt-Eintrag wird nach mcp.servers verschoben")
                    current = None
            if current is not None and flag in current:
                entry[flag] = current[flag]
            if current == entry:
                lines.append(f"  = {server_name} (unveraendert)")
                continue
            lines.append(f"  {'~' if current else '+'} {server_name}: {json.dumps(entry, ensure_ascii=False)}")
            changes.append((server_name, entry))

    report = [f"Ziel: {target}", f"Quelle: {a.source}", ""] + (lines or ["  (keine Eintraege)"])
    if skipped:
        report += ["", "Uebersprungen:"] + [f"  - {s}" for s in skipped]
    if notes:
        report += ["", "Hinweise:"] + [f"  - {n}" for n in notes]

    applied = False
    if apply and changes:
        if os.path.exists(target):
            shutil.copy2(target, f"{target}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
        for server_name, entry in changes:
            if v2:
                mcp.pop(server_name, None)
            servers[server_name] = entry
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w") as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
            f.write("\n")
        applied = True
        report += ["", f"{len(changes)} Eintrag/Eintraege geschrieben (Backup daneben). opencode neu starten."]
    elif changes:
        report += ["", f"{len(changes)} Aenderung(en) offen — mode=apply schreibt sie."]

    text = "\n".join(report)
    report_path = os.path.join(a.run_dir, "report.txt")
    with open(report_path, "w") as f:
        f.write(text + "\n")
    with open(os.path.join(a.run_dir, "outputs.json"), "w") as f:
        json.dump({"report": report_path, "changed": bool(changes), "applied": applied}, f)
    print(text)


if __name__ == "__main__":
    main()
