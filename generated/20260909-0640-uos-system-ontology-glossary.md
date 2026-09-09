| IAST | Devanagari | English | Definition |
|---|---|---|---|
| abhisandhi | अभिसन्धि | Intent | A declared intent, rank-strict (must target L0/L1). |
| abhisandhi-utsarjana | अभिसन्धि-उत्सर्जन | emit_intent | STPA control action `emit_intent` dispatched by CTRL-TUI-APP. |
| acala-sthāpana | अचल-स्थापन | Immutable commit | A commit past the configured immutable boundary (e.g. already integrated); jj refuses to rewrite it, protecting shared history from silent mutation. |
| adhigrahaṇa | अधिग्रहण | Claim | An agent claims a task under a fenced lease. |
| adhigrahaṇa | अधिग्रहण | Claim | A lease on `task:<id>` subject to the swarm's WIP limit. |
| adhikāra | अधिकार | Hierarchical authority | Holon uos/holon/L3/control/policy (uos_tui/coord (authorize)), whole coord. |
| adhiṣṭhātṛ | अधिष्ठातृ | L0 design authority (Fable) | Holon uos/holon/L0/control/supervisor (uos_tui/coord (policy)), whole uos. |
| adhiṣṭhātṛ | अधिष्ठातृ | Design authority | Design decisions (Plan/Dispatch/Integrate/Andon broadcasts) come only from the design authority model roster. |
| adhyakṣa | अध्यक्ष | Gleam/OTP Root Supervisor | 17-aspect audit check #4: Gleam/OTP Root Supervisor. |
| ahaṃkāra | अहंकार | Ahaṃkāra (I-maker, self-model) | Ahaṃkāra is the sense of 'I'; maps onto the agent's self-model as posted on the board (Agent id/layer/model). |
| andhakāra | अन्धकार | Dark | Cockpit mode: minimum draw, only heartbeats. |
| annamaya | अन्नमय | Annamaya-kośa (matter sheath) | The gross material sheath; maps onto the hardware substrate and the BEAM VM it runs on. |
| antaḥkaraṇa | अन्तःकरण | Antaḥkaraṇa (inner instrument) | The fourfold inner instrument of cognition; maps onto the agent's cognitive stack end to end. |
| anujñā | अनुज्ञा | Grant | A scoped, expiring, opaque capability token minted only by L0/L1 and tracked as a board message. |
| anumana-yantra | अनुमान-यन्त्र | Modular MAX inference tier | Holon uos/holon/L2/intelligence/inference-max (services/inference/max), whole intelligence-plane. |
| anumāna | अनुमान | Anumāna (inference) | Inference from evidence; maps onto Rete forward-chaining rules and Bayesian belief updates. |
| atiprakriyā | अतिप्रक्रिया | Overprocessing | Muda: doing more work on a slice than the spec requires. |
| atyutpādana | अत्युत्पादन | Overproduction | Muda: producing more, sooner, or faster than the next station needs. |
| avalokana | अवलोकन | observe | OODA: gather the observation window (manas). |
| avarodha | अवरोध | Hold | The line-stopped state entered by jidoka when no_failures fails, pending a fix and sovereign review. |
| aviphala | अविफल | No-failures gate | The softer gate: zero Fail findings, Declared tolerated (used for jidoka stop/resume). |
| aṅga | अङ्ग | Widget | textual.widget.Widget -> uos_tui/widget.Widget(msg) (Homomorphic). class hierarchy becomes one closed sum type; state lives in the model |
| aṅga | अङ्ग | Widget catalog (17 families) | Holon uos/holon/L3/runtime/widgets (uos_tui/widget), whole app. |
| aṅga | अङ्ग | Part | One child holon id listed in a holon's `parts` field (`Holon.parts`); every part's `whole` must name this holon back (base rule B2) and every part's `level` must be at or above this holon's `level` (base rule B4). |
| aṅga-sopāna | अङ्ग-सोपान | Holarchy | The layered structure formed by holons nested through whole/part relationships across levels (`holon.holarchy()`), validated acyclic and level-monotonic by the nine core base rules B1..B9 (`holon.base_rules`). |
| bandhana | बन्धन | Binding / action | textual.binding.Binding -> uos_tui/widget.Binding(msg) (Isomorphic). key -> msg with description shown in Footer |
| bhāṣā-tala | भाषा-तल | Language plane | Holon uos/holon/L1/language/language-plane (uos_tui/acl), whole planes. |
| buddhi | बुद्धि | Buddhi (discerning intellect) | Buddhi discriminates and decides; maps onto the OODA Decide phase and manager.step's control decision. The intelligence plane's own Sanskrit name is buddhi-tala. |
| buddhi-tala | बुद्धि-तल | Intelligence plane | Holon uos/holon/L1/intelligence/intelligence-plane (uos_tui/manager), whole planes. |
| bīja-gaṇitīya-māpa-citra | बीज-गणितीय-माप-चित्र | Algebraic Atlas | The category-theoretic topology and sheaf cohomology model (H^1(Atlas, F) = 0) proving local-to-global intent gluing across fractal boundaries without inconsistency. |
| cakra | चक्र | Fast OODA controller | Holon uos/holon/L3/intelligence/ooda (uos_tui/ooda), whole manager. |
| calaka-patala | चालक-पटल | UOS TUI cockpit | Holon uos/holon/L2/runtime/uos-tui (apps/uos_tui), whole runtime-plane. |
| caturtha-śreṇī | चतुर्थ-श्रेणी | R4 bounded implementation | Bounded implementation: Sonnet. |
| citra-kāra | चित्र-कार | Compositor | textual._compositor -> uos_tui/render.compose/arrange (Homomorphic). placements blitted into a frame; no dirty-region diffing yet |
| citra-kāra | चित्र-कार | Compositor | Holon uos/holon/L3/runtime/render (uos_tui/render), whole app. |
| citrāṅkana | चित्राङ्कन | paint_frame | STPA control action `paint_frame` dispatched by CTRL-TUI-DRIVER. |
| citta | चित्त | Citta (mind-stuff, memory store) | Citta is the substrate that retains impressions; maps onto the agent's ETS live memory table. |
| citta-vṛtti | चित्त-वृत्ति | Citta-vṛtti (modifications of mind-stuff) | The five fluctuations of mind-stuff (Yoga Sūtra 1.6); maps onto the agent's cognitive/memory states. |
| cālaka | चालक | Driver | textual.driver -> uos_tui/live.run/child_spec (Homomorphic). OTP actor + reader process; raw mode via pure Erlang shell API |
| dattāṃśa-sāraṇī | दत्तांश-सारणी | DataTable | textual.widgets.DataTable -> uos_tui/widget.DataTable (Homomorphic). row cursor only |
| dattāṃśa-tala | दत्तांश-तल | Data plane | Holon uos/holon/L1/data/data-plane (uos_tui/board (ledger)), whole planes. |
| doṣa | दोष | Defects | Muda: rework caused by a verification failure that should have been caught earlier. |
| dvi-kuñcikā-satyāpana | द्वि-कुञ्चिका-सत्यापन | Two-key verification | Trust requires BOTH fresh observed runtime behaviour AND a machine-verifiable formal specification. |
| dvitīya-śreṇī | द्वितीय-श्रेणी | R2 docs/summaries | Docs/summaries: Haiku or OpenRouter nano. |
| dūra-mitī | दूर-मिती | Zenoh OoZ & MoZ Mesh Telemetry | 17-aspect audit check #10: Zenoh OoZ & MoZ Mesh Telemetry. |
| dṛṣṭi-śṛṅkhalā | दृष्टि-शृङ्खला | Focus chain | textual.screen.focus_chain -> uos_tui/app.move_focus (Isomorphic). document-order Tab/Shift-Tab |
| ekīkṛta-kārya-tantra | एकीकृत-कार्य-तन्त्र | Unified Operational System | Holon uos/holon/L0/control/uos (apps/uos_tui), whole (root). |
| gati | गति | Motion | Muda: unnecessary context switching or re-reading by an agent. |
| gati-kāla | गति-काल | Takt time | The target minutes per card that keeps the swarm at customer pace. |
| gaṇanā | गणना | Census | The 113-row daemon census that census-derived `Process`-kind holons mirror one-to-one (base rule B10, `holon.rule_b10`/`holon.b10_missing`), so every observed daemon names exactly one Process holon and vice versa. |
| gaṇita-adhikāra | गणित-अधिकार | Mathematical Authority & Conservation | 17-aspect audit check #7: Mathematical Authority & Conservation. |
| ghaṭanā-srota | घटना-स्रोत | AG-UI 32-Event SSE Stream | 17-aspect audit check #11: AG-UI 32-Event SSE Stream. |
| ghoṣita | घोषित | Declared | Bound by declaration/config, not fresh observed behaviour. |
| guṇa | गुण | Guṇa (the three qualities) | Sāṃkhya's three qualities, used here as a state classification for system health: sattva, rajas, tamas. |
| gṛhīta | गृहीत | Claimed | F´ lifecycle: claimed under a lease, not yet started. |
| hastākṣara | हस्ताक्षर | Signature | An HMAC over the message digest with a per-agent derived key; a shared master key never signs directly. |
| jala-yantra | जाल-यन्त्र | Indrajaal Gleam web | Holon uos/holon/L2/runtime/indrajaal-gleam-web (apps/indrajaal_gleam_web), whole runtime-plane. |
| jhunda | झुण्ड | UOS swarm package | Holon uos/holon/L2/messaging/uos-swarm (apps/uos_swarm), whole messaging-plane. |
| jñāna-trika | ज्ञान-त्रिक | Knowledge Management Triad | 17-aspect audit check #16: Knowledge Management Triad. |
| jāla-mārga-darśana | जाल-मार्ग-दर्शन | Universal Tailscale FQDN Web Navigation | 17-aspect audit check #14: Universal Tailscale FQDN Web Navigation. |
| jāla-sevā | जाल-सेवा | Textual Web / serve | textual-serve -> uos_tui/frame.to_text/to_ansi (Deferred). projection to Wisp at :4100 is a follow-on |
| jīrṇa-kārya-pratilipi | जीर्ण-कार्य-प्रतिलिपि | Stale working copy | A workspace's working copy that no longer matches its recorded commit because another process wrote to the shared repository; readers avoid provoking it against a workspace they do not own (`--ignore-working-copy`). |
| jīva-cālaka | जीव-चालक | OTP live driver | Holon uos/holon/L2/runtime/live (uos_tui/live), whole runtime-plane. |
| jīva-saṅketa-vijñāna | जीव-सङ्केत-विज्ञान | Biosemiotic Cybernetics & Rocha Cut | 17-aspect audit check #8: Biosemiotic Cybernetics & Rocha Cut. |
| jīvana-cakra | जीवन-चक्र | Lifecycle | The six-state biological holon lifecycle (Dormant/Awakening/Active/Stressed/Healing/Apoptotic, HOLON-LIFECYCLE) and its legal `holon.transition` state machine; census-derived holons start from `holon.lifecycle_from_status`. |
| jīvanta-vrnda-pāristhitiki | जीवन्त-वृन्द-पारिस्थितिकी | Living Swarm Ecology | Multi-agent cybernetic ecology (ADR-094, apps/cepaf_gleam/src/cepaf_gleam/ecology/) with harmonic song synthesis, capability ports, and decentralized work-stealing. |
| kaccā-praveśa | कच्चा-प्रवेश | enter_raw | STPA control action `enter_raw` dispatched by CTRL-TUI-DRIVER. |
| kalpanā | कल्पना | Hypothesize | Offers an unproven proposition for testing (the dream module's output). |
| karma-tantra | कर्म-तन्त्र | UOS operational units | Holon uos/holon/L2/runtime/ops (ops), whole runtime-plane. |
| kevala-yojana-rakṣā | केवल-योजन-रक्षा | Append-Only Trigger Defense | The fail-closed BEFORE INSERT triggers (*_no_replace) on cycle, ev_evidence, ev_verdict, merge_hold, and merge_hold_release that refuse SQLite REPLACE INTO even with recursive_triggers=OFF. |
| khaṇḍa | खण्ड | Segment / Strip | rich.segment / textual.strip -> uos_tui/segment.Strip (Isomorphic). styled runs with cached cell length; crop/extend/simplify |
| khaṇḍa-satyāpana | खण्ड-सत्यापन | verify_slice | STPA control action `verify_slice` dispatched by CTRL-SWARM-VERIFIER. |
| khaṇḍa-saṃyojana | खण्ड-संयोजन | integrate_slice | STPA control action `integrate_slice` dispatched by CTRL-SWARM-L0. |
| kośa | कोश | Sanskrit/English lexicon | Holon uos/holon/L3/language/lexicon (uos_tui/acl (lexicon)), whole acl. |
| kriyā | क्रिया | act | OODA: emit the chosen actions for this cycle. |
| kriyā-lekha | क्रिया-लेख | Operation log | The append-only ledger of every repository-mutating operation; the sole audit trail from which any prior state can be restored (BG 2.40: no effort is lost). |
| kriyā-punaḥsthāpana | क्रिया-पुनःस्थापना | Operation restore | Restoring the repository to an exact prior operation-log entry (`jj op restore`) — whole-repository time-travel, distinct from undoing a single change. |
| kāraṇa-antara | कारण-अन्तर | Causal gap | An explicit record documenting a reply target that is provably lost, so it never has to be forged or recreated. |
| kārmakara | कार्मकर | Worker | textual.worker -> uos_tui/app + uos_tui/live.Effect.Task (Homomorphic). task functions run in BEAM processes by the live driver |
| kārya-kṣetra | कार्य-क्षेत्र | Workspace | A checkout of the repository with its own working copy, sharing the same underlying `.jj/` operation log and store as its siblings. |
| kārya-pratilipi | कार्य-प्रतिलिपि | Working copy | The live checked-out files of a workspace, itself tracked as an ordinary (mutable) commit that jj auto-snapshots before every command. |
| kārya-smṛti | कार्य-स्मृति | Working memory | Namespace `working/`: scratch memory for the task in flight. |
| kārya-sīmā | कार्य-सीमा | WIP limit | The maximum number of cards a swarm may hold In Progress at once. |
| kāryarata | कार्यरत | Working | F´ lifecycle: actively being worked. |
| kṣaṇa-citra | क्षण-चित्र | Snapshot | The automatic recording of the working copy's current file state into the working-copy commit before every command runs, so nothing typed is ever silently lost. |
| kṣetra | क्षेत्र | Region/Size/Offset | textual.geometry -> uos_tui/geometry.Region (Isomorphic). half-open rectangles with intersection/union laws |
| laghu-rekhā | लघु-रेखा | Sparkline | textual.widgets.Sparkline -> uos_tui/widget.Sparkline (Isomorphic).  |
| lakṣya | लक्ष्य | Goal memory | Namespace `goal/`: the agent's current objectives. |
| lekhā | लेखा | Append-only JSONL ledger | Holon uos/holon/L2/data/ledger (uos_tui/board (jsonl)), whole data-plane. |
| manas | मनस् | Manas (sensing mind) | Manas gathers and filters sense-data; maps onto the OODA Observe phase. |
| manda | मन्द | Dim | Cockpit mode: low draw, occasional repaint. |
| manomaya | मनोमय | Manomaya-kośa (mind sheath) | The sheath of mind; maps onto the agents themselves and their OODA loops. |
| matam | मतम् | Belief memory | Namespace `belief/`: doxastic state the agent holds but has not asserted. |
| max-mojo-dvividha-cālaka | मैक्स-मोजो-द्विविध-चालक | MAX Mojo Dual-Surface Runner | Pure Mojo zero-bash runner (services/inference/max/uos_tui_webui_runner.mojo) separating component test examples from live integration verification, returning exit code 2 HOLD for unrun paths. |
| megha-smṛti | मेघ-स्मृति | Zenoh memory storages | Holon uos/holon/L2/data/zenoh-storage (ops/zenoh (storage_manager)), whole data-plane. |
| mukhya-saṅketa | मुख्य-सङ्केत | Main bookmark | The `main` bookmark, left uncreated until final system admission (EV-15); until then work proceeds only on feature and `integration/*` bookmarks. |
| mula-bija | मूल-बीज | Native bounded NIF kernels | Holon uos/holon/L1/runtime/native-nifs (native/nifs), whole runtime-plane. |
| mārga-darśaka | मार्ग-दर्शक | Zenoh router c3i-zenoh-router-1 | Holon uos/holon/L2/messaging/zenoh-router (ops/zenoh), whole messaging-plane. |
| mātrā | मात्रा | Scalar / fr units | textual.css.scalar -> uos_tui/layout.Scalar (Isomorphic). Cells, Fraction, Percent, Auto |
| mūla-yantra | मूल-यन्त्र | TEA application core | Holon uos/holon/L2/runtime/app (uos_tui/app), whole runtime-plane. |
| mūlya-sīmā | मूल्य-सीमा | Price ceiling | The highest per-token price (USD) accepted for an allowlisted model. |
| mṛta-patra | मृत-पत्र | DeadLetter | A message retried past its limit and dead-lettered. |
| navīna | नवीन | New | Creating a new, empty working-copy change on top of one or more parents (`jj new`), the usual way work begins. |
| nidrā | निद्रा | Nidrā (sleep) | The vṛtti of contentless sleep; maps onto an agent's Idle lifecycle line. |
| nirgama-peṭikā | निर्गम-पेटिका | Transactional outbox | Durable ledger acceptance gates publication: a message is Outboxed before any Zenoh put is attempted. |
| niryāyaka-nix | निर्यायक-निक्स | Determinate Nix | The sole toolchain provisioning authority (SC-NIX-DEVENV-001); supplies hermetic profile symlink farms under toolchains/nix-profile without ad-hoc host dependencies. |
| nirākaraṇa | निराकरण | Reject | Rejects a prior Request/Propose, with a reason. |
| nirṇaya | निर्णय | Verdict | A verifier's admit/reject decision. |
| nirṇaya | निर्णय | decide | OODA: choose the mode and actions (buddhi). |
| niyama | नियम | Rete (rule matcher) | Bounded forward-chaining matcher over typed facts (naive unification, not a full Rete network). |
| niyantrana-yantra | नियन्त्रण-यन्त्र | CEPAF Gleam control plane | Holon uos/holon/L2/control/cepaf-gleam (apps/cepaf_gleam), whole control-plane. |
| niyantraṇa-tala | नियन्त्रण-तल | Control plane | Holon uos/holon/L1/control/control-plane (uos_tui/coord), whole planes. |
| niyata-yantra | नियत-यन्त्र | ZigVM deterministic runtime | Holon uos/holon/L1/runtime/zigvm (engines/zigvm), whole runtime-plane. |
| niyata-yantra | नियत-यन्त्र | ZigVM Deterministic Engine & VFS Laws | 17-aspect audit check #5: ZigVM Deterministic Engine & VFS Laws. |
| niṣkriya | निष्क्रिय | Idle | F´ lifecycle: unclaimed, no lease held. |
| nāma-paṭṭikā | नाम-पट्टिका | Static/Label | textual.widgets.Static -> uos_tui/widget.Static (Isomorphic).  |
| parityāga | परित्याग | Abandon | Discarding a change (and rebasing its descendants onto its parent); recorded in the operation log and reversible by undo, never a silent deletion. |
| parivahana | परिवहन | Transport | Muda: unnecessary movement of work or artifacts between agents. |
| parivartana-cayana | परिवर्तन-चयन | Revset | A revset-language expression that selects a set of changes (by id, bookmark, ancestry, or predicate) for a command to act on. |
| parivartana-nāma | परिवर्तन-नाम | Change id | The stable identity of an edit across rewrites (rebase/squash/split change its content but never its change id) — the primary handle a worker or reviewer names. |
| parivartana-sthāpana-bheda | परिवर्तन-स्थापन-भेद | Change vs. commit | The fundamental Jujutsu distinction: change id is stable identity, commit id is a content hash of one revision of that identity — a worker must never equate the two. |
| parivartana-tantra | परिवर्तन-तन्त्र | Jujutsu version control | Holon uos/holon/L2/structure/jujutsu (uos_swarm/jj), whole structure-plane. |
| parīkṣaka | परीक्षक | Pilot / run_test | textual.pilot.Pilot -> uos_tui/headless.run (Isomorphic). scripted events, captured frames |
| parīkṣaka | परीक्षक | Headless pilot | Holon uos/holon/L2/runtime/headless (uos_tui/headless), whole runtime-plane. |
| parīkṣyamāṇa | परीक्ष्यमाण | Verifying | Kanban column: submitted, awaiting verification. |
| parīkṣyamāṇa | परीक्ष्यमाण | Verifying | F´ lifecycle: submitted, awaiting verification. |
| pañca-kośa | पञ्च-कोश | Pañca-kośa (the five sheaths) | The five sheaths from gross to subtle; maps onto the system's layers from hardware to admitted harmony. |
| pañca-stara-sulabhatā | पञ्च-स्तर-सुलभता | Penta-Stack Multi-Interface Accessibility | 17-aspect audit check #13: Penta-Stack Multi-Interface Accessibility. |
| pañcama-śreṇī | पञ्चम-श्रेणी | R5 sovereign review | Sovereign security/architecture review: Codex Astra and Antigravity. |
| paṭala | पटल | Screen | textual.screen.Screen -> uos_tui/app.Screen (Isomorphic). named view over the model; push/pop via PushScreen/PopScreen effects |
| paṭala-parīkṣā | पटल-परीक्षा | audit_screen | STPA control action `audit_screen` dispatched by CTRL-TUI-ASPECTS. |
| paṭṭa-niyantrita-mukhya-gamana | पट्ट-नियन्त्रित-मुख्य-गमन | Lease-gated main move | The rule that the `main` bookmark (once created) may move only under a live `integration/main` lease together with a recorded decision — never by an unaudited direct move (BG 18.63: full analysis offered, the choice remains the authority's). |
| paṭṭā | पट्टा | Fenced leases | Holon uos/holon/L3/control/leases (uos_tui/coord (acquire/renew/release)), whole coord. |
| paṭṭā | पट्टा | Lease | A fenced, time-bounded hold on a resource with a monotonically increasing epoch. |
| paṭṭā-anujñā | पट्टा-अनुज्ञा | LeaseGrant | Grant of a fenced lease/epoch. |
| paṭṭā-mukti | पट्टा-मुक्ति | LeaseRelease | Release of a held lease. |
| prabandhaka | प्रबन्धक | F´ managing agent | Holon uos/holon/L2/intelligence/manager (uos_tui/manager), whole intelligence-plane. |
| pragati | प्रगति | Progress | An in-flight progress update. |
| pragati-paṭṭī | प्रगति-पट्टी | ProgressBar | textual.widgets.ProgressBar -> uos_tui/widget.ProgressBar (Isomorphic).  |
| prakriya | प्रक्रिया | c3i.target | Holon uos/holon/L4/runtime/c3i-target (~/.config/systemd/user/c3i.target (installed; authoritative def not found as a tracked file in /home/an/dev/ver/c3i, host-local unit)), whole ops. |
| prakriya | प्रक्रिया | c3i-docs-server.service | Holon uos/holon/L4/runtime/c3i-docs-server-service (~/.config/systemd/user/c3i-docs-server.service), whole tools. |
| prakriya | प्रक्रिया | c3i-gleam-server.service | Holon uos/holon/L4/runtime/c3i-gleam-server-service (/home/an/NAS-setup/c3i/sa-gleam-start), whole cepaf-gleam. |
| prakriya | प्रक्रिया | c3i-health-publisher.service | Holon uos/holon/L4/runtime/c3i-health-publisher-service (gleam run -m scripts/sysd/health_publish), whole tools. |
| prakriya | प्रक्रिया | c3i-history-compactor.service | Holon uos/holon/L4/runtime/c3i-history-compactor-service (gleam run -m scripts/pass10/p10_history_compactor), whole tools. |
| prakriya | प्रक्रिया | c3i-iam-native-guard.service | Holon uos/holon/L0/runtime/c3i-iam-native-guard-service (/home/an/NAS-setup/c3i/scripts/systemd/c3i-user/iam-native-guard.sh), whole constitution. |
| prakriya | प्रक्रिया | c3i-muda-prune.service | Holon uos/holon/L4/runtime/c3i-muda-prune-service (gleam run -m scripts/sysd/muda_prune), whole tools. |
| prakriya | प्रक्रिया | c3i-ops-status.service | Holon uos/holon/L4/runtime/c3i-ops-status-service (gleam run -m scripts/pass10/p10_ops_status), whole tools. |
| prakriya | प्रक्रिया | c3i-pi-runtime.service | Holon uos/holon/L4/runtime/c3i-pi-runtime-service (node packages/coding-agent/dist/cli.js --provider google --mode rpc (Pi-mono)), whole cepaf-gleam. |
| prakriya | प्रक्रिया | c3i-pressure-publisher.service | Holon uos/holon/L4/runtime/c3i-pressure-publisher-service (gleam run -m scripts/sysd/pressure_publish), whole tools. |
| prakriya | प्रक्रिया | c3i-rete-autofix.service | Holon uos/holon/L5/runtime/c3i-rete-autofix-service (gleam run -m scripts/pass10/p10_rete_autofix), whole hermes. |
| prakriya | प्रक्रिया | c3i-robustness-gate.service | Holon uos/holon/L4/runtime/c3i-robustness-gate-service (gleam run -m scripts/pass10/p10_robustness_gate), whole tools. |
| prakriya | प्रक्रिया | c3i-sa-plan-cortex.service | Holon uos/holon/L4/runtime/c3i-sa-plan-cortex-service (/home/an/NAS-setup/c3i/sa-plan daemon), whole hermes. |
| prakriya | प्रक्रिया | c3i-sa-plan-default-scheduler.service | Holon uos/holon/L4/runtime/c3i-sa-plan-default-scheduler-service (sa-plan scheduler-run --queue default --limit 8 --interval 2), whole tools. |
| prakriya | प्रक्रिया | c3i-sa-plan-http.service | Holon uos/holon/L4/runtime/c3i-sa-plan-http-service (sa-plan serve --port 4200), whole indrajaal-gleam-web. |
| prakriya | प्रक्रिया | c3i-sa-plan-inference.service | Holon uos/holon/L5/runtime/c3i-sa-plan-inference-service (sa-plan inference-serve --sock %t/c3i/inference.sock), whole inference-max. |
| prakriya | प्रक्रिया | c3i-slo-guard.service | Holon uos/holon/L4/runtime/c3i-slo-guard-service (gleam run -m scripts/pass10/p10_slo_guard), whole tools. |
| prakriya | प्रक्रिया | c3i-sutra.service | Holon uos/holon/L7/runtime/c3i-sutra-service (gleam run (Sutra Matrix/federation server, sub-projects/sutra)), whole tools. |
| prakriya | प्रक्रिया | c3i-symbiosis-monitor.service | Holon uos/holon/L4/runtime/c3i-symbiosis-monitor-service (gleam run -m scripts/pass9/p9_symbiosis_monitor), whole tools. |
| prakriya | प्रक्रिया | c3i-tls-proxy.service | Holon uos/holon/L4/runtime/c3i-tls-proxy-service (sa-plan tls serve --https-port 8443 --http-port 8088), whole cepaf-gleam. |
| prakriya | प्रक्रिया | c3i-zenoh-router.service (alt/:8000) | Holon uos/holon/L4/runtime/c3i-zenoh-router-service-alt-8000 (~/.config/systemd/user/c3i-zenoh-router.service; podman run ... --rest-http-port 8000), whole ops. |
| prakriya | प्रक्रिया | c3i-zenoh-router-1.service | Holon uos/holon/L4/runtime/c3i-zenoh-router-1-service (~/.config/systemd/user/c3i-zenoh-router-1.service; podman start c3i-zenoh-router-1 (docker.io/eclipse/zenoh)), whole ops. |
| prakriya | प्रक्रिया | sa-plan-tls.service (deploy packaging) | Holon uos/holon/L4/runtime/sa-plan-tls-service-deploy-packaging (/home/an/dev/ver/c3i/sub-projects/c3i/deploy/systemd/sa-plan-tls.service), whole tools. |
| prakriya | प्रक्रिया | scripts-gleam@.service / .timer (template) | Holon uos/holon/L4/runtime/scripts-gleam-service-timer-template (/home/an/dev/ver/c3i/sub-projects/scripts-gleam/deploy/systemd/scripts-gleam@.{service,timer}), whole tools. |
| prakriya | प्रक्रिया | openclaw-auth-monitor.service | Holon uos/holon/L4/runtime/openclaw-auth-monitor-service (/home/an/dev/ver/c3i/sub-projects/openclaw/scripts/systemd/openclaw-auth-monitor.service), whole tools. |
| prakriya | प्रक्रिया | openclaw-auth-monitor.timer | Holon uos/holon/L4/runtime/openclaw-auth-monitor-timer (same dir, .timer), whole tools. |
| prakriya | प्रक्रिया | uos-clock-guard@.service | Holon uos/holon/L0/runtime/uos-clock-guard-service (~/.config/systemd/user/uos-clock-guard@.service; UOS copy at ops/observability/20260907-0941-uos-clock-guard@.service), whole constitution. |
| prakriya | प्रक्रिया | uos_sup.gleam root supervisor | Holon uos/holon/L4/runtime/uos-sup-gleam-root-supervisor (apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | spec-child: cepaf_gleam_wisp | Holon uos/holon/L4/runtime/spec-child-cepaf-gleam-wisp (uos_sup.gleam AppsDomain child (string only)), whole cepaf-gleam. |
| prakriya | प्रक्रिया | spec-child: indrajaal_holon_runtime | Holon uos/holon/L4/runtime/spec-child-indrajaal-holon-runtime (uos_sup.gleam AppsDomain child (string only)), whole tools. |
| prakriya | प्रक्रिया | spec-child: indrajaal_web | Holon uos/holon/L4/runtime/spec-child-indrajaal-web (uos_sup.gleam AppsDomain child (string only)), whole indrajaal-gleam-web. |
| prakriya | प्रक्रिया | spec-child: zigvm_port_manager | Holon uos/holon/L4/runtime/spec-child-zigvm-port-manager (uos_sup.gleam EnginesDomain child (string only)), whole zigvm. |
| prakriya | प्रक्रिया | spec-child: hermes_oracle_supervisor | Holon uos/holon/L5/runtime/spec-child-hermes-oracle-supervisor (uos_sup.gleam EnginesDomain child (string only)), whole hermes. |
| prakriya | प्रक्रिया | spec-child: max_isolated_worker | Holon uos/holon/L4/runtime/spec-child-max-isolated-worker (uos_sup.gleam ServicesDomain child (string only)), whole uos-swarm. |
| prakriya | प्रक्रिया | spec-child: mcp_unified_gateway | Holon uos/holon/L5/runtime/spec-child-mcp-unified-gateway (uos_sup.gleam ServicesDomain child (string only)), whole tools. |
| prakriya | प्रक्रिया | spec-child: planning_worker | Holon uos/holon/L4/runtime/spec-child-planning-worker (uos_sup.gleam ServicesDomain child (string only)), whole cepaf-gleam. |
| prakriya | प्रक्रिया | spec-child: holon_swarm_mesh | Holon uos/holon/L4/runtime/spec-child-holon-swarm-mesh (uos_sup.gleam IntelligenceDomain child (string only)), whole uos-tui. |
| prakriya | प्रक्रिया | spec-child: lease_fencing_monitor | Holon uos/holon/L4/runtime/spec-child-lease-fencing-monitor (uos_sup.gleam IntelligenceDomain child (string only)), whole tools. |
| prakriya | प्रक्रिया | spec-child: rete_ul_engine | Holon uos/holon/L5/runtime/spec-child-rete-ul-engine (uos_sup.gleam IntelligenceDomain child (string only)), whole hermes. |
| prakriya | प्रक्रिया | cepaf_gleam.gleam main/0 | Holon uos/holon/L4/runtime/cepaf-gleam-gleam-main-0 (apps/cepaf_gleam/src/cepaf_gleam.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | cepaf_gleam/agents/cybernetic executive supervisor | Holon uos/holon/L4/runtime/cepaf-gleam-agents-cybernetic-executive-supervisor (apps/cepaf_gleam/src/cepaf_gleam/agents/cybernetic.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | unified_verification_supervisor.gleam | Holon uos/holon/L4/runtime/unified-verification-supervisor-gleam (apps/cepaf_gleam/src/cepaf_gleam/verification/unified_verification_supervisor.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | c3i_knowledge_supervisor.gleam | Holon uos/holon/L4/runtime/c3i-knowledge-supervisor-gleam (apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_supervisor.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | pi_supervisor.gleam | Holon uos/holon/L4/runtime/pi-supervisor-gleam (apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_supervisor.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | cpig_supervisor.gleam | Holon uos/holon/L4/runtime/cpig-supervisor-gleam (apps/cepaf_gleam/src/cepaf_gleam/actors/cpig_supervisor.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | iam/supervisor.gleam | Holon uos/holon/L0/runtime/iam-supervisor-gleam (apps/cepaf_gleam/src/cepaf_gleam/iam/supervisor.gleam), whole constitution. |
| prakriya | प्रक्रिया | vault_supervisor.gleam | Holon uos/holon/L0/runtime/vault-supervisor-gleam (apps/cepaf_gleam/src/cepaf_gleam/vault_supervisor.gleam), whole constitution. |
| prakriya | प्रक्रिया | ha/supervisor_config.gleam | Holon uos/holon/L4/runtime/ha-supervisor-config-gleam (apps/cepaf_gleam/src/cepaf_gleam/ha/supervisor_config.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | prajna/circuit_breaker.gleam | Holon uos/holon/L4/runtime/prajna-circuit-breaker-gleam (apps/cepaf_gleam/src/cepaf_gleam/prajna/circuit_breaker.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | ha/lyapunov_proof.gleam | Holon uos/holon/L4/runtime/ha-lyapunov-proof-gleam (apps/cepaf_gleam/src/cepaf_gleam/ha/lyapunov_proof.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | ha/freshness_monitor.gleam | Holon uos/holon/L4/runtime/ha-freshness-monitor-gleam (apps/cepaf_gleam/src/cepaf_gleam/ha/freshness_monitor.gleam), whole cepaf-gleam. |
| prakriya | प्रक्रिया | fractal/l0_constitutional.gleam | Holon uos/holon/L0/runtime/fractal-l0-constitutional-gleam (apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam), whole constitution. |
| prakriya | प्रक्रिया | services/stan_worker (stub) | Holon uos/holon/L4/runtime/services-stan-worker-stub (services/stan_worker/README.md), whole tools. |
| prakriya | प्रक्रिया | services/rule_engine_worker (stub) | Holon uos/holon/L5/runtime/services-rule-engine-worker-stub (services/rule_engine_worker/README.md), whole tools. |
| prakriya | प्रक्रिया | services/solver_worker (stub) | Holon uos/holon/L4/runtime/services-solver-worker-stub (services/solver_worker/README.md), whole tools. |
| prakriya | प्रक्रिया | apps/indrajaal_gleam (library) | Holon uos/holon/L4/runtime/apps-indrajaal-gleam-library (apps/indrajaal_gleam/{gleam.toml,manifest.toml,README.md}), whole indrajaal-gleam-web. |
| prakriya | प्रक्रिया | indrajaal_gleam_web Mist HTTP listener :4100 | Holon uos/holon/L4/messaging/indrajaal-gleam-web-mist-http-listener-4100 (apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam:988-990 (mist.new/port/bind)), whole indrajaal-gleam-web. |
| prakriya | प्रक्रिया | cepaf_gleam web/server.gleam Mist HTTP listener | Holon uos/holon/L4/messaging/cepaf-gleam-web-server-gleam-mist-http-listener (apps/cepaf_gleam/src/cepaf_gleam/web/server.gleam:1228-1230), whole cepaf-gleam. |
| prakriya | प्रक्रिया | cepaf_gleam web/server.gleam Mist HTTPS listener | Holon uos/holon/L4/messaging/cepaf-gleam-web-server-gleam-mist-https-listener (apps/cepaf_gleam/src/cepaf_gleam/web/server.gleam:1243-1245), whole cepaf-gleam. |
| prakriya | प्रक्रिया | Zenoh router TCP:7447 / REST:8080 | Holon uos/holon/L4/messaging/zenoh-router-tcp-7447-rest-8080 (c3i-zenoh-router-1 podman container (docker.io/eclipse/zenoh); config ops/zenoh/20260907-0450-uos-zenoh-router-1.json5), whole ops. |
| prakriya | प्रक्रिया | Zenoh router REST:8000 (alt) | Holon uos/holon/L4/messaging/zenoh-router-rest-8000-alt (c3i-zenoh-router.service (non -1 variant)), whole tools. |
| prakriya | प्रक्रिया | sa-plan HTTP dashboard :4200 | Holon uos/holon/L4/messaging/sa-plan-http-dashboard-4200 (c3i-sa-plan-http.service), whole tools. |
| prakriya | प्रक्रिया | sa-plan TLS proxy :8443/:8088 | Holon uos/holon/L4/messaging/sa-plan-tls-proxy-8443-8088 (c3i-tls-proxy.service), whole tools. |
| prakriya | प्रक्रिया | sa-plan inference UDS socket | Holon uos/holon/L5/messaging/sa-plan-inference-uds-socket (c3i-sa-plan-inference.service, %t/c3i/inference.sock), whole tools. |
| prakriya | प्रक्रिया | MCP stdio servers (zigvm_harness --mcp, hermes_ops mcp) | Holon uos/holon/L5/messaging/mcp-stdio-servers-zigvm-harness-mcp-hermes-ops-mcp (/home/an/dev/ver/zigvm ... zigvm_harness.exe --mcp; /home/an/NAS-setup/harness-bionic/_build/.../hermes_ops/ops_main.exe mcp), whole hermes. |
| prakriya | प्रक्रिया | AG-UI SSE stream /ag-ui/events | Holon uos/holon/L4/messaging/ag-ui-sse-stream-ag-ui-events (apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam router ('ag-ui' path branch calling cepaf_gleam/ui/wisp/router as c3i_router)), whole cepaf-gleam. |
| prakriya | प्रक्रिया | max_worker.py | Holon uos/holon/L5/runtime/max-worker-py (services/inference/max/max_worker.py), whole uos-swarm. |
| prakriya | प्रक्रिया | max_kernel.mojo | Holon uos/holon/L5/intelligence/max-kernel-mojo (services/inference/max/max_kernel.mojo), whole inference-max. |
| prakriya | प्रक्रिया | e2e_ui_tester.py | Holon uos/holon/L4/runtime/e2e-ui-tester-py (/home/an/dev/ver/c3i/e2e_ui_tester.py), whole tools. |
| prakriya | प्रक्रिया | generate_ui.py | Holon uos/holon/L4/runtime/generate-ui-py (/home/an/dev/ver/c3i/generate_ui.py), whole tools. |
| prakriya | प्रक्रिया | run_tui.py | Holon uos/holon/L4/runtime/run-tui-py (/home/an/dev/ver/c3i/run_tui.py), whole uos-tui. |
| prakriya | प्रक्रिया | fix_gleam_warnings.py | Holon uos/holon/L4/runtime/fix-gleam-warnings-py (/home/an/dev/ver/c3i/fix_gleam_warnings.py), whole tools. |
| prakriya | प्रक्रिया | exhaustive_parity_audit.py | Holon uos/holon/L4/runtime/exhaustive-parity-audit-py (/home/an/dev/ver/c3i/scripts/exhaustive_parity_audit.py), whole tools. |
| prakriya | प्रक्रिया | mcp/c3i_server (Rust) | Holon uos/holon/L5/runtime/mcp-c3i-server-rust (/home/an/dev/ver/c3i/sub-projects/c3i/mcp/c3i_server (Cargo [[bin]])), whole tools. |
| prakriya | प्रक्रिया | mcp/timestamp_sync (Rust) | Holon uos/holon/L5/intelligence/mcp-timestamp-sync-rust (/home/an/dev/ver/c3i/sub-projects/c3i/mcp/timestamp_sync), whole hermes. |
| prakriya | प्रक्रिया | native/wireframe_renderer (Rust) | Holon uos/holon/L1/runtime/native-wireframe-renderer-rust (/home/an/dev/ver/c3i/sub-projects/c3i/native/wireframe_renderer), whole native-nifs. |
| prakriya | प्रक्रिया | native/planning_daemon (Rust) | Holon uos/holon/L1/runtime/native-planning-daemon-rust (/home/an/dev/ver/c3i/sub-projects/c3i/native/planning_daemon), whole native-nifs. |
| prakriya | प्रक्रिया | native/ignition_daemon (Rust) | Holon uos/holon/L1/runtime/native-ignition-daemon-rust (/home/an/dev/ver/c3i/sub-projects/c3i/native/ignition_daemon), whole native-nifs. |
| prakriya | प्रक्रिया | ferriskey-vendored/operator (Rust) | Holon uos/holon/L0/runtime/ferriskey-vendored-operator-rust (/home/an/dev/ver/c3i/sub-projects/ferriskey-vendored/operator (Cargo [[bin]])), whole constitution. |
| prakriya | प्रक्रिया | rusty_vault_vendored (Rust, source of rusty_vault_nif.so) | Holon uos/holon/L0/runtime/rusty-vault-vendored-rust-source-of-rusty-vault-nif-so (/home/an/dev/ver/c3i/sub-projects/rusty_vault_vendored), whole constitution. |
| prakriya | प्रक्रिया | graphene_nif Rust crate (lib/cepaf_gleam/native/graphene_nif) | Holon uos/holon/L1/runtime/graphene-nif-rust-crate-lib-cepaf-gleam-native-graphene-nif (/home/an/dev/ver/c3i/lib/cepaf_gleam/native/graphene_nif (Cargo [[bin]]/cdylib wrapping graphene/tiny-skia/kurbo/resvg/plotters/vega-lite/petgraph crates)), whole native-nifs. |
| prakriya | प्रक्रिया | graphite-editor (Bevy-based Rust desktop editor) | Holon uos/holon/L1/runtime/graphite-editor-bevy-based-rust-desktop-editor (/home/an/dev/ver/c3i/lib/cepaf_gleam/native/graphite-editor/desktop (+ platform/linux, platform/mac, platform/win Cargo.toml)), whole native-nifs. |
| prakriya | प्रक्रिया | indrajaal_ark (Rust) | Holon uos/holon/L1/runtime/indrajaal-ark-rust (/home/an/dev/ver/c3i/sub-projects/c3i/lib/indrajaal_ark (Cargo.toml)), whole tools. |
| prakriya | प्रक्रिया | indrajaal_ark_zig (Zig) | Holon uos/holon/L1/runtime/indrajaal-ark-zig-zig (/home/an/dev/ver/c3i/sub-projects/c3i/lib/indrajaal_ark_zig/src/main.zig), whole zigvm. |
| prakriya | प्रक्रिया | indrajaal_env_checker (Rust) | Holon uos/holon/L1/runtime/indrajaal-env-checker-rust (/home/an/dev/ver/c3i/sub-projects/c3i/src/rust/indrajaal_env_checker), whole tools. |
| prakriya | प्रक्रिया | indrajaal_web (Elixir/Phoenix, legacy) | Holon uos/holon/L4/runtime/indrajaal-web-elixir-phoenix-legacy (/home/an/dev/ver/c3i/sub-projects/c3i/lib/indrajaal_web/{endpoint,router,presence,telemetry,guardian,gettext,rate_limiter,connection_tracker,open_api,unified_controller_patterns}.ex), whole indrajaal-gleam-web. |
| prakriya | प्रक्रिया | hermes_harness (incl. hermes_rete.ml + compiled Zenoh C-stub) | Holon uos/holon/L5/intelligence/hermes-harness-incl-hermes-rete-ml-compiled-zenoh-c-stub (engines/hermes/modules/hermes_harness/{hermes_rete.ml,.mli,.gospel, dune}; compiled dllhermes_harness_hermes_zenoh_stubs.so), whole hermes. |
| prakriya | प्रक्रिया | hermes_dependability (dune, dependability_clock.ml) | Holon uos/holon/L5/intelligence/hermes-dependability-dune-dependability-clock-ml (engines/hermes/modules/hermes_dependability/dune), whole hermes. |
| prakriya | प्रक्रिया | tailscale_monitor (dune exe) | Holon uos/holon/L5/intelligence/tailscale-monitor-dune-exe (engines/hermes/modules/tailscale_monitor/dune), whole hermes. |
| prakriya | प्रक्रिया | hermes_server (dune exe) | Holon uos/holon/L5/intelligence/hermes-server-dune-exe (engines/hermes/modules/hermes_server/dune), whole hermes. |
| prakriya | प्रक्रिया | hermes_ops (dune exe, ops_main.exe mcp) | Holon uos/holon/L5/intelligence/hermes-ops-dune-exe-ops-main-exe-mcp (engines/hermes/modules/hermes_ops/dune), whole hermes. |
| prakriya | प्रक्रिया | hermes_mirage (dune exe) | Holon uos/holon/L5/intelligence/hermes-mirage-dune-exe (engines/hermes/modules/hermes_mirage/dune), whole hermes. |
| prakriya | प्रक्रिया | hermes_vision (dune exe) | Holon uos/holon/L5/intelligence/hermes-vision-dune-exe (engines/hermes/modules/hermes_vision/dune), whole hermes. |
| prakriya | प्रक्रिया | hermes_wiki tools+frontend (dune exe) | Holon uos/holon/L5/intelligence/hermes-wiki-tools-frontend-dune-exe (engines/hermes/modules/hermes_wiki/src/{tools,frontend}/dune), whole hermes. |
| prakriya | प्रक्रिया | hermes_ops_dashboard (dune exe) | Holon uos/holon/L5/intelligence/hermes-ops-dashboard-dune-exe (engines/hermes/modules/hermes_ops_dashboard/dune), whole hermes. |
| prakriya | प्रक्रिया | hermes_zellij (dune exe) | Holon uos/holon/L5/intelligence/hermes-zellij-dune-exe (engines/hermes/modules/hermes_zellij/dune), whole hermes. |
| prakriya | प्रक्रिया | hermes_sysml (dune exe) | Holon uos/holon/L5/intelligence/hermes-sysml-dune-exe (engines/hermes/modules/hermes_sysml/dune), whole hermes. |
| prakriya | प्रक्रिया | swarm (dune module) | Holon uos/holon/L5/runtime/swarm-dune-module (engines/hermes/modules/swarm/dune), whole uos-swarm. |
| prakriya | प्रक्रिया | hermes tooling modules (toolchain/nix/vcs/fpp_authority/dune_graph/harness_stubber/fetch_cowboy/sa_plan test) | Holon uos/holon/L5/intelligence/hermes-tooling-modules-toolchain-nix-vcs-fpp-authority-dune-graph-harness-stubber-fetch-cowboy-sa-plan-test (engines/hermes/modules/{hermes_toolchain,hermes_nix,hermes_vcs,hermes_fpp_authority,hermes_dune_graph,hermes_harness_stubber,fetch_cowboy}/dune, engines/hermes/modules/sa_plan/test/dune), whole hermes. |
| prakriya | प्रक्रिया | ferriskey_nif | Holon uos/holon/L0/runtime/ferriskey-nif (apps/cepaf_gleam/src/ferriskey_nif.erl -> priv/ferriskey_nif.so), whole constitution. |
| prakriya | प्रक्रिया | c3i_ocaml_nif | Holon uos/holon/L1/runtime/c3i-ocaml-nif (apps/cepaf_gleam/src/c3i_ocaml_nif.erl -> priv/c3i_ocaml_nif.so), whole native-nifs. |
| prakriya | प्रक्रिया | rule_engine_nif | Holon uos/holon/L1/runtime/rule-engine-nif (apps/cepaf_gleam/src/rule_engine_nif.erl -> priv/rule_engine_nif.so), whole native-nifs. |
| prakriya | प्रक्रिया | planning_nif | Holon uos/holon/L1/runtime/planning-nif (apps/cepaf_gleam/src/planning_nif.erl -> priv/native/planning_nif.so), whole native-nifs. |
| prakriya | प्रक्रिया | c3i_nif | Holon uos/holon/L1/runtime/c3i-nif (apps/cepaf_gleam/src/c3i_nif.erl -> priv/c3i_nif.so), whole native-nifs. |
| prakriya | प्रक्रिया | graphene_nif (loader) | Holon uos/holon/L1/runtime/graphene-nif-loader (apps/cepaf_gleam/src/graphene_nif.erl), whole native-nifs. |
| prakriya | प्रक्रिया | rusty_vault_nif | Holon uos/holon/L0/runtime/rusty-vault-nif (apps/cepaf_gleam/src/rusty_vault_nif.erl -> priv/rusty_vault_nif.so), whole constitution. |
| prakriya | प्रक्रिया | containers/Dockerfile.precompiled | Holon uos/holon/L6/runtime/containers-dockerfile-precompiled (/home/an/dev/ver/c3i/containers/Dockerfile.precompiled (also under sub-projects/c3i/containers/)), whole tools. |
| prakriya | प्रक्रिया | containers/signoz docker-compose (observability stack) | Holon uos/holon/L6/runtime/containers-signoz-docker-compose-observability-stack (/home/an/dev/ver/c3i/containers/signoz/docker-compose.yml), whole tools. |
| prakriya | प्रक्रिया | sub-projects/c3i Dockerfile.* cluster (db, sil4-db, sil4-app, sil4-obs, cortex, kms-catalog, cepaf-bridge, mojo, fix, sopv51-app, sopv51-app-hardened, sopv51-base) | Holon uos/holon/L6/runtime/sub-projects-c3i-dockerfile-cluster-db-sil4-db-sil4-app-sil4-obs-cortex-kms-catalog-cepaf-bridge-mojo-fix-sopv51-app-sopv51-app-hardened-sopv51-base (/home/an/dev/ver/c3i/sub-projects/c3i/Dockerfile.* (12 files)), whole tools. |
| prakriya | प्रक्रिया | ferriskey-vendored containers + k8s manifests | Holon uos/holon/L6/runtime/ferriskey-vendored-containers-k8s-manifests (/home/an/dev/ver/c3i/sub-projects/ferriskey-vendored/{Dockerfile, charts/ferriskey/templates/{api,webapp}/deployment.yaml, charts/ferriskey/templates/postgresql/statefulset.yaml, operator/k8s/deployment.yaml}), whole tools. |
| prakriya | प्रक्रिया | openclaw containers + k8s manifest | Holon uos/holon/L6/runtime/openclaw-containers-k8s-manifest (/home/an/dev/ver/c3i/sub-projects/openclaw/{Dockerfile, Dockerfile.sandbox*, docker-compose.yml, scripts/k8s/manifests/deployment.yaml, scripts/e2e/Dockerfile*}), whole tools. |
| prakriya | प्रक्रिया | tools/sa-plan (OCaml sa_plan_main.exe) | Holon uos/holon/L5/intelligence/tools-sa-plan-ocaml-sa-plan-main-exe (tools/sa-plan (bash wrapper) -> engines/hermes/_build/default/modules/sa_plan/test/sa_plan_main.exe; live DB at var/sa-plan/uos.sqlite3), whole hermes. |
| prakriya | प्रक्रिया | k8s-lab Rust CLI (render/kube_apply/spec) | Holon uos/holon/L6/runtime/k8s-lab-rust-cli-render-kube-apply-spec (/home/an/NAS-setup/k8s-lab/src/{main.rs,spec.rs,render.rs,kube_apply.rs}), whole ops. |
| prakāśa | प्रकाश | Bright | Cockpit mode: elevated cadence plus an aspect audit. |
| pramana-yantra | प्रमाण-यन्त्र | Hermes OCaml evidence engine | Holon uos/holon/L2/intelligence/hermes (engines/hermes), whole intelligence-plane. |
| pramāṇa | प्रमाण | Pramāṇa (valid means of knowledge) | The four accepted means of valid cognition; maps onto the system's evidence sources for two-key verification. |
| pramāṇa | प्रमाण | Pramāṇa (valid cognition) | Valid cognition grounded in perception/inference/testimony; maps onto a verified, Pass-admitted evidence state. |
| pramāṇa-sākṣya | प्रमाण-साक्ष्य | Hermes Formal Evidence & Gospel | 17-aspect audit check #6: Hermes Formal Evidence & Gospel. |
| prasaṅga-smṛti | प्रसङ्ग-स्मृति | Episodic memory | Namespace `episodic/<id>`: a remembered board message. |
| prastāva | प्रस्ताव | Propose | Proposes a feasible action for the receiver to accept or reject. |
| prathama-śreṇī | प्रथम-श्रेणी | R1 mechanical verification | Mechanical verification: script, else Haiku. |
| prathamataḥ-niḥśulka | प्रथमतः-निःशुल्क | Free-first | Free tiers are tried before any paid model; free-only is the default policy. |
| pratijñā | प्रतिज्ञा | Assert | Asserts a known proposition into the shared ledger. |
| pratikriyā | प्रतिक्रिया | reactive | textual.reactive -> uos_tui/app.update -> render (Reinterpreted). every message re-renders; watchers become update clauses |
| pratyakṣa | प्रत्यक्ष | Pratyakṣa (perception) | Direct perception; maps onto observed runtime behaviour, the first key of two-key verification. |
| pratyāhāra | प्रत्याहार | Retract | Withdraws a previously asserted proposition. |
| pratyāvartana | प्रत्यावर्तन | Undo | Reversing the most recent operation-log entry (`jj undo`); operations are always restored or undone, never hand-edited in place. |
| pratīkṣā | प्रतीक्षा | Waiting | Muda: idle time while a card sits blocked on another resource. |
| pravartaka-punaḥsthāpana | प्रवर्तक-पुनःस्थापना | restore_terminal | STPA control action `restore_terminal` dispatched by CTRL-TUI-DRIVER. |
| pravartamāna | प्रवर्तमान | Running | Kanban column: actively being worked. |
| pravartana-tala | प्रवर्तन-तल | Runtime plane | Holon uos/holon/L1/runtime/runtime-plane (uos_tui/live), whole planes. |
| praveśa | प्रवेश | Input | textual.widgets.Input -> uos_tui/widget.Input (Homomorphic). no validators/suggester |
| praśna | प्रश्न | Question | A question posted to another agent. |
| praśna | प्रश्न | Query | Asks the receiver to Inform on a proposition. |
| preṣaka-śṛṅkhalā | प्रेषक-शृङ्खला | Per-sender digest chain | One SHA-256 hash chain per sender (multi-writer safe), ordered by id within the sender. |
| preṣaṇa | प्रेषण | Dispatch | L0/L1 dispatch of work to an agent. |
| prākṛta-git-vikāra | प्राकृत-गिट्-विकार | Native git mutation | Any direct Git-mutating command (`git commit`, `git push`, `git checkout`, etc.); strictly prohibited inside the standalone UOS repository regardless of tooling convenience. |
| prārthanā | प्रार्थना | Request | Requests the receiver to accept or reject doing an action. |
| prāṇa-lakṣaṇa | प्राण-लक्षण | Vitals | The optional observed-liveness record on a holon (`heartbeat_age_s`, `restarts`, `last_transition`, `holon.Vitals`) -- distinct from the census-derived `lifecycle` classification, which is a one-shot snapshot, not a live poll. |
| prāṇamaya | प्राणमय | Prāṇamaya-kośa (vital-breath sheath) | The sheath of vital energy; maps onto running BEAM processes and the OTP supervisor. |
| punar-ādhāra | पुनराधार | Rebase | Replaying a change (and its descendants) onto a new parent, producing new commit ids while preserving change ids; the mechanism by which integration serializes worker changes in order. |
| puṣṭi | पुष्टि | Confirm | Confirms a belief the receiver was uncertain of. |
| puṣṭi-paṭala-preṣaṇa | पुष्टि-पटल-प्रेषण | push_confirm_screen | STPA control action `push_confirm_screen` dispatched by CTRL-TUI-APP. |
| pātra | पात्र | Container | textual.containers -> uos_tui/widget.Container, Grid (Isomorphic). border + title like Textual border-title |
| pūrṇa | पूर्ण | Whole | The optional parent holon id a holon names as its whole (`Holon.whole`); `None` only for the root (`uos`); reciprocated by the parent's `parts` list under base rule B2. |
| racanā | रचना | compose() | Widget.compose -> uos_tui/app.Screen.view (Isomorphic). pure function model -> tree |
| rajas | रजस् | Rajas (activity) | Active, restless quality; maps onto churn — high Progress/Dispatch traffic on the board. |
| rekhā | रेखा | Rule | textual.widgets.Rule -> uos_tui/widget.Rule (Isomorphic).  |
| rekhā-śṛṅkhala-saṃyojana | रेखा-शृङ्खला-संयोजन | Linear-chain integration | The integration pattern by which verified worker changes are rebased onto the integration bookmark one after another, in order, rather than merged concurrently; a conflict stops the chain. |
| rāga | राग | Rāga (melodic framework) | A melodic framework of specific notes, phrases and mood used by the music module. |
| sahasthita-nikṣepa | सहस्थित-निक्षेप | Colocated repository | A `.jj/` repository backed by a sibling `.git/` directory; permitted by upstream Jujutsu but strictly barred inside `/home/an/NAS-setup/uos`. |
| sahodara-kārya-kṣetra | सहोदर-कार्य-क्षेत्र | Sibling workspace | One of the `.uos-workspaces/*` peer workspaces used for parallel work streams (e.g. this worker's `jj-2`); each owns a disjoint file scope (BG 3.35, svadharma). |
| samagra-sūcī-patra | समग्र-सूची-पत्र | Comprehensive Verification Checklist | 17-aspect audit check #15: Comprehensive Verification Checklist. |
| samanvaya | समन्वय | Coordination & sync | Holon uos/holon/L2/control/coord (uos_tui/coord), whole control-plane. |
| samanvaya | समन्वय | Reconcile | Merge a remote view of the board into the local one; a differing prior digest is a conflict, quarantined by refusal. |
| sambhāvanā | सम्भावना | Bayes (Beta-Binomial belief) | Bayesian (Beta-Binomial) success belief per (agent, model), used for cheapest-adequate routing. |
| sambhāṣā | सम्भाषा | Agent communication language | Holon uos/holon/L2/language/acl (uos_tui/acl), whole language-plane. |
| sandeśa | सन्देश | Message / Event | textual.message / textual.events -> uos_tui/event.Event, msg (Homomorphic). system events typed; widget messages are user-typed msg |
| sandeśa-phalaka | सन्देश-फलक | Message board | Holon uos/holon/L2/messaging/board (uos_tui/board), whole messaging-plane. |
| sandeśa-tala | सन्देश-तल | Messaging plane | Holon uos/holon/L1/messaging/messaging-plane (uos_tui/board), whole planes. |
| sapta-tala | सप्त-तल | Seven planes | Holon uos/holon/L1/structure/planes (uos_tui/holon), whole uos. |
| saptadaśa-pakṣa | सप्तदश-पक्ष | 17 Aspect audit | (none) -> uos_tui/aspects.audit (Reinterpreted). UOS-only: fail-closed structural verification of a composed screen |
| saptadaśa-pakṣa | सप्तदश-पक्ष | 17-aspect audit | Holon uos/holon/L2/structure/aspects (uos_tui/aspects), whole structure-plane. |
| sarva-parīkṣā | सर्व-परीक्षा | System-wide audit | Holon uos/holon/L2/intelligence/system-audit (uos_tui/system_audit), whole intelligence-plane. |
| sattva | सत्त्व | Sattva (clarity) | Clear, balanced quality; maps onto a subject with zero Fail and zero Declared findings. |
| sattā-śāstra | सत्ता-शास्त्र | Fractal Textual ontology | Holon uos/holon/L2/structure/ontology (uos_tui/ontology), whole structure-plane. |
| saṃgraha | संग्रह | Inventory | Muda: unclaimed or unmerged work piling up (WIP above takt capacity). |
| saṃgraha-surakṣā | संग्रह-सुरक्षा | Substrate & Hardware Storage Safety | 17-aspect audit check #1: Substrate & Hardware Storage Safety. |
| saṃracanā-tala | संरचना-तल | Structure plane | Holon uos/holon/L1/structure/structure-plane (uos_tui/ontology), whole planes. |
| saṃvidhāna | संविधान | L0 constitutional whole: IAM, secrets, clock guard, governance | Holon uos/holon/L0/control/constitution (apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam), whole uos. |
| saṃvidhāna | संविधान | Constitution | The L0 constitutional-whole pattern: a `Subsystem`-kind holon (e.g. the `constitution` holon itself) grouping IAM, secrets, clock-guard and governance rows so their L0 level never pulls an unrelated subsystem down (HOLON-LIFECYCLE). |
| saṃyojana | संयोजन | Integrate | L0/L1 integration of a verified slice. |
| saṃyojana-saṅketa | संयोजन-सङ्केत | Integration bookmark | An `integration/*` bookmark (e.g. `integration/main`) where verified sibling-workspace slices are rebased in and serialized under a live lease. |
| saṅgarodha | सङ्गरोध | Quarantine | A malformed or refused artifact is preserved verbatim for inspection, never dropped and never silently absorbed. |
| saṅgarodhita-anumāna | सङ्गरोधित-अनुमान | Quarantined Modular MAX Inference | 17-aspect audit check #9: Quarantined Modular MAX Inference. |
| saṅkalpa | सङ्कल्प | Commit | Commits the speaker to completing an action by a deadline. |
| saṅkalpa-mūlaka-vinyāsa | सङ्कल्प-मूलक-विन्यास | Intent-Based Configuration | Declarative intent configuration (SC-FPP-INTENT-001) parsed and verified before runtime effect authorization, preventing invalid configuration transitions. |
| saṅketa | सङ्केत | Bookmark | A named, movable pointer to a change (Jujutsu's analogue of a Git branch); moved explicitly, never implicitly by commit. |
| saṅkoca | सङ्कोच | Squash | Folding a change's content into its parent, contracting two commits into one while the parent's change id survives. |
| saṅkocanīya | सङ्कोचनीय | Collapsible | textual.widgets.Collapsible -> uos_tui/widget.Checklist (Reinterpreted). UOS 5-domain/18-item checklist accordion (SC-CHECKLIST-001) |
| siddha | सिद्ध | Done | Kanban column: verified and accepted. |
| siddha | सिद्ध | Done | F´ lifecycle: verified and accepted. |
| siddha | सिद्ध | Pass | Freshly, positively evidenced. |
| smṛti | स्मृति | ETS live table | Holon uos/holon/L2/data/ets (uos_swarm_ffi.erl (ets)), whole data-plane. |
| smṛti | स्मृति | Smṛti (memory) | Retention of past experience; maps onto the ETS live table and the episodic memory namespace. |
| spandana | स्पन्दन | Freshness monitor | Holon uos/holon/L3/control/heartbeats (uos_tui/coord (beat/stale)), whole coord. |
| spandana | स्पन्दन | Heartbeat | A freshness pulse from a live agent. |
| spandana | स्पन्दन | Heartbeat | A periodic freshness pulse; its absence trips the dead-man's-switch. |
| sparśaka | स्पर्शक | Button | textual.widgets.Button -> uos_tui/widget.Button (Isomorphic).  |
| stara | स्तर | Level | The integer fractal layer (0..9) a holon occupies (`Holon.level`), used verbatim in its board address (`uos/holon/L<level>/<plane>/<id>`, `holon.address`) and constrained level-monotonic across whole/part edges (base rule B4). |
| sthāpita-sāra | स्थापित-सार | Commit id | The content hash of one specific snapshot of a change; every rewrite (rebase, squash, describe) produces a new commit id even though the change id is unchanged. |
| sthāyitā-yojanā | स्थायिता-योजना | Sa-Plan & Bionic Durable Workflows | 17-aspect audit check #17: Sa-Plan & Bionic Durable Workflows. |
| surakṣā | सुरक्षा | STPA & FMEA safety | Holon uos/holon/L2/control/stpa (uos_tui/stpa), whole control-plane. |
| svara | स्वर | Svara (musical note) | The seven svara (sa ri ga ma pa dha ni), the base pitches used by the music module. |
| svatantra-nikṣepa | स्वतन्त्र-निक्षेप | Standalone repository | A non-colocated `.jj/` repository with no backing `.git/` directory — the sole VCS mode admitted for UOS (CLAUDE.md §4). |
| svatantra-saṃskaraṇa | स्वतन्त्र-संस्करण | Standalone Jujutsu Monorepo Discipline | 17-aspect audit check #2: Standalone Jujutsu Monorepo Discipline. |
| svayaṃ-nirodha | स्वयं-निरोध | Jidoka | A stop-the-line signal. |
| svayaṃ-nirodha | स्वयं-निरोध | Jidoka (stop-the-line) | Autonomation: stop the line the instant a defect is detected, rather than pass it on. |
| svayaṃ-pūrṇa-aṅga | स्वयं-पूर्ण-अङ्ग | Holon | A self-complete part: a unit simultaneously whole to its own parts and part of a larger whole (Koestler); every entry of `holon.holarchy()` instantiates this pattern via the `Holon` record (id, whole, parts, level, plane, kind, uid, lifecycle, vitals). |
| svāmitva-patra-lekhana | स्वामित्व-पत्र-लेखन | write_owned_file | STPA control action `write_owned_file` dispatched by CTRL-SWARM-L0. |
| svīkāra | स्वीकार | Accept | Accepts a prior Request/Propose; the speaker now intends to act. |
| svīkārya | स्वीकार्य | Admissible | Strict two-key admission: zero Fail AND zero Declared findings. |
| svīkṛta-vikāsa-sīmā | स्वीकृत-विकास-सीमा | Admitted EV Ceiling | The machine-checked ceiling (admitted_ev_ceiling = 93, SC-PROVENANCE-001, INV-PROV-05) barring unadmitted EV numbers EV-94..EV-109 from claiming admission without fresh two-key verification. |
| svīkṛti | स्वीकृति | Ack | Acknowledgement of receipt/delivery. |
| sāmarthya | सामर्थ्य | Capability | A default-deny permission class (Memory, Rete, Bayes, Zenoh, Lean, Quint, STM) gated by a live grant. |
| sāmānya | सामान्य | Normal | Cockpit mode: steady-state repaint cadence. |
| sārvabhauma-parīkṣā | सार्वभौम-परीक्षा | Sovereign review | Tri-sovereign multi-agent review consensus (Antigravity/AGY, Claude, Codex) verified and ratified. |
| sāvadhāna | सावधान | Andon | A line-status alert (yellow/red). |
| sāvadhāna | सावधान | Andon | Raises a hazard; forces a decide obligation and a yellow/red line state. |
| sāvadhāna-saṅketa | सावधान-सङ्केत | Andon signal | Green/Yellow/Red line-status signal raised by a card in trouble. |
| sūcanā | सूचना | Inform | B(s,φ) ∧ ¬B(s,K(r,φ)) ⇒ K(r,φ): the sender shares a belief the receiver did not know. |
| sūcī | सूची | ListView | textual.widgets.ListView -> uos_tui/widget.ListView (Isomorphic).  |
| sūcī-kośa | सूची-कोश | A2UI Declarative Catalog | 17-aspect audit check #12: A2UI Declarative Catalog. |
| tala | तल | Plane | One of the seven control/structure/runtime/data/messaging/intelligence/language planes (`holon.Plane`) every holon is assigned to; each plane sounds one Hindustani svara via `holon.swara_of_plane`. |
| tamas | तमस् | Tamas (inertia) | Dull, inert quality; maps onto a stale subject — no heartbeat, Dark OODA mode. |
| thāṭ | थाट | Thāṭ (parent scale) | A parent scale (one of the 10 Hindustani thāṭ) from which rāga are derived. |
| trayī-ekīkaraṇa | त्रयी-एकीकरण | Triadic Unification | The unified architecture (ADR-095) consolidating C3I command cockpit, Indrajaal distributed mesh, and UOS standalone Jujutsu monorepo under a root OTP 29 supervisor. |
| tāla | ताल | Tāla (rhythmic cycle) | A cyclic rhythmic pattern counted in beats (mātrā), used by the music module. |
| tṛtīya-śreṇī | तृतीय-श्रेणी | R3 advisory second opinion | Advisory second opinion: free-first bounded OpenRouter. |
| upakarana | उपकरण | UOS CLI tooling | Holon uos/holon/L1/control/tools (tools), whole control-plane. |
| upakaraṇa-prāg-parīkṣā | उपकरण-प्राग्-परीक्षा | In-Project Toolchain Preflight | The repository-local gate (tools/preflight, G-PREFLIGHT, SC-TOOLCHAIN-INPROJECT-001) verifying that all 20 entrypoints execute under $UOS_ROOT and report valid status. |
| upamāna | उपमान | Upamāna (comparison) | Knowledge by comparison/analogy; maps onto differential oracles and the 17-aspect audit. |
| upāṅga | उपाङ्ग | F´ component | (none) -> uos_tui/fprime.component/dictionary_json (Reinterpreted). UOS-only: ports, commands, channels, events, parameters, ground dictionary |
| uttara | उत्तर | Answer | An answer to a Question. |
| varṇa-vinyāsa | वर्ण-विन्यास | Themes | textual.theme -> uos_tui/render.Theme (Homomorphic). single dark theme plus Dark Cockpit mode overlay |
| varṇana | वर्णन | Describe | Setting or editing a change's commit message without altering its file content; produces a new commit id under the same change id. |
| vibhajana | विभजन | Split | Dividing one change into two or more successive changes, each with its own new change id. |
| vibhāga | विभाग | Tabs / TabbedContent | textual.widgets.Tabs -> uos_tui/widget.Tabs (Homomorphic). content switching is the model's job |
| vicāra | विचार | orient | OODA: weigh the observation against the trend. |
| vijñānamaya | विज्ञानमय | Vijñānamaya-kośa (discernment sheath) | The sheath of discerning knowledge; maps onto formal verification and the 17-aspect audit. |
| vikalpa | विकल्प | Vikalpa (imagination, conceptualisation) | Cognition built from words/imagination without a directly grounded object; maps onto the dream module's speculative output posted as a Hypothesize. |
| vikāsa | विकास | Evolution | (none) -> uos_tui/ontology.Fidelity (Reinterpreted). fidelity ladder Deferred -> Reinterpreted -> Homomorphic -> Isomorphic |
| vikāsa-paryāvaraṇa | विकास-पर्यावरण | devenv | Reproducible developer and test environment definition (devenv.nix, devenv.yaml) enforcing OTP 29 runtime pins and isolated test execution. |
| vinyāsa | विन्यास | Vertical/Horizontal/Grid | textual.layouts -> uos_tui/layout.arrange/grid (Isomorphic). same resolution order: fixed, percent, auto, fraction |
| viparyaya | विपर्यय | Viparyaya (error, misconception) | False cognition; maps onto a Fail verdict. |
| viphala | विफल | Failed | Kanban column: verification failed, awaiting rework. |
| viphala | विफल | Failed | F´ lifecycle: verification failed. |
| viphala | विफल | Fail | Not positively evidenced; fail-closed default. |
| virodha | विरोध | Conflict | A first-class conflict state stored directly in the commit itself (never a special repository mode); a conflicted change can be rebased, described, and inspected like any other, and is resolved by editing the working copy. |
| vivaraṇa | विवरण | Report | A worker's report of completed work. |
| vyaya-sīmā | व्यय-सीमा | Budget | The USD ceiling an advisory call may not exceed (default 0.02 USD). |
| vṛkṣa | वृक्ष | DOM | textual.dom.DOMNode -> uos_tui/widget.flatten/find/children (Isomorphic). pre-order tree with ids |
| vṛkṣa | वृक्ष | Tree | textual.widgets.Tree -> uos_tui/widget.Tree (Homomorphic).  |
| vṛttānta | वृत्तान्त | RichLog / Log | textual.widgets.Log -> uos_tui/widget.Log (Homomorphic). plain lines, scroll offset |
| yantra | यन्त्र | App | textual.app.App -> uos_tui/app.App (Homomorphic). class with compose() becomes a record of init/update/screens; reactivity is TEA re-render |
| yojanā | योजना | Plan | A broadcast plan for the swarm. |
| yojita | योजित | Planned | Kanban column: queued, not yet started. |
| yuga | युग | Epoch (fencing token) | The monotonically increasing token that fences a lease against a stale holder. |
| ādeśa-thālī | आदेश-थाली | Command palette | textual.command -> uos_tui/gallery.view/search/score (Homomorphic). fuzzy subsequence scoring; caller supplies the registry (uos_tui/gallery demos it) |
| ānandamaya | आनन्दमय | Ānandamaya-kośa (bliss sheath) | The innermost sheath of bliss/harmony; maps onto the final `admitted` evidence state where discovered -> ... -> admitted closes without residue. |
| āpad | आपद् | Emergency | Cockpit mode: halt admission, raise Andon, repaint every cycle. |
| śabda | शब्द | Śabda (testimony) | Verbal testimony from a trusted source; maps onto board Report messages and sovereign reviews. |
| śabda-kośa | शब्द-कोश | F´ dictionaries | Holon uos/holon/L2/structure/fprime (uos_tui/fprime), whole structure-plane. |
| śailī | शैली | TCSS | textual.css -> uos_tui/style.Style (Reinterpreted). no CSS parser; typed style records with a combine monoid |
| śiras-pāda | शिरस्-पाद | Header/Footer | textual.widgets -> uos_tui/widget.Header, Footer (Isomorphic).  |
| śreṇī | श्रेणी | Tier | Free or Paid classification of an allowlisted advisory model. |
| śreṇī-niyata-saṅkalpa | श्रेणी-नियत-सङ्कल्प | Rank-strict intent | An Intent message must target a strictly higher-ranked layer than its sender. |
| śūnya-vyartha-śuddhi | शून्य-व्यर्थ-शुद्धि | Zero-Muda Purity & Waste Elimination | 17-aspect audit check #3: Zero-Muda Purity & Waste Elimination. |
| śūnya-śreṇī | शून्य-श्रेणी | R0 deterministic code | Runtime control: deterministic code, 0 tokens. |
| ṣaṣṭha-śreṇī | षष्ठ-श्रेणी | R6 design authority | Design authority, integration, admission: Fable only. |
