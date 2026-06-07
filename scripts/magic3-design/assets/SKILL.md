---
name: magic3-design
description: Wendet das hauseigene "magic3" Design an — IBCS-konforme (SUCCESS) Dokument-/Report-Optik mit hellem Hintergrund und grünem Akzent (#388E3C). Gilt formatübergreifend für Markdown, Word, HTML, PDF und PPTX. Aufrufen beim Erstellen oder Umstellen von Dokumenten/Reports/Präsentationen auf das magic3-Design.
---

# magic3 Design Skill

Dieser Skill bringt **ein** Design-System in alle Ausgabeformate: hell, ruhig, IBCS-konform, mit grünem Akzent **#388E3C**. Eine Spezifikation → Markdown, Word, HTML, PDF, PPTX.

magic3 ist **eigenständig** — es ist nicht TK-Dark, nicht b-imtec/Collana, nicht "Clean Design" (UI/Glas-Cards). Die IBCS/Hichert-SUCCESS-Regeln sind die *fachliche* Grundlage, die Optik (Farben, Layout, Format-Mapping) ist hauseigen.

## Wann Du diesen Skill verwendest

- Der User nennt **"magic3"** / **"magic3 Design"** / **"magic3Design"** beim Erstellen oder Umstellen eines Dokuments.
- Als **Default**, wenn ein Dokument/Report/Präsentation erstellt wird und der User kein anderes Design explizit nennt (siehe ai-rem Pinned-Regel "Default-Design: IBCS Hell/Grün beim Erstellen").
- `apply <datei>` → bestehende Datei auf magic3 umschreiben.
- `check <datei>` → gegen die magic3/SUCCESS-Regeln prüfen und Findings liefern.

**Vorrang-Ausnahmen:** Nennt der User explizit ein anderes Design (TK-Dark, b-imtec/collana, magicM, Clean Design) → das nehmen. Bei verbindlichem Kunden-Corporate-Design haben dessen Farben Vorrang; die SUCCESS-**Struktur/Semantik** gilt trotzdem.

## Wie Du vorgehst

1. Lies `design-spec.md` (vollständige Regelbasis: Farbsemantik, Typografie, SUCCESS-Kern, Format-Mapping).
2. Beim Erstellen wendest Du die Spec direkt an. Beim Umstellen (`apply`) änderst Du priorisiert: Titel→Botschaft, Farbsemantik, Skalen auf Null, Torten→Balken, Deko/Schatten/Gitter raus, Direktbeschriftung.
3. Für **HTML/PDF** injizierst Du `theme.css` (oder dessen `:root`-Variablen). PDF läuft über `md_to_pdf`/WeasyPrint — Flex statt Grid, **nicht** `design=collana/magicM`, sondern dieses CSS.
4. Für **Word/PPTX** setzt Du Theme-Akzent #388E3C, Text #333, helle Flächen und die Formatvorlagen/Folienmaster gemäß Spec.
5. Berichte am Ende kurz, was Du nach magic3 gesetzt/geändert hast.

## Kernidentität (Kurzfassung)

- **Hintergrund hell**: #FFFFFF Fläche, #FAFAFA Seite/Slide, #ECECEC Trennlinien.
- **Text/Ist**: #333333 (Titel #000000).
- **Akzent / günstig**: #388E3C · **ungünstig**: #DD3333 · **Plan**: #808080 (nur Kontur) · **Vorjahr/Forecast**: #B0B0B0 (hell/schraffiert).
- **Farbe folgt der Bewertung**, nicht dem Vorzeichen (Kostensenkung = grün).
- Serifenlos: **Source Sans 3** (Fallback Arial), Laufweite +0,15 pt, festes Größen-System, Zahlen rechtsbündig.
- Kein 3D, keine Torten (außer 2 Segmente), keine Farbverläufe/Schatten/Deko, Direktbeschriftung statt Legende.

## Referenzen

- `design-spec.md` — vollständige Spezifikation inkl. Format-Mapping (MD/Word/HTML/PDF/PPTX).
- `theme.css` — fertige CSS-Variablen + Basis-Regeln für HTML & WeasyPrint-PDF.
- IBCS/SUCCESS-Hintergrund: Skill `bimtec-codex:ibcs` (neutrale Regelquelle).
