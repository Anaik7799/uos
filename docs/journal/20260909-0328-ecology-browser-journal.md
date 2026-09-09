# 20260909-0328 — Actual ecology browser verification

#fractal-l0 #fractal-l4 #fractal-l5 #fractal-l7 #fractal-l8 #zk-adr #zero-muda #tailscale-web

[Ecology](http://nas-1.tail55d152.ts.net:4110/ecology) · [Receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0228-ecology-browser-live-1/20260909-0328-receipt.json) · [Initial screenshot](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0228-ecology-browser-live-1/20260909-0328-initial.png) · [After live refresh](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0228-ecology-browser-live-1/20260909-0328-after-live-refresh.png) · [Risk](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0328-ecology-browser-risk.json)

Observed 2026-09-09T03:05:28Z–03:05:36Z. Task `uos/ecology-browser/20260909-0228`, `BROWSER`, worker `codex-ecology-browser`, attempt 1. Before-run clock check: chrony stratum 3, absolute offset 0.000436347 seconds, uncertainty 0.01673193 seconds. Browser local time displayed UTC+02:00. This journal records a scoped browser pass; application admission remains false.

## 1. Scope & Trigger

The parent requested real browser evidence for the newly staged ecology listener: rendered DOM, at least six seconds of live counter progress, 26 participant rows, visible shared Andon states, no browser errors, screenshots and a machine receipt. Service configuration, activation, runtime code, dependency installation and VCS changes were outside this task.

## 2. Pre-State Assessment

The existing refresh checks exercised source behavior but did not establish execution inside Chrome. The typed OCaml Playwright library, driver 1.59.0, Chrome and pinned Nix release libraries were already realized. The listener was not initially running, so the controller was prepared and held until the parent supplied its target and expected declared revision.

## 3. Execution Detail

Added `tools/validation/ecology_browser_check.ml`. It uses typed browser, context, page, response and locator APIs with no authored page JavaScript. Observations are OCaml records; violations are a finite variant and acceptance requires an empty list. Browser/context/driver lifetimes are bracketed with Eio and `Fun.protect`, inside a 55-second deadline. Driver cache files are checked before launch to prevent an implicit acquisition step.

The final target was `http://nas-1.tail55d152.ts.net:4110/ecology`, declared candidate `502a8cdd0d49fab09f411a04ac1ab7e7d3fb1910`. Chrome used explicit FQDN resolution to the actual service address, `100.87.7.78`; private high ports retain loopback mapping. Requests to other HTTP origins were blocked. Only read-only page and runtime-identity requests were made.

## 4. Root Cause Analysis

L5: source tests alone could not distinguish a rendered, refreshing page from static text. The actual browser supplies DOM, counter and error evidence. L7: the initial private-loopback assumption did not match the final Tailnet-only binding; the mapping was corrected from the parent's observed service address before any browser request. L8: Sa-plan rejected an initial single-segment plan name; the canonical hierarchical name was then created, and preflight passed before claiming.

The first controller launch also exposed a runtime library search issue: host curl was selected ahead of the intended Nix library directory, leaving transitive `libnghttp2.so.14` unavailable to the Nix loader. An explicit already-realized `LD_LIBRARY_PATH` resolved the issue. No package or global environment setting was changed.

## 5. Fix Taxonomy

New native browser verifier and evidence only. Existing release-capture code was a read-only pattern reference. The controller adds bounded waits, identity continuity, exact participant checks and error rejection; it does not alter application behavior or turn displayed readiness into system admission.

## 6. Patterns & Anti-Patterns Discovered

Observe elapsed-time counter progression in the same page and retain before/after screenshots. Bind declared revision and actual PID/run identity before and after the interval. Keep phase labels separate from capability invocation claims. Use the actual listener binding when mapping a canonical FQDN. Preserve failed preparation observations rather than presenting them as browser failures or silently omitting them.

## 7. Verification Matrix

| Check | Observed result | Scope |
|---|---|---|
| Native controller compilation | PASS | Existing OCaml 5.5 and pinned Nix compiler/libraries; deprecated Mtime alias warning only |
| Observation-law mutants | PASS 14 | Missing render, stalled/reversed counters, too-short interval, wrong/duplicate rows, invalid Andon, stale refresh, errors, identity change and target validation |
| Typed protocol ontology | 304 commands, 62 events, zero missing bindings | Read-only external source oracle against installed API; 14 product gaps remain |
| Actual page render | PASS | Heading, body, both shared Andon labels and 26 unique participant rows |
| Live interval | 6.350403349 seconds | Cycles 137 → 143; invocation counter 139 → 145; refresh state live at both samples |
| Shared Andon | Both ready | `modular_max: ready`, `openrouter_free: ready`; no recovery/failure transition was induced |
| Runtime identity | Stable | PID 204594, run `204594-1788922992203090`, OTP 29, ERTS 17.0.5, expected declared revision |
| Browser errors and violations | Zero | Page exceptions, error-level console messages and blocked external requests |
| Screenshots | Two valid PNGs, visually reviewed | Initial 326,721 bytes; after refresh 326,687 bytes |
| Human acceptance, accessibility, other routes, indefinite liveness | UNRUN | No broader passing claim |

## 8. Files Modified

Added `tools/validation/ecology_browser_check.ml` and timestamped task evidence under `docs/journal/`. Final source SHA256: `a726a1077af4b86b2e33e2d8c6936d64df60e2984786be5505f19c304b4be1d9`. Executable SHA256: `4ab378cdc14d2c6435eac6f0e7ab56c90a73c1760e6b1adba674ab2c5f2cbf06`. Actual browser receipt SHA256: `9be1c69ca95010d343862d1870a3c1005db24f3c283cdb0f7df8b54ff114f418`.

Compilation and ontology outputs remain in task-owned `/tmp/20260909-0228-ecology-browser-*` directories. Earlier preparation records retain their earlier source hash and UNRUN browser state; the actual receipt supersedes those preparation claims. No existing source, service or external tree was modified.

## 9. Architectural Observations

The verifier denotes `Observation × Observation × IdentityPair × BrowserErrors → Accept | Reject(violation list)`. Acceptance requires a visible real page, exact participant cardinality and distinct IDs, meaningful shared phase labels, a monotonic interval of at least six seconds, increasing cycles, nondecreasing invocations and unchanged runtime identity. PNGs are observed evidence, not explanatory diagrams.

The page explicitly says the participant models share one ecology actor and external system bindings are absent. This visible limitation is consistent with the bounded evidence: 26 displayed models do not establish 26 independently bound external systems. Runtime candidate metadata is declared configuration; package attestation remains a separate release gate.

## 10. Remaining Gaps

Visual review found the static song SVG title overlaps the chart area and is horizontally clipped inside its scrollable card. The table, counters and Andon panel remained readable. The issue was reported to the parent as a presentation follow-up and does not justify a complete visual/accessibility claim.

Only one 1280×900 Chromium viewport and one live interval were checked. Stopped/recovering transitions, other pages, all browser engines, long-term liveness and human acceptance remain outside this result. Browser/driver internals are external runtime libraries; protocol coverage does not establish whole Playwright product parity. Root owns grouped wiki/ZK/KM publication and later candidate changes.

## 11. Metrics Summary

Actual controller duration 7.313075946 seconds; sample interval 6.350403349 seconds; cycle delta 6; invocation delta 6; participant rows 26; PNG bytes 653,408; browser errors 0; violations 0. Bounds: one browser, 55-second operation, 12-second launch, 8-second navigation, 3-second locator reads and 8 MiB per screenshot. No inference or paid-model request was made by this browser task.

## 12. STAMP & Constitutional Alignment

The risk record covers all four UCA types: omitted browser observation, unsafe acceptance, stale/wrong-timing samples and excessive duration. Raw FMEA remains S4/O3/Det3/RPN36, ordinal P1/768; the score grants no authority. Sa-plan preflight and active observations passed for the current attempt. No EV number, VCS action, service mutation or system admission was issued.

| Aspect | Scoped evidence / limit |
|---|---|
| A01 Storage | New task artifacts only; no devices |
| A02 Jujutsu | No VCS mutation |
| A03 Zero-Muda | Existing libraries; no downloads or installations |
| A04 OTP | Actual OTP/ERTS/PID/run identity observed; supervisor proof separate |
| A05 ZigVM/VFS | No kernel change; whole VFS laws unrun |
| A06 Hermes | Native typed OCaml evidence; Gospel/Z3 proof unrun |
| A07 Mathematics | Finite verdict laws tested; formal proof unrun |
| A08 Authority | Read-only browser accepts evidence, not effects |
| A09 MAX/Mojo | Displayed MAX readiness observed; invocation evidence separately owned |
| A10 Zenoh | No mesh effect or delivery claim |
| A11 AG-UI | This page uses bounded refresh; full SSE protocol unrun |
| A12 A2UI | One actual page; catalog coverage unrun |
| A13 Accessibility | One viewport; full accessibility/human acceptance unrun |
| A14 Tailscale | Canonical FQDN and actual Tailnet-only binding used |
| A15 Checklist | Evidence-qualified checklist visibly rendered; global gate unrun |
| A16 KM | Journal, risk, screenshots and receipt delivered for root grouping |
| A17 Sa-plan | Exact BROWSER worker/attempt recorded; workflow recovery separate |

## 13. Conclusion

The actual ecology page rendered and refreshed successfully for the expected declared candidate, with 26 participant rows, both ready Andon states and no browser errors. The receipt and screenshots preserve the observed interval and its limits. A static SVG presentation defect remains recorded; application admission remains false.

<details><summary>Verification checklist — five domains, 18 checkpoints</summary>

| Domain | Checkpoints | Scope |
|---|---|---|
| Metadata/navigation | CHK-01-TIME, CHK-02-TAIL, CHK-03-FRACT, CHK-04-KM | Timestamp, host clock, full links, tags and root grouping references |
| Purity/storage | CHK-05-MUDA, CHK-06-GRAPH, CHK-07-DRIVE | No new dependency/device effect; full fleet checks unrun |
| Verification | CHK-08-C1C8, CHK-09-MATH, CHK-10-9MOD, CHK-11-REGR | Finite controller laws and actual browser checks; formal/global gates separate |
| Runtime/observability | CHK-12-GLEAM, CHK-13-HERMES, CHK-14-ZIGVM, CHK-15-MAX, CHK-16-OTEL | DOM and actual VM observations; broad runtime/trace conformance unrun |
| Governance/JJ | CHK-17-SOV, CHK-18-JJ | No admission or VCS action from this worker |

</details>
