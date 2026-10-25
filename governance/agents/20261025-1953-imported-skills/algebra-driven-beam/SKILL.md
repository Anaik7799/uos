---
name: algebra-driven-beam
description: >-
  Design and implement Erlang/OTP and Elixir libraries, protocols, and domain
  models on the BEAM using Algebra-Driven Design (Sandy Maguire): behaviour
  signatures, equational laws, property-based tests, and initial/final
  encodings via tagged tuples, pure functions, and processes-as-
  interpretations. Use whenever the user mentions algebra-driven design, ADD,
  algebraic specification, denotational or equational design, leak-free
  abstractions, DSL or combinator libraries in Erlang/Elixir,
  monoids/semigroups/semilattices or laws on the BEAM, property-based testing
  (PropEr, StreamData, QuickCheck-style), initial vs final encodings,
  tagged-tuple ASTs with interpreters, behaviours as contracts, gen_server
  protocol design, or CRDT merge semantics — and when asked to "design a clean
  abstraction", "model a domain", or "architect a library" for Erlang, Elixir,
  OTP, or the BEAM, even without the word "algebra".
---

# Algebra-Driven Design on the BEAM

Treat software as an **algebraic specification**: a domain is a set of types
and operations (the *signature*), governed by equational *laws*, given meaning
by one or more *interpretations*. The design is correct when every law passes
as a property-based test over both an obviously-correct interpretation and the
efficient one.

The methodology is Sandy Maguire's *Algebra-Driven Design* (Haskell-centric);
this skill translates it to the BEAM: behaviours + a runtime contract instead
of typeclasses, tagged tuples instead of GADTs, pure immutable terms with GC
instead of manual memory, threaded `rand` state (or PropEr/StreamData) instead
of QuickCheck — and one thing the book cannot offer: **processes, gen_servers,
and distribution as additional interpretations of the same algebra**, verified
by the same law suite.

The BEAM is unusually friendly ground: data is immutable so laws can't be
broken by aliasing, term equality (`=:=`) is structural and canonical for
maps, and "let it crash" pairs naturally with exhaustive pattern-matching
interpreters.

## Reference files — read before designing

| File | Read when |
|---|---|
| `references/methodology.md` | Always, before Phase 1. Constructors/combinators/observations, choosing the semantic domain, deriving laws, quality gates, deriving implementations. |
| `references/beam-idioms.md` | Always, before writing code. Behaviour contracts, tagged-tuple encodings, generator patterns, PropEr/StreamData, processes-as-interpretations, OTP version notes. |
| `references/algebra-catalog.md` | During design/testing to name the structure and import its full law set. |
| `references/canvas_algebra.erl` (+ `canvas_initial.erl`, `canvas_final.erl`) | Gold-standard worked example, compile-verified on OTP 25. Mirror its module layout. |
| `assets/severity_algebra.erl` (+ `severity_initial.erl`, `severity_final.erl`) | Starting skeleton for a new domain (a bounded semilattice); adapt, don't rewrite. |

## Non-negotiable doctrine

1. **Laws are observational, never structural.** `overlay(empty(), X)` is the
   term `{overlay, empty, X}` — never `=:=` to `X`, yet lawfully equal to it.
   The signature must include an observation into a semantic domain
   (`rasterize/1`, `level/1`, `run/1`), and the callback `eql/2` compares
   denotations. Structural comparison is only ever an optimization over a
   canonical form, adopted after a property test proves it equivalent.
2. **Every algebra ships with ≥2 interpretations** — an initial encoding
   (tagged tuples + interpreter; the oracle) and an efficient final encoding —
   plus a **homomorphism test** (twin-seeded generators) proving they denote
   the same algebra. Process-based interpretations, when relevant, are a third
   module run through the *same* suite.
3. **Purity inside the algebra; effects only in interpretations.** Combinators
   are pure term → term functions: no messaging, no ets, no side effects.
   Processes/gen_servers *host* denotations at the edge; they never leak into
   combinator semantics.
4. **Exhaustive pattern matching.** Interpreter clauses cover every variant of
   the domain type with **no catch-all clause**; a new variant must crash
   unhandled interpreters loudly (let it crash) and be flagged by dialyzer.
5. **Contracts diagnose, not gatekeep.** Signature = `-callback` specs in a
   behaviour module **and** a `verify_signature(Mod)` that names every missing
   export in its error. Law suites call it first, so misuse fails with the
   offending module and arity spelled out.
6. **Specs on every exported function**; run dialyzer when available. Type
   sloppiness hides exactly the leaks ADD exists to prevent.
7. **Verify with a real toolchain before delivering.** Compile with `erlc`,
   run eunit (`scripts/run_beam_tests.sh` does both, two-pass so behaviour
   info resolves). Never deliver BEAM code you haven't compiled. Note the OTP
   release you verified on (`erlang:system_info(otp_release)`).

## Workflow

### Phase 0 — Scope the domain
List in plain language: the atomic things, what combines them, what users
ultimately extract. For existing code, recover the implicit algebra first
(which functions construct / combine / observe) — gen_server APIs usually
*are* an undocumented algebra whose laws were never written down.

### Phase 1 — Design the algebra on paper (no code)
Per `references/methodology.md`: (1) signature with each operation classified
constructor/combinator/observation; (2) **semantic domain chosen from the
observations first**, stated as a `[[.]] ≙` equation — on the BEAM prefer a
denotation that is a plain term (a map, an ordered atom) so `=:=` gives
canonical equality for free; (3) laws from the pairwise grid, named against
`references/algebra-catalog.md`; (4) quality gates (closure, no privileged
constructors, parsimony, generalization pressure, every combinator in ≥1
law). Confirm signature + laws with the user when the domain is theirs.

### Phase 2 — Signature + semantic domain in code
One `<domain>_algebra` module holding: `-callback` specs, `verify_signature/1`,
the semantic-domain helpers with `-spec`s, and (later) the generator + law
suites. Start by adapting `assets/severity_algebra.erl`.

### Phase 3 — Initial encoding (the oracle)
`<domain>_initial` module: tagged-tuple term type, constructors returning
tuples verbatim, interpreter clauses transcribing the `[[.]]` equations
one-to-one, `eql/2` = compare denotations. It cannot be wrong — that is its
job.

### Phase 4 — Laws as property-based tests
One generator per algebra, built from the implementation's **own
constructors**, depth-bounded, threading explicit `rand:*_s` state from a
fixed seed (patterns in `beam-idioms.md`; use PropEr/StreamData instead when
the project already depends on them). One `verify_<structure>_laws(Mod, Cfg)`
generic over the module, transcribing Phase-1 laws 1:1, echoing seed +
iteration on failure. eunit `_test_()` wrappers with timeouts, plus a
**doctrine-guard test** (structurally distinct, observationally equal pair)
and a **negative contract test** (`verify_signature` on a wrong module raises
the named error). Run now, against the initial encoding only: red here indicts
the *laws or domain* — iterate the design while it's cheap.

### Phase 5 — Derive the final encoding (+ optional process interpretation)
Derive the representation from the denotation (methodology §7): function-like
denotation → tabulate as a map; laws with normal forms → store the normal
form; fold-like → store the accumulator. Add the final module, run the same
law suite, then the **homomorphism test** between encodings. If the domain
will live behind a process boundary, add the process interpretation
(`beam-idioms.md` §5) as a third module through the same suite — this is the
BEAM-specific payoff: laws survive `!` and `receive`.

### Phase 6 — Verify and deliver
`scripts/run_beam_tests.sh <files...>` green; dialyzer clean if available;
negative case checked. Deliver: the modules, a short design note (signature,
laws, named structure, OTP release verified on), and the run command.

## Output structure

```
<domain>_algebra.erl   %% PART 1 signature (-callbacks + verify_signature)
                       %% PART 2 semantic domain (+ -specs)
                       %% PART 4 generator, verify_*_laws/2, homomorphism, eunit
<domain>_initial.erl   %% PART 3a: tagged tuples + exhaustive interpreter
<domain>_final.erl     %% PART 3b: the denotation itself
```

## Anti-patterns to reject on sight

- Structural `=:=`/pattern matching used to judge laws (rule 1) — makes
  correct implementations fail their own suite.
- Catch-all `_` clauses in interpreters over domain variants; `-callback`s
  with no `verify_signature` (silent when unimplemented).
- Combinators that message processes, read ets/persistent_term, or otherwise
  smuggle effects into term semantics.
- Laws tested on hand-picked examples instead of generated terms; a single
  interpretation with no oracle.
- Unverified code: if `erlc` + eunit weren't run, the task is not done.
