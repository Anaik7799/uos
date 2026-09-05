---
id: hermes-imported-bonsai-guide
status: published
type: reference
generated: false
migrated_from: zigvm/docs/bonsai/BONSAI_GUIDE.md
---
# Bonsai — features, patterns, and how to work in it

The practical companion to `BONSAI_ONTOLOGY.md` (vocabulary) and
`BONSAI_ALGEBRA.md` (laws). Everything here is either a fact read from the
installed interfaces at pin `v0.18~preview.130.106+341`, or this repository's
own analysis and examples.

---

## 1 · The feature surface

A complete-as-installed inventory, grouped by the taxonomy in the ontology.

### 1.1 Pure and incremental

`return`, `return_lazy`, `map`, `map2`…`map7`, `both`, `cutoff`,
`transpose_opt`, `arr1`…`arr7`. Surface syntax: `let%arr` (preferred),
`let%map`, `let%sub`, `match%sub`, `if%sub`.

### 1.2 State

`state`, `state'` (setter takes a function), `state_opt`, `toggle`, `toggle'`,
`state_machine`, `state_machine_with_input`, `actor`, `actor_with_input`, the
`Actor` functor for GADT actions with per-constructor response types, and
`wrap` for a model that sees the component's own result.

### 1.3 Collections

`assoc`, `assoc_set`, `assoc_list`, `all_map`, the `*_n` autopack variants that
return up to seven separate values instead of one packed tuple, and
`Expert.assoc_on`. Plus the incremental map and set algebra: `Bonsai.Map` with
roughly forty operations (`mapi`, `filter_mapi`, `partition_mapi`,
`unordered_fold`, `merge`, `unzip`, `rank`, `subrange`, `subrange_by_rank`,
`rekey`, `index_by`, `collapse`, `expand`, `counti`, `sum`, min and max
families) and `Bonsai.Set` (`union`, `inter`, `diff`, `filter`,
`unordered_fold`, `cartesian_product`).

### 1.4 Control flow

`enum` (exhaustive by construction), `switch`, `delay`, `fix`, `fix2`.

### 1.5 Edge and time

`lifecycle`, `lifecycle'`, `on_change`, `on_change'`, `before_display`,
`after_display`, `wait_before_display`, `wait_after_display`,
`with_inverted_lifecycle_ordering`; `Edge.Poll.effect_on_change` and
`manual_refresh`; `Clock.approx_now`, `at`, `every`, `get_current_time`,
`sleep`, `until`, and `Clock.Expert.now`.

### 1.6 Sharing and scope

`Memo` (create, lookup, responses), `scope_model`, `with_model_resetter` and
its primed and autopack variants, `path`, `path_id`, `Dynamic_scope` (create,
derived, set, set', lookup, modify, `Bulk_setter`), `freeze`,
`previous_value`, `most_recent_some`, `most_recent_value_satisfying`, `peek`.

### 1.7 Effects

Monad and parallel-monad interfaces, `of_sync_fun`, `of_thunk`,
`of_deferred_fun`, primed variants taking `on_exn`, `lazy_`, `never`,
`both_parallel`, `all_parallel`, `protect`, the error family (`try_with`,
`try_with_or_error`, `lower_or_error`, `iter_errors`), `Result` and `Or_error`
submodules, `Effect_throttling.poll`, and the `Define`/`Define1` functors for
registering entirely new effect kinds.

### 1.8 Web

`Start.start` and `start_and_get_handle` with `Result_spec`; `Handle` (stop,
started, schedule, extra bus); `Vdom` node and attribute constructors;
browser effects (focus, reload, document title, JS promise interop);
`Rpc_effect` (dispatcher, poll, `poll_until_ok`,
`poll_until_condition_met`, `manual_poll`, `shared_poller`, polling-state RPCs,
connection `Status`, mock connectors); `Persistent_var` over local or session
storage; `Test_selector`; `To_incr_dom` interop.

### 1.9 Introspection

`Skeleton` (serialisable graph mirror, node counts), `Graph_info` (lexical tree
and sharing dag), `To_dot`, `Node_path`, `Instrumentation`, `Linter` (static
missed-optimisation report), and `Debug.watch_computation` — which is a no-op
unless externally enabled, so it can stay in production code at zero cost.

---

## 2 · How to use it — the shape of an app

```ocaml
(* 1 · DOMAIN — no Bonsai in sight. Pure, total, unit-testable. *)
module Model = struct
  type filter = All | Active | Done
  type t = { items : Item.t Int.Map.t; filter : filter; draft : string }

  let empty = { items = Int.Map.empty; filter = All; draft = "" }
end

module Action = struct
  type t =
    | Set_draft of string
    | Add
    | Toggle of int
    | Set_filter of Model.filter
end

let step (m : Model.t) : Action.t -> Model.t = function
  | Set_draft draft -> { m with draft }
  | Add when String.is_empty m.draft -> m
  | Add -> { m with items = Item.add m.items m.draft; draft = "" }
  | Toggle id -> { m with items = Item.toggle m.items id }
  | Set_filter filter -> { m with filter }

(* 2 · WIRING — the state machine is a thin adapter over `step`. *)
let app graph =
  let model, inject =
    Bonsai.state_machine
      ~default_model:Model.empty
      ~apply_action:(fun _ctx model action -> step model action)
      graph
  in
  (* 3 · derive only what each part needs — NOT one map over everything *)
  let visible =
    let%arr model = model in
    Item.filter model.items ~filter:model.filter
  in
  let rows =
    Bonsai.assoc (module Int) visible
      ~f:(fun id item graph -> row ~id ~item ~inject graph)
      graph
  in
  (* 4 · VIEW — a function of state alone *)
  let%arr rows = rows and model = model and inject = inject in
  Vdom.Node.div [ header ~draft:model.draft ~inject; list (Map.data rows) ]
```

Four things to notice, because they are the whole method:

1. `step` has no Bonsai types, so it is testable with an ordinary property test.
2. The action type makes every transition explicit and exhaustively checked.
3. `assoc` gives each row its own subgraph, so toggling one row does not
   recompute the others.
4. The final `let%arr` names exactly what it reads.

---

## 3 · Use cases and which tool fits

| Use case | Reach for | Why |
|---|---|---|
| A form field | `state` or `state_machine` over a typed record | one model, invariants in one place |
| A dynamic list or table | `assoc` over a map | per-key subgraphs, diff-based updates |
| Master–detail | `assoc` plus `scope_model` on the selection | switching selection swaps the detail model |
| Tabs or wizard steps | `match%sub` or `enum` | exhaustive, inactive branches keep their models |
| Fetch on input change | `Edge.Poll.effect_on_change` | out-of-order protection is built in |
| Periodic refresh | `Clock.every` with an explicit `when_to_start_next_effect` | the overlap policy is a decision, so make it |
| Shared expensive computation | `Memo` | computed once, refcounted, lazily activated |
| Cross-cutting context | `Dynamic_scope` | avoids threading a parameter through every signature |
| Server call | `Rpc_effect.dispatcher` or `poll` | connection status and retries are modelled |
| Persisted preference | `Persistent_var` | typed via `Sexpable`, survives reload |
| Undo or reset | `with_model_resetter` | resets a whole subgraph to defaults |
| Reading a value inside an effect chain | `peek` | returns `Computation_status`, forcing the inactive case |

---

## 4 · What to do

| Do | Because |
|---|---|
| Put the transition function in the domain, not in Bonsai | it becomes unit-testable and framework-independent |
| Make one model per concept | invariants across fields have somewhere to live |
| Use variants for every enumeration | the compiler checks exhaustiveness |
| Prefer `let%arr` over chained `let%map` | one node of the right arity instead of a chain |
| Give each view the state it reads | a change recomputes only its dependents |
| Use `assoc` for collections | unchanged keys cost nothing |
| Supply `~equal` on models where cheap | lets the framework store defaults instead of copies |
| Declare `Test_selector` hooks deliberately | typed test handles that vanish in production |
| Take the weakest state shape that works | `state` before `state_machine` before `actor` before `wrap` |
| Return `Or_error.t` from fallible effects | the caller cannot ignore it |

---

## 5 · What not to do

| Do not | Because | Detected by |
|---|---|---|
| Bind a dozen separate states in one component | no single model, no home for invariants | `BONSAI-STATE-EXPLOSION` |
| Bundle state into a positional list | position, not type, distinguishes entries; forces a catch-all arm | `BONSAI-POSITIONAL-BUNDLE` |
| Store numbers or enums as strings | re-parsed on every read, usually with a swallowed error | `BONSAI-STRINGLY-STATE` |
| Write one map over all state | every change recomputes the whole view | `BONSAI-MONOLITHIC-MAP` |
| Look for a monadic bind | it does not exist by design; use `match%sub`, `enum`, `assoc`, `Memo` | review |
| Perform effects inside `apply_action` | breaks purity and testability; schedule via the context | review |
| Rebuild a list of components on every change | no key identity, so nothing is preserved | review |
| Use `Clock.Expert.now` for display | recomputes every frame; use `approx_now ~tick_every` | review |
| Depend on a lifecycle order other than the specified one | the ordering is a contract | review |
| Reach for `Expert.*` or `Incr.compute` casually | escape hatches need a written justification | review |
| Split a graph finer than the work justifies | nodes are not free to create, fire or track — see the algebra §8.1 | review |
| Instantiate `graph`-taking things inside a large `assoc` body | a `graph`-free body compiles to a constant-node incremental map; touching `graph` forfeits that | review |
| Build a variable-length `Vdom.Node.t list` for conditional children | list diffing compares by index, so an insertion destroys and recreates every later node | review |
| Raise exceptions in UI code | exceptions are very slow in the compiled-to-JavaScript runtime; return `Or_error.t` | review |
| Update state from a value the handler closed over | it may be a frame stale; use the update-taking setter that receives the current model | review |
| Store a value you could derive | the stored copy goes stale; store the smallest key and re-derive | review |
| Push a server stream to a browser client | a backgrounded tab throttles frames, so the stream accumulates on both ends; poll and diff instead | review |
| Call a hook or widget functor per render | it mints a fresh identity each time, so you get destroy-and-reinit every frame | review |

---

## 6 · Pattern catalogue

### 6.1 Model–action–step

The default. A record or variant model, a variant action, a pure
`step : model -> action -> model`, and a three-line `apply_action` adapter.
Everything else in this catalogue is a variation on it.

### 6.2 Derived read models

Rather than one view over the whole model, derive small named values and let
each part of the view depend on the one it needs. The names document the
dependency structure and the graph enforces it.

### 6.3 Keyed collection

`assoc` over a map keyed by a domain identifier. Each item gets its own
subgraph *and its own state*, which is what makes per-row editing work without
a central registry of row states.

### 6.4 Request as a value

Model a server call's outcome as data, not as an exception path:

```ocaml
type 'a request = Idle | Loading | Loaded of 'a | Failed of Error.t
```

Every state is renderable, and the compiler forces you to render each one. This
repository's `ui_state.ml` already does exactly this with `request_state`.

### 6.5 Effect at the edge

Effects are constructed where the domain decides and scheduled where the
framework allows. An effect built in `step` and returned as data is fine; an
effect *performed* inside `step` is not.

### 6.6 Escape hatch with a receipt

`Incr.compute`, `Expert.assoc_on`, `peek`, `Clock.Expert.now` are legitimate
and occasionally necessary. The rule is a comment naming what was measured and
why the ordinary combinator was insufficient — otherwise the escape hatch
becomes the default by drift.

---

## 7 · Anti-pattern catalogue

Each entry names the smell, the cost, and the refactor.

| Smell | Cost | Refactor |
|---|---|---|
| **State explosion** | no invariant has a home; every field independently settable into an illegal combination | one record model behind `state_machine` |
| **Positional bundle** | reordering is a silent behavioural change; adding an entry degrades the UI at runtime rather than failing to compile | a record, or a typed model |
| **God map** | any change recomputes everything; the incremental graph is bypassed | split by what each part reads |
| **Stringly-typed state** | parse-and-swallow on every read; no exhaustiveness | the parsed type, parsed once at the edge |
| **Effect in the transition** | untestable; ordering becomes implicit | schedule through the context |
| **List rebuild** | no key identity, so no state or DOM is preserved | `assoc` over a map |
| **Silent inactive** | `Computation_status.Inactive` ignored | handle it, or restructure so it cannot occur |
| **Unbounded poll** | overlapping requests, last-write-wins races | `Edge.Poll` or `Effect_throttling.poll` |
| **Over-incrementalisation** | node overhead exceeds the work saved | split only where it separates expensive work from fast-changing input |
| **Derived value stored in state** | the copy goes stale while its source moves on | store the smallest key and re-derive |
| **Stale-closure update** | two concurrent updates each overwrite the other's field | use the setter that receives the current model |
| **Index-diffed child list** | inserting one element destroys and recreates every later DOM node | keep the list length constant, or use a keyed children construct |

### 7.1 A note on where these come from

The four rules with a lint identifier were derived from this repository's own
frontend. The rest are drawn from the framework's published guidance and are
recorded here as review obligations rather than mechanised checks. Where the
two disagree — and in one case they do, on whether `let%map` is harmful — the
**installed interface and its documentation at our pin** win over older
material, because that is what we compile against.

---

## 8 · Findings in this repository

The rules above are not hypothetical: they were derived from, and currently
fire on, this repository's own frontend. Present state, from the gate:

| Finding | Location | Rule |
|---|---|---|
| 25 separate states in one component | `harness/ui_web/main.ml` | `BONSAI-STATE-EXPLOSION` |
| positional bundle of 25 pairs | same, line 1693 | `BONSAI-POSITIONAL-BUNDLE` |
| five numeric-string states | same, lines 1668–1684 | `BONSAI-STRINGLY-STATE` |
| a 321-line map over all state | same, line 1725 | `BONSAI-MONOLITHIC-MAP` |

The sharpest detail: `ui_state.ml` already defines
`camera = { zoom : float; x : float; y : float }` and typed variants for
session, request, provider, visibility and window class — while `main.ml`
stores zoom as the string `"1.0"` and re-parses it. **The correct types already
exist and the UI layer routes around them.**

These are recorded at `Info` severity so the errors-and-warnings ratchet stays
at zero. That is a deliberate, disclosed choice: a new rule family over an
existing 5,000-line component lands advisory, with the backlog fully visible,
rather than either raising a ceiling that is at zero or blocking on an
unrelated refactor. **Promotion trigger:** when the frontend refactor slice
lands, these become warnings. The refactor is a single coherent slice —
introduce a `Legacy_ui_model.t` record, move the 25 fields into it, replace the
bundle with that record, and split the 321-line map along the panels it already
renders.

---

## 9 · How to extend and evolve

### 9.1 Writing a reusable component

A component is a function, so a reusable one is a function you export. The
conventions that make it composable:

- Take inputs as `'a t`, not as plain values, so callers can pass dynamic data.
- Take `graph` last, positionally, matching the framework.
- Return a record of named values rather than a tuple when there is more than
  one output; the framework's own `Toggle.t` is the model to imitate.
- Accept `?equal` and `?sexp_of_model` and pass them through, so callers keep
  the optimisation and debugging options.

### 9.2 Adding a new effect kind

The `Define` and `Define1` functors register a handler into the dispatch table,
which is how the framework itself adds browser effects. Use this when
integrating a new external capability; the result is an ordinary `Effect.t`
that composes with everything else.

### 9.3 Migrating older code

Three API generations exist. The current one is the graph-taking style; the
older `Proc` style is now a *type-level alias* onto it (`'a Value.t` is `'a t`,
`'a Computation.t` is `graph -> 'a t`), so the two interoperate directly and
migration is mechanical rather than a rewrite. The oldest arrow-style API is
explicitly for existing code only.

Renames worth knowing when reading older material: the zero-input state machine
is now `state_machine`, the one-input version is `state_machine_with_input`,
and the "read a value out of the graph" operation is `peek`. `assoc_on` and
`now` moved under `Expert`; `if_` and `of_module` are gone in favour of
`match%sub` and explicit state machines.

**A warning about external material.** The long-form public guide at
`bonsai.red` teaches the *previous* API generation — two separate types for
values and computations, and a binding form to instantiate a computation. That
material is still worth reading for the design rationale (particularly why the
interface is applicative and why the framework is best understood as a compiler
targeting an incremental engine), but **do not copy its code shapes**: at our
pin the two types have collapsed into one, and a computation is an ordinary
function taking the graph. Its advice that one binding form is "always harmful"
has also been superseded — at our pin the two forms differ only when the
pattern ignores fields, where one inserts cutoffs and the other does not.
Component library module names have likewise been reorganised. When older
material and the installed interface disagree, the interface wins.

### 9.4 Evolving safely

| Change | Watch for |
|---|---|
| Adding a model field | does the default remain legal, and does `reset` still reach a legal state |
| Adding an action | is `apply_action` still total |
| Splitting a component | do the models move with it, or silently reset |
| Adding a dependency to a view | did you just widen what recomputes |
| Introducing `assoc` | is the key a stable domain identifier, not an array index |

---

## 10 · Testing

The installed switch provides the driver-level surface rather than the
expect-test wrapper: `Bonsai_driver` (headless, no DOM) with the frame protocol
`flush` → `result` → `trigger_lifecycles`; `Bonsai_web.Driver` (with a DOM);
`Expert.Var` to drive inputs from outside the graph; `Time_source` advancement,
which enqueues alarms rather than firing them; `Test_selector` for typed
handles; and the effect testing helpers for resolving pending effects
deterministically.

### 10.1 The executable feature suite, and what it found

`harness/bonsai_features.exe` validates the behaviour these documents claim,
against the real library at our pin, headlessly through the driver. It is the
evidence for the prose: if the pin moves and a behaviour changes, it goes red
instead of the documentation silently rotting.

**Each section runs in its own process.** That is not fastidiousness — it is
the fix for a diagnosed defect. Incremental state is per-process and shared by
every driver in it, so drivers accumulated until an arbitrary later section
raised inside stabilisation, after which everything downstream failed too. Four
probes proved the raise followed *position*, not the combinator under test.

Current run after that fix: **10 sections, 0 failures.** Every previously
"failing" combinator — `scope_model`, `with_model_resetter`, effects — was
correct all along.

**The correction that matters most, because it was mine.** Under the poisoned
shared state I observed `on_change` "firing every frame with the initial
value", and retracted a documented claim on that basis. With process isolation
the claim is **restored**: `on_change` fires on activation and carries the
latest value, exactly as documented. The retraction was over-broad, and the
artifact that caused it was in the harness, not the framework.

One narrow finding does survive, and is now asserted as *observed*:

| Finding | Status |
|---|---|
| **`on_change` fires again on a re-set to an EQUAL value** | **OPEN, and narrow.** Re-setting the observed variable to a value it already holds fires the callback again, even with an `equal` supplied. Everything else about `on_change` matches its documentation under process isolation, which is why only this clause is singled out. Asserted as *observed* rather than as documented, so a change in either direction is noticed rather than silently absorbed. |
| `scope_model` raised inside stabilisation | **CLOSED — `scope_model` was never at fault.** Four probes cleared it: it works with an off-graph variable, a constant, and in-graph state; it survives a dozen preceding drivers and a lifecycle driver; and it correctly retains per-scope models across a switch and back (1 → switch → 0 → switch back → 1). `with_model_resetter` is equally correct in isolation. The decisive test was **moving the section to run first**: it then passed, and the identical error appeared in the section that had moved into its old position. **The raise follows POSITION, not combinator** — it is the accumulation of drivers in one process, and the section that happens to run after enough of them is the one that fails. |
| the section after a raising one also failed | **CLOSED, same root cause.** Incremental state is shared across drivers in one process, so one raised stabilisation poisons every later one. Both findings reduce to one defect: **the suite needs a process boundary per section**, not a fresh driver. Until then, a failure's *location* in this suite carries no information about which combinator is at fault — which is worth knowing before anyone debugs from it. |

Two behaviours the suite *did* pin down, both of which would have been wrong if
guessed from the type signatures alone:

- **`on_change` defaults to the before-display phase**, which the headless
  frame protocol does not pump — so an edge test written against the default
  observes nothing at all. The after-display trigger is what a driver-based
  test can see.
- **Three actions injected in one frame all apply, in order.** This is the
  concrete reason state machines exist rather than plain setters, and it is now
  asserted rather than asserted-about.

The suite also prints, on every run, what it does **not** cover — the vdom, the
app entry point, RPC, browser effects, storage, hooks and widgets. Those need a
browser, and claiming them here would be the fabricated-evidence failure this
repository exists to prevent.

The highest-value tests, in order:

1. **Property tests on `step`.** Pure, total, no framework — seeded action
   sequences against model invariants. Cheapest and catches the most.
2. **Driver tests on the component.** Assert the rendered result after a
   sequence of injected actions and clock advances.
3. **Runtime verification through typed OCaml Playwright**, per
   `skills/ocaml-playwright-control`. This is the only thing that proves the
   real browser agrees, and it is where `Test_selector` pays off.
