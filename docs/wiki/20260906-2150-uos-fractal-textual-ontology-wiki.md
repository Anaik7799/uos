# 20260906-2150- UOS Fractal Textual Ontology (Textual → uos_tui across L0..L9)
#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #km-triad #zero-muda #tailscale-web #textual-reference #uos-tui #zk-adr

- **Wiki Identifier**: `WKI-20260906-2150-FRACTAL-TEXTUAL-ONTOLOGY`
- **Timestamp**: `20260906-2150-`
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260906-2150-uos-fractal-textual-ontology-wiki.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260906-2150-uos-fractal-textual-ontology-wiki.md)
- **Source of truth**: `apps/uos_tui/src/uos_tui/ontology.gleam` (typed graph; this table is `ontology.to_markdown(ontology.graph())` output, validated by `ontology_test`)
- **Transclusions**: `[[wiki:20260906-2150-textual-applications-review-and-uos-tui-lessons-wiki]]` `[[zk:20260906-2150-adr-061-uos-tui-gleam-library-textual-reference]]` `[[wiki:20260906-0955-uos-fprime-agent-ecosystem-and-taxonomy]]` `[[wiki:20260906-1730-uos-omni-fractal-matrix-and-17-aspect-wiki]]` `[[zk:20260905-1801-moc-uos-unified-master]]`
- **Graph shape**: same node/edge form as `cepaf_gleam/fpp/ontology.gleam` (`OntoNode`/`OntoEdge`), so both graphs merge into the C3I living ontology.

---

## Comprehensive Verification Checklist (SC-CHECKLIST-001)

<details><summary><strong>18 checkpoints</strong></summary>

- [x] CHK-01-TIME `20260906-2150-` prefix
- [x] CHK-02-TAIL Tailscale FQDN link above
- [x] CHK-03-FRACT every concept carries an explicit L0..L9 coordinate
- [x] CHK-04-KM transclusions declared; graph validated by `ontology.validate`
- [x] CHK-05-MUDA 0 Bevy, 0 Graphite, 0 Python (Textual is reference only)
- [x] CHK-06-GRAPH 0 NIFs in `apps/uos_tui` (6 pure-Erlang externals in `live.gleam`)
- [x] CHK-07-DRIVE serial `25503L801736` is an F´ parameter and a status-bar field
- [x] CHK-08-C1C8 mapped in the applications review wiki
- [x] CHK-09-MATH declared, not claimed, for this document
- [x] CHK-10-9MOD 116 tests across 14 modules (unit, BDD, property, fuzz, chaos, scalability, performance)
- [x] CHK-11-REGR n/a
- [x] CHK-12-GLEAM `live.child_spec` hands the driver to `uos_sup`
- [x] CHK-13-HERMES `hermes_evidence_in` port declared
- [x] CHK-14-ZIGVM `zigvm_tlm_in` port declared
- [x] CHK-15-MAX `max_inference_in` port declared
- [x] CHK-16-OTEL `FrameMicros`, `FrameCount` channels
- [x] CHK-17-SOV pending tri-sovereign review
- [x] CHK-18-JJ authored in the standalone `.jj/` working copy

</details>

---

## 1. Fidelity ladder

Each Textual concept is placed on a four-rung ladder that doubles as the evolution path (`#fractal-l8`): **Deferred → Reinterpreted → Homomorphic → Isomorphic**.

| Rung | Meaning | Count |
|---|---|---:|
| Isomorphic | Same shape and same laws in Gleam | 18 |
| Homomorphic | Structure preserved, some capabilities narrowed | 12 |
| Reinterpreted | Different mechanism serving the same purpose, or UOS-only | 6 |
| Deferred | Named, not built | 2 |

## 2. Concept table (generated)

| Textual concept | Textual locus | uos_tui | Layer | Fidelity | Note |
|---|---|---|---|---|---|
| App | `textual.app.App` | `uos_tui/app.App` | #fractal-l4 | Homomorphic | class with compose() becomes a record of init/update/screens; reactivity is TEA re-render |
| Screen | `textual.screen.Screen` | `uos_tui/app.Screen` | #fractal-l4 | Isomorphic | named view over the model; push/pop via PushScreen/PopScreen effects |
| Widget | `textual.widget.Widget` | `uos_tui/widget.Widget(msg)` | #fractal-l2 | Homomorphic | class hierarchy becomes one closed sum type; state lives in the model |
| DOM | `textual.dom.DOMNode` | `uos_tui/widget.flatten/find/children` | #fractal-l2 | Isomorphic | pre-order tree with ids |
| compose() | `Widget.compose` | `uos_tui/app.Screen.view` | #fractal-l2 | Isomorphic | pure function model -> tree |
| TCSS | `textual.css` | `uos_tui/style.Style` | #fractal-l1 | Reinterpreted | no CSS parser; typed style records with a combine monoid |
| Scalar / fr units | `textual.css.scalar` | `uos_tui/layout.Scalar` | #fractal-l1 | Isomorphic | Cells, Fraction, Percent, Auto |
| Vertical/Horizontal/Grid | `textual.layouts` | `uos_tui/layout.arrange/grid` | #fractal-l2 | Isomorphic | same resolution order: fixed, percent, auto, fraction |
| Region/Size/Offset | `textual.geometry` | `uos_tui/geometry.Region` | #fractal-l1 | Isomorphic | half-open rectangles with intersection/union laws |
| Segment / Strip | `rich.segment / textual.strip` | `uos_tui/segment.Strip` | #fractal-l1 | Isomorphic | styled runs with cached cell length; crop/extend/simplify |
| Compositor | `textual._compositor` | `uos_tui/render.compose/arrange` | #fractal-l3 | Homomorphic | placements blitted into a frame; no dirty-region diffing yet |
| reactive | `textual.reactive` | `uos_tui/app.update -> render` | #fractal-l3 | Reinterpreted | every message re-renders; watchers become update clauses |
| Message / Event | `textual.message / textual.events` | `uos_tui/event.Event, msg` | #fractal-l3 | Homomorphic | system events typed; widget messages are user-typed msg |
| Binding / action | `textual.binding.Binding` | `uos_tui/widget.Binding(msg)` | #fractal-l3 | Isomorphic | key -> msg with description shown in Footer |
| Focus chain | `textual.screen.focus_chain` | `uos_tui/app.move_focus` | #fractal-l3 | Isomorphic | document-order Tab/Shift-Tab |
| Worker | `textual.worker` | `uos_tui/app + uos_tui/live.Effect.Task` | #fractal-l4 | Homomorphic | task functions run in BEAM processes by the live driver |
| Driver | `textual.driver` | `uos_tui/live.run/child_spec` | #fractal-l4 | Homomorphic | OTP actor + reader process; raw mode via pure Erlang shell API |
| Pilot / run_test | `textual.pilot.Pilot` | `uos_tui/headless.run` | #fractal-l5 | Isomorphic | scripted events, captured frames |
| Command palette | `textual.command` | `uos_tui/cockpit.Input#command` | #fractal-l5 | Deferred | fuzzy palette not implemented; command input only |
| Themes | `textual.theme` | `uos_tui/render.Theme` | #fractal-l1 | Homomorphic | single dark theme plus Dark Cockpit mode overlay |
| Header/Footer | `textual.widgets` | `uos_tui/widget.Header, Footer` | #fractal-l2 | Isomorphic |  |
| Static/Label | `textual.widgets.Static` | `uos_tui/widget.Static` | #fractal-l2 | Isomorphic |  |
| Button | `textual.widgets.Button` | `uos_tui/widget.Button` | #fractal-l2 | Isomorphic |  |
| Input | `textual.widgets.Input` | `uos_tui/widget.Input` | #fractal-l2 | Homomorphic | no validators/suggester |
| DataTable | `textual.widgets.DataTable` | `uos_tui/widget.DataTable` | #fractal-l2 | Homomorphic | row cursor only |
| Tree | `textual.widgets.Tree` | `uos_tui/widget.Tree` | #fractal-l2 | Homomorphic |  |
| ListView | `textual.widgets.ListView` | `uos_tui/widget.ListView` | #fractal-l2 | Isomorphic |  |
| ProgressBar | `textual.widgets.ProgressBar` | `uos_tui/widget.ProgressBar` | #fractal-l2 | Isomorphic |  |
| Sparkline | `textual.widgets.Sparkline` | `uos_tui/widget.Sparkline` | #fractal-l2 | Isomorphic |  |
| Tabs / TabbedContent | `textual.widgets.Tabs` | `uos_tui/widget.Tabs` | #fractal-l2 | Homomorphic | content switching is the model's job |
| RichLog / Log | `textual.widgets.Log` | `uos_tui/widget.Log` | #fractal-l2 | Homomorphic | plain lines, scroll offset |
| Rule | `textual.widgets.Rule` | `uos_tui/widget.Rule` | #fractal-l2 | Isomorphic |  |
| Collapsible | `textual.widgets.Collapsible` | `uos_tui/widget.Checklist` | #fractal-l0 | Reinterpreted | UOS 5-domain/18-item checklist accordion (SC-CHECKLIST-001) |
| Container | `textual.containers` | `uos_tui/widget.Container, Grid` | #fractal-l2 | Isomorphic | border + title like Textual border-title |
| 17 Aspect audit | `(none)` | `uos_tui/aspects.audit` | #fractal-l0 | Reinterpreted | UOS-only: fail-closed structural verification of a composed screen |
| F´ component | `(none)` | `uos_tui/fprime.component/dictionary_json` | #fractal-l6 | Reinterpreted | UOS-only: ports, commands, channels, events, parameters, ground dictionary |
| Textual Web / serve | `textual-serve` | `uos_tui/frame.to_text/to_ansi` | #fractal-l7 | Deferred | projection to Wisp at :4100 is a follow-on |
| Evolution | `(none)` | `uos_tui/ontology.Fidelity` | #fractal-l8 | Reinterpreted | fidelity ladder Deferred -> Reinterpreted -> Homomorphic -> Isomorphic |

## 3. Layer reading

- **L0 Constitutional**: the Checklist accordion and the 17-aspect audit. Nothing renders as admissible unless `aspects.audit` returns zero `Fail`.
- **L1 Atomic**: geometry, style, strip and scalar units. These carry the algebraic laws (intersection idempotent, union commutative, style combine associative, crop never exceeds width) proved by property tests.
- **L2 Component**: the closed `Widget(msg)` sum type and the 17-family catalog.
- **L3 Transaction**: compositor, events, bindings and focus chain. One event, one pure `step`, one frame.
- **L4 System**: `App`, `Screen` stack, the OTP driver and worker tasks.
- **L5 Cognitive**: the headless pilot and the command input.
- **L6 Ecosystem**: the F´ component dictionary that connects the TUI to engines and policy.
- **L7 Federation**: text and ANSI projections that make a Wisp route at `:4100` possible.
- **L8 Evolution**: the fidelity ladder itself.
- **L9 Singularity**: no concept is placed here; the layer is reserved.

## 4. Edges

- App --Composes--> Screen
- Screen --Composes--> Widget
- Widget --Composes--> DOM
- compose() --Composes--> Widget
- TCSS --Styles--> Widget
- Themes --Styles--> Compositor
- Vertical/Horizontal/Grid --Composes--> Region/Size/Offset
- Compositor --Renders--> Segment / Strip
- Compositor --Renders--> Region/Size/Offset
- Message / Event --Dispatches--> App
- Binding / action --Binds--> App
- Focus chain --Binds--> Widget
- Worker --Drives--> Driver
- Driver --Drives--> App
- Pilot / run_test --Drives--> App
- 17 Aspect audit --Audits--> Widget
- F´ component --Declares--> App
- Collapsible --Declares--> 17 Aspect audit
