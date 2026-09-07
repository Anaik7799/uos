# 20260907-2312 — UOS interface quality rules

Created: 2026-09-07T23:30:00Z. #fractal-l0 #fractal-l2 #fractal-l4 #fractal-l7 #fractal-l9 #zk-adr #zero-muda

[Candidate source](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-interface-quality/references/20260907-2312-interface-rules.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-2312-interface-skills-journal.md)

Candidate files are local in this workspace; publication at these URLs is unverified.

Rule set **UOS-UI-QUALITY-001**, version 1.0.0. Applies to GUI/TUI work consuming this local package. No global hook, runtime guard or policy admission is implied. Existing UOS language, authority and scope constraints remain in force.

## Shared — operational truth and control

| ID | Required behavior | Observable acceptance |
|---|---|---|
| UI-R01 | Model data origin (observed, simulated, unavailable), observed-at, received-at and freshness bound. | Expired or missing measurements display STALE/UNKNOWN; a client receive clock cannot renew source freshness. |
| UI-R02 | Distinguish healthy, unhealthy and unknown; fixtures and forecasts are labeled. | Disconnect the source in a controlled fixture; no permanent ONLINE or nominal fallback. |
| UI-R03 | A clicked control emits an intent; only an authorized executor receipt confirms the effect. | Success, rejection, timeout and retry are distinguishable. Stale ownership/permissions are rechecked by the backend at execution. |
| UI-R04 | Share a typed domain projection between GUI, TUI and API while adapting presentation. | Same event history and source state produce consistent meaning, including unknown values and denied actions. |
| UI-R05 | Preserve causal IDs and source sequence; wall time and Lamport order are different measurements. | Duplicate/out-of-order/replayed data does not become fresh evidence. Show clock uncertainty and gaps when relevant. |
| UI-R06 | Keep expensive work outside render/update loops. Bound histories, payloads, refresh rate and subscriptions. | Burst and disconnected-client tests establish limits and cleanup; attach measured evidence before a latency claim. |

No dashboard, inference output, signed-looking string or board ACK grants deployment authority. Publish reviewable decision summaries and evidence references; private model reasoning is not required.

## GUI — Lustre/OTP

Use an operator-centered hierarchy: overview → discrepancy → evidence → authorized action. Preserve the current navigation and visual tokens; measure changes in task completion and error prevention, not decoration. Prefer familiar controls, readable type, aligned labels, meaningful empty states and restrained motion.

Use semantic elements, labels and focus order. For custom widgets, implement the matching keyboard pattern. Review at 320 CSS pixels and representative larger widths, with text zoom/reflow; choose explicit accessible alternatives for genuinely two-dimensional content. Aim for WCAG 2.2 AA: applicable contrast, focus, keyboard, target size and status-message criteria. Automated scans and a screenshot alone do not establish conformance. [W3C WCAG 2.2](https://www.w3.org/TR/2024/REC-WCAG22-20241212/) and [ARIA authoring patterns](https://www.w3.org/WAI/ARIA/apg/).

Separate decoded domain state from transport state. SSE requires the actual HTTP path, UTF-8 event-stream response and event delivery into the client. A named event needs its corresponding listener; onmessage covers unnamed message events. Specify reconnect cursor, duplicate handling, heartbeat and retention behavior. End-of-response reconnects do not make a finite fixture live telemetry. Include stale/error states, subscription cleanup and bounded rows. [WHATWG EventSource](https://html.spec.whatwg.org/multipage/server-sent-events.html).

Render externally supplied text with typed elements/textContent. Avoid concatenating event fields into innerHTML. If rich text is a product requirement, use an approved sanitizer and test the resulting allowlist. Don't expose secrets, privileged controls or cross-tenant data through UI state.

## TUI — Gleam/OTP

| Area | Required design and test |
|---|---|
| Reachability | Verify entrypoint → input → update → render. List dead/unwired views separately from shipped UI. |
| Input | Decode split UTF-8/escape sequences with explicit bounds and timeouts. Provide help; handle unknown keys. Bracketed paste stays data. Negotiate optional keyboard protocols and retain a documented fallback. |
| Layout | Exercise 40×12, 80×24 and 120×40 as starting fixtures; adapt to supported terminals. Keep primary status reachable, retain focus/selection and clear old regions after shrink/expand. |
| Text | Clip by grapheme boundary and terminal cells, not byte count. State ambiguous-width/emoji policy and provide fallback for unsupported glyphs. |
| Escape safety | Escape external ESC/C0/C1 and OSC content; only the renderer emits trusted control sequences. Never reflect clipboard/title/cursor controls from board messages. |
| Accessibility | Provide readable plain output, text status labels and a no-color mode. Respect NO_COLOR by default with documented explicit overrides. Avoid relying on mouse, color, flashing or animation. |
| Lifecycle | Restore modes/cursor on normal exit, EOF, catchable signals and exceptions. Define suspend/resume. Abrupt uncatchable termination cannot promise restoration; document recovery. |
| Performance | Bound event queues/history, decouple telemetry from key input, coalesce repainting and test slow consumers. Avoid one redraw per high-rate event. |

Primary protocol references: [xterm control sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html), [kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/), [Unicode grapheme segmentation](https://unicode.org/reports/tr29/) and [NO_COLOR](https://no-color.org/). Segmentation alone does not define display-cell width.

## Process — scoped Superpowers adaptation

Choose design, planning, debugging, regression testing and evidence review according to the change. For a real behavior defect, write a reproducer that fails for the intended reason before claiming the fix. A reversible text/style edit needs proportionate inspection, not a synthetic test suite.

Record the exact candidate and commands. Compare schema/unit, browser/PTY, deployed runtime and formal evidence separately. A test count or validator exit is never whole-product proof. Record unknowns rather than invent metrics. Use local deterministic checks before a model; use a more capable model only when its expected decision value justifies the authorized cost.

Existing optional skills: lustre-gleam-ui-expert, mobile-first-adaptive-ui, systematic-debugging, test-driven-development, verification-before-completion, writing-plans and using-jj-workspaces. Their global/external copies are not required for this package. Adapt imported environment-specific paths and restrictions only within UOS authority; never copy them as executable policy by default.

## Verification and use

Read the [acceptance scenarios](20260907-2312-acceptance-scenarios.json) before implementation. They cover observed homeostasis failures and adversarial cases. Baseline FAIL is an observed defect or coverage gap; UNTESTED is a proposed check. Neither is evidence of independent agent behavior.

Run `bash tools/ui-skill-check` for package structure and `bash tools/ui-skill-check --selftest` for validator-negative fixtures. These checks are report-only, use OCaml, create bounded temporary build files and do not contact services or agents. They do not run browser/PTY acceptance tests.

Skill discovery uses relative repository-owned links under .agents, .codex, .claude and .gemini. Actual agent-loader activation is unverified until observed in a permitted session. Protocol-mandated SKILL.md links point to timestamped authored documents. No external source file, executable installer, framework dependency or hidden startup hook is imported.

<details><summary>Verification — 5 domains / 18 checkpoints</summary>

Status applies to this guidance package; unchecked means unrun, not passed.

- Domain 1: [x] CHK-01-TIME host time; [x] CHK-02-TAIL FQDN references (publication unverified); [x] CHK-03-FRACT tags; [x] CHK-04-KM local rules and journal.
- Domain 2: [ ] CHK-05-MUDA fleet scan; [ ] CHK-06-GRAPH runtime language conformance; [ ] CHK-07-DRIVE hardware interlock.
- Domain 3: [ ] CHK-08-C1C8 full UI matrix; [ ] CHK-09-MATH mathematical gates; [ ] CHK-10-9MOD nine modalities; [ ] CHK-11-REGR deployed regression.
- Domain 4: [ ] CHK-12-GLEAM supervision; [ ] CHK-13-HERMES independent formal evidence; [ ] CHK-14-ZIGVM kernel; [ ] CHK-15-MAX inference; [ ] CHK-16-OTEL live trace correlation.
- Domain 5: [ ] CHK-17-SOV independent admission; [x] CHK-18-JJ isolated Jujutsu only.

</details>


