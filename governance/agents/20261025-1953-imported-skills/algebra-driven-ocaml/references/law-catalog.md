# Law Catalog

## Contents

1. Equality and meaning
2. Pairwise law grid
3. Algebraic structures
4. Domain laws
5. Generators and mutants

## 1. Equality And Meaning

Define equality through the complete observation family:

```text
x ~= y iff for every public observation obs and valid parameter p,
             obs(p,x) = obs(p,y)
```

Do not infer structural equality from observational equality. Require the
meaning function to preserve operations:

```text
denote(op(x,y)) = op_meaning(denote(x), denote(y))
```

## 2. Pairwise Law Grid

Place constructors and combinators on rows. Place observations and other
combinators on columns. Mark each cell with:

- an equation;
- a conditional equation with precondition;
- a rejection/error law;
- a complexity/fuel bound;
- `independent`, with rationale.

No public operation may have an empty row.

## 3. Algebraic Structures

| Property | Equation | Main payoff |
|---|---|---|
| Associativity | `(a op b) op c ~= a op (b op c)` | chunked, tree, or parallel folds |
| Commutativity | `a op b ~= b op a` | reordering and out-of-order merge |
| Identity | `e op a ~= a ~= a op e` | empty case and fold seed |
| Idempotence | `a op a ~= a` | deduplication and convergence |
| Annihilator | `z op a ~= z ~= a op z` | lawful short circuit |
| Involution | `f(f(a)) ~= a` | reversible normalization |
| Distributivity | `a*(b+c) ~= a*b + a*c` | factoring and optimization |
| Absorption | `a join (a meet b) ~= a` | lattice simplification |
| Homomorphism | `denote(f(a)) = g(denote(a))` | interpretation admission |
| Monotonicity | `a <= b implies f(a) <= f(b)` | ratchets and safe refinement |
| Round trip | `decode(encode(a)) ~= a` | codec and persistence correctness |

| Structure | Required laws | Typical OCaml use |
|---|---|---|
| Semigroup | associative operation | non-empty aggregation |
| Monoid | semigroup plus identity | lists, batches, event logs |
| Commutative monoid | monoid plus commutativity | order-independent metrics |
| Idempotent semilattice | associative, commutative, idempotent merge | CRDT convergence |
| Group | monoid plus inverse | undo and reversible transforms |
| Semiring | two monoids plus distribution | weighted paths and counts |
| Lattice | meet, join, absorption | permissions and verdict order |
| Monoid action | `act(m1<>m2,s) ~= act(m1,act(m2,s))` | event replay |
| Functor | identity and composition | structure-preserving map |
| Applicative | identity, composition, homomorphism, interchange | independent validation |

Use the weakest structure required by the real algorithm. Do not claim
commutativity, idempotence, inverses, or convergence because they are useful;
test whether the domain actually grants them.

## 4. Domain Laws

### Validation agreement

```text
is_ok(fail_fast(x)) = is_ok(accumulating(x))
both successful results are observationally equal
```

### Event sourcing

```text
replay determinism: fold(s0, events) is deterministic
chunking: fold(fold(s0, pre), post) ~= fold(s0, pre @ post)
command safety: valid(s) and decide(s,c)=Ok(es) => valid(fold(s,es))
projection: p(fold(s0,es)) ~= fold_p(p(s0),es)
```

### ACL translation

```text
denote_downstream(translate(x)) = morph(denote_upstream(x))
```

### Snapshot and batch laws

```text
resume(snapshot(pre), post) ~= replay(pre @ post)
analyze(concat(chunks)) ~= combine(map(analyze,chunks))
```

### Boundedness

State exact domains and bounds. Examples include maximum generated term size,
maximum fold length, reduction fuel, queue capacity, timeout, and retained
snapshot count. A timeout or fuel exhaustion is an observed result, never a
silent skip.

## 5. Generators And Mutants

Generators must:

- construct values through the public algebra;
- include boundary and invalid inputs;
- be seeded and bounded;
- support counterexample replay;
- use twin seeds for cross-interpretation construction.

Mutants should alter meaning, not formatting. Prefer:

- replace an operation with a non-associative one;
- remove identity handling;
- bypass a smart constructor;
- reorder non-commutative events;
- skip one replay event;
- weaken an invariant check;
- make a projection non-incremental;
- accept a wrong ACL translation;
- treat unknown or timeout as success;
- compare representation instead of observations.

Record the exact law that turns red. Equivalent mutants are classified, not
counted as killed.
