# magic3 — Design-Spezifikation

Eine Spezifikation, fünf Ausgaben (Markdown, Word, HTML, PDF, PPTX). Fachliche Grundlage: IBCS/Hichert **SUCCESS**-Regeln (Regel-IDs in Klammern verweisen auf den `bimtec-codex:ibcs`-Skill).

---

## 1. Farbsemantik (Farbe folgt der Bewertung, nicht dem Vorzeichen — RULE-N1)

| Rolle | Hex | Einsatz |
|---|---|---|
| Hintergrund Fläche | `#FFFFFF` | Inhaltsflächen, Karten |
| Hintergrund Seite/Slide | `#FAFAFA` | Seiten-/Folien-Grund |
| Trennlinien / Karten-Rand | `#ECECEC` | dezente Abgrenzung |
| Text / Ist (Aktual) | `#333333` | Fließtext, Datenwerte |
| Titel (stark) | `#000000` | nur Botschafts-Titel |
| Sekundärtext / Achsen | `#666666` | Annotation, Achsbeschriftung |
| Feine Linien | `#D0D0D0` | Tabellen, Achslinien |
| **Akzent / positiv = günstig** | **`#388E3C`** | Akzentbalken, günstige Abweichung, Marker |
| Akzent dunkler (Hover) | `#2E7D32` | Interaktion (HTML) |
| Akzent soft / Fläche | `#DCEBD6` | dezente günstige Flächen |
| Negativ = ungünstig | `#DD3333` | ungünstige Abweichung |
| Negativ soft | `#F7D5D5` | dezente ungünstige Flächen |
| Plan / Budget | `#808080` | **nur gerahmt/Kontur**, nicht gefüllt (RULE-N3) |
| Vorjahr (PY) | `#B0B0B0` | gefüllt-hell (RULE-N4) |
| Forecast | `#B0B0B0` | schraffiert (RULE-N5) |

**Regeln:**
- Ampel-Logik: grün = günstig, rot = ungünstig — auch bei negativem Vorzeichen (Kostensenkung = grün).
- Grün **nie** als ganze Fläche "weil schön" — nur als Akzentlinie/Marker/günstige Bewertung.
- Farbsemantik im ganzen Dokument konsistent (RULE-U1).

---

## 2. Typografie (RULE-N13/N14)

- Serifenlos, **eine** Familie pro Dokument: **Source Sans 3** (bevorzugt), Fallback Source Sans Pro/Arial.
- **Laufweite +0,15 pt** (leicht erweitert). CSS: `letter-spacing: 0.15pt`. Word/PPTX: Zeichenabstand „erweitert" um 0,15 pt.
- Festes Größen-System, nicht beliebig mischen: **Titel-Botschaft · Untertitel · Body · Annotation/Quelle**.
- Zahlen in Tabellen **rechtsbündig** (RULE-N15), **gleiche Dezimalstellen pro Spalte** (RULE-N16).
- Jede Zahl mit Einheit, Zeitraum, Kontext (RULE-N11).

---

## 3. SUCCESS-Kern (immer durchsetzen)

- **SAY** — Jeder Titel ist eine **Botschaft**, kein Thema. „Umsatz 12 % unter Plan" statt „Umsatz 2026". Tabellen bekommen ein Kurzfazit.
- **UNIFY** — Farbsemantik, Einheiten und Zeitachsen (links → rechts) konsistent; direkt verglichene Charts haben identische Skalen.
- **CONDENSE** — Hohe Dichte, kleine Multiples; Tabelle bündelt Ist / Plan / Δ abs / Δ % in einer Zeile.
- **CHECK** — Y-Achse bei Null; kein 3D; keine perspektivischen Torten; gekappte Achsen kennzeichnen.
- **EXPRESS** — Zeitreihe → Säulen (Ist) / Linie (Forecast); Anteil & Vergleich → horizontale, sortierte Balken; **keine Torten** (außer genau 2 Segmente), keine Spider-Charts.
- **SIMPLIFY** — Keine Farbverläufe, Schatten, Chart-Rahmen, überflüssigen Gitter, Legenden (direkt beschriften), Deko-Icons/Wasserzeichen.
- **STRUCTURE** — MECE; Tabellen hierarchisch; einheitlich Titel → Inhalt → Quelle/Fußzeile.
- **Abweichungen** — absolut **und** relativ nebeneinander, Vorzeichen explizit, farblich bewertet (RULE-N6–N8).

---

## 4. Format-Mapping

### Markdown (Quelle, auch für `md_to_pdf`)
- `H1` = Dokument-Botschaft, `H2` = Abschnitts-Botschaft.
- Tabellen mit Δ-Spalten (abs + %), Zahlen rechtsbündig, einheitliche Dezimalstellen.
- Keine dekorativen Badges/Emojis. Beim PDF/HTML-Render `theme.css` einbinden.

### HTML / CSS
- `theme.css` einbinden bzw. dessen `:root`-Variablen nutzen.
- Kein `box-shadow`, kein `gradient`. Direktlabels an Datenpunkten statt Legende.
- **Flex statt Grid**, wenn das HTML auch via WeasyPrint zu PDF wird.

### PDF (via `md_to_pdf` / WeasyPrint, MD → HTML/CSS-Pfad)
- Gleiche Variablen wie HTML; **Flex statt Grid** (WeasyPrint-Limit).
- Heller Seitenhintergrund `#FFFFFF`, Akzentlinien `#388E3C`, Tabellen mit dünnen `#D0D0D0`-Linien.
- `@page`-Rand + dezente Kopf-/Fußzeile mit Quelle/Datum.
- **Nicht** `design=collana/magicM` (das sind b-imtec/TK) — stattdessen `theme.css` injizieren.

### Word (.docx)
- Theme-Akzentfarbe `#388E3C`, Text `#333333`.
- Formatvorlagen: „Titel" = Botschaft, „Überschrift 1/2" = Abschnitts-Botschaften.
- Tabellenstil mit dünnen `#D0D0D0`-Linien, Zahlenspalten rechtsbündig.
- Keine Schatten/3D-Effekte in eingebetteten Charts.

### PPTX
- Folienmaster: heller Hintergrund `#FAFAFA`, Titelzeile = Message (linksbündig), Akzentbalken `#388E3C`.
- Theme-Farben: Akzent1 `#388E3C`, Akzent2 `#DD3333`, Text `#333333`, Plan/PY in Graustufen.
- Charts ohne Gitter/Legende, Direktbeschriftung, **kleine Multiples** statt 1 Chart pro Folie.

---

## 5. Abgrenzung

magic3 ist **nicht** zu verwechseln mit:
- **Clean Design** (UI/Glas-Cards, `#16a34a`),
- **TK-Dark** / **b-imtec/Collana** (`bimtec-codex`-Skills, `md_to_pdf` collana),
- **magicM** (privater `md_to_pdf`-Default).

Bei explizitem Kunden-Corporate-Design hat dessen Farbe Vorrang; die SUCCESS-Struktur/Semantik gilt trotzdem.
