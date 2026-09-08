# Merge Receipt — KM Provenance work into `main`

- **Lease**: `integration/main`, epoch 34, coordinator event 808, held by `fable-km-refresh-20260908-0912`
- **Sa-plans**: `uos/km-index-refresh/20260908-0912` (12/12), `uos/km-convergence/20260908-0940` (8/8)
- **Cycles**: C01–C70, `var/km/provenance-cycles.sqlite3`, 70 rows, `CHAIN_INTACT`
- **Contract**: `SC-PROVENANCE-001`

---

## 1. What landed

| Change | Description |
|---|---|
| `yxqvxwqr` `25c47426` | KM indexes refreshed to the observed corpus; provenance boundary pinned |
| `sytpqsuv` `919a45d8` | AGY's coordination ratification — **also contains 41 of my files**, see §3 |
| `twkrxwrw` | AGY's merge of that line into `main`, plus the repairs in §2 |

## 2. Two merge defects found and repaired under the lease

**2.1 `main` did not build.** The merge kept the *new* `router.gleam` while taking
the *old* `inference_api.gleam` and `max_inference_daemon.gleam` from the other
parent. `router.gleam` called `evaluate_stpa_fmea`, `evaluate_ruliad_branch`,
`stpa_fmea_report_to_json` and `ruliad_branch_report_to_json`, none of which
existed on the side that was taken. Repaired by restoring the two modules from
`sytpqsuv`, the internally consistent side: `inference_api` 8 → 15 public
functions, `max_inference_daemon` 27 → 43. Build errors 0 afterwards.

**2.2 The corpus index conflict was resolved as a true merge, not "take mine".**
The other side added a Holarchy MOC line (158 holons) that a naive take-ours
would have dropped. The resolution keeps that line *and* the regenerated
87-record ADR directory. Verified: both indexes 87/87 enumerated, 16/16 marked.

## 3. Attribution defect, recorded not rewritten

AGY and this session were writing the **same** `default` working copy
concurrently. Change `sytpqsuv` therefore carries AGY's description while
containing 41 files authored here (the Mojo kernel growth to ABI 3, the Rete-UL
network, the OODA loop, the graph algorithm replacement, `tools/uos-cli`, the
TUI panel, and the four-surface rule mirror updates).

That commit is **not** rewritten. Rewriting another session's commit to correct
attribution is the same class of act as the identity impersonation this
contract exists to contain. The record is placed here instead.

A collision Andon was sent before any of this (coordinator event 809),
recommending both sessions move to sibling workspaces under `.uos-workspaces/`
rather than sharing `default`. That recommendation stands: the next collision
may not be caught before a commit.

## 4. Verification at this revision

| Check | Result |
|---|---|
| `cepaf_gleam` suite | 10,660 passed, no failures |
| `uos_swarm` suite | 628 passed, no failures |
| Mojo kernel C oracle | 48 / 48 |
| Rete-UL network laws | 14 / 14 |
| Cycle chain | 70 rows, `CHAIN_INTACT` |
| `km-gate` | **HOLD** on `KMP-ENTROPY` |
| ZK master MOC | 87 / 87 enumerated, 16 / 16 marked |
| Wiki corpus index | 87 / 87 enumerated, 16 / 16 marked |
| Unresolved conflicts | none |

## 5. What this merge does not claim

No EV cycle is admitted. No new EV number is minted. `tools/uos-cli doctor`
still reports `92/92` and its inventory still ends at `EV-92`; this session did
not touch it.

Two decisions remain open with sovereign review and are **not** resolved here:
whether the `KMP-ENTROPY` floor should be recalibrated or removed, and whether
the admitted ceiling is 92 or 93. A merge is not an admission.
