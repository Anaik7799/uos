# EV98 campaign direct native launcher repair

Observed: 2026-09-09T11:28:45Z. Immutable source: `b8da78ab9e88c5d8f41f4dc36d26f3aad3e1bc53`.

Tags: #fractal-l0 #fractal-l4 #zk-adr #zero-muda

Navigation: [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Verification](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1145-ev-campaign-direct-verification.json).

## 1. Scope & Trigger

The independent reviewer held the producer after discovering that pinned OTP `bin/erl` is a Bash wrapper. Parent PROGRAM authorized this bounded native launcher correction under Sa-plan `uos/ev-evidence-campaign/20260909`, task `PRODUCER`. No formal solver, deployment, admission or live mesh effect is part of this change.

## 2. Pre-State Assessment

The original source `01c5a095...` and its passing campaign used a wrapper-dependent execution path. Their source, receipts and journal remain unchanged as historical evidence; their wording does not establish compliance with the no-shell requirement. OCaml automation now invokes the native `ocamlrun` executable with the bytecode `ocaml` input, avoiding its shell header.

## 3. Execution Detail

The recipe now invokes the ELF ERTS 17.0.5 `erlexec` directly. Explicit ROOTDIR, BINDIR, EMU, PROGNAME, ERL_ROOTDIR, ESCRIPT_EMULATOR and ERLC_EMULATOR variables select the inspected OTP 29.0.5 tree; ERLC_USE_SERVER=false excludes an inherited compiler daemon. A private `erl` symlink points to that exact executable and is rechecked. Every recipe executable must have ELF magic. Trace-observed tput, erl_child_setup and inet_gethost bytes are also pinned.

An initial ptrace attempt was refused by the sandbox. Approval for the retry arrived after the original task lease expired. That completed private trace is retained as a non-authority observation; substantive work stopped until recovery. Native preflight preserved the expired attempt-1 HOLD. Parent-authorized canonical claim returned attempt 2, and active checks passed at 11:24:27Z and 11:28:09Z. The new candidate was then extracted as eight exact immutable Dune source files into `/tmp/uos-campaign-direct-source-b8da78ab`, built privately, and the full campaign was traced again under attempt 2. The latest active observation binds 12 files and assessment `6a6b408008adc311e399ce6540c7974fb20704d2eb1223f38650123f7b4b35fb`.

## 4. Root Cause Analysis

A pinned pathname and argv-only process API do not determine the interpreter used by that file. The previous implementation treated the `erl` frontend as native without inspecting its bytes. Compiler frontends also choose their emulator separately. ELF checking, exact nested emulator selectors and observed exec tracing cover the tested path.

## 5. Fix Taxonomy

This is a launcher selection and executable binding correction. The generated 42-case runner, designated mutant assertions, fixed policy and acceptance hashes, candidate reader, coverage rules and partial evidence authority remain unchanged. Recipe identity changes because launcher environment and helper hashes are part of its descriptor.

## 6. Patterns & Anti-Patterns Discovered

Inspect frontend bytes and nested launchers before making native execution claims. Keep delayed tool approval separate from task lease validity. Preserve a failed observation and perform a fresh authorized run after recovery. A process trace can confirm the exercised path but cannot prove all future executions or a complete dynamic-library release closure.

## 7. Verification Matrix

| Check | Actual outcome | Boundary |
|---|---|---|
| Old-recipe ELF guard | Refuses `recipe executable uses a wrapper: erl` | Native test stops before a wrapper launches |
| Immutable eight-file build | PASS | Realized local compiler and libraries |
| Producer unit/process suite | 20 PASS | Includes two launcher controls |
| Closed CLI suite | 7 PASS | Includes counterfeit reader refusal and artifact rehash |
| Component runner | 42 PASS | Exact fixed completed-call denominator |
| Compiled negative controls | 3 designated assertion failures | Each compiles successfully first |
| Receipt consistency regressions | 67 PASS | Synthetic fixtures, no admission evidence |
| Post-recovery exec trace | All existing executed paths ELF; no shell exec observed | Finite run only |
| Independent final review | PENDING | PRODUCER remains executing |

<details>
<summary>18-checkpoint verification structure</summary>

| Domain | Checkpoint | Status |
|---|---|---|
| Metadata and navigation | Timestamp prefix and observed clock | PASS |
| Metadata and navigation | Canonical Tailscale navigation | PASS |
| Metadata and navigation | Immutable source and evidence references | PASS |
| Purity and storage | Native OCaml and Gleam implementation | PASS |
| Purity and storage | No package download or external ingestion | PASS |
| Purity and storage | Private fixtures; no live DB or runtime mutation | PASS |
| Tests and mathematical gates | Behavioral red observation preserved | PASS |
| Tests and mathematical gates | Exact positive execution denominator | PASS |
| Tests and mathematical gates | Three real compiled mutation controls | PASS |
| Tests and mathematical gates | Formal mathematical key | UNAVAILABLE |
| Control and observability | Bounded subprocess and process-group cleanup | PASS |
| Control and observability | Source, dependency, tool and output digests | PASS |
| Control and observability | Full live multi-host behavior | NOT ESTABLISHED |
| Governance and JJ | Canonical task and active attempt | PASS |
| Governance and JJ | Owned sibling and frozen candidate | PASS |
| Governance and JJ | Independent final review | PENDING |
| Provenance | EV93 ceiling retained | PASS |
| Provenance | New sovereign admission | NOT GRANTED |

</details>

## 8. Files Modified

`tools/ev_receipts/ev98_recipe.ml` binds the native launcher environment and observed helpers; `ev_campaign.ml` selects and checks direct native execution; `campaign_test.ml` adds ELF and nested launcher controls. Timestamped risk assessments, receipts, trace, exact outputs, mutation source copies and this journal record the repair. The receipt test's synthetic fixture was moved to private `/tmp` storage; no generated compiler artifact or fixture enters the candidate.

## 9. Architectural Observations

The component producer still provides a local executable observation with fixed inputs and a bounded child protocol. Native launch closure is an observed property of this campaign path. The separate health-order formal work has not been integrated, so the report retains `Formal_unavailable` and `Sovereign_pending`.

## 10. Remaining Gaps

Full live multi-host behavior, invocation/producer authentication, applicable formal evidence, sovereign effect authority, hostile same-UID race protection and a reproducible dynamic-library release closure remain absent. The report grants no admission or replay-sensitive effect. Compiler binaries stay in private `/tmp`; durable exact text evidence is copied by digest.

## 11. Metrics Summary

The new recipe digest is `412ab8bc2e203603f8fe8a5f57b8bf1359b59c82dce5fd37b523a64502cea6d8`. The final report binds 444 artifacts and 37 bounded invocations. Fresh checks comprise 42 component cases, 3 compiled mutation controls, 20 unit/process checks, 7 CLI checks and 67 synthetic consistency regressions. Post-recovery trace SHA256 is `63257c640fd1a0ffebae07f099757a825ae59a929cd9cafba64e8a8725ae53cb`.

## 12. STAMP & Constitutional Alignment

Missing native path evidence cannot receive native execution credit; wrong launcher selection is refused; late lease evidence triggers HOLD and recovery; inherited compiler server reuse is disabled. These address omitted, incorrect, mistimed and overlong unsafe controls within this component scope. Raw task FMEA remains 5/3/4 (RPN 60), priority 2500. Sa-plan remains task authority and the parent owns workspace coordination; no root identity is impersonated and no sovereign admission is written.

## 13. Conclusion

Candidate `b8da78ab...` has fresh direct native execution observations and preserved failure provenance. PRODUCER remains executing at attempt 2 for independent review. EV98 remains not admitted.

Previous: [Historical producer journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0603-ev-campaign-producer-journal.md) · Next: [Verification record](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1145-ev-campaign-direct-verification.json).

UOS evidence footer: component observations only · authority NONE · EV93 admitted ceiling.
