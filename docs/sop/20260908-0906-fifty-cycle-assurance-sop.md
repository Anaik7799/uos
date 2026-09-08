# Fifty-cycle release assurance standard work

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda #tailscale-web

Observed design time: 2026-09-08 09:19:06 UTC. Status: implemented checker, execution pending.
[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Twelve-stage manual and agent runbook](http://nas-1.tail55d152.ts.net:4100/docs/sop/20260908-0551-web-release-sdlc-sre-runbook.md) · [Denotational lifecycle](http://nas-1.tail55d152.ts.net:4100/docs/design/20260908-0551-release-lifecycle-denotational-specification.md) · [17-aspect review](http://nas-1.tail55d152.ts.net:4100/docs/reviews/20260908-0551-release-17-aspect-and-source-review.md)

## Scope and authority

Use this extension for fifty distinct bounded assurance focuses on a fixed package. It does not mean fifty deployments, independent end-to-end trials, or fifty repairs. The machine catalog, tools/evolution_cycles.ml plan, binds dependencies, fractal layers L0–L9, eight artifact domains and all 17 canonical aspect references. A reference is not proof that the aspect passes.

Sa-plan owns one explicit task, attempt and worker. Session coordination owns separate workspace, staging runtime and integration leases. Observe the clock and recheck these fences before every bounded cycle and publication. Their cooperative checks do not replace an executor's atomic authorization. No board message, forecast, model answer or test result grants production admission.

Run in a sibling JJ workspace. Preserve root checkout, peer changes, production processes, shared journals and shared Zenoh keys. Use only the session's own new message IDs and Zenoh namespace. Never delete keys as synchronization. Only a current integration owner may advance main after resolving and checking the actual merge.

## Denotation and invariants

For bytes b and requested field k, guard(b,k) accepts exactly when b is within the configured byte budget, b parses as a JSON object, and k is a top-level object key. Passing bytes are preserved. A value containing k, longer key, nested object or malformed text is insufficient. Null and false values count as present. This guard is not a full value schema or an authorization engine. Duplicate-key policy needs its own explicit schema boundary.

Fallback JSON is built with the JSON encoder. Endpoint or field metadata cannot change the typed failure verdict. Oversize input is rejected before parsing. Gleam tests and an independent OCaml JSON-object oracle exercise these laws; no new foreign runtime is admitted.

The existing F Prime-style lifecycle prefix model advances only with stage-specific evidence for the expected candidate and fresh observations. The common OCaml operational core executes bounded argv lists without shell evaluation. Mojo forwards the same command surface to that core and supplies independent finite transition/selection oracles. This is functional interface equivalence, not two independent operational engines. OCaml is easier to generate and test here because the installed repository already provides its compiler, JSON, process, cryptographic and browser libraries.

Eligible focuses have all dependencies observed. A failed dependency never becomes a successful admission prerequisite; follow-up diagnostic focuses may still execute. Among eligible focuses select maximum C × STPA × FMEA × dependency × impact, with deterministic ID ties and a bounded impact increase in failed domains. The mandatory risk SOP defines the ordinal scales; the product is a prioritization heuristic, not an expected loss estimate. P0 safety controls override a low calculated score.

The receipt chain binds candidate, checker source hashes, owner, task, attempt, scope, predecessor hash, incoming evidence hash and precommitted forecast hash. Verification recalculates ordering, scores, outcomes and summary totals. The hash chain detects inconsistent alteration; it does not prove authenticity against an attacker able to replace the whole evidence set and its trusted anchor.

## Native commands and reproducible dependencies

From the sibling workspace:

```text
ocaml -I tools tools/evolution_cycles.ml plan
ocaml -I tools tools/evolution_cycles.ml selftest
ocaml -I tools tools/evolution_integrity_test.ml
ocaml -I tools tools/output_guard_check.ml SOURCE_ROOT
ocaml tools/release_process.ml unit SOURCE_ROOT
ocaml tools/release_process.ml capture-build SOURCE_ROOT
ocaml -I tools tools/evolution_cycles.ml run CONFIG_JSON
ocaml -I tools tools/evolution_cycles.ml verify OUTPUT_DIRECTORY
ocaml tools/release_process.ml capture SOURCE_ROOT RELEASE_DIRECTORY PRIVATE_PORT
```

The equivalent operational entry is tools/evolution_cycles.mojo under the existing supervised MAX environment, using pixi run --no-install --frozen. It imports only existing Python standard-library os for argv-only exec. New Python, browser or native packages must be installed through Determinate Nix/devenv. A missing dependency is a blocked prerequisite, not permission to download from another installer. Nix --offline alone is insufficient proof of zero network downloads: fixed-output builders may still attempt downloads. Reuse verified realized store paths; do not repeat an uncached build under an offline claim.

CONFIG_JSON must contain exactly source, release, private_port, output, risk, plan, task, worker, session, attempt, workspace_epoch, runtime_epoch. Paths are absolute. Source must be a sibling JJ workspace. Output must not exist. Private ports are 49152–65535. The runner verifies the packaged revision and protected checker bytes and refuses drift.

Every network operation uses the Tailnet FQDN. Private browser/curl tests retain that hostname with explicit local resolution for the owned private listener; this is a local test route and does not establish remote Tailnet access. A remote manual test needs a separately authorized Tailnet listener or tunnel. Stop only the recorded systemd unit after validating its runtime epoch, InvocationID and PID. Production port4100 is outside this task.

## Test strategy and reuse

| Area | Automated check | Human review and remaining obligation |
|---|---|---|
| Contract and output | Exact-key JSON cases, malformed/large payloads, escaped fallback, independent oracle | Review consumer value schemas and duplicate-key policy |
| Lifecycle | All twelve stage-packet negatives; 338 finite transition cases | Genuine authorization, deploy, recovery and acceptance receipts remain mandatory |
| Packaging/runtime | Complete inventory, corruption mutants, actual OTP27/29 observations with spoofed environment | Compare exact production artifact and rollback, not just labels |
| GUI/TUI | Eight-route browser suite, real/test/unavailable API and terminal projections, SSE stale/reorder/disconnect checks | Human keyboard/readability review and all233-component coverage are separate |
| Recordings | Eight real browser videos, seven samples per route over at least30 observed seconds | Watch videos and investigate frozen or inaccessible elements; video is not a correctness oracle |
| Evidence/checkers | Synthetic positive set plus deliberate receipt mutations, source/forecast/summary consistency | Trusted anchors, persistent transport and independent admission need separate evidence |
| Synchronization | Last10 incoming board messages each cycle, Zenoh observations, exact own-envelope readback | Zenoh memory readback does not establish durable disk or remote replication |

Test outputs reused within a focus run are labeled as the same fresh invocation. Twelve lifecycle focuses reuse one113-check invocation; three browser-related focuses reuse one browser run; guard subfocuses reuse one freshly compiled suite. Count distinct executions honestly.

The eight recorded routes are cockpit, planning, Mirage, wiki, ZK, evolution, components and terminal. Capture body rendering, script errors and time/frame observations while scrolling. The separate interaction suite exercises changing controls, fixtures and stream failures. Do not imply that every component or page has a30-second interaction scenario.

VM-1 was inspected read-only through vm-1.tail55d152.ts.net. C3I otp_release_test.gleam checks release constructors and .rel/.appup formatting; webui_full_coverage_test.gleam checks page/path and render mappings; batch3_tui_wisp_verification_test.gleam explicitly contains pure TUI/Wisp tests without network or SQLite. Reuse their case organization and domain contracts; none proves actual browser updates or real release rollback. No external code was imported in this task. The separate /home/an/dev/ver/indrajaal path was absent; existing prior Indrajaal review remains evidence, not a newly inspected source.

Observed external source SHA-256 values at09:18 UTC:
- C3I lib/cepaf_gleam/test/otp_release_test.gleam: b480a94ffc6d8645e96364611b3205e8dee10479e96b40ef18575fceb180292a
- C3I lib/cepaf_gleam/test/webui_full_coverage_test.gleam: f9a6cef43f8736114e81724ae2266f39f0f2bd4385b5a63ecc8660ce57a8645d
- C3I lib/cepaf_gleam/test/batch3_tui_wisp_verification_test.gleam: f32244c174f4db3fe9087bad5de55d698b1055058899a781269a375d302bb58d

## Forecasts, reviewable decisions and convergence

Before each check, record the event “this focus returns PASS,” horizon, current evidence, probability and method. The simple prior is (previous passes+1)/(previous scored outcomes+2). Score PASS/FAIL with Brier loss; keep OBSERVED/BLOCKED unscored. Related checks are dependent, so this is a transparent local heuristic, not a calibrated probability of system health or consciousness.

Reviewable decision summaries record goal, observation, alternatives, selected action, reason, expected outcome, confidence limitation and falsifier. They do not expose private model reasoning. STPA identifies unsafe control actions; FMEA ranks concrete failure modes; fractal RCA links symptom, component, runtime and governance causes. Jidoka stops an unsafe transition while permitting safe diagnostic observation. STM/two-lattice source and Rete-UL rules remain advisory unless fresh execution evidence binds them to this release path.

The Tailnet routing endpoint may select a Gemma model without executing it. Do not claim OpenRouter verification without a bounded completion receipt, exact model ID, evidence submitted, output and usage. No such new completion was available at design time. Existing peer advice and unloaded MAX status cannot serve as physical-system proof.

## Required closure

Retain the original50 outcomes, including failures. Repairs require new receipts; never rewrite failed evidence green. Recompute all mirrors and aggregate totals. Keep a13-section completion journal and state actual source candidate, source integration revision, tested runtime candidate, video locations and unresolved17-aspect gates separately. A successful source merge does not deploy it.

<details><summary>Verification checklist: five domains and eighteen checkpoints</summary>

Metadata/navigation: CHK-01-TIME, CHK-02-TAIL, CHK-03-FRACT, CHK-04-KM.
Purity/storage: CHK-05-MUDA, CHK-06-GRAPH, CHK-07-DRIVE.
Testing: CHK-08-C1C8, CHK-09-MATH, CHK-10-9MOD, CHK-11-REGR.
Runtime/observability: CHK-12-GLEAM, CHK-13-HERMES, CHK-14-ZIGVM, CHK-15-MAX, CHK-16-OTEL.
Governance/JJ: CHK-17-SOV, CHK-18-JJ.
These are review obligations; no global passing state is asserted.

</details>

