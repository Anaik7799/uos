# 20260907-1559 — ADR: one risk prioritization policy across UOS

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Source](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20260907-1559-adr-risk-prioritization.md) · [SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1559-risk-prioritization-guide.md) · [ADR](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1559-adr-risk-prioritization.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1559-risk-prioritization-journal.md)

Created: 2026-09-07T15:58:59Z. Process guidance; no production admission claim.

**Decision:** use one repository-owned SOP for all SDLC, SRE and agentic selection.
Apply authority/safety constraints and dependency readiness before C × T × F × Dep × I.
Preserve raw STPA and FMEA analysis, uncertainty and decision history.
Use local skill/plugin bindings rather than modifying externally linked source skills.

**Context:** selection guidance was split across imported skills and process documents.
The inspected Sa-plan adapter stores six legacy factors and free-form rationale, has no impact column,
and appends selection evidence without changing queue priority. Process requirements therefore exceed current runtime enforcement.

**Alternatives considered:** a standalone Markdown backlog would split authority; global plugin hooks could
affect unrelated sessions; importing whole skill trees would duplicate moving external sources.
The chosen policy is explicit, local and compatible with exact-task Sa-plan claiming.

**Consequences:** all relevant agent entry points read the same method; validators can expose malformed
records and dependency/ranking errors; runtime authority and independent admission remain separate.
Severity, recurrence and detection retain separate inputs. RPN is ordinal, and score multiplication is a
local heuristic rather than a probability model.

**Verification status:** see the journal for actual local checks. Independent agent behavior,
automatic scheduler enforcement and production adoption remain unverified.

[[wiki:20260907-1559-risk-prioritization-guide]]

## Comprehensive verification checklist

This is a process/document package. The entries below do not assert production conformance.
UNRUN and NOT_ADMITTED remain nonpassing; N/A must be justified for each actual change.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host timestamp recorded.
- [x] CHK-02-TAIL — Full Tailscale FQDN references provided; live delivery unverified.
- [x] CHK-03-FRACT — L0–L9 applicability tagged.
- [x] CHK-04-KM — SOP, wiki, ADR and journal linked in this package.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] CHK-05-MUDA — Fleet dependency exclusion scan UNRUN.
- [ ] CHK-06-GRAPH — Runtime language/NIF conformance UNRUN.
- [ ] CHK-07-DRIVE — OS storage interlock execution UNRUN.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI categories UNRUN.
- [ ] CHK-09-MATH — Mathematical quality gates UNRUN.
- [ ] CHK-10-9MOD — Nine runtime test modalities UNRUN.
- [ ] CHK-11-REGR — Live UI regression monitoring UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Production supervision/fencing checks UNRUN.
- [ ] CHK-13-HERMES — Mandatory scheduler enforcement NOT_IMPLEMENTED by this package.
- [ ] CHK-14-ZIGVM — Runtime kernel checks UNRUN.
- [ ] CHK-15-MAX — Actual inference checks UNRUN.
- [ ] CHK-16-OTEL — Runtime telemetry correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review/admission NOT_ADMITTED.
- [x] CHK-18-JJ — No native Git command or integration/VCS mutation used for this package.

</details>

**UOS footer:** authored policy decision; no blanket runtime or mathematical admission.

