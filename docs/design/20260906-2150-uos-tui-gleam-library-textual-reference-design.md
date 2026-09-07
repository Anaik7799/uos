# 20260906-2150- uos_tui: Pure-Gleam Terminal UI Library (Textual Reference, F´ Binding, 17-Aspect Audit)
#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #zero-muda #tailscale-web #km-triad #uos-tui #textual-reference

- **Document Identifier**: `DESIGN-UOS-TUI-001`
- **Timestamp**: `20260906-2150-`
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260906-2150-uos-tui-gleam-library-textual-reference-design.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260906-2150-uos-tui-gleam-library-textual-reference-design.md)
- **Package**: `apps/uos_tui` (Gleam 1.16, target erlang, deps: gleam_stdlib, gleam_erlang, gleam_otp, gleam_json, argv)
- **Reference**: [Textualize/textual](https://github.com/Textualize/textual) (Python, MIT). Reference only; no Python, no NIF, no C.
- **Transclusions**: `[[wiki:20260906-2150-uos-fractal-textual-ontology-wiki]]` `[[wiki:20260906-2150-textual-applications-review-and-uos-tui-lessons-wiki]]` `[[zk:20260906-2150-adr-061-uos-tui-gleam-library-textual-reference]]` `[[wiki:20260906-1730-uos-omni-fractal-matrix-and-17-aspect-wiki]]` `[[wiki:20260906-0955-uos-fprime-agent-ecosystem-and-taxonomy]]`
- **Concurrent specification (not verified here)**: `docs/design/20260906-2150-uos-tui-fractal-aspect-denotational-algebraic-design-and-scenarios.md` was written by Antigravity/Gemini at the same minute and covers a TUI fractal-aspect algebra independently of this package; its "RATIFIED & FORMALLY PROVEN" status is that document's own claim.
- **Evidence state**: `implemented -> built -> executed -> passed` (116/116 tests, 0 warnings). Not `verified` or `admitted`: no Hermes two-key record and no tri-sovereign review yet.

---

## Comprehensive Verification Checklist (SC-CHECKLIST-001)

<details><summary><strong>18 checkpoints</strong></summary>

- [x] CHK-01-TIME `20260906-2150-` prefix
- [x] CHK-02-TAIL FQDN link above and in the cockpit status bar (aspect 14 test)
- [x] CHK-03-FRACT tags declared; every ontology concept has a layer
- [x] CHK-04-KM transclusions above; cockpit shows `[[wiki:...]]` and `[[zk:...]]` (aspect 16 test)
- [x] CHK-05-MUDA dependency manifest audited by aspect 3 (0 Bevy, 0 Graphite)
- [x] CHK-06-GRAPH 0 NIFs; 6 `@external` calls into `shell`, `io`, `erlang`, `calendar`
- [x] CHK-07-DRIVE `25503L801736` is an F´ parameter, a status field, and aspect 1
- [x] CHK-08-C1C8 catalog covers C1..C8 (see §5)
- [x] CHK-09-MATH not measured for this package (declared)
- [x] CHK-10-9MOD unit, system(headless), TDD, BDD, performance, scalability, property, fuzz, chaos present; see §7
- [x] CHK-11-REGR n/a
- [x] CHK-12-GLEAM `live.child_spec` returns an OTP `ChildSpecification`
- [x] CHK-13-HERMES `hermes_evidence_in` port
- [x] CHK-14-ZIGVM `zigvm_tlm_in` port
- [x] CHK-15-MAX `max_inference_in` port
- [x] CHK-16-OTEL `FrameMicros`/`FrameCount`/`ScreenDepth`/`CockpitMode` channels
- [x] CHK-17-SOV pending
- [x] CHK-18-JJ standalone `.jj/` working copy; no git mutation

</details>

---

## 1. Problem

The prior TUI layer (`apps/cepaf_gleam/src/cepaf_gleam/ui/tui/`, reviewed in the journal of 20260906) is 54 string renderers with no runtime, a bash launcher that boots a VM per keypress (1.16s per frame), literal data, and fictional container actions. It failed 10 of 17 aspects. This design replaces the runtime and widget layer with a library that a Gleam application composes, keeping the old renderers as read-only evidence.

## 2. Architecture (Textual → uos_tui)

```text
 Textual (Python)                       uos_tui (Gleam/OTP)
 ┌──────────────┐                       ┌──────────────────────────────┐
 │ App.compose  │ ───── TEA ──────────▶ │ app.App{init,update,screens} │  L4
 │ Screen stack │                       │ Effect: Push/Pop/Focus/Task  │
 ├──────────────┤                       ├──────────────────────────────┤
 │ Widget DOM   │ ─── closed sum ─────▶ │ widget.Widget(msg) (17 kinds)│  L2
 │ TCSS         │ ─── typed record ───▶ │ style.Style (combine monoid) │  L1
 │ Scalar/fr    │ ─── isomorphic ─────▶ │ layout.Scalar / arrange/grid │  L1
 ├──────────────┤                       ├──────────────────────────────┤
 │ Compositor   │ ─── blit/placements ▶ │ render.compose -> frame.Frame│  L3
 │ Strip/Segment│ ─── isomorphic ─────▶ │ segment.Strip (crop/extend)  │  L1
 ├──────────────┤                       ├──────────────────────────────┤
 │ events/keys  │ ─── total parser ───▶ │ event.parse_keys             │  L3
 │ Bindings     │ ─── Binding(msg) ───▶ │ Footer renders descriptions  │  L3
 │ Workers      │ ─── BEAM process ───▶ │ live: Task -> Dispatch(msg)  │  L4
 │ Driver       │ ─── OTP actor ──────▶ │ live.start / child_spec      │  L4
 │ Pilot        │ ─── pure fold ──────▶ │ headless.run -> frames       │  L5
 └──────────────┘                       ├──────────────────────────────┤
                                        │ aspects.audit (17, fail-closed)│ L0
                                        │ fprime.component/dictionary  │  L6
                                        │ ontology.graph (fidelity)    │  L8
                                        └──────────────────────────────┘
```

## 3. Module map

| Module | Lines | Responsibility | Laws / invariants tested |
|---|---:|---|---|
| `geometry` | 129 | Size, Offset, Region, splits | intersection idempotent & commutative; union commutative & absorbing |
| `style` | 173 | Color, Style, SGR | combine associative with `none` identity; SGR well-formed |
| `segment` | 199 | Segment, Strip, cell widths | crop ≤ width; fit == width; CJK width 2; ZWSP/combining width 0 |
| `frame` | 152 | Frame, blit, normalise | every line == width, lines == height, under random blits |
| `layout` | 122 | Scalar, resolve, arrange, grid | sizes sum to total when a Fraction exists; never negative |
| `event` | 232 | Key, Event, escape-sequence parser | total; fuzz never crashes; ≤ one key per grapheme |
| `widget` | 292 | 17-kind widget tree, focus chain, texts | pre-order traversal; focusables |
| `render` | 413 | Compositor, theme, per-widget line renderers | well-formed at any size 0..60×0..30 |
| `app` | 331 | App/Screen/State/Effect, pure `step`, focus & input handling | determinism; stack never empties |
| `headless` | 60 | Pilot: scripted events → frames, tasks run inline | bounded settle (64) |
| `live` | 200 | OTP actor driver, reader, ticker, raw mode, child spec | frame micros telemetry |
| `aspects` | 262 | 17-aspect fail-closed audit | cockpit: 12 Pass, 5 Declared, 0 Fail; empty context: 16 Fail |
| `fprime` | 300 | F´ component, instance, validate, dictionary JSON | unique ids, base 0x2000 outside DMC agent window |
| `ontology` | 176 | Fractal Textual ontology graph | validate: no dangling edges; every layer L0..L8 populated |
| `cockpit` | 366 | Reference UOS cockpit app | BDD: confirm → Intent, cancel → nothing |

## 4. Runtime contract

1. `app.step(state, event)` is pure. The live driver and the headless pilot share it, so every interactive behavior is testable without a terminal.
2. Focused widgets consume keys before app bindings. Typing `r` into the command Input never triggers the restart binding.
3. Destructive verbs never mutate the model's world state. They push a confirm screen; confirmation appends an `Intent(verb, target, epoch)` and emits telemetry. Execution belongs to policy (Rocha cut, C8).
4. Raw mode uses `shell:start_interactive({noshell, raw})` and size uses `io:columns/rows`; both are Result-typed with a fallback size, so non-tty callers (Wisp, MCP, tests) use `live.snapshot_text` or `headless.run`.
5. `live.child_spec` returns an OTP `ChildSpecification` so the driver can be a child of `uos_sup` (aspect 4 requires the driver to report `supervised: True`).

## 5. Widget catalog and C1-C8

Static, Header, Footer, Button, Input, DataTable, Tree, ListView, ProgressBar, Sparkline, Tabs, Log, Rule, Container, Grid, Checklist, StatusBar. C1 structure (Header/Footer/Container/Grid), C2 health (StatusBar/ProgressBar), C3 grids (DataTable), C4 timeline (Log/Sparkline), C5 interactive (Input/Tabs/ListView/Tree/Checklist/Button), C6 dark cockpit (`cockpit.Mode`), C7 advisory (MAX port), C8 interlock (confirm screen + Intent).

## 6. F´ binding and dictionary

Component `UosTui` (Active), instance `uosTui` at base id `0x2000` (span 64, outside the agent DMC window `[0x1000, 0x1400)`). 18 ports (6 engine telemetry inputs, key input, cmd/intent outputs, 9 special ports), 6 commands, 7 events, 7 channels, 3 parameters. Generated dictionary: `generated/20260906-2123-uos-tui-fprime-ground-dictionary.json` (`gleam run -- dictionary`). Field names mirror `cepaf_gleam/fpp/domain.gleam`; a path-dependency adapter is a follow-on (see §9).

## 7. Test matrix (116 tests, 14 modules)

| Modality | Where | Count |
|---|---|---:|
| Unit | geometry, style, segment, layout, event, frame, render, widget-level | 52 |
| System (headless pilot) | app_test | 14 |
| BDD | cockpit_test (Given/When/Then scenarios) | 9 |
| Property | geometry, style, segment, layout (200–300 seeds each) | 5 |
| Fuzz | event_test (500 random byte strings) | 1 |
| Chaos | frame_test, render_test, cockpit_test (random sizes incl. 0×0, random keys) | 3 |
| Scalability | cockpit_test (5,000-row table) | 1 |
| Performance | perf_test (200 frames at 120×40 under 16ms each) | 1 |
| Formal binding | aspects_test, fprime_test, ontology_test | 30 |

TDD: every renderer and reducer was written against the failing test first in this session's history; the suite was red at 4 failures before the final fixes.

## 8. Commands

```bash
cd apps/uos_tui && gleam test              # 116 passed
cd apps/uos_tui && gleam run               # live cockpit (raw mode, alt screen, q quits)
cd apps/uos_tui && gleam run -- snapshot   # one 120x40 frame as text (non-tty callers)
cd apps/uos_tui && gleam run -- dictionary # F´ ground dictionary JSON
```

## 9. Remaining gaps

- **P1** Path dependency from `cepaf_gleam` to `uos_tui` and an adapter to `fpp/domain.Component` (blocked on cepaf's pinned stdlib 0.71 vs uos_tui's resolved 1.0.5).
- **P1** Wisp route at `:4100/tui` serving `live.snapshot_text` and a `tools/uos tui` subcommand replacing the bash launcher.
- **P2** Live data sources: the reference cockpit's containers, telemetry and lease epoch are supplied by the caller; no Podman, Zenoh or Sa-Plan bridge is wired here.
- **P2** Textual features deferred: command palette fuzzy search, Markdown/TextArea, mouse, dirty-region diffing.
- **P3** Hermes two-key evidence record and tri-sovereign review before `verified`/`admitted`.
