---
name: algebra-driven-ocaml
description: Design, implement, review, or migrate OCaml systems as law-governed algebras using observations-first requirements, semantic domains, signatures, property laws, oracle and final interpretations, twin-seed homomorphism, smart constructors, event-sourcing laws, and mutation verification. Use for any OCaml domain model, library, service, aggregate, persistent interpreter, API, workflow, or function where correctness and compositional semantics matter.
---

# Algebra-Driven OCaml

Treat this skill as the primary doctrine for authored OCaml. Design every unit,
from a whole system to one function, through the same loop:

```text
Ontology -> Signature -> Laws -> Interpretations -> Verification
```

The equations define behavior. An implementation is only one interpretation
of those equations.

## Establish The Contract

Before code:

1. Restate the domain in the user's language.
2. List observations first: what can an outside party learn from each value?
3. List givens and assumptions. Record assumptions in the decision log.
4. Ask only questions whose answers change a public signature, invariant, or
   business law. Proceed with explicit assumptions for other uncertainty.
5. Classify each concept as value object, entity, aggregate, command, event,
   observation, service, policy, or invariant.
6. Convert each acceptance criterion into a quantified equation or a
   generalizable example with explicit preconditions.
7. Present the glossary, ontology, and requirement-to-law map for confirmation
   before implementation when a law encodes a business choice.

Read [phase-gates.md](references/phase-gates.md) for the complete gated
workflow and fractal scale obligations.

## Apply The Six Gates

1. **Requirements:** observations, glossary, ontology, assumptions, and
   requirement-to-law map exist.
2. **Semantic design:** semantic domains, signatures, error strategies,
   context boundaries, and effect boundaries exist.
3. **Law design:** the pairwise law grid covers every public constructor,
   combinator, and observer; business laws are confirmed.
4. **Oracle:** an initial encoding passes the seeded law suite before an
   optimized encoding is written.
5. **Final interpretation:** the efficient and effectful interpretations pass
   the same laws and a twin-seed observational homomorphism against the oracle.
6. **Delivery:** compilation, negative paths, mutation, exact toolchain,
   seeds, law status, residuals, and handoff are recorded.

Do not skip a gate by calling prose, examples, or passing unit tests a law.

## Keep Three Strata Separate

- **Stratum A, algebraic core:** pure carriers, constructors, combinators,
  observations, invariants, laws, and initial denotations.
- **Stratum B, engines and interpretations:** persistence, state machines,
  async execution, projections, optimized encodings, and adapters admitted by
  homomorphism, state equality, trace equivalence, or an explicit bound.
- **Stratum C, substrate:** I/O, clocks, randomness, schedulers, databases,
  network libraries, effect handlers, and foreign runtimes. Quarantine these
  behind typed interpreters; never let substrate behavior define a core law.

## Enforce The OCaml House Style

1. Compare values through observations, never representation equality.
2. Ship at least two interpretations for each nontrivial algebra: initial
   oracle and final encoding.
3. Keep effects out of algebraic combinators.
4. Match domain variants exhaustively; compile warning 8 as an error.
5. Assert compile-time conformance with `module _ : SIG = Impl`.
6. Make smart constructors the only path to invariant-bearing values.
7. Build generators only through public constructors.
8. Run the real pinned toolchain, deterministic property suites, twin-seed
   homomorphism, negative conformance, and law-targeted mutants.

Use GADTs for typed initial syntax, phantom types for protocol state, and
ordinary variants to make illegal state combinations unrepresentable. Choose
fail-fast `result` for dependent validation and accumulating validation for
independent errors; whenever both exist, test their success and value
agreement.

Read [law-catalog.md](references/law-catalog.md) when selecting structures,
filling the law grid, designing event sourcing, or choosing mutant targets.

## Derive, Do Not Guess, The Final Encoding

Start with one initial constructor per algebra constructor. Define observers
directly from the semantic domain. Make its law suite green. Then derive the
final representation using only law-licensed transformations such as:

- canonical or normalized forms;
- tabulation of function-like meanings;
- fold accumulators and catamorphisms;
- monoid or semiring aggregation;
- snapshots licensed by fold chunking;
- incremental projections licensed by homomorphism.

Run the same `Make_laws` functor over every interpretation. Build equivalent
terms from two identically seeded `Random.State.t` streams and compare all
observations.

## Treat Effects And Boundaries As Interpretations

Persistence, HTTP, UI, concurrency, browser control, time, randomness, and
external services are interpretations. Define anti-corruption layers as typed
translations and test the translation homomorphism. For event-sourced
aggregates require replay determinism, fold chunking, invariant preservation,
and projection homomorphism.

## Integrate With The Host Repository

Repository rules override generic defaults. Discover and report the actual
compiler, Dune, package, and PPX versions; never claim a version is current
without evidence. In zigvm specifically:

- use exact OCaml 5.5.0 and `skills/ocaml-scripting/SKILL.md`;
- keep VM semantics in Zig and OCaml in the harness, scripts, services, and
  generated frontend pipeline only;
- access SQLite only through the harness `Db` actor or authored OCaml;
- use `algebraic-fractal-structures` for ZigVM semantic slices;
- use `stpa-safety-protocol` for controllers and evidence paths;
- use `formal-technique-selection` for proof, SMT, model, Rete, or ruliology
  choices;
- keep Stan advisory under `stan-probabilistic-substrate`;
- use `ocaml-playwright-control` for browser automation;
- admit completion only through the canonical harness and Zero-Trust gate.

Read [zigvm-integration.md](references/zigvm-integration.md) for the L0-L10,
STPA, Rete-UL, ruliology, Stan, harness, skill, agent, and artifact crosswalk.
Read [system-qualities.md](references/system-qualities.md) for structure,
control/data/evidence planes, distributed-systems criteria, actor and Zenoh
messaging, robustness, durability, availability, scalability, performance,
logging, introspection, debugging, and tracing laws.

## Produce The Artifacts

Read [source-prompt.md](references/source-prompt.md) for the provenance rule.
When this skill's source requirement or scope is disputed, treat
`references/source-prompt.jsonl` as the authoritative lossless user-prompt
transcript. Never normalize, deduplicate, reflow, or silently replace it with a
summary; derived artifacts must link to it and record assumptions.

Use [artifact-templates.md](references/artifact-templates.md) for the ontology,
glossary, domain language, semantic domain, ruleset, interpretation register,
context map, event catalog, traceability matrix, ADR, property suite, and
handoff. Keep identifiers in the ubiquitous language and link every law to its
requirement, test, implementation, seed, and killed mutant.

Use [literature-directives.md](references/literature-directives.md) when a
design choice needs its theoretical basis or a reviewer needs provenance.

## Reject These Failure Modes

- implementation-first design with laws inferred afterward;
- structural equality standing in for observational equality;
- one representation with no independent oracle;
- generators that fabricate private constructors;
- wildcard matches over evolving domain variants;
- unbounded or unseeded property tests;
- a persistent interpreter called equivalent without replay evidence;
- an advisory model, report, or agent assertion treated as gate evidence;
- claims of proof where only tests, bounded search, or prose exist;
- delivery without exact versions, seeds, law results, mutants, and residuals.

## Close With Evidence

Every delivery states:

- toolchain and dependency versions actually used;
- deterministic seeds and iteration bounds;
- law suites and interpretation status;
- homomorphism status;
- mutants injected and killed, or why mutation is not applicable;
- negative conformance result;
- assumptions, unverified claims, and remaining semantic gaps;
- the next concrete action in the handoff.

## Fractal FP atlas synchronization

When authored OCaml changes a path classified by
`Fractal_fp_atlas_surface.classify`, preserve the carrier/denotation/law change
in the relevant atlas registry entry, regenerate the eleven projections, run
`--selfcheck-fractal-fp-atlas` and `--wiki-audit`, then record
`phase:atlas_sync`. The phase is traceability only; exact-head Green Stamp
evidence remains authority, and a classifier-empty diff adds no atlas work.
