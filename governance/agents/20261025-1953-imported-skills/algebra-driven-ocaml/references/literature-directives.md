# Literature Directives

Use these as design provenance, not as substitutes for project evidence. Check
the actual edition and tool versions when exact bibliographic or compatibility
claims matter.

## Algebra And Denotation

- **Sandy Maguire, Algebra-Driven Design:** define syntax and observations,
  then let equations supply meaning; derive optimized representations from the
  laws instead of reverse-engineering laws from code.
- **Conal Elliott, denotational design and type-class morphisms:** choose a
  simple semantic domain and require operations to preserve meaning. Disclose
  when no faithful simple denotation exists.
- **Guttag, Horning, Goguen, and initial-algebra traditions:** use an initial
  syntax as an executable semantic oracle before quotienting or optimizing it.
- **Bird and de Moor, algebra of programming:** calculate folds, fusion,
  accumulators, and transformations from equations.
- **Backus, algebra of programs:** prefer compositional value-transforming
  forms that support equational reasoning.
- **Stepanov and Elements of Programming:** derive the weakest concepts needed
  by real algorithms and preserve regular whole-part value semantics.

## Domain Modeling

- **Eric Evans, Domain-Driven Design:** preserve one ubiquitous language,
  explicit bounded contexts, aggregate consistency boundaries, and named
  context-map relationships.
- **Vaughn Vernon, implementing DDD:** keep aggregates small, enforce
  invariants at the root, and make integration boundaries explicit.
- **Debasish Ghosh, functional and reactive domain modeling:** model behavior
  and compose pure domain algebras separately from effectful interpreters.
- **Scott Wlaschin, domain modeling and railway-oriented programming:** make
  illegal states unrepresentable and choose validation composition according
  to whether errors are dependent or independent.

## OCaml And Typed Design

- **Yaron Minsky and Real World OCaml:** use variants for exhaustive state
  spaces, abstract modules for invariants, and compiler errors as evolution
  pressure.
- **OCaml module and type system practice:** write signatures first, seal at
  ownership boundaries, use smart constructors, GADTs for typed syntax, and
  phantom types for protocol state.
- **Free/final and interpreter-oriented architecture, including Granin:** keep
  effect descriptions separate from interpretation, and compare multiple
  interpreters against one semantic contract.
- **Eric Normand, Actions/Calculations/Data:** keep reusable calculations pure,
  data explicit, and runtime actions at the boundary.

## Verification

- **Claessen and Hughes, QuickCheck:** properties generalize examples; seeded
  generators, shrinking, and counterexamples make laws executable.
- **QuickSpec work by Claessen, Smallbone, Johansson, and collaborators:** use
  signature-driven candidate equations as prompts for human-confirmed laws,
  not as automatic business requirements.
- **Mutation testing:** demonstrate that properties discriminate plausible
  wrong meanings, rather than only executing code.
- **Model-based and differential testing:** use independent state machines,
  external oracles, and trace agreement where a simple denotation is
  insufficient.

## Safety And Decision Boundaries

- **Leveson, STPA and CAST:** model development and evidence tooling as control
  systems; identify unsafe control actions, constraints, feedback, and process
  model flaws, especially on admission paths.
- **Production-rule systems:** separate fact projection from rule evaluation;
  a rule can gate only facts grounded in reality, not self-attested notes.
- **Ruliology and rewrite-system analysis:** for normalizers and rule transforms,
  examine termination, confluence, critical pairs, idempotence, and normal
  forms against the real consumer.
- **Bayesian and Stan practice:** probabilistic inference quantifies uncertainty
  but does not establish semantic correctness. Require an independent oracle,
  calibration, diagnostics, and an advisory-only authority boundary unless a
  separate safety case changes it.

## Synthesis Rule

When sources suggest different abstractions, resolve the disagreement through
the domain observations and laws. Record the decision and its consequences.
Do not import terminology, type classes, frameworks, or proofs merely because
they are canonical in a book.
