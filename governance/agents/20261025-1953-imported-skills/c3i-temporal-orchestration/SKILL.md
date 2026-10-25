---
name: c3i-temporal-orchestration
description: Explains how to use the Sa_plan subsystem (Oban + Temporal) for robust agent task dispatch.
---

# C3I Temporal Orchestration Skill

When a multi-step execution requires high resilience or strict dependencies,
use the native OCaml `Sa_plan` dispatch system instead of disjoint shell jobs.
The durable guarantee is at-least-once execution plus idempotent activities;
exactly-once external effects are not claimed.

## 1. What is Sa_plan?

`Sa_plan` is the OCaml C3I daemon embedded inside `zigvm_harness.exe`. It contains three primary engines:
- **`Sa_plan.Management`**: Topo-sorts task DAGs (Directed Acyclic Graphs).
- **`Sa_plan.Store`**: durable SQLite plan/task/lease/activity store with
  restart recovery and compare-and-set claims.
- **`Sa_plan.Store` job surface**: SQLite-backed Oban-compatible queues,
  compare-and-set leases, bounded exponential/capped retry, attempt bounds and
  durable terminal outcomes. `Sa_plan.Oban` remains a legacy pure precursor.
- **`Sa_plan.Store` workflow surface**: SQLite-backed ordered histories and
  stable-key activity idempotency. `Sa_plan.Temporal` remains a legacy pure
  precursor; cancellation/signals/timers absent from the Store are reported
  `Unavailable_observed`, never inferred.
- **`Sa_plan.C3i_reference`**: normalizes actual Store traces against the
  existing C3I Rust source/captured observations and emits only `Verified`,
  `Rejected_by_policy`, or `Unavailable_observed` rows.

C3I/Rust planning, Oban and Temporal feature parity is tracked explicitly by
Tasks 12–17 in `docs/superpowers/plans/2026-08-04-0936-infranodus-fractal-closure.md`.
All plans, jobs, workflows, claims and completions MUST be created or updated
through the typed OCaml Sa-plan Store and runners. Markdown, UI and agent
messages cannot mutate task truth.

The canonical CLI surface uses noun/verb commands:

```text
plan register | status | list | tree
task claim | complete | select
job|oban enqueue | claim | complete | list
workflow|temporal start | activity | complete | fail | history
ui tui | jobs | workflows | bonsai | snapshot PATH | parity PATH
```

Use `ZIGVM_SA_PLAN_DB` to select the durable SQLite state file. The CLI is an
OCaml projection over the Store, not a second planning authority.

`--tui` renders one ANSI terminal snapshot. `--bonsai` renders the read-only
Bonsai model contract for `/bonsai`; both are observers and cannot mutate
plans, jobs, workflows or gate state.

## 2. How to dispatch an Epic

Database access must go through the harness or authored OCaml code. Construct
an OCaml runner or use a typed harness/MCP operation; direct database clients
and ad hoc shell SQL are forbidden.

**Runner hygiene (a rotted runner has already broken the build once):** a runner file is
EPHEMERAL epic scaffolding, but `dune` compiles it forever. The canonical gate builds only
`harness/zigvm_harness.exe`, so a runner referencing a dropped `Sa_plan` symbol breaks the
FULL `dune build` silently for weeks (observed: `e11_t4_runner.ml` → `Unbound value
Sa_plan.Management.mark_completed`). Rules: (a) after authoring, prove it with
`opam exec -- dune build harness/<runner>.exe`; (b) call ONLY the current
`Sa_plan.Management` surface — `empty` / `add_node` / `execution_plan` /
`dispatch_plan_to_queue` (check `harness/sa_plan/sa_plan_management.ml`, do not trust this
list over the source); (c) DELETE the runner when the epic closes.

1. Create a `harness/my_epic_runner.ml` file.
2. Initialize the DAG:
```ocaml
let plan = Sa_plan.Management.empty in
let plan = Sa_plan.Management.add_node plan {
  id = "Task1"; parent_id = None; task_type = Sa_plan.Management.Story;
  title = "Do step 1"; estimate_points = Some 1; dependencies = []
} in
let plan = Sa_plan.Management.add_node plan {
  id = "Task2"; parent_id = None; task_type = Sa_plan.Management.Story;
  title = "Do step 2"; estimate_points = Some 1; dependencies = ["Task1"]
} in
```
3. Dispatch to Queue:
```ocaml
match Sa_plan.Management.dispatch_plan_to_queue plan ~queue_name:"my_epic" with
| Ok jobs -> (* jobs are queued *)
| Error e -> (* handle cycle error *)
```

## 3. How to Execute Safely (Temporal)

When a worker pulls from the durable Store queue, it must use a stable workflow
and activity idempotency key. The legacy in-memory example below is algebraic
background only; it is not task authority and does not establish durability.

```ocaml
match Sa_plan.Oban.fetch_and_lock_next_job jobs ~queue:"my_epic" with
| Some active_job ->
    let w_state = Sa_plan.Temporal.start_workflow ~id:("wf_" ^ active_job.args) in
    
    let w_state, res1 = Sa_plan.Temporal.execute_activity w_state ~activity_id:"heavy_compilation" ~f:(fun () ->
      (* Pure precursor only; durable effects use Store.complete_workflow_activity. *)
      "COMPILATION_DONE"
    ) in
```

## 4. Automation hook
You do NOT need to manually trigger the markdown generation. When an agent runs `record_cycle`, the Zero-Trust Gate evaluates the database. On success, `harness/supervisor_memory.ml` automatically invokes `Sa_plan.publish`, broadcasting the CRDT state to:
- `docs/journal/journal.md`
- `docs/journal/journal.html`
- `docs/journal/slide_deck.md`

Always check the `docs/journal/slide_deck.md` after completion for the C3I debriefing.
