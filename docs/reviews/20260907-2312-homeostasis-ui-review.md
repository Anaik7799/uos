# 20260907-2312 — Homeostasis GUI/TUI review

Observed source: **4eab8b7280e13186cca69aecc101ba17d12b0247**, copied into a private verification harness.
Live observations: **2026-09-07T23:27:52Z** and **2026-09-07T23:42:19Z**.
#fractal-l0 #fractal-l2 #fractal-l4 #fractal-l7 #zk-adr #zero-muda

[HUD](http://nas-1.tail55d152.ts.net:4100/homeostasis/evolution) · [Stream](http://nas-1.tail55d152.ts.net:4100/api/v1/homeostasis/stream) · [PID API](http://nas-1.tail55d152.ts.net:4100/api/v1/homeostasis) · [Skill rules](../../plugins/uos-interface-quality/references/20260907-2312-interface-rules.md)

## Verdict

The source contains useful typed models, deterministic transition tests and reusable renderers. The claimed live homeostasis interface is **not verified for production**. Source-generated health, peer status, telemetry and checklist badges are constants or fixtures. Live response inspection also fails the expected page/stream contract. No application source or runtime was modified.

This is an author-performed side-session review, not an independent sovereign admission. The deployed process revision was not attested; live failures and candidate-source findings are separate evidence.

## Prioritized findings

Priorities are provisional review judgments, using the local [risk SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md).
Safety class and dependency eligibility come before the product. S/O/Det are ordinal estimates, not measured failure probabilities. F = max(S, RPN band). No execution work order or peer owner is assigned here.

| Order / class | Finding | C / T / F / Dep / I | S/O/Det; RPN | Product |
|---|---|---|---|---|
| 1 / P1 | HUI-01 — False health, peer and verification labels | 5/5/5/5/5 | 5/3/4; 60 | 3125 |
| 2 / P1 | HUI-02 — Live page and stream fail their contracts | 4/4/4/5/5 | 4/3/3; 36 | 1600 |
| 3 / P1 | HUI-03 — Event fields flow into unsafe HTML insertion | 4/4/4/4/4 | 4/2/3; 24 | 1024 |
| 4 / P2 | HUI-04 — Named SSE events lack matching browser handlers | 3/3/3/4/4 | 3/3/3; 27 | 432 |
| 5 / P2 | HUI-05 — TUI renderers lack demonstrated application wiring | 3/3/3/3/4 | 3/3/3; 27 | 324 |
| 6 / P2 | HUI-06 — UI checks do not test interaction, bounds or live behavior | 3/3/3/2/3 | 3/3/3; 27 | 162 |

C reflects consequence to operator decisions; T reflects unsafe feedback/control exposure; Dep reflects downstream integration work; I reflects affected operational surfaces. HUI-01 precedes exposing more purportedly live data. Source/fixture checks for HUI-02 can run now, but production exposure depends on HUI-01, HUI-03 and HUI-04. HUI-06 tests are acceptance prerequisites for each relevant repair rather than a reason to defer all testing.

### HUI-01: healthy/verified status is not bound to observations

- [SSE generator](../../apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/agui_sse_api.gleam), lines 204–243: seven fixed payloads include watchdog freshness 45ms, RATIFIED, 4/4 votes and nominal physiology.
- [HUD](../../apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/homeostasis_evolution_hud.gleam), lines 211–228 and 417–444: all four peers are unconditionally ONLINE, and 18 checkpoints are presented as validated without a receipt argument.
- [Evolution TUI](../../apps/cepaf_gleam/src/cepaf_gleam/ui/tui/homeostasis_evolution_view.gleam), lines 150–160: every peer is ONLINE even when rendering a newly initialized model with no peer observations.
- [Sysadmin TUI](../../apps/cepaf_gleam/src/cepaf_gleam/ui/tui/sysadmin_cockpit.gleam), lines 529–548: fixed service health, old refresh time, initial physiology and example board claims. Its stop/start/GC helpers at 686–733 change only the model but report completed effects.
- [Router](../../apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam), lines 2378–2420: PID and evolution APIs return literal healthy values. HUD construction at 4522 uses initial state, not an observed stream state.

A fresh executable probe rendered ONLINE from init(0). Two independent generator calls returned identical seven-event streams. These are executable fixture properties, not evidence of healthy peers. Use observed/simulated/unavailable origins, freshness expiry and receipt-backed actions; keep model tests, but label their semantics.

### HUI-02: HTTP 200 is concealing missing functionality

At 23:42:19Z:
- Stream: status 200, application/json, 21 bytes, body `{"error":"not_found"}`.
- HUD: status 200, text/html, 36,238 bytes, generic master cockpit title; none of the candidate HUD's three distinctive markers appeared.
- PID API: status 200, application/json, 196 bytes, fixed healthy values identical to the literal source model.

The earlier stream observation showed the same missing route. Verify the actual serving revision and ingress dispatch. Assert expected page markers, semantic response and actual event delivery. A HEAD request or raw 200 does not establish a functioning page.

### HUI-03: the prospective live handler creates an injection sink

HUD line 410 concatenates event-derived subsystem, level and message into `tr.innerHTML`. The initial server-rendered rows use escaped text, but the dynamic path does not. Use text nodes/typed rendering for these fields; test hostile markup in an isolated browser fixture before connecting untrusted events. **No exploit or browser execution was attempted**, and the live route currently fails earlier.

### HUI-04: SSE producer and consumer disagree

The generator emits named `event:` fields, while HUD line 410 registers only `src.onmessage`. EventSource dispatches named events to their corresponding listeners. The same handler has no observable disconnect/stale state and replaces observation time with a client receive timestamp. Even after route repair, these frames will not update this handler as designed. [WHATWG EventSource](https://html.spec.whatwg.org/multipage/server-sent-events.html).

### HUI-05: page labels and pure renderers do not establish a running TUI

Reviewed all dedicated homeostasis terminal views plus the generic and sysadmin renderers:
- `homeostasis_evolution_view`: no application caller found in the inspected apps' Gleam source.
- `homeostasis_view`: referenced by a rendering test, no application caller found.
- `sysadmin_cockpit`: tested pure model/render functions; no runtime application caller found in the inspected Gleam source.
- Generic `renderer.render_frame`: prints Homeostasis in navigation; it does not dispatch its page view.

A foreign/dynamic launcher could exist outside this static search, so this is a wiring/evidence gap rather than proof that no launcher can exist. Produce the actual entrypoint and a private PTY receipt for navigation, input, resize and cleanup. Shared domain data should reach GUI/TUI/API consistently.

### HUI-06: passing tests are narrower than their names and report claims

The three HUD tests assert only nonempty rendered HTML. SSE tests assert expected strings. The terminal dimension/bounds test never supplies dimensions or checks width/height; it asserts nonempty content. The F Prime “wired” tests use literal WiredContext fixtures and do not exercise hardware acquisition.

These remain useful model/serialization checks. Add browser event delivery, disconnected/stale states, malformed input, safe rendering and PTY lifecycle/bounds checks. Do not rename their results into hardware or full-system verification.

## Verification receipts

| Check | Observed result / limit |
|---|---|
| Exact candidate source compilation | PASS in private /tmp harness; existing cached dependencies; warnings present |
| Selected tests | 27/27 PASS: SSE 6, HUD 3, F Prime fixture tests 11, sysadmin model/render tests 7 |
| Toolchain | Gleam 1.16.0 / OTP 27 observed; OTP 29 NOT_RUN |
| Default-peer probe | ONLINE present with no peer observations |
| Stream repeat probe | Identical bodies, seven named events |
| Live stream acceptance | FAIL: not_found JSON instead of event-stream |
| Live HUD acceptance | FAIL: expected candidate markers absent |
| Browser interaction, screenshots, assistive technology | UNRUN |
| PTY interaction, resize, injected controls, cleanup | UNRUN |
| Full 10,609-test suite, hardware, formal proof and deployment provenance | NOT_REVERIFIED |

Private harness: `/tmp/uos-homeostasis-ui.EdFYPa`. All candidate src was copied, four test files added to the private src tree, and gleeunit promoted from dev to regular dependency only in the temporary harness manifest. No repository build cache or application file was modified by this check. Tests ran with a two-scheduler BEAM and a 35-second timeout; compilation had a 60-second timeout.

Test log SHA-256: `6dca383fc9016c465b3791e1388318c8a1f4322439ab7d10ad9add03762a522a`.
Compile log SHA-256: `2f96ded47bc555907035d0738d0ff90a8a313e1f04755eec709bc0893278b66e`.
These logs are temporary receipts, not permanent provenance archives.

## STPA controls

Loss: operators or agents act on false operational feedback.
Hazard: a static, stale or untrusted observation is displayed as current verified authority.

| Unsafe control action | Constraint |
|---|---|
| Not providing failure/unavailability | Render unknown/stale/disconnected states and visible errors. |
| Providing an unsafe positive status/action result | Require source observations and executor receipts, not literals. |
| Providing feedback at the wrong time/order | Preserve observed time, source sequence and freshness validity. |
| Providing feedback for too long | Expire labels and subscriptions; bound history and reconnect behavior. |

These findings informed the new local skills. Their 12 scenarios and packaging checker do not repair or admit this application.

<details><summary>Verification — 5 domains / 18 checkpoints</summary>

Status applies to this guidance package; unchecked means unrun, not passed.

- Domain 1: [x] CHK-01-TIME host time; [x] CHK-02-TAIL FQDN references (publication unverified); [x] CHK-03-FRACT tags; [x] CHK-04-KM local rules and journal.
- Domain 2: [ ] CHK-05-MUDA fleet scan; [ ] CHK-06-GRAPH runtime language conformance; [ ] CHK-07-DRIVE hardware interlock.
- Domain 3: [ ] CHK-08-C1C8 full UI matrix; [ ] CHK-09-MATH mathematical gates; [ ] CHK-10-9MOD nine modalities; [ ] CHK-11-REGR deployed regression.
- Domain 4: [ ] CHK-12-GLEAM supervision; [ ] CHK-13-HERMES independent formal evidence; [ ] CHK-14-ZIGVM kernel; [ ] CHK-15-MAX inference; [ ] CHK-16-OTEL live trace correlation.
- Domain 5: [ ] CHK-17-SOV independent admission; [x] CHK-18-JJ isolated Jujutsu only.

</details>


