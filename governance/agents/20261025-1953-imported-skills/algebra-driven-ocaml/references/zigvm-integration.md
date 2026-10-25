# ZigVM Fractal Integration

## Contents

1. Authority and boundaries
2. L0-L10 crosswalk
3. Control and data flow
4. STPA mapping
5. Rete-UL and ruliology
6. Stan and decision support
7. Harness verification
8. Skills, agents, and artifacts
9. System qualities and distributed messaging

## 1. Authority And Boundaries

`algebra-driven-ocaml` is the primary doctrine for authored OCaml. It does not
move ZigVM semantics into OCaml. Compose it with:

- `algebraic-fractal-structures` for Zig VM algebras;
- `ocaml-scripting` for the exact OCaml 5.5.0 toolchain and automation;
- `stpa-safety-protocol` for controllers and evidence paths;
- `formal-technique-selection` for proof, SMT, model checking, Rete, or
  ruliology technique fit;
- `harness-supervisor` for L0-L3 OODA orchestration;
- `stan-probabilistic-substrate` for report-only inference;
- `ocaml-playwright-control` for direct typed browser automation;
- `mobile-first-adaptive-ui` for Bonsai layout and accessibility laws.

Hard boundaries remain:

- VM semantics are Zig-only under `src/`.
- Harness, scripts, backend, generated frontend source, and control logic are
  authored in OCaml.
- Database access uses the harness `Db` actor or authored OCaml only.
- Browser automation is direct OCaml through the patched Playwright binding.
- C/C++/Rust are external FFI dependencies only; shell and Python are not
  authored project automation.

## 2. L0-L10 Crosswalk

| Layer | Doctrine object | ZigVM realization | Required evidence |
|---|---|---|---|
| L0 Boundary | toolchain, language, oracle, effect seams | exact OCaml 5.5.0, Dune/opam/PPX, Zig, OTP, external libraries | setup check and boundary gate |
| L1 Artifact | signatures, rulesets, proofs, journals, state | skills, docs, `.mli`/`.ml`, SQLite rows, git revisions | inventory and provenance |
| L2 Subsystem | bounded contexts and service algebras | harness, Dream, Bonsai, Sa_plan, formal mesh, S1-S33 | context laws and ownership map |
| L3 Module | module signature and interpretations | Dune-linked OCaml modules and Zig modules | conformance plus module laws |
| L4 Feature | user/agent-observable capability | CLI modes, MCP operations, routes, backlog and verdict surfaces | capability observation and rejection |
| L5 Representation | carrier, oracle, final encoding | semantic domains, ledgers, state machines, web read models | homomorphism or explicit bound |
| L6 Operation | constructor, combinator, observer, control action | harness functions, DB actor calls, graph/browser operations | operation law and effect contract |
| L7 Generator | seeded construction and fixtures | `Random.State`, corpus, OTP differential, viewport matrix | seed, bounds, replay |
| L8 Mutation | plausible wrong interpretation | mutant catalog, fault injection, counterexamples | named law turns red |
| L9 Verification | judge and exact-revision evidence | Dune tests, Zig laws, selfchecks, formal checks, canonical gate | green run bound to HEAD |
| L10 Governance | admission and safety constraints | AGENTS, skills, STPA/CAST, Rete rule gate, record-cycle | fail-closed admission record |

Every layer repeats ontology, signature, laws, interpretations, and
verification. A layer may delegate an obligation, but it may not omit it.

## 3. Control And Data Flow

```text
user requirement
  -> agent invokes doctrine
  -> observations/glossary/ontology
  -> signatures and law grid
  -> oracle implementation + seeded laws
  -> final/effectful interpretation + homomorphism
  -> focused tests and mutants
  -> canonical harness
  -> exact-HEAD cycle evidence
  -> Rete-UL record-cycle admission
  -> SQLite evidence and handoff
```

Database flow:

```text
agent/MCP/CLI -> authored OCaml -> Db actor -> SQLite
Dream -> typed read model -> Db actor -> SQLite
Bonsai -> Dream API; never SQLite directly
```

Probabilistic flow:

```text
recorded evidence -> Stan/native OCaml inference -> advisory report
advisory report -> decision log/orientation
advisory report -X-> law verdict, gate fact, or record-cycle authority
```

## 4. STPA Mapping

The doctrine is a governing process policy, not a new runtime evidence writer.
It constrains existing controllers.

| Existing controller | Control action examined | Unsafe action class | Doctrine constraint |
|---|---|---|---|
| Agent/workflow | confirm or assume a business law | provides wrong law / omits needed law | surface signature-changing laws and record assumptions |
| OCaml implementer | admit final encoding | admits too early or without homomorphism | oracle law suite must be green first |
| Harness gate | issue verification verdict | false green or stale evidence | exact-HEAD, bounded, replayable evidence only |
| Rete gate | admit cycle | accepts self-attested or missing facts | project facts from source, runs, diff, and ledgers |
| DB actor | persist evidence | wrong order, partial write, or bypass | typed OCaml transaction and single-writer discipline |
| Stan advisor | publish uncertainty estimate | estimate presented as proof/authority | advisory-only label, diagnostics, independent oracle |
| Browser controller | capture UI evidence | wrong viewport/state or incomplete teardown | isolated contexts, typed observations, fail-closed evidence |

At each slice, use the existing STPA packet: control actions, all four UCA
types, linked hazards, constraints, FMEA delta, priority, enforcement, and
residuals. Do not add a new safety ledger row solely because this skill was
invoked.

## 5. Rete-UL And Ruliology

The current Rete-UL gate mediates only live facts exposed by the harness. This
skill does not create a new gate rule by prose. Candidate doctrine facts are:

```text
law_register_present
oracle_suite_green_at_head
final_suite_green_at_head
homomorphism_green_at_head
mutants_killed_count
negative_conformance_observed
business_laws_confirmed
```

Arm a doctrine rule only after these facts have objective projections and a
law battery. Until then, enforcement is the existing project process, compiler,
test, document, ontology, and canonical gate.

Treat the six-phase workflow as a rewrite system:

```text
unframed -> requirements -> designed -> lawed -> oracle_green
         -> interpretations_green -> delivered
```

Ruliology obligations:

- termination: each transition discharges a finite artifact checklist;
- no phase-skipping critical pair: implementation cannot commute before law
  confirmation when the law is a business decision;
- idempotence: rerunning a completed gate without changed inputs preserves its
  verdict;
- confluence: alternate lawful implementation paths converge observationally;
- normal form: delivered means all required evidence fields are present;
- monotonicity: stronger verification may refine evidence but cannot silently
  weaken a confirmed law or accepted baseline.

## 6. Stan And Decision Support

Stan may help rank alternatives, quantify uncertain workload or failure rates,
and update OODA confidence. It cannot:

- define observational equality;
- confirm a business law;
- establish an invariant;
- admit an interpretation;
- satisfy a formal proof obligation;
- write or influence Rete gate facts.

Any use follows `stan-probabilistic-substrate`: real recorded data, a uniquely
probabilistic question, independent oracle, diagnostics/calibration, and
report-only output.

## 7. Harness Verification

Minimum project closure for a skill or OCaml doctrine change:

```text
zigvm_skill_validator
check-docs
wiki-audit when ontology changes
dune build/tests for touched OCaml
canonical zigvm_harness gate
```

Harness-engine changes additionally require the DB, graph, cache, scheduler,
shard, parallel, OODA, and SLO selfcheck battery. Browser changes require the
direct OCaml Playwright OODA matrix. Safety/control changes require safety sync
and formal/rule checks. Database evidence is inspected through harness modes,
never an external SQLite client.

## 8. Skills, Agents, And Artifacts

All agents read the same canonical skill under `skills/` through `.claude`,
`.codex`, `.gemini`, and `.agents` mirrors. `AGENTS.md` is binding; vendor
entrypoints add transport details but cannot weaken the doctrine.

Artifact ownership:

| Artifact | Role |
|---|---|
| `skills/algebra-driven-ocaml/` | reusable doctrine and templates |
| `skills/README.md` | canonical discoverability and linked/reference status |
| `AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `GEMINI.md` | synchronized invocation policy |
| `docs/ALGEBRA_DRIVEN_OCAML_DOCTRINE.md` | project-wide ontology and interaction map |
| `docs/ONTOLOGY.md`, `docs/FRACTAL_ONTOLOGY.md` | canonical system model |
| `harness/zigvm_harness.ml` | executable ontology projection and laws |
| `SAFETY_ANALYSIS.md` | existing controller/UCA/constraint source of truth |
| `harness/rete_rules.ml` | actual fail-closed rule authority |
| `HANDOFF.md` | continuity and exact verification status |
| session journal | prompt, assumptions, decisions, evidence, residuals |

Historical artifacts keep their historical counts and claims. Update only
current canonical inventories and entrypoints.

## 9. System Qualities And Distributed Messaging

Apply [system-qualities.md](system-qualities.md) at every affected L0-L10 layer.
In zigvm, map the quality planes as follows:

| Concern | Current carrier and authority |
|---|---|
| Control plane | MCP/CLI, Sa_plan workflows, agent supervision, Rete admission |
| Data plane | ZigVM terms/signals/distribution, Dream HTTP, graph jobs, Zenoh messages where explicitly wired |
| Evidence plane | harness runs, ledgers, logs, traces, screenshots, git revision |
| Actor plane | Riot-supervised workers and in-house OCaml actor patterns including the `Db` writer |
| Durable plane | SQLite event/work queues and git artifacts; off-host DR remains a separate SRE question |
| Observability | harness events, status modes, dashboards, coverage, traces, exact failure output |
| Evolution | signatures, exhaustive variants, schema/wire versions, compatibility patches, ratchets |

Zenoh has two truthful surfaces: native OCaml Ctypes/MCP publish-ping control
over external `zenoh-c`, and the separately verified Zig CRDT/mesh message
path. Do not infer that Bonsai, Dream, the DB actor, or every agent message uses
Zenoh. Any broader transport migration needs an oracle, lifecycle laws,
backpressure, security, failure/recovery, tracing, and compatibility evidence.
