#!/usr/bin/env python3
"""Vergleicht und synchronisiert Claude Code settings.json mit Template."""
import argparse
import json
import os
import sys


def load_json(path):
    with open(path) as f:
        return json.load(f)


def diff_settings(local, tmpl):
    diffs = {"general": [], "allow_missing": [], "deny_missing": [], "hooks_missing": []}

    for key, expected in tmpl.get("general", {}).items():
        actual = local.get(key)
        if actual != expected:
            diffs["general"].append({"key": key, "actual": actual, "expected": expected})

    local_allow = set(local.get("permissions", {}).get("allow", []))
    for p in tmpl.get("permissions_allow_portable", []):
        if p in local_allow:
            continue
        if any(a.endswith("*") and p.startswith(a[:-1]) for a in local_allow):
            continue
        diffs["allow_missing"].append(p)

    local_deny = set(local.get("permissions", {}).get("deny", []))
    for p in tmpl.get("permissions_deny", []):
        if p not in local_deny:
            diffs["deny_missing"].append(p)

    local_hooks = local.get("hooks", {})
    for event in tmpl.get("hooks", {}):
        if event not in local_hooks:
            diffs["hooks_missing"].append(event)

    return diffs


def apply_diffs(local, tmpl, diffs):
    changed = False

    for d in diffs["general"]:
        local[d["key"]] = d["expected"]
        changed = True

    if diffs["allow_missing"]:
        local.setdefault("permissions", {}).setdefault("allow", [])
        local["permissions"]["allow"].extend(diffs["allow_missing"])
        changed = True

    if diffs["deny_missing"]:
        local.setdefault("permissions", {}).setdefault("deny", [])
        local["permissions"]["deny"].extend(diffs["deny_missing"])
        changed = True

    return changed


def format_report(diffs):
    lines = []
    total = 0

    if diffs["general"]:
        lines.append("## General Settings")
        for d in diffs["general"]:
            lines.append(f"  {d['key']}: {d['actual']} -> {d['expected']}")
            total += 1

    if diffs["allow_missing"]:
        lines.append("## Fehlende Allow-Permissions")
        for p in diffs["allow_missing"]:
            lines.append(f"  + {p}")
            total += 1

    if diffs["deny_missing"]:
        lines.append("## Fehlende Deny-Permissions")
        for p in diffs["deny_missing"]:
            lines.append(f"  + {p}")
            total += 1

    if diffs["hooks_missing"]:
        lines.append("## Fehlende Hooks")
        for h in diffs["hooks_missing"]:
            lines.append(f"  + {h}")
            total += 1
        lines.append("  (Hooks werden von 'apply' NICHT automatisch ergaenzt — bitte manuell in settings.json eintragen.)")

    if not lines:
        lines.append("Keine Abweichungen — settings.json ist aktuell.")

    return total, "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", default="check")
    parser.add_argument("--settings", required=True)
    parser.add_argument("--template", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()

    if not os.path.exists(args.template):
        print("ERROR: Template nicht gefunden: " + args.template, file=sys.stderr)
        sys.exit(2)
    if not os.path.exists(args.settings):
        print("ERROR: Settings nicht gefunden: " + args.settings, file=sys.stderr)
        sys.exit(2)

    local = load_json(args.settings)
    tmpl = load_json(args.template)
    diffs = diff_settings(local, tmpl)
    total, report = format_report(diffs)
    applied = False

    if args.mode == "apply" and total > 0:
        applied = apply_diffs(local, tmpl, diffs)
        if applied:
            with open(args.settings, "w") as f:
                json.dump(local, f, indent=2, ensure_ascii=False)
                f.write("\n")
            report += f"\n\n{total} Aenderung(en) angewendet auf {args.settings}"

    report_path = os.path.join(args.run_dir, "report.txt")
    with open(report_path, "w") as f:
        f.write(report + "\n")

    with open(os.path.join(args.run_dir, "outputs.json"), "w") as f:
        json.dump({"report": report_path, "applied": applied}, f)

    print(report)


if __name__ == "__main__":
    main()
