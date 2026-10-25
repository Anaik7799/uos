# Artifact Templates

## Contents

1. Ontology and glossary
2. Semantic and signature artifacts
3. Law and interpretation registers
4. Context and event artifacts
5. Verification skeleton
6. Traceability, decisions, and handoff

## 1. Ontology And Glossary

```markdown
| Concept | Category | Denotation | OCaml carrier | Invariant/notes |
|---|---|---|---|---|
| Money | Value object | non-negative integer cents | abstract `Money.t` | smart constructor only |
| Account | Aggregate | identity, balance, history | `Account.t` | transaction boundary |
| Charge | Command | request that may fail | `charge` | validates funds |
| Charged | Event | accepted charge fact | `Charged of Money.t` | `apply` is total |
| Balance | Observation | current non-negative cents | `balance` | defines equality with other observers |
```

```markdown
### Term
- Domain definition:
- Bounded contexts:
- Category: value object | entity | aggregate | command | event | observation | service | policy | invariant
- OCaml identifier:
- Synonyms to avoid:
- Related laws:
```

## 2. Semantic And Signature Artifacts

```markdown
- Carrier:
- Meaning: `denote(t) = ...`
- Defining observations:
- Observational equality:
- Morphism equations:
- Faithfulness limit, if any:
```

```markdown
| Kind | Name | Signature | Denotation equation |
|---|---|---|---|
| Terminal constructor | `zero` | `t` | `denote(zero) = 0` |
| Constructor | `add` | `t -> amount -> t` | `denote(add t a) = denote(t) + a` |
| Combinator | `append` | `t -> t -> t` | `denote(append a b) = denote(a) ++ denote(b)` |
| Observation | `balance` | `t -> amount` | `balance(t) = ...` |
```

```ocaml
module type DOMAIN = sig
  type t
  type error

  (* constructors *)
  (* combinators *)
  (* observations *)
end

module _ : DOMAIN = Initial
module _ : DOMAIN = Final
```

Use opaque sealing at library boundaries and transparent sealing only in
white-box tests:

```ocaml
module Domain : DOMAIN = Final
module Domain_white_box : DOMAIN with type t = Final.t = Final
```

## 3. Law And Interpretation Registers

```markdown
| ID | Name | Quantified equation | Preconditions | Requirement | Structure | Test/seed | Status | Mutant |
|---|---|---|---|---|---|---|---|---|
| L-01 | append associativity | `(a<>b)<>c ~= a<>(b<>c)` | none | R-03 | monoid | `append.assoc`, 42 | green | subtraction/order mutant |
```

```markdown
| Interpretation | Representation | Stratum | Role | Admission relation | Status |
|---|---|---|---|---|---|
| Initial | one constructor per operation | A | oracle | identity | green |
| Final | normalized accumulator | A/B | efficient | observational homomorphism | green seed 1337 |
| Persistent | event log and snapshots | B | durable | replay and chunking | pending |
```

Pairwise law grid:

```markdown
| Operation / observer | `empty` | `append` | `observe` | `size` |
|---|---|---|---|---|
| `empty` | identity | left/right identity | empty observation | zero |
| `append` | identity | associativity | observation homomorphism | additive |
| `normalize` | idempotent | compositional | transparent | non-increasing |
```

## 4. Context And Event Artifacts

```markdown
| Upstream | Downstream | Relationship | Translation | ACL law | Test |
|---|---|---|---|---|---|
| Billing | Shipping | anti-corruption layer | `to_shipping` | `denote_S(to_shipping o)=morph(denote_B o)` | twin seed 1337 |
```

```markdown
| Event | Payload VOs | Apply equation | Commands | Invariants preserved |
|---|---|---|---|---|
| Charged | `Money.t` | subtract amount | `charge` | balance non-negative |
| Refunded | `Money.t` | add amount | `refund` | balance non-negative |
```

```markdown
| Command | Preconditions | Result events | Rejections | Preservation law |
|---|---|---|---|---|
| `charge` | amount positive, funds sufficient | `[Charged amount]` | invalid amount, insufficient funds | applying accepted events preserves invariant |
```

## 5. Verification Skeleton

```ocaml
module Make_laws (A : DOMAIN) = struct
  let expect_law ~name ~seed ~iter prop =
    let state = Random.State.make [| seed |] in
    try
      for _ = 1 to iter do
        assert (prop state)
      done;
      Printf.printf "ok: %s seed=%d cases=%d\n" name seed iter
    with Assert_failure _ ->
      Printf.eprintf "LAW FAILED: %s seed=%d cases=%d\n" name seed iter;
      exit 1

  (* Generate only with A's public constructors. *)
end
```

Twin-seed pattern:

```ocaml
let homomorphism ~seed ~iter =
  let oracle_state = Random.State.make [| seed |] in
  let final_state = Random.State.make [| seed |] in
  for _ = 1 to iter do
    let oracle = Build_initial.term oracle_state in
    let final = Build_final.term final_state in
    assert (Initial.observe oracle = Final.observe final)
  done
```

Dune test stanza:

```lisp
(test
 (name laws)
 (libraries domain qcheck-core)
 (flags (:standard -w +8 -warn-error +8)))
```

Negative conformance is a compile rejection fixture containing a deliberately
incomplete or misshapen implementation:

```ocaml
module _ : DOMAIN = Wrong
```

The test passes only when the compiler rejects `Wrong` for the intended named
contract failure.

## 6. Traceability, Decisions, And Handoff

```markdown
| Req ID | Requirement | Law ID | Test | Module/value | Evidence | Status |
|---|---|---|---|---|---|---|
| R-03 | totals are chunk invariant | L-01 | `append.assoc` | `Domain.append` | seed 42 | green |
```

```markdown
# ADR-N: Title
- Date/status:
- Context:
- Observations affected:
- Candidate laws:
- Decision:
- Consequences:
- Alternatives rejected:
- Assumptions:
- Verification obligation:
```

```markdown
# HANDOFF - System - Date
- Phase reached:
- Confirmed laws:
- Pending laws/questions:
- Interpretations: oracle / final / persistent
- Toolchain:
- Seeds and bounds:
- Mutants killed:
- Negative conformance:
- Coverage map:
- Unverified claims/residuals:
- Next action:
```

Delivery note:

```markdown
Toolchain: OCaml ..., Dune ..., PPX ..., qcheck-core ...
Seeds: ...; bounds: ...
Laws: ...
Homomorphisms: ...
Mutants: ...
Negative conformance: ...
Assumptions/unverified: ...
```
