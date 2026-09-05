# 02 — Declare intent and run the convergence loop

Goal: add or change a **blueprint directive** (desired state), then run the
closed loop and read its output correctly.

## Part A — declare a directive

### Substitution table

| Placeholder | Meaning | Example |
|---|---|---|
| `⟨DIR_ID⟩` | short unique directive id | `routing_family` |
| `⟨TARGET⟩` | a fractal node: `hermes`, `hermes.⟨family⟩`, or `hermes.⟨family⟩.⟨capability⟩` | `hermes.model_routing` |
| `⟨WHY⟩` | the human rationale, ≥ 20 chars, specific | "all seven routing slices differentially verified" |
| `⟨REQS⟩` | ids of directives this one depends on | `["transports"; "retry"]` |

### Steps

1. ACTION: Open `hermes_harness/parity_intent.ml`. The blueprint starts at the
   `let blueprint : Blueprint.t =` anchor. Add a directive record in the
   existing style — **the OCaml comment above it carries the intent prose; the
   `intent` field mirrors it**:

   ```ocaml
   (* ⟨WHY — the full rationale, written for a reviewer⟩ *)
   { id = "⟨DIR_ID⟩"; target = "⟨TARGET⟩";
     desired = Parity_algebra.Verified;
     intent = "⟨WHY⟩";
     requires = ⟨REQS⟩ };
   ```

2. RULES the validator will enforce (fix before running, don't discover them):
   - `⟨TARGET⟩` must resolve to a REAL node (the resolver is built from
     `Capability_catalog` — a typo is rejected as `Unknown_target`);
   - `⟨DIR_ID⟩` unique; every id in `⟨REQS⟩` must exist; no dependency cycle;
   - `intent` must be substantive (≥ 20 chars) — vacuous intent is rejected.

3. VERIFY: `dune exec hermes_harness/test_blueprint.exe` → `failed: 0`, and
   `dune exec hermes_harness/auto_converge.exe` does NOT print
   `blueprint invalid:`.
   IF-FAIL: the printed `describe_error` names the exact problem — fix that
   directive; never loosen `Blueprint.validate`.

### What a directive can and cannot do

- It CAN declare desired state at any catalog level (L0/L1/L2) and order work
  via `requires`.
- It CANNOT make anything Verified. If the target lacks L4–L6 evidence, the
  loop reports it as residual drift — that is correct behavior (R10), not a
  bug to fix in the blueprint.

## Part B — run the loop and read it

1. ACTION: `dune exec hermes_harness/auto_converge.exe`

2. READ the output in this order:

   | Line | Meaning | Healthy looks like |
   |---|---|---|
   | `trajectory: {} -> {…}` | satisfied-intent sets per iteration | grows once, then repeats (fixed candidate ⇒ one growth step) |
   | `converged` | EVERY intent satisfied | only when the whole blueprint is proven |
   | `settled after N iteration(s): K satisfied, drift remains on [...]` | partial fixpoint | the drift list is EXACTLY the remaining real work |
   | `anomaly: lost [...]` | a step UN-satisfied an intent | **never healthy — STOP, jidoka, report verbatim** |
   | `residual work (...)` runbook | per-drift action from the rule engine | one actionable row per unsatisfied intent |

3. ACT on the runbook: each row names the action (e.g.
   `capture-and-compare hermes.⟨family⟩.⟨capability⟩`) — that action is a
   playbook: capture/compare → playbook 01; contract → playbook 04.
   The loop names work; humans/agents do the work; re-running the loop then
   observes it (never the other way round).

4. AFTER new evidence lands, re-run `auto_converge` and confirm the newly
   covered intent moved from the drift list into the satisfied set.

## Interpreting verdicts on a target (decision table)

| actual verdict | meaning | your next action |
|---|---|---|
| `Verified` | differential evidence exists and matched | nothing — keep it green |
| `Unmapped` | no evidence yet at this node (or an empty required roll-up) | playbook 01 for the missing slice(s) |
| `Blocked` | environment/control prevented measurement | fix the environment (interpreter, disk, tool); NEVER record as candidate defect (R5) |
| `Divergent` | a real measured difference | playbook 03 |
