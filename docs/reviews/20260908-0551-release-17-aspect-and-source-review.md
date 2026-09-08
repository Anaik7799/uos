# 20260908-0551 — Release assurance: 17 aspects, algebraic atlas and source reuse

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Runbook](http://nas-1.tail55d152.ts.net:4100/docs/sop/20260908-0551-web-release-sdlc-sre-runbook.md) · [Denotation](http://nas-1.tail55d152.ts.net:4100/docs/design/20260908-0551-release-lifecycle-denotational-specification.md)

Review scope: homeostasis interfaces and the native web-release process. This is not an assertion that every UOS service works. The aspect names below come from docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.json. Full compliance remains NOT_VERIFIED. Candidate runtime receipts and author review are separate from independent admission.

## Algebraic atlas and declarative intent

| Object / morphism | Denotation | Executable evidence / limit |
|---|---|---|
| Candidate C | Exact 40-hex JJ revision | Build refuses changed source; packaged candidate checked |
| Stage S | Ordered 12-element lifecycle | fpp/release_lifecycle.gleam; all normal transitions checked |
| Receipt R | Candidate, stage, result, time window, digest | OCaml structural packet validator; authentic evidence still required |
| Intent I | SubmitEvidence, ReportFault, ReportRestoration | Typed Gleam interpreter; no shell, network, service or VCS effect |
| Interpret: C × S × I → Result(S) | Pure evidence-state transition | Uses existing UOS FPP interpreter; direct/declarative observations agree |
| Package: C → inventory | Sorted exact byte set | Corruption, missing/extra file and symlink rejection |
| Observe: runtime → attributed sample | Actual OTP/ERTS, process identity and counters | Coherent runtime identity; invalid counters unavailable; five-second TTL |
| Project: sample → GUI/TUI/API/SSE | One shared field meaning | Component, browser and transport tests; remote mesh projection unverified |
| Fold: events → state | Deterministic prefix accumulation | Composition and replay checks; 338-case OCaml/Mojo/Gleam comparison |
| Effect boundary | Intent plus externally checked authority | Sa-plan attempt and fresh runtime lease; the model cannot authorize itself |

The existing fpp/algebraic_atlas.gleam builder sets associativity_preserved, gluing_verified and morphism verification flags to literal True. Those are declarations, not invocation-specific proofs. This release uses concrete finite-model tests and does not consume those flags as authority. Official FPP compiler conformance and Lean/Gospel/Quint proofs remain UNRUN. The 338 cases cover finite prefix transitions; fault/restoration and intent equivalence have separate Gleam tests.

## All 17 canonical aspects

“Partial” means some scoped evidence exists and at least one obligation remains. It is never a passing admission state.

| ID | Canonical aspect | Evidence in this slice | Remaining obligation / status |
|---|---|---|---|
| A01 | Substrate & Hardware Storage Interlock | Private temporary/build directories; no device operations | Hardware/VFS isolation tests UNRUN |
| A02 | Standalone Jujutsu Monorepo Discipline | Isolated JJ composition, exact build revision, unchanged-source guard; internal JJ Git backend target | Shared root contains an empty .git placeholder (no HEAD/config), so a strict .git-absence check fails; own workspace has none. No active Git colocation was found. Integration and review outstanding; PARTIAL |
| A03 | Zero-Muda Purity & Waste Elimination | Existing OCaml/Mojo/BEAM tools; shared operational core; no new Bash or Python install | Whole dependency/history scan UNRUN; no blanket purity claim |
| A04 | Gleam/OTP 29 4-Domain Root Supervisor | Actual OTP29/ERTS17; managed private web process, restart and shutdown observations | Four-domain application supervision and cross-node failover UNRUN |
| A05 | ZigVM Deterministic Engine & 8 VFS Laws | Explicit native filesystem/process boundary | Descriptor-relative confinement and all eight VFS laws UNRUN; file-viewer boundary unresolved |
| A06 | Hermes Formal Evidence, Gospel & Z3 | OCaml oracle, bounded subprocesses, exact inventories and structured receipts | Gospel/Z3 proof and sovereign validation UNRUN |
| A07 | Mathematical Authority & Conservation | Prefix denotation, fold/replay laws, finite differential checks | Distributed authority/budget/trace proofs UNRUN |
| A08 | Biosemiotic Cybernetics & Rocha Cut | Display and intent model expose no execution authority; simulation cannot become live evidence | All tool/ingress enforcement paths UNRUN |
| A09 | Quarantined Modular MAX/Mojo Inference | Existing Mojo used for deterministic scripts and independent model, no inference calls | Operator-authorized Python stdlib execv exception documented; no inference verification claimed |
| A10 | Zenoh OoZ & MoZ Mesh Telemetry Backplane | Existing mesh left untouched | ACL, authenticated routing, dedup/retry and OTel delivery UNRUN |
| A11 | AG-UI 32-Event SSE Stream Protocol | Homeostasis named events, bounded frames, malformed/out-of-order/stale/disconnect checks | Entire 32-event protocol and authenticated tenant subscriptions UNRUN |
| A12 | A2UI 233-Component Declarative Catalog | Homeostasis components use shared data meanings and escaped text | All 233 components UNRUN |
| A13 | Penta-Stack Multi-Interface Accessibility | Lustre, Wisp, native TUI and SSE component parity; browser keyboard/narrow-layout checks | MoZ parity, full accessibility audit and all other screens UNRUN |
| A14 | Universal Tailscale FQDN Web Navigation | Eight FQDN smoke routes; explicit private-loopback resolution; external browser host rejection; startup links use the actual port and Tailscale FQDN | Private checks do not prove remote reachability; legacy applications and logs need separate audit |
| A15 | Comprehensive Verification Checklist | Five-domain/18-checkpoint structure; passing/unknown scope explicit | Whole-site/current-revision checklist gate UNRUN |
| A16 | Knowledge Management Triad (Wiki/ZK/Ont) | Linked specification, SOP, source review, journal and verification receipt | Canonical publication/indexing and ontology/ACL checks UNRUN |
| A17 | Sa-Plan & Bionic Durable Workflows | Canonical PREPARE claim, task-attempt record and own runtime lease | Production authorization/execution, Bionic crash recovery and saga proof UNRUN |

The full matrix is a release gate: an unknown applicable requirement cannot be averaged into green by unrelated test counts. Exclusions require a justified scope and reviewer; this document does not invent exclusions to reach 17/17.

## Fractal RCA and Jidoka standard work

For every incident, retain layer, target, candidate, observation time/clock domain, symptom, evidence, causal hypothesis, falsifier, affected control constraint, owner, containment and restoration receipt. Diagnose upward until the cause is established, then test the repair downward at each affected interface.

| Layer | Observed issue or boundary | Containment and regression |
|---|---|---|
| L0 — policy | Declared version or atlas flag can be confused with evidence | Never let a label grant admission; incomplete evidence blocks the release |
| L1 — value/FFI | OTP previously came from an environment/default label | Observe system_info directly; spoofed UOS_OTP_RELEASE rejected in actual OTP27/29 checks |
| L2 — module | OTP alone allowed an inconsistent ERTS/time/process tuple | Coherence checks reject ERTS15 with OTP29, missing identity and clock reversal |
| L3 — interface | Simulated or stale health can look like a live measurement | Shared attributed sample; invalid counters and expired samples unavailable; GUI/TUI/API/SSE checks |
| L4 — service | Production is an unmanaged, revision-unbound process | Preserve it; stage a packaged revision and require a bound rollback before cutover |
| L5 — checking | Source suites include constant/string checks and skipped assertions | Add meaningful negative tests and actual browser/runtime observations; keep source claims scoped |
| L6 — lifecycle | RuntimeMaxSec combined with Restart=on-failure restarted staging at its time cap | Final canary uses Restart=no and bounded lifetime; restart drills are separate, explicitly stopped tests |
| L7 — release integration | Moving source and stale artifacts can diverge | Snapshot build input, exact manifest, source-stability check, expected live candidate before/after probing |
| L8 — coordination | A stale task/heartbeat/epoch can outlive its authorization | Recheck canonical task attempt and cooperative lease immediately before each owned effect |
| L9 — system | Component tests cannot establish global stability | Keep system-wide admission NOT_VERIFIED; publish unresolved gaps and prioritize their next evidence |

Jidoka stops the smallest affected operation that safely contains the hazard. A failed stage enters held or recovering in the FPP model; it does not kill unrelated services. A review packet or board message cannot restart a stopped transition. Restoration needs a fresh receipt and externally validated target. Escalation is explicit when the affected boundary cannot contain the loss. No autonomous controller is newly deployed by this side-conversation change.

## C3I / Indrajaal VM-1 review and reuse

On 2026-09-08, read-only SSH to vm-1.tail55d152.ts.net confirmed the same bytes as the local source copies for the following inspected files. No source tree was quiesced or admitted; no external code, live database, secret, model weight or historical runtime artifact was imported.

| VM-1 source | SHA-256 | Finding and adapted coverage |
|---|---|---|
| /home/an/dev/ver/c3i/lib/cepaf_gleam/test/playwright/e2e_all_pages.spec.ts | 5ba4aea11e1d1436002ec6d5e0afa9e22ccf9fac0ccbbe50aa694e237b8056ae | Reuse route matrices, accessible navigation, browser-error and SSE checks. Its body-exists “dark cockpit” assertion is insufficient evidence of theme correctness. Our scoped eight routes add rendered-content, usable-link and browser-error checks. |
| /home/an/dev/ver/c3i/lib/cepaf_gleam/test/otp_release_test.gleam | b480a94ffc6d8645e96364611b3205e8dee10479e96b40ef18575fceb180292a | Useful format/roundtrip concepts; mostly generated text/version checks. Add actual VM identity, package corruption, full server startup and artifact restoration. |
| /home/an/dev/ver/c3i/lib/indrajaal_gleam_web/test/indrajaal_gleam_web_test.gleam | 59c80a632ce920baffa4dba7f4153c5c95191293af46fbb03f4a5806de7a07ea | Inspected file contains a greeting test, not web integration coverage. Use UOS runtime, transport and real browser tests; no blanket statement about the rest of Indrajaal. |

Also inspected remotely: C3I otp_app_release_test.gleam checks state counters and release constants; one throttle branch skips its assertion. The 20260407 web/TUI sync document explicitly describes a plan and then-missing interfaces. It supplies useful requirements, not present-day runtime evidence. We did not run these upstream suites against live VM-1 services.

Reuse categories are separated: already-present UOS implementation, newly authored tests informed by source review, and externally sourced artifacts awaiting ingestion approval/provenance. No imported test-count claim is added to UOS's measured results.

## Next work ordered by risk and dependency

1. Bind the current production process to an approved recoverable artifact and repair/verify the document/file-viewer authorization boundary. These gate cutover regardless of score.
2. Integrate the reviewed candidate through canonical ownership, rehearse target-specific draining and rollback, then observe the exact deployed revision.
3. Extend the route/component catalog to the rest of UOS with semantic API checks, expected unavailable states, keyboard/ARIA checks and fresh artifact links.
4. Replace declaration-only atlas/checklist health with revision-bound runtime and formal receipts. Verify the remaining 17-aspect obligations.
5. Establish a tested OTel/mesh path, durable actor ownership, startup/reboot and cross-node failover. Until measured, those remain unknown.

Prioritization uses criticality × STPA × FMEA band × dependency × impact, with hard blockers applied before sorting. The current release preparation score is 768; the score is an engineering assessment and never grants execution authority.


<details><summary>Verification checklist — five domains, 18 checkpoints</summary>

| Domain | Checkpoints | Scope |
|---|---|---|
| Metadata and navigation | CHK-01-TIME, CHK-02-TAIL, CHK-03-FRACT, CHK-04-KM | Timestamp, full Tailnet links, tags and evidence references |
| Purity and storage | CHK-05-MUDA, CHK-06-GRAPH, CHK-07-DRIVE | Existing runtimes only; no drive operations |
| Verification | CHK-08-C1C8, CHK-09-MATH, CHK-10-9MOD, CHK-11-REGR | Scoped test receipts; broader gates remain unverified |
| Runtime and observability | CHK-12-GLEAM, CHK-13-HERMES, CHK-14-ZIGVM, CHK-15-MAX, CHK-16-OTEL | Distinguish actual process observations from simulations |
| Governance and JJ | CHK-17-SOV, CHK-18-JJ | Independent admission outstanding; isolated JJ work |

No row grants a passing global checklist. Consult the revision-bound verification receipt.
</details>
