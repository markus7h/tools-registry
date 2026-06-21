#!/usr/bin/env python3
"""
UserPromptSubmit hook for Claude Code.

Dünner Client: schickt den rohen Prompt an den ai-rem /discover REST-Endpoint.
Keyword-Extraktion, Suche, Kategorisierung und Caching laufen server-seitig
(ein Round-Trip statt MCP-Handshake). Die Antwort liefert:
  - tools/playbooks/knowledge → relevanz-gematcht (Keywords/Semantik)
  - routines                  → gepinnte Meta-Regeln, IMMER (unabhängig vom Match)

Der Hook löst den privat/work-Kontext HYBRID auf (Override-Datei → context-map.json
gegen cwd → sonst 'private' + Unsicherheits-Marker) und sendet ihn an /discover,
damit kontext-abhängige Regeln (Default-Design etc.) richtig gefiltert werden.

Endpoint + Bearer-Token werden aus AI_REM_ENDPOINT bzw. ~/.claude.json abgeleitet
(früher hart auf 127.0.0.1:3456 ohne Auth → lief ins Leere / 401).

Bei Treffern werden <available-tools>/<routines>/<context-uncertain>-Blöcke auf
stdout geschrieben, die Claude als Kontext injiziert bekommt. Stille bei Fehler,
leerem Prompt, kein Treffer. Niemals exit != 0, damit ein defekter Hook den
Prompt nicht blockt.
"""

import json
import os
import sys
import urllib.error
import urllib.request

TIMEOUT = 3.0
MAX_HITS = 5
HOME = os.path.expanduser("~")
CLAUDE_JSON = os.path.join(HOME, ".claude.json")
CONTEXT_MAP = os.path.join(HOME, ".claude", "context-map.json")
ACTIVE_CONTEXT = os.path.join(HOME, ".claude", ".active-context")


def emit(text: str) -> None:
    sys.stdout.write(text + "\n")
    sys.stdout.flush()


def _airem_conf() -> tuple[str, str]:
    """(discover_url, auth_header) aus Env/claude.json ableiten.

    URL-Quelle: AI_REM_DISCOVER_URL > AI_REM_ENDPOINT > claude.json ai-rem.url,
    jeweils '/mcp'→'/discover'. Token: claude.json ai-rem.headers.Authorization.
    """
    url = os.environ.get("AI_REM_DISCOVER_URL", "")
    auth = ""
    if not url:
        base = os.environ.get("AI_REM_ENDPOINT", "")
        if not base:
            try:
                with open(CLAUDE_JSON) as f:
                    base = json.load(f)["mcpServers"]["ai-rem"]["url"]
            except Exception:
                base = ""
        if base:
            url = base.rstrip("/")
            url = url[:-4] + "/discover" if url.endswith("/mcp") else url + "/discover"
    try:
        with open(CLAUDE_JSON) as f:
            auth = json.load(f)["mcpServers"]["ai-rem"]["headers"]["Authorization"]
    except Exception:
        auth = ""
    return url, auth


def _resolve_context(cwd: str) -> tuple[str, bool]:
    """Hybrid: (context, certain). Override-Datei → context-map gegen cwd →
    sonst 'private' + certain=False (Unsicherheits-Marker)."""
    # 1) Expliziter Session-Override
    try:
        val = open(ACTIVE_CONTEXT).read().strip().lower()
        if val in ("work", "private"):
            return val, True
    except Exception:
        pass
    # 2) cwd gegen context-map (längster Präfix-Treffer gewinnt)
    cwd = os.path.realpath(cwd or os.getcwd())
    try:
        with open(CONTEXT_MAP) as f:
            cmap = json.load(f)
    except Exception:
        cmap = {}
    best_ctx, best_len = "", -1
    for ctx in ("work", "private"):
        for root in cmap.get(ctx, []):
            root = os.path.realpath(os.path.expanduser(root))
            if (cwd == root or cwd.startswith(root + os.sep)) and len(root) > best_len:
                best_ctx, best_len = ctx, len(root)
    if best_ctx:
        return best_ctx, True
    # 3) Unklar → privat annehmen, aber markieren
    return "private", False


def discover(url: str, auth: str, prompt: str, context: str) -> dict:
    body = json.dumps({"prompt": prompt, "context": context, "max_hits": MAX_HITS}).encode()
    headers = {"Content-Type": "application/json"}
    if auth:
        headers["Authorization"] = auth
    req = urllib.request.Request(url, data=body, method="POST", headers=headers)
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

    url, auth = _airem_conf()
    if not url:
        return

    context, certain = _resolve_context(payload.get("cwd", ""))

    try:
        data = discover(url, auth, prompt, context)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return

    tools = data.get("tools", [])
    playbooks = data.get("playbooks", [])
    knowledge = data.get("knowledge", [])
    routines = data.get("routines", [])
    if not (tools or playbooks or knowledge or routines):
        return

    keywords = ", ".join(data.get("keywords", []))
    lines = []

    # Kontext-Status zuerst — steuert kontext-abhängige Defaults (Design etc.).
    if certain:
        lines.append(f"<active-context>{context}</active-context>")
    else:
        lines.append(
            "<context-uncertain>Kontext privat/work nicht eindeutig — 'private' "
            "angenommen. Vor kontext-abhängigen Defaults (Design, Git-Account, "
            "Deploy-Ziel) bestätigen.</context-uncertain>")

    if routines:
        lines.append("<routines>")
        lines.append(f"Immer geltende Regeln (ai-rem, Kontext: {context}):")
        for r in routines:
            lines.append(f"- **{r['name']}**: {r['summary']}")
        lines.append("</routines>")

    if tools or playbooks:
        lines.append("<available-tools>")
        lines.append(
            f"Aus ai-rem für deine Aufgabe relevant (Keywords: {keywords}) — "
            "bevorzuge diese gegenüber Bash-/Edit-/Write-Eigenlösungen:")
        for h in playbooks[:MAX_HITS]:
            lines.append(f"- [Playbook] **{h['name']}** — {h['summary'][:160].rstrip()}")
        for h in tools[:MAX_HITS]:
            lines.append(f"- [Tool] **{h['name']}** — {h['summary'][:160].rstrip()}")
        lines.append("</available-tools>")

    if knowledge:
        lines.append("<relevant-knowledge>")
        lines.append("Aus ai-rem relevant (Kontext, keine Tools):")
        for h in knowledge:
            lines.append(f"- [{h['type']}] **{h['name']}** — {h['summary'][:160].rstrip()}")
        lines.append("</relevant-knowledge>")

    emit("\n".join(lines))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Hook darf den Prompt nie blockieren.
        pass
