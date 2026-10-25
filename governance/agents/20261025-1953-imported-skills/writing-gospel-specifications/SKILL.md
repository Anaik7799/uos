---
name: writing-gospel-specifications
description: Use when writing or generating Gospel specifications in OCaml .mli files, adding (*@ ... *) contract annotations, seeing "Syntax error" or "Symbol not found in scope" or "No module with name" or "Invariant on public type" from gospel check, or installing the gospel toolchain on a modern OCaml switch
---

# Writing Gospel Specifications

Gospel annotates OCaml `.mli` files with `(*@ ... *)` contracts. The syntax
resembles OCaml but is a **separate language** with its own keyword table,
per-block-kind clause grammar, scoping, and type system. `gospel check`
collapses nearly every violation to a bare `Syntax error` at a column — the
symptom, never the cause.

**Core rule: never hand back a Gospel spec you have not run through
`gospel-lint`.** These failures look like valid OCaml on inspection.

## Mandatory: this toolchain is OCaml, end to end

**No Python.** Not in the linter, not in the tests, and not as a throwaway
shell utility for editing files or parsing tool output. If a task here needs a
tool, write it in OCaml and put it in `gospel_lint/`.

This is not stylistic. A Python helper invoked from a shell heredoc is
unreviewed, untested and invisible to the build — no types, no test, and it
rots silently when a format changes. `coverage_points.ml` exists for exactly
this reason: parsing bisect's coverage file began as an inline Python snippet,
and as OCaml it now validates every length it reads and fails loudly instead of
mis-reporting coverage.

Use `Read`/`Edit` to change files rather than scripting the edit. Reaching for
`python3 - <<EOF` is the signal to stop and write the OCaml.

## Fractal RCA — diagnose at the level the defect enters

| Level | Failure | Root cause |
|---|---|---|
| **L1 lexical** | reserved word used as an identifier | a name drawn from OCaml vocabulary without consulting Gospel's keyword table |
| **L2 syntactic** | clause illegal *for this block kind*; labelled application in a term | clause grammar is per-kind, and the kinds look alike |
| **L3 scope** | name used where it is not bound (self-reference) | Gospel's scoping is not OCaml's |
| **L4 type** | `integer` over `int`; `consumes` on a unit return; invariant on a public type | term resolves but cannot type |
| **L5 environment** | unresolvable module; checker absent | gospel sees one file — **never a specification defect** |

Treating an L5 as a spec defect is the costly mistake: it records a false
negative. Report it as *not checkable*, not *rejected*.

## The Six Traps

1. **Reserved words** (35, from `lib/gospel/ulexer.ml`). Cannot be identifiers
   *anywhere*, including as an OCaml label name — `~model:string` is natural
   OCaml and unspecifiable in Gospel. Rename the label; there is no escape
   syntax.

   ```
   as axiom checks coercion consumes diverges else ensures ephemeral exists
   false forall fun function if in invariant let match model modifies mutable
   not old predicate pure raises rec requires then true variant when with
   ```

2. **A function is not in scope inside its own spec.** `ensures f r = r` always
   fails with `Symbol f not found in scope`. Mark it `pure` and state the
   property as a **top-level axiom** after the `val`.

3. **Clauses are per block kind.** `variant` is a *function*-spec clause and is
   illegal in a val spec; `model`/`invariant`/`ephemeral` belong to types.

   | Block | Clauses |
   |---|---|
   | `val` | requires, checks, ensures, raises, modifies, consumes, diverges, pure, equivalent |
   | `type` | ephemeral, model, invariant |
   | `function` / `predicate` | requires, ensures, variant, coercion |

4. **Labelled functions cannot be applied in a term** — not in `ensures`, not in
   an axiom. Bind bare in the header (`~keep`, never `~keep:k`). If a property
   needs a labelled call, the contract cannot carry it: state it as a property
   test and say so, rather than silently dropping the obligation.

5. **`int` is not `integer`.** `integer` is Gospel's unbounded type and will not
   unify with machine `int`.

6. **External modules do not resolve.** `gospel check` sees one file, and it
   ignores `include module type of`, so pointing a load path at the *real*
   interface does not rescue a submodule such as `Yojson.Safe`. Tooling gap,
   not a defect — fix it with a stub, below.

Also: an `invariant` needs an **abstract** type (a public record gives
`Invariant on public type`), and `consumes` needs a **non-unit** return.

## Toolchain: gospel on a modern switch

Upstream gospel 0.3.1 caps at `ocaml <= 5.3.0`. The cap is real but narrow:
OCaml 5.5.0 added `CamlinternalFormatBasics.neutral_concat`, whose field type
uses an explicit polymorphic quantifier **and** a polymorphic variant. Gospel
parses the stdlib on every run, so that one declaration makes *every* file
uncheckable — the binary itself compiles on 5.5.0 unchanged.

**Do not try to upstream this patch.** Upstream master already works on OCaml
5.5.0 unpatched: its type-checker was rewritten (it now depends on `inferno`)
and `Ptyp_poly` no longer appears in its sources. The bug exists only in the
*released* 0.3.1, which is the newest release. Master is also not a drop-in
replacement — it has breaking spec-syntax changes, where `raises E -> ...`,
`predicate f (b: t) = ...` and even `forall x: int` are all rejected. So the
patched 0.3.1 is the right choice until upstream cuts a new release.

`gospel-0.3.1-ocaml-5.5.0.patch` fixes it in three parts:

1. `Ptyp_poly` binds its quantified variables and descends into the body
   (Gospel's type system is prenex, so the quantifier adds nothing).
2. While loading an **imported** interface, a declaration Gospel cannot model
   is skipped instead of aborting the run. The name never enters Gospel's
   namespace, so a spec that references it still fails precisely.
3. The `ocaml` upper bound is relaxed.

Recovery is scoped to imported files by an `importing` counter, so **nothing is
ever skipped in the file the user asked to check**. Verified differentially:
the patched 5.5.0 build and the stock 5.3.0 build give identical verdicts on all
33 constructs and all 8 defect fixtures.

```sh
opam source gospel.0.3.1 --dir=/path/to/gospel
cd /path/to/gospel && patch -p0 < gospel-0.3.1-ocaml-5.5.0.patch
opam pin add gospel /path/to/gospel -y
```

With gospel in the project switch there is no PATH hazard. If you instead keep
it in a **side switch**, never put that switch's `bin` on `PATH`: it carries an
`ocamlc` that shadows the project compiler and breaks dune with `is not a
compiled interface for this version of OCaml`. Point `HERMES_GOSPEL` or
`GOSPEL_BIN` at the binary instead.

`gospel check` writes a `.gospel` sidecar **beside its input**, so always check a
temp copy. `gospel-lint` does this for you.

## Unresolvable modules: checking-only stubs

When a contract's type mentions a module gospel cannot resolve, supply a stub
on `GOSPEL_LOAD_PATH` (colon-separated) rather than abandoning the contract:

```ocaml
(* yojson.mli -- checking only *)
module Safe : sig
  type t
end
```

```sh
GOSPEL_LOAD_PATH=path/to/stubs ./gospel-lint contract.mli
```

**A stub must stay weaker than the interface it stands in for.** An abstract
type gives gospel strictly fewer facts than the real variant, so a spec that
type-checks against the stub also type-checks against the real module: the stub
can cause a false *rejection*, never a false *acceptance*. Adding constructors
or equations reverses that direction and lets a contract pass on facts the real
type does not provide — which is how a stub turns into a lie.

With no load path configured, an unresolvable module is reported statically as
not-checkable. With one configured, gospel decides, and a module it still
cannot find is reported as not-checkable rather than rejected.

## Workflow

```sh
./gospel-lint path/to/file.mli    # named diagnostics, then gospel for the verdict
```

| Exit | Meaning |
|---|---|
| 0 | OK — gospel agreed |
| 1 | errors found |
| 2 | not checkable here (external module) |
| 3 | gospel unavailable — **nothing was verified** |
| 4 | internal linter error — verdict unreliable |

The linter never reports OK without gospel agreeing. Static rules name causes;
gospel decides truth.

## Files

- `templates.mli` — one worked example per construct across the whole surface.
  Passes `gospel check` as one unit. **Copy from here rather than composing from
  memory.**
- `gospel_lint/` — the linter, pure OCaml, zero dependencies beyond `unix`
  (no regex engine, no ppx), so it builds in any switch.
- `gospel-lint` — CLI wrapper; builds on first use.
- `gospel-0.3.1-ocaml-5.5.0.patch` — the toolchain patch above.

```sh
cd gospel_lint && dune build && dune exec ./test_gospel_lint.exe

# measured coverage (instrumentation is opt-in; plain builds carry no ppx)
find . -name '*.coverage' -delete
dune exec --instrument-with bisect_ppx ./test_gospel_lint.exe
bisect-ppx-report summary --coverage-path .

# which sub-line points are missing (summary gives only a percentage, and the
# html marks a line visited when any point on it was hit)
dune exec ./coverage_points.exe -- $(ls *.coverage) gospel_lint.ml
```

139 checks across eight layers: TDD (per rule), BDD (user-visible scenarios),
SURFACE (all 33 constructs against the real checker), PROPERTY, CHAOS (600
deterministic mutations), ROBUSTNESS, EDGES, and STRUCTURE.

Measured coverage is **100% of lines, 620/629 points (98.6%)**. The residual
points are sub-line branches of defensive guards — a whitespace disjunct that
line-split input can never present, and arms of the checker-invocation error
handling. They are listed rather than excluded: contorting tests to light up a
counter optimises the metric, not the software.

STRUCTURE is kept alongside the coverage tool rather than replaced by it. It
asserts that every declared rule, level, block kind and verdict is exercised,
which line coverage cannot express: a rule can be fully covered and still have
no fixture proving it fires on its own defect.

`bisect_ppx` needs the same treatment as gospel — its last release (2.8.3,
2023) predates the OCaml 5.2 AST, so `Pexp_function` fails to compile against
ppxlib 0.36+. Upstream PR #455 (`pr448+ocaml5.5`, unmerged) fixes it and builds
clean on 5.5.0; it is pinned from `~/.local/src/bisect_ppx-5.5.0`. That branch
is validated the same way the gospel patch was: the suite's 139 checks pass
identically instrumented and uninstrumented, so instrumentation preserves
semantics.

The load-bearing test is differential: **linter-OK implies gospel-OK**. A linter
that passes a file gospel rejects is worse than no linter.

## Common Mistakes

| Mistake | Fix |
|---|---|
| `ensures f r = r` | `pure` + top-level `axiom` |
| `~model:string` label | rename to `~model_id` |
| `variant` in a val spec | it is a function-spec clause |
| `forall x: integer` over `int` | `forall x: int` |
| invariant on a public record | abstract type + `model` |
| `consumes` on a unit return | drop it, or return non-unit |
| checking the in-tree `.mli` | check a temp copy |
| side-switch gospel on `PATH` | use `HERMES_GOSPEL`; it shadows `ocamlc` |
| recording `No module with name` as rejected | it is not-checkable; add a stub |
| a stub with constructors or equations | keep stubs abstract, strictly weaker |
