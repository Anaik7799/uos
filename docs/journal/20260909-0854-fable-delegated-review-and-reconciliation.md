# 20260909-0854 — Fable delegated review, identity and reconciliation (`claude-fable-harness-1`)

#fractal-l0 #fractal-l4 #fractal-l5 #fractal-l9 #zero-muda #km-triad #stamp-stpa

**UOS / Journal / Independent Review — ADDITIVE.** Does not amend the two frozen prior artifacts.
**Status:** DELIVERED. **Not approval. Not admission. No effect authority. Delivery ACK is not admission.**

## 1. Fable identity — preserved verbatim, as root required

| Field | Value |
|---|---|
| Self-reported model | **claude-fable-5-1 (Fable 5.1)** |
| Caveat, in its own framing | Model self-report. Fable stated plainly it cannot prove this cryptographically. Preserved verbatim per root's condition. |
| Relationship | Delegated read-only subagent inside session session_01B9GiR9bF4d1Jv2aSMowAKC, the same session that produced the Opus 5 review. Different model, same session container. |
| Independent sovereign session? | **NO** |
| Sa-plan claim / board write / peer ACK | **none, none, none** |
| Fable's own note on that | Constraints precluded claiming a task and posting to the board; Fable recorded this as an unsatisfied gap rather than papering over it. |
| Root disposition | Root observed the delegated completion and stated it satisfies requested Fable model input if reported identity is preserved; it is NOT a separate sovereign session, claim or admission vote. |
| Method | Source-only. Executed only sha256sum, wc, grep, diff, cat, ls, find, date, python3 JSON reads and jj --ignore-working-copy log/op log/file show. No network, no services, no VCS mutation. |

**Bound to:** `development.gleam` 27918058dcf2...4c2c5 · `clock.gleam` a8df8dcb7767...4325d · packet `99c41eb7…5a4798`.

**Did not read:** mcp/{server,tools,authz}.gleam; sa_plan_bridge.gleam beyond a range; session_sync.gleam beyond a range; session_sync_ffi lock acquisition; herdr.gleam / uos_herdr_ffi.erl; formal spec and atlas; test bodies beyond names; ecology_process.ml; the coordinator board.

**Did not execute:** gleam build/test; preflight; uos_toolchain_verify; risk-priority-check; any dashboard fetch. It produced no 28-row decision matrix and said so.

## 2. Findings

| ID | Severity | Title |
|---|---|---|
| N1 | **HIGH** | No candidate; the source moved under all three reviews |
| F1-verdict | **MEDIUM** | F1 holds for the reviewed revision; PARTIALLY REPAIRED since |
| F5-refutation | **CORRECTION** | Opus 5 F5 severity was WRONG; Fable refuted it and Opus 5 verified the refutation |
| H1-verdict | **HIGH** | H1 holds; exposure wider than Opus 5 stated |
| N2 | **MEDIUM** | harness_risk_refresh launders a digest-invalidated assessment back to PASS |
| N3 | **MEDIUM** | Write scope is a prefix; attestation scope is a fixed list |
| N4 | **MEDIUM** | pub const root hardcodes the canonical checkout, violating workspace isolation |
| N5 | **LOW** | journal_sections_valid conflicts with SC-CHECKLIST-001 |
| N6 | **LOW** | Inconsistent bounding of coordinator calls |
| N7 | **LOW** | Every effect pays an uncached OCaml build under a 15 s bound |
| N8 | **INFO-RESOLVED** | The old test receipt could not satisfy the validator; a new one now does |
| N9 | **INFO** | Checked and cleared |

### N1 — HIGH — No candidate; the source moved under all three reviews

**Detail:** development.gleam measured 843 lines (Opus 5 read), 1578 (Fable start), 1663 (Fable end), 1709 (Opus 5 re-measure). jj op log snapshots every 1-2 min. Every line citation in Opus 5 F1/F5 fits a revision that no longer exists on disk or at the working-copy change.

**Fix:** Worker records a candidate change before requesting review; reviewers cite change_id plus file sha256.

**Residual:** Findings are digest-bound, not candidate-bound, which is what the packet said reviews must not be.

### F1-verdict — MEDIUM — F1 holds for the reviewed revision; PARTIALLY REPAIRED since

**Detail:** jj and gleam now resolve through toolchains/. Three host paths remain, grep-verified by Opus 5: sqlite3 (development.gleam:54) and bash (:56) are now declared in adapter_scope as bootstrap_host_exceptions with all_adapters_pinned=false; chronyc (clock.gleam:77) is still host and NOT in that declared list - a third, undisclosed exception. Additionally env is resolved from toolchains but has no arm in uos_tool_path (verified: uos_tool_path env returns nothing), so the source comment claiming the table is mirrored is not literally true. tools/risk-priority-check resolves dune, ocamlc, ocamlfind and timeout via command -v from inherited PATH.

**Fix:** Declare chronyc in bootstrap_host_exceptions or pin it; add an env arm or correct the comment; pass PATH=build_path to the risk checker.

**Residual:** Two of three host exceptions are now honest; one is not.

### F5-refutation — CORRECTION — Opus 5 F5 severity was WRONG; Fable refuted it and Opus 5 verified the refutation

**Detail:** clock_contract.validate applies max_evidence_age_us to current.boot_us - evidence.reading.boot_us, the RECEIPT AGE in the boot domain (clock_contract.gleam:153-155). The harness 3_600_000_000 bounds chrony REFERENCE AGE, which strict_policy does not govern. On the quantity strict_policy governs the harness passes 3_000_000 us, 40x STRICTER not 30x looser. The 'no rationale in source' claim was also wrong: clock_guard.strict_config (clock_guard.gleam:93-104) documents it. Only the positional-construction hazard and dual field semantics survive, both already repaired.

**Fix:** Downgrade F5 from MEDIUM to LOW-repaired. Do not act on the 30x figure.

**Residual:** Opus 5 filed a finding without reading the sibling module that governed it.

### H1-verdict — HIGH — H1 holds; exposure wider than Opus 5 stated

**Detail:** demo_events is event_stream_widget.gleam:27-82 (not 27-40); the literal 'AG-UI Event Stream (Live)' is at :89 and :140; it is wired unconditionally at THREE call sites - dashboard_views.gleam:507, special_views.gleam:1312, agui_cockpit.gleam:12. Fable could not observe the live rendering (no network); Opus 5 did observe it and confirmed podman ps showed 2 containers against the page's 16/16.

**Fix:** Bind to real telemetry or label the panel Demo and drop the word Live, at all three call sites.

**Residual:** Other demo_* helpers were not enumerated.

### N2 — MEDIUM — harness_risk_refresh launders a digest-invalidated assessment back to PASS

**Detail:** It rewrites every evidence sha256 to current bytes and stamps observed_at=now while leaving S/O/Det and the UCA analysis untouched, so write -> refresh -> check yields ACTIVE_OBSERVATION_PASS with byte-identical analysis. SC-RISK-PRIORITY-001 section 4 says a changed input digest invalidates the assessment and requires a new one, not reinterpretation by a worker.

**Fix:** Refuse refresh when any digest changed, or append a superseding assessment requiring re-signed analysis; at minimum emit digest_rebound_without_reassessment=true.

**Residual:** Refresh does not touch valid_until, so that fence still expires and holds.

### N3 — MEDIUM — Write scope is a prefix; attestation scope is a fixed list

**Detail:** source_allowed admits any harness/*.gleam and test/harness_*.gleam; bootstrap_source_paths is a fixed 24-entry list. A new file under the prefix is compiled and tested, absent from source_manifest, and source_manifest_unchanged stays true. Portfolio evidence omits peers.gleam (which pushes prompts into other agents' Herdr panes) and cepaf_gleam_ffi.erl (identity-binding get_env).

**Fix:** Derive the manifest by walking the write-allowed prefixes, or restrict writes to the list; make portfolio evidence a superset of the manifest.

**Residual:** The generic disclaimer does not name these omissions.

### N4 — MEDIUM — pub const root hardcodes the canonical checkout, violating workspace isolation

**Detail:** Every read/write/build/test/sqlite/coordinator path is pinned to the canonical default checkout, which SC-WORKSPACE-ISO-001 says nobody owns and is not a work surface. ecology_capability_ffi.erl resolves its root from priv_dir specifically so nothing hardcodes a machine path; the Gleam layer above re-hardcodes it. Neither prior delivery listed this literal.

**Fix:** Bind the source root to the launcher's validated workspace, or record HARNESSBOOT as an explicit isolation exception.

**Residual:** The concurrent-edit churn in N1 is the collision class isolation exists to prevent.

### N5 — LOW — journal_sections_valid conflicts with SC-CHECKLIST-001

**Detail:** It requires the set of H2 headings to EQUAL exactly the 13 numbered sections, so any journal carrying the mandated '## Comprehensive verification checklist' fails harness_finish with completion_journal_sections_missing. Seven journals dated 2026-09-08/09 carry it.

**Fix:** Require the 13 as an ordered subsequence and whitelist the checklist H2, or mandate H3 for it.

**Residual:** None.

### N6 — LOW — Inconsistent bounding of coordinator calls

**Detail:** heartbeat calls session_sync_cli.run twice unbounded and renews the coordinator lease for 3600 s per call; reconcile_terminal wraps release in a 2000 ms bound. Whether the ffi lock acquisition can wait is UNKNOWN - Fable did not read that path.

**Fix:** Wrap both in bounded_observation; reconsider a one-hour renew from a heartbeat.

**Residual:** UNKNOWN lock path.

### N7 — LOW — Every effect pays an uncached OCaml build under a 15 s bound

**Detail:** risk_check runs tools/risk-priority-check, which dune-builds into a fresh mktemp -d with DUNE_CACHE=disabled on every call, with dune/ocamlc resolved from inherited PATH.

**Fix:** Pass PATH=build_path via pinned_env as harness_build does; cache the validator.

**Residual:** None.

### N8 — INFO-RESOLVED — The old test receipt could not satisfy the validator; a new one now does

**Detail:** Fable observed that 20260909-0412-bootstrap-test-1-result.json has 12 keys while validate_bootstrap_receipt requires six more plus a loaded module md5 a rebuild would not match. Opus 5 subsequently verified that 20260909-0412-bootstrap-authority-test-1-result.json carries 22 keys including all six, loaded_dispatch_module_md5=372888f7 (distinct from the old 725e1eb9, exactly as Fable predicted), status EXECUTED, verification passed, admission NOT_GRANTED, observed_start 05:52:49.774192Z to observed_end 05:52:53.091822Z. N8 is RESOLVED by that receipt.

**Fix:** None required.

**Residual:** STALE ALREADY: 4 of the receipt's 22 manifest entries have different bytes on disk now - development.gleam 27918058->9fbc188a, mcp.gleam 7d8d6323->31590a95, harness_authority_test.gleam 6a43ed9c->257c3793, harness_verification.gleam d5d0be0a->48e7110f. The receipt being digest-bound is why this is detectable; that is the receipt working as designed, not a defect in it.

### N9 — INFO — Checked and cleared

**Detail:** SQL concatenation is guarded by valid_identifier admitting no quote characters; sa-plan lease_until_ns is UTC-epoch ns so the comparison against utc_us*1000 is same-domain; the coordinator lease is compared in the boot domain with boot_id equality; no orphaned .harness-* pending files exist. clock.gleam's hardcoded synchronized:True is not a defect - clock_guard_ffi.erl asserts Leap =:= Normal and fails parse otherwise.

**Fix:** None.

**Residual:** None.

## 3. Reconciliation against root's latest

**Feature catalog** `governance/capability-inventory/20260909-0412-harness-feature-catalog.json`

- sha256 **verified independently**: `e631c77fff18c202bb527545844a4834b0d3f4f53200f585878f95bd60652a4d` — matches root's `e631c77f…`.
- **49 features**, stages: EXECUTED 7, IMPLEMENTED 10, PLANNED 19, MAPPED 13, VERIFIED 0.
- Zero of 49 features are VERIFIED. The catalog's own all_features_complete=false and system_admission=false agree with the Opus 5 matrix answer that not all requested features are implemented.
- Authority field is correctly framed: canonical Sa-plan SQLite, catalog is a read-only projection, not execution authority.
- Per-entry Sa-plan linkage is ABSENT: 0 of 49 entries carry task_id, job_id, workflow_id or plan_id; only a top-level plan_id uos/harness-features/20260909 exists, and only 1 of 49 evidence blocks references a Sa-plan identifier. This is the join-linkage gap root said it retained; confirmed independently.
- Dashboard coverage corroborates H2: 48 of 49 entries record NOT_VERIFIED; exactly one names a real URL (the 4110 ecology page).
- All 49 entries carry both evidence and a blocker, which is good discipline.

**MCP test receipt** `var/harness/effects/20260909-0412-bootstrap-authority-test-1-result.json` — 22 keys, status `EXECUTED`, verification `passed`, admission `NOT_GRANTED`, `2026-09-09T05:52:49.774192Z` → `2026-09-09T05:52:53.091822Z`.

- Consistent with root's PASS 05:52:52 claim. The receipt evidences verification=passed at a digest-bound source set; it does not carry a structured test count, so the figure 46 is not evidenced by this receipt itself.
- **Already stale:** 4 of 22 manifest entries differ from disk now: development.gleam, mcp.gleam, harness_authority_test.gleam, harness_verification.gleam. The receipt being digest-bound is why this is detectable — that is the receipt working as designed.

**Sa-plan schema gap (retained):** sa_plan_job and sa_plan_workflow still have no plan_id/task_id column; FKs to sa_plan_task exist only from sa_plan_dependency, sa_plan_selection_evidence and sa_plan_bridge_mapping. 58 of 129 jobs and 19 of 32 workflows carry no reference at all.

## 4. Limits

- Delivery ACK is not admission and not approval.
- Fable is a delegated model instance, not a sovereign session; it cast no admission vote.
- No production or dashboard change was made by either reviewer.
- EV ceiling 93 and EV-94..109 NOT_ADMITTED untouched; no new EV number created.
- Source-only counts are not completion; none is asserted here.

---

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this artifact grants no admission and no effect authority.
