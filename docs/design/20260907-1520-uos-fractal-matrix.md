# 20260907-1520- UOS Fractal Matrix (generated)
#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zero-muda #tailscale-web #km-triad #rocha-semiotics #cybernetics #stamp-stpa #holon

- **Identifier**: `GEN-UOS-FRACTAL-MATRIX-001`
- **Timestamp**: `20260907-1520-`
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-1520-uos-fractal-matrix.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-1520-uos-fractal-matrix.md)
- **Carrier**: `generated/20260907-1520-uos-fractal-matrix.json` (`uos-fractal-matrix/v1`), regenerable by the shell pipeline embedded in that JSON's `generator` field
- **Governing design**: `docs/design/20260907-1505-uos-holonic-architecture-and-fractal-services-mapping-approach.md` (this document is its appendix)
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`
- **Method**: real, observed-repository data only — every cell below carries a `file:line` evidence pointer or an explicit `unassigned`/`none` marker. No guessed classification is presented as fact.

## Comprehensive Verification Checklist (SC-CHECKLIST-001)
<details><summary>18 checkpoints (this artifact's status)</summary>
CHK-01 PASS (`20260907-1520-` prefix) · CHK-02 PASS (Tailscale link above) · CHK-03 PASS (tags L0–L9) · CHK-04 PASS (zk/wiki transclusions) · CHK-05 PASS (0 Bevy/Graphite found by this scan) · CHK-06 DECLARED (graphene.gleam presence noted, §E) · CHK-07 N/A · CHK-08 N/A · CHK-09 N/A (this is a structural inventory, not a test run) · CHK-10 N/A · CHK-11 N/A · CHK-12 PASS (`uos_sup.gleam` supervision edges captured, §C) · CHK-13 DECLARED (Hermes modules aggregated, §A) · CHK-14 DECLARED (ZigVM src dirs aggregated, §A) · CHK-15 PASS (`max` subsystem enumerated, §B) · CHK-16 DECLARED (evidence carries `file:line`, not OTel trace context) · CHK-17 PENDING (tri-sovereign review of this generated artifact) · CHK-18 PASS (jj-only workflow, no git mutation used)
</details>

---

## A. Counts (layers × planes × subsystems × components × interactions × services)

```text
Fractal layers (L0..L9 + flat namespace)....... 11   (design doc §3.1 / §1.3 table)
Architectural planes (declared, holon.gleam).....  7   (control, structure, runtime, data, messaging, intelligence, language)
Subsystems scanned.............................. 94   (54 cepaf incl. cepaf.top, 2 indrajaal, 1 uos_swarm, 1 uos_tui,
                                                          26 hermes modules, 3 zigvm, 1 max, 1 tools, 4 native/nifs)
Components, per-file rows....................... 671   (cap was 800; not exceeded — see aggregation note below)
Components, aggregated rows..................... 30   (hermes 26 + zigvm 3 + tools 1 subsystems; folded to 1 summary
                                                          row each because per-file rows would have pushed the file
                                                          count past 800 — hermes alone holds 1,449 recursively-counted
                                                          .ml/.mli/.zig files across its 26 modules)
Aggregated files represented (not row-expanded). 1,449
Holons in holarchy() (apps/uos_swarm/.../holon.gleam) 34   (design doc's own text says "35"; this scan counted the
                                                          actual `Holon(` blocks in the source and found 34 — see §F)
17-aspect audit list (uos_tui/aspects.gleam)..... 17
Census process rows (external input)............ 113
Interaction rows (this report, capped/sampled)... 483   zenoh-key 159, route 212, supervisor-child 23, sa-plan 60 (of
                                                          496 production-file matches), ffi 15 (of 366 @external
                                                          declarations, top components by count), nif 6, board 8
Cross-cutting services tracked.................. 11   (10 grep-pattern services + testing-file-presence)
```

**Layer assignment rule applied** (stated explicitly, per instruction, rather than guessed):
- **Rule A (primary, evidence)**: for every subsystem, tally the literal `"indrajaal/l<n>/<domain>"` Zenoh-key string constants found in its own (non-test) source files; assign the layer/domain with the most occurrences (ties broken toward the lower layer number). 10 subsystems get a layer this way.
- **Rule B (secondary, declared fallback)**: if Rule A found nothing, assign a layer only when the subsystem's own directory basename is an *exact* match to one of the design doc's domain-plane keywords (`const,iam,secret→L0`; `atomic→L1`; `system,cpig,sync,sched→L4`; `cog,test→L5`; `eco→L6`; `fed,matrix,fmea→L7`; `otel,pi,kms,safety,moz→flat/no-layer`). 1 additional subsystem (`cepaf.kms`) gets a layer this way.
- **Otherwise: `unassigned`.** 83 of 94 subsystems (88%) are `unassigned` by this rule — this is not a scan failure, it is the same gap the governing design doc itself reports in its §2 gap table ("holarchy covers 35 of 113 process-level units; levels 4–9 have no holon") extended to the whole source tree: most of UOS's ~700 components carry no `indrajaal/l<n>/…` Zenoh-key literal and no directory name that matches a declared C3I domain keyword, so today there is no mechanical way to place them on the L0–L9 ladder without guessing.

**Plane assignment rule applied**: a *component* (not a subsystem) gets an architectural plane only when its filename (minus extension) exactly matches the base of a `holon.gleam` `module` field, restricted to the `uos_tui`/`uos_swarm` trees the holon actually names (see §B.holons and §F). 17 of 671 components qualify. No general C3I-domain → UOS-architectural-plane joining rule exists in the codebase (design doc §2, gap row "Two orthogonal taxonomies... without a joining rule", severity P2) so subsystem-level `plane` is reported as `unassigned` everywhere except where it can be inherited from a holon-linked component majority.

---

## B. Per layer L0..L9

### L0 — Constitutional (`const`, `iam`, `secret`)

5 subsystems assigned by Rule A.

| Subsystem | Domain (evidence) | Components | Census status (rolled up) |
|---|---|---|---|
| `cepaf.iam` | `iam` (12 zenoh-key hits, e.g. `apps/cepaf_gleam/src/cepaf_gleam/iam/pi_bridge.gleam:49`) | 19 | 2 rows: `imported-not-wired:1, integrated:1` |
| `cepaf.planning` | `const` (1 hit, `apps/cepaf_gleam/src/cepaf_gleam/planning/sa_plan_bridge.gleam:1034`) | 17 | 3 rows: `absent:2, imported-not-wired:1` |
| `cepaf.rules` | `const` (1 hit, `apps/cepaf_gleam/src/cepaf_gleam/rules/dispatcher.gleam:53`) | 3 | none matched |
| `cepaf.ui` | `const` (2 hits, e.g. `apps/cepaf_gleam/src/cepaf_gleam/ui/web/system_views.gleam:168`) | 201 | none matched |
| `cepaf.top` (loose files under `cepaf_gleam/`) | `secret` (6 hits, `vault_topics.gleam:22` etc.) | 25 | 6 rows: `absent:1, imp-not-wired:2, integrated:2, superseded:1` |

Components (file names), by subsystem:
```text
cepaf.iam (19):      freshness_monitor.gleam jwks_cache_actor.gleam key_rotation_actor.gleam
                      l0_constitutional.gleam l1_atomic.gleam l2_component.gleam l3_transaction.gleam
                      l4_system.gleam l5_cognitive.gleam l6_ecosystem.gleam l7_federation.gleam
                      lifecycle.gleam matrix.gleam nif_manager.gleam objects.gleam pi_bridge.gleam
                      scim_outbound_actor.gleam sts_token_cache_actor.gleam supervisor.gleam
cepaf.planning (17):  access_control.gleam chaya.gleam cli.gleam domain.gleam enforcer.gleam
                      graph_verification.gleam manager.gleam math_optimization.gleam nif.gleam
                      ooda.gleam orchestration.gleam parser.gleam repository.gleam safety_kernel.gleam
                      sa_plan_bridge.gleam task.gleam zenoh_adapter.gleam
cepaf.rules (3):      dispatcher.gleam engine.gleam stream.gleam
cepaf.top (25):       email_artifact_notify.gleam gemini_compute.gleam graphene.gleam iam.gleam
                      ignition_launch_request.gleam otp_app.gleam release.gleam render_cli.gleam
                      uos_sup.gleam vault_adc_token.gleam vault_audit_query.gleam
                      vault_audit_reconcile.gleam vault_audit_reconcile_io.gleam vault_gcp_sm.gleam
                      vault_gcp_sm_io.gleam vault.gleam vault_kek.gleam vault_kek_rotation.gleam
                      vault_kms.gleam vault_kms_io.gleam vault_migration.gleam vault_pii_scrub.gleam
                      vault_supervisor.gleam vault_sync_actor.gleam vault_topics.gleam
cepaf.ui (201):       (full 201-name list is in generated JSON `.subsystems[] | select(.id=="cepaf.ui").components`;
                      representative sample: agents.gleam auth_api.gleam bicameral.gleam cockpit_api.gleam
                      federation_api.gleam fmea_api.gleam health_api.gleam holon.gleam iam_api.gleam
                      kms_api.gleam mcp_api.gleam planning_api.gleam router.gleam secret_api.gleam
                      telemetry_api.gleam verification_api.gleam zenoh_api.gleam zk_decision_matrix.gleam)
```
No holon from `holarchy()` maps onto any of these 265 components (holon matching is scoped to `uos_tui`/`uos_swarm` only, §F).

### L1 — Atomic (`atomic`)

**0 subsystems assigned** by Rule A/B. The design doc places NIF runtimes and the ZigVM kernel at L1, but no subsystem's own source carries an `"indrajaal/l1/atomic"` literal as its *majority* domain (isolated single hits exist inside `cepaf.top`/`vault_topics.gleam:34` and `cepaf.ui`, both dominated by other layers there). `nifs.c`, `nifs.cpp`, `nifs.ocaml`, `nifs.rust`, `zigvm.src-root`, `zigvm.bifs`, `zigvm.substrate` — the subsystems the design doc *names* as L1 — carry no such literal at all (Zig and C/C++/OCaml NIF sources do not embed Gleam-side Zenoh-key strings), so they are honestly `unassigned` rather than force-labelled L1.

### L2 — Component / L3 — Transaction

**0 subsystems assigned.** The design doc itself documents L2 and L3 as "(documents only)" in its domain-plane table — i.e. no `indrajaal/l2/…` or `indrajaal/l3/…` Zenoh-key domain literal is used anywhere in the scanned source at all (grep confirms 0 occurrences of both). This scan corroborates that documented gap exactly.

### L4 — System (`system`, `cpig`, `sync`, `sched`)

3 subsystems assigned by Rule A.

| Subsystem | Domain (evidence) | Components |
|---|---|---|
| `cepaf.actors` | `cpig` (6 hits) | 6: `cpig_subscriber.gleam cpig_supervisor.gleam freshness_actor.gleam guard_grid_actor.gleam observer_actor.gleam pi_subscriber.gleam` |
| `cepaf.chrome` | `system` (6 hits, `apps/cepaf_gleam/src/cepaf_gleam/chrome/browser.gleam:92`) | 1: `browser.gleam` |
| `hermes.hermes_wiki` | `sre` (8 hits — a domain token used in code but **not** in the design doc's L0–L7 table; kept as evidence-based) | aggregated: 285 `.ml`/`.mli` files recursively |

### L5 — Cognitive (`cog`, `test`)

2 subsystems assigned by Rule A.

| Subsystem | Domain (evidence) | Components |
|---|---|---|
| `cepaf.gateway` | `cog` (3 hits) | 10: `bridge.gleam client.gleam codec.gleam config.gleam gchat.gleam http.gleam rooms.gleam telegram.gleam types.gleam whatsapp.gleam` |
| `cepaf.moz` | `cog` (5 hits, `apps/cepaf_gleam/src/cepaf_gleam/moz/vault.gleam:37`) | 4: `client.gleam planning.gleam system.gleam vault.gleam` |

### L6 — Ecosystem (`eco`) / L7 — Federation (`fed`, `matrix`, `fmea`)

**0 subsystems assigned.** `"indrajaal/l6/eco"` and `"indrajaal/l7/fed"`/`"indrajaal/l7/matrix"`/`"indrajaal/l7/fmea"` literals exist in the source (e.g. `apps/cepaf_gleam/src/cepaf_gleam/vault_topics.gleam:49,52` and `apps/cepaf_gleam/src/cepaf_gleam/iam/*.gleam`), but in every subsystem where they occur they are outnumbered by another layer's literals in the same subsystem (`cepaf.top` is majority-L0/`secret`; `cepaf.iam` is majority-L0/`iam` with only 10 of its 22 hits at L7/`fed`). No subsystem has L6 or L7 as its *majority* domain.

### L8 — Evolution / L9 — Cosmos

**0 subsystems assigned; 0 literal evidence of any kind.** The design doc names these two layers "for the first time" (§3.1) — they are a proposed extension, not yet used anywhere in the Zenoh-key namespace. `grep -rn '"indrajaal/l8/\|"indrajaal/l9/'` returns nothing. This is a genuine, machine-confirmed absence, consistent with the design doc's own admission.

### `flat` — non-layered C3I namespaces (`otel`, `pi`, `kms`, `safety`, `moz`)

1 subsystem assigned by Rule B: `cepaf.kms` (directory-basename exact match; component: `catalog.gleam`). `otel`, `pi`, `safety` have no subsystem whose *directory* is literally named that (their traffic lives inside other subsystems, e.g. `cepaf.observability` for `otel`, `cepaf.bridge/pi_agent.gleam` for `pi`), so per the stated rule they stay `unassigned` at the subsystem level even though the literal keys exist (see §C zenoh-key sample).

### Holon-linked components (holarchy levels 0–3, independent of the L0–L9 grep rule above)

`holarchy()` in `apps/uos_swarm/src/uos_swarm/holon.gleam` declares its own `level` field (0–3 observed) and a `Plane` (Control/Structure/Runtime/DataPlane/Messaging/Intelligence/Language) per holon. Matching holon `module` basenames against actual files in `uos_tui`/`uos_swarm` (the only two subsystems any holon names) finds 17 real links out of 34 holons and 59 components in those two subsystems:

```text
subsystem   file              holon_id        level  plane
uos_swarm   holon.gleam       planes          1      Structure
uos_swarm   coord.gleam       heartbeats      3      Control
uos_swarm   system_audit.gleam system-audit   2      Intelligence
uos_swarm   acl.gleam         lexicon         3      Language
uos_swarm   manager.gleam     manager         2      Intelligence
uos_swarm   stpa.gleam        stpa            2      Control
uos_swarm   board.gleam       board           2      Messaging
uos_swarm   jj.gleam          jujutsu         2      Structure
uos_swarm   ooda.gleam        ooda            3      Intelligence
uos_tui     render.gleam      render          3      Runtime
uos_tui     app.gleam         app             2      Runtime
uos_tui     fprime.gleam      fprime          2      Structure
uos_tui     headless.gleam    headless        2      Runtime
uos_tui     live.gleam        live            2      Runtime
uos_tui     aspects.gleam     aspects         2      Structure
uos_tui     ontology.gleam    ontology        2      Structure
uos_tui     widget.gleam      widgets         3      Runtime
```
See §F for the discovery that 8 of these 9 `uos_swarm` links declare `module: "uos_tui/<name>"` in `holon.gleam` even though the file only exists under `uos_swarm/` — a stale/aspirational module reference resolved here by filename, not by trusting the declared tree.

### `unassigned` (83 of 94 subsystems, 88%)

No `indrajaal/l<n>/<domain>` majority and no exact directory-basename match. Component counts include aggregated-subsystem file totals where applicable.

```text
subsystem_id                 tree        components   subsystem_id                 tree        components
cepaf.a2ui                   cepaf                9   cepaf.metabolic               cepaf                2
cepaf.adk                    cepaf                1   cepaf.nif                     cepaf                1
cepaf.agents                 cepaf                9   cepaf.observability           cepaf                1
cepaf.agui                   cepaf                7   cepaf.ontology                cepaf                1
cepaf.api                    cepaf                2   cepaf.podman                  cepaf                7
cepaf.auth                   cepaf                5   cepaf.prajna                  cepaf                7
cepaf.bridge                 cepaf               14   cepaf.sdlc                    cepaf                6
cepaf.c3i                    cepaf                2   cepaf.services                cepaf                4
cepaf.chaos                  cepaf                1   cepaf.smriti                  cepaf                2
cepaf.cockpit                cepaf                2   cepaf.substrate               cepaf                7
cepaf.config                 cepaf                2   cepaf.symbiosis               cepaf                2
cepaf.core                   cepaf                4   cepaf.telegram                cepaf                3
cepaf.crdt                   cepaf                2   cepaf.telemetry               cepaf                2
cepaf.db                     cepaf                5   cepaf.testing                 cepaf               15
cepaf.eventsource            cepaf                1   cepaf.tools                   cepaf                4
cepaf.fpp                    cepaf               16   cepaf.verification            cepaf               21
cepaf.fractal                cepaf                8   cepaf.web                     cepaf                1
cepaf.git                    cepaf                1   cepaf.zenoh                   cepaf                4
cepaf.ha                     cepaf               85   cepaf.zettelkasten            cepaf               10
cepaf.harness                cepaf                1   hermes.fetch_cowboy           hermes               1
cepaf.holon                  cepaf                1   hermes.gateway                hermes               0
cepaf.immune                 cepaf                4   hermes.hermes_agent_loop      hermes              48
cepaf.knowledge               cepaf              15   hermes.hermes_cli             hermes               0
cepaf.lifecycle               cepaf              1   hermes.hermes_dependability    hermes              80
cepaf.math                    cepaf              5   hermes.hermes_dune_graph       hermes               6
cepaf.mcp                     cepaf              3   hermes.hermes_fpp_authority    hermes               3
hermes.hermes_harness         hermes           247   hermes.hermes_harness_stubber  hermes               1
hermes.hermes_mirage          hermes            25   hermes.hermes_nix              hermes              33
hermes.hermes_ops_dashboard   hermes            85   hermes.hermes_ops              hermes             148
hermes.hermes_server          hermes             1   hermes.hermes_sqlite           hermes               0
hermes.hermes_stanza          hermes             2   hermes.hermes_sysml            hermes              18
hermes.hermes_toolchain       hermes             6   hermes.hermes_vcs              hermes              99
hermes.hermes_vision          hermes            75   hermes.hermes_zellij           hermes              19
hermes.sa_plan                hermes            52   hermes.swarm                   hermes              63
hermes.system_engg            hermes            37   hermes.tailscale_monitor       hermes               1
indrajaal.core                indrajaal          1   indrajaal.web                  indrajaal            1
max                           max                3   nifs.c                         nifs                 0
nifs.cpp                      nifs               0   nifs.ocaml                     nifs                 0
nifs.rust                     nifs              14   tools                          tools                9
uos_swarm                     uos_swarm         38   uos_tui                        uos_tui             21
zigvm.bifs                    zigvm             32   zigvm.src-root                 zigvm               67
zigvm.substrate                zigvm             6
```
`nifs.c`, `nifs.cpp`, `nifs.ocaml` show 0 because the single file each holds (`native/nifs/{c,cpp,ocaml}/*`) did not match the `-name "*.rs\|*.c\|*.cpp\|*.ml\|*.toml"` glob used for the `nifs` tree at `-maxdepth 3` in this run — a generator precision gap, see §F.

---

## C. Interactions table (source → target, `file:line` evidence)

483 rows total this run, by kind: `zenoh-key` 159, `route` 212, `supervisor-child` 23, `sa-plan` 60 (sampled, 1 per source file, from 496 production-file `sa_plan`/`sa-plan` line matches), `ffi` 15 (top components by `@external(erlang)` count, out of 366 total declarations, 391 including test files), `nif` 6, `board` 8. Full rows are in `generated/20260907-1520-uos-fractal-matrix.json` → `.interactions[]`.

### supervisor-child (23/23, complete)
```text
source                                                          target                       evidence (file:line)
UOSRootSupervisor                                               AppsSupervisor               uos_sup.gleam:69
UOSRootSupervisor                                                EnginesSupervisor            uos_sup.gleam:80
UOSRootSupervisor                                                ServicesSupervisor           uos_sup.gleam:86
UOSRootSupervisor                                                IntelligenceSupervisor       uos_sup.gleam:97
AppsSupervisor                                                    cepaf_gleam_wisp              uos_sup.gleam:73
AppsSupervisor                                                    indrajaal_holon_runtime       uos_sup.gleam:74
AppsSupervisor                                                    indrajaal_web                 uos_sup.gleam:75
EnginesSupervisor                                                 zigvm_port_manager            uos_sup.gleam:83
EnginesSupervisor                                                 hermes_oracle_supervisor      uos_sup.gleam:83
ServicesSupervisor                                                max_isolated_worker           uos_sup.gleam:90
ServicesSupervisor                                                mcp_unified_gateway           uos_sup.gleam:91
ServicesSupervisor                                                planning_worker                uos_sup.gleam:92
ServicesSupervisor                                                predictive_zenoh_stream        uos_sup.gleam:93
IntelligenceSupervisor                                            holon_swarm_mesh               uos_sup.gleam:100
IntelligenceSupervisor                                            lease_fencing_monitor          uos_sup.gleam:101
IntelligenceSupervisor                                            rete_ul_engine                 uos_sup.gleam:102
cepaf_gleam/uos_sup.gleam (sup.add)                                predictive_zenoh_stream        uos_sup.gleam:139
cepaf_gleam/iam/supervisor.gleam (sup.add)                         nif_manager                    supervisor.gleam:138
cepaf_gleam/iam/supervisor.gleam (sup.add)                         freshness_monitor              supervisor.gleam:139
cepaf_gleam/iam/supervisor.gleam (sup.add)                         jwks_cache_actor               supervisor.gleam:140
cepaf_gleam/iam/supervisor.gleam (sup.add)                         sts_token_cache_actor          supervisor.gleam:141
cepaf_gleam/iam/supervisor.gleam (sup.add)                         scim_outbound_actor            supervisor.gleam:142
cepaf_gleam/iam/supervisor.gleam (sup.add)                         key_rotation_actor             supervisor.gleam:143
```
Note: the top 16 rows come from `uos_sup.gleam`'s **declarative** `RootSupervisorSpec` (a list of strings, never turned into real `sup.add`/`static_supervisor` calls — confirms design doc gap "Root supervisor is declarative"). Only `iam/supervisor.gleam` and one `predictive_zenoh_stream` line under `uos_sup.gleam` itself use the real `sup.add(X.supervised())` pipeline; the other 5 `*_supervisor.gleam` files found (`vault_supervisor.gleam`, `unified_verification_supervisor.gleam`, `pi_supervisor.gleam`, `c3i_knowledge_supervisor.gleam`, `cpig_supervisor.gleam`) exist but this scan's `sup\.add\(...\.supervised\(\)\)` pattern found no matches inside them — either they use a different wiring idiom or are not yet wired (not determined further, see §F).

### nif (6/6, complete)
```text
apps/cepaf_gleam/src/c3i_nif.erl          erlang:load_nif  c3i_nif.erl:32
apps/cepaf_gleam/src/rusty_vault_nif.erl  erlang:load_nif  rusty_vault_nif.erl:27
apps/cepaf_gleam/src/rule_engine_nif.erl  erlang:load_nif  rule_engine_nif.erl:11
apps/cepaf_gleam/src/c3i_ocaml_nif.erl    erlang:load_nif  c3i_ocaml_nif.erl:22
apps/cepaf_gleam/src/planning_nif.erl     erlang:load_nif  planning_nif.erl:11
apps/cepaf_gleam/src/ferriskey_nif.erl    erlang:load_nif  ferriskey_nif.erl:85
```
`apps/cepaf_gleam/src/graphene_nif.erl` was found by the `*_nif.erl` glob (7 files total) but has **no** `erlang:load_nif(` call anywhere in it — it is present as source but never loads, consistent with the Zero-Muda policy that Graphene is "not required" (see §E).

### board (8/8, complete)
```text
apps/uos_swarm/src/uos_swarm.gleam        board.post  uos_swarm.gleam:162,185,563,634
apps/uos_swarm/src/uos_swarm/coord.gleam  board.post  coord.gleam:663,690,934,1079
```

### zenoh-key (15 of 159 shown)
```text
source              target                                                evidence
cepaf.observability  "indrajaal/otel/ops/"                                 zenoh_otel_ingestor.gleam:13
cepaf.moz            "indrajaal/l5/cog/mcp/req"                            client.gleam:73
cepaf.moz            "indrajaal/l5/cog/mcp/res"                            client.gleam:77
cepaf.moz            "indrajaal/l5/cog/mcp/query"                          client.gleam:81
cepaf.moz            "indrajaal/l5/cog/vault_moz"                          vault.gleam:37
cepaf.moz            "indrajaal/moz/planning"                              planning.gleam:17
cepaf.moz            "indrajaal/moz/system"                                system.gleam:16
cepaf.chrome         "indrajaal/l4/system/mcp/req/browser/screenshot"      browser.gleam:92
cepaf.chrome         "indrajaal/l4/system/mcp/req/browser/dom"             browser.gleam:105
cepaf.chrome         "indrajaal/l4/system/mcp/req/browser/diff"            browser.gleam:119
cepaf.chrome         "indrajaal/l5/cog/chrome/concept"                     browser.gleam:142
cepaf.chrome         "indrajaal/l5/cog/chrome/spec-verify"                 browser.gleam:143
cepaf.chrome         "indrajaal/l4/system/chrome/dev-feedback"             browser.gleam:144
cepaf.chrome         "indrajaal/l4/system/chrome/test"                     browser.gleam:145
cepaf.chrome         "indrajaal/l4/system/chrome/deploy-verify"            browser.gleam:146
```
Full 159 (and the 511 total non-test occurrences before subsystem-mapping / distinct-key dedup) are in the JSON. Not test-derived: interactions exclude anything under a `test/` directory by design (see §F).

### route (15 of 212 shown, from `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam`)
```text
"/"                        router.gleam:1067    "/agents"              router.gleam:4174
"/ag-ui/"                  router.gleam:3249    "/ag-ui/events"        router.gleam:660
"/ag-ui/health"            router.gleam:661     "/ag-ui/hitl/pending"  router.gleam:3498
"/ag-ui/hitl/respond"      router.gleam:4332    "/ag-ui/run"           router.gleam:660
"/ag-ui/state"             router.gleam:3503    "/ag-ui/tools/result"  router.gleam:4333
"/allium/"                 router.gleam:2421    "/api/"                router.gleam:3249
"/api/access/policy"       router.gleam:496     "/api/agents/hierarchy" router.gleam:521
"/api/bridge/status"       router.gleam:551
```

### ffi (top 15 of 15 by `@external(erlang)` count)
```text
apps/cepaf_gleam/src/cepaf_gleam/auth/ferriskey_nif.gleam       x31
apps/cepaf_gleam/src/cepaf_gleam/c3i/nif.gleam                  x30
apps/cepaf_gleam/src/cepaf_gleam/graphene.gleam                 x28
apps/uos_swarm/src/uos_swarm/board.gleam                        x15
apps/cepaf_gleam/src/cepaf_gleam/ha/hot_reload.gleam            x9
apps/cepaf_gleam/src/cepaf_gleam/substrate/beam_cache.gleam     x8
apps/cepaf_gleam/src/cepaf_gleam/substrate/database.gleam       x8
apps/cepaf_gleam/src/cepaf_gleam/planning/nif.gleam             x7
apps/uos_tui/src/uos_tui/live.gleam                             x6
apps/cepaf_gleam/src/cepaf_gleam/c3i/ocaml_nif.gleam            x5
apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/secret_api.gleam       x5
apps/uos_swarm/src/uos_swarm/clock_guard.gleam                  x5
apps/uos_swarm/src/uos_swarm/agent_runtime.gleam                x5
apps/cepaf_gleam/src/cepaf_gleam/auth/vault_bridge.gleam        x4
apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_daemon.gleam         x4
```

### sa-plan (10 of 60 sampled shown, 1 line per distinct source file)
```text
apps/cepaf_gleam/src/cepaf_gleam/ha/fmea_generator.gleam           fmea_generator.gleam:204
apps/cepaf_gleam/src/cepaf_gleam/ha/autonomous_capabilities.gleam  autonomous_capabilities.gleam:128
apps/cepaf_gleam/src/vault_smriti_ffi.erl                          vault_smriti_ffi.erl:34
engines/hermes/modules/swarm/dune                                  dune:85
engines/hermes/modules/hermes_wiki/import/c3i/skills/zk-recall/SKILL.md SKILL.md:12
apps/cepaf_gleam/src/cepaf_gleam/planning/manager.gleam             manager.gleam:33
apps/cepaf_gleam/COMPLETION_REPORT.md                               COMPLETION_REPORT.md:11
```

---

## D. Cross-cutting services matrix

Rows = subsystems with ≥1 real component (61 of 94; aggregated-only subsystems have no per-component service evidence in this run — see §F). Columns = the 11 cross-cutting services. Cell = count of components in that subsystem with ≥1 grep match (`-` = 0). Top 12 subsystems by total evidence hits shown here; the complete 61-row matrix is `generated/20260907-1520-uos-fractal-matrix.json` → `.services_by_subsystem`.

```text
subsystem            log  obs  sec  saf  clk  per  msg  pln  frm  knw  tst
cepaf.ui              8  112   31   25   34   33   72   38   19   31   66
cepaf.ha              18   45   11   18   42   43   49   32   14   50   82
uos_swarm              1   16   29   25   24   23   28   14    7   14   36
cepaf.top              6    6   20    7    5   17   15    7    2    5   19
cepaf.verification     3   10   14    5   10    8    8    5   11    8   14
cepaf.fpp              2   14    7    4    8    7    5    2    4    4   11
cepaf.planning         4    4    8    2    6    8    5   17    3    2    7
cepaf.testing          4   11    2    8    1    4   11    7    2    2   11
uos_tui                -   10    1    1    3    4    4    6    1    4   20
cepaf.bridge           5    8    4    2    4    8   12    1    2    2    4
cepaf.zettelkasten     4    5    5    1    3    9    5    3    5    5    9
cepaf.knowledge        3    8    4    3    5    8    5    1    2   15    9
```
(`log`=logging, `obs`=observability, `sec`=security, `saf`=safety, `clk`=clock, `per`=persistence, `msg`=messaging, `pln`=planning, `frm`=formal, `knw`=knowledge, `tst`=testing.)

Second matrix: rows = services, columns = layers (component-level evidence, using each component's own subsystem's assigned layer):

```text
service         l0   l1   l2   l3   l4   l5   l6   l7   l8   l9  flat  unassigned
logging         21    0    0    0    5    1    0    0    0    0     1          63
observability  128    0    0    0    6    4    0    0    0    0     0         175
security        79    0    0    0    0    2    0    0    0    0     0         127
safety          41    0    0    0    2    1    0    0    0    0     0          99
clock           47    0    0    0    4    2    0    0    0    0     1         156
persistence     61    0    0    0    3    2    0    0    0    0     0         153
messaging      100    0    0    0    5    8    0    0    0    0     1         182
planning        64    0    0    0    1    1    0    0    0    0     0         104
formal          25    0    0    0    2    0    0    0    0    0     0          62
knowledge       39    0    0    0    2    0    0    0    0    0     0         119
testing         99    0    0    0    6    8    0    0    0    0     1         263
```
L1/L2/L3/L6/L7/L8/L9 are all-zero here for the same reason §B reports 0 subsystems assigned to them: no subsystem's Rule-A/B layer is one of those values, so no component inherits it. The `unassigned` column dominates every row (63–263 of 671 components) — this is the single largest, most consistent finding of this matrix: **cross-cutting service evidence is abundant (thousands of grep hits) but almost none of it is currently attachable to a fractal layer**, because layer assignment itself is the bottleneck (§A rule, 88% unassigned), not the service detection.

---

## E. Gaps

Five largest, by evidence volume:

1. **88% of subsystems (83/94) have no mechanical L0–L9 layer assignment.** Root cause: the Zenoh-key `indrajaal/l<n>/<domain>` literal convention is only used in ~10% of subsystems' own source; most components (NIF/native, ZigVM, Hermes OCaml, most of `cepaf_gleam`'s ~50 other subsystems) never embed such a string. See §A/§B.
2. **276 of 671 components (41%) show zero interaction evidence** of any kind tracked here (no `@external(erlang)`, no `messaging`/`planning` service keyword match, not a `source` in any of the 483 sampled interaction rows). This is a components-with-no-detected-wiring count, not a claim they are dead code — some genuinely are pure/leaf modules (types, records), others may use interaction idioms this generator's patterns don't cover (see §F). Full list in `generated/...json` → `.gaps.components_no_interaction_evidence` (20-item sample embedded, count=276).
3. **Two subsystems (`cepaf.db`, `cepaf.eventsource`) show zero evidence across all four "core" services** (logging, observability, security, testing) — `cepaf.db` has 5 components, `cepaf.eventsource` has 1; neither a log call, a trace/span/metric keyword, an auth/vault/acl keyword, nor a same-named test file was found for any of their files.
4. **17 of 34 holons (50%) match no component at all**: `acl, control-plane, coord, data-plane, ets, intelligence-plane, language-plane, leases, ledger, messaging-plane, policy, runtime-plane, structure-plane, supervisor, uos, zenoh-router, zenoh-storage`. Most of these are the *abstract plane-holons* (`control-plane` … `language-plane`, level 1) and the *root* (`uos`, `supervisor`, level 0) which were never meant to be a single file; a few (`coord`'s `leases`/`policy` children, `board`'s `ledger`, `zenoh`'s `zenoh-router`/`zenoh-storage`) name operational concepts (`ops/zenoh`, lease acquire/renew/release inside `coord.gleam`) rather than standalone files, so "no component" is the honest, expected answer for them too.
5. **14 census rows with `uos_status: "absent"` match no subsystem at all** (of 23 total unmatched census rows): `sa-plan-tls.service`, `scripts-gleam@.service`, the 3 `spec-child:` entries from `uos_sup.gleam`'s declarative-only children (`zigvm_port_manager`, `hermes_oracle_supervisor`, `lease_fencing_monitor` — consistent with finding 1 in §C), `sa-plan` dashboard/proxy/socket ports, and 5 Python scripts (`e2e_ui_tester.py`, `generate_ui.py`, `run_tui.py`, `fix_gleam_warnings.py`, `exhaustive_parity_audit.py`) plus one Dockerfile — these are census-observed absences with no matching directory anywhere in the scanned trees, i.e. genuinely nowhere in source, not a matching-rule failure.

Additional, smaller gap: `graphene.gleam` (in `cepaf.top`) carries 28 `@external(erlang)` FFI declarations and `graphene_nif.erl` exists under `apps/cepaf_gleam/src/`, but the NIF file has **no** `erlang:load_nif(` call (§C/nif) — i.e. Graphene-adjacent FFI surface exists in source but is not wired to load, which this scan reads as consistent with (not a violation of) the "Graphene is not required" policy, though it warrants a human decision-record either way since Graphene and the barred Graphite are easily confused by name.

---

## F. What could not be determined

- **The exact number of holons in `holarchy()`.** The governing design doc's evidence-inputs line states "35 holons"; this scan's `awk` parse of the actual `Holon(...)` blocks in `apps/uos_swarm/src/uos_swarm/holon.gleam` (lines 113–533) counted 34. Not reconciled — either the doc is off by one or this parser mis-counts a block with an unusual layout; not independently re-verified beyond a second manual `grep -c "Holon($"` (also 34).
- **Whether the 8 `uos_swarm`-file holons that declare `module: "uos_tui/<name>"` (§B) are a documentation bug, an intentional aspirational rename not yet executed, or a naming collision this scan mis-resolved.** Resolved here purely by filename match to the *actual* file; not confirmed against any commit history or design intent.
- **Whether `vault_supervisor.gleam`, `unified_verification_supervisor.gleam`, `pi_supervisor.gleam`, `c3i_knowledge_supervisor.gleam`, `cpig_supervisor.gleam` register children.** They exist and are named as supervisors (found via `find -iname "*supervisor*.gleam"`) but the `sup\.add\([a-zA-Z_.]+\.supervised\(\)\)` pattern that worked for `iam/supervisor.gleam` found nothing in them — they may use `static_supervisor.add_child(...)` with a record literal instead of the `.supervised()` builder, which this generator's regex does not cover. Not manually inspected file-by-file.
- **Full recursive `nifs.{c,cpp,ocaml}` component coverage.** These three subsystems show `0` components (§B/unassigned table) because their single top-level file in each did not match the file-extension glob used (`*.rs|*.c|*.cpp|*.ml|*.toml` at `-maxdepth 3`); `nifs.c` and `nifs.cpp` likely hold a `.h`/header or a differently-named source file not covered by that glob. Not individually re-checked.
- **Whether the 276 "no interaction evidence" components (§E.2) are genuinely unwired or simply use an interaction idiom outside this generator's six patterns** (e.g. direct Erlang message passing, OTP `process.send`, a Gleam-native pub/sub not spelled `board.*`/`zenoh.*`). Not determined; would need a broader idiom survey.
- **The true file extent of `hermes.gateway`, `hermes.hermes_cli`, `hermes.hermes_sqlite`** (all report 0 aggregated files) — either these modules are empty stubs, contain only non-`.ml`/`.mli` files (e.g. `dune`, `.mll`, `.mly`), or the module directory itself is a placeholder. Not opened.
- **Census-to-subsystem linkage precision.** The substring-match rule (§A) is coarse by design and known to produce at least one false positive noted in the generator's own `undetermined` array (`hermes_fpp_authority` matching `cepaf.auth` via the substring `auth`). No manual correction pass was applied to the 46-subsystem census table in §B/appendix; treat it as first-pass triage, not ground truth.
- **Zero occurrences of the design doc's proposed `uos/l<n>/<domain>` Zenoh prefix** (SC-HOLON-NAME-001 target naming) — confirmed by direct grep (0 hits) but not further investigated as to whether any *non-string-literal* (e.g. dynamically constructed) key already uses it.

---

## Generator

The full, re-runnable shell pipeline (`find`/`grep`/`jq`/`awk`, no Python/Node) that produced every count and table above is embedded verbatim in `generated/20260907-1520-uos-fractal-matrix.json` under the top-level `generator` key. Invoke as `CENSUS=/path/to/census.json bash <(jq -r .generator generated/20260907-1520-uos-fractal-matrix.json)` from the workspace root to regenerate. One-line summary: it enumerates 94 subsystems across `apps/cepaf_gleam`, `apps/indrajaal_gleam_web`, `apps/uos_swarm`, `apps/uos_tui`, `engines/hermes/modules`, `engines/zigvm/src`, `services/inference/max`, `tools`, and `native/nifs`; extracts the 34-holon `holarchy()` and the 17-aspect list from Gleam source with hand-rolled `awk` block parsers; greps for `indrajaal/l<n>/<domain>` Zenoh-key literals to majority-vote a fractal layer per subsystem (falling back to an exact directory-basename match, else `unassigned`); greps for 10 cross-cutting service keyword families plus test-file presence per component; greps for Zenoh keys, `sup.add(...)` / declarative `RootSupervisorSpec` supervisor edges, HTTP routes, `erlang:load_nif` NIF loaders, `sa_plan`/`board.post` calls, and `@external(erlang)` FFI counts as interaction evidence; substring-matches the external 113-row process census against subsystem directory names; and assembles everything into one JSON document validated with `jq empty`.

---
Navigation: [ZK Master MOC](http://nas-1.tail55d152.ts.net:4100/zk) · [Hermes Wiki Corpus Index](http://nas-1.tail55d152.ts.net:4100/wiki) · [Governing Design](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-1505-uos-holonic-architecture-and-fractal-services-mapping-approach.md)
