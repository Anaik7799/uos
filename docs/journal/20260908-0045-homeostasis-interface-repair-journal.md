# Homeostasis interface repair and evidence journal

#fractal-l0 #fractal-l2 #fractal-l5 #zk-adr #zero-muda #tailscale-web

Task: `uos/homeostasis-ui/20260908-0045 / REPAIR`; worker `codex-side-homeostasis`, attempt 2.
Observed receipt time: 2026-09-08 01:56:45 UTC.
[Specification](../design/20260908-0045-homeostasis-interface-specification.md) ·
[Recordings and verification](../reviews/20260908-0045-homeostasis-interface-verification.md) ·
[Machine manifest](../reviews/20260908-0045-homeostasis-interface-verification.json) ·
[GUI/TUI skills and rules](../design/20260908-0045-gui-tui-skills-rules-and-superpowers.md).
Intended [Tailnet interface](http://nas-1.tail55d152.ts.net:4100/homeostasis/evolution)
is a production destination, not evidence of deployment of this side-conversation candidate.

## 1. Scope & Trigger

The operator requested fully wired homeostasis GUI/TUI test and real data modes, 30 evolutionary
verification cycles, 30-second recordings for pages/components, mathematical checks, denotational
design and a comprehensive executable test strategy. Scope was explicitly bounded to homeostasis,
its existing host adapters and the local UI-rule package. Work remained in an isolated sibling JJ
workspace. No peer agent, board post, mainline integration, production restart or control-plane
cutover was initiated.

The selected implementation provides read-only evidence and simulated evolution. It does not
invent missing live physiology or grant control authority to browser actions.

## 2. Pre-State Assessment

The root intake was `888b0df29e68d5e1051545f19d27175d9319db79`; the prior local interface-rule
candidate `efbaea22367d3363df94ee0e36924ce1bfe2585f` was included in the isolated workspace.
The repair comparison base is `813b062b`.

The master and related documents asserted live physical wiring, fixed active peers, verified
checklists, ratification and broad stability/consensus claims. Inspection showed generated/model
contexts and fixed or disconnected interface paths. The old SSE output did not constitute a
continuous source-backed observation stream. The initial focused red check produced eight
failures before repair; its OTP 27 run was diagnostic only. Final receipts use OTP 29.

Risk was assessed P1 using criticality, STPA, FMEA, dependency and impact: C/T/F/Dep/I=4 each,
score 1024; FMEA S=4, O=3, detection difficulty=3, RPN=36. The typed assessment binds canonical
intake evidence and Sa-plan ownership. It is not a certificate of the evolving output candidate.

## 3. Execution Detail

### Data, interfaces and controls

Introduced an opaque evidence snapshot and a shared field denotation. Real mode acquires existing
local BEAM counters; test mode provides deterministic nominal/disturbance/recovery/unavailable
scenarios. Model times and source UTC remain distinct. GUI, terminal and JSON use the same fields.

Wired the actual web entrypoint before generic routing, plus the pure-router adapter. Added
selected-mode JSON, named SSE, plain text and review endpoints. The browser validates complete
field sets, source ordering, TTL and authority; invalid data clear measurements to UNKNOWN.
Bounded stream history, teardown and source expiry were exercised in an actual browser.

Mode/scenario/cycle controls, threshold sliders and preview output are connected. Real control
requests return 403 with no execution; test previews respond to selected sample/thresholds.
The existing TUI host receives an explicit snapshot/selection refresh adapter; a native entrypoint
renders both modes without taking ownership of terminal modes.

### Verification and documentation

Ran 30 simulated model evolutions with accounting/time/energy assertions and 120 scenario-cycle
projection checks. Captured 26 browser views in each of 30 checked update intervals and two native
30-cycle PTY traces. A separate OCaml validator checked receipt identity, continuous updates,
source clocks, media duration, mode attribution and integrity. Four corrupt receipts failed closed.

The first recording pass was superseded after adding threshold controls and stricter stream
schema validation. The final pass2 recordings bind to the tested application source. Historical
documents received correction notices; their previous bodies remain byte-identical. New
denotational specification, machine contract, test strategy, rule index and evidence manifest are
repository-contained.

## 4. Root Cause Analysis

1. Display code inferred health and peer activity from default or unrelated state rather than an
   attributed source snapshot. HTTP success and rich presentation were mistaken for evidence.
2. GUI, API and TUI projections had different defaults and route ownership, allowing stale or
   simulated values to appear operational.
3. Mathematical commentary enlarged conditional arithmetic/model properties into plant stability
   and distributed agreement claims.
4. The original stream path was not tested for real delivery, update continuity and failure
   invalidation at the actual web entrypoint.

The repair centralizes evidence denotation and validates actual transport/rendering behavior.
Source acquisition and release authority remain explicit separate integration tasks.

## 5. Fix Taxonomy

| Class | Repair |
|---|---|
| Evidence correctness | UNKNOWN/SIMULATED/OBSERVED/STALE; source UTC and TTL; no invented peers or passes |
| Routing/integration | Actual HTTP entrypoint, pure-router adapter, native terminal and existing host refresh hook |
| Functional UI | Shared fields, mode/scenario/cycle controls, threshold preview, component navigation |
| Reliability | Complete frame schema, monotonic source ordering, expiry, disconnect clearing, bounded history |
| Safety | No UI execution authority, real review denied, F Prime input-domain rejection, terminal escaping |
| Mathematical claims | Explicit denotation and ten bounded laws; corrected comments on proof assumptions |
| Reproducibility | Private OTP 29 build, OCaml browser/recording/receipt code, PTY script, source/media digests |

## 6. Patterns & Anti-Patterns Discovered

**Useful patterns:** typed provenance before rendering; one canonical field projection; deterministic
fixtures beside actual limited observations; explicit side-effect boundaries; negative-control
receipts; independent source-copy and continuity comparisons.

**Rejected patterns:** default healthy state, literal online agent lists, checklist counts presented
as verification, fixed frames labelled continuous telemetry, simulated ballots treated as peer
ACKs, browser wall time replacing source time, and non-increasing energy described as a complete
asymptotic-stability proof.

Compiler diagnostics caught a reserved Gleam identifier and option-constructor qualification;
a legacy TUI expectation was corrected to UNKNOWN. The evidence validator initially rejected
Playwright's integral JSON floats, then gained explicit safe-integer checks. These failed attempts
were not counted as passing evidence.

## 7. Verification Matrix

| Evidence | Result and scope |
|---|---|
| Focused Gleam/EUnit | 69/69 on OTP 29, 0 failures |
| Browser controls/rendering/faults | 43 checks passed; 320/768/1280 px |
| Model cycles | 30 generation/history/time/energy-checked simulated evolutions |
| Scenario denotation | 120 bounded cases across four scenarios |
| Browser captures | 26 views × 30 update checks = 780; 16,380 canonical field comparisons |
| Native terminal | 2 modes × 30 cycles, exit 0 |
| Receipt/media validator | Continuous updates, real source-clock advance, 21 fields, 30.92–31.36 s recordings, SHA-256 |
| Negative receipt controls | Missing cycle, stalled display, backward clock, false mode: all rejected |
| Source copy | 682 application source files + 12 test/probe modules exactly match tested copy |
| Historical document bodies | 15/15 preserved byte-for-byte below notices |
| Skill package | 3 skills, 12 aliases, 10 resources, 8 negative fixtures rejected |
| Independent system admission | UNRUN: full UOS protocol, production cutover, peer review and independent formal invocation |

The source revision locator is `294661d3941946413b591285b394969def88c42e`; the final manifest binds
changed implementation/test hashes. Later evidence/journal metadata does not change those tested
application bytes. A review bookmark contains the complete handoff.

## 8. Files Modified

52 files changed in this repair compared with `813b062b`. The prior UI skill package is
already present in the parent candidate; it was checked rather than re-created.

<details><summary>Complete repair file inventory</summary>

- `apps/cepaf_gleam/src/cepaf_gleam/fpp/homeostasis_fprime.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/homeostasis_data.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/homeostasis_status.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/homeostasis.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/homeostasis_evolution_hud.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/widgets/homeostasis_control.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/tui/homeostasis_evolution_view.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/tui/homeostasis_view.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/tui/renderer.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/tui/sysadmin_cockpit.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/web/special_views.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/agui_sse_api.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/homeostasis_api.gleam`
- `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam`
- `apps/cepaf_gleam/test/agui_sse_api_test.gleam`
- `apps/cepaf_gleam/test/homeostasis_algebra_test.gleam`
- `apps/cepaf_gleam/test/homeostasis_evidence_test.gleam`
- `apps/cepaf_gleam/test/homeostasis_fprime_wired_test.gleam`
- `apps/cepaf_gleam/test/homeostasis_ui_contract_test.gleam`
- `apps/cepaf_gleam/test/sysadmin_tui_test.gleam`
- `apps/indrajaal_gleam_web/src/indrajaal/homeostasis_http.gleam`
- `apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam`
- `apps/indrajaal_gleam_web/test/homeostasis_http_probe.gleam`
- `apps/indrajaal_gleam_web/test/homeostasis_transport_test.gleam`
- `contracts/specs/20260908-0045-homeostasis-interface-contract.json`
- `docs/design/20260907-2213-homeostasis-monitoring-sdlc-specification.md`
- `docs/design/20260907-2216-homeostasis-monitoring-fractal-sdlc-specification.md`
- `docs/design/20260907-2222-homeostasis-cockpit-operational-usecases.md`
- `docs/design/20260907-2234-tui-homeostasis-mvu-algebra-and-simulation-sdlc.md`
- `docs/design/20260908-0021-homeostasis-monitoring-comprehensive-matrix-sdlc.md`
- `docs/design/20260908-0041-homeostasis-screen-elements-components-and-state-machines-sdlc.md`
- `docs/design/20260908-0045-gui-tui-skills-rules-and-superpowers.md`
- `docs/design/20260908-0045-homeostasis-interface-specification.md`
- `docs/design/20260908-0047-homeostasis-fprime-state-machines-simulated-and-wired-sdlc.md`
- `docs/design/20260908-0048-homeostasis-declarative-intentional-system.md`
- `docs/design/20260908-0048-homeostasis-deontic-specification.md`
- `docs/design/20260908-0048-homeostasis-fractal-atlas.md`
- `docs/design/20260908-0048-homeostasis-fractal-ontology.md`
- `docs/design/20260908-0050-homeostasis-master-prompts-analysis-and-sdlc-synthesis.md`
- `docs/design/20260908-0105-homeostasis-monitoring-sdlc-specification.md`
- `docs/design/20260908-0113-homeostasis-monitoring-unified-master-sdlc-journal-and-specification.md`
- `docs/reviews/20260908-0045-homeostasis-interface-verification.json`
- `docs/reviews/20260908-0045-homeostasis-interface-verification.md`
- `docs/reviews/20260908-0045-homeostasis-repair-risk.json`
- `docs/zk/20260907-2315-adr-086-4-party-quorum-homeostasis-and-autonomous-self-evolution.md`
- `formal/lean/Homeostasis_Evolution.lean`
- `tools/homeostasis-ui-check`
- `tools/validation/homeostasis_browser_check.ml`
- `tools/validation/homeostasis_evidence_check.ml`
- `tools/validation/homeostasis_pty_check`
- `tools/validation/homeostasis_recording_check.ml`
- `docs/journal/20260908-0045-homeostasis-interface-repair-journal.md`

</details>

Generated video, screenshots, PTY captures and logs remain under ignored
`var/evidence/homeostasis/20260908-0045/pass2`. No compiler binaries, model weights or live
database files were added to the tracked candidate.

## 9. Architectural Observations

The existing Gleam/OTP and OCaml toolchain was sufficient for data acquisition, rendering,
transport, algebra checks and browser evidence. No new AI model or daemon was required.
The opaque evidence sum type prevents accidental equivalence between simulation, observation
and operational permission. Shared field IDs allow GUI/TUI/API comparisons without assigning
authority to the browser.

The present real-data slice is intentionally partial: VM counters are available, physiological
control sources are not. Future adapters need source contracts, authenticated provenance and
freshness checks before exposing health or remediation. The specification retains ASCII and
Mermaid sources for its explanatory architecture diagram.

## 10. Remaining Gaps

- Real physiological telemetry, peer-vote observation, runtime Pareto evidence and authenticated
  actuation are not implemented by this slice.
- The entire interactive TUI host's keyboard/mouse/resize/signal behavior and production proxy
  reconnection require integration verification. Native render and PTY output were verified.
- The evolution engine needs an independent check of current-state freshness, stale proposals,
  quorum epochs, replay fencing and effect authorization before control-plane use.
- Independent Lean/Quint execution, plant stability, full distributed consensus and the complete
  UOS nine-modality protocol are not established.
- The production Tailnet host and mainline were not changed. The candidate requires an integration
  owner and fresh checks at the integrated revision.

## 11. Metrics Summary

| Metric | Value |
|---|---|
| New provider/model calls | 0 |
| Peer agents contacted or spawned | 0 |
| Production deployments/restarts | 0 |
| Focused tests / browser checks | 69 / 43 |
| Model evolutions / scenario cases | 30 / 120 |
| Browser clips / checked intervals | 26 / 780 |
| Native PTY cycles | 60 |
| Per-interval data fields | 21 |
| Minimum / maximum clip duration | 30.92 / 31.36 seconds |
| Historical documents corrected | 15 |
| Root source files altered by this side task | 0; implementation lives in isolated sibling workspace |
| Runtime admission authority | NONE |

No claims of consciousness, physical-system stability, swarm agreement or full-system correctness
are inferred from these metrics.

## 12. STAMP & Constitutional Alignment

Hazards addressed include false healthy status, stale measurements presented as current,
unauthorized evolution, source-time aliasing and executable terminal/browser payloads.
Control constraints require source attribution, complete schema, freshness, bounded resources,
explicit test labels and denial of unowned effects. These constraints apply before an operational
action can become available.

Sa-plan task ownership remained distinct from release authority. The initial lease was explicitly
released and the same task reclaimed as attempt 2 for the expanded recording work. No duplicate
dispatch authority was created. Jujutsu standalone workspaces, Zero-Muda scope, native language
boundaries, timestamp prefixes, 13-section journaling and diagram provenance were maintained.
No shared live journal was regenerated and no peer board was written.

## 13. Conclusion

The homeostasis interface repair is ready for **candidate review** with measured test/real modes,
shared denotation, bounded checks and inspectable recordings. The evidence supports this isolated
implementation slice. It does not admit a production controller or close the remaining operational
gaps. Use the linked manifest and recordings, then re-run the integration gates before release.


<details><summary>Verification: 5 domains / 18 checkpoints</summary>

| Domain | Checkpoints and current scope |
|---|---|
| Metadata/time/navigation | CHK-01 observed host time; CHK-02 FQDN references, publication UNVERIFIED; CHK-03 fractal tags; CHK-04 local specification/knowledge links |
| Purity/storage | CHK-05 no new foreign runtime; CHK-06 native boundaries unchanged; CHK-07 storage interlock UNRUN |
| Tests/mathematics | CHK-08 full C1–C8 UNRUN; CHK-09 bounded algebraic tests only; CHK-10 nine modalities UNRUN; CHK-11 candidate UI checks in attached receipt |
| Control/observability | CHK-12 private OTP 29 run; CHK-13 independent formal proof UNRUN; CHK-14 ZigVM UNRUN; CHK-15 MAX UNRUN; CHK-16 source timestamps and SSE tested, full OTel correlation UNRUN |
| Governance/JJ | CHK-17 independent admission UNRUN; CHK-18 isolated JJ candidate, no mainline cutover |

</details>


