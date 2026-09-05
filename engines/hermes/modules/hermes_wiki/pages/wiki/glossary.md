---
id: hermes-glossary
status: published
type: reference
ktype: source
maturity: incubating
domain: formal_verification
topics: [glossary, vocabulary, terminology]
created: 2026-08-09
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Glossary — the controlled vocabulary, enforced

#feature #src-unified #area-address #cov-vocabulary

The corpus's private vocabulary as a CHECKED artifact instead of an oral
tradition (HW.3.7.4). Every level-2 heading below defines one term; a
[[term:parity]]-style reference anywhere in the corpus resolves here and
ONLY here — a term used and defined nowhere is a diagnostic, by the kind
law `kind(resolve_k(x)) = k`.

## Parity

Byte-equality between the candidate's output and the frozen reference's,
after canonical normalization, at differential evidence levels L4–L6.
Only an Implementation-origin divergence may deny parity credit (R5).

## Divergence

A measured difference between candidate and reference. A divergence is a
successful measurement, never a suite failure; it is recorded, diagnosed
with a fractal coordinate and an RCA origin, and fixed at its cause.

## Oracle

An external tool or a frozen implementation consulted for ground truth.
Oracles are consulted, never authored here; a missing oracle is
unavailable or blocked, never passing.

## Frozen reference

The pinned snapshot a candidate is measured against. It is digest-pinned,
never edited to flatter the candidate, and probed rather than guessed.

## Evidence chain

The receipt lattice L0 product → L6 receipt: every claim's path from the
whole system down to a digest. The wiki corpus has its OWN fractal, and
the two are never identified (R9).

## Fractal level

The coordinate that says WHERE in a plane's fractal a finding sits —
L0..L6 within a plane, LX for the control plane. Carried by every
diagnostic beside its RCA origin, which says where to go looking.

## Ratchet

The monotone gauge discipline: sensed values may only improve against
their pins; any adverse movement is a breach that must be explained and
fixed at its source. Re-pinning is a deliberate act, never automatic.

## Gauge

One sensed integer with a pinned bound — dead links, schema debt,
orphans. Every pinned gauge is a telemetry channel of the FPP topology,
so nothing is measured that the actor model cannot carry.

## Mirror

A structural port from the prior ZigVM harness or the import fleet
(R14): survey first, reuse or structurally mirror, never reinvent. The
import ledger dispositions every mirror source; `unported_mirrors`
ratchets the backlog down.

## Suppressed reference

The per-reference opt-out `[[!target]]` (HW.3.7.6): mentioned, not
asserted. It makes no edge, is never warned about, and is always
disclosed by count — an escape hatch that leaves a mark.

## Muda

Structure that serves no stratum: duplicated artifacts, phantom edges,
dead configuration. Cleared, never accumulated; the workspace strata
(R17) exist so muda has nowhere to hide.

## Corpus

The tracked document set (`git ls-files` under the pinned roots): an
untracked note is invisible until committed. Membership is the first
gate every other law builds on.

## Doctest

A TESTED example (HW.9.3.1): a `doctest`-tagged fence whose `> input`
markdown must render to exactly the expected lines. This page carries a
live one — if the paragraph grammar ever changes, this document drifts
loudly instead of lying quietly:

```doctest
> code is not prose
<p>code is not prose</p>
```
