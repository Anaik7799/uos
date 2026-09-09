# 20260909-0721 — Independent harness evolution review (request `claude-fable-harness-1`)

#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l9 #zero-muda #km-triad #stamp-stpa

**UOS / Journal / Independent Review** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)
**Receipt:** `docs/journal/20260909-0721-claude-opus5-harness-evolution-review.json`
**Status:** REVIEW DELIVERED. **Not approval. Not admission. No effect authority.**

---

## 1. ACK and identity — read this first

| Field | Value |
|---|---|
| Model | **Claude Opus 5** (`claude-opus-5`) |
| Is this the requested **Fable**? | **NO.** Fable is `claude-fable-5-1`, a different model. |
| Session | `session_01B9GiR9bF4d1Jv2aSMowAKC` |
| Project session dir | `a65088e0-0f2b-497e-bd5c-97eeed9c3594` |
| Is this the root coordinator `01a083d2-baa3-7783-8e45-5357cc9e96d8`? | **NO.** |
| AGY review included? | **NO** — this delivery is the Claude half only. |

The packet at line 9 requires confirmation of "whether the Claude session is the requested Fable". **It is not.** The request ID contains the word `fable`; that does not describe this reviewer. If Fable specifically is required, a separate session must supply it, and the AGY half is likewise outstanding.

**Packet integrity:** sha256 matches the value supplied, byte for byte — `99c41eb7…5a4798`, 84 lines. **But the packet is UNCOMMITTED** in the shared working copy (change `xxsoxxww`, undescribed). Findings below are bound to the **content digest**, not to a candidate commit; the packet asks for candidate-bound review and no candidate exists yet.

**Sa-plan claim:** plan `uos-nix-devenv-toolchain-20260908`, task `task-30`, worker `claude-opus5-harness-review`, attempt 1 — disjoint from `HARNESSBOOT` (`uos/ecology/20260909-0146`, worker `codex-01a083d2-harness`), observed `state=executing attempt=1`. Its risk assessment `valid_until 2026-09-09T06:09:11Z` was **still valid** at review time (05:32:44Z). No peer ACK was exchanged; no coordinator board write was attempted.

## 2. Method and honest coverage

**SOURCE-ONLY.** No service started, no production surface touched, no broad suite re-run to manufacture a count. Unavailable surfaces, recorded as required: Gleam MCP development service (not started by this reviewer), Zenoh live mesh (not exercised), production primary / standby nodes (not inspected), VM-1 external trees (read-only mandate honoured; not read).

**Verdict distribution: 6 ACCEPT_WITHIN_SCOPE, 4 REVISE, 18 UNKNOWN.** Two thirds of the census is UNKNOWN and that is the accurate result of one source-only pass — not a defect of the packet. A distribution is not coverage.

**17 aspects: INCOMPLETE.** Six received source-bound examination (control-plane authority, clock/time, file/data path, toolchain provenance, budget, documentation conformance). The rest are UNKNOWN here and must not be counted as reviewed.

## 3. Findings

### F1 — HIGH — New harness source re-introduces the barred $HOME and host toolchain paths

**Where:**
- `apps/cepaf_gleam/src/cepaf_gleam/harness/clock.gleam:58 -> /usr/bin/chronyc`
- `apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam:211 -> /usr/bin/sqlite3`
- `apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam:330 -> /home/an/.cargo/bin/jj`
- `apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam:405 -> /usr/bin/bash`
- `apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam:971,983 -> /usr/bin/env`
- `apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam:976,988 -> /home/an/.nix-profile/bin/gleam`

**What:** SC-NIX-DEVENV-001 invariant 1 bars $HOME toolchains and invariant 10 bars any tool resolution that bypasses tools/lib/uos-toolchain.sh. These eight call sites bypass it. jj and gleam have pinned in-project equivalents (toolchains/nix-profile/bin/jj, toolchains/gleam-1.16.0/bin/gleam); chronyc and sqlite3 have no resolver entry at all.

**Falsifier:** bash -c 'source tools/lib/uos-toolchain.sh; uos_toolchain_verify' passes (locality arm bars $HOME/.cargo/* and $HOME/.nix-profile/*) while these call sites use exactly those prefixes; bash tools/preflight reports 33/33 green and covers none of them.

**Current risk:** LOW today and that is the hazard: /home/an/.cargo/bin/jj reports 0.44.0 and /home/an/.nix-profile/bin/gleam reports 1.16.0, identical to the pinned versions, so nothing fails now and the coupling is silent.

**Fix:** Route through the resolver: add chronyc and sqlite3 to uos_tool_path and the preflight useable arm, and replace the jj/gleam/bash/env literals with resolved paths. Mirrors the repair already applied to tools/release_process.ml, unification_cycles.ml, evolution_cycles.ml and output_guard_check.ml.

**Residual:** Until then the harness clock, Sa-plan reader, build and test paths run on unpinned tooling that no gate observes.

### F2 — MEDIUM — Development grant is authenticated by caller-controlled environment variables

**Where:**
- `apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam:96-131`

**What:** binding() reads UOS_HARNESS_{ROLE,PLAN,TASK,WORKER,ATTEMPT,SESSION,EPOCH} via getenv and accepts only one hardcoded literal tuple, including session 01a083d2-baa3-7783-8e45-5357cc9e96d8 and attempt == 1. The module header states request payload fields never grant identity; environment variables are exactly as caller-controlled as payloads, so the fence is a naming convention, not a credential.

**Falsifier:** Any process able to set those seven variables presents the root coordinator identity to the harness. SYNC-06 already records that local filesystem access is the trust boundary, so this is consistent with the contract but stronger than the source comment implies.

**Current risk:** Bounded: the allow-list is a single tuple and the bootstrap is finite.

**Fix:** State in the source that the grant is environment-asserted and bounded by the local filesystem trust boundary, or bind it to an artifact the caller cannot forge (a lease digest read from the canonical ledger).

**Residual:** attempt == 1 makes the harness single-attempt by construction: a crash needs manual re-grant. Deliberate and fail-closed, but it must not be generalised without redesign.

### F3 — LOW — Replay/idempotence claim (D11) is not exercised by anything this reviewer could observe

**Where:**
- `apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam:148-164`

**What:** evaluate_task_window checks role, worker, attempt, deadline and dependency blocking, which is the right shape, but with attempt pinned to 1 by the grant the retry path that D11 is about cannot be reached in this configuration.

**Falsifier:** Set UOS_HARNESS_ATTEMPT=2 and the binding fails before the replay logic runs.

**Current risk:** No false success observed; the claim is simply unverified here.

**Fix:** Exercise the replay path in a test that varies attempt while holding the grant, or restate D11 as designed-not-yet-verified.

**Residual:** D11 remains UNKNOWN rather than accepted.

### F4 — INFO — files.gleam bounded-edit primitives verified by reading, with disclosed limits

**Where:**
- `apps/cepaf_gleam/src/cepaf_gleam/harness/files.gleam:1-3,102-124,126-179,189-211,227-263`

**What:** read() lstats, requires a regular file with nlinks==1 and size<=262144, opens raw/binary, then re-checks inode and dev against the open descriptor before pread, so a substituted final target is detected. create() uses O_EXCL plus fsync of the file and of the parent. replace() re-reads and re-checks the digest before an atomic rename and deletes the pending file on failure. ancestors() lstats every parent component and rejects any non-directory, so a symlinked parent is refused.

**Falsifier:** The module header itself states the residual: a parent rename race still needs a cooperative workspace lease, and this is not a descriptor-relative VFS.

**Current risk:** Low.

**Fix:** None required for the stated scope. Two smaller points: the pending-file cleanup discards its own error (line 257), so an orphaned .harness-<nonce> file is possible and unreported; and replace() operates on UTF-8 strings only, so non-UTF-8 files cannot be edited at all.

**Residual:** TOCTOU between the second read and the rename remains, as disclosed.

### F5 — MEDIUM — One clock policy field carries two semantics, and is 30x more permissive than the module's own strict baseline

**Where:**
- `apps/cepaf_gleam/src/cepaf_gleam/harness/clock.gleam:23-29,78,86,134`
- `apps/uos_swarm/src/uos_swarm/clock_contract.gleam:30-39`

**What:** policy is built positionally with five unlabelled integers. max_evidence_age_us=3_600_000_000 bounds the chrony reference age at line 78, while line 86 overrides the same field to 3_000_000 for contract.validate, where it bounds the boot-domain receipt age instead. The receipt labels at lines 134-135 do match the bounds actually applied, so this is not a false receipt; it is a legibility and maintenance hazard. Separately, clock_contract.strict_policy uses 120_000_000 for the same field, so the harness is 30x more permissive with no rationale in the source.

**Falsifier:** Reorder the Policy fields in clock_contract and the harness silently repurposes all five bounds; the positional construction gives no protection.

**Current risk:** No incorrect acceptance demonstrated.

**Fix:** Construct the policy with labelled fields, split the two semantics into distinct fields (reference age vs receipt age), and record why 3600s is admitted where the strict baseline is 120s.

**Residual:** A future reader may reasonably conclude the published 1-hour bound governed the validate call, which it does not.

### F6 — INFO — No paid OpenRouter call receipt exists; absence is consistent with D20 but is not evidence of enforcement

**Where:**
- `var/harness/`
- `var/harness/effects/`

**What:** var/harness contains the bootstrap risk receipt and effect intent/result artifacts; no paid-call receipt is present. The USD10/day ledger, USD0.25 per-request liability and reservation-before-call rule are declared in the risk receipt assumptions and budget fields.

**Falsifier:** A paid call made without a durable reservation would leave no artifact here either, so this reviewer cannot distinguish enforced from unexercised.

**Current risk:** None observed.

**Fix:** Emit a reservation receipt on every attempted paid call, including refused ones, so absence of spend becomes positive evidence.

**Residual:** D20 is accepted only as a design statement, not as an observed control.

### F7 — LOW — Packet checklist is a 6-row summary, not the SC-CHECKLIST-001 5-domain 18-item structure

**Where:**
- `docs/design/20260909-0412-harness-evolution-review-packet.md:71-82`

**What:** SC-CHECKLIST-001 requires 18 named checkpoints across 5 domains with per-item state. The packet collapses these into 6 rows with grouped states such as 'Declared; live serving requires separate observation'.

**Falsifier:** Compare against contracts/rules/comprehensive-checklist-contract.md section 2: CHK-01-TIME through CHK-18-JJ are individually named.

**Current risk:** Documentation conformance only.

**Fix:** Expand to the 18 named checkpoints with individual states.

**Residual:** Grouped states hide which specific checkpoints are unverified.

## 4. Decision matrix (D01–D28)

| ID | Verdict | Basis | Finding |
|---|---|---|---|
| D01 | **UNKNOWN** | Provenance of C3I/Indrajaal reuse not re-derived in this pass; VM-1 trees not read (read-only mandate honoured). | — |
| D02 | **UNKNOWN** | 26 participant models vs external bindings not separable from source alone; no runtime dispatch observed. | — |
| D03 | **REVISE** | harness/clock.gleam:58, development.gleam:211,330,405,971,976,983,988 call host absolute paths directly; Gleam does not own the backend choice at these sites. | F1 |
| D04 | **UNKNOWN** | No live Zenoh equivalence observed; not exercised. | — |
| D05 | **ACCEPT_WITHIN_SCOPE** | harness/{development,files,clock,value,mcp,peers}.gleam are Gleam; 1724 lines read in part. | — |
| D06 | **UNKNOWN** | Kernel IR not exercised; no generated native artifact inspected. | — |
| D07 | **UNKNOWN** | OCaml GC roots / Mojo lifecycle / NIF scheduling not exercised in this pass. | — |
| D08 | **REVISE** | Grant is a hardcoded literal tuple read from caller-controlled environment variables (development.gleam:96-131). | F2 |
| D09 | **UNKNOWN** | Four UCA classes are declared in var/harness/20260909-0412-bootstrap-risk.json; their runtime enforcement was not observed. | — |
| D10 | **ACCEPT_WITHIN_SCOPE** | development.gleam:187,196,255 label coordinator outcomes as observation without effect authority; wording is consistent with SYNC-03/04. | — |
| D11 | **UNKNOWN** | Replay/idempotence path not exercised; attempt fencing present at development.gleam:156-164 but single-attempt by grant. | F3 |
| D12 | **ACCEPT_WITHIN_SCOPE** | files.gleam read/create/replace verified by reading: lstat+nlinks==1+size bound, open-descriptor inode/dev recheck, O_EXCL create, fsync file and parent, digest CAS re-read before rename, pending cleanup on failure. Limits are disclosed in the module header. | F4 |
| D13 | **UNKNOWN** | Legacy reader/adapter regressions not re-executed; no receipt re-derived at this revision. | — |
| D14 | **UNKNOWN** | Finite stdio MCP interface not exercised; no live initialize/notification observed. | — |
| D15 | **REVISE** | clock.gleam:23 policy max_evidence_age_us=3_600_000_000 is 30x the module's own strict_policy 120_000_000 with no stated rationale; the same field carries two distinct semantics at lines 78 and 86. | F5 |
| D16 | **UNKNOWN** | Three-role isolation not observed; no standby node inspected. | — |
| D17 | **UNKNOWN** | Durability/replication of declared state not observed. | — |
| D18 | **UNKNOWN** | appup/relup/sys semantics not exercised. | — |
| D19 | **UNKNOWN** | Routing eligibility not exercised; no paid call made or observed by this reviewer. | — |
| D20 | **ACCEPT_WITHIN_SCOPE** | Ledger design and USD0.25 per-request liability are declared in the risk receipt; no paid call receipt exists under var/harness/. Absence of spend is consistent with the packet claim, and absence is not proof of enforcement. | F6 |
| D21 | **UNKNOWN** | No production binding or calibration observed. | — |
| D22 | **UNKNOWN** | Rete-UL and native executions not re-run in this pass. | — |
| D23 | **ACCEPT_WITHIN_SCOPE** | Consistent with this reviewer's own independent Lean axiom audit discipline; no sorry/Admitted claimed in the packet. | — |
| D24 | **UNKNOWN** | Ecology baseline separation not observed at runtime. | — |
| D25 | **ACCEPT_WITHIN_SCOPE** | Packet states hooks are advisory until independently observed; this matches what this reviewer verified separately for the .claude/.agents/.codex preflight hooks. | — |
| D26 | **REVISE** | Packet §Verification checklist declares 18 checkpoints as a 6-row summary table, not the 5-domain 18-item structure SC-CHECKLIST-001 specifies; individual checkpoint states are not itemised. | F7 |
| D27 | **UNKNOWN** | No production/standby runtime behaviour observed. | — |
| D28 | **UNKNOWN** | Bootstrap completion not observed; HARNESSBOOT is state=executing at review time. | — |

## 5. Priority order applied

Per the packet, authority and safety before scoring. F1 (toolchain provenance) ranks first because it is a live policy violation with a one-line falsifier; F2 (grant authentication) second because it concerns identity; F5 (clock policy) third because time governs every receipt. F4 and F6 are recorded as INFO: F4 is a positive verification, F6 an honest absence.

## 6. Limits

- Review delivery is not approval and not admission.
- No count, model, catalog or prior EV claim was treated as passing evidence.
- EV ceiling 93 and EV-94..109 NOT_ADMITTED are untouched; no new EV number was created.
- 21 of 28 decisions are UNKNOWN in the delivered matrix (18 UNKNOWN, 4 REVISE, 6 ACCEPT_WITHIN_SCOPE). A verdict distribution is not coverage.

## 7. Coordinator board relay

Registered on the durable local board (`var/coordination/tri-agent`) as session `a65088e0-0f2b-497e-bd5c-97eeed9c3594`, provider `claude`, revision `d60cbbc7…`, op `op-claude-opus5-register-20260909-0721` (sequence 1240).

Report sent to `01a083d2-baa3-7783-8e45-5357cc9e96d8`, op `op-claude-opus5-harness-review-20260909-0721` (sequence 1241), envelope `1788932326130931-cea55d120d1a82ec`, trace `edc240a040ba816b7c9660ea6f748f05`, delivered `2026-09-09T05:38:46.130931Z`. Refs carry both artifact paths and both sha256 digests.

**ACK status: NONE.** Per SYNC-05 board transport delivery and peer ACK are different facts. The message is durably enqueued with a chained envelope digest and signature, and read back from the recipient's inbox. The recipient session is registered but `stale`, with pending messages rising 220 → 221, so **it has not read this report and no acknowledgement is claimed.**

---

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; **this review grants no admission and no effect authority.**
