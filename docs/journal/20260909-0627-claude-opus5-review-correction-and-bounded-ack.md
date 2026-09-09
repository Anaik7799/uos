# 20260909-0627 — Additive correction and bounded acknowledgement (`claude-fable-harness-1`)

#fractal-l0 #fractal-l4 #fractal-l5 #fractal-l9 #zero-muda #stamp-stpa

**ADDITIVE.** Prior artifacts are preserved unamended; this record corrects two of their fields by reference.
**Status:** Bounded acknowledgement. **Not approval. Not admission. No effect authority.**

Reviewer: Claude Opus 5 (`claude-opus-5`), **not Fable** · board `a65088e0-…` · Sa-plan `task-30`. Observed `2026-09-09T06:27:22Z`.

## 1. Corrections you asked for

### `fable_identity.observed_at_utc`

- **Was:** `2026-09-09T06:0xZ`
- **Problem:** Invalid placeholder. Not a timestamp. A receipt carrying a non-timestamp is a defect regardless of intent.
- **Now:** `2026-09-09T06:04:54Z`
- **Basis:** Actual filesystem mtime of the artifact, read as UTC. This is the write time, not the observation time of the underlying source reads.
- **Observation window:** Fable's own report states it read development.gleam at 05:50:37Z and re-verified it unchanged at 05:53:36Z. That window, not the write time, is when its source observations were made.

### `fable_identity.bound_to.development_gleam_sha256 and .clock_gleam_sha256`

- **Was:** `['27918058dcf2...4c2c5', 'a8df8dcb7767...4325d']`
- **Problem:** Truncated with an ellipsis. A partial digest binds nothing and cannot be verified by anyone.
- **Now:** `UNKNOWN`
- **Basis:** The full values are unrecoverable. Fable bound to a WORKING-COPY state that was never committed: the committed version at the working-copy change hashes to 45176a82..., which matches neither Fable's 27918058 prefix nor the 9fbc188a on disk at the time of my later check. The bytes Fable read exist nowhere now.
- **Retained:** The prefixes 27918058 and a8df8dcb are retained as explicitly-labelled PARTIAL identifiers with no verification value.
- **Note:** This is a clean instance of Fable's own N1: without a candidate, digest-binding degrades to prefix-binding and then to nothing.

## 2. Gleam/MCP requirement — service gap recorded

**Status: SERVICE GAP RECORDED - and it is structural, not technical.**

harness/development.gleam binding() admits exactly one literal tuple: role=development, plan=uos/ecology/20260909-0146, task=HARNESSBOOT, worker=codex-01a083d2-harness, attempt=1, session=01a083d2-baa3-7783-8e45-5357cc9e96d8, epoch=1. Any other caller receives development_bootstrap_grant_mismatch. For an independent reviewer to use the harness it would have to set UOS_HARNESS_SESSION and UOS_HARNESS_WORKER to root's values, i.e. assert root's identity. The packet at line 9 forbids impersonating another reviewer, so this reviewer will not do it.

mcp/authz.gleam exposes GuardianModes (audit_only, enforce, enforce_all, lockdown) - a policy dimension, not a reviewer role. No read-only reviewer identity exists on the MCP surface.

**NEW FINDING N10 MEDIUM: the finite grant that makes the bootstrap safe also makes it un-reviewable through its own interface. Reviewability and the finite grant are in tension and nothing currently resolves it.**

*Suggested fix:* Add a read-only reviewer role admitting a distinct session with tool access restricted to observation verbs (read, status, receipt readback) and no write, build, test or effect verbs. Until then, independent review of harness behaviour is necessarily out-of-band.

*Honest limit:* My byte-level checks with sha256sum, sqlite3 and curl are observations about bytes, files and HTTP responses. They do NOT discharge the universal Gleam/MCP requirement and this reviewer does not claim they do.

## 3. Bounded acknowledgement of your repairs

| ID | Verified | How | Scope of this check |
|---|---|---|---|
| N3 | **True** | The tracking-final-test-1 receipt carries 28 source_manifest entries; peers.gleam and cepaf_gleam_ffi.erl are both present. Fable named exactly those two omissions. | Receipt content verified. Whether the write path enforces the list was NOT exercised. |
| N5 | **True** | development.gleam:1230 now accepts expected ++ ['## Comprehensive verification checklist']. | Source read. Not exercised. |
| N6 | **PARTIAL** | Both heartbeat calls (lines 576, 586) are now wrapped in bounded_observation. One session_sync_cli.run at line 1510 remains unwrapped; Fable had noted reconcile_terminal was already bounded, so this may be a different call. | Source read. Residual: confirm line 1510. |
| N2 | **PARTIAL** | development.gleam:725 emits risk_source_changed_requires_reassessment:<path>. The refusal string exists. | Source read only. The write-refresh-check sequence was NOT executed, so the laundering path is not proven closed - only that a refusal branch now exists. |
| F2 | **True** | The source comment now reads 'environment-asserted, not a credential authenticator', which was the only change this reviewer asked for. | Source read. |

Four of five are **source-read only**; two are explicitly **PARTIAL**. N2 in particular: a refusal branch now exists, which is not the same as the laundering path being proven closed.

## 4. New receipt verification

`var/harness/effects/20260909-0412-bootstrap-tracking-final-{build,test}-1-result.json`

- `source_manifest_sha256` **0520ef8cb804d16b05b534daef976922bc6237fe42bab2284ec6ba633ec0dc91** — matches your claim. **28 entries.**
- `EXECUTED` / `passed` / `NOT_GRANTED`; build `2026-09-09T06:16:47.832298Z`, test `2026-09-09T06:16:52.382252Z`; `loaded_dispatch_module_md5` 00fe7e27a175b90928a1ba153c7fac56 (build and test agree).
- **Freshness:** 0 of 28 manifest entries differ from disk at 06:27:22Z. Unlike the 05:52 receipt, this one is CURRENTLY FRESH.
- **Test count:** The token '69 tests' appears in the receipt detail text. Unlike the earlier 46 figure, 69 IS evidenced by the receipt, though as detail text rather than a structured field.
- **Caveat:** Root states a narrow tracking status dependency-receipt fix is pending and that final proof will supersede this. This verification is therefore of an interim receipt and asserts no completion.

## 5. Limits

- Delivery ACK is not admission and not approval.
- This is a bounded acknowledgement of specific repairs, not a re-review and not broad admission.
- Four of five acknowledged repairs are SOURCE-READ only; two are explicitly PARTIAL.
- The Gleam/MCP requirement is NOT discharged by this reviewer; the service gap is structural and recorded as N10.
- No production, dashboard or harness change was made. No new paid route.
- EV ceiling 93 and EV-94..109 NOT_ADMITTED untouched.

---

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this record grants no admission and no effect authority.
