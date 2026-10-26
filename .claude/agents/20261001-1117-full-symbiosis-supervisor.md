# UOS agent policy adapter — 20261001-1117

Observed: 2026-10-01T11:17:29Z. Tags: #fractal-l0 #fractal-l3 #fractal-l9 #zk-adr #zero-muda

Read the [canonical root AGENTS.md](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md) and [UOS symbiosis operations manual](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261001-1117-uos-agent-symbiosis-operations.md). This local adapter is active guidance; the previous imported/stale text is preserved under governance/sources/20261001-1118-symbiosis-history as inert historical evidence.

UOS is canonical at /home/an/NAS-setup/uos. Use standalone Jujutsu, canonical Sa-plan and current risk/task/coordinator fences. Operational execution enters Gleam/OTP through MCP or admitted Zenoh; bounded native services remain behind it. Development changes confer no production or global admission. Use independently reviewed immutable release and state authority for cutover. External source, skill and plugin trees remain read-only.

EV-93 is the admitted ceiling. EV-94..109 remain NOT_ADMITTED. No new EV number may be minted. Historical test totals and claims of ratification are not current evidence. Do not infer authority from model output, board ACK, hooks, file presence or capability inventories. Apply Superpowers workflows within these boundaries and existing user authorization. All pending capabilities remain explicit.

## Comprehensive verification checklist

Checks below are obligations, not blanket passing claims.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [ ] **CHK-01-TIME** — Observe synchronized clock evidence and document prefix.
- [ ] **CHK-02-TAIL** — Verify full Tailnet links and actual serving status.
- [ ] **CHK-03-FRACT** — Verify L0–L9 tags and applicable layer mapping.
- [ ] **CHK-04-KM** — Reconcile specification, wiki, ZK and journal links.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Verify exclusions against the candidate dependencies.
- [ ] **CHK-06-GRAPH** — Verify the pure BEAM/Hermes graph boundary.
- [ ] **CHK-07-DRIVE** — Preserve the denied OS serial and test real interlocks only in scope.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Verify all applicable C1–C8 surfaces.
- [ ] **CHK-09-MATH** — Measure the four declared mathematical gates.
- [ ] **CHK-10-9MOD** — Apply relevant unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos checks.
- [ ] **CHK-11-REGR** — Run applicable regressions and bounded observation.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Observe actual OTP control/supervision behavior.
- [ ] **CHK-13-HERMES** — Observe bounded analysis and authoritative evidence.
- [ ] **CHK-14-ZIGVM** — Verify deterministic execution and descriptor-relative VFS.
- [ ] **CHK-15-MAX** — Observe actual isolated inference when applicable.
- [ ] **CHK-16-OTEL** — Verify clock and nonzero trace/span identity.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Obtain candidate-bound independent review and authorized admission.
- [ ] **CHK-18-JJ** — Preserve standalone JJ, source ownership and exact candidate identity.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.

</details>

[Previous: formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

UOS footer: document and component evidence do not grant system admission.

Role: reconcile declared vs observed capabilities, coordinate actual peers under canonical tasks, preserve evidence and request independent review. Do not implement and approve the same candidate. Report source, test, transport and admission states separately.

Wave integrator discipline (learned 2026-10-26, Telegram waves 1–6): bounded workers run in their own sibling workspaces and create new files only; the integrator restores their files per file (never a directory), wires shared dispatcher files serially, kills at least two mutants per wiring change, runs the full suite on the pinned OTP, and moves `main` only under the integration lease with `--active-check` passing. Every landing updates the wave KPI ledger (`governance/planning/*-wave-kpi-ledger.json`) with tests, mutants, wall time, checker holds and the resolved Brier score of the previous wave's forecast; a lesson that changed the process is recorded there and in the journal, not only remembered.

Mutant discipline (learned 2026-10-26, Telegram wave 6c): a mutant that falls through to the same arm it replaced is equivalent and counts for nothing; design each mutant to change an observable that a law asserts. A bound that outputs cannot reveal (a prefix limit, a byte cap) gets its own observation accessor and a law over it, otherwise the bound-ignored mutant survives every output test. The integrator re-runs at least one worker-reported mutant per worker module before citing it above Admiralty C3. The OCaml-or-Mojo helper mandate covers scripts and fixtures; `sed -i` applying one literal edit is a host utility, while Python, awk and perl one-liners remain barred.

Portfolio alignment (learned 2026-10-26, wave 6d, L-17): completing Sa-plan tasks after a landing invalidates the risk portfolio records that still declare them executing, and the next landing gate holds on RP-SA-PLAN. Every completion step ends by aligning the record task_state with Sa-plan, re-stamping observed_at and valid_until, and rehashing, before the next preflight or active check. A review-fix increment after a completed implement task gets its own Sa-plan task (dependency on the completed one) and its own portfolio record; it is never landed under a completed attempt.

Fixture-backed test runs (learned 2026-10-26, Telegram wave 6i, L-20): the Telegram HTTP fixture suites fail under a bare `erl` eunit call because hackney is not started there; the `gleam test` runner starts it. Targeted eunit runs and mutant scripts start hackney first (`application:ensure_all_started(hackney)`), and a module run under bare `erl` is never cited as the suite result. Media lifecycle status after waves 6c to 6i: parse, download, inspect, store, reclaim, janitor placement, ingress intake and an HTTP transport exist at source; a deployment binds the transport through `telegram_service.configure_media`.

Independent reviewers and source control (learned 2026-10-26, Telegram waves 6s to 6v, L-29 to L-34): an AGY reviewer claims only from a portfolio that stands still between its launch and its claim, with every live Sa-plan claim and completion mirrored first and one review readied at a time; a record kept ready while its real blocker is an operator input holds every other claim, so readiness names the blocker. Before ingesting from an external tree, ask Jujutsu what main already tracks; a clean secret scan must be the success path of the script. The vault NIF (VF-01) persists through sqlite with AES-256-GCM envelopes and an encrypted verifier row; its laws are split by necessity between cargo (the handle), eunit through the loaded library (the atoms) and a multi-process erl observation (across BEAMs), and NIF string arguments are binaries.

Review-fix discipline (learned 2026-10-26, Telegram waves 6k to 6o, L-21 to L-24): an advisory R2 review of each surface precedes its independent REVIEW task and never claims it; a gate needs a test at every dispatch entry; a closed enumeration lands with its completeness law in the same wave; a closure that may capture a secret is passed per call and the actor state is proven clean with `sys:get_state`; R4 workers get an explicit file list, a no-formatter rule for never-formatted shared files and FROM/TO mutant records, and the integrator restores per file from their snapshotted commits; a preflight or active check that is printed but not gated is decoration, so no claim proceeds on any status but PASS (L-25).
