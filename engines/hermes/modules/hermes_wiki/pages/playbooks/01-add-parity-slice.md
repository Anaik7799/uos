# 01 — Add a parity slice (the master recipe)

Goal: differential evidence for one frozen-reference capability — from nothing
to a VERIFIED (or honestly DIVERGENT) compare, fully integrated.

**Worked example used throughout:** the `gemini` slice
(`gemini_schema_adapter.py` → `capture_gemini_traces.ml` → `gemini_schema.ml`
→ `"gemini.schema"` scenarios). Open those files beside this playbook and
pattern-match them exactly.

## Substitution table — fill this in FIRST

| Placeholder | Meaning | Example |
|---|---|---|
| `⟨SLICE⟩` | short lowercase slice name | `gemini` |
| `⟨CAP⟩` | capability node suffix | `model_routing.gemini_adapter` |
| `⟨FROZEN_FN⟩` | the frozen function, module-qualified | `agent.gemini_adapter.sanitize_tool_parameters` |
| `⟨CANDIDATE⟩` | candidate module name | `gemini_schema` |
| `⟨ID⟩` | scenario id prefix | `gemini` (ids become `"gemini.schema"` …) |

## Steps

### 1. Probe the frozen source — NEVER guess

ACTION: Read the frozen function in `external/hermes_source/`. Record: exact
signature (watch for **keyword-only args** — `def f(x, *, role="user")` broke a
past slice), every branch, every default, every helper it calls, any
logging/IO side effects, any lazy-import/network behavior.

VERIFY: You can state, in writing, the function's output for two hand-picked
inputs *with line references to the frozen source for every claim*.
IF-FAIL: Keep reading. Do not proceed on a partial understanding.

### 2. Write the declared adapter

ACTION: Create `hermes_harness/reference_adapter/⟨SLICE⟩_adapter.py` by copying
`gemini_schema_adapter.py` and adapting. The adapter MUST:

- set `PYTHONPATH` handling so the frozen tree wins (copy the existing header — L-01);
- neutralize environment side effects BEFORE the frozen import — at minimum
  `logging.disable(logging.CRITICAL)` (L-10); if the frozen module lazy-installs,
  also `os.environ["HERMES_DISABLE_LAZY_INSTALLS"] = "1"` (see
  `bedrock_converse_adapter.py`);
- import ONLY `⟨FROZEN_FN⟩`, apply it positionally/keyword exactly as probed to
  each input read from the scenario payload, collect results **in input order**;
- print exactly one JSON object to stdout: `{"trace": {"results": [...]}}`;
- make **no decisions** — no normalization, no filtering, no error recovery.

VERIFY: `dune build` still exits 0 (the adapter is data, but confirm no dune
breakage), and the adapter file contains the string `logging.disable`.
IF-FAIL: STOP — jidoka. An adapter that can't stay dumb means the frozen
function has a side effect you haven't understood; go back to step 1.

### 3. Write the capture executable

ACTION: Create `hermes_harness/capture_⟨SLICE⟩_traces.ml` by copying
`capture_gemini_traces.ml`; change the adapter basename, scenario source, and
slice naming. Add its `(executable ...)` stanza to `hermes_harness/dune` by
copying the `capture_gemini_traces` stanza verbatim and renaming.

VERIFY: `dune build` exit 0.
IF-FAIL: fix the dune stanza (usual cause: a library missing from `(libraries ...)` — copy the gemini list).

### 4. Declare the scenarios (inputs only)

ACTION: In `hermes_harness/parity_compare.ml`, find the anchor
`let gemini_scenarios` and add, in the same style, a
`let ⟨ID⟩_scenarios` list. Each entry: `("⟨ID⟩.⟨case⟩", <input payload>)`.
Choose cases that exercise EVERY branch you recorded in step 1 (empty input,
each special key, each type coercion, the error path).

Also extend `node_of` and `attribution` where the other prefixes are matched:
add the `"⟨ID⟩."` prefix mapping to node `"hermes.⟨CAP⟩"`.

VERIFY: `dune build` exit 0.

### 5. Capture the real fixtures

ACTION: `dune exec hermes_harness/capture_⟨SLICE⟩_traces.exe`

VERIFY: one `captured` line per scenario, exit 0. Fixtures are now
digest-pinned in the evidence store.
IF-FAIL, adapter exited non-zero: read the stderr it printed. If it is an
import/network/logging problem → fix the adapter's neutralization (step 2),
NEVER the frozen source. If the interpreter is missing → Blocked, STOP and
report (that is an environment problem, R5 — not your bug to route around).

### 6. Candidate — TDD, faithfully from the frozen source

ACTION (strict order):
1. Write `hermes_harness/⟨CANDIDATE⟩.mli` — the minimal interface.
2. Write `hermes_harness/test_⟨CANDIDATE⟩.ml` with unit cases derived from the
   frozen source's branches (the two hand-picked inputs from step 1 first).
   Add both stanzas to `hermes_harness/dune` (copy the `gemini_schema` pair).
3. Stub `⟨CANDIDATE⟩.ml` so it compiles but fails the tests.
4. `dune exec hermes_harness/test_⟨CANDIDATE⟩.exe` — **confirm RED and that the
   failure is the expected assertion**, not a compile error.
5. Implement faithfully — translate the frozen branches, never "improve" them.
6. `dune exec hermes_harness/test_⟨CANDIDATE⟩.exe` — GREEN (`failed: 0`).

VERIFY: the RED run happened and is reflected in your notes; GREEN now.
IF-FAIL at GREEN: fix the candidate against the frozen source. Never adjust a
test to match the candidate.

### 7. Wire the differential compare

ACTION: In `parity_compare.ml`, next to `candidate_gemini` /
`compare_gemini_scenario`, add `candidate_⟨SLICE⟩` (project the candidate's
output to **the reference's schema** — never the intersection) and
`compare_⟨SLICE⟩_scenario`. In `test_parity_compare.ml`, mirror how the gemini
scenarios are exercised. In `compare_reference_traces.ml`, add the slice's
section where the other slices are listed.

VERIFY: `dune exec hermes_harness/test_parity_compare.exe` → `failed: 0`.

### 8. Run the differential — the moment of truth

ACTION: `dune exec hermes_harness/compare_reference_traces.exe`

VERIFY: your scenarios print `VERIFIED`, summary counts them, exit 0.
IF-FAIL with `DIVERGENT`: **this is a successful measurement, not a suite
failure.** Go to [playbook 03](03-resolve-divergence.md) and follow its
decision tree. Do not touch the normalizer. Do not delete the scenario.

### 9. Integrate (the checklist lower-end models most often miss)

Do ALL rows; each has its own VERIFY:

| # | File | Action | VERIFY |
|---|---|---|---|
| 1 | `capability_catalog.ml` | confirm node `hermes.⟨CAP⟩` exists (it usually does) | `dune exec hermes_harness/test_capability_catalog.exe` |
| 2 | `auto_converge.ml` | add the node + its scenario roll-up to `slice_nodes` (copy the gemini entry) | `dune exec hermes_harness/auto_converge.exe` — node appears in trajectory set |
| 3 | `parity_intent.ml` | only if a NEW directive/family is intended — playbook 02 | `dune exec hermes_harness/test_blueprint.exe` |
| 4 | `contract_catalog.ml` + Gospel | playbook 04 | `dune exec hermes_harness/test_contract_catalog.exe` |
| 5 | `specs/parity_frontier.qnt` | ONLY if the blueprint DAG changed — playbook 05 | `dune exec hermes_harness/test_quint_frontier.exe` |
| 6 | `parity_dashboard.ml` | update KPI expectations | playbook 06 |
| 7 | docs + HANDOVER | playbook 06 | — |

### 10. Full battery

ACTION: run, in order:
`dune exec hermes_harness/test_parity_compare.exe`,
`dune exec hermes_harness/test_reference_capture.exe`,
`dune exec hermes_harness/compare_reference_traces.exe`,
`dune exec hermes_harness/auto_converge.exe`.

VERIFY: all `failed: 0` / exit 0.
IF-FAIL: STOP — jidoka. Report the verbatim failing output.

## Red flags — STOP immediately if you notice yourself…

- writing an "expected" JSON by hand instead of capturing it;
- adding a field to the volatile/elision list to clear a mismatch;
- reordering/omitting reference fields in the candidate projection;
- "fixing" the adapter by adding logic to it;
- skipping the RED run because the implementation "is obvious".
