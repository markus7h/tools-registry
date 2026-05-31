#!/usr/bin/env python3
"""
UserPromptSubmit hook for Claude Code.

Dünner Client: schickt den rohen Prompt an den ai-rem /discover REST-Endpoint.
Keyword-Extraktion, Suche, Kategorisierung und Caching laufen server-seitig
(ein Round-Trip statt MCP-Handshake). Bei Treffern wird ein <available-tools>
Block auf stdout geschrieben, den Claude als Kontext injiziert bekommt.

Stille bei: Fehler, leerem Prompt, kein Treffer. Niemals exit != 0, damit ein
defekter Hook den Prompt nicht blockt.
"""

import json
import os
import sys
import urllib.error
import urllib.request

# Endpoint des ai-rem /discover-Servers. Default lokal; via Env überschreibbar.
DISCOVER_URL = os.environ.get("AI_REM_DISCOVER_URL", "http://127.0.0.1:3456/discover")
TIMEOUT = 2.5
MAX_HITS = 5


def emit(text: str) -> None:
    sys.stdout.write(text + "\n")
    sys.stdout.flush()


def discover(prompt: str) -> dict:
    body = json.dumps({"prompt": prompt, "context": "private", "max_hits": MAX_HITS}).encode()
    req = urllib.request.Request(
        DISCOVER_URL, data=body, method="POST",
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return

    prompt = (payload.get("prompt") or "").strip()
    if len(prompt) < 5:
        return

    try:
        data = discover(prompt)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return

    tools = data.get("tools", [])
    playbooks = data.get("playbooks", [])
    knowledge = data.get("knowledge", [])
    if not (tools or playbooks or knowledge):
        return

    keywords = ", ".join(data.get("keywords", []))
    lines = ["<available-tools>"]

    if tools or playbooks:
        lines.append(
            f"Aus ai-rem für deine Aufgabe relevant (Keywords: {keywords}) — "
            "bevorzuge diese gegenüber Bash-/Edit-/Write-Eigenlösungen:")
        for h in playbooks[:MAX_HITS]:
            lines.append(f"- [Playbook] **{h['name']}** — {h['summary'][:160].rstrip()}")
        for h in tools[:MAX_HITS]:
            lines.append(f"- [Tool] **{h['name']}** — {h['summary'][:160].rstrip()}")

    if knowledge:
        lines.append("Aus ai-rem relevant (Kontext, keine Tools):")
        for h in knowledge:
            lines.append(f"- [{h['type']}] **{h['name']}** — {h['summary'][:160].rstrip()}")

    lines.append("</available-tools>")
    emit("\n".join(lines))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Hook darf den Prompt nie blockieren.
        pass
