# beam-zig — a BEAM VM in Zig, algebra-driven

Every subsystem of the VM is specified as an algebra (signature + laws +
semantic domain), implemented twice (an obviously-correct initial encoding as
the oracle, an efficient final encoding for production), and glued by
homomorphism property tests. Methodology: the `algebra-driven-zig` skill;
BEAM-side semantics cross-checked against `algebra-driven-beam` and erts
(github.com/erlang/otp, `erts/emulator`).

## Why algebra-driven is the right tool for a VM specifically

A VM is a stack of *representation changes* that must each preserve meaning:
source terms → tagged words → GC-relocated words → serialized (distribution)
words; programs → bytecode → dispatched execution. "Preserves meaning under a
representation change" **is** the homomorphism property. So the entire
correctness story of the VM becomes: one semantic domain per subsystem, and a
homomorphism test at every representation boundary. Notably:

- **A copying GC is a heap-to-heap homomorphism.** Its whole spec is
  `denote(after) == denote(before)` with the old heap poisoned. (Milestone 1
  ships this, verified.)
- **The bytecode interpreter vs. any optimized dispatch** (threaded code,
  JIT later) is initial vs. final encoding of the instruction algebra.
- **Term order/equality over tagged words** vs. over canonical trees is the
  compare homomorphism — the oracle catches pointer-identity and tag-decoding
  bugs that unit tests reliably miss.

## The algebra decomposition

The same decomposition describes the whole project. `docs/ONTOLOGY.md` defines
first-class L0-L10 layers, nine planes, canonical components, S1-S33,
artifacts, control objects, and typed interactions;
`docs/FRACTAL_ONTOLOGY.md` defines their recursive closure. The OCaml
`refresh_ontology` projection materializes and validates that graph atomically.
Architecture changes update this registry and pass `--wiki-audit`; database
access is harness/OCaml-only.

| # | Algebra | Constructors / combinators | Observations (semantic domain) | Key laws | Structure |
|---|---|---|---|---|---|
| 1 | **Term** | `int, atom, nil, cons, tuple` (+ later: float, binary, map, pid, fun) | `denote : Term -> Value` (canonical tree); `compare : (Term,Term) -> lt/eq/gt` | total preorder (refl, antisym, trans); `eql ⇔ compare=eq`; equality is by value, never address; Erlang kind order `number < atom < tuple < nil < cons` | total order + congruence |
| 1b | **Heap/GC** | `copy : (Heap, Heap, Term) -> Term` | same `denote` | `denote(copy(t)) == denote(t)`, valid after source-heap poisoning; (later, with forwarding: sharing/DAG preservation) | homomorphism |
| 2 | **Atom table** | `intern : bytes -> AtomIdx` | `nameOf : AtomIdx -> bytes` | `intern` injective up to `nameOf`; `nameOf(intern(s)) == s`; compare-by-index consistent with... nothing — Erlang atom *order* is by name: law ties `compare(atom a, atom b)` to `lexical(nameOf a, nameOf b)` and forces the M1 stub to be upgraded | interning bijection |
| 3 | **Pattern match** | patterns: `pvar, plit, pcons, ptuple, pwild` | `match : (Pattern, Term) -> ?Bindings` | round-trip: `match(p, build(p, θ)) == θ` for linear p; failure soundness: no partial bindings observable; substitution composition | partial function + unifier laws |
| 4 | **Mailbox** | `deliver : (Mbox, Msg) -> Mbox`; `recv : (Mbox, Pattern) -> ?(Msg, Mbox)` | queue-as-sequence | per-sender FIFO; selective receive = first match in arrival order; `recv` removes exactly one; deliver is associative-with-append (list monoid action) | monoid action |
| 5 | **Instructions / reductions** | `nop, seq, move, call, ret, send, recv_loop, test+jump` over a register file | small-step `step : State -> State` + big-step trace | `seq(nop,p)==p`, `seq` associative (monoid); step determinism; reduction budget decrements exactly 1 per step (fuel law) | monoid + deterministic LTS |
| 6 | **Process & scheduler** | `spawn, yield, exit`; scheduler `pick : RunQ -> (Pid, RunQ)` | observable event trace (multiset + per-process order) | per-process program order preserved; no run-starvation under finite budgets (every ready pid scheduled within N·budget); send/receive causality (a message is received after it is sent) | fairness over an LTS |
| 7 | **External term format** | `encode/decode` (dist protocol subset) | round-trip into Term's `denote` | `denote(decode(encode(t))) == denote(t)` | serialization homomorphism |
| 8 | **Module/BEAM loading** | `.beam` chunk parse → instruction algebra terms | disassembly denotation | load∘assemble = id on the supported subset | round-trip |

Dependency spine: 1 → (2,3) → 4 → 5 → 6; 7 and 8 hang off 1 and 5. Each
milestone lands only when its law suite + boundary homomorphisms are green
against the oracle encoding, per the skill's Phase 4–6 gates.

## Milestone 1 — shipped in `src/term_algebra.zig` (this drop)

- **Semantic domain** `spec.Value`: canonical term trees with the Erlang
  total term order implemented once, as executable specification.
- **Initial encoding** `InitialTerms`: terms *are* canonical trees
  (arena-owned). Cannot be wrong; exists to be the oracle.
- **Final encoding** `FinalTerms`: erts-faithful 64-bit tagged words over a
  bump-allocated process heap — primary tags `header=00, list=01, boxed=10,
  immediate=11`; small ints and atoms immediate; cons = 2-word cells; tuples
  = arity header + elements. `compare` walks raw words directly (no tree
  materialization), exactly like `erts/emulator/beam/utils.c` does.
- **Copying GC** on the final encoding, verified by the poisoned-source
  homomorphism law.
- **Law suite** (property-based, seeded, generic over the encoding):
  reflexivity, antisymmetry, transitivity, eql⇔compare, value-not-address
  equality, spec-agreement of `compare`, cross-encoding homomorphism,
  GC homomorphism, doctrine guard, negative signature contract.

Deliberate M1 simplifications, each promoted to a later milestone by an
already-stated law: atoms are indices (M2's lexical-order law forces the atom
table); GC duplicates shared subterms (semantics-preserving on trees; M1.5
adds forwarding words for DAG sharing + cost laws); ints are ≤60-bit smalls
(bignums join in M2 as boxed, constrained by the same order laws).

## Ground rules (from the skills, non-negotiable)

Observational equality only; oracle + efficient encoding + homomorphism at
every boundary; exhaustive switches over domain unions; arena/heap ownership
explicit; comptime signature contracts that diagnose by name; Stepanov/EOP/ADD
concept extraction with weakest useful requirements, whole-part value
semantics, iterator/coordinate separation, initial encodings, semantics
freezing, efficient final encodings, validation, and measurement; nothing lands
uncompiled. The normal repository gate is
`opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD"`.
