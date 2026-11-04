# 20261105-1025 — Stale-shadow rule mapping and removal receipt

#fractal-l0 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

Authority: `SC-MIRROR-PROJ-001` §3 (stale-shadow law) governed pass. Report-only record; grants no admission.
Observed host clock: 2026-11-05T10:35:25Z.

## Finding

Two rule files existed in all four vendor `rules/` mirrors as **byte-identical duplicates** of a
canonical contract that was *also* projected into the same directory, so every Claude session loaded
each contract's bytes twice.

| Shadow name (removed from mirrors) | Canonical contract (retained, projected) | Bytes | md5 |
|---|---|---|---|
| `workspace-isolation-contract.md` | `contracts/rules/20260908-1030-workspace-isolation-contract.md` | 6,303 | `925f166c581e28c379bf4db3ebe477d9` |
| `provenance-integrity-contract.md` | `contracts/rules/20260908-0912-provenance-integrity-contract.md` | 9,771 | `62bf5af417b2de432ab42d3c3d004a46` |

Neither short name exists in `contracts/rules/`: they were never canonical contracts, only shadows.
All 8 mirror copies (2 names x 4 surfaces) were verified byte-identical to their canonical before removal.

## Action

1. Shadow bytes preserved here as `*.shadow-preserved` (nothing deleted; `SC-MIRROR-PROJ-001` §3).
2. Shadow removed from `.claude/rules`, `.codex/rules`, `.gemini/rules`, `.agents/rules` **equally**,
   preserving §4 four-mirror name-set isomorphism.
3. Canonical timestamped projection retained in all four mirrors, so §2 projection completeness holds.

Removal rather than the §3 symlink option was chosen deliberately: a symlink left in a loaded rules
directory is still read by the harness, so it would dedupe the disk but not the context, which was the
whole defect. The §3 requirements actually binding — never deleted, never silently diverged, mapping
recorded — are satisfied by this receipt.

## Not touched (divergent, not duplicates)

These short names differ in content from their timestamped counterparts and are **summaries, not
duplicates**. They are recorded here and left in place pending a reading pass:

| Short name | Bytes | Timestamped counterpart |
|---|---|---|
| `denotational-intent-algebraic-atlas-contract.md` | 1,789 | `20260908-1110-denotational-intent-algebraic-atlas-contract.md` |
| `indrajaal-constitution-migration.md` | 1,476 | `20260908-1055-indrajaal-constitution-migration.md` |

## Limits

EV ceiling 93; `EV-94..109` `NOT_ADMITTED`; no new EV number minted. No canonical contract text was
edited. This receipt is documentary; it establishes no runtime enforcement and no admission.
