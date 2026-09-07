# 20260907-1756- Journal: Fractal Checklist for Production-Grade Agentic Infrastructure Mapped to UOS Code with Third-Party Oracles

`#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5` `#fractal-l6` `#fractal-l7` `#fractal-l8` `#fractal-l9` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-production-agent-infrastructure-fractal-checklist-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-production-agent-infrastructure-fractal-checklist-journal.md)  
**Cockpit**: [http://nas-1.tail55d152.ts.net:4100/](http://nas-1.tail55d152.ts.net:4100/) · **Planning**: [http://nas-1.tail55d152.ts.net:4100/planning](http://nas-1.tail55d152.ts.net:4100/planning) · **Wiki**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · **ZK**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Deliverable**: [Fractal checklist and oracle map](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-1756-production-agent-infrastructure-fractal-checklist-and-oracle-map.md) · [Oracle registry](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20260907-1756-agentic-infra-third-party-oracle-registry.json)  
**Clock receipt**: host `2026-09-07T17:25:56Z`, chrony stratum 3, leap Normal, offset 0.0003 s. **Revision**: jj working copy `umvyzluq 20d033ec`. **Sa-plan**: plan `uos/agentic-infra-checklist/20260907-1722`, task `t1-fractal-checklist`, worker `claude-fable-5.1-session-019m7SjJ`, attempt 1.

## 1. Scope & Trigger

Operator directive, delivered as the tail of a pasted reference document ("Production-Grade Infrastructure Architecture for Agentic AI Systems"): **"make a full fractal checklist, mapping to current system code, get 3rd party code as oracles."** Scope: documentation and evidence only. No runtime, gate or source code was changed. The 22 taxonomy services and 6 readiness criteria of the reference document were mapped to UOS code at the observed revision, graded from code, and paired with pinned third-party reference implementations.

## 2. Pre-State Assessment

Three UOS-ified versions of the reference document already existed in the working copy (`docs/design/20260907-1909-…`, `-1911-…`, `-1912-…`), each asserting an `18/18 PASS` verification matrix from policy. None mapped a single service row to a `path:line`, none named an oracle, and none distinguished simulation stubs from running code. The sa-plan status plan was `infranodus-fractal-closure-20260804-0936` with zero tasks. Another writer was active in the tree during this session (edits to the risk SOP and `AGENTS.md` appeared on disk); this task added new files only and touched none of theirs.

## 3. Execution Detail

1. Created sa-plan plan `uos/agentic-infra-checklist/20260907-1722` and task `t1-fractal-checklist` (hierarchical names are mandatory; the first attempt with flat names was rejected by the CLI).
2. Wrote an `SC-RISK-PRIORITY-001` record (C3 T2 F4 Dep2 I4, score 192, class P2) and ran `tools/risk-priority-check --preflight`. Two holds were raised and repaired: `CLAUDE.md` is a symlink to `AGENTS.md` (symlink evidence is rejected), and evidence observed after the assessment time is rejected. The third run returned `PREFLIGHT_PASS`; the task was then claimed with a 4-hour lease (attempt 1).
3. Shallow-cloned 24 upstream repositories into `/home/an/NAS-setup/oracles` (outside UOS, 1,522 MB, all `cloned`) and recorded URL, HEAD, branch, commit date, license digest, file count and size in `governance/sources/20260907-1756-agentic-infra-third-party-oracle-registry.json` under the `uos-source-ingestion/v1` carrier, status `NOT_INGESTED`.
4. Ran six parallel read-only code surveys (identity and security; discovery and tooling; state and memory; execution and compute; inference and routing; observability, governance and testing), each returning `path:line`, tests, gates and a grade.
5. Spot-verified 50 cited line references by opening them; corrected three (`router.gleam` guardian demo, `checkpoint.gleam` stub comment, `wiki_similarity.ml` functions) and confirmed the highest-impact claims by independent grep (enforcer importers, worker spawn sites, guardian gate callers, dispatch-hook callers, unconditional checklist summary).
6. Authored the checklist document: 27 service rows plus 6 readiness rows, layer view, ASCII and Mermaid evidence-flow diagrams, scorecard, gate-integrity findings, 13-harness differential test plan, reproduction commands, 18-check accordion, navigation.
7. Ran the document validators and the active-check (section 7), then completed the sa-plan task with a result receipt.

## 4. Root Cause Analysis

The earlier blueprint documents overclaim because the machinery they cite cannot fail: `tools/uos checklist` prints `18/18 Checks Passed` unconditionally (`tools/uos/src/main.gleam:1044-1045`), several selfchecks print fixed `[PASS]` lines, and other gates test only that files exist. Markdown then copies phrases from the reference document ("fine-grained network egress control", "cycling between identical error states") into UOS specifications without implementing them, and later documents cite those specifications as evidence. Modules that are real but unwired (`planning/enforcer.gleam`, `ha/context_manager.gleam`, `ha/context_cache.gleam`, `sa_plan_temporal.ml`, `agent_dispatch_hook.ml`) are counted as capabilities because existence gates cannot see call graphs.

## 5. Fix Taxonomy

Documentation and evidence, not code: (a) a code-bound checklist replacing policy assertions with `path:line` and grades; (b) an oracle registry binding third-party references with provenance; (c) a differential test plan that names the harness each row needs to advance. Gate defects were recorded as P1 findings, not repaired, because gate code is outside this task's scope and authority.

## 6. Patterns & Anti-Patterns Discovered

**Patterns worth keeping**: the MCP tool catalog marks unavailable tools explicitly (`mcp/tools.gleam:18-32`); the unikernel daemon names its functions `simulate_*`; `doctor` labels its rows `[INVENTORY]`; the sa-plan control plane is tested against an independent replay oracle; the risk checker refuses symlink and stale evidence.

**Anti-patterns**: unconditional PASS summaries; file-existence gates presented as verification; three OTel emitters with two different severity scales and no validator for the contract; conformance-mirror modules with no callers; proofs (`formal/lean/*.lean`) with no build in the repository; a `SemanticCache` table read by a NIF that nothing creates; a hard-coded `cache_hit_rate: 0.942` in the inference worker; a stateless demo approval endpoint returning hard-coded pending requests.

## 7. Verification Matrix

| Check | Command | Result |
|---|---|---|
| Sa-plan preflight before claim | `bash tools/risk-priority-check --preflight <portfolio> t1-fractal-checklist` | `PREFLIGHT_PASS` after two evidence repairs |
| Sa-plan claim | `tools/sa-plan task claim … 14400000000000 t1-fractal-checklist` | `claimed=true attempt=1` |
| Oracle clones | 24 × `git clone --depth 1` (evidence directory only) | 24 `cloned`, 0 failed |
| Line-reference spot checks | `sed -n` on 50 cited lines | 47 matched; 3 corrected before publication |
| Active check during execution | `bash tools/risk-priority-check --active-check <portfolio> t1-fractal-checklist <worker> 1` | `ACTIVE_OBSERVATION_PASS`, no findings, exit 0 |
| `tools/uos timestamp-check` | `gleam run -- timestamp-check` | PASS (regex `^[0-9]{8}-[0-9]{4}-` and contract presence; repository-level, not per-file) |
| `tools/uos rocha-check` | `gleam run -- rocha-check` | PASS 6/6 (checks fixed files, not this document; per-document markers self-checked below) |
| `tools/uos km-check` | `gleam run -- km-check` | PASS 4/4 (contract and engine presence) |
| `tools/uos checklist` | `gleam run -- checklist` | printed 18/18; non-gating by construction (see checklist section 6.2) |
| Test suites | none executed | `UNRUN` by design of this task |
| Oracle differential tests | none exist | `UNRUN` |

## 8. Files Modified

| File | Change |
|---|---|
| `docs/design/20260907-1756-production-agent-infrastructure-fractal-checklist-and-oracle-map.md` | New: the checklist and oracle map |
| `governance/sources/20260907-1756-agentic-infra-third-party-oracle-registry.json` | New: 24 pinned oracle records |
| `docs/journal/20260907-1756-production-agent-infrastructure-fractal-checklist-journal.md` | New: this journal |
| `var/sa-plan/uos.sqlite3` | Ledger rows for the plan, task, claim and completion (through `tools/sa-plan` only) |
| `/home/an/NAS-setup/oracles/*` | New external evidence directory, outside the UOS tree |

## 9. Architectural Observations

The transaction plane (sa-plan) is the strongest subsystem in the map: fencing tokens, idempotency keys, replay against an oracle, and a CLI that this task exercised end to end. The weakest planes are execution isolation (fragments plus simulation, no egress control) and the seams between planes: policy logic, rate limiting, compaction, caching and the inference worker each exist as tested modules with no caller on the live dispatch path. The right first investments are wiring, not new modules.

## 10. Remaining Gaps

Per the checklist's section 6.3: gate integrity repairs (P1); guardian gate and enforcer on `tools/call`; persistent approvals bound to sa-plan; sandbox egress and seccomp; compensations and pause/resume; tenant budgets and a dispatch-path limiter; unified severity scale, traceparent parsing, span persistence; then caches, ANN and compaction wiring. Thirteen differential harnesses are specified and none exists. Independent Codex and AGY review of this document is outstanding.

## 11. Metrics Summary

| Metric | Value |
|---|---|
| Service rows mapped | 27 (REAL 13, PARTIAL 13, DOC-ONLY 1) |
| Readiness criteria met | 0 of 6 fully; 4 partial; 2 not met |
| Sub-requirements ABSENT or DOC-ONLY | 12 |
| Oracles pinned / rows covered | 24 / 24 of 27 |
| Differential harnesses existing | 0 of 13 |
| Line references cited / spot-checked / corrected | ~120 / 50 / 3 |
| Code surveys | 6 parallel, 216 s to 521 s each |
| Oracle clone volume | 1,522 MB, 24 repositories |
| Files added to UOS | 3 |
| Test suites run | 0 |

## 12. STAMP & Constitutional Alignment

Controller: this session as documentation author. Control action: publish a code-bound readiness checklist. Loss guarded: L-1 false conformance. Hazard: H-1, a green gate over a defect. UCA "provided unsafe" (grading a DOC-ONLY capability as REAL) was constrained by requiring `path:line` plus test evidence per row and by spot-checking lines; UCA "not provided" (omitting gaps) was constrained by listing every taxonomy row including ABSENT sub-parts; UCA "wrong timing" (stale tree) was constrained by recording the jj change and the concurrent writer. `SC-JIDOKA-001` and `SC-SA-PLAN-001` were observed: the work was ledgered, preflighted, claimed and completed only through `tools/sa-plan`. `SC-RISK-CHECK-001` preflight and active-check were run. No Git command was executed inside UOS (`CHK-18-JJ`). Ingestion discipline (policy section 3) was observed: oracle bytes stay outside the tree with locator-bound provenance.

## 13. Conclusion

UOS is **not production-ready** by the reference document's own six criteria at the observed revision, and the earlier `18/18 PASS` matrices do not survive a code-level reading. The system does contain a strong durable transaction plane, real crypto, vault, routing, graph, tracing-context and adversarial-testing modules, and an unusually self-honest MCP catalog. What it lacks is wiring at effect boundaries, sandbox egress control, and gates that can fail. Every row now names the code, the test, the oracle and the gap, so the next tasks can be claimed against evidence instead of narrative.

---

**Previous:** [Checklist and oracle map](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-1756-production-agent-infrastructure-fractal-checklist-and-oracle-map.md) · **Next:** follow-up sa-plan tasks per section 10  
**Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md) · **Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md) · **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md)  
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · peer `vm-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.

**Per-document marker self-check (grep, both new Markdown files)**: `#fractal-l0` … `#fractal-l9`, `#rocha-semiotics`, `#cybernetics`, `#km-triad`, `#zero-muda`, `[[zk:20260905-1801-moc-uos-unified-master]]`, `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`, `http://nas-1.tail55d152.ts.net:4100/` links, bottom navigation to ZK MOC, Wiki index and Review Tome, ASCII and Mermaid sources for the one diagram: all present. **Concurrent writer note**: during this task the shared jj working copy was re-described by another session (now `1b742ce3`, "feat(cockpit,crdt,formal)…"); the three files of this task sit in that working copy and were not committed by this session.
