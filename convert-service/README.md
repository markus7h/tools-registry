# convert-service (Teil B)

Zustandsloser Konvertier-Dienst: bündelt die schweren Helfer (Chromium, LibreOffice,
WeasyPrint, pandoc, poppler) in **einem** Container, damit die tools-mcp-Clients nur `curl`
brauchen. Aufruf: rohe Datei im Request-Body → fertige Datei im Response-Body.

## Endpunkte

| Methode & Pfad | Body rein | Antwort | Query-Parameter |
|---|---|---|---|
| `GET /health` | – | `ok` | – |
| `POST /html_to_pdf` | HTML | PDF | `theme=none\|magic3`, `landscape=true\|false`, `wait_ms=<int>` |
| `POST /md_to_pdf` | Markdown | PDF | `design=collana\|magicM` |
| `POST /docx_to_pdf` | .docx | PDF | – (Metadaten in `X-Converter`, `X-Warning`) |
| `POST /pdf_to_text` | PDF | Text | `layout=true\|false` |

Nicht-200 → Klartext-Fehler im Body. `theme=magic3` injiziert das magic3-Theme (hell, grüner
Akzent #388E3C) + setzt gängige dunkle Theme-Variablen hell; Mermaid wird per Headless-Chromium
gerendert (CDN-geladenes Mermaid braucht Internet im Container).

## Konfiguration (Env)

| Variable | Default | Wirkung |
|---|---|---|
| `PORT` / `HOST` | `3458` / `0.0.0.0` | Listen-Adresse |
| `CONVERT_TOKEN` | – | gesetzt → alle POSTs verlangen `Authorization: Bearer <token>` |
| `CONVERT_MAX_BODY` | `104857600` | Body-Limit in Bytes (100 MB) |
| `CONVERT_TIMEOUT` | `120` | Per-Request-Timeout in Sekunden |
| `CHROME_BIN` | `/usr/bin/chromium` | Chromium-Pfad |

## Lokal bauen & testen

```bash
docker build -t tools-convert:latest convert-service/
docker run --rm -p 3458:3458 tools-convert:latest
curl -s localhost:3458/health                                            # → ok
curl -s --data-binary @doc.html "localhost:3458/html_to_pdf?theme=magic3&wait_ms=6000" -o out.pdf
```

Deploy auf den zentralen Host: `../deploy-convert.sh` (siehe Haupt-README).

> **Sicherheit:** nur im vertrauenswürdigen LAN binden, nie öffentlich. `CONVERT_TOKEN` setzen.
