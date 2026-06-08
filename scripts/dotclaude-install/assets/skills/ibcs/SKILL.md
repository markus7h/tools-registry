---
name: ibcs
description: IBCS/Hichert-Standards auf Präsentationen, Reports, Dashboards anwenden oder prüfen. SUCCESS-Regeln, Farbsemantik, Notation.
---

# IBCS / Hichert Skill

Dieser Skill bringt die IBCS-Standards (International Business Communication Standards) nach Prof. Dr. Rolf Hichert in die Arbeit mit Claude ein. Grundlage sind die **SUCCESS-Regeln** und die **harten Notationsregeln** aus `rules.md`.

## Wann Du diesen Skill verwendest

### On-Demand (Standard)

Der Skill läuft nur, wenn der User explizit aufruft:

- **`check <datei|beschreibung>`** → Review: prüfe die Datei/Beschreibung gegen SUCCESS und Notation, liefere strukturierte Findings mit konkreten Verbesserungsvorschlägen.
- **`apply <datei>`** → Rewrite: schreibe die Datei IBCS-konform um (Titel als Botschaft, Farbsemantik, Skalen, Flächennotation).
- **`explain <regel>`** → Erkläre eine spezifische SUCCESS-Regel oder Notationsvorgabe.

### Passiv (Hinweis, nicht Durchsetzung)

Wenn der User **in einer normalen Konversation** eine Präsentation, einen Report oder ein Dashboard-Konzept erstellt, **darfst Du einmalig** darauf hinweisen: „Soll ich IBCS anwenden?". Niemals aufdrängen. Keine Aufforderung, wenn der User bereits explizit IBCS oder Hichert erwähnt hat.

## Wie Du vorgehst

### Bei `check`

1. Lade `rules.md` und nutze die dortige Regelbasis als Prüfmaßstab.
2. Analysiere die Eingabe (Datei, Beschreibung oder explizit genannter Slide) strukturiert:
   - **Say**: Hat jede Slide / jedes Diagramm einen Botschafts-Titel?
   - **Unify**: Ist die Farbsemantik konsistent? Haben Einheiten und Zeitachsen einheitliche Notation?
   - **Condense**: Ist die Informationsdichte angemessen oder wirkt etwas künstlich aufgebläht / zu dünn?
   - **Check**: Y-Achsen bei Null? Kein 3D? Keine Verzerrung?
   - **Express**: Richtiger Diagrammtyp für den Datentyp?
   - **Simplify**: Rauschen (Gitter, Schatten, Farbverläufe, Deko) vorhanden?
   - **Structure**: Logische Gliederung, MECE-konform?
3. Liefere ein Review in dieser Form:

```
# IBCS-Review: [Dateiname]

## Findings

### Kritisch
- [Nummerierte Liste mit konkreten Verstößen, jeweils mit Slide/Element-Referenz]

### Empfohlen
- [Verbesserungen, die nicht Regelverstöße sind, aber Qualität heben]

### OK
- [Was bereits konform ist – kurz, nur Highlights]

## Zusammenfassung
[1-2 Sätze: wie IBCS-konform ist das Dokument, und was sind die 3 wichtigsten Hebel?]
```

### Bei `apply`

1. Lade `rules.md`.
2. Lies die Zieldatei.
3. Wende die Regeln an, priorisiert:
   - **Titel** als Botschaft umformulieren (kein Thema mehr)
   - **Farbsemantik** durchsetzen (Ist/Plan/Vorjahr/Forecast)
   - **Flächennotation** anwenden (gefüllt/gerahmt/schraffiert)
   - **Skalen** prüfen, bei Bedarf auf Null-Basis setzen
   - **Tortendiagramme** durch Balken ersetzen
   - **Gitter, Schatten, Farbverläufe** entfernen
   - **Direktbeschriftung** statt Legenden
   - **Abweichungen** explizit (abs + rel)
4. Berichte am Ende, was Du verändert hast, in einer kurzen Liste.

### Bei `explain`

Gib eine kompakte, praxisnahe Erklärung der genannten Regel, mit mindestens einem konkreten Beispiel (schlecht → gut). Verweise am Ende auf `../../docs/ibcs-hichert.md` für die ausführliche Fassung.

## Wichtige Hinweise

- **Farben sind kontextabhängig**: Positive Abweichung ist nicht immer „plus", sondern „günstig". Kostensenkung ist grün, auch wenn das Vorzeichen minus ist.
- **Keine Ideologie**: Wenn ein Kunde explizit andere Vorgaben hat (eigenes Corporate Design, spezielles Branding), dann diese respektieren und IBCS-Regeln nur dort anwenden, wo sie **nicht** mit der Kundenvorgabe kollidieren.
- **Ehrlich bleiben**: Wenn die Datei grundsätzlich in Ordnung ist, sag das. Nicht künstlich Findings erfinden, um Arbeit zu zeigen.
- **Rules first, Style second**: IBCS-Regeln haben Vorrang vor ästhetischen Vorlieben. Aber wenn ein Regelverstoß aus gutem Grund gewählt wurde (dokumentierte Ausnahme), akzeptieren.

## Verweise

- `rules.md` – die harte Regelbasis (automatisch mit diesem Skill geladen)
- `../../docs/ibcs-hichert.md` – Kompendium für Menschen, ausführlich
- `../../docs/ibcs-cheatsheet.md` – 1-Seiten-Quick-Reference
- [ibcs.com](https://www.ibcs.com/de/) – offizielle Standards, CC-Lizenz
