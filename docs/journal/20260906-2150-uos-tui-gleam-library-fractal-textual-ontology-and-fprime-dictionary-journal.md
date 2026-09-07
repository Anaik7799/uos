# 20260906-2150- uos_tui Gleam TUI Library, Fractal Textual Ontology, Textual Applications Review & F´ Dictionary Journal
#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #zero-muda #tailscale-web #km-triad #uos-tui #textual-reference #zk-adr

- **Journal Identifier**: `JRN-20260906-2150-UOS-TUI`
- **Timestamp**: `20260906-2150-`
- **Author**: Claude Fable 5.1 (session 01B9GiR9bF4d1Jv2aSMowAKC)
- **Status**: Built, executed, passed. NOT verified, NOT admitted.
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260906-2150-uos-tui-gleam-library-fractal-textual-ontology-and-fprime-dictionary-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260906-2150-uos-tui-gleam-library-fractal-textual-ontology-and-fprime-dictionary-journal.md)
- **Transclusions**: `[[zk:20260906-2150-adr-061-uos-tui-gleam-library-textual-reference]]` `[[wiki:20260906-2150-uos-fractal-textual-ontology-wiki]]` `[[wiki:20260906-2150-textual-applications-review-and-uos-tui-lessons-wiki]]` `[[zk:20260906-2048-adr-060-sysadmin-remote-tui-cockpit-architecture]]`
- **Concurrent specification (not verified here)**: `docs/design/20260906-2150-uos-tui-fractal-aspect-denotational-algebraic-design-and-scenarios.md` was written by Antigravity/Gemini at the same minute and covers a TUI fractal-aspect algebra independently of this package; its "RATIFIED & FORMALLY PROVEN" status is that document's own claim.
- **Scale**: Major (24 files created, 2 modified)

## Comprehensive Verification Checklist (SC-CHECKLIST-001)

<details><summary><strong>18 checkpoints (honest status)</strong></summary>

| ID | Status | Evidence |
|---|---|---|
| CHK-01-TIME | PASS | all 5 new docs and the dictionary carry `YYYYMMDD-HHSS-` |
| CHK-02-TAIL | PASS | FQDN in every doc header and in the cockpit status bar (aspect 14 test) |
| CHK-03-FRACT | PASS | tags declared; ontology assigns L0..L8 |
| CHK-04-KM | PASS | transclusions in docs and on screen (aspect 16 test) |
| CHK-05-MUDA | PASS | deps: gleam_stdlib, gleam_erlang, gleam_otp, gleam_json, argv |
| CHK-06-GRAPH | PASS | 0 NIFs; 6 pure-Erlang externals |
| CHK-07-DRIVE | PASS | serial is an F´ parameter, status field, aspect 1 |
| CHK-08-C1C8 | PASS | catalog covers C1..C8 (design §5) |
| CHK-09-MATH | NOT MEASURED | no entropy/CCM/ITQS run for this package |
| CHK-10-9MOD | PASS | 9 modalities present, 116/116 green |
| CHK-11-REGR | N/A | no UI regression suite targets this package yet |
| CHK-12-GLEAM | PASS | `live.child_spec` OTP worker spec |
| CHK-13-HERMES | DECLARED | port only; no ledger write |
| CHK-14-ZIGVM | DECLARED | port only |
| CHK-15-MAX | DECLARED | port only |
| CHK-16-OTEL | PARTIAL | FrameMicros/FrameCount channels; no trace_id/span_id yet |
| CHK-17-SOV | PENDING | single-agent authorship |
| CHK-18-JJ | PASS | standalone `.jj/` working copy, no git mutation commands |

</details>

---

## 1. Scope & Trigger

Operator directive: "create gleam tui library using textual tui as a reference using 17 aspect system and fprime gleam, create fractal textual ontology, review some key applications built using textual and dictionary". Preceded in the same session by a 17-aspect review of the existing `ui/tui` layer (10 of 17 failed) and by a correction that `teashop` is not a published library. Scope: a new package, its tests, a typed ontology, an applications review, an F´ ground dictionary, and this journal. Out of scope by decision: modifying `cepaf_gleam`, deleting the legacy renderers or the bash launcher.

## 2. Pre-State Assessment

- Existing TUI: 54 modules / 6,563 lines of ANSI string renderers, 0 runtime importers, launcher `tools/tui` (bash, 440 lines) at 1.16s and 82MB per frame, 4 test modules (230 tests, presence checks).
- Toolchain: Gleam 1.16.0, `erl` on PATH is OTP 27 (docs state OTP 29), `shell:start_interactive/1` exported, `io:columns` returns `enotsup` off-tty.
- 17-aspect definition: wiki 20260906-1730 (EV-24). F´ types: `cepaf_gleam/fpp/domain.gleam`. Textual: GitHub README (37,160 stars) and 12 applications via the GitHub API.

## 3. Execution Detail

### 3.1 Wave 1: foundation algebra (geometry, style, segment)
Half-open regions with intersection/union; typed styles with an associative `combine`; strips with grapheme- and East-Asian-width-aware `crop`/`extend`/`fit`. Compiled clean on first build.

### 3.2 Wave 2: frame, layout, events
Frame blit with clipping to both region and frame; Textual-order scalar resolution (Cells, Percent, Auto, Fraction remainder to last fr); total escape-sequence parser (CSI, SS3, tilde, control bytes).

### 3.3 Wave 3: widget catalog and compositor
17 widget families as one closed sum type; per-widget line renderers; scroll-to-cursor for tables, lists and trees; hard wrap for Static; border with title.

### 3.4 Wave 4: application core and drivers
TEA `App`/`Screen`/`State`/`Effect`; pure `step` with widget-first key routing, focus chain, input editing, paste; headless pilot with bounded task settling; OTP live driver with reader and ticker processes, raw mode via pure Erlang, alt-screen enter/restore, `child_spec`.

### 3.5 Wave 5: UOS bindings
`aspects.audit` (17 fail-closed checks with a `Declared` rung), `fprime` component + validate + dictionary JSON, `ontology` graph (38 concepts, 18 edges, fidelity ladder), `cockpit` reference app with confirm screen and Intent emission.

### 3.6 Wave 6: tests and docs
14 test modules, 116 tests; design doc, ADR-061, two wikis, MOC registration, apps README, generated dictionary.

## 4. Root Cause Analysis

Why did the previous TUI fail 10 aspects? Because it was authored as renderers first and never given a runtime, so nothing forced state, input, size or effects to be modelled. Why no runtime? The C3I port copied 51 of 53 files byte-for-byte and stopped at "Phase 3: Spectre parity" unchecked. Why did docs claim admission anyway? Contract IDs (`SC-GLM-UI-*`) exist only in a skill file, not in `contracts/`, so no gate could check them. Why did the launcher end up in bash? Because there was no OTP driver to call. Why is that acceptable now? It is not; this package supplies the driver and the audit that would have caught each gap.

## 5. Fix Taxonomy

- **Pure-core/impure-shell**: one `step` shared by live and headless drivers.
- **Fail-closed audit with a Declared rung**: dictionary-level evidence can never masquerade as runtime evidence.
- **Invariant-by-construction**: `frame.normalise` guarantees width/height after every compose.
- **Intent emission instead of execution**: confirm screen + `Intent` record + telemetry.
- **Total parsers**: unknown sequences become `Unknown(String)` rather than crashes.

## 6. Patterns & Anti-Patterns Discovered

- DO keep widget state in the model; Textual's per-widget reactive state does not survive translation to a closed sum type without a runtime-side state map, and the model is simpler.
- DO route keys to the focused widget before app bindings; otherwise a global `r` binding fires while typing.
- AVOID `list.range` under gleam_stdlib 1.x (removed); use `int.range` or a local helper.
- AVOID calling functions in case guards (Gleam forbids it); bind first.
- AVOID claiming a library from memory: teashop was never on Hex; shore exists but the operator excluded it.

## 7. Verification Matrix

| Check | Command | Result |
|---|---|---|
| Build | `gleam build` | 0 warnings, 0 errors |
| Format | `gleam format` | clean |
| Tests | `gleam test` | 116 passed, no failures |
| Snapshot | `gleam run -- snapshot` | 40 lines at 120 columns, status bar intact |
| Dictionary | `gleam run -- dictionary` | valid JSON: 18 ports, 6 commands, 7 events, 7 channels, 3 params |
| Aspect audit (cockpit) | `cockpit_test` | 12 Pass, 5 Declared, 0 Fail |
| Aspect audit (empty ctx) | `aspects_test` | 16 Fail, 1 Pass (fail-closed confirmed) |
| Performance | `perf_test` | 200 frames at 120×40 under 16ms each |
| Live terminal | not run | session has no tty; `io:columns` returned `enotsup` |

## 8. Files Modified

| File | Delta | Note |
|---|---|---|
| `apps/uos_tui/gleam.toml` | NEW | package manifest |
| `apps/uos_tui/src/uos_tui.gleam` | NEW | entry: live / snapshot / dictionary |
| `apps/uos_tui/src/uos_tui_ffi.erl` | NEW 40 | pure-Erlang shim |
| `apps/uos_tui/src/uos_tui/{geometry,style,segment,frame,layout,event,widget,render,app,headless,live,aspects,fprime,ontology,cockpit}.gleam` | NEW 15 modules, ~4,300 lines | library |
| `apps/uos_tui/test/{prng,geometry,style,segment,layout,event,frame,render,app,cockpit,aspects,fprime,ontology,perf,uos_tui}_test.gleam` | NEW 15 files, 1,459 lines | 116 tests |
| `generated/20260906-2123-uos-tui-fprime-ground-dictionary.json` | NEW | F´ ground dictionary |
| `docs/design/20260906-2150-uos-tui-gleam-library-textual-reference-design.md` | NEW | design spec |
| `docs/zk/20260906-2150-adr-061-uos-tui-gleam-library-textual-reference.md` | NEW | ADR-061 |
| `docs/wiki/20260906-2150-uos-fractal-textual-ontology-wiki.md` | NEW | generated ontology table |
| `docs/wiki/20260906-2150-textual-applications-review-and-uos-tui-lessons-wiki.md` | NEW | 12-app review |
| `docs/zk/20260905-1801-moc-uos-unified-master.md` | +1 line | ADR-061 registered |
| `apps/README.md` | +4 lines | uos_tui entry |

## 9. Architectural Observations

```text
        events ──▶ app.step (pure) ──▶ State ──▶ render.compose ──▶ Frame ──▶ to_ansi / to_text
                       │                                   ▲
                       └── Effect ──▶ live (OTP) / headless ┘        aspects.audit(view, ctx) ──▶ 17 Findings
                                          │
                                          └── Task ──▶ BEAM process ──▶ Dispatch(msg)
```
The audit sits beside the render path, not inside it, so a failing aspect never changes what is drawn; it changes whether the screen is admissible. The F´ dictionary is the only place engine names appear, which keeps the widget layer free of engine coupling.

## 10. Remaining Gaps

- **P1** cepaf_gleam path dependency and `fpp/domain.Component` adapter (stdlib pin conflict).
- **P1** Wisp `/tui` route and `tools/uos tui` subcommand; retire the bash launcher.
- **P2** Live data bridges (Podman, Zenoh, Sa-Plan lease epoch) for the reference cockpit.
- **P2** trace_id/span_id on telemetry (CHK-16), math gates (CHK-09).
- **P3** Hermes two-key record, tri-sovereign review, `tools/uos doctor` boundary.

## 11. Metrics Summary

| Metric | Before | After |
|---|---|---|
| TUI runtime | bash loop, 1.16s/frame | OTP actor, <16ms/frame (headless measurement) |
| Widget families | 12 string helpers | 17 typed widgets |
| Input handling | none in Gleam | total parser, focus chain, input editing |
| Aspects passing (default screen) | 1 Pass / 6 Partial / 10 Fail | 12 Pass / 5 Declared / 0 Fail |
| Tests | 230 presence checks | 116 behavioral incl. property/fuzz/chaos/perf |
| `let assert` / `panic` in src | n/a | 0 |

## 12. STAMP & Constitutional Alignment

- **SC-MUDA-001**: no Bevy, Graphite, NIF or Python; Textual is a reference document only.
- **SC-CHECKLIST-001 / G-CHECKLIST**: Checklist widget mounted on the reference screen; aspect 15 enforces 5/18.
- **SC-TAILSCALE-WEB-001**: FQDN in status bar and in every document.
- **SC-FPP-INTENT-001 / Rocha cut**: `intent_out` only; no execution path exists in the package.
- **SC-TIME-001**: all generated files prefixed; host clock verified by chrony (0.0001s offset).
- **Evidence semantics (§6 policy)**: state is `passed`; this journal makes no `verified` or `admitted` claim.

## 13. Conclusion

The package delivers what the directive asked for: a Gleam TUI library shaped by Textual's architecture, bound to the 17 aspects through a fail-closed audit, expressed as an F´ component with a generated dictionary, documented by a typed fractal ontology, and informed by twelve real Textual applications. Everything interactive runs through one pure step function, which is why 116 tests can cover input, focus, screens, effects, sizes down to zero, and random key soup without a terminal.

Two honest limits remain. The live driver has not been exercised on a real tty in this session, and the reference cockpit carries no live data bridges. Both are P1 follow-ons listed above, and neither is hidden behind a green badge.
