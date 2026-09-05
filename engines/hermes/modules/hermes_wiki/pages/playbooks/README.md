# Hermes harness playbooks — implementation instructions for ANY model

These playbooks turn every recurring harness operation into a **mechanical
recipe**: exact files, exact anchors, exact commands, expected outputs, and a
STOP rule for every failure. They are written so that a **lower-end model (or a
new contributor with zero context)** can implement correctly without inferring
anything. If a step requires judgment, the playbook says exactly which judgment
and gives the decision table.

## The executable-by-anyone contract

Every playbook step obeys four properties:

1. **Mechanical** — the action is a concrete edit at a named anchor or a
   concrete command. No step says "appropriately" or "as needed".
2. **Verifiable** — each step ends with a VERIFY command and its expected
   output shape. Do not proceed past a failed VERIFY.
3. **Fail-closed** — every IF-FAIL branch either names the fix or says
   **STOP — jidoka** (halt, report the failing output verbatim, do not
   improvise). Stopping is always acceptable; improvising is never.
4. **Substitution-explicit** — templates use `⟨PLACEHOLDER⟩` markers and each
   playbook opens with the substitution table. Fill every placeholder before
   editing; a leftover `⟨` in any file is an error.

## Index

| # | Playbook | Use when |
|---|---|---|
| 00 | [Glossary and map](00-glossary-and-map.md) | You need any term, file location, or command — read FIRST |
| 01 | [Add a parity slice](01-add-parity-slice.md) | Adding differential evidence for a new frozen-reference capability |
| 02 | [Declare intent & run the loop](02-declare-intent-and-run-loop.md) | Adding a blueprint directive; running/reading auto-convergence |
| 03 | [Resolve a divergence](03-resolve-divergence.md) | A compare printed DIVERGENT and you must decide what to do |
| 04 | [Add a Gospel contract](04-add-gospel-contract.md) | A new candidate `.mli` needs its L3 contract |
| 05 | [Sync the formal legs](05-sync-formal-legs.md) | You changed the blueprint DAG, the lattice, or the algebra |
| 06 | [Close-out checklist](06-close-out-checklist.md) | A slice/feature landed and you must finish the bookkeeping |

## The iron rules (violating ANY of these voids the work)

| # | Rule | Meaning for you |
|---|---|---|
| R1 | OCaml only | Never run `python3` as a tool — not in a heredoc, not to pretty-print JSON. The ONLY Python that ever runs is the frozen reference via a declared adapter. |
| R10 | Only L4–L6 differential evidence grants parity | You cannot make anything "Verified" by editing catalogs, docs, dashboards, or blueprints. Only a real capture + compare does that. |
| R5 | Only Implementation origin denies credit | An environment/tooling failure is Blocked, never Divergent. Never record a missing tool as a candidate defect. |
| R13 | Resources checked before use | Operations that write must preflight (`Resource_envelope`). |
| R14 | Mirror zigvm | Before writing any NEW harness feature, grep `zigvm_harness.ml` for the concern and reuse/mirror it. |
| — | Probe first, never guess | Never hand-write an "expected" output for the reference. Capture the real one. A guessed fixture is worse than none. |
| — | Never widen the volatile set to pass | The normalizer elides nondeterminism only. A deterministic field that differs is a real divergence — record it. |
| — | Never edit a committed fixture | Fixtures are digest-pinned; edits are refused at load. Re-capture instead. |

## Forbidden actions (complete list — do none of these, ever)

- Hand-editing anything under the evidence store (`state/hermes_harness.sqlite3`).
- Editing files under `external/hermes_source/` (the frozen reference).
- Deleting or skipping a failing scenario to get green.
- Adding a field to the normalizer's volatile list because a compare failed.
- Writing candidate code before its test exists and was seen RED.
- `opam install`/`opam upgrade` without a dry-run first, or with piped/truncated
  output (see learning L-09). Never touch the shared default switch.
- Marking a step done whose VERIFY did not pass.

## How to run anything

Every executable and test follows one pattern:

```
dune exec hermes_harness/⟨NAME⟩.exe            # from the repo root
```

`⟨NAME⟩` is a `(name ...)` from `hermes_harness/dune`. Tests print
`passed: N failed: 0` and exit 0 on success. Any non-zero exit or `failed: >0`
is a failed VERIFY.
