# ADR-061: uos_tui Pure-Gleam Terminal UI Library with Textual Reference, F´ Binding and 17-Aspect Audit

- **Status**: Proposed (built, executed, passed; awaiting two-key verification and tri-sovereign review)
- **Date**: 2026-09-06
- **Timestamp**: `20260906-2150-`
- **Deciders**: Claude Fable 5.1 (author); AGY and Codex review pending
- **Consulted**: Textualize/textual (reference architecture), `cepaf_gleam/fpp/domain.gleam` (F´ types), wiki 20260906-1730 (17 aspects)
- **Informed**: Operator, remote system administrators
- **Governing Design**: [`DESIGN-UOS-TUI-001`](file:///home/an/NAS-setup/uos/docs/design/20260906-2150-uos-tui-gleam-library-textual-reference-design.md)
- **Tailscale Web Link**: [`http://nas-1.tail55d152.ts.net:4100/zk/20260906-2150-adr-061-uos-tui-gleam-library-textual-reference.md`](http://nas-1.tail55d152.ts.net:4100/zk/20260906-2150-adr-061-uos-tui-gleam-library-textual-reference.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l8`
- **Knowledge Tags**: `#zk-adr` `#uos-tui` `#textual-reference` `#km-triad` `#zero-muda` `#checklist-nav` `#tailscale-web` `#fprime-agents`
- **Transclusions**: `[[wiki:20260906-2150-uos-fractal-textual-ontology-wiki]]` `[[wiki:20260906-2150-textual-applications-review-and-uos-tui-lessons-wiki]]` `[[zk:20260906-2048-adr-060-sysadmin-remote-tui-cockpit-architecture]]` `[[zk:20260905-1801-moc-uos-unified-master]]`

---

## Context

ADR-060 ratified a sysadmin TUI whose runtime is a bash loop booting one BEAM per keypress, whose model is literal data, and whose container actions mutate a status string without any effect. A 17-aspect review on 2026-09-06 found 10 failures and no runtime consumer of the 54 renderer modules. The operator directed a new Gleam TUI library using Textual as the reference, bound to the 17-aspect system and to F´ Gleam.

## Decision

1. Create `apps/uos_tui` as a standalone Gleam package (15 modules, 4,408 lines of Gleam and Erlang, 116 tests) that realises Textual's App/Screen/Widget/Compositor/Strip/Binding/Worker/Pilot concepts as The Elm Architecture on OTP.
2. Keep all state in the model; widgets are data; `app.step` is pure and shared by the live OTP driver and the headless pilot.
3. Bind the library to the 17 aspects through `aspects.audit`, a fail-closed structural check over the composed screen plus driver context; `Declared` is distinct from `Pass` and never counts as evidence of runtime behavior.
4. Model the TUI as an F´ `Active` component with a generated ground dictionary at base id `0x2000`, emitting `Intent` values on `intent_out` and executing nothing (Rocha cut).
5. Publish the Textual-to-uos_tui mapping as a typed ontology graph with a fidelity ladder, validated by tests and rendered into the wiki.
6. Leave `apps/cepaf_gleam/src/cepaf_gleam/ui/tui/` and `tools/tui` untouched as read-only evidence; they are superseded, not deleted (exclusion provenance rule).

## Consequences

- Positive: interactive behavior is testable without a terminal; every frame is well-formed by construction; destructive actions cannot bypass the confirm screen; the aspect audit turns policy into a machine check.
- Negative: two dependency graphs (cepaf pins stdlib 0.71, uos_tui resolves 1.0.5) block a path dependency until cepaf is bumped; the reference cockpit has no live data bridges yet; Textual's command palette, Markdown and mouse are deferred.
- Evidence state after this ADR: `passed`. Promotion to `verified` requires a Hermes two-key record; to `admitted` requires tri-sovereign ratification and a `tools/uos doctor` boundary.
