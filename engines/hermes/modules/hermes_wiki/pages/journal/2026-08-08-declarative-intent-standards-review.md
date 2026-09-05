# Journal — Declarative intent: standards alignment, fable review, playbooks

**Date:** 2026-08-08 (continuation of the declarative-intent track)
**State when this began:** routing_family complete at `004fd00`; mechanism landed
(Blueprint + Harness_config + Converge + auto_converge + Evidence_rollup +
Drift_rules + run_config); all suites green.

## The directive (user prompt, verbatim)

> since this system and harness will be reused for creating new software - we
> want a declarative , intent based mechanism of configuring and giving
> instructions. the textual part will be ocaml comments and executable part
> will be Ocaml or OCAML DSL --
> https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/declarative-agent-architecture,
> https://www.nokia.com/blog/the-secret-ingredient-to-scalable-networks-intent-based-networking-in-higher-ed/,
> https://www.pulumi.com/ , https://developer.hashicorp.com/terraform ,
> https://www.ietf.org/archive/id/draft-irtf-nmrg-ibn-concepts-definitions-05.html ,
> https://www.rfc-editor.org/info/rfc7575/ ,
> https://www.ietf.org/archive/id/draft-ietf-anima-autonomic-control-plane-30.txt ,
> https://www.rfc-editor.org/info/rfc9316/ , https://www.rfc-editor.org/info/rfc9315 ,
> https://arxiv.org/html/2603.23772v1
>
> AS-IS: sync with fully align with current system, fractal atlas, fractal
> algebric, fractal ontology and mapped to current harness and system
> architecture.
>
> TO-BE: create the algebra, configuration grammer, behavior of the harness to
> configure and execute different activities performed by the harness -- be as
> comprehensive and complete as possible, cover all fractal layers and fractal
> components and fractal behaviors. testing - tdd, bdd, property testing, fuzz,
> chaos testing, formal analysis, formal tools, very strong typing. all aspects
> of system - harness and hermes should be fully configurable using this mode.
> create detailed list of features and documentation covering all sdlc and sre
> aspects. use rete ul, stan, z3, quint, Rcoq, stmml for all aspects of teh
> system -- continue the formal system slice in parallel -- rcoq irs, rcoq,
> quint, etc -- all of them -- focus on making sure declarative, intent based
> mechansim is Automatically used for giving configuration and intent based
> operational instructions. The system should automatically converge the
> configuration to the intent. use formal checkers and automated techniques for
> doing this mapping seamlessly and correctly -- show and update the
> documentation -- review the existing content, get all the new references,
> update fractal ontology, fractal atal artifacs, fractal grammer, all docs,
> sdlc and sre docs and code, Standard operating procedures and configuration
> and operations related code and stsem config and structure.

Complete prompt history for this track (verbatim, in order — nothing elided):

> show list of documents, skills and journal content for declarative intent
> based configuration and control

> review using fable . be as comprehensive and detailed as possible . look at
> all fractal layers x fractal components x fractal work flows sdlc and sre x
> syestem behavior x fast OODA convergence and homeostatis

> crete comprehensive documentation and detailed instruction show that lower
> end models can implement it.

> add full details in journal with prompt

> add full details in journal with prompt history. do not lose any information.
> make sure we have contols .review zigvm and c3i for control and homeostatis
> algorithms and control algorithms . import thes to harness ocml

> add full details in journal with prompt history. do not lose any information.
> make sure we have contols .review zigvm and c3i for control and homeostatis
> algorithms and control algorithms . import thes to harness ocml. get all the
> c3i controllers . do deep analyis on how these controllers can be used in
> sdlc and system sre

## Step 1 — the new references, fetched and distilled

The Pulumi/Terraform/Nokia/M365 sources were already integrated in the design
(docs/hermes/declarative-configuration.md). The genuinely NEW references are
the IETF/IRTF standards and the arXiv paper; each was fetched and distilled
(full digest preserved in the session scratchpad; key vocabulary):

- **RFC 9315** (IBN Concepts & Definitions): intent = declarative goals/
  outcomes without the how. Dual-loop lifecycle — Fulfillment (Intent
  Ingestion/User Interaction → Intent Translation → Intent Orchestration) and
  Assurance (Monitoring → Intent Compliance Assessment → Intent Compliance
  Actions → Abstraction/Aggregation/Reporting); inner autonomic loop + outer
  user loop. Properties: Single Source of Truth; One Touch But Not One Shot;
  Autonomy & Supervision; Learning; Capability Exposure; Abstract &
  Outcome-Driven. Intent vs policy (ECA) vs service model.
- **RFC 9316** (Intent Classification): dimensions — user type, intent type,
  scope, network scope, Abstraction (technical/non-technical), Life Cycle
  (persistent/transient).
- **RFC 7575** (Autonomic Networking): self-configuration / self-healing /
  self-optimizing / self-protection; ten design goals (incl. Autonomic
  Reporting, Independence of Function and Layer, Full Life-Cycle Support);
  intent is domain-wide, never node-specific.
- **ANIMA ACP** (draft-30): a self-forming/self-managing/self-protecting
  control plane SEPARATE from the data plane — management survives data-plane
  breakage; no circular dependency.
- **arXiv 2603.23772** (AI-driven IBN): schema-constrained intent→policy-IR
  with validation + correction loops; conflict-aware activation (conflicts
  detected BEFORE deployment; unresolved → escalate); proactive multi-intent
  assurance — "intent drift" = KPI degradation preceding violation; root-cause
  disambiguation; lead-time warnings.

## Step 2 — the fable review (five parallel lenses)

Per the user's cross-product, five fable-model reviewers were launched in
parallel, each read-only, each required to verify in code (file:line) and to
grade against the fetched standards:

1. **Fractal layers** — L0–L6+LX: where intent is declarable vs where actual
   is measured; per-level gap table.
2. **Fractal components** — R12 ontology entries + atlas edges for the nine
   mechanism modules; RFC lifecycle phase ownership.
3. **SDLC × SRE workflows + SOPs** — row-by-row verification of the coverage
   tables; staleness sweep; SOP gaps; RFC 7575 ten-goal scorecard.
4. **System behavior** — law→proof→test matrix; per-module test-discipline
   matrix; typing-seam audit; fail-closed audit; conflict-detection gap.
5. **OODA + homeostasis** — OODA mapping with latency; perturbation/sensor/
   response table; ACP-separation trace; self-* scorecard; zigvm autonomic
   mirror (R14).

### Final tally — all five lenses landed

**59 findings, 12 HIGH, deduplicated to 9 HIGH clusters.** Full synthesis with
every finding, the merged scorecards, and the sequenced TO-BE queue:
`docs/hermes/reviews/2026-08-08-declarative-intent-fable-review.md`.

The 9 HIGH clusters: (H1) dashboard hard-codes its KPIs — found independently
by THREE lenses; (H2) ontology fail-open at component grain (6 unregistered
components); (H3) no intent-conflict detection; (H4) observe tick ~95% waste
(17 s re-hashing the frozen tree per entry); (H5) inner loop human-cranked (no
autonomous re-observation); (H6) three disagreeing observe surfaces (run_config
folds 22/28 scenarios and ignores its corpus argument); (H7) the Kleene loop
iterates a constant (`step _ = cached` — anomaly detector structurally dead in
production); (H8) no exit-code teeth + the two live entry points and the
canonical blueprint are untested by the battery; (H9) the self-description is
inverted (five landed formal tools marked ⬜).

Notable single-lens finds: F-BT-5 (the one genuinely fail-open evidence path —
a typo'd contract id on a FAILING scenario lets the real node roll up false
Verified); F-L0-2 (empty blueprint reconciles to Verified through the run_config
driver); F-SW-5/F-BT-8 (live drift diagnostics always UNANALYSED, the
auto-countermeasure rule unreachable); F-OH-9 (the zigvm autonomic-backlog
invariant `open-runbook-items == current-drift` has no analogue).

Cross-corroboration was the method working: H1 by lenses 1+3+5, H6 by 3+4+5,
H7 by 3+4+5, H3 by 2+4 — none of them shared context.

### Initial per-lens headlines (recorded as they landed)

**Lens 1 (layers) — 10 findings.** Headlines:
- F-L0-1 [HIGH]: `parity_dashboard.generate` hard-codes KPIs/family pills/
  fractal strip instead of deriving from `Evidence_rollup` — the Report leg
  asserts rather than measures (violates RFC 9315 outcome-derivation and the
  R10 spirit at the reporting layer).
- F-L6-1: every intent drift is filed at L6_receipt regardless of target level
  (blueprint.ml:121) — level should derive from target arity.
- F-L3-1: intent stops at L2; contracts (L3) and scenario families (L4) are
  verdict-bearing but not intent-addressable (falls short of Capability
  Exposure).
- F-LX-1: `Fractal_diagnostic.fractal_level` has no LX constructor — LX
  activity failures are filed inconsistently (L4/L2/L6).
- F-L0-2: empty blueprint reconciles to Verified through run_config's driver —
  a vacuous-truth hole at the one layer users author.
- F-L1-1: `routing_family.requires` names 4 slices while its verdict rolls
  over 7 — declared decomposition disagrees with measured decomposition.

**Lens 2 (components/ontology) — 12 findings.** Headlines:
- F-CO-1 [HIGH]: 6 of 9 mechanism components have NO ontology entry (converge,
  auto_converge, evidence_rollup, parity_intent, run_config,
  reconcile_blueprint) — 66 unexamined aspect cells.
- F-CO-2 [HIGH]: R12 enforcement is fail-open at component granularity — the
  ontology test iterates only DECLARED components, so a new module ships
  invisible; needs a dune-module-list vs ontology completeness diff.
- F-CO-3 [HIGH]: no conflicting-desire detection (two directives on one target
  with different desired verdicts pass validate; ancestor/descendant
  contradictions pass) — the arXiv conflict-aware-activation gap.
- F-CO-4: nine concrete missing atlas edges (call-site-justified list);
  F-CO-6: Compliance Actions unowned even for the declared-safe Automatic
  countermeasure subset; F-CO-7: parity_dashboard and determinism_verifier are
  not ontology components so `Governs` edges to them are inexpressible;
  F-CO-9: fractal-atlas.md + feature-ontology.md contradict the code (stale
  "L5/L6 not durable", "2 contracts" vs 11).

## Step 3 — the playbooks (docs/hermes/playbooks/)

Per the "lower-end models can implement it" directive: every recurring harness
operation rewritten as a mechanical recipe — substitution tables, exact
anchors, VERIFY command + expected output per step, IF-FAIL branches ending in
a named fix or STOP-jidoka, and forbidden-action tables. Files:

- `README.md` — index, the executable-by-anyone contract, iron rules,
  forbidden actions.
- `00-glossary-and-map.md` — every term, file map, command reference, env
  vars, L-01…L-10 distilled to one-liners.
- `01-add-parity-slice.md` — the master recipe (probe → adapter → capture →
  TDD candidate → compare → 7-row integration checklist).
- `02-declare-intent-and-run-loop.md` — directive template + validator rules +
  how to read trajectory/settled/anomaly/runbook + verdict decision table.
- `03-resolve-divergence.md` — the Q1/Q2/Q3 decision tree with prohibitions.
- `04-add-gospel-contract.md` — spec → lint → register, with the known lint
  failure modes.
- `05-sync-formal-legs.md` — change→leg lookup (Quint/Rocq/z3/smtml/Rete/
  Stan), each with re-sync steps and the meta-rule (a failing leg is working).
- `06-close-out-checklist.md` — dashboard/docs/handover/ontology/overlap-map/
  battery/commit.

Every command and path in the playbooks was verified against the live tree
before writing (dune stanza names, adapter registry, env vars, scenario-id
convention, evidence-store schema; `test_converge` executed as the invocation-
pattern proof: 9/0).

## Method notes

- The standards were FETCHED, not recalled — the same probe-first discipline
  the parity corpus uses (never trust a hand-derived expectation).
- The reviewers were instructed to verify in code and forbidden to report from
  docs — lens 1 and 2 both caught doc-vs-code drift that a doc-driven review
  would have repeated as fact.
- Review findings are inputs to the TO-BE queue, not conclusions: each will be
  fixed at the source (ontology entries, completeness test, conflict
  validation, dashboard derivation, level derivation) under the usual TDD/
  formal discipline, and nothing gets marked done without its VERIFY.

## TO-BE execution (sequenced from the full findings)

Five waves, every item TDD-RED-first (full detail in the review doc):

1. **Truth of reporting + guard rails** — dashboard derives from the store
   (H1); battery validates the canonical blueprint (F-BT-3); exit-code teeth +
   smoke tests for run_config/auto_converge (H8); one shared scenario registry
   (H6).
2. **Ontology/atlas completeness** — R12 completeness test first (F-CO-2, it
   prevents recurrence), then the six entries + nine edges + the
   dashboard/determinism/formal_specs/rocq_lattice registrations.
3. **Validation semantics** — conflict detection (H3); HZ-INT-* hazards +
   level-from-target-arity (F-SW-5/F-L6-1); vacuous-blueprint guard (F-L0-2);
   the three missing directives + requires-consistency (F-L1-1); node-id
   cross-check (F-BT-5).
4. **Docs + SOPs** — §4 flip (H9), live-output refresh, HANDOVER/atlas/
   feature-ontology corrections, the 11-SOP document.
5. **Fast OODA + homeostasis** — pin-check fast tick (H4, zigvm Vcache
   mirror); real per-iteration step (H7); preflight in auto_converge; the
   TMPDIR actuator; runbook-as-tracked-tasks with the zigvm invariant.

Wave 1 item 1 (dashboard) began immediately after synthesis, in this session.

## Wave 1.1 LANDED — the dashboard now derives (H1 closed)

TDD, RED first (`Unbound value Parity_dashboard.kpi_of_rows`), then:
- `Evidence_store.latest_snapshot` (new reader — report surfaces key their
  reads without re-scanning the frozen tree; also the F-OH-1 direction).
- `Parity_dashboard.kpi_of_rows` — pure derivation of every KPI from the
  store's latest `(contract_id, passed)` rows via `Evidence_rollup.per_node` +
  `family_verdicts` over `Parity_intent.family_catalog` (SSoT — no sixth
  hand-rolled node encoding).
- `family_rows`/`fractal_strip`/hero prose fully derived (covered capabilities
  NAMED per family; a covered-but-unverified slice is marked `!` by name);
  "L3: 4 checked" → "11 declared" derived from `Contract_catalog.all`.
- `generate` returns `result`; unreadable store REFUSES (render exe exits 1;
  run_config's Report primitive maps it to Blocked — fail-closed, a control).
- Differential tests: 46 checks incl. different-evidence⇒different-numbers,
  family-scale vacuous truth (7/7 verified vs 6/7), catalog-driven row
  construction. **Live proof:** the derived dashboard reproduces the previously
  pinned truth exactly — 28/28, 9 slices, 0 open divergences, 1/18 families,
  full 64-char snapshot digest (better than the truncated constant it replaced).

## The controls directive — zigvm + c3i survey (in progress at this entry)

User directive: make sure we have controls; review zigvm and c3i for control
and homeostasis algorithms; import to harness OCaml. Standing constraint
honored: the C3I environment file is never printed, committed, or sourced —
code survey only.

**zigvm control inventory** (from the R14 lens-5 mirror table): OODA-cycle
verifiability law (every cycle a validated fact), lifecycle-transition
legality, the autonomic self-repair backlog with invariant
`open orphan-tasks == current orphans`, `Vcache.dirty_frontier` incremental
verification (cold=all-dirty, cached-Fail-always-reruns, corrupt-decodes-dirty),
vitality/foresight least-squares trend over own defect history, Stan
predictions ledger with resolutions + calibration, GATE-DETERMINACY.

**c3i control inventory** (survey of ~/dev/ver/c3i, 1,951 gleam/erl sources):
a rich homeostasis vocabulary layer — `stop_hook_lyapunov.gleam` (Lyapunov
stability gate), `pressure_publish.gleam` (backpressure), `muda_prune.gleam`
(waste pruning), `learn_loop_healthcheck.gleam`, `p10_chaos_probe` /
`p10_robustness_gate` / `p10_rete_autofix`, `ha_canary_controller`,
`c8_guardian_consensus`, plus pervasive circuit_breaker (323), hysteresis
(124), quarantine (151), watchdog (87), heartbeat (874) implementations.

Import target: `hermes_harness/homeostasis.ml` — pure control algorithms
(Lyapunov descent over the drift measure, hysteresis/flap detection over
receipt history, circuit breaker for oracle invocation) with full TDD +
ontology entry in the SAME commit (F-CO-1's lesson: no unregistered modules,
ever again). LANDED at f560f45 (38/0 stub-RED-first; live leg green over 3
recorded runs; exit-2 teeth armed).

## The FULL FRACTAL CONTROLLER PASS — LANDED

User directive: "do full fractal pass to use controllers in every part of the
system." Landed as `control_plane.ml` (one pure leg constructor per fractal
level; sweeps composed per entry point; unsensed levels always named — no
silent caps) + `Homeostasis.regressed/regression_alert` (the P0 cross-run
regression sensor) + two store readers (`parity_history` full chronological
trajectory, `latest_receipt_revision`), wired into EVERY surface:

| Surface | Sweep | Teeth |
|---|---|---|
| `compare_reference_traces` | full 7-leg sweep after receipts (own read session — the write session closes first) | exit 2 on P0 (a REGRESSION stops the line; a first-time divergence stays a recorded measurement, exit 0) |
| `auto_converge` | full sweep + NEW R13 frozen-reference preflight (F-OH-4 closed: refuses with a named diagnostic instead of dying raw) | exit 2 on P0/Anomaly |
| `run_config` | full sweep with ITS OWN corpus size | exit 2 on P0 |
| `parity_dashboard` | store-only sweep (L0/L1/L2/L4) + 4 unsensed legs with reasons, rendered as its own section | render-only |

Live proofs (the sensors caught real things immediately):
1. **The registry-drift sensor fired on a real defect**: run_config's sweep
   printed `L6 P1 — 28 scenarios have receipts but this surface's corpus
   lists only 22 — its corpus registry is STALE`. A GENERAL controller caught
   F-SW-3 (found by three reviewers) at runtime with zero defect-specific code.
2. **The staleness lead-time sensor completed a full homeostatic cycle**:
   L4 P2 (`receipts minted at 98497f9, HEAD is 89e5f23`) → the runbook action
   (fresh compare, 28/28 at HEAD) → L4 green. Detect → act → restore.
3. **Window memory works (c3i last-10 rule)**: the L2 recovery note shrank
   from five scenarios to one as old transitions aged out of their windows —
   caught first as a design defect (permanent-noise notes) by the live run,
   fixed RED-first with the windowing laws pinned.
4. **A real wiring defect caught by the live run**: the compare sweep first
   ran against the closed write-session store (fatal). Fixed by giving the
   sweep its own read session — deliberate act and observation stay separate.

Suites: control_plane 29/0 · homeostasis 46/0 · dashboard 49/0 · rollup +
append-only-trajectory law ok · ontology 619/0 (22 components, 29 edges) ·
compare live 28/28 exit 0 · loop live green. Import-queue status: items 1
(exit teeth, all entry points) and the L4/L6 sensor halves of item 3 are DONE;
2 (runbook_registry), rest of 3, 4-11 remain.

## ZENOH MESH TELEMETRY — LANDED (with the boundary stated as law)

User prompt (verbatim): "can we use zenoh for messaging between every componet
in the system"

**The boundary answer, recorded as law:** between every COMPONENT — no.
Intra-process composition stays pure function calls, because the algebra IS
the proof: the evidence fold, the fail-closed Gate, and GATE-DETERMINACY all
depend on synchronous deterministic composition, and the formal legs certify
exactly that. Between every PROCESS/SYSTEM — yes: the c3i discipline ("all
system-to-system communication MUST go through this module"; "Zenoh failure
must not fail the aggregator"), published data is observation or advice,
never authority (the two-lattice law).

**What was found on probe:** a live zenoh router (podman `zenoh-router`,
ports 7447 + 8000) — the c3i mesh is UP on this machine; and
`vendor/zenoh-c/` (prebuilt libzenohc.a/.so + 1.x headers) already staged in
the harness repo. No new external tool needed: FFI, not subprocess — the
permitted-oracle list is untouched.

**Landed:** `hermes_zenoh.ml/.mli` + `hz_stubs.c` (one C stub: JSON config
via `zc_config_from_str` in CLIENT mode so an absent router fails fast, put,
drop; OCaml strings copied before any zenoh call) + dune foreign-archive
wiring (copy rule for the prebuilt .a; `extra_deps (glob_files ...)` because
data_only vendor files mirror LAZILY — the .a copied via its rule, the
headers only when declared). TDD stub-RED first; **14/0 including the LIVE
leg: a real session to the running mesh router, publish, clean close**; chaos
(closed port → typed Error, fast) and explicit opt-out (HERMES_ZENOH=0,
reported not silent) pinned. Wired best-effort into all three run surfaces:
`hermes/control/sweep/{compare,auto_converge,run_config}` +
`hermes/control/worst/{...}`. Live: the loop printed
`zenoh: published -> hermes/control/sweep/auto_converge` against the real
router. Ontology entry + edge and the overlap-map row (zigvm mcp_server =
tool-RPC, a different concern; c3i zenoh.gleam is the mirror) in the same
commit.

Build learnings worth keeping: dune compiles foreign stubs with cwd = the
stanza's build dir and %{project_root} = `..`; data_only_dirs contents enter
_build only as declared deps; this zenoh-c build has no `zp_config_insert` —
`zc_config_from_str` with the documented JSON idiom is the portable path.

## The full c3i controller analysis — LANDED

`docs/hermes/c3i-controller-analysis.md` (fable analyst, read-only, env file
untouched). Key corrections vs the first scan: the controller heartland is
`lib/cepaf_gleam/src/cepaf_gleam/ha/` (70+ modules); there is NO single
homeostasis engine — homeostasis is a three-level model (doctrine: 7
properties-of-life × 8 fractal layers = 56 evidence-bearing cells; mechanism:
emitter/detector PAIRS graded P0/P1/P2/green folded worst-of by one
aggregator; runtime: sensor → filter → detector → decision → gate → actuator).

Catalog: ~50 controllers across breakers/approval gates (incl. guardian
deny-on-silence + 2oo3 consensus), sensors/emitters, the Lyapunov detector
family (stop-hook, disk, PSI hysteresis with previous-level memory, debounced
SLO pager, Welford drift/anomaly, CV failure classifier, health calculus,
formal Lyapunov proof, entropy alarm, 4-tier freshness ladder), aggregators/
gates (meta-falsification!, fitness, CI/CD, invariant, sentinel, SLO tracker),
release path (canary no-data-no-promote, rollback-on-budget, IEC 61508
degradation ladder, OTP restart budgets), interlocked actuators (autofix:
disabled-by-default + guardian + cooldown + bounded batch/wall-clock +
heartbeat; muda prune), and pure estimators (PID, Kalman, uncertainty,
capacity EMA, endocrine, QoS admission).

Two load-bearing design results adopted:
1. **The two-lattice algebra**: evidence (Verified<Unmapped<Blocked<Divergent,
   empty=Unmapped) ⊥ control (Green<P2<P1<P0, empty=Green); sanctioned
   morphisms = read-only observation, refusal-via-R13 (absence of evidence +
   Blocked diagnostic), exit codes; FORBIDDEN and to be pinned as a law test:
   any `alert -> verdict` function or alert-conditioned evidence write.
2. **Meta-falsification as required test shape**: every detector must have a
   test proving it trips on synthetic bad input (already true for the frontier
   gate's 300 chaos injections; becomes the house rule).

Accepted import queue (ordered): 1 exit-teeth on remaining entry points;
2 runbook_registry (fail-closed tracked-runbook gate); 3 oracle_freshness
(4-tier ladder + binary-vs-receipt staleness); 4 sentinel_patrol (autonomous
re-observation as a WORK QUEUE, never a verdict); 5 pressure_governor
(hysteresis backpressure); 6 quarantine_registry (flap isolation that never
suppresses evidence); 7 reliability_drift; 8 failure_pattern (CV classes);
9 loop_slo (loop budgets ONLY — no parity error budget, posteriors already
own that); 10 countermeasure_actuator (one whitelisted class, full autofix
interlock set, last deliberately); 11 chaos_probe (game-day meta-falsification
of the whole control plane).
