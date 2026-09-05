# Journal: F Prime import — the harness as flight software (2026-08-08)

## The prompt (verbatim)

> f prime
> https://github.com/nasa/fprime
> https://nasa.github.io/fpp/fpp-spec.html
> https://fprime.jpl.nasa.gov/latest/docs/reference/api/cpp/html/
> https://fprime.jpl.nasa.gov/latest/docs/
> import all the documentation
>
> AS-IS
> - align f prime to sync and fully align with current system, create
>   fractal atlas, fractal algebra, fractal ontology and fractal map to
>   current harness and system architecture. map f prime specification to
>   ocaml language and constructs. . all constructs must be mapped fully.
>
> TO-BE
> - create the algebra, configuration grammer, behavior of the harness to
>   configure and execute different activities performed by the harness --be
>   as comprehensive and complete as possible, cover all fractal layers and
>   fractal components and fractal behaviors.
> testing - tdd, bdd, property testing, fuzz, chaos testing, formal
> analysis, formal tools, very strong typing.
> all aspects of system - harness and hermes should be fully configurable
> using this mode. create detailed list of features and documentation
> covering all sdlc and sre aspects.
> use rete ul, stan, z3, quint, Rcoq, stmml for all aspects of teh system
> -- continue the formal system slice in parallel
> - rcoq irs, rcoq, quint, etc -- all of them
> -- focus on making sure declarative , intent based mechansim is
> Automatically used for giving configuration and intent based operational
> instructions.
> The system should automatically converge the configuration to the intent.
> use formal checkers and automated techniques for doing this mapping
> seamlessly and correctly
> -- show and update the documentation

(One "continue" arrived mid-implementation; no course change.)

## What was done, in order

1. **Imported the documentation** (six fetches, never guessed): the fprime
   README, the FPP spec (three targeted passes: construct inventory;
   component/C&DH semantics; topology/instance/state-machine/type-system
   semantics), the docs map, the C++ API root, the JSON dictionary spec, the
   Svc::Health SDD. Committed digest:
   `docs/hermes/references/fprime-digest.md`.

2. **R14 survey before any code**: zigvm's component modeling is the
   `Component:*` typed-edge graph (already mirrored as `fractal_ontology`);
   its state-machine leg is the quint-sm differential (already mirrored as
   `test_quint_frontier`). c3i's contribution is the actor/heartbeat doctrine
   (already imported as homeostasis/control_plane). The typed port model,
   base-id/opcode dictionaries, pattern graphs, and the FPP state-machine
   sub-language exist in neither source — genuinely new imports. Overlap map
   updated with the provenance split.

3. **`fpp_model.ml` (TDD, stub-RED observed)**: the FPP metamodel — 14
   definitions, 18 specifiers, 11 state-machine elements, all kinds/
   severities/queue-full behaviors — with every semantic check the spec
   mandates as a named validator (FPP-NAME/TYPE/CMP/SM/INST/TOPO-*), each
   violation a fractal diagnostic at L3/contract, Specification origin,
   No_effect on parity (a model defect can never touch credit, R10).
   Emitters: FPP source text + the JSON dictionary per the published spec,
   fail-closed on invalid models. **64/0**: unit per law, 200 generated
   valid models clean, 100 injected defects each caught by its own check
   (meta-falsification), chaos (max_int span arithmetic, 60-component
   timing).

4. **`harness_topology.ml` (TDD, stub-RED observed)**: the harness AS an F
   Prime topology — 11 real components as instances (base ids 0x100..0xB00),
   13 direct connections in three graphs (evidence/gating/sweep), 4 pattern
   graphs (time←inventory, health←control_plane, telemetry←hermes_zenoh,
   event←fractal_diagnostic), the converge loop as the `ConvergeLoop` FPP
   state machine (OODA states; the choice node is the Kleene decision;
   `Anomalous` terminal = exit 2, human reset — L-09), the two lattices as
   separate FPP enums so the forbidden morphism is untypeable. **16/0**.

5. **The differential law earned its keep immediately**: every direct
   connection must lie over a fractal-ontology edge — and the
   `parity_compare → evidence_store` receipt flow had NO edge. The code was
   right, the ontology was wrong; edge added
   (`evidence_store Governs parity_compare`) with the finding recorded in
   the ontology source. Two encodings, one system: where they disagreed, one
   was provably wrong. Ontology now 25 components, 34 edges, **702/0**
   (includes the two new R12 entries `fpp_model`, `harness_topology` + 3
   edges).

6. **Formal leg (`test_fprime_smt.ml`, smtml/Z3 in-process, 8/0)**: proved
   the thing the OCaml validator cannot prove about itself — the
   sorted-consecutive gap criterion IMPLIES full pairwise base-id
   disjointness (symbolic, UNSAT of negation); the concrete layout disjoint
   on the solver path; dictionary opcodes globally distinct; SAT sanity +
   mutant legs so nothing is vacuous.

7. **Atlas artifacts**: `render_fprime_atlas` (fail-closed: refuses on
   validation diagnostics OR ontology gaps) writes committed
   `docs/hermes/atlas/hermes-harness.fpp` +
   `hermes-harness-dictionary.json` — the operator's instance-qualified
   index of every opcode, event id, channel, and parameter.

8. **Docs**: `docs/hermes/fprime-alignment.md` — the full 43-construct
   mapping (FPP → OCaml → harness realization → fractal level), the pattern
   table (who serves time/health/telemetry/event/command/param here), the
   severity mapping that keeps the two-lattice law intact (FATAL stops the
   machine, never rewrites evidence), the honesty table of what is
   deliberately not modeled (packet sets, subtopology export, hierarchy,
   PrmDb persistence), SDLC/SRE coverage, and the TO-BE queue.

## Live proofs this session

- RED observed for both modules before implementation (every check
  `Failure("unimplemented")`), then GREEN.
- The ontology gap found by the new law (step 5) — not staged, discovered.
- Z3 UNSAT on the algorithm law with SAT sanity legs alongside.

## Suite numbers

fpp_model **64/0** · harness_topology **16/0** · fprime_smt **8/0** ·
fractal_ontology **702/0** (25 components, 34 edges).

## Standing constraints honored

OCaml end to end (no Python anywhere in the import or the tooling); the
frozen reference untouched; C3I environment file untouched; no bulk-staging
of legacy files; TDD Iron Law: stub-RED before every implementation.

---

## Follow-on: the FPP testing pass (same day)

### The prompt (verbatim)

> run tdd, bdd, fuzz, chaos and property testing for fpp. create common use
> cases fir testing. map all harness usecases and worflows to fpp and test

### What was done

1. **`fpp_interp.ml`** (TDD, stub-RED 0/25 observed): a pure simulator for
   the executable FPP semantics — state-machine dispatch per the spec
   (exit → do → entry order pinned by the action log; guard-gated
   transitions; unhandled signals dropped; unknown signals/tampered states
   are errors; fuel-bounded choice resolution so garbage cannot loop) and
   command dispatch through instance base-id windows with the three
   queue-full policies. **25/0**, including the real ConvergeLoop OODA
   walk, the R13 refusal→Blocked→retry path, and Anomalous absorbing.

2. **`fpp_usecases.ml` + `test_fpp_bdd.ml`** (RED observed with the empty
   catalog via the runner's coverage floor): scenarios as data, a printing
   Given/When/Then runner. **8 generic use cases** (sensor+telemetry, async
   wiring, drop/assert/block queue policies, state-machine lifecycle,
   two-instances-two-dictionaries, invalid-wiring-rejected) and **15
   harness workflows mapped to FPP** and executed against the REAL
   topology: pipeline dispatch (assert on full queue), the OODA converge
   walk, R13 refusal, anomaly stop-the-line (FATAL + absorbing), divergence
   -as-measurement (ACTIVITY_HI, never FATAL), capture/report read-only
   laws asserted as OPCODE ABSENCE, health/time/telemetry pattern flows,
   the two-lattice boundary, the armed frontier sensor, reconcile drift
   events, parameter set/save pseudo-commands, guarded preflight.
   **23 scenarios, 85 steps, 0 failures.**

3. **`test_fpp_fuzz.ml`**: totality fuzz (300 garbage models — diagnose or
   refuse, never crash), mutation fuzz (8 operators × 200 rounds, every
   injection caught by its own check), signal-soup fuzz over ConvergeLoop
   (200 runs × 30 signals: closed states, growing log, absorbing Anomalous
   — with a non-vacuity counter proving the property was visited), opcode
   fuzz (400 random dispatches), chaos (500-instance model, 120-deep alias
   chain + 60-cycle, 80-state ring × 500 dispatches, 40-deep choice ladder,
   100-target pattern fan-out), properties (emitter/validator determinism,
   the dictionary base-window law, expansion monotonicity, id_span
   monotonicity). **16/0.**

4. **The mutant proof did its job on the first swing**: an injected
   off-by-one in the queue bound (`<` → `<=`) was NOT caught — the original
   opcode fuzz used fresh empty queues each round, so the overfill
   invariant was nearly vacuous. Fixed by adding the persistent-queue load
   leg (one evolving queue driven hard). Re-injected the mutant: **2
   failures caught**; reverted: green. The checker now provably checks.

5. R12: `fpp_interp` + `fpp_usecases` registered with edges
   (fpp_interp ← fpp_model; fpp_usecases ← harness_topology, observes
   fpp_interp). Ontology **757/0** (27 components, 37 edges).

### Suite numbers

fpp_interp **25/0** · fpp_bdd **23 scenarios / 85 steps / 0** ·
fpp_fuzz **16/0** (seeded, printed) · ontology **757/0** · full battery
below.
