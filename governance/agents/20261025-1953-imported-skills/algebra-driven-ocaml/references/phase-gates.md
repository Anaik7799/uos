# Phase Gates

## Contents

1. Fractal scales
2. Gate 1: requirements
3. Gate 2: semantic design
4. Gate 3: laws
5. Gate 4: oracle
6. Gate 5: final interpretations
7. Gate 6: delivery

## 1. Fractal Scales

Apply the complete loop at every scale.

| Scale | Ontology | Signature | Laws | Interpretations | Verification |
|---|---|---|---|---|---|
| System | domain vision and context map | top-level service algebra | cross-context consistency | deployable system and reference model | end-to-end observational agreement |
| Bounded context | ubiquitous language | one module type per context | invariants and ACL translation | memory and persistent forms | context laws plus ACL homomorphism |
| Aggregate/service | root, commands, events | command/event algebra | replay, chunking, invariant preservation | event list and snapshot/store | state and projection agreement |
| Module | file concepts | `.mli` or module type | structure and domain laws | oracle and optimized module | shared law functor |
| Function | input and output concepts | `val` signature | pre/post equation | direct and law-derived forms | examples, properties, mutation |

The parent observes only the child's published observations. A child is
admitted when its interpretation preserves those observations.

## 2. Gate 1: Requirements

Produce:

- a domain restatement;
- givens, assumptions, and signature-changing questions;
- observations for every externally meaningful carrier;
- a ubiquitous-language glossary;
- an ontology classifying every concept;
- a requirement-to-law list;
- non-functional laws for bounds, fuel, capacity, chunking, and space.

Generalize examples carefully. Record preconditions. Surface any business
choice in plain English with its candidate equation. Stop for confirmation
when a different answer changes a public law.

Gate condition: no requirement remains as unclassified prose when it can be an
observation, invariant, law, explicit example, or acknowledged unknown.

## 3. Gate 2: Semantic Design

For every carrier write `denote(t) = mathematical meaning`. Choose the smallest
meaning jointly exposed by the observations. If no faithful simple denotation
exists, use the explicit initial syntax as the semantic model and disclose the
limit.

Design signatures for:

- closure and compositionality;
- a parsimonious constructor basis;
- orthogonality or explicitly derived operations;
- no representation escape hatch;
- smart-constructor enforcement;
- an observation for each requirement;
- a law for each public operation.

Map bounded contexts. For each boundary define an ACL translation and the law:

```text
denote_B(translate(x)) = morph(denote_A(x))
```

Choose fail-fast or accumulating validation. If both are exposed, require:

```text
is_ok(fast(x)) = is_ok(accum(x))
fast(x) = Ok(v) and accum(x) = Ok(w) implies observe(v) = observe(w)
```

Quarantine I/O, persistence, time, randomness, concurrency, UI, and external
runtimes behind interpreter signatures.

Gate condition: semantic domains, signature skeletons, context map, error
strategy, and effect boundaries are explicit.

## 4. Gate 3: Laws

Build a pairwise grid with constructors/combinators on rows and observations
plus other operations on columns. For each cell ask whether an equation,
precondition, rejection rule, or explicit non-law relates them.

Search for identity, associativity, commutativity, idempotence, involution,
annihilation, distributivity, absorption, monotonicity, round trips,
homomorphisms, chunking, and boundedness. Record the weakest structure that
supports the real algorithms.

Require:

- observational equality, not representation equality;
- quantified variables and preconditions;
- source requirement and test name;
- generator domain and seed;
- at least one discriminating mutant target per significant law;
- complete operation coverage.

Gate condition: the human confirms business laws, and every public operation
appears in at least one law or explicit rejection contract.

## 5. Gate 4: Oracle

Implement the initial encoding first. Prefer one data constructor per algebra
constructor. Define observations directly from the semantic domain.

Write a `Make_laws` functor over the public signature. Generators use only
public smart constructors. Echo seeds and bounds on failure. Include negative
construction and negative module-conformance checks.

Gate condition: the initial encoding compiles with exhaustive matching and its
complete seeded law suite is green. Do not begin an efficient representation
before this gate.

## 6. Gate 5: Final Interpretations

Derive the final encoding from laws: normal form, table, fold accumulator,
snapshot, persistent log, indexed representation, or another justified form.
Run the oracle law functor unchanged.

For each oracle/final pair:

1. Create two `Random.State.t` values from the same seed.
2. Run the same public construction script against each implementation.
3. Compare every observation, including error and trace observations.
4. Bound the script length and report the seed on failure.

For event sourcing require:

```text
fold(fold(s0, pre), post) = fold(s0, pre @ post)
valid(s) and command(s,c) = Ok(events) implies valid(fold(s,events))
project(fold(s0,events)) = fold_project(project(s0),events)
```

Gate condition: shared laws and homomorphisms are green for every admitted
interpretation. Effects have explicit failure and teardown behavior.

## 7. Gate 6: Delivery

Run the real project toolchain. Treat warnings, hangs, missing evidence, and
unknown solver outcomes according to repository policy, normally fail-closed.

Record:

- compiler, Dune, PPX, and direct dependency versions;
- commands, seeds, iterations, time/fuel bounds;
- law suite and interpretation matrix;
- homomorphism result;
- negative conformance result;
- mutant IDs and laws that killed them;
- unresolved assumptions and semantic gaps;
- artifact and traceability updates;
- one concrete next action.

Never label reasoned-only code verified. Never let a probabilistic estimate,
agent report, or cached prose substitute for exact-revision evidence.
