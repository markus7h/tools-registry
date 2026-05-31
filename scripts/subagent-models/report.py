#!/usr/bin/env python3
"""Welche Modelle haben die delegierten Subagenten genutzt?

Liest die Subagent-Transcripts unter
  ~/.claude/projects/<proj>/<session>/subagents/agent-*.jsonl
Jede Assistant-Zeile traegt message.model, message.usage.output_tokens und
attributionAgent (Agent-Typ). Eine Datei = ein Subagent-Lauf. Aggregiert pro
(Agent-Typ x Modell-Familie): Laeufe, Turns, Output-Tokens.

scope=all  : alle Sessions.
scope=session: nur die juengste Session (neuestes <uuid>.jsonl by mtime).
"""
import argparse
import glob
import json
import os
from collections import Counter


def family(model: str) -> str:
    m = (model or "").lower()
    if "haiku" in m:
        return "haiku"
    if "sonnet" in m:
        return "sonnet"
    if "opus" in m:
        return "opus"
    return model or "?"


def subagent_files(projects_dir: str, scope: str) -> list[str]:
    if scope == "session":
        mains = glob.glob(os.path.join(projects_dir, "*", "*.jsonl"))
        if not mains:
            return []
        newest = max(mains, key=lambda p: os.path.getmtime(p))
        session_dir = newest[:-len(".jsonl")]  # <proj>/<uuid>
        return sorted(glob.glob(os.path.join(session_dir, "subagents", "*.jsonl")))
    return sorted(glob.glob(os.path.join(projects_dir, "*", "*", "subagents", "*.jsonl")))


def collect(files: list[str]):
    runs = Counter()    # (agent, fam) -> # Dateien
    turns = Counter()   # (agent, fam) -> # Assistant-Turns
    tokens = Counter()  # (agent, fam) -> Output-Tokens
    for f in files:
        first_key = None
        try:
            fh = open(f, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if o.get("type") != "assistant":
                    continue
                msg = o.get("message", {}) or {}
                key = (o.get("attributionAgent") or "?", family(msg.get("model")))
                turns[key] += 1
                usage = msg.get("usage", {}) or {}
                tokens[key] += usage.get("output_tokens", 0) or 0
                if first_key is None:
                    first_key = key
        if first_key is not None:
            runs[first_key] += 1
    return runs, turns, tokens


def build_report(runs, turns, tokens, scope, nfiles) -> str:
    lines = [f"subagent-models  (scope={scope}, {nfiles} Subagent-Laeufe)", ""]
    if not runs:
        lines.append("Keine Subagent-Transcripts gefunden.")
        return "\n".join(lines)
    lines.append(f"{'Agent-Typ':<18} {'Modell':<8} {'Laeufe':>7} {'Turns':>7} {'Out-Tok':>10}")
    lines.append("-" * 54)
    for key in sorted(runs, key=lambda k: (-runs[k], -turns[k])):
        agent, fam = key
        lines.append(f"{agent:<18} {fam:<8} {runs[key]:>7} {turns[key]:>7} {tokens[key]:>10,}")
    tot_runs = sum(runs.values())
    tot_turns = sum(turns.values())
    tot_tok = sum(tokens.values())
    lines.append("-" * 54)
    lines.append(f"{'GESAMT':<18} {'':<8} {tot_runs:>7} {tot_turns:>7} {tot_tok:>10,}")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scope", default="all")
    ap.add_argument("--projects-dir", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--run-dir", required=True)
    args = ap.parse_args()

    scope = "session" if args.scope == "session" else "all"
    files = subagent_files(args.projects_dir, scope)
    runs, turns, tokens = collect(files)
    report = build_report(runs, turns, tokens, scope, len(files))

    os.makedirs(args.run_dir, exist_ok=True)
    report_file = os.path.join(args.run_dir, "subagent-models.txt")
    with open(report_file, "w", encoding="utf-8") as fh:
        fh.write(report + "\n")
    with open(os.path.join(args.run_dir, "outputs.json"), "w", encoding="utf-8") as fh:
        json.dump({"report_file": report_file, "summary": report}, fh, ensure_ascii=False, indent=2)

    print(report)


if __name__ == "__main__":
    main()
