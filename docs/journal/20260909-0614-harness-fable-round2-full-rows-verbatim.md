# 20260909-0614 — Fable round 2 FULL VERBATIM ROWS: D01–D28 census + 17 §7 aspects (`claude-fable-harness-1`)

#fractal-l0 #fractal-l4 #fractal-l5 #fractal-l9 #zero-muda #stamp-stpa

**ADDITIVE.** All prior artifacts preserved unamended. **Not approval. Not admission. No admission vote.**

Tailnet: [http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0614-harness-fable-round2-full-rows-verbatim.md](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0614-harness-fable-round2-full-rows-verbatim.md)

## 0. Why this artifact exists — a defect in my own prior artifact

Root's MCP readback of `docs/journal/20260909-0644-harness-fable-round2-census-and-aspects.md` is correct, and both gaps it names are mine:

| Prior claim | Location | Truth |
|---|---|---|
| "Full per-row tables are in the delegated report relayed to the coordinator board" | 0644 §2 | **FALSE.** I relayed paths and digests to the board, never the rows. No board message contains the full report. There is no board message reference to give. |
| "Fable listed extensive not-read and not-executed scope; that list is preserved in the markdown" | 0644 §7 | **FALSE.** The list was not in that markdown. It is in §5 below. |

This is the same defect class this review has been reporting throughout: **an observable coarser than the property being enforced** — I published counts and asserted the rows existed elsewhere, and no check compared the assertion to the artifact. Root's readback was the check.

**Prior artifacts are NOT amended.** This file is additive and supersedes only those two sentences.

## 1. Provenance of the rows below

- **Source:** the delegated Fable subagent's single final report, task id `ae32fc53b62c4686d`, tool-use id `toolu_01M5N3r3Tr1QVYNu6GR7Uj5x`, delivered `2026-09-09T06:43:56.006Z`.
- **Extraction:** copied verbatim from the session transcript `a65088e0-0f2b-497e-bd5c-97eeed9c3594.jsonl`. The transcript records the delivery twice; both copies were extracted independently and compared byte-for-byte — **identical**. Extracted body sha256 `3786f3e5a16c82f31d91d2ecc4f4477708e68286dead3fec9bfe2eeafbc6f0c8` (96 lines, 22921 bytes).
- **No Opus rows substituted. No Fable verdict regenerated, reworded, added or removed.**
- `&gt;` / `&lt;` sequences appearing inside the body are the delivery channel's control-tag neutralization, present in the delivered text. Preserved rather than un-escaped, because un-escaping would edit the delivered bytes.
- Reported model identity `claude-fable-5-1` is a **self-report and is not cryptographically provable**. Preserved as delivered.
- The subagent is a delegated read-only instance inside session `session_01B9GiR9bF4d1Jv2aSMowAKC`. **Not a sovereign session. No Sa-plan claim, no board write, no peer ACK, no admission vote.**

---

## 2–5. VERBATIM DELEGATED REPORT (unedited)

**Identity:** I am Claude **Fable 5.1** (model ID `claude-fable-5-1`), running as a read-only Claude Code subagent. Herdr session `a65088e0-0f2b-497e-bd5c-97eeed9c3594`, pane `w2:p2` (matches the root's peer receipts for `claude-fable-harness-1` and `fable-complete-decision-census`). I am not the granted harness worker and did not impersonate it. This review grants no admission and casts no admission vote.

**Review window:** 2026-09-09T06:32:13Z to 2026-09-09T06:38:42Z. Host TZ +0200 (file mtimes below converted to UTC).

**Digests (sha256, verified):**
- packet `99c41eb7c35749d28970ca3cab7e52bd488273eb7df96144902ac5b1625a4798` MATCH
- formal spec `7388539c78ceccdd00cc4116231ccceee1268b484b36575ee16f33b81172b901` MATCH
- atlas `b55c66b0a6b41197b9d197baec96f5a9fdcaa595a25926e164d776e645addb56` MATCH
- prior: 0721 opus5 review `871087bcafa31bcb4c07bea2032ecba47fd8ac68a8b273b563ecdee699c3a979`; 0720 matrix `cfb7eb0521a020d7aa4e238e0c35848d3b4cf7d2ecdaea035a3626a3be296257`; 0854 round-1 `53ac267608c2ef29bca7ad465c32c079f977d80148303d93255412221ffcc67a`; 0627 correction `31328e21c1b54cb5c523c2c5cdd47feca1935d9bab7d187321e646bfb1c2e438`

**Source identity:** jj change `xxsoxxwwqsrpmwkxwnkoryqwtmnvuzty`, commit `fb9e605e6f39482b12061663b05bc50931baba29`, working copy DIRTY (harness/*.gleam Added, mcp/*.gleam Modified). No committed candidate exists. Source moved during this review: `harness_tracking_test.gleam` mtime 2026-09-09T06:35:47Z.

Path legend (all under `/home/an/NAS-setup/uos/`): `dev.gleam`=`apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam` (`b750bda8550c6684875217e2b048cd7a5fb4ea0f2f75baf04ceb4b46120e6e25`); `files.gleam` (`e478adc77086491ffbdf3a9276c77a6a3d4366c5e6bf6d8af5a5bf0157f8900e`); `clock.gleam` (`a8df8dcb7767c89081b3431f0a6ddfc338f53fdfaa884315024af8482194325d`); `mcp.gleam` (`3c737157417b145af952e643d1b460de697c3ed5496e3e24732205d79a6f550c`); `peers.gleam` (`2a0ca519c89a1237d9d17aa8a692162a4ecdcee9bcc346237ed81c263bd8d456`); `tracking.gleam` (`1655c40eda58fbabdf01ad904d0f02cdf60f410319b5b8f3a493189ca3694e24`); `server.gleam`=`.../mcp/server.gleam` (`294cac68950b937b66e963acf3b8ad61e2b1b246a8488845db347352a5a911f2`); `authz.gleam` (`c3f480bc64809d523580c15cf7b5480e7335755d0c6f055dd57a49f61ba1b4e0`); `bridge.gleam`=`.../planning/sa_plan_bridge.gleam` (`7d9d3e31c2ef06ceed016b7077cb5d466b6524bcc6cea35cdd8200a4439b70ae`); `ffi.erl`=`apps/cepaf_gleam/src/ecology_capability_ffi.erl` (`ea39820d592d68d10cbbb1fffa12dff7d0080c4d5eadcf327c80ef23077af8fd`); `process.ml`=`tools/ecology_process.ml` (`cb5bc7a25b562ecc259696920f84f59e172b78842c3b53b3ed6173b2ab752ecf`); `risk.json`=`var/harness/20260909-0412-bootstrap-risk.json`; `final-test`=`var/harness/effects/20260909-0412-bootstrap-tracking-final-test-1-result.json`; `atlas`=`docs/design/20260909-0412-gleam-harness-symbiosis-algebraic-atlas.json`; `spec`=`docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md`.

## (1) D01–D28 decision matrix

| D | Verdict | Basis (answering the packet's own challenge) |
|---|---|---|
| D01 | ACCEPT_WITHIN_SCOPE | `governance/sources/20260909-0241-ecology-vm1-comparison-receipt.json` scope = read-only, no external writes; atlas `ucon.binding` state=planned "not located/verified"; `dev.gleam:605-659` read scope excludes external trees; UCon not invented. |
| D02 | REVISE | `ecology/living_swarm.gleam:115` `Participant` type has exactly 26 variants (local enum, not bindings); "discovery" is a fixed list `mcp.gleam:233-255` (dev+peers+tracking names), not a capability inventory; atlas `holon_policy` is prose. |
| D03 | REVISE | No client enforcement: `.claude/settings.json` has no `hooks` key (uses non-standard `uos_control_loop`, never executed by Claude Code); `.codex/hooks.json` self-declares advisory; contract §9 leaves direct-tool exception open; this review ran on host tools because the harness refuses every non-granted identity (see 4). |
| D04 | ACCEPT_WITHIN_SCOPE | Requirement only, no parity claimed: atlas `bootstrap_ready.zenoh`=`UNAVAILABLE_NOT_VERIFIED`; `zenoh/zmof_transport.gleam:83,87` prefixes `indrajaal/mcp/req|res`; `zenoh/client.gleam` has no MCP prefix; harness has no Zenoh path. |
| D05 | REVISE | New non-Gleam control-adjacent code was authored in the bootstrap: `process.ml` (OCaml guardian, 04:12Z) and `ffi.erl` (Erlang port runner, `:119-160`); atlas `native.ocaml` says "existing pinned analysis adapters" and does not list `process.ml`. |
| D06 | ACCEPT_WITHIN_SCOPE | atlas `compiler_layer.state`=PROPOSED, `general_gleam_native_translation`=NOT_AVAILABLE_NOT_CLAIMED; no kernel-IR module in `apps/cepaf_gleam/src` (grep empty). |
| D07 | ACCEPT_WITHIN_SCOPE | OCaml runs out-of-process (`process.ml` fork/setsid/execve, group kill, one-shot alarm, 1 MiB cap) so GC-root/NIF questions do not arise on this path; MAX via pixi subprocess `ffi.erl:233-244` with 64 KiB bound; NIF/Mojo lifecycle contracts remain UNKNOWN (atlas rows mapped). |
| D08 | REVISE | Effect-time fence is real: `dev.gleam:312-322` reads `sa_plan_task` + dependency-blocked count, `:250-274` requires executing/worker/attempt/deadline/blocked==0. But `bridge.gleam:627-736` still holds an in-memory Task/ObanJob model and `sdlc/sa_plan_engine.gleam:170 claim_task` exists (atlas falsifier "no independent task store"); harness reads the store via `/usr/bin/sqlite3` (`dev.gleam:55`) rather than the CLI. |
| D09 | ACCEPT_WITHIN_SCOPE | `risk.json`: 2 assessments (ECOLOGY, HARNESSBOOT), class P1, score 768; UCA types present = {not_provided, provided_unsafe, wrong_timing, duration}; FMEA raw s/o/det/rpn/band (S4 O3 Det3 RPN36). Defect: every factor's `evidence_refs` is the same 28-path list; interval degenerate [768,768]. |
| D10 | ACCEPT_WITHIN_SCOPE | `dev.gleam:445-470` re-samples clock after both observations, requires same `boot_id` and coordinator deadline &gt; now + required; receipts `fence_scope=cooperative_observation_not_atomic_authority`, `system_admission:false` (`:1541`). Residual: heartbeat renews 3600 s per call (`:592`) vs 70 s window. |
| D11 | ACCEPT_WITHIN_SCOPE | `dev.gleam:1051-1173`: exclusive-create pending intent keyed by sha256(name+args) (`:946-948`, attempt excluded); pending-without-result -&gt; `effect_outcome_unknown_reconcile_without_retry`; `replay_receipt:1175-1210` refuses non-EXECUTED/non-passed; test `replay_preserves_failure_and_rejects_corrupt_or_unbound_receipts_test`. Cross-transport dedup untestable (no Zenoh). Source-only. |
| D12 | ACCEPT_WITHIN_SCOPE | `files.gleam:88-100` rejects `.`,`..`,`\\`,NUL,&gt;512 B; `:102-118` parents must be directories via `link_info`; `:126-179` nlinks==1, ≤262144 B, open-descriptor inode/dev match, pread bound, UTF-8; `:189-211` `[Exclusive,Sync]` + parent sync; `:227-263` double-digest CAS + rename; header `:1-3` admits parent-rename race. |
| D13 | ACCEPT_WITHIN_SCOPE | `server.gleam:1373-1382` invalid UTF-8 -&gt; `Error("Invalid UTF-8 in file")`; `bridge.gleam:951-985` literal argv, ≤16 args, ≤65536 B, NUL refused, pinned env + `UOS_SA_PLAN_DB`; `:1021-1041` attempt&gt;0; 5 boundary tests. Remaining legacy gap: `authz.gleam:14-17` default `AuditOnly`; `bridge.gleam:947` hardcodes a `_build/.../test/sa_plan_main.exe` path. |
| D14 | ACCEPT_WITHIN_SCOPE | `mcp.gleam:206-207` notifications never dispatch; `:227-230` `initialize_required` (-32002); `schema():155-180` `additionalProperties:false`; frame 524288 B / 5000 ms (`:24-25,36-42`); `control_id()` = module md5 (`dev.gleam:134-142`) and my probe returned `00fe7e27a175b90928a1ba153c7fac56` = receipt; `reconcile_terminal:1493-1544`. Only the refusal path was observed at runtime by me. |
| D15 | ACCEPT_WITHIN_SCOPE | `clock.gleam:77` bounded `/usr/bin/chronyc -c tracking` (2000 ms); reference age (≤3600 s, `:28`) vs delivery (≤3 s, `:30`) vs offset/uncertainty (`:32-38`) are separate fields; `dev.gleam:463` refuses cross-boot comparison. `final-test` shows offset 185 us, uncertainty 17593 us, reference_age 285.4 s. |
| D16 | UNKNOWN | Only the literal role `"development"` exists in code (`dev.gleam:189,261,1327,1357`); production/standby have no representation; spec §9 calls it a design proposal. Nothing to evaluate. |
| D17 | REVISE | spec §8 requires writer/durability/schema/replication/restore per state item; atlas `states` is 34 bare strings; all 30 rows have `state.replication`/`restore` = "UNKNOWN until..." literals; no replication symbols in `apps/cepaf_gleam/src` (mnesia/disk_log/replication_position/writer_epoch: none). |
| D18 | ACCEPT_WITHIN_SCOPE | Conditional only; `ha/otp_release.gleam` is a typed `.rel/.appup` representation, not release_handler execution; atlas `release.dynamic` planned "rehearsals unrun"; no `release_handler`/`code:load_binary` in harness. |
| D19 | REVISE | Names are hardcoded ceilings `ecology/daily_budget.gleam:43-47` (`z-ai/glm-5.3`, `moonshotai/kimi-k3`, `deepseek/deepseek-v4-pro-0813`, `deepseek-v4-flash-0731`, `google/gemma-4-31b-it`); no measured task-quality receipt binds "prefer Gemma 4" (I did not read `docs/journal/20260909-0331-*`, so its coverage is UNKNOWN). |
| D20 | ACCEPT_WITHIN_SCOPE | `daily_budget.gleam:9` 10_000_000_000 nano-USD/day, `:11` 250_000_000 per-call, `:106` worst_case ≤ reservation, `:141-159` invoice cannot reduce reserved liability; module header `:1-2`: persistence/atomic reservation live elsewhere (UNKNOWN, unobserved); no OpenRouter receipt in `var/harness/effects/`. |
| D21 | UNKNOWN | `openrouter_engine.gleam:1` "No queue, retries, optimizer"; atlas `models.routing` "whole ecology binding pending"; calibration needs runtime data that does not exist. |
| D22 | REVISE | `tools/validation/openrouter_eval_{build,catalog,cli,expr,native,test,validate}.ml` exist; no Rete-UL implementation found in `engines/hermes/modules` (only wiki prose) or Gleam; atlas `rules.rete_ul` planned. The decision must not list Rete as covered. |
| D23 | ACCEPT_WITHIN_SCOPE | Policy holds; but `formal/lean/Denotational_Atlas_Cohomology.lean:55,62,74` contain `sorry` (0 top-level `axiom` across `formal/lean`); `Algebraic_Atlas_Intent.lean` clean (3 theorems). Harness binds no Lean/Quint invocation (atlas rows mapped). |
| D24 | ACCEPT_WITHIN_SCOPE | `var/releases/ecology/` holds 5 staged read-only release dirs separate from `build/dev`; `risk.json` ECOLOGY `task_state=available` "not completed"; `ucon.binding` planned. |
| D25 | ACCEPT_WITHIN_SCOPE | `.codex/hooks.json` = SessionStart advisory + preflight; on the Claude surface there is no hook at all (`.claude/settings.json` non-standard key); `.agents/hooks.json`, `.gemini/hooks.json` not read. Decision text is accurate; enforcement absent. |
| D26 | REVISE | `dev.gleam:1212-1231` enforces the exact 13 titles; spec §22 ASCII/Mermaid pairs match by node/edge count (12/16, 8/10, 7/11) and atlas `diagrams` titles match; but atlas `traceability.aspects` is the same constant string on all 30 rows (no per-aspect map); no `20260909-*harness*` wiki/ZK docs exist. |
| D27 | UNKNOWN | No standby node, no replication code, atlas `state.replication`/`release.dynamic` planned; spec §21:403 itself marks RTO/loss UNKNOWN until tested. |
| D28 | REVISE | No `var/harness/20260909-0412-bootstrap-completion-{intent,result}.json` exists; latest `final-test` (06:16:52Z, "All 69 tests passed", `admission NOT_GRANTED`) is stale: 1/28 manifest entries differ now (`harness_tracking_test.gleam` receipt `d87b1c1a8b2366e57530938a0f164bae6d9e8617dcc7cd26d035405282ee3413` vs now `cb0a339938a8ccd234fa9b8bd33accc1b04cc660f5eeaec589cad3420efbf63d`, modified 06:35:47Z); a `peer-claude-final-harness-source-frozen` prompt was dispatched while source still moved; all peer receipts `peer_acknowledged:false`. |

## (2) Seventeen aspects (spec §7 names, verbatim)

| # | Aspect | Status | Observed in source | Gap |
|---|---|---|---|---|
| 1 | Substrate and hardware safety | ACCEPT_WITHIN_SCOPE | `ops/kubernetes/nas-k8s-lab/src/spec.rs:192` serial unchanged; harness sources contain no device/storage references. | Interlock runtime test UNRUN (CHK-07). |
| 2 | Version control | REVISE | Heartbeat uses pinned `jj --ignore-working-copy` (`dev.gleam:558-572`). Candidate is an uncommitted dirty working copy; `pub const root` hardcodes canonical checkout (`dev.gleam:27`). | No committed candidate to bind receipts; source moved during review. |
| 3 | Purity and provenance | REVISE | `dev.gleam:59-68 adapter_scope()` explicitly declares host `/usr/bin/{sqlite3,bash,chronyc}` (now declared, not hidden); external trees excluded (`finite_file_scope_excludes_credentials_and_external_trees_test`). | Host-path exception contradicts SC-NIX-DEVENV-001 inv.5 and has no governance manifest entry; dependency diff not checked by me. |
| 4 | Supervision | REVISE | `mcp.gleam:84-92 main()` is a bare loop; workers are `spawn_unlinked` (`dev.gleam:288-291`); no harness child in `uos_sup.gleam`; atlas `otp.supervision` planned. | The harness itself is unsupervised; restart budgets undeclared. |
| 5 | Deterministic runtime | UNKNOWN | `engines/zigvm` present; zero ZigVM references in harness; atlas `backends` lists `zigvm` as `admitted_deterministic_engine` but no capability row uses it. | "admitted" label unsupported by any row; nothing to evaluate. |
| 6 | Evidence and analysis | ACCEPT_WITHIN_SCOPE | `process.ml` guardian (process group, one-shot alarm, output cap); `sa_plan_main.exe` invoked with literal argv (`bridge.gleam:951-985`). | Per-call `ocaml` toplevel load; `hermes_bionic_bridge.gleam` not reviewed. |
| 7 | Mathematical authority | ACCEPT_WITHIN_SCOPE | No harness tool invokes Lean/Quint; `sorry` at `Denotational_Atlas_Cohomology.lean:55,62,74`; 0 axioms. | `formal.lean`/`formal.quint` rows mapped; no invocation receipts. |
| 8 | Feedback and homeostasis | ACCEPT_WITHIN_SCOPE | Observation (`bounded_observation :279-309`), decision (`evaluate_task_window :250-274`), authority (`fence_for :445-470`), effect (`effect :1051`) are separate; receipts `authority=OBSERVATION_ONLY`. | None at bootstrap scope. |
| 9 | Inference | ACCEPT_WITHIN_SCOPE | MAX isolated via pixi subprocess (`ffi.erl:233-244`); OpenRouter engine pure, price required pre-POST (`openrouter_engine.gleam:28,50`); no paid receipt. | Harness exposes no model tool; ecology binding pending. |
| 10 | Mesh and observability | REVISE | No Zenoh path in harness; receipts carry `intent_id`/`signature` but no `trace_id`/`span_id`. | spec §2 envelope requires trace ID; C3I OTel contract unmet by harness receipts. |
| 11 | Agent events | REVISE | `agui/events.gleam` exists; harness emits no AG-UI lifecycle/tool/state/result events; `var/harness/effects/` is the only trail. | Events do not "reflect actual transitions" because none are emitted. |
| 12 | Declarative UI | UNKNOWN | `tracking.gleam:167` treats `dashboard` as catalog metadata; no UI module references harness. | No projection exists to assess. |
| 13 | Interfaces | REVISE | Only stdio MCP exists (`serverInfo uos-gleam-development-harness 0.1.0`); no Wisp route, TUI, or Zenoh; Claude client has no hook. | "Same authority semantics" untestable with one interface; legacy `server.gleam` (AuditOnly) still coexists. |
| 14 | Navigation | ACCEPT_WITHIN_SCOPE | Spec/packet carry full Tailnet FQDN links; GET of the spec URL returned HTTP 200, 30970 bytes at 06:36:58Z. | Byte-equality with local file not verified; wiki/ZK pages absent. |
| 15 | Verification checklist | REVISE | Receipts report scope/freshness (source manifest, start/end clocks, `admission NOT_GRANTED`); spec §16 lists 18 checkpoints all OPEN. | Packet checklist (`:71-82`) is a 6-row summary, not the 18-item SC-CHECKLIST-001 structure. |
| 16 | Knowledge triad | REVISE | `journal_sections_valid` enforces 13 sections; `document_allowed :623-642` permits wiki/ZK writes. | No `20260909-*harness*` wiki/ZK docs exist; atlas per-row aspects constant. This review is message-only per root's read-only instruction; no journal file added. |
| 17 | Durable execution | REVISE | Tracking plan `uos/harness-features/20260909` (`tracking.gleam:18`), 396 feature intents / 218 results, mode `metadata_only_no_automatic_dispatch`; task fence reads canonical sqlite. | Second task model in `bridge.gleam:627-736` and `sdlc/sa_plan_engine.gleam:170`; direct `/usr/bin/sqlite3` reader alongside the CLI authority. |

## (3) Spec, atlas and lifecycle review

**§2 denotational core.** No `denote(I,S,A,C)` implementation exists (only unrelated `denote` in `verification/web_quality_contract.gleam:234` and `dmc_tcm_algebraic_atlas.gleam:49`). Request envelope: harness tool arguments are only `path/content/expected_sha256/intent_id/...` (`mcp.gleam:155-165`); no schema version, trace ID, holon ID, environment, resource ceiling, deadline or capability version; task/attempt/epoch come from launcher env, not the request (correctly, per "payload identity SHALL NOT authenticate"). Receipt: has intent, attempt, epoch, source manifest, clocks, status, admission; lacks trace ID, selected backend, resource use, replication position. Supported: durable intent before dispatch (`dev.gleam:1079-1091`), dedup independent of attempt (`:946-948`), no automatic retry on unknown outcome. H05/H07/H11 unexercised.

**§3 algebraic atlas vs JSON.** The JSON does not encode the §3 nine-structure table. Keyword hits in the atlas: associativ 0, commut 0, disjoint 0, intersection 0, "UNKNOWN never" 0, committed prefix 0, migration relation 0, nonnegative/conserved 0, serialized admission 0. Every one of the 30 rows carries the identical second law string ("Backend refinement preserves the declared relation; denial dominates capability composition") and the identical oracle string ("Independent specification/reference required per capability; generic row is not a proof"); only the first law string is row-specific. `traceability.aspects` is one constant sentence on all rows. §5's requirement that the atlas enumerate the actual OTP/ERTS installation is unmet (no `otp_inventory`/`installed_applications` key). True claims: 16-field schema present, 30 rows, evidence.state = planned 11 / mapped 9 / implemented 6 / executed 4, `admitted:false` everywhere, `admission.ev_ceiling=93`, three diagram titles match §22 (and §22 ASCII/Mermaid pairs match by nodes/edges).

**§20 complete SDLC coverage.** 13 stages in the spec; atlas has no sdlc/lifecycle key. Harness covers Implementation (edit), Verification (build/test), Review (peer transport), and Planning partially (tracking metadata). Intake/Requirements/Architecture are document-only; Validation, Packaging, Release, Operation, Evolution, Retirement have no harness capability. R26 ("SDLC, SRE, verification and retirement use the same harness authority", verified by H01-H16) is unsupported beyond H02/H04 source repairs and codex's own MCP receipts.

**§21 SRE and verification policy.** Atlas rows contain no availability/latency/saturation/error-budget/RTO/RPO fields (0 hits); `supervision.bounds` is a placeholder sentence. The spec's own line 403 concedes recovery bounds UNKNOWN, so the spec is internally consistent but the atlas does not carry the required per-capability declarations. "Verification SHALL exercise the public MCP/Zenoh interface": MCP exercised by codex receipts; Zenoh not. OTP release handling: `ha/otp_release.gleam` is representation only.

**Other spec assertions unsupported by source:** §1 "unavailable harness SHALL cause explicit hold; no silent host-tool fallback" has no client mechanism (D03/D25). §15 identifies the server as `c3i-planning-mcp 1.0.0`; the new harness identifies as `uos-gleam-development-harness 0.1.0` and the legacy `server.gleam` (AuditOnly authz) still exists; §14.C does not reconcile two MCP servers. §23's "28 checks at 05:14:09Z" is superseded by 69 eunit tests at 06:16:52Z, itself now stale for 1/28 manifest paths.

## (4) Harness access attempt

Toolchain: pinned OTP 29.0.5 `/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5`; already-built ebin (35 dirs, `cepaf_gleam@harness@development.beam` mtime 06:15:25Z). No `UOS_HARNESS_*` variables were set in my environment; I never set them to the granted values.

- **First attempt 2026-09-09T06:36:27Z FAILED before reaching the harness** (my zsh passed the whole `-pa` list as one argument, BEAM boot `system_limit` crash). **Side effect:** `/home/an/NAS-setup/uos/erl_crash.dump` (1,091,766 bytes, mtime 06:36:27.868Z) was written to the repository root. It is covered by `.gitignore:48` (so jj will not snapshot it). I did not delete it (deletion is forbidden to me); root should remove it.
- **Re-run 2026-09-09T06:38:02Z** with crash dumps disabled (`ERL_CRASH_DUMP_SECONDS=0`):
  - A. `load_binding()` with no env -&gt; `{error,&lt;&lt;"role_binding_missing"&gt;&gt;}`
  - B. `load_binding()` with a clearly non-impersonating identity (`role=development, plan=uos/ecology/20260909-0146, task=HARNESSBOOT, worker=claude-fable-delegated-review, attempt=1, session=claude-fable-harness-1, epoch=1`) -&gt; `{error,&lt;&lt;"development_bootstrap_grant_mismatch"&gt;&gt;}` (`dev.gleam:188-199`, single literal tuple; comment `:186-187` says new scopes need a separately reviewed grant, i.e. a source change).
  - C. Real entry `cepaf_gleam@harness@mcp:main()` fed `initialize` + `tools/call harness_read_file(packet)` with no env -&gt; stdout 0 bytes, stderr `harness: trusted development binding or stdin unavailable`, exit 0. No JSON-RPC response of any kind, because binding is checked before the transport loop (`mcp.gleam:85-91`).
  - D. `control_id()` -&gt; `00fe7e27a175b90928a1ba153c7fac56`, equal to the receipt's `loaded_dispatch_module_md5` (built dispatch module matches the receipt; the `.beam` file md5 `24b3709239c15687a9bb858ed721ede6` differs only because `control_id` is `module_info(md5)`).
- **Missing bootstrap method:** no launcher script, `.mcp.json`, or Codex MCP config references the harness (`UOS_HARNESS_` appears only in `dev.gleam`); the only route is manual `erl -pa` plus env. There is no second-reviewer grant path. `peers.gleam:56-58` limits peer review to `claude|agy`; the root's prompts reached my pane (`w2:p2`, `scope_allowed_by_default:false`, `peer_acknowledged:false`).

## Not read / not executed

Not read: bodies of `tracking.gleam`, `hermes_bionic_bridge.gleam`, `mcp/tools.gleam`, most of `server.gleam`, the four test bodies (names only), `uos_swarm/openrouter_worker.gleam`, `session_sync*`, `herdr`, `.agents/.gemini hooks.json`, atlas rows 2-30 in full (summarized fields only), the bodies of the Codex reviews (0510, 0539), the 0331/0356 journals, and round-1/Opus bodies (headings only). Not executed: `gleam build/test`, `sa-plan`, `km-gate`, `preflight`, any Zenoh, any OpenRouter or paid call, any jj command after 06:36Z. Runtime observations by me are limited to probes A-D above and one bounded HTTP GET; every other verdict is source-only.

---

## 6. End of verbatim region

Nothing above this line was authored by Opus 5.

### 6.1 A third defect found by machine-counting the rows

Counting the verbatim `D01`–`D28` verdicts mechanically gives:

| | Rows (authoritative) | 0644 artifact published |
|---|---|---|
| ACCEPT_WITHIN_SCOPE | **16** | 17 |
| REVISE | **9** | 8 |
| UNKNOWN | 3 | 3 |
| REJECT | 0 | 0 |

**The published D-census count was wrong by one.** One decision Fable marked `REVISE` was counted as `ACCEPT_WITHIN_SCOPE`. The rows are authoritative; the count was mine and it was not derived from them. Per-row verdicts as delivered: `ACCEPT_WITHIN_SCOPE` = D01, D04, D06, D07, D09, D10, D11, D12, D13, D14, D15, D18, D20, D23, D24, D25 (16). `REVISE` = D02, D03, D05, D08, D17, D19, D22, D26, D28 (9). `UNKNOWN` = D16, D21, D27 (3).

This is the same defect class a third time, and it is the strongest available argument for root's position: **counts are not coverage, and my counts were not even correct.** No Fable verdict was altered to make the numbers agree — the artifact carries the rows and the corrected arithmetic.

The 17-aspect counts DO match: `ACCEPT_WITHIN_SCOPE` 6, `REVISE` 9, `UNKNOWN` 2, `REJECT` 0.

## 7. Limits

- Full coverage is delivered **as rows**, not as counts. This artifact is the row delivery.
- Delivery is not admission. No admission vote is cast by either reviewer.
- Fable's runtime observations are limited to probes A–D and one bounded HTTP GET; every other verdict is source-only, as its own §"Not read / not executed" states.
- R2-1 … R2-7 and N10 remain **open gaps**, not hidden admission.
- No production, dashboard, or harness change was made. Root's 28-file manifest was not touched. No new paid route.

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · peer [vm-1.tail55d152.ts.net:8088](http://vm-1.tail55d152.ts.net:8088) · Sa-plan is the sole execution authority; this artifact grants no admission and no effect authority.
