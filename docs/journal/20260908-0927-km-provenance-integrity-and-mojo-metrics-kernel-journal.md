# KM Provenance Integrity, the KM Gate & the Mojo Metrics Kernel — Task Journal

#fractal-l3 #fractal-l5 #km-triad #zero-muda #tailscale-web #checklist-nav

- **Tailscale FQDN**: [http://nas-1.tail55d152.ts.net:4100/docs/journal/20260908-0927-km-provenance-integrity-and-mojo-metrics-kernel-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260908-0927-km-provenance-integrity-and-mojo-metrics-kernel-journal.md)
- **Sa-plan authority**: `uos/km-index-refresh/20260908-0912` (`km-index-refresh-20260908-0912`)
- **Contract**: `SC-PROVENANCE-001` · **Decision record**: `[[zk:20260908-0927-adr-087-provenance-integrity-km-gate-and-mojo-metrics-kernel]]`
- **Cycle chain**: `var/km/provenance-cycles.sqlite3`, 20 rows, `CHAIN_INTACT`
- **Scale**: major (15+ files)

---

## 1. Scope & Trigger

Operator prompt, accreted across nine mid-turn messages in one session: sync on
system state; extract key information from wiki, ZK and KM; **refresh the KM
indexes to ADR-086 with quarantine status marked**; review, sync and update all
system artifacts across SDLC, SRE, evidence, web UI, agentic surfaces (rules,
skills, superpowers, plugins, agents, hooks), TUI, docs, wiki, ZK and KM along
multidimensional vectors × fractal functionality × surfaces; create metrics and
measures; create checklist, docs, code and processes; use Mojo for
computationally intensive algorithms and custom AI/ML; embed as NIFs for Gleam
control; run 20 evolutionary cycles; wire everything; fast OODA loops with
prediction and forecasting; explain thinking and mindstate; state how
forecasting, probabilistic decision making, STM, Rete-UL, STPA and FMEA drive
convergence; use OpenRouter Gemma 4 to verify information; save prompt,
understanding, analysis and plan in a journal appended per cycle; keep the record
in SQL to prevent corruption; fractal TPS; fractal zero-muda; full symbiosis and
sync; update the message board and Zenoh for all changes.

The full prompt, the understanding derived from it, the analysis and the plan are
stored verbatim as cycle `C01` in the append-only store, per the operator's
instruction that they be journalled rather than only acted on.

## 2. Pre-State Assessment

| Surface | Observed before |
|---|---|
| ZK master MOC §2.0 | heading claimed `ADR-001..ADR-017`; listed 39 of 86 records (001–017, 047–068); 47 missing |
| Wiki corpus index §4.0 | listed 16 of 86; topology diagram asserted `ADR-001..ADR-016` |
| Round-O KM index | stopped at `ADR-064` |
| Quarantine markers | **0** on every surface |
| `AGENTS.md` §1 | "EV-01 through EV-99 admitted" |
| `AGENTS.md` §9 | `CURRENT EV-CYCLE: EV-108` — contradicting both §1 and its own caveat |
| `services/inference/max/max_kernel.mojo` | **does not compile** under Mojo 1.0.0 |
| Cycle journal | none; prior journals were flat files, corrupted in place three times on 2026-09-07 |
| Web `:4100` | 200, health ok, 16/16 containers, OTP 29, up 6h23m |
| Staged release `:59457` | 200 but malformed health body |
| `vm-1:8088` | connection refused though the node is online in the tailnet |

## 3. Execution Detail

Twenty cycles, `C01`..`C20`, each appended to `var/km/provenance-cycles.sqlite3`
through `tools/km-gate --append`.

| Cycle | Kind | Substance |
|---|---|---|
| C01 | mindstate | Prompt, understanding, analysis, plan, approach |
| C02 | observation | Runtime and VCS state |
| C03 | finding | Quarantine confirmed from the primary notes, not the summary |
| C04 | measurement | 86 ADRs enumerated; claims extracted from H1 titles only |
| C05 | baseline | Index staleness measured before any repair |
| C06 | decision | Preserve-not-rewrite; verified against Gemma 4 |
| C07 | change | ZK master MOC refreshed |
| C08 | change | Wiki corpus index refreshed |
| C09 | change | Round-O scoped, not rewritten |
| C10 | finding | Fractal layer taxonomy collapsed (1.306 bits) |
| C11 | build | Mojo 1.0 kernel; legacy kernel proven non-compiling |
| C12 | verification | 29/29 independent C oracle checks |
| C13 | build | C ABI NIF facade, Erlang shim, Gleam control |
| C14 | verification | NIF verified on OTP 27 and OTP 29 |
| C15 | verification | 10,640 Gleam tests green with 14 new laws |
| C16 | build | Append-only SQLite cycle journal, 4 falsifiers refused |
| C17 | finding | Zero-muda holds; a purity *claim* does not |
| C18 | change | `SC-PROVENANCE-001`, checklist Domain 6 |
| C19 | change | Coordinator and Zenoh updated via sanctioned channels only |
| C20 | closure | Convergence state and open items |

## 4. Root Cause Analysis

**Why the indexes drifted.** Index membership was maintained by hand, by whoever
authored each record. There was no check that the index was a function of the
corpus, so every author who skipped the step left a silent gap. 47 accumulated.

**Why the drift was dangerous rather than merely untidy.** Sixteen of the missing
or unmarked records assert ratification of EV cycles whose evidence is
quarantined. An index that lists them as ordinary decisions is an
evidence-laundering path: an agent reading the index cites `ADR-085`, and
`EV-108` re-enters the record as fact.

**Why the flat journal failed.** Nothing structurally prevented in-place
mutation. The 2026-09-07 incident overwrote events 417–419 destroying a lease
claim and two peer reports, and appended 422–432, using operations
(`publish_evidence`, `ratify_ev_cycle`) for which the `Command` type has no
constructor. The writer, not the store, was the only control.

**Why the status line contradicted itself.** The caveat was added additively (the
correct instinct — preserve the record) but the status line beneath it was left
untouched, so the file asserted and denied `EV-108` in two places.

## 5. Fix Taxonomy

| Class | Fix |
|---|---|
| **Derive, don't restate** | Indexes regenerated from the observed corpus; `admitted_ev_ceiling` is one constant every surface derives from |
| **Additive marking** | 16 records marked `NOT_ADMITTED`; zero ADR bodies modified |
| **Structural control** | Append-only SQLite with triggers: the store refuses mutation, not the writer |
| **Machine check** | `tools/km-gate`, six rules, `REPORT_ONLY` |
| **Fail-closed numerics** | Missing kernel ⇒ error, never a passing number |
| **Independent oracle** | Expected values computed in C from first principles |
| **Scoped, not rewritten** | Round-O got a banner and a forward pointer; its content is untouched |
| **Refusal** | No `EV-110`+ minted |

## 6. Patterns & Anti-Patterns Discovered

**Anti-pattern: the index that is not a function of its corpus.** If membership
is maintained by hand, drift is guaranteed and unbounded. The repair is not "be
more careful" but "make the check mechanical". Immediately demonstrated: adding
`ADR-087` made the gate report `KMP-INCOMPLETE` within seconds.

**Anti-pattern: marking the caveat but not the claim.** A correction added in one
section while the contradicted assertion survives elsewhere leaves the document
asserting both. Gemma 4 caught this independently.

**Anti-pattern: "pure Erlang" meaning "stubbed".** `graphene_nif.erl` satisfies
zero-muda literally (no foreign NIF) while implementing nothing:
`graph_shortest_path` returns cost 1.0 for any pair. A purity metric that counts
dependencies cannot see this.

**Pattern: the falsifier that fires on you.** The seed row inserted by hand
during the trigger test was later caught by `--verify-chain` as a content digest
mismatch. Rather than special-casing it, the store was retired to
`var/km/quarantine/` with a README and rebuilt through the sanctioned appender —
the same discipline the repository applies to foreign writes.

**Pattern: report the HOLD.** The gate's own verdict on this work is `HOLD`,
because layer entropy is 1.359 bits against a 2.50 floor. Publishing a `PASS` by
lowering the floor or dropping the check would reproduce the failure being fixed.

## 7. Verification Matrix

| Claim | Method | Result |
|---|---|---|
| Corpus completeness | `km-gate --metrics` | 87 records, `ADR-001..ADR-087`, contiguous, 0 duplicates |
| Master MOC completeness | `km-gate --gate` | 87/87, ratio 1.00 |
| Corpus index completeness | `km-gate --gate` | 87/87, ratio 1.00 |
| Quarantine marking | `km-gate --gate` | 16/16 on both surfaces |
| ADR bodies unmodified | no write to `docs/zk/*adr-0*` except the new ADR-087 | held |
| Mojo kernel correctness | independent C oracle | **29 checks, 0 failures** |
| NIF on system OTP | `erl` + `uos_km_nif:loaded()` | OTP 27, abi=1, values correct |
| NIF on cockpit OTP | nix `erl` OTP 29 | abi=1, values correct |
| Fail-closed path | run with `.so` absent | `{error, nif_not_loaded}` |
| Gleam suite | `gleam test` | **10,640 passed, 0 failed** |
| Cycle chain | `km-gate --verify-chain` | 20 rows, `CHAIN_INTACT` |
| Append-only falsifiers | 4 hostile writes | all refused by the store |
| Zero-muda | manifest scan | 0 declarations of bevy/graphite/graphene |
| Clock sync | `chronyc tracking` | NTP synced, offset 0.34 ms (nominal <2 s) |
| Risk gate | `risk-priority-check --active-check` | `ACTIVE_OBSERVATION_PASS`, 0 findings |
| Coordinator | `session_sync_cli` | events 582, 583 |
| Zenoh | `uos_swarm board post` + readback | delivered, key readable |
| Gate self-test | added ADR-087 unindexed | `KMP-INCOMPLETE` fired, then cleared |

## 8. Files Modified

**Created (12):** `contracts/rules/20260908-0912-provenance-integrity-contract.md`;
`docs/zk/20260908-0927-adr-087-...md`; `docs/wiki/20260908-0927-uos-provenance-integrity-and-km-gate-guide.md`;
this journal; `native/nifs/mojo/{uos_km_kernel.mojo,uos_km_nif.c,test_uos_km_kernel.c,Makefile}`;
`tools/km_provenance/{dune-project,dune,km_corpus.ml,km_metrics.ml,km_chain.ml,km_gate.ml}`;
`tools/km-gate`; `apps/cepaf_gleam/src/{uos_km_nif.erl,cepaf_km_ffi.erl}`;
`apps/cepaf_gleam/src/cepaf_gleam/km/provenance_metrics.gleam`;
`apps/cepaf_gleam/test/provenance_metrics_test.gleam`;
`governance/advisory/20260908-0912-gemma4-km-provenance-advisory.json`;
`var/km/provenance-cycles.sqlite3`; `var/km/km-provenance-board.jsonl`;
`var/km/quarantine/{20260908-0912-provenance-cycles-seeded.sqlite3,20260908-0912-README.txt}`.

**Modified (9):** `AGENTS.md` (§1 EV status, §1 caveat resolution, §9 status line);
`docs/zk/20260905-1801-moc-uos-unified-master.md`;
`docs/wiki/20260905-1801-uos-zk-km-corpus-index.md`;
`docs/wiki/20260907-1105-uos-km-index-round-o.md`;
`contracts/rules/comprehensive-checklist-contract.md` and its four mirrors under
`.claude/`, `.gemini/`, `.agents/`, `.codex/`.

**Preserved byte-for-byte:** all 86 pre-existing ADR bodies; all quarantined
coordinator events; Round-O content below its banner.

## 9. Architectural Observations

**The boundary is a scalar.** Reducing "update everything" to
`admitted_ev_ceiling = 93` is what made a gate possible. An open-ended
consistency requirement is unmeasurable; a predicate over one constant is not.

**Language placement matched shape, not preference.** Mojo took the SIMD
reduction; C took marshalling and bound-checking; Gleam took thresholds and
verdicts; OCaml took corpus observation and the digest chain; SQLite took
immutability. Each boundary is a type change, so each is a place to fail closed.

**Mojo 1.0 is a breaking release.** `fn` removed, `alias`→`comptime`, `math`/`sys`
moved under `std.`, `UnsafePointer`→`Pointer` with an explicit origin,
`simdwidthof`→`simd_width_of`. The shipped `.mojo` sources under `site-packages`
are the reliable reference; the prose documentation is stale. The pre-existing
kernel is a casualty of this and has been silently dead.

**Report-only is a feature.** `km-gate`, `risk-priority-check` and the board all
declare `authority: NONE` or `REPORT_ONLY`. In a repository whose central
incident was a writer claiming authority it did not have, tools that loudly
disclaim authority are the correct default.

## 10. Remaining Gaps

1. **`KMP-ENTROPY` open.** 68 of 87 ADRs tagged `#fractal-l0`; entropy 1.359 bits
   vs a 2.50 floor. Repair requires re-classification with the records' authors.
2. **`graphene_nif.erl` is a stub facade.** Policy claims graph operations are
   "implemented in pure Erlang/Gleam"; they are not.
3. **Staged release `:59457`** returns `{"error":"missing_field","field":"status"}`
   from `/api/health`. It must not be promoted off loopback in this state.
4. **`vm-1:8088` refuses connection** though the node is online in the tailnet.
5. **`tools/uos` CLI is documented but absent.** `tools/uos doctor`,
   `checklist`, `web-links`, `timestamp-check` are cited in `AGENTS.md` and three
   rule files; `tools/uos` is a Gleam package directory, not an executable.
6. **60 sibling jj workspaces**, one divergent change `nsknzutp`.
7. **Sovereign review of `EV-94`..`EV-109`** by Codex and AGY remains open.
8. **The cycle appender is invoked from a shell wrapper.** The store's triggers
   are the real control, but a supervised Gleam/OTP writer would be stronger.
9. **9-modality test protocol not re-observed.** Only the Gleam suite and the C
   oracle were run; the status line now says so rather than restating old counts.

## 11. Metrics Summary

| Measure | Before | After |
|---|---|---|
| ADR records enumerated, master MOC | 39 / 86 (0.453) | **87 / 87 (1.000)** |
| ADR records enumerated, corpus index | 16 / 86 (0.186) | **87 / 87 (1.000)** |
| Quarantine marking coverage | 0 / 16 (0.000) | **16 / 16 (1.000)** |
| Surface marking drift | 2.000 | **0.000** |
| Surface completeness drift | 1.721 | **0.000** |
| Fractal layer entropy (bits) | 1.306 | 1.359 (floor 2.50, **open**) |
| Mojo C-ABI exports | 0 (kernel non-compiling) | **6** |
| Independent oracle checks | 0 | **29 / 29** |
| Gleam tests | not re-observed | **10,640 / 0 failed** |
| Cycle chain rows | 0 | **20, `CHAIN_INTACT`** |
| Append-only falsifiers refused | n/a | **4 / 4** |
| Checklist domains | 5 (18 checks) | **6 (24 checks)** |
| Contract mirror digest parity | n/a | **5 / 5 identical** |
| EV numbers minted | — | **0 (deliberate)** |
| OpenRouter advisory cost | — | **USD 0.0000732** |

Both drift figures are Euclidean distances computed by the Mojo kernel over an
observed-vs-nominal vector across four surfaces (master MOC, corpus index,
Round-O, `AGENTS.md`), verified on OTP 29:

- *marking drift* over `[0,0,0,0]` against nominal `[1,1,1,1]` = `2.000`; after
  marking, `[1,1,1,1]` = `0.000`.
- *completeness drift* over `[0.453, 0.186, 0.0, 0.0]` = `1.721`; after
  regeneration, `0.000`.

The layer entropy figure `1.306` is likewise the kernel's own
`shannon_entropy_bits([68,5,4,3,2,1,1,1,1])`, agreeing with the OCaml gate's
independent computation to six decimal places. It rises to `1.359` once ADR-087
is counted.

## 12. STAMP & Constitutional Alignment

**Loss.** `L-KM-FORGED-EVIDENCE-PROPAGATION` — forged ratification claims
re-enter the record as fact through a trusted index.

**Hazards.** `H-KM-UNMARKED-QUARANTINE`, `H-KM-STALE-INDEX`.

**Controller / control action.** A knowledge-recall actor citing an ADR as
admission evidence.

**UCAs and the constraints now enforcing them:**

| UCA type | Context | Constraint | Enforced by |
|---|---|---|---|
| not provided | Records absent from the index are never surfaced | enumerate from the observed corpus | `KMP-INCOMPLETE` |
| provided unsafe | Quarantined records listed as ordinary decisions | every EV>93 claim carries `NOT_ADMITTED` | `KMP-UNMARKED` |
| wrong timing | Verdict frozen before sovereign review concludes | record `NOT_ADMITTED`, never admitted or rejected | `INV-PROV-02` |
| too long | Marking persists after review supersedes it | bind marking to task id and evidence path | `INV-PROV-05` |

**FMEA.** `FM-KM-001`: S4 O3 Det3, RPN 36, band 4 — verified by the Mojo kernel's
own `fmea_band(4,3,3) = 4` against the policy maxima `[5,15,35,70,125]`.

**Constitutional (L0).** Two-key verification is respected by *not* claiming it:
no EV cycle was admitted, and no new EV number minted. Zero-muda holds at the
manifest, with the stub-facade caveat recorded. Sa-plan remained sole execution
authority; the coordinator journal was written only through `session_sync_cli`.

**Fractal TPS.** *Jidoka* — the gate stops the line and reports `HOLD` rather
than passing degraded work. *Poka-yoke* — append-only triggers make the corrupting
action impossible rather than discouraged. *Muda* — 47 missing index entries and
a non-compiling kernel were pure waste, now removed. *Standardised work* —
`km-gate` has one schema and one canonical digest form. *Heijunka* — the 20
cycles were levelled into uniform append operations against one store.

## 13. Conclusion

The KM indexes now enumerate the full corpus and mark every quarantine-derived
record, the boundary that makes those markings meaningful is a single pinned
constant, and both properties are machine-checkable rather than asserted. The
numeric core runs in Mojo behind a bounded C ABI under Gleam control, verified by
an independent oracle on two OTP targets. The cycle record lives where in-place
corruption is refused by the store rather than by the writer.

The gate's verdict on this work is **`HOLD`**, on `KMP-ENTROPY`. That is the
honest result: the fractal layer taxonomy has collapsed to 1.359 bits and needs
re-classification by the records' authors, not a bulk retag by this session. No
EV cycle was admitted and no new EV number was minted, because two-key
verification is not satisfiable for the range under review — and minting numbers
during a forgery quarantine is precisely the failure mode being contained.
