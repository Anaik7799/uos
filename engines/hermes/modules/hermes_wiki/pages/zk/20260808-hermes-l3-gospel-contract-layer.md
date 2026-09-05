---
migrated_from: docs/zk/20260808-hermes-l3-gospel-contract-layer.md (zigvm-era tree, authored for Hermes)
---
# Architectural Decision: L3 Contracts Are Gospel-Specified Interfaces

**Date:** August 8, 2026
**Topic:** Hermes Harness Evidence Fractal — L3 layer and its toolchain

## Decision
An L3 contract is a Gospel-specified OCaml `.mli` bound to an L2 capability
slice. It is stored as two records, not one: a declaration stable per snapshot
(`capability_contract`), and a check receipt keyed by snapshot, contract,
harness revision and verifier (`capability_contract_receipt`). Only a `checked`
verdict grants L3 credit.

## Rationale
- **Receipts are observations, not properties.** Whether gospel ran at all is a
  fact about the environment. Folding it into a single verdict column would
  make an "unavailable" observation collide with a later real check under the
  divergent-replay guard; keying by revision and verifier lets both coexist as
  history.
- **A tooling gap is not a specification defect.** When gospel cannot resolve a
  module it reports failure, but that is L5 (environment), not L4 (type).
  Recording it as `rejected` would write a false negative into the evidence
  store, which is the one thing this store exists to prevent.
- **Stubs must only be able to reject.** `hermes_harness/gospel_stubs` supplies
  names gospel cannot resolve alone. Every stub is strictly weaker than the
  interface it stands in for — an abstract type gives gospel fewer facts — so a
  spec that checks against a stub also checks against the real module. A stub
  carrying constructors or equations would reverse that and let a contract pass
  on facts the real type does not provide.
- **The toolchain is pinned, not assumed.** Released gospel 0.3.1 cannot parse
  OCaml 5.5.0's stdlib (`CamlinternalFormatBasics.neutral_concat`). It is
  patched and pinned into the project switch; the patch ships with the
  `writing-gospel-specifications` skill. Upstream master already fixes this but
  is unreleased and has breaking spec-syntax changes, so it is not adopted.

## Status
Two contracts declared, both `checked`: turn budget monotonic consumption, and
message hygiene sanitization idempotence. Strict parity remains `0 / 18` — a
checked contract is an obligation, and only L4–L6 differential evidence moves a
family.
