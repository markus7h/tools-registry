#!/usr/bin/env python3
"""Regressionstest: Routines-Drosselung im Discovery-Hook.

Die Routines sind Verhaltensregeln — werden sie zu selten oder gar nicht
ausgegeben, verliert Claude sie still. Darum hier festgenagelt.

    python3 hooks/test_routines_due.py
"""
import importlib.machinery, importlib.util, os, pathlib, tempfile, sys

HOOK = pathlib.Path(__file__).with_name("tool-discovery.sh")
loader = importlib.machinery.SourceFileLoader("td", str(HOOK))
spec = importlib.util.spec_from_loader("td", loader)
td = importlib.util.module_from_spec(spec)
loader.exec_module(td)

fails = []


def check(label, got, want):
    if got != want:
        fails.append(f"{label}: erwartet {want}, war {got}")


with tempfile.TemporaryDirectory() as tmp:
    os.environ["XDG_RUNTIME_DIR"] = tmp

    # Erster Prompt einer Session: ja. Danach bis ROUTINES_EVERY: nein.
    check("Prompt 1", td._routines_due("sess-a"), True)
    for i in range(2, td.ROUTINES_EVERY + 1):
        check(f"Prompt {i}", td._routines_due("sess-a"), False)
    # Nach ROUTINES_EVERY weiteren Prompts wieder ja.
    check(f"Prompt {td.ROUTINES_EVERY + 1}", td._routines_due("sess-a"), True)

    # Zweite Session zaehlt unabhaengig.
    check("andere Session", td._routines_due("sess-b"), True)

    # Ohne session_id: lieber redundant als regelfrei.
    check("ohne session_id", td._routines_due(""), True)

    # Kaputter Zaehler darf nicht stumm schalten.
    td._routines_due("sess-c")
    import hashlib
    d = pathlib.Path(tmp) / f"claude-routines.{os.getuid()}"
    (d / hashlib.sha256(b"sess-c").hexdigest()[:32]).write_text("MUELL")
    check("kaputte Marker-Datei", td._routines_due("sess-c"), True)

    # Marker-Verzeichnis nicht beschreibbar -> ebenfalls ausgeben.
    os.environ["XDG_RUNTIME_DIR"] = "/proc/nonexistent-readonly"
    check("unschreibbares XDG_RUNTIME_DIR", td._routines_due("sess-d"), True)

if fails:
    print("FEHLGESCHLAGEN:")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("ok - Routines-Drosselung verhaelt sich wie erwartet")
