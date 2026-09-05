# Copy deck — canonical text before canvas

Authored 20260804 (Phase-0 "write copy first"). Voice: plain, technical,
honest — never overclaim; unavailable things say so. Evidence-gated
surfaces use observed-not-fabricated phrasing (closure lattice). This deck
is the copy source for Figma text layers and the Bonsai views; the drawn
screens P01/P05/P17/P19 already use it.

## Global microcopy patterns

| Context | Copy |
|---|---|
| Primary CTA | Create your first graph |
| Secondary CTA | Explore a demo |
| Empty (first-use) | Nothing here yet — import a source to begin. |
| Empty (no-results) | No matches — adjust the query. |
| Unavailable | Not available: {reason} (observed, not fabricated). |
| Rate-limited | Provider rate-limited — retrying with backoff; results may lag. |
| Destructive confirm | This permanently removes {thing} and its evidence links. |
| Destructive button | Delete · cancel = Cancel (never "OK") |
| Saving states | Saving… → Saved · conflict = Newer version exists — review before overwriting. |
| Progress | {n} of {m} sources · working… · done — {count} statements admitted |
| Field placeholder | Paste or write text to analyze… |
| Invalid field | {what} isn't valid: {why} |
| Tooltip style | Noun phrase, no period ("Betweenness centrality") |

## Per-screen headings + lead copy (selected)

**P01 Product home** — H1: *See the structure of any text as a knowledge
graph.* Lead: *Import documents, web sources, and live notes; explore
concepts, gaps, and topical clusters in an interactive graph backed by the
OCaml harness.* Nav: Use cases · Pricing · Docs · Sign in · Get started.

**P05 Login** — H1: *Sign in to zigvm.* Note: *Evidence-gated session —
the account surface stays Unavailable_observed until a provider is
configured.* Fields: Email / Password · CTA: Sign in · Link: Forgot
password?

**P07 Onboarding** — Steps: Welcome → Pick a use case → Privacy defaults →
First source. Step lead: *Everything stays private until you explicitly
share it.*

**P10 New graph wizard** — H1: *New graph.* Steps: Identity · Privacy ·
Source · Confirm. Confirm lead: *Review the summary before continuing.*

**P12 Document import** — Dropzone: *Drop documents here* / sub: *PDF,
DOCX, TXT, CSV up to 25 MB.* Rejected: *Unsupported file type.*

**P16 Import progress** — States: queued · running ({n} of {m}) ·
retrying · complete (*done — {count} statements admitted*) · failed
(*failed at source {k} — retry or skip*).

**P17 Interactive graph** — Panel title: *ZigVM living ontology.* Rows:
Nodes · Edges · Components · Communities · Density. Export chip:
*GraphML · DOT exports.* Context actions: Focus · Hide · Open statements.

**P18 Statements** — Filter chips: All · Selected node · Selected topic ·
By source. Empty: *Select a node to see its supporting statements.*

**P19 Analytics** — Tiles: Statements · Concepts · Topics · Structural
gaps. Insights: *Bridge topic detected* / *Structural gap* (+ one-line
explanation, click-through: *click to open supporting statements*).

**P21 Research** — Composer placeholder: *Ask about this graph…* ·
Unavailable: *No provider configured — connect one in Settings →
Providers.*

**P25 Share** — Visibility: Private (default) → *Make public?* confirm:
*Anyone with the link can view this graph.* → Public · Revoke: *Revoking
disables all existing links.*

**P26 Export** — Formats: JSON · CSV · GraphML · PNG · SVG · PDF · Ready:
*Your export is ready* · button: Download.

**P34 Privacy** — Delete flow: *Delete project?* → confirm phrase →
*Deleted. Retention: purged from backups within 30 days.*

**P35–P37 Account** — Gate line: *EVIDENCE_GATED: the account surface is
Unavailable_observed until a provider session exists — never fabricated.*

## Tone rules

1. State facts, not promises; numbers over adjectives.
2. Every error names the cause and the next action.
3. "observed, not fabricated" wording is mandatory on gated surfaces.
4. Buttons are verbs; toggles are states; tooltips are noun phrases.
