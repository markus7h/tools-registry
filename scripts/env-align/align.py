#!/usr/bin/env python3
"""Gleicht Claude-Code-Plugins/Marketplaces eines Systems an eine Referenz an.

Referenz = zweites System (SSH-Alias), lokale settings.json oder Manifest-JSON.
Verglichen/synchronisiert werden `enabledPlugins` (aktivierte) und
`extraKnownMarketplaces`. Additiv per Default: es werden nur fehlende
Marketplaces registriert und Plugins aktiviert — lokale Extras bleiben.
Mit --strict werden lokal aktivierte Plugins, die die Referenz nicht kennt,
deaktiviert (Voll-Spiegel).
"""
import argparse
import json
import os
import subprocess
import sys


def load_json_text(text):
    return json.loads(text)


def read_reference(ref):
    """ref -> (enabledPlugins-true-set, extraKnownMarketplaces-dict).

    Aufloesung: existierende Datei -> direkt lesen; sonst SSH-Alias
    (ssh <ref> cat ~/.claude/settings.json).
    """
    if os.path.exists(ref):
        with open(ref) as f:
            data = load_json_text(f.read())
    else:
        out = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", ref,
             "cat ~/.claude/settings.json"],
            capture_output=True, text=True,
        )
        if out.returncode != 0:
            print("ERROR: Referenz nicht lesbar (weder Datei noch SSH-Host): "
                  + ref + "\n" + out.stderr.strip(), file=sys.stderr)
            sys.exit(2)
        data = load_json_text(out.stdout)

    enabled = {k for k, v in data.get("enabledPlugins", {}).items() if v}
    markets = data.get("extraKnownMarketplaces", {})
    return enabled, markets


def diff(local, ref_enabled, ref_markets, strict):
    local_enabled = {k for k, v in local.get("enabledPlugins", {}).items() if v}
    local_markets = local.get("extraKnownMarketplaces", {})

    return {
        "plugins_enable": sorted(ref_enabled - local_enabled),
        "plugins_disable": sorted(local_enabled - ref_enabled) if strict else [],
        "markets_add": sorted(k for k in ref_markets if k not in local_markets),
    }


def apply_diff(local, ref_markets, d):
    changed = False
    ep = local.setdefault("enabledPlugins", {})
    for p in d["plugins_enable"]:
        ep[p] = True
        changed = True
    for p in d["plugins_disable"]:
        ep[p] = False
        changed = True
    if d["markets_add"]:
        km = local.setdefault("extraKnownMarketplaces", {})
        for name in d["markets_add"]:
            km[name] = ref_markets[name]
            changed = True
    return changed


def format_report(d, ref, strict):
    lines = [f"# env-align gegen Referenz: {ref}" + (" (strict)" if strict else "")]
    total = 0

    if d["markets_add"]:
        lines.append("\n## Marketplaces registrieren")
        for m in d["markets_add"]:
            lines.append(f"  + {m}")
            total += 1

    if d["plugins_enable"]:
        lines.append("\n## Plugins aktivieren")
        for p in d["plugins_enable"]:
            lines.append(f"  + {p}")
            total += 1

    if d["plugins_disable"]:
        lines.append("\n## Plugins deaktivieren (strict)")
        for p in d["plugins_disable"]:
            lines.append(f"  - {p}")
            total += 1

    if total == 0:
        lines.append("\nKeine Abweichungen — System ist angeglichen.")
    else:
        lines.append("\nHinweis: Plugin-/Marketplace-Aenderungen greifen erst nach "
                     "Claude-Code-Neustart (Auto-Install aus extraKnownMarketplaces).")
    return total, "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="check")
    ap.add_argument("--reference", required=True)
    ap.add_argument("--settings", required=True)
    ap.add_argument("--strict", default="false")
    ap.add_argument("--run-dir", required=True)
    args = ap.parse_args()

    strict = str(args.strict).lower() in ("1", "true", "yes")

    if not os.path.exists(args.settings):
        print("ERROR: lokale settings.json nicht gefunden: " + args.settings,
              file=sys.stderr)
        sys.exit(2)

    with open(args.settings) as f:
        local = json.load(f)

    ref_enabled, ref_markets = read_reference(args.reference)
    d = diff(local, ref_enabled, ref_markets, strict)
    total, report = format_report(d, args.reference, strict)
    applied = False

    if args.mode == "apply" and total > 0:
        # Backup vor Schreiben
        bak = args.settings + ".bak-envalign"
        with open(bak, "w") as f:
            json.dump(local, f, indent=2, ensure_ascii=False)
            f.write("\n")
        applied = apply_diff(local, ref_markets, d)
        if applied:
            with open(args.settings, "w") as f:
                json.dump(local, f, indent=2, ensure_ascii=False)
                f.write("\n")
            report += f"\n\n{total} Aenderung(en) angewendet. Backup: {bak}"

    report_path = os.path.join(args.run_dir, "report.txt")
    with open(report_path, "w") as f:
        f.write(report + "\n")
    with open(os.path.join(args.run_dir, "outputs.json"), "w") as f:
        json.dump({"report": report_path, "applied": applied, "changes": total}, f)

    print(report)


if __name__ == "__main__":
    main()
