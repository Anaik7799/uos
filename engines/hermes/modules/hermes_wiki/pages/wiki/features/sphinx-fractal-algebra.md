---
id: hermes-sphinx-fractal-algebra
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Sphinx — fractal algebra

#feature #src-sphinx #area-algebra #cov-analysis

## 1. Typed reference

- **Carrier** `Target = Domain × Kind × Name`
- **Operation** `resolve : Kind → Name ⇀ Target`
- **Identity** the local document's own namespace
- **Absorbing** an unresolved reference under nitpicky — it **fails the build**
- **Laws**
  - *kind soundness*: `kind(resolve_k(x)) = k` — resolving to the wrong kind is
    a failure, not a fallback
  - *disjointness*: `d ≠ d' ⟹ (d,n) ≠ (d',n)`, so cross-domain collision is
    **unrepresentable**
  - *unique resolution*: `|resolve_any(x)| = 1`, with `0` and `>1` reported
    **distinctly**
  - *disclosed suppression*: `!x` suppresses the warning and leaves a mark in
    the source

**HERMES.** Our resolver is `Key ⇀ Slug`, untyped, first-registration-wins, and
ambiguity is a notice at the *definition* site. HW.3.7.1–3 close the gap; the
`|·| = 1` law is the one worth taking first, because the reader is harmed at
the *use* site.

## 2. Navigation

- **Carrier** the toctree
- **Operation** `attach : document → parent → tree`
- **Identity** the root document
- **Absorbing** none
- **Laws** *tree* (single root, acyclic, each document once) · *hidden ≠
  orphaned*: `:hidden:` registers the edge without rendering the link ·
  *reachability*: unreachable ∧ ¬`:orphan:` ⟹ diagnostic

**HERMES.** HW.6.8.1–2. The `:orphan:` opt-out is the pattern our rules already
use — strict by default with a **disclosed** exception that leaves a mark.

## 3. Inventories — a functor between projects

- **Carrier** `Inventory = Name ⇀ URI` (root-relative)
- **Operation** `resolve_ext : Inventory list → Name ⇀ URI`, consulted **only
  after** local resolution fails
- **Identity** the empty inventory
- **Absorbing** none
- **Laws** *layout independence*: the citing project never encodes the cited
  project's paths · *fail-closed*: unresolvable ⟹ diagnostic, never a silent
  plain-text fallback

This is the only *inter-corpus* algebra in the survey. Formally it is a partial
map between name spaces that composes: `resolve_ext` over a list is the
left-biased union of partial maps — a monoid with the empty inventory as unit.

**HERMES.** HW.3.8.1–2. Additional obligation for us: inventories are read from
**local paths only**, because a network fetch in the render path would
reintroduce the non-determinism HW.3.1.5 was excluded to avoid.

## 4. Executable documentation

- **Carrier** test blocks partitioned into **groups**
- **Operation** `run : group → setup* → test+ → Result`
- **Identity** the empty group (vacuously passes)
- **Absorbing** a failing test
- **Laws**
  - *setup precedence*: setup blocks run before tests in the group
  - *isolation*: running groups together = running each alone
  - *cleanup totality*: cleanup runs even on failure
  - *disclosed skips*: `:skipif:` names and counts what was not run

**HERMES.** HW.9.3.*. The R5 refinement is ours to add: a doctest failure is a
**documentation-drift** diagnostic — it may *block* credit, never *deny* it,
because it says our prose is stale, not that the candidate diverged.

## 5. Coverage

- **Carrier** documented objects vs all objects
- **Operation** `coverage : Module → ℚ × Name list`
- **Identity** an empty module (100%, vacuously)
- **Absorbing** an unanalysable module — **0% with a reason**, never omitted
- **Laws** *fail-closed* (above) · *names, not counts*: a percentage is a
  score, a list is a worklist

**HERMES.** `Formal_coverage` is the same shape aimed at the inverse gap: ours
answers "what is verified", Sphinx's "what is documented". HW.9.4.* adds the
second census.

## 6. The build

- **Carrier** `(Environment, Corpus)`
- **Operation** `build : Env × Corpus → Env × Output`
- **Identity** the empty environment (a cold build)
- **Absorbing** a warning under `-W` — every warning becomes an error
- **Laws**
  - *soundness before speed*: `output(build(env, c)) = output(build(∅, c))` for
    every reachable `env` — an incremental render must equal a cold one
  - *dependency over-approximation is safe*: `reads(render d) ⊆ deps(d)`;
    under-approximation is **not**, because it yields a stale page the gate
    then pins
  - *ratchet*: with `-W`, `warnings(HEAD) ≤ warnings(HEAD~1)`

**HERMES.** HW.10.*. The ratchet is the half we lack: our notice/defect split
is the right *classification*, but nothing stops the notice count growing.

## 7. Import — the excluded algebra

- **Carrier** Python modules
- **Operation** `import` during the build
- **Laws** none — arbitrary code executes

**HERMES — exclusion invariant.** The build **imports nothing**;
`iface_doc : Mli ⇀ Doc` is a **static parse** and a pure function of the file
bytes. Executing code during a render would end determinism, and the render
baseline with it.

Cross-references: `[[Sphinx — fractal ontology]]` · `[[Sphinx — fractal atlas]]` ·
`[[Unified fractal algebra]]`.

Part of [[Knowledge fractal map]].
