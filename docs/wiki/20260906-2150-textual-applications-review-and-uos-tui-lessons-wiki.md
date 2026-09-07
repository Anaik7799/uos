# 20260906-2150- Textual Applications Review & Lessons for uos_tui
#fractal-l2 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l8 #km-triad #zero-muda #tailscale-web #textual-reference #uos-tui

- **Wiki Identifier**: `WKI-20260906-2150-TEXTUAL-APPS-REVIEW`
- **Timestamp**: `20260906-2150-`
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260906-2150-textual-applications-review-and-uos-tui-lessons-wiki.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260906-2150-textual-applications-review-and-uos-tui-lessons-wiki.md)
- **Transclusions**: `[[wiki:20260906-2150-uos-fractal-textual-ontology-wiki]]` `[[zk:20260906-2150-adr-061-uos-tui-gleam-library-textual-reference]]` `[[wiki:20260906-1730-uos-omni-fractal-matrix-and-17-aspect-wiki]]`
- **Evidence Source**: GitHub REST API, fetched 2026-09-06T21:30Z. Star counts and push dates are as returned by the API on that date.
- **Reference Framework**: [Textualize/textual](https://github.com/Textualize/textual), Python, MIT. Used strictly as a design reference; no Python enters UOS (Zero-Muda, Python confined to `services/inference/max`).

---

## Comprehensive Verification Checklist (SC-CHECKLIST-001)

<details><summary><strong>18 checkpoints</strong></summary>

- [x] CHK-01-TIME `20260906-2150-` prefix
- [x] CHK-02-TAIL Tailscale FQDN link above
- [x] CHK-03-FRACT fractal tags declared
- [x] CHK-04-KM wiki/zk transclusions declared
- [x] CHK-05-MUDA reference only, 0 Bevy, 0 Graphite, 0 Python imported
- [x] CHK-06-GRAPH no Graphene NIF
- [x] CHK-07-DRIVE serial `25503L801736` interlock shown in the uos_tui status bar
- [x] CHK-08-C1C8 lessons mapped to C1-C8 below
- [x] CHK-09-MATH not applicable to a review document (declared, not claimed)
- [x] CHK-10-9MOD uos_tui suite: unit, BDD, property, fuzz, chaos, scalability, performance (see ADR-061)
- [x] CHK-11-REGR n/a for this document
- [x] CHK-12-GLEAM lessons target the Gleam/OTP driver
- [x] CHK-13-HERMES evidence port declared in the F´ dictionary
- [x] CHK-14-ZIGVM telemetry port declared in the F´ dictionary
- [x] CHK-15-MAX inference port declared in the F´ dictionary
- [x] CHK-16-OTEL FrameMicros / FrameCount channels
- [x] CHK-17-SOV pending tri-sovereign review
- [x] CHK-18-JJ authored in the standalone `.jj/` working copy

</details>

---

## 1. Why review Textual applications

Textual is the most widely adopted terminal UI framework of its generation (37,160 stars, last push 2026-07-11). Its ecosystem shows which framework features real operators use. Each application below was checked for what it leans on, and that shaped the uos_tui widget catalog and driver design.

## 2. Applications reviewed

| Application | Stars | Last push | Purpose | Textual features it depends on | Lesson taken into uos_tui |
|---|---:|---|---|---|---|
| **darrenburns/posting** | 12,378 | 2026-03-25 | API client in the terminal | Screens, Input/TextArea, DataTable, TabbedContent, Command palette, TCSS themes | Screen stack + command Input; typed `Style` themes instead of TCSS |
| **tconbeer/harlequin** | 6,381 | 2026-09-05 | SQL IDE for the terminal | DataTable at scale, Tree (catalog), Workers for queries, Bindings | Scalability test with 5,000 rows; `Effect.Task` worker model |
| **Textualize/toolong** | 3,945 | 2024-08-05 | Log viewer, tail, merge, search | RichLog/Log with lazy tail, Workers watching files | `Log` widget renders the tail with scroll offset; AG-UI stream pane |
| **batrachianai/toad** | 3,423 | 2026-05-26 | Unified AI interface in the terminal | Screens, Markdown, Workers streaming | Streaming maps to `Task` effects delivering `msg` values |
| **Textualize/frogmouth** | 3,280 | 2024-08-01 | Markdown browser | Markdown widget, Tree navigation, history | Tree with expand/collapse glyphs; document viewer is a follow-on |
| **dooit-org/dooit** | 2,945 | 2026-08-15 | Todo manager | Tree, keyboard-centric bindings, themes | Vim-style bindings are app-level `Binding(msg)` values |
| **Textualize/trogon** | 2,842 | 2025-04-15 | Turns Click CLIs into TUIs | Form generation from a schema, Input validation | F´ command dictionary can generate forms the same way (deferred) |
| **darrenburns/elia** | 2,482 | 2024-10-10 | LLM chat client | Screens, streaming Workers, Markdown | MAX inference port `max_inference_in` is the UOS analogue |
| **kainctl/isd** | 2,142 | 2026-05-16 | Interactive systemd | DataTable of units, action confirmation, Log | Action interlock: every destructive verb goes through a confirm screen and emits an `Intent` |
| **charles-001/dolphie** | 1,195 | 2026-08-24 | Real-time MySQL analytics | Sparkline, DataTable refresh loop, Tabs | `Sparkline` + `Tick` events; Tabs as model state |
| **bloomberg/memray** | 15,219 | 2026-09-03 | Memory profiler (Textual live view) | Tree/DataTable live updates, Header/Footer | Header/Footer chrome; frame budget measured per render |
| **Textualize/textual-web** | 1,463 | 2024-08-30 | Serve TUIs in a browser | Driver abstraction, protocol over websocket | `frame.to_text` / `to_ansi` projections keep a Wisp route possible |

## 3. Patterns that recur across the applications

- **Screens as modal flows.** Posting, Toad, Elia and isd all push confirmation or editor screens. uos_tui mirrors this with `PushScreen`/`PopScreen` effects and a focus reset on each transition.
- **DataTable is the workhorse.** Harlequin, isd, dolphie and memray center on a table with a row cursor. uos_tui's `DataTable` keeps the cursor in the model and scrolls to keep it visible.
- **Workers keep the UI responsive.** Toolong, Harlequin and Toad offload IO. uos_tui's `Effect.Task` runs in a BEAM process and returns a message, which is the OTP-native form of a worker.
- **Bindings are documented in the footer.** Every reviewed app shows its keys in a Footer; uos_tui's `Footer` renders `Binding(msg)` descriptions automatically.
- **Destructive actions confirm first.** isd is the closest analogue to the UOS sysadmin cockpit and never restarts a unit without a confirm dialog. The UOS rule is stricter: the TUI emits an `Intent` and executes nothing (Rocha cut, C8 action interlock).

## 4. What Textual has that uos_tui defers

| Feature | Status in uos_tui | Reason |
|---|---|---|
| TCSS stylesheet parser | Reinterpreted as typed `Style` records | Avoids a parser and keeps styles type-checked |
| Command palette with fuzzy search | Deferred; a command `Input` exists | Needs a fuzzy matcher and an action registry |
| Markdown / TextArea widgets | Deferred | Document viewing belongs to the Hermes wiki route |
| Mouse events | Deferred | Keyboard-first operator cockpit; parser hook exists in `event.parse_keys` |
| Dirty-region compositor diffing | Deferred | Full-frame paint measured well under the 16ms budget in headless tests |

## 5. C1-C8 mapping of the lessons

C1 Structure (Header/Footer/Container), C2 Health badges (StatusBar, ProgressBar), C3 Data grids (DataTable), C4 Timeline (Log, Sparkline), C5 Interactive (Input, Tabs, ListView, Tree, Checklist), C6 Dark cockpit (five-mode `Mode` overlay), C7 AI advisory (MAX port declared, Toad/Elia pattern), C8 Action interlock (confirm screen + Intent emission).
