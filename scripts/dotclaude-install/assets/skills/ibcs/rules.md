# IBCS Regelbasis (maschinenlesbar)

Diese Datei ist die Regelquelle für den `ibcs`-Skill. Sie beschreibt die Prüfkriterien in kompakter, entscheidbarer Form. Die ausführliche Erklärung steht in `../../docs/ibcs-hichert.md`.

## SUCCESS-Regeln als Prüfpunkte

### S – Say

- **RULE-S1**: Der Titel einer Slide / eines Diagramms formuliert eine Botschaft, nicht ein Thema.
  - Violation: `Umsatz 2026`, `Kosten Q1`, `Mitarbeiterübersicht`
  - OK: `Umsatz 2026 liegt 12% unter Plan`, `Kosten Q1 wieder im Rahmen`, `Mitarbeiterzahl in DACH stagniert seit 18 Monaten`
- **RULE-S2**: Jede Slide hat einen erkennbaren Message-Satz (Titel oder Subheader).
- **RULE-S3**: Tabellen bekommen einen Bewertungstext (Kurzfazit).

### U – Unify

- **RULE-U1**: Farbsemantik ist konsistent. Ist-, Plan-, Vorjahres- und Forecast-Werte haben jeweils immer die gleiche Farbe/Notation im gesamten Dokument.
- **RULE-U2**: Einheiten-Notation ist einheitlich (`EUR m` statt mal `Mio. €` und mal `€ Mio`).
- **RULE-U3**: Zeitachsen laufen immer von links nach rechts.
- **RULE-U4**: Wenn zwei Diagramme direkt verglichen werden, haben sie identische Skalen.

### C – Condense

- **RULE-C1**: Hohe Informationsdichte. Eine Slide mit mehreren sinnvollen Informationen ist besser als mehrere leere Slides.
- **RULE-C2**: Kleine Multiples statt einer Slide pro Diagramm.
- **RULE-C3**: Tabellen bündeln Ist, Plan, Δ abs, Δ % auf einer Zeile.

### C – Check (Integrität)

- **RULE-CH1**: Y-Achse beginnt bei Null (Werte, Mengen).
- **RULE-CH2**: Kein 3D.
- **RULE-CH3**: Keine Tortendiagramme mit Perspektive.
- **RULE-CH4**: Gekappte Achsen explizit kennzeichnen (Bruchlinie).
- **RULE-CH5**: Logarithmische Skala nur mit Kennzeichnung.
- **RULE-CH6**: Bubble-Fläche proportional zum Wert (nicht Radius).

### E – Express (Diagrammwahl)

- **RULE-E1**: Diagrammtyp passt zum Datentyp.
  - Zeitreihe → Säulen (Ist), Linien (Forecast)
  - Struktur/Anteil → horizontale Balken, sortiert
  - Vergleich wenige Werte → horizontale Balken
  - Vergleich viele Kategorien → sortierte Tabelle mit Abweichungen
  - Verteilung → Histogramm/Boxplot
  - Zusammenhang → Streudiagramm
- **RULE-E2**: Keine Tortendiagramme (Ausnahme: genau 2 Segmente).
- **RULE-E3**: Keine Radar-/Spider-Charts (außer in spezifischen Fachkontexten).

### S – Simplify

- **RULE-SI1**: Keine Farbverläufe.
- **RULE-SI2**: Keine Schatten.
- **RULE-SI3**: Keine Rahmen um Diagramme.
- **RULE-SI4**: Keine Gitterlinien, wenn Achsenbeschriftung ausreicht.
- **RULE-SI5**: Keine Legenden, wenn direkte Beschriftung möglich.
- **RULE-SI6**: Keine Hintergrundbilder, Wasserzeichen, dekorative Icons.

### S – Structure

- **RULE-ST1**: MECE bei Segmentierungen (keine Überschneidungen, keine Lücken).
- **RULE-ST2**: Navigation in Dashboards: Top-Down oder Left-to-Right, nicht gemischt.
- **RULE-ST3**: Einheitliche Slide-Struktur: Titel-Botschaft, Inhalt, Fußzeile/Quelle.
- **RULE-ST4**: Tabellen hierarchisch gliedern (Obergruppen/Untergruppen), nicht flach.

## Harte Notationsregeln

### Farbpalette (Empfehlung, muss mit Corporate Design abgeglichen werden)

| Bedeutung | Farbe (Hex) |
|---|---|
| Ist (Aktual) | `#000000` oder `#333333` |
| Plan / Budget | `#808080` (gerahmt, nicht gefüllt) |
| Vorjahr (PY) | `#B0B0B0` |
| Forecast | Schraffur auf `#B0B0B0` |
| Positive Abweichung (günstig) | `#1DC6BC` oder `#00A651` |
| Negative Abweichung (ungünstig) | `#DD3333` oder `#C00000` |

**RULE-N1**: Farbe folgt der **Bewertung** (günstig/ungünstig), nicht dem Vorzeichen. Kostensenkung = grün, auch wenn Minus.

### Flächennotation

- **RULE-N2**: Ist = gefüllte Fläche
- **RULE-N3**: Plan = gerahmte Fläche (nur Kontur)
- **RULE-N4**: Vorjahr = hellere gefüllte Fläche
- **RULE-N5**: Forecast = schraffierte Fläche

### Abweichungen

- **RULE-N6**: Absolute Differenz und relative Differenz nebeneinander, nicht nur eine.
- **RULE-N7**: Vorzeichen explizit (+/−).
- **RULE-N8**: Farbliche Bewertung (günstig grün / ungünstig rot) gemäß Kontext.

### Skalierung und Beschriftung

- **RULE-N9**: Gleiche Einheiten = gleiche Skalen.
- **RULE-N10**: Y-Achse bei Null starten.
- **RULE-N11**: Jede Zahl hat Einheit, Zeitraum, Kontext.
- **RULE-N12**: Labels direkt am Datenpunkt, nicht in Legende.

### Layout

- **RULE-N13**: Serifenlose Schrift, konsistent (z.B. Aptos, Inter, Arial).
- **RULE-N14**: Schriftgrößen-System: Titel, Untertitel, Body, Annotation – nicht beliebig mischen.
- **RULE-N15**: Zahlen in Tabellen rechtsbündig.
- **RULE-N16**: Einheitliche Dezimalstellen pro Spalte.

## Output-Schema für Review (Skill-Modus `check`)

```markdown
# IBCS-Review: [Dateiname oder Eingabebeschreibung]

## Findings

### Kritisch (Regel-Verstöße, zu beheben)
- [Slide/Element] RULE-XX: [konkrete Beobachtung]. Korrektur: [konkreter Vorschlag].

### Empfohlen (Qualitäts-Upgrade, nicht zwingend)
- [Slide/Element]: [Beobachtung]. Hebel: [konkreter Vorschlag].

### OK (Highlights des Konformen)
- [kurz genannt]

## Zusammenfassung
[1-2 Sätze IBCS-Konformitäts-Einschätzung + 3 wichtigste Hebel]
```

## Output-Schema für Apply (Skill-Modus `apply`)

Nach der Bearbeitung:

```markdown
# IBCS-Apply: [Dateiname] – Änderungen

## Geändert
- [Slide X]: Titel `...` → `...` (RULE-S1)
- [Slide Y]: Farbpalette angepasst (RULE-U1, RULE-N1)
- ...

## Unverändert (bewusst belassen)
- [Element]: [Grund, z.B. Kunden-Corporate-Design]
```

## Kontext-Ausnahmen

Der Skill **respektiert** explizite Kundenvorgaben:

- Wenn Corporate Design des Kunden Farben vorgibt, haben diese Vorrang vor IBCS-Farben – Struktur/Semantik-Regeln gelten trotzdem.
- Wenn ein Kunde ausdrücklich andere Reporting-Standards nutzt (z.B. eigene interne Spec), wird IBCS nur als Sekundär-Check angewendet und nicht automatisch durchgesetzt.
- Bei Unsicherheit: User fragen, nicht selbstständig überschreiben.
