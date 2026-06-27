#!/usr/bin/env python3
"""Re-measure the ai-rem token-savings basis from the local Claude Code
transcripts (~/.claude/projects/*/*.jsonl).

Measured per session: date, whether ai-rem MCP tools were used, number of
ai-rem calls, and the size of the ai-rem tool-result payload (chars / ~4 as a
rough token estimate). Agent sidechains and near-empty sessions are skipped.

Note: Claude Code prunes transcripts after ~30 days (cleanupPeriodDays), so the
window only covers what is still on disk. The per-recall-session savings itself
stays a model — this script only measures usage, recall rate and overhead.
"""
import argparse
import collections
import datetime
import glob
import json
import os


def collect(projects_dir: str) -> list[tuple]:
    sessions = []  # (date, used_airem, n_calls, result_chars)
    for f in glob.glob(os.path.join(projects_dir, "*", "*.jsonl")):
        first_ts = None
        used = False
        n_calls = 0
        result_chars = 0
        n_msgs = 0
        sidechain = False
        try:
            with open(f, encoding="utf-8", errors="replace") as fh:
                pending_airem = set()
                for line in fh:
                    try:
                        rec = json.loads(line)
                    except Exception:
                        continue
                    ts = rec.get("timestamp")
                    if ts and first_ts is None:
                        first_ts = ts
                    if rec.get("isSidechain"):
                        sidechain = True
                    msg = rec.get("message") or {}
                    content = msg.get("content")
                    if isinstance(content, list):
                        for c in content:
                            if not isinstance(c, dict):
                                continue
                            if c.get("type") == "tool_use" and str(c.get("name", "")).startswith("mcp__ai-rem__"):
                                used = True
                                n_calls += 1
                                pending_airem.add(c.get("id"))
                            elif c.get("type") == "tool_result" and c.get("tool_use_id") in pending_airem:
                                result_chars += len(json.dumps(c.get("content", ""), ensure_ascii=False))
                    if rec.get("type") in ("user", "assistant"):
                        n_msgs += 1
        except Exception:
            continue
        if first_ts is None or sidechain or n_msgs < 2:
            continue
        sessions.append((first_ts[:10], used, n_calls, result_chars))
    sessions.sort()
    return sessions


def build_report(sessions: list[tuple]) -> str:
    if not sessions:
        return "no sessions found"
    dates = [s[0] for s in sessions]
    days = (datetime.date.fromisoformat(dates[-1]) - datetime.date.fromisoformat(dates[0])).days + 1
    total = len(sessions)
    recall = [s for s in sessions if s[1]]
    calls = sum(s[2] for s in recall)
    chars = sum(s[3] for s in recall)
    lines = [
        f"Transcript window: {dates[0]} .. {dates[-1]}  ({days} days)",
        f"Total sessions: {total}  ({total/days:.1f}/day)",
        f"Sessions using ai-rem: {len(recall)}  ({100*len(recall)/total:.0f} %)",
        f"ai-rem tool calls total: {calls}  (avg {calls/max(len(recall),1):.1f}/recall-session)",
        f"ai-rem result payload: {chars} chars ≈ {chars//4} tokens total, "
        f"≈ {chars//4//max(len(recall),1)} tokens/recall-session",
        "",
        "Per month: total / with-ai-rem",
    ]
    by_month = collections.Counter(d[:7] for d in dates)
    by_month_recall = collections.Counter(s[0][:7] for s in recall)
    for m in sorted(by_month):
        lines.append(f"  {m}: {by_month[m]} / {by_month_recall.get(m, 0)}")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--projects-dir", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--run-dir", required=True)
    args = ap.parse_args()

    report = build_report(collect(args.projects_dir))

    os.makedirs(args.run_dir, exist_ok=True)
    report_file = os.path.join(args.run_dir, "measure-savings.txt")
    with open(report_file, "w", encoding="utf-8") as fh:
        fh.write(report + "\n")
    with open(os.path.join(args.run_dir, "outputs.json"), "w", encoding="utf-8") as fh:
        json.dump({"report_file": report_file, "summary": report}, fh, ensure_ascii=False, indent=2)

    print(report)


if __name__ == "__main__":
    main()
