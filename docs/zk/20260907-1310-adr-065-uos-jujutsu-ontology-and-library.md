20260907-1310-adr-065-uos-jujutsu-ontology-and-library
#fractal-l0 #fractal-l2 #fractal-l4 #zero-muda #tailscale-web #km-triad #rocha-semiotics #cybernetics #jujutsu #uos-tui #swarm

- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1310-adr-065-uos-jujutsu-ontology-and-library.md](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1310-adr-065-uos-jujutsu-ontology-and-library.md)

[[zk:20260907-1105-adr-064-uos-system-ontology-sutra-sangita-and-hive-cognition]] [[zk:20260907-0950-adr-063-uos-tui-and-swarm-work-stream-split]] [[zk:20260905-1801-moc-uos-unified-master]] [[wiki:20260905-1801-uos-zk-km-corpus-index]]

---

## ADR-065: UOS Jujutsu Ontology and Library

**Status**: Accepted

### Context

The UOS monorepo uses standalone, non-colocated Jujutsu (`.jj/`) as its sole VCS, per `CLAUDE.md §4`. Prior rounds (Sonnet workers in round J) designed and implemented:

1. **Jujutsu Library** (`jj.gleam`, 500+ lines): A typed, pure-Gleam client over the `jj` binary via `uos_jj_ffi.erl` (an Erlang `spawn_executable` port, never shell-escaped).
2. **Jujutsu Ontology**: A 28-concept vocabulary in the Version control domain (Sanskrit mapping change id → parivartana-nāma, commit id → sthāpita-sāra, etc.).
3. **VCS Discipline** (D1–D8): Eight machine-enforced rules (no native git mutation, readers never snapshot, main moves only with lease + decision record, integration is a linear rebased chain, workspaces created with explicit `--revision`, operations never edited only restored/undone, change ids ≠ commit ids, conflicts are first-class).
4. **Sūtras** (S2.8–S2.14): Seven Sanskrit aphorisms binding the Jujutsu ontology to the system's formal governance rules.

### Decision

**Admit** the Jujutsu library, ontology, discipline rules, and integrating sūtras into the UOS canonical knowledge base and supervision tree (`uos_swarm/holon.gleam`).

#### (a) Library: `jj.gleam`

- **Types**: `Repo`, `Change`, `Workspace`, `Operation`, `Bookmark`, `DiffStatEntry`, `Error`, `LeaseProof`, `DecisionRef`, `Revset`.
- **Public functions**:
  - **Open**: `open/1` (resolve `jj` on PATH).
  - **Revset builders**: `rev/1`, `main/0`, `at/0`, `expr/1`, `parents/1`, `ancestors/2`, `descendants/1`, `union/2`, `intersect/2`, `bookmarks_revset/0`, `heads_all/0`, `to_string/1`.
  - **Readers** (all via `guard_read/1`, passing `--ignore-working-copy`): `log/3`, `show/2`, `description_of/2`, `workspaces/1`, `operations/2`, `bookmarks/1`, `diff_stat/3`, `file_list/2`, `file_show/3`, `is_conflicted/2`.
  - **Writers**: `describe/3`, `new/3`, `rebase_source/4`, `squash_into/3`, `abandon/2`, `bookmark_set/3`, `workspace_add/3`, `workspace_forget/2`, `workspace_update_stale/2`, `op_restore/2`, `op_undo/1`.
  - **Guards**: `guard_read/1`, `move_main/5` (refuses without `LeaseProof` + `DecisionRef`), `integrate_chain/3` (linear rebase, stops at first conflict).
- **Discipline enforcement**: `discipline/0` (D1–D8 rules encoded as module invariants and function guards).
- **Test coverage**: 8 new tests against throwaway repos created with `jj git init --no-colocate` (verified no `.git` at root).
- **Live verification**: `guard-main-move main` dry-run on real repo answered "would: refuse, reason: no lease proof presented".

#### (b) Jujutsu Ontology

**28 VCS-domain concepts** (Sanskrit e.g., change id → **parivartana-nāma**; commit id → **sthāpita-sāra**; working copy → **kārya-pratilipi**; operation log → **kriyā-lekha**; bookmark → **saṅketa**; workspace → **kārya-kṣetra**; conflict → **virodha**; rebase → **punar-ādhāra**; squash → **saṅkoca**; snapshot → **kṣaṇa-citra**; undo → **pratyāvartana**; immutable → **acala**; VCS → **sañcaya-tantra**).

**Holon placement**: Under the structure plane (`uos/holon/L2/jujutsu`, Sanskrit **parivartana-tantra**), 34 holons total, 7 planes bijective to the 7 **svara-s**.

**Base rules** (B1–B9): All PASS.

#### (c) Sūtras S2.8–S2.14 (Seven Rules)

| id | Sanskrit | English | Rule |
|---|---|---|---|
| S2.8 | स्वतन्त्र निक्षेपः सहस्थानम् न | The repository stands alone; never co-located | Standalone, non-colocated `.jj/` |
| S2.9 | मूल गित्विकारः सर्वथा विवर्जितः | A native git mutation is barred outright | D1: no git mutation |
| S2.10 | परिवर्तनं नाम, स्थापनं सारः | Change is identity; commit is substance | D7: change id ≠ commit id |
| S2.11 | पठकः साधारणां कार्यप्रतिलिपिं न क्षणचित्रयति | A reader never snapshots a shared working copy | D2: `--ignore-working-copy` |
| S2.12 | मुख्यगमनं जीवत्पट्टेन निर्णयलेखेन च | Main moves only under live lease + decision record | D3: move_main guards |
| S2.13 | संयोजनं रेखाशृङ्खलया क्रमेण पुनराधीयते विरोधे तिष्ठति | Integration is linear chain, rebase in order; conflict stops it | D4: integrate_chain |
| S2.14 | क्रियाः पुनःस्थाप्यन्ते प्रत्यावर्त्यन्ते न कदापि सम्पाद्यन्ते | Operations are restored or undone, never edited | D6: op_restore, op_undo only |

### Consequences

1. **Supervision tree**: The holon `uos/holon/L2/jujutsu` (`parivartana-tantra`) becomes a live component of the UOS structure plane, owning the Jujutsu ontology and integrating it with L0 authority and the durable decision record ledger.

2. **Integration workflow**: Two-parent merges under coordinator lease epochs; worker workspaces start on fresh child changes; forget workspace before rebasing; readers never snapshot; main moves only with live lease + decision record.

3. **Process defects recorded in round J**:
   - Worker workspace `@` on an integrated change rewrote main's ancestry → new sūtra: worker workspaces start on fresh child change.
   - Prepared record file lost during recovery, regenerated → new pattern: snapshot record files immediately into tracked paths.
   - Change diverged three times under concurrent workspace snapshots → new pattern: forget worker workspace before rebasing its change.

4. **Formal gates**: `uos_tui` 198 tests, `uos_swarm` 486 tests, 0 warnings. Formal gates (lake/lean/quint) UNRUN on nas-1 (deferred). C04/C05 + KPI parked on `integration/candidates-c04-c05-pending` due to `action_boundary` test errors combined with C01's crash-safe journal.

5. **Knowledge integration**: Sūtras S2.8–S2.14 now part of the canonical sutra register (56 total across all 7 pāda-s); holon base rules B1–B9 PASS; VCS ontology (28 concepts) indexed in the master dictionary.

### Related

- `ADR-064`: System Ontology, Sūtra Sangita, and Hive Cognition.
- `ADR-063`: UOS TUI and Swarm Work Stream Split.
- `CLAUDE.md §4`: Jujutsu Standalone VCS Discipline.
- Library source: `apps/uos_swarm/src/uos_swarm/jj.gleam` (500+ lines, 8 tests).
- FFI: `uos_jj_ffi.erl` (pure Erlang `open_port`, no shell injection).
- CLI: `uos_jj_cli` (`log`, `workspaces`, `ops`, `bookmarks`, `show`, `stat`, `discipline`, `guard-main-move`, `integrate-chain`).

---

<details>
<summary>Comprehensive Verification Checklist (SC-CHECKLIST-001)</summary>

- [x] **CHK-01-TIME**: `20260907-1310-` prefix present.
- [x] **CHK-02-TAIL**: Tailscale FQDN link [http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1310-adr-065-uos-jujutsu-ontology-and-library.md](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1310-adr-065-uos-jujutsu-ontology-and-library.md).
- [x] **CHK-03-FRACT**: Tags `#fractal-l0` `#fractal-l4` applied.
- [x] **CHK-04-KM**: Transclusions `[[zk:...]]` `[[wiki:...]]` active.
- [x] **CHK-05-MUDA**: Zero-Muda: 0 Bevy, 0 Graphite (`jj.gleam` pure Gleam/Erlang).
- [x] **CHK-06-GRAPH**: No Graphene NIF, pure BEAM math.
- [x] **CHK-07-DRIVE**: Hardware Root Drive Interlock (locked NVMe serial).
- [ ] **CHK-08-C1C8**: (DECLARED) 8-Category Gold Standard in web/runtime context.
- [ ] **CHK-09-MATH**: (DECLARED) 4 Mathematical Gates verified at admission.
- [ ] **CHK-10-9MOD**: (DECLARED) 9-Modality Test Protocol 100% Green.
- [ ] **CHK-11-REGR**: (DECLARED) 381 UI Regression tests in continuous monitoring.
- [x] **CHK-12-GLEAM**: Gleam/OTP 29: `jj.gleam` owned by UOS swarm supervisor.
- [x] **CHK-13-HERMES**: Hermes OCaml: decision record ledger, Gospel contracts.
- [x] **CHK-14-ZIGVM**: ZigVM: Zettelkasten ADRs, sūtras, holon base rules.
- [x] **CHK-15-MAX**: Modular MAX/Mojo: isolated (not involved in VCS layer).
- [x] **CHK-16-OTEL**: OTP 29 Telemetry: C3I trace/span context.
- [x] **CHK-17-SOV**: Tri-sovereign review: Antigravity, Claude, Codex PASS.
- [x] **CHK-18-JJ**: Jujutsu standalone monorepo with 0 native Git mutations.

</details>

---

**Bottom navigation**: [← ZK Master MOC](http://nas-1.tail55d152.ts.net:4100/zk) | [Hermes Wiki Corpus Index →](http://nas-1.tail55d152.ts.net:4100/wiki)
