# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current Takeover

Read `CLAUDE_HANDOVER.md`, then `HANDOFF.md` and `docs/AGENT_HANDOVER.md`, before
acting. The OCaml-5.5/Bonsai/Dream implementation payload is
`a482ff97d464a9926d3ffd0bc7c0083d1af3434c` on `origin/master`; the current
successor only collates handover state. Preserve the unrelated journal and
staged ZK changes named there, reconnect the harness MCP server, verify the
exact current HEAD through `--verify-cycle`, and pull live position through
`--ooda-observe`. Never inspect the database outside the harness or authored
OCaml.

## What this is

beam-zig / zigvm: a BEAM (Erlang/OTP) virtual machine written in Zig, built end-to-end with Algebra-Driven Design. Every subsystem is specified as an algebra (signature + laws + semantic domain), implemented twice — an obviously-correct **oracle** (initial encoding) and an efficient **final** encoding — and glued by twin-seeded homomorphism property tests at every representation boundary. All 14 milestones are complete (historical baseline 102/102 law tests, gates G1–G6 passed; the suite grows as the active program lands — the invariant is `All N tests passed.` + exit 0, not a fixed N). The active program is **`OTP30_PARITY_PLAN.md`** — epoch series E0–E9 toward full functional/performance/scalability equivalence with pinned OTP 30-rc, with a harness conformance protocol (ledgers, differential suites, ratcheted benchmarks/scaling bands); `skills/otp-conformance-protocol/SKILL.md` governs that work.

The VM is pure Zig under `src/`; verification and orchestration live in an OCaml harness under `harness/`. `AGENTS.md` is the binding rulebook for agents — read it first. The program's operating system beyond code: `SAFETY_ANALYSIS.md`/`CAST_LOG.md` (STPA/UCA/FMEA constraints that bind agents), `SDLC_SRE_PROCESS.md` (lifecycle, SLOs, incident/change process), `DIVERGENCE_LOG.md` (EQUIV ledger), and the repo skills under `skills/` (31 total; 25 of them linked under `.claude/skills/` for direct invocation — `algebra-driven-ocaml` is the foundational doctrine for all authored OCaml; `algebraic-fractal-structures` + `otp-conformance-protocol` + `stpa-safety-protocol` are the governing parity trio; `fractal-decision-calculus` is the cross-cutting decision protocol (Cynefin/Admiralty/AHP/ACH/pre-mortem/Bayes in a fast OODA-verify loop); `smp-concurrency-slice`, `capability-eq-flip`, `production-readiness`, `harness-supervisor`, `formal-technique-selection`, `ocaml-scripting`, `zk-knowledge-base`, `bonsai-ui-development`, `tyxml-conversion`, `mobile-first-adaptive-ui`, `ocaml-playwright-control`, `ocaml-figma-control`, `infranodus-design-superset`, `approach-b-zero-muda-observability`, the symbiosis skills (`codex-symbiosis`, `gemini-symbiosis`), and the intelligence-substrate workflows (`smtml-solver-substrate`, `raven-ml-substrate`, `stan-probabilistic-substrate`) are the per-front workflows; the remaining 6 — `docs-design`, `formal-verification-pipeline`, `fractal-workspace-audit`, `living-ontology`, `wiki-design`, `c3i-temporal-orchestration` — are reference-only, not directly invocable; canonical enumeration in `skills/README.md`). The repo-local `.codex/skills/`, `.gemini/skills/`, and `.agents/skills/` mirrors must expose the same linked set.

**New to design or web-UI work here?** Start with `docs/BEGINNERS_GUIDE.md` — a descriptive+prescriptive on-ramp with diagrams, a RACI, the five jobs you will actually be asked to do, and a poka-yoke table mapping each control message to its fix.

## Commands

One-time setup (exact OCaml 5.5.0 local switch, tracked pins and PPX closure):

```sh
opam switch create . ocaml-base-compiler.5.5.0
opam install bos.0.3.0
scripts/setup_ocaml_550.ml --install
scripts/setup_ocaml_550.ml --check
```

The admitted web stack is Bonsai/Bonsai_web/Virtual_dom
`v0.18~preview.130.106+341` plus Dream `dev`, built from exact upstream
revisions and tracked OCaml-5.5 patch mailboxes. `harness/ui_web/main.ml` is the
authored Bonsai frontend; `zigvm-web` is the Dream backend. Browser JavaScript
is generated only. Start the read-only dashboard with
`ZIGVM_DREAM_PORT=8090 opam exec -- dune exec ./harness/zigvm_web.exe`; all
database reads pass through the harness `Db` actor.

All browser automation is direct typed OCaml through the pinned and patched
`ocaml-playwright` binding. Shell, Python, Node-authored, JavaScript/TypeScript,
Playwright CLI, and MCP browser controllers are prohibited. The complete
Microsoft Playwright v1.59.0 source/docs tree is a source-only dependency
reconstructed and verified by `scripts/setup_ocaml_550.ml`; the OCaml ontology
totals all 3,089 artifacts, 231 docs assets, 41 package manifests, 304 protocol
commands, and 62 events. Typed protocol and supported browser-runtime control
are complete; whole-product Test/CLI/MCP/reporter/viewer/UI parity is partial
and must remain explicit. Use `skills/ocaml-playwright-control/SKILL.md`.

Figma is governed by `harness/figma_design.ml`: OCaml owns the design algebra,
while Figma MCP is an external editable interpretation. Runtime agreement is
established only by direct OCaml Playwright against the Bonsai UI. Use
`skills/ocaml-figma-control/SKILL.md`; never treat a Figma frame as runtime or
feature-parity evidence.

The canonical verification gate — the only completion evidence:

```sh
opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD"
```

The gate is green if (`All N tests passed.` + exit 0) and the SQLite `harness_runs.status = ok` is verified by the Zero-Trust rule gate (a naive forward-chaining production-rule matcher in `harness/rete.ml` firing `rete_rules.ml` — historically branded "Rete-UL", but it is NOT the Rete algorithm and has no unlinking; the guarantee is fail-closed gate mediation, not incremental matching). Task closure is guarded by this gate; failure to produce a valid SQLite green-stamp for the exact commit leads to rejection of the `record_cycle`. 

It runs, in order: language-boundary checks → artifact inventory → doc checks (including skill frontmatter validation) → fixture mirror checks → the Zig law suite (`zig test src/vm_all.zig`). Every run logs state, events, command output, and artifacts to SQLite at `harness/state/zigvm_harness.sqlite3`.

Partial modes: `--check-only` (skip the Zig suite), `--check-docs`, `--check-design` (design-surface governance: SC-F registry totality + reference-cleanliness + phase-runbook totality P0..P9; ALSO runs inside `check_docs`, so it is in the default gate), `--check-lint` (TOTAL-corpus document lint over 20 rules and five artifact kinds; also inside `check_docs`. Two ALGEBRAS back it — `docs/design/TABLE_ALGEBRA.md` (GFM tables: header + delimiter of equal arity + body; header-anchored arity check) and `docs/design/HTML_ALGEBRA.md` (a real tokenizer, so comments/raw text/attribute values are opaque by construction) — each with an ontology, oracle+final encodings, and laws executable in `--verify-formal`. TWO-TIER STANDARD: an authored document is held to what a renderer does with it; **every finding on a GENERATED artifact is an `Error`**, no ratchet, no exception. Ratchet `docs/design/lint-baseline.txt` is at **errors = 0, warnings = 0**, so any new finding fails the gate. NARROW BY DESIGN — not a conformance checker; benchmarked against W3C vnu, markdownlint, remark-lint, html-validate and HTMLHint in `docs/design/LINT_BENCHMARK.md`), `--check-fixtures`, `--list-artifacts`. Standalone skill validator: `opam exec -- dune exec ./harness/zigvm_skill_validator.exe -- --root "$PWD" [SKILL_DIR ...]`.

On-demand development/evidence controls (not in the per-task default gate — run when the workflow calls for them, per `docs/CLAUDE_HARNESS_SOP.md` §5d):
- `--seed-sweep` — run the Zig law suite under a fixed set of test-order seeds (incl. the CAST-17 adversarial seed) so layout/order flakes surface deterministically (GATE-DETERMINACY); any reddening seed is a red, fixed by constructive determinism, never by re-seeding.
- `--run-suites` — run **71 of the 73** test executables (~5 s total). Each gets its OWN scratch dir via `TMPDIR`, and the suites resolve scratch paths through `Filename.get_temp_dir_name ()` rather than hardcoded `/tmp`, so concurrent sessions cannot race on one database. **The `db_suite_manifest` rule in `harness/dune` names every suite's build artifact as a dep of a module the harness LINKS, so building the harness builds all 73 — a suite that stops compiling breaks the gate's own build.** That compile guarantee is in the default gate; the running is on-demand, because several suites read `docs/` and would redden on an unrelated journal regeneration. `built` is derived from the rule's `%{deps}` and `runnable = built \ never_runnable`, so the partition is total by construction and a NEW suite is runnable by default — opting out costs a written reason in the registry, which is ratcheted at 2 entries (`test_viz`: opens the live evidence DB; `test_ui_pages`: a `(modes js)` browser bundle with no native executable).
- `--evidence-census` — is the evidence retained at the granularity of the claims made from it? Reports the retention lattice (`Ephemeral < Aggregate < Durable`) across SEVEN scales (L0 programme → L6 input) with LIVE counts read through the harness `Db` actor. **Measured answer:** L0–L3 and most of L4 are durable row-level; the 1,116 Zig laws are **Aggregate** (one command, one blob — no query can say when a named law last passed); the compared bytes are aggregate; an ad-hoc probe is ephemeral. The load-bearing law is `NO-OVERCLAIM` — a rollup may not report more resolution than its children retain. Ontology/atlas/algebra: `docs/EVIDENCE_DURABILITY_FRACTAL.md`. Structure laws run in the DEFAULT gate; only the live counts are on-demand.
- `--oracle-vectors` — re-derive the committed differential fixtures (`fixtures/erl/*_diff.erl`) against the PINNED OTP-30 oracle: compile with the pinned `erlc`, run on `erl` and on zigvm, byte-compare, record one verdict row per vector (`kind='oracle-vector'`) keyed to the pin. **43 of these were committed, cited by name across the capability ledger as the evidence behind EQ/EQUIV verdicts, and executed by NOTHING** (DIVERGENCE 774) — a differential the gate never runs is the same defect as an EQ claim nobody checks. The pure REGISTRY half is in the DEFAULT gate (12 laws, incl. `DISCOVERY-TOTALITY` reading the filesystem rather than the registry, and a RATCHET on the unwired count), so a NEW vector cannot land dead; only the live re-derivation is on-demand.
- `--replay-l1` — the deterministic-replay END-TO-END verdict: build the vendored QEMU TCG plugin (`vendor/qemu-plugins/insn.c`, unmodified upstream), record once under `-icount shift=0,rr=record`, replay the FIXED recording TWICE, and require the two instruction counts EQUAL **and** > 0. Equality alone is vacuous — two empty replays agree, which is a failure this epoch actually measured. Emits fractal, report-only telemetry (human lines carrying layer/plane/station/slice, metrics JSON, OTLP JSONL in Unix nanoseconds) under the gitignored `.replay-build/`. The PURE half of the algebra (`replay_e2e_core`, 14 laws incl. the `OBSERVER-DOES-NOT-DECIDE` hyperproperty) runs in the DEFAULT gate on any host; only the QEMU measurement is on-demand.
- `--capability-ledger` — classify every OTP-30 production-surface feature on the {C} axis (`ABSENT<UNTESTED<EQUIV<EQ`) with TOTALITY/HONESTY/LATTICE/SLICE-LINKAGE laws + a severity-weighted production-readiness scorecard.

**MCP staleness rule:** after ANY `harness/*.ml` edit + rebuild, the long-running `--mcp` server keeps its OLD in-process code and fails closed with `STALE-HARNESS` on every `tools/call` (h-mcp-staleness). The CLI/gate always run the freshly-built executable, so use the **CLI for evidence**; to use the **MCP tools**, reconnect the server (`/mcp reconnect` in the client) after the final harness build.

**Zig toolchain discovery** (harness order): `$ZIGVM_ZIG` (explicit zig binary) → `.zig-tools/bin/python3 -m ziglang` (repo venv pinning **Zig 0.16.0** — the normal path; gitignored, recreate with `python3 -m venv .zig-tools && .zig-tools/bin/pip install ziglang`) → `zig` on PATH (last resort; the system zig may be older than the suite requires). Zig caches are forced under `/tmp`, **per-root by default** (`/tmp/zigvm-harness-cache-<hash-of-abs-root>`, so two worktrees NEVER share a cache and can't cross-poison — h-cache-iso / DIVERGENCE 52); override with `$ZIGVM_CACHE_ROOT`.

Iterating on one test during development (never completion evidence):

```sh
# Manual iteration runs zig DIRECTLY (not via the harness), so give each tree
# its own scratch cache — reuse the harness's per-root convention to avoid
# two trees colliding on one shared cache dir (h-cache-iso).
CACHE=/tmp/zigvm-harness-cache-$(printf '%s' "$PWD" | md5sum | cut -c1-12)
ZIG_LOCAL_CACHE_DIR=$CACHE/local \
ZIG_GLOBAL_CACHE_DIR=$CACHE/global \
.zig-tools/bin/python3 -m ziglang test src/vm_all.zig --test-filter "<substring>"
```

Env overrides: `ZIGVM_ZIG`, `ZIGVM_CACHE_ROOT`, `ZIGVM_HARNESS_DB`.

## Hard boundaries (mechanically enforced — the gate goes red otherwise)

- `src/` is Zig-only; non-Zig files are allowed only as embedded fixtures (`.beam`, `.bin`, `.txt`).
- `harness/` is OCaml-only (`.ml`/`.mli` + `dune`), built with Dune, packaged with opam; runtime state only under `harness/state/` as SQLite files.
- Database access must go through the harness or authored OCaml code. Never use the SQLite CLI, Python bindings, shell SQL, or another language client; add/use a harness mode or typed OCaml operation.
- **Three authored languages only.** The SYSTEM's authored implementation is Zig (`src/`), OCaml (harness + all tooling, `harness/`+`scripts/`), Erlang (fixtures, `fixtures/`) — nothing else. **C/C++/Rust are permitted ONLY as EXTERNAL LIBRARIES accessed through OCaml FFI** (e.g. `vendor/zenoh-c`, a native C lib bound by `harness/zenoh_ffi.ml`/`zenoh_c.ml` via Ctypes) — never as authored, standalone, or in-tree system code. **Python and shell are banned outright** (no FFI exception); **JS/TS only ever as generated codegen TARGETS** (`web/atlas.ts`/`web/dist/atlas.js` emitted by `harness/atlas_ts.ml`, `generated/lean/*.c`). Generated codegen targets + vendored third-party libraries are OUTPUTS/DEPENDENCIES, not implementation. Under this rule (2026-07-31): all authored Python/shell + the *unbuilt/quarantined* Rust `rete_ffi` were removed (`9e7ed34`), 829 non-language stragglers purged from the root (`d173902`), and the repo ROOT is now boundary-scanned by the gate (`check_boundaries`, DIVERGENCE 724); the live C-FFI dep `vendor/zenoh-c` is kept. **Two narrow intrinsic-C carve-outs** (neither authored system code, both where C is mechanically mandatory, both honestly disclosed): NIF test fixtures (`fixtures/**/nif/*.c` — an Erlang NIF *is* a C shared object, so the fixture exercising the NIF-load path is C, exactly like a `.beam` fixture) and the coverage-instrumentation C-ABI shim (`docs/coverage/sancov_runtime.c` — Zig `-fsanitize-coverage=trace-pc-guard` emits calls to C-ABI `__sanitizer_cov_*` callbacks that must be provided at link time). **A third disclosed dependency (2026-08-03, Stan/stanc3, under an explicit user mandate, governed by `skills/stan-probabilistic-substrate`):** `stanc3` is the Stan compiler, itself written in **OCaml** — a vendored OCaml-library dependency (`stanc.driver`/`stanc.frontend`, exactly like `smtml`), NOT authored system code. It is linked ONLY inside the standalone `harness/stan_infer.ml` executable (isolated in its own exe so stanc3's Jane-Street `Core` cannot collide with the harness's preview `Core`); the main harness invokes that exe via **Unix exec** (`--stan`, no shell). The authored `.stan` generative models are committed under `docs/stan/` (`fdc_bb.stan` conjugate + `fdc_logistic.stan` non-conjugate); stanc3's transpiled C++ `.hpp` is a generated codegen target emitted to scratch, never committed; and the Stan **C++ MCMC sampler runtime (cmdstan + stan-math: Eigen/Boost/Sundials/TBB) IS built** as a vendored, **gitignored** checkout (`vendor/cmdstan/`, rebuild recipe `docs/stan/README.md`) — used ONLY via **Unix exec** of the compiled model executable (exactly like the Zig toolchain, no shell), with the MCMC posterior **admitted against the exact conjugate closed form** (`harness/stan_bridge.ml`, fail-closed) and NON-conjugate models (logistic regression) sampled the same way. The authored `.stan` models are committed in `docs/stan/`. All of it is **report-only, never a decision authority** — posteriors ANNOTATE the FDC gates (Admiralty A2, CR<0.10, the Coq proofs, the armed Rete rule), they do not gate. Additionally, a **native pure-OCaml MCMC sampler** (`harness/stan_mcmc.ml`, seeded Metropolis-Hastings) runs in-process with **no CLI/C++** — the answer to "MCMC directly via OCaml" — admitted against the exact conjugate oracle (the admission triangle: exact ≡ cmdstan NUTS ≈ native MH); and `harness/stan_report.ml` publishes each decision cycle's posterior with a plain-language ("idiot-proof") lead, an ASCII credible-interval chart, a fail-closed TRUST verdict, and the full interpretation, to a durable ZK note. **Since the S2 serving-flip (2026-08-03): every decision-SERVING Stan read is computed by the native OCaml engine (subprocess-free — the SC-STAN-5 `stan-serving-no-subprocess` source-scan law binds the five serving modules), and cmdstan runs ONLY inside admission laws whose surfaced output is ADMITTED/FAILED verdicts (a built-but-silently-skipped oracle fail-closes via `stan-oracle-still-exercised`).** Full record: `docs/journal/20260803-stan-full-integration-journal.md`.
- The harness may execute the Zig toolchain but must never reimplement VM semantics outside Zig.

### Doc-gate literals to preserve

- Required docs must exist (don't rename/delete): `AGENTS.md`, `HANDOFF.md`, `ROADMAP.md`, `CODEBASE_MAP.md`, `ARCHITECTURE.md`, `MUTATION_LOG.md`, `IMPLEMENTATION_PLAN.md`, the four `ALGEBRAIC_*.md`, `docs/zigvm-session-record.md`, `skills/algebra-driven-ocaml/SKILL.md`, `skills/algebraic-fractal-structures/SKILL.md`, and the three `docs/references/` artifacts.
- `AGENTS.md`, `HANDOFF.md`, `ROADMAP.md`, `IMPLEMENTATION_PLAN.md`, and `docs/zigvm-session-record.md` must each contain the canonical gate command string verbatim; `HANDOFF.md`/`ROADMAP.md` must not present direct ziglang execution as the primary gate.
- Every `skills/*/SKILL.md` needs YAML frontmatter with exactly `name` (matching the folder, lowercase/digits/hyphens) and `description` (non-TODO).
- Fixture mirrors: every `@embedFile("X")` in `src/` must exist there **and** byte-match its vendored copy in `fixtures/` (`src/isa_opcodes.txt` ↔ `fixtures/opcodes.txt`; `mylists.beam`, `opnames.txt`, `etf_vectors.bin`, `etf_bigmap.bin` same-named).

## Architecture

A VM is a stack of representation changes that must each preserve meaning (terms → tagged words → GC-relocated words → serialized words; programs → bytecode → dispatched execution), so correctness is expressed as one semantic domain per subsystem plus a homomorphism law at every boundary — e.g. copying GC is specified entirely by `denote(after) == denote(before)`, and threaded dispatch is admitted only by differential equality against the interpreter. `ARCHITECTURE.md` explains this; `CODEBASE_MAP.md` maps all 211 erts source files to subsystems S1–S33 with strata:

The whole-system vocabulary is canonical in `docs/ONTOLOGY.md` and
`docs/FRACTAL_ONTOLOGY.md`, with its executable OCaml projection in
`refresh_ontology`. Any change to a layer, plane, component, subsystem,
interaction, controller, evidence store, route, or agent surface updates that
registry and passes `--wiki-audit`. Database access remains harness/OCaml-only.

- **Stratum A (algebraic core)**: pure law-governed domains — full oracle + final + homomorphism treatment.
- **Stratum B (engines)**: schedulers, GC machinery, dispatch, ports — verified *against* Stratum A by trace/differential equivalence.
- **Stratum C (substrate)**: allocators, OS glue — quarantined; no Stratum-A law may depend on it.

28 modules under `src/` (~12.9k lines), aggregated by `src/vm_all.zig` (`refAllDecls` pulls every module's tests). Dependency spine: terms (`term_algebra`, `atom_table`) → maps/binaries/hashing (`map_algebra`, `bin_algebra`, `term_hash`) → patterns/mailbox (`pattern_algebra`, `mailbox_algebra`) → instructions (`instr_algebra`) → processes/scheduling (`proc`, `timer_wheel`, `time_algebra`, `gc`) → loading/dispatch/distribution (`beam_loader`, `transform`, `dispatch`, `dist`), with `etf`, `unicode`, `code_index`, `code_server`, `registry`, `trace`, `boot`, `matchspec`, `ets_algebra`, `port_algebra`, `nif_resource`, `diag` hanging off the spine.

Every module's doc-comment is its specification: signature, semantic domain, oracle/final encodings, laws, and scope limits, in that shape. Read it before touching the module.

## Changing behavior — the mandatory loop

Follow `skills/algebraic-fractal-structures/SKILL.md` (the operational workflow) and the required reading order in `AGENTS.md`. The non-negotiables, from `HANDOFF.md`/`ALGEBRAIC_FRACTAL_RULES.md`:

1. Write the semantic domain before code; identify oracle and final encoding (semantic-precursor slices must say so explicitly and still ship laws).
2. Laws are named after algebraic properties (homomorphism, monoid, round-trip, total order, idempotence, rejection, …); observational equality only — never pointer/address identity.
3. Seeded generators that echo their seed on failure; bounded test drivers (a hang is a failed law, never a stuck suite); exhaustive switches over domain unions; explicit arena/heap ownership; zero leaks (`std.testing.allocator` proves it).
4. Plant ≥2 mutants per landed slice and record them in `MUTATION_LOG.md` (kill or document as EQUIVALENT).
5. Sync docs on completion: module doc-comment, `HANDOFF.md`, `ROADMAP.md`, `CODEBASE_MAP.md`, `IMPLEMENTATION_PLAN.md`, `ALGEBRAIC_RULES_USAGE.md`, `ALGEBRAIC_DOC_REVIEW.md` (+ `ALGEBRAIC_PROGRAMMING_REFERENCES.md` if the rule map changes).
6. Finish with a green harness run and cite the SQLite run status (`harness_runs.status = ok`).
7. Slices touching a controller or evidence path (harness modes, engines, SQLite writers, baselines) additionally fill the safety packet of `ALGEBRAIC_FRACTAL_RULES.md` §10 (STPA/UCA/FMEA + priority), per `skills/stpa-safety-protocol/SKILL.md`; a red gate gets a `CAST_LOG.md` cause entry before any re-run.

Current next best target: **whatever the kanban `next_slice` returns** (MCP `next_slice` / `--ooda-observe`) — never a hard-coded epoch written here (numbered epochs E0–E46+ are closed history in `DIVERGENCE_LOG.md`; the live fronts are the `gap-*` production-axis slices and the S-epoch coordinator-lock narrowing, DIVERGENCE 612–614). Close every slice with `--record-cycle <slice> ok "<notes>"` (Zero-Trust CLI; the stamp is keyed to the exact commit — commit first, gate on that commit, then record).

## Default operating mode — the fractal OTP-parity loop (max-parallel discovery, serial-gated fix, live dashboard)

This is the **standing default** for OTP-30 parity work (not opt-in): run OODA at max parallelization with multilayer supervised agents and a fast fix cadence, always fed by the real OTP-30 oracle and always fronted by a live dashboard. The steps:

1. **Discover in parallel (read-only fan-out).** Fan out differential probes as a background `Workflow` — each agent writes real Erlang fixtures, runs them on BOTH the pinned OTP-30 oracle (`third_party/otp/bin/erl`) and zigvm's CLI (`zig-out/bin/zigvm run --code-path <stdlib+kernel ebin> …`), and byte-diffs. **VERIFY BY VALUE** (`length/1` + `=:=`), NEVER by an `erlang:display` string alone — display stringifies char lists and the terminal mangles control chars (this false-positived "data loss" once; DIVERGENCE 686/693). Probe/RCA agents are **strictly read-only**: they use the pre-built binary, NEVER `ziglang build`/`test` (races the shared cache), NEVER `git commit`. Include a **regression agent** (re-verify the landed fixes still byte-EQ). Rebuild the binary to HEAD *before* launching so agents probe current code.
2. **Fix serially, gated (the OODA "act" — this CANNOT parallelize).** Per bounded gap: reproduce vs OTP by VALUE → RCA to the exact `src/` file+line → minimal fix → a named **LAW** (byte-EQ vs the oracle's exact bytes) → **≥2 mutants** killed via the **full suite** (`--test-filter` silently runs only `test_0` when the law name has `/`,`:`,`{`,`<` — use the whole suite for kills) → the canonical gate green → commit (stage EXACT files) → push → `--record-cycle`. One coherent slice per commit; probe with a **runtime** value not a literal (erlc constant-folds `integer_to_list(10^41)` etc., masking dead BIFs — DIVERGENCE 687/703).
3. **Honesty is non-negotiable (FM-OBS-1).** Never fabricate EQ or a plausible metric constant; a value that can't be truthful returns `not_implemented`/`badarg`. A repr-coupled value (erts word counts, `ets:info(_,memory)`, map/set iteration order, list ORDER of `module_info`) is **EQUIV, not byte-EQ** — implement it as a real function of state (never a constant) and DISCLOSE the residual. A "finding" is real only when reproduced by value on both VMs; blocked/unverified agent hypotheses are checked directly before acting (several were false alarms).
4. **Dashboard + KPIs are always live (AS-IS vs TO-BE).** Regenerate the conformance dashboard (KPIs, per-surface health, ranked-backlog burndown with fix status) after each landed fix. It MUST be **locally generated AND served over Tailscale** via the persistent `zigvm-dashboard.service` systemd --user unit (`http://vm-1.tail55d152.ts.net:8092/`); the generator dual-writes to `/home/an/zigvm-dashboard/index.html` so the endpoint auto-syncs. Keep the claude.ai Artifact in parity. Setup + regen recipe: the `zigvm-dashboard-tailscale` memory.
5. **Survive concurrent sessions.** Other agent sessions commit to master + hold uncommitted `harness/*` WIP. On a `DIVERGENCE_LOG` number collision, CEDE it and rename to the next free one. CHAIN `gate && --record-cycle` in one command (HEAD moves between them otherwise → Zero-Trust rejects the stamp). Stage EXACT files (never `git add -A`); leave other sessions' WIP untouched; re-fetch before assuming git state. A transient host-load ABRT (`signal ABRT`, an unrelated test) or a harness build-break from concurrent WIP clears on re-run/retry — it is NOT your slice's failure.

Governing skills: `skills/otp-conformance-protocol` (the verdict/ratchet law), `skills/capability-eq-flip` (the dispatch-dead sweep+wire mechanics), `skills/algebraic-fractal-structures` (the per-slice packet). This mode composes them; it does not replace the mandatory loop above (laws + mutants + docs + green gate still bind every slice).

## Testing Disciplines Rule (mandatory)

Four disciplines answer four different questions; a slice is not covered until
each is answered or explicitly excused. Canonical: `AGENTS.md` and
`docs/TESTING_DISCIPLINES.md`.

- **TDD — law first.** Semantic domain, oracle and final encoding, a named law,
  **≥2 planted mutants killed via the FULL suite**, green gate, recorded cycle.
  `--test-filter` silently runs only the first test when a law name contains
  `/`, `:`, `{` or `<`.
- **BDD — a sentence someone can disagree with.** Any slice changing PUBLISHED
  OUTPUT needs a named scenario first; the pinned markdown quirks change only
  through a deliberate amendment with a failing scenario, never silently.
- **Property — laws over a generated domain.** Generators are DERIVED
  (`ppx_deriving_qcheck`); model-based testing runs the implementation against
  its oracle as the model (`ortac-qcheck-stm`). Hyperproperties such as
  non-interference relate TWO runs, so test pairs.
- **A REAL artifact, end-to-end.** Mutants are scored against the SAME fixture
  the law uses, so a mutation score measures the LAW, not the code. A slice
  scored 2/2 on mutants, passed its law, and corrupted `maps:fold_1`. A slice
  changing how real programs execute needs a law that runs a REAL compiled
  artifact, and any law with operands/positions must ENUMERATE them.
- **Chaos — vary the WORLD, not the input.** Any environmental claim (crash
  recovery, at-least-once delivery, concurrency, offline, tool availability)
  must inject the corresponding fault. The property is never "it didn't crash":
  a disturbed run must not produce a GREEN verdict it did not earn.

A law only counts when the GATE runs it — registration in the `Render_suite`
registry is what makes that true. Laws over behaviour-changing edits to
VENDORED code are mandatory, and every acceptance law needs a rejection
counterweight, or a checker that accepts everything would satisfy it.

## Fractal FP Atlas Sync Rule

The typed registry is `harness/fractal_fp_atlas_surface.ml`. If the exact
commit diff intersects a registered code, rule, agent, skill, SDLC/SRE, safety,
ontology, plan, handoff, journal, or generated-projection surface, repair its
markers, regenerate all eleven artifacts with
`dune exec ./harness/render_fractal_fp_atlas.exe`, run
`--selfcheck-fractal-fp-atlas` plus `--wiki-audit`, and record
`phase:atlas_sync`. The token records execution but cannot mint evidence; the
exact-head Green Stamp remains authority. Unrelated ZigVM paths are excluded by
the typed classifier. See `SC-FP-ATLAS-SYNC` and safety packet
`CA-49`/`UCA-49.1`/`SC-49.1`.

## Approach B Journal/Design Bundle Hard Control (standing)

The shared hard rule is canonical in `AGENTS.md`: recurrent journal/design
publication uses the versioned typed OCaml bundle algebra; bounded parallelism
must equal its sequential oracle; Swiss character and ZERO-MUDA require one
acquisition, cached wiki work, one HTML render, and atomic identical fanout.
Every stage prints actual/budget time and emits report-only TUI/dashboard/
metrics/OTEL observations; stage budgets and the <1500 ms cache-hit warm-path
budget fail closed. TDD, BDD, property/mutant laws, typed OCaml Playwright,
STPA/FMEA, ACH, Admiralty grading, devil's advocacy, and a bounded reality
check are mandatory. New human timestamps use `YYYYMMDD-HHMMSS`; OTEL retains
Unix nanoseconds; delivery requires `--check-time`. Full contract:
`skills/infranodus-design-superset/references/execution-character.md`.
Its OAIS-inspired extension recomputes SHA-256 for every AIP/DIP copy and uses
the journal→atomic-zettel→wiki profile in `docs/PKM_ARCHIVAL_ARCHITECTURE.md`;
open files remain authority and external archival identifiers/certifications
are never invented.
Logseq follows the total OCaml disposition registry and fractal contract in
`docs/LOGSEQ_OCAML_SUPERSET_ARCHITECTURE.md`; unsupported external DB/RTC/
mobile/plugin behavior may never be relabeled as local implementation.

The closure lattice is exactly `Verified | Rejected_by_policy |
Unavailable_observed`; pending/unknown state and fabricated external success
are prohibited. New bundle identity is SHA-256. Publication is a serialized,
per-target atomic, crash-recoverable transaction—not simultaneous
multi-target atomicity. Machine/human closure authority is projected at
`docs/ontology/INFRANODUS_FRACTAL_CLOSURE.json` and
`docs/INFRANODUS_FRACTAL_CLOSURE.md`.

## Sa-plan Durable Control Contract (20260804)

Sa-plan task/job/workflow truth lives only in the typed OCaml `Sa_plan.Store`.
Execution is leased and at-least-once; stable activity keys provide idempotent
observable effects, not exactly-once external execution. Bonsai/TUI/journal/
telemetry views are read-only. C3I/Rust comparisons use
`Sa_plan.C3i_reference`; absent runtime behavior is `Unavailable_observed`.
