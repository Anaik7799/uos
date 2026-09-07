| id | Devanagari | IAST | English | domain | layer | aspects | definition | source |
|---|---|---|---|---|---|---|---|---|
| App | यन्त्र | yantra | App | TUI Library | 4 |  | textual.app.App -> uos_tui/app.App (Homomorphic). class with compose() becomes a record of init/update/screens; reactivity is TEA re-render | `uos_tui/app:App` |
| Screen | पटल | paṭala | Screen | TUI Library | 4 |  | textual.screen.Screen -> uos_tui/app.Screen (Isomorphic). named view over the model; push/pop via PushScreen/PopScreen effects | `uos_tui/app:Screen` |
| Widget | अङ्ग | aṅga | Widget | TUI Library | 2 |  | textual.widget.Widget -> uos_tui/widget.Widget(msg) (Homomorphic). class hierarchy becomes one closed sum type; state lives in the model | `uos_tui/widget:Widget(msg)` |
| DOM | वृक्ष | vṛkṣa | DOM | TUI Library | 2 |  | textual.dom.DOMNode -> uos_tui/widget.flatten/find/children (Isomorphic). pre-order tree with ids | `uos_tui/widget:flatten/find/children` |
| compose() | रचना | racanā | compose() | TUI Library | 2 |  | Widget.compose -> uos_tui/app.Screen.view (Isomorphic). pure function model -> tree | `uos_tui/app:Screen.view` |
| TCSS | शैली | śailī | TCSS | TUI Library | 1 |  | textual.css -> uos_tui/style.Style (Reinterpreted). no CSS parser; typed style records with a combine monoid | `uos_tui/style:Style` |
| Scalar / fr units | मात्रा | mātrā | Scalar / fr units | TUI Library | 1 |  | textual.css.scalar -> uos_tui/layout.Scalar (Isomorphic). Cells, Fraction, Percent, Auto | `uos_tui/layout:Scalar` |
| Vertical/Horizontal/Grid | विन्यास | vinyāsa | Vertical/Horizontal/Grid | TUI Library | 2 |  | textual.layouts -> uos_tui/layout.arrange/grid (Isomorphic). same resolution order: fixed, percent, auto, fraction | `uos_tui/layout:arrange/grid` |
| Region/Size/Offset | क्षेत्र | kṣetra | Region/Size/Offset | TUI Library | 1 |  | textual.geometry -> uos_tui/geometry.Region (Isomorphic). half-open rectangles with intersection/union laws | `uos_tui/geometry:Region` |
| Segment / Strip | खण्ड | khaṇḍa | Segment / Strip | TUI Library | 1 |  | rich.segment / textual.strip -> uos_tui/segment.Strip (Isomorphic). styled runs with cached cell length; crop/extend/simplify | `uos_tui/segment:Strip` |
| Compositor | चित्र-कार | citra-kāra | Compositor | TUI Library | 3 |  | textual._compositor -> uos_tui/render.compose/arrange (Homomorphic). placements blitted into a frame; no dirty-region diffing yet | `uos_tui/render:compose/arrange` |
| reactive | प्रतिक्रिया | pratikriyā | reactive | TUI Library | 3 |  | textual.reactive -> uos_tui/app.update -> render (Reinterpreted). every message re-renders; watchers become update clauses | `uos_tui/app:update -> render` |
| Message / Event | सन्देश | sandeśa | Message / Event | TUI Library | 3 |  | textual.message / textual.events -> uos_tui/event.Event, msg (Homomorphic). system events typed; widget messages are user-typed msg | `uos_tui/event:Event, msg` |
| Binding / action | बन्धन | bandhana | Binding / action | TUI Library | 3 |  | textual.binding.Binding -> uos_tui/widget.Binding(msg) (Isomorphic). key -> msg with description shown in Footer | `uos_tui/widget:Binding(msg)` |
| Focus chain | दृष्टि-शृङ्खला | dṛṣṭi-śṛṅkhalā | Focus chain | TUI Library | 3 |  | textual.screen.focus_chain -> uos_tui/app.move_focus (Isomorphic). document-order Tab/Shift-Tab | `uos_tui/app:move_focus` |
| Worker | कार्मकर | kārmakara | Worker | TUI Library | 4 |  | textual.worker -> uos_tui/app + uos_tui/live.Effect.Task (Homomorphic). task functions run in BEAM processes by the live driver | `uos_tui/app + uos_tui/live:Effect.Task` |
| Driver | चालक | cālaka | Driver | TUI Library | 4 |  | textual.driver -> uos_tui/live.run/child_spec (Homomorphic). OTP actor + reader process; raw mode via pure Erlang shell API | `uos_tui/live:run/child_spec` |
| Pilot / run_test | परीक्षक | parīkṣaka | Pilot / run_test | TUI Library | 5 |  | textual.pilot.Pilot -> uos_tui/headless.run (Isomorphic). scripted events, captured frames | `uos_tui/headless:run` |
| Command palette | आदेश-थाली | ādeśa-thālī | Command palette | TUI Library | 5 |  | textual.command -> uos_tui/gallery.view/search/score (Homomorphic). fuzzy subsequence scoring; caller supplies the registry (uos_tui/gallery demos it) | `uos_tui/gallery:view/search/score` |
| Themes | वर्ण-विन्यास | varṇa-vinyāsa | Themes | TUI Library | 1 |  | textual.theme -> uos_tui/render.Theme (Homomorphic). single dark theme plus Dark Cockpit mode overlay | `uos_tui/render:Theme` |
| Header/Footer | शिरस्-पाद | śiras-pāda | Header/Footer | TUI Library | 2 |  | textual.widgets -> uos_tui/widget.Header, Footer (Isomorphic).  | `uos_tui/widget:Header, Footer` |
| Static/Label | नाम-पट्टिका | nāma-paṭṭikā | Static/Label | TUI Library | 2 |  | textual.widgets.Static -> uos_tui/widget.Static (Isomorphic).  | `uos_tui/widget:Static` |
| Button | स्पर्शक | sparśaka | Button | TUI Library | 2 |  | textual.widgets.Button -> uos_tui/widget.Button (Isomorphic).  | `uos_tui/widget:Button` |
| Input | प्रवेश | praveśa | Input | TUI Library | 2 |  | textual.widgets.Input -> uos_tui/widget.Input (Homomorphic). no validators/suggester | `uos_tui/widget:Input` |
| DataTable | दत्तांश-सारणी | dattāṃśa-sāraṇī | DataTable | TUI Library | 2 |  | textual.widgets.DataTable -> uos_tui/widget.DataTable (Homomorphic). row cursor only | `uos_tui/widget:DataTable` |
| Tree | वृक्ष | vṛkṣa | Tree | TUI Library | 2 |  | textual.widgets.Tree -> uos_tui/widget.Tree (Homomorphic).  | `uos_tui/widget:Tree` |
| ListView | सूची | sūcī | ListView | TUI Library | 2 |  | textual.widgets.ListView -> uos_tui/widget.ListView (Isomorphic).  | `uos_tui/widget:ListView` |
| ProgressBar | प्रगति-पट्टी | pragati-paṭṭī | ProgressBar | TUI Library | 2 |  | textual.widgets.ProgressBar -> uos_tui/widget.ProgressBar (Isomorphic).  | `uos_tui/widget:ProgressBar` |
| Sparkline | लघु-रेखा | laghu-rekhā | Sparkline | TUI Library | 2 |  | textual.widgets.Sparkline -> uos_tui/widget.Sparkline (Isomorphic).  | `uos_tui/widget:Sparkline` |
| Tabs / TabbedContent | विभाग | vibhāga | Tabs / TabbedContent | TUI Library | 2 |  | textual.widgets.Tabs -> uos_tui/widget.Tabs (Homomorphic). content switching is the model's job | `uos_tui/widget:Tabs` |
| RichLog / Log | वृत्तान्त | vṛttānta | RichLog / Log | TUI Library | 2 |  | textual.widgets.Log -> uos_tui/widget.Log (Homomorphic). plain lines, scroll offset | `uos_tui/widget:Log` |
| Rule | रेखा | rekhā | Rule | TUI Library | 2 |  | textual.widgets.Rule -> uos_tui/widget.Rule (Isomorphic).  | `uos_tui/widget:Rule` |
| Collapsible | सङ्कोचनीय | saṅkocanīya | Collapsible | TUI Library | 0 |  | textual.widgets.Collapsible -> uos_tui/widget.Checklist (Reinterpreted). UOS 5-domain/18-item checklist accordion (SC-CHECKLIST-001) | `uos_tui/widget:Checklist` |
| Container | पात्र | pātra | Container | TUI Library | 2 |  | textual.containers -> uos_tui/widget.Container, Grid (Isomorphic). border + title like Textual border-title | `uos_tui/widget:Container, Grid` |
| 17 Aspect audit | सप्तदश-पक्ष | saptadaśa-pakṣa | 17 Aspect audit | TUI Library | 0 |  | (none) -> uos_tui/aspects.audit (Reinterpreted). UOS-only: fail-closed structural verification of a composed screen | `uos_tui/aspects:audit` |
| F´ component | उपाङ्ग | upāṅga | F´ component | TUI Library | 6 |  | (none) -> uos_tui/fprime.component/dictionary_json (Reinterpreted). UOS-only: ports, commands, channels, events, parameters, ground dictionary | `uos_tui/fprime:component/dictionary_json` |
| Textual Web / serve | जाल-सेवा | jāla-sevā | Textual Web / serve | TUI Library | 7 |  | textual-serve -> uos_tui/frame.to_text/to_ansi (Deferred). projection to Wisp at :4100 is a follow-on | `uos_tui/frame:to_text/to_ansi` |
| Evolution | विकास | vikāsa | Evolution | TUI Library | 8 |  | (none) -> uos_tui/ontology.Fidelity (Reinterpreted). fidelity ladder Deferred -> Reinterpreted -> Homomorphic -> Isomorphic | `uos_tui/ontology:Fidelity` |
| uos | एकीकृत-कार्य-तन्त्र | ekīkṛta-kārya-tantra | Unified Operational System | Coordination | 0 |  | Holon uos/holon/L0/uos (apps/uos_tui), whole (root). | `uos_swarm/holon.gleam:holarchy` |
| supervisor | अधिष्ठातृ | adhiṣṭhātṛ | L0 design authority (Fable) | Coordination | 0 |  | Holon uos/holon/L0/supervisor (uos_tui/coord (policy)), whole uos. | `uos_swarm/holon.gleam:holarchy` |
| planes | सप्त-तल | sapta-tala | Seven planes | Structure | 1 |  | Holon uos/holon/L1/planes (uos_tui/holon), whole uos. | `uos_swarm/holon.gleam:holarchy` |
| control-plane | नियन्त्रण-तल | niyantraṇa-tala | Control plane | Coordination | 1 |  | Holon uos/holon/L1/control-plane (uos_tui/coord), whole planes. | `uos_swarm/holon.gleam:holarchy` |
| structure-plane | संरचना-तल | saṃracanā-tala | Structure plane | Structure | 1 |  | Holon uos/holon/L1/structure-plane (uos_tui/ontology), whole planes. | `uos_swarm/holon.gleam:holarchy` |
| runtime-plane | प्रवर्तन-तल | pravartana-tala | Runtime plane | Runtime | 1 |  | Holon uos/holon/L1/runtime-plane (uos_tui/live), whole planes. | `uos_swarm/holon.gleam:holarchy` |
| data-plane | दत्तांश-तल | dattāṃśa-tala | Data plane | Data | 1 |  | Holon uos/holon/L1/data-plane (uos_tui/board (ledger)), whole planes. | `uos_swarm/holon.gleam:holarchy` |
| messaging-plane | सन्देश-तल | sandeśa-tala | Messaging plane | Messaging | 1 |  | Holon uos/holon/L1/messaging-plane (uos_tui/board), whole planes. | `uos_swarm/holon.gleam:holarchy` |
| intelligence-plane | बुद्धि-तल | buddhi-tala | Intelligence plane | Intelligence | 1 |  | Holon uos/holon/L1/intelligence-plane (uos_tui/manager), whole planes. | `uos_swarm/holon.gleam:holarchy` |
| language-plane | भाषा-तल | bhāṣā-tala | Language plane | Language | 1 |  | Holon uos/holon/L1/language-plane (uos_tui/acl), whole planes. | `uos_swarm/holon.gleam:holarchy` |
| coord | समन्वय | samanvaya | Coordination & sync | Coordination | 2 |  | Holon uos/holon/L2/coord (uos_tui/coord), whole control-plane. | `uos_swarm/holon.gleam:holarchy` |
| stpa | सुरक्षा | surakṣā | STPA & FMEA safety | Coordination | 2 |  | Holon uos/holon/L2/stpa (uos_tui/stpa), whole control-plane. | `uos_swarm/holon.gleam:holarchy` |
| ontology | सत्ता-शास्त्र | sattā-śāstra | Fractal Textual ontology | Structure | 2 |  | Holon uos/holon/L2/ontology (uos_tui/ontology), whole structure-plane. | `uos_swarm/holon.gleam:holarchy` |
| fprime | शब्द-कोश | śabda-kośa | F´ dictionaries | Structure | 2 |  | Holon uos/holon/L2/fprime (uos_tui/fprime), whole structure-plane. | `uos_swarm/holon.gleam:holarchy` |
| aspects | सप्तदश-पक्ष | saptadaśa-pakṣa | 17-aspect audit | Structure | 2 |  | Holon uos/holon/L2/aspects (uos_tui/aspects), whole structure-plane. | `uos_swarm/holon.gleam:holarchy` |
| live | जीव-चालक | jīva-cālaka | OTP live driver | Runtime | 2 |  | Holon uos/holon/L2/live (uos_tui/live), whole runtime-plane. | `uos_swarm/holon.gleam:holarchy` |
| headless | परीक्षक | parīkṣaka | Headless pilot | Runtime | 2 |  | Holon uos/holon/L2/headless (uos_tui/headless), whole runtime-plane. | `uos_swarm/holon.gleam:holarchy` |
| app | मूल-यन्त्र | mūla-yantra | TEA application core | Runtime | 2 |  | Holon uos/holon/L2/app (uos_tui/app), whole runtime-plane. | `uos_swarm/holon.gleam:holarchy` |
| ledger | लेखा | lekhā | Append-only JSONL ledger | Data | 2 |  | Holon uos/holon/L2/ledger (uos_tui/board (jsonl)), whole data-plane. | `uos_swarm/holon.gleam:holarchy` |
| ets | स्मृति | smṛti | ETS live table | Data | 2 |  | Holon uos/holon/L2/ets (uos_swarm_ffi.erl (ets)), whole data-plane. | `uos_swarm/holon.gleam:holarchy` |
| zenoh-storage | मेघ-स्मृति | megha-smṛti | Zenoh memory storages | Data | 2 |  | Holon uos/holon/L2/zenoh-storage (ops/zenoh (storage_manager)), whole data-plane. | `uos_swarm/holon.gleam:holarchy` |
| board | सन्देश-फलक | sandeśa-phalaka | Message board | Messaging | 2 |  | Holon uos/holon/L2/board (uos_tui/board), whole messaging-plane. | `uos_swarm/holon.gleam:holarchy` |
| zenoh-router | मार्ग-दर्शक | mārga-darśaka | Zenoh router c3i-zenoh-router-1 | Messaging | 2 |  | Holon uos/holon/L2/zenoh-router (ops/zenoh), whole messaging-plane. | `uos_swarm/holon.gleam:holarchy` |
| manager | प्रबन्धक | prabandhaka | F´ managing agent | Intelligence | 2 |  | Holon uos/holon/L2/manager (uos_tui/manager), whole intelligence-plane. | `uos_swarm/holon.gleam:holarchy` |
| system-audit | सर्व-परीक्षा | sarva-parīkṣā | System-wide audit | Intelligence | 2 |  | Holon uos/holon/L2/system-audit (uos_tui/system_audit), whole intelligence-plane. | `uos_swarm/holon.gleam:holarchy` |
| acl | सम्भाषा | sambhāṣā | Agent communication language | Language | 2 |  | Holon uos/holon/L2/acl (uos_tui/acl), whole language-plane. | `uos_swarm/holon.gleam:holarchy` |
| widgets | अङ्ग | aṅga | Widget catalog (17 families) | Runtime | 3 |  | Holon uos/holon/L3/widgets (uos_tui/widget), whole app. | `uos_swarm/holon.gleam:holarchy` |
| render | चित्र-कार | citra-kāra | Compositor | Runtime | 3 |  | Holon uos/holon/L3/render (uos_tui/render), whole app. | `uos_swarm/holon.gleam:holarchy` |
| ooda | चक्र | cakra | Fast OODA controller | Intelligence | 3 |  | Holon uos/holon/L3/ooda (uos_tui/ooda), whole manager. | `uos_swarm/holon.gleam:holarchy` |
| leases | पट्टा | paṭṭā | Fenced leases | Coordination | 3 |  | Holon uos/holon/L3/leases (uos_tui/coord (acquire/renew/release)), whole coord. | `uos_swarm/holon.gleam:holarchy` |
| heartbeats | स्पन्दन | spandana | Freshness monitor | Coordination | 3 |  | Holon uos/holon/L3/heartbeats (uos_tui/coord (beat/stale)), whole coord. | `uos_swarm/holon.gleam:holarchy` |
| policy | अधिकार | adhikāra | Hierarchical authority | Coordination | 3 |  | Holon uos/holon/L3/policy (uos_tui/coord (authorize)), whole coord. | `uos_swarm/holon.gleam:holarchy` |
| lexicon | कोश | kośa | Sanskrit/English lexicon | Language | 3 |  | Holon uos/holon/L3/lexicon (uos_tui/acl (lexicon)), whole acl. | `uos_swarm/holon.gleam:holarchy` |
| aspect:SubstrateStorageSafety | संग्रह-सुरक्षा | saṃgraha-surakṣā | Substrate & Hardware Storage Safety | Safety | 0 | 1 | 17-aspect audit check #1: Substrate & Hardware Storage Safety. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:StandaloneJujutsu | स्वतन्त्र-संस्करण | svatantra-saṃskaraṇa | Standalone Jujutsu Monorepo Discipline | Safety | 0 | 2 | 17-aspect audit check #2: Standalone Jujutsu Monorepo Discipline. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:ZeroMudaPurity | शून्य-व्यर्थ-शुद्धि | śūnya-vyartha-śuddhi | Zero-Muda Purity & Waste Elimination | Safety | 0 | 3 | 17-aspect audit check #3: Zero-Muda Purity & Waste Elimination. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:GleamOtpSupervisor | अध्यक्ष | adhyakṣa | Gleam/OTP Root Supervisor | Safety | 0 | 4 | 17-aspect audit check #4: Gleam/OTP Root Supervisor. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:ZigVmEngine | नियत-यन्त्र | niyata-yantra | ZigVM Deterministic Engine & VFS Laws | Safety | 0 | 5 | 17-aspect audit check #5: ZigVM Deterministic Engine & VFS Laws. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:HermesEvidence | प्रमाण-साक्ष्य | pramāṇa-sākṣya | Hermes Formal Evidence & Gospel | Safety | 0 | 6 | 17-aspect audit check #6: Hermes Formal Evidence & Gospel. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:MathematicalAuthority | गणित-अधिकार | gaṇita-adhikāra | Mathematical Authority & Conservation | Safety | 0 | 7 | 17-aspect audit check #7: Mathematical Authority & Conservation. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:BiosemioticCybernetics | जीव-सङ्केत-विज्ञान | jīva-saṅketa-vijñāna | Biosemiotic Cybernetics & Rocha Cut | Safety | 0 | 8 | 17-aspect audit check #8: Biosemiotic Cybernetics & Rocha Cut. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:QuarantinedMaxInference | सङ्गरोधित-अनुमान | saṅgarodhita-anumāna | Quarantined Modular MAX Inference | Safety | 0 | 9 | 17-aspect audit check #9: Quarantined Modular MAX Inference. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:ZenohTelemetry | दूर-मिती | dūra-mitī | Zenoh OoZ & MoZ Mesh Telemetry | Safety | 0 | 10 | 17-aspect audit check #10: Zenoh OoZ & MoZ Mesh Telemetry. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:AgUiEventStream | घटना-स्रोत | ghaṭanā-srota | AG-UI 32-Event SSE Stream | Safety | 0 | 11 | 17-aspect audit check #11: AG-UI 32-Event SSE Stream. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:A2UiCatalog | सूची-कोश | sūcī-kośa | A2UI Declarative Catalog | Safety | 0 | 12 | 17-aspect audit check #12: A2UI Declarative Catalog. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:PentaStackAccessibility | पञ्च-स्तर-सुलभता | pañca-stara-sulabhatā | Penta-Stack Multi-Interface Accessibility | Safety | 0 | 13 | 17-aspect audit check #13: Penta-Stack Multi-Interface Accessibility. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:TailscaleFqdnNavigation | जाल-मार्ग-दर्शन | jāla-mārga-darśana | Universal Tailscale FQDN Web Navigation | Safety | 0 | 14 | 17-aspect audit check #14: Universal Tailscale FQDN Web Navigation. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:ComprehensiveChecklist | समग्र-सूची-पत्र | samagra-sūcī-patra | Comprehensive Verification Checklist | Safety | 0 | 15 | 17-aspect audit check #15: Comprehensive Verification Checklist. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:KnowledgeTriad | ज्ञान-त्रिक | jñāna-trika | Knowledge Management Triad | Safety | 0 | 16 | 17-aspect audit check #16: Knowledge Management Triad. | `uos_tui/aspects.gleam:Aspect/check` |
| aspect:SaPlanDurability | स्थायिता-योजना | sthāyitā-yojanā | Sa-Plan & Bionic Durable Workflows | Safety | 0 | 17 | 17-aspect audit check #17: Sa-Plan & Bionic Durable Workflows. | `uos_tui/aspects.gleam:Aspect/check` |
| CA-emit_intent | अभिसन्धि-उत्सर्जन | abhisandhi-utsarjana | emit_intent | Safety | 3 |  | STPA control action `emit_intent` dispatched by CTRL-TUI-APP. | `uos_swarm/stpa.gleam:model/control_actions` |
| CA-push_confirm_screen | पुष्टि-पटल-प्रेषण | puṣṭi-paṭala-preṣaṇa | push_confirm_screen | Safety | 3 |  | STPA control action `push_confirm_screen` dispatched by CTRL-TUI-APP. | `uos_swarm/stpa.gleam:model/control_actions` |
| CA-paint_frame | चित्राङ्कन | citrāṅkana | paint_frame | Safety | 3 |  | STPA control action `paint_frame` dispatched by CTRL-TUI-DRIVER. | `uos_swarm/stpa.gleam:model/control_actions` |
| CA-enter_raw | कच्चा-प्रवेश | kaccā-praveśa | enter_raw | Safety | 3 |  | STPA control action `enter_raw` dispatched by CTRL-TUI-DRIVER. | `uos_swarm/stpa.gleam:model/control_actions` |
| CA-restore_terminal | प्रवर्तक-पुनःस्थापना | pravartaka-punaḥsthāpana | restore_terminal | Safety | 3 |  | STPA control action `restore_terminal` dispatched by CTRL-TUI-DRIVER. | `uos_swarm/stpa.gleam:model/control_actions` |
| CA-audit_screen | पटल-परीक्षा | paṭala-parīkṣā | audit_screen | Safety | 3 |  | STPA control action `audit_screen` dispatched by CTRL-TUI-ASPECTS. | `uos_swarm/stpa.gleam:model/control_actions` |
| CA-integrate_slice | खण्ड-संयोजन | khaṇḍa-saṃyojana | integrate_slice | Safety | 3 |  | STPA control action `integrate_slice` dispatched by CTRL-SWARM-L0. | `uos_swarm/stpa.gleam:model/control_actions` |
| CA-verify_slice | खण्ड-सत्यापन | khaṇḍa-satyāpana | verify_slice | Safety | 3 |  | STPA control action `verify_slice` dispatched by CTRL-SWARM-VERIFIER. | `uos_swarm/stpa.gleam:model/control_actions` |
| CA-write_owned_file | स्वामित्व-पत्र-लेखन | svāmitva-patra-lekhana | write_owned_file | Safety | 3 |  | STPA control action `write_owned_file` dispatched by CTRL-SWARM-L0. | `uos_swarm/stpa.gleam:model/control_actions` |
| Overproduction | अत्युत्पादन | atyutpādana | Overproduction | Coordination | 3 |  | Muda: producing more, sooner, or faster than the next station needs. | `uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda` |
| Waiting | प्रतीक्षा | pratīkṣā | Waiting | Coordination | 3 |  | Muda: idle time while a card sits blocked on another resource. | `uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda` |
| Transport | परिवहन | parivahana | Transport | Coordination | 3 |  | Muda: unnecessary movement of work or artifacts between agents. | `uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda` |
| Overprocessing | अतिप्रक्रिया | atiprakriyā | Overprocessing | Coordination | 3 |  | Muda: doing more work on a slice than the spec requires. | `uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda` |
| Inventory | संग्रह | saṃgraha | Inventory | Coordination | 3 |  | Muda: unclaimed or unmerged work piling up (WIP above takt capacity). | `uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda` |
| Motion | गति | gati | Motion | Coordination | 3 |  | Muda: unnecessary context switching or re-reading by an agent. | `uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda` |
| Defects | दोष | doṣa | Defects | Coordination | 3 |  | Muda: rework caused by a verification failure that should have been caught earlier. | `uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda` |
| kind:Plan | योजना | yojanā | Plan | Messaging | 3 |  | A broadcast plan for the swarm. | `uos_swarm/board.gleam:Kind` |
| kind:Dispatch | प्रेषण | preṣaṇa | Dispatch | Messaging | 3 |  | L0/L1 dispatch of work to an agent. | `uos_swarm/board.gleam:Kind` |
| kind:Claim | अधिग्रहण | adhigrahaṇa | Claim | Messaging | 3 |  | An agent claims a task under a fenced lease. | `uos_swarm/board.gleam:Kind` |
| kind:Progress | प्रगति | pragati | Progress | Messaging | 3 |  | An in-flight progress update. | `uos_swarm/board.gleam:Kind` |
| kind:Question | प्रश्न | praśna | Question | Messaging | 3 |  | A question posted to another agent. | `uos_swarm/board.gleam:Kind` |
| kind:Answer | उत्तर | uttara | Answer | Messaging | 3 |  | An answer to a Question. | `uos_swarm/board.gleam:Kind` |
| kind:Report | विवरण | vivaraṇa | Report | Messaging | 3 |  | A worker's report of completed work. | `uos_swarm/board.gleam:Kind` |
| kind:Verdict | निर्णय | nirṇaya | Verdict | Messaging | 3 |  | A verifier's admit/reject decision. | `uos_swarm/board.gleam:Kind` |
| kind:Andon | सावधान | sāvadhāna | Andon | Messaging | 3 |  | A line-status alert (yellow/red). | `uos_swarm/board.gleam:Kind` |
| kind:Jidoka | स्वयं-निरोध | svayaṃ-nirodha | Jidoka | Messaging | 3 |  | A stop-the-line signal. | `uos_swarm/board.gleam:Kind` |
| kind:Integrate | संयोजन | saṃyojana | Integrate | Messaging | 3 |  | L0/L1 integration of a verified slice. | `uos_swarm/board.gleam:Kind` |
| kind:Heartbeat | स्पन्दन | spandana | Heartbeat | Messaging | 3 |  | A freshness pulse from a live agent. | `uos_swarm/board.gleam:Kind` |
| kind:Intent | अभिसन्धि | abhisandhi | Intent | Messaging | 3 |  | A declared intent, rank-strict (must target L0/L1). | `uos_swarm/board.gleam:Kind` |
| kind:LeaseGrant | पट्टा-अनुज्ञा | paṭṭā-anujñā | LeaseGrant | Messaging | 3 |  | Grant of a fenced lease/epoch. | `uos_swarm/board.gleam:Kind` |
| kind:LeaseRelease | पट्टा-मुक्ति | paṭṭā-mukti | LeaseRelease | Messaging | 3 |  | Release of a held lease. | `uos_swarm/board.gleam:Kind` |
| kind:Ack | स्वीकृति | svīkṛti | Ack | Messaging | 3 |  | Acknowledgement of receipt/delivery. | `uos_swarm/board.gleam:Kind` |
| kind:DeadLetter | मृत-पत्र | mṛta-patra | DeadLetter | Messaging | 3 |  | A message retried past its limit and dead-lettered. | `uos_swarm/board.gleam:Kind` |
| perf:Inform | सूचना | sūcanā | Inform | Language | 3 |  | B(s,φ) ∧ ¬B(s,K(r,φ)) ⇒ K(r,φ): the sender shares a belief the receiver did not know. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Request | प्रार्थना | prārthanā | Request | Language | 3 |  | Requests the receiver to accept or reject doing an action. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Propose | प्रस्ताव | prastāva | Propose | Language | 3 |  | Proposes a feasible action for the receiver to accept or reject. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Accept | स्वीकार | svīkāra | Accept | Language | 3 |  | Accepts a prior Request/Propose; the speaker now intends to act. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Reject | निराकरण | nirākaraṇa | Reject | Language | 3 |  | Rejects a prior Request/Propose, with a reason. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Query | प्रश्न | praśna | Query | Language | 3 |  | Asks the receiver to Inform on a proposition. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Confirm | पुष्टि | puṣṭi | Confirm | Language | 3 |  | Confirms a belief the receiver was uncertain of. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Commit | सङ्कल्प | saṅkalpa | Commit | Language | 3 |  | Commits the speaker to completing an action by a deadline. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Assert | प्रतिज्ञा | pratijñā | Assert | Language | 3 |  | Asserts a known proposition into the shared ledger. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Retract | प्रत्याहार | pratyāhāra | Retract | Language | 3 |  | Withdraws a previously asserted proposition. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Hypothesize | कल्पना | kalpanā | Hypothesize | Language | 3 |  | Offers an unproven proposition for testing (the dream module's output). | `uos_swarm/acl.gleam:Performative/semantics_of` |
| perf:Andon | सावधान | sāvadhāna | Andon | Language | 3 |  | Raises a hazard; forces a decide obligation and a yellow/red line state. | `uos_swarm/acl.gleam:Performative/semantics_of` |
| ooda-mode:Dark | अन्धकार | andhakāra | Dark | Intelligence | 5 |  | Cockpit mode: minimum draw, only heartbeats. | `uos_swarm/ooda.gleam:Mode` |
| ooda-mode:Dim | मन्द | manda | Dim | Intelligence | 5 |  | Cockpit mode: low draw, occasional repaint. | `uos_swarm/ooda.gleam:Mode` |
| ooda-mode:Normal | सामान्य | sāmānya | Normal | Intelligence | 5 |  | Cockpit mode: steady-state repaint cadence. | `uos_swarm/ooda.gleam:Mode` |
| ooda-mode:Bright | प्रकाश | prakāśa | Bright | Intelligence | 5 |  | Cockpit mode: elevated cadence plus an aspect audit. | `uos_swarm/ooda.gleam:Mode` |
| ooda-mode:Emergency | आपद् | āpad | Emergency | Intelligence | 5 |  | Cockpit mode: halt admission, raise Andon, repaint every cycle. | `uos_swarm/ooda.gleam:Mode` |
| ooda-phase:observe | अवलोकन | avalokana | observe | Intelligence | 5 |  | OODA: gather the observation window (manas). | `uos_swarm/ooda.gleam:step` |
| ooda-phase:orient | विचार | vicāra | orient | Intelligence | 5 |  | OODA: weigh the observation against the trend. | `uos_swarm/ooda.gleam:step` |
| ooda-phase:decide | निर्णय | nirṇaya | decide | Intelligence | 5 |  | OODA: choose the mode and actions (buddhi). | `uos_swarm/ooda.gleam:step` |
| ooda-phase:act | क्रिया | kriyā | act | Intelligence | 5 |  | OODA: emit the chosen actions for this cycle. | `uos_swarm/ooda.gleam:step` |
| wip-limit | कार्य-सीमा | kārya-sīmā | WIP limit | Coordination | 3 |  | The maximum number of cards a swarm may hold In Progress at once. | `uos_swarm/tps.gleam:Board.wip_limit` |
| takt-time | गति-काल | gati-kāla | Takt time | Coordination | 3 |  | The target minutes per card that keeps the swarm at customer pace. | `uos_swarm/tps.gleam:Board.takt_minutes` |
| jidoka | स्वयं-निरोध | svayaṃ-nirodha | Jidoka (stop-the-line) | Coordination | 3 |  | Autonomation: stop the line the instant a defect is detected, rather than pass it on. | `uos_swarm/tps.gleam:Board.jidoka_stops/line_stopped` |
| andon-signal | सावधान-सङ्केत | sāvadhāna-saṅketa | Andon signal | Coordination | 3 |  | Green/Yellow/Red line-status signal raised by a card in trouble. | `uos_swarm/tps.gleam:Andon` |
| kanban:Planned | योजित | yojita | Planned | Coordination | 3 |  | Kanban column: queued, not yet started. | `uos_swarm/tps.gleam:Column` |
| kanban:Running | प्रवर्तमान | pravartamāna | Running | Coordination | 3 |  | Kanban column: actively being worked. | `uos_swarm/tps.gleam:Column` |
| kanban:Verifying | परीक्ष्यमाण | parīkṣyamāṇa | Verifying | Coordination | 3 |  | Kanban column: submitted, awaiting verification. | `uos_swarm/tps.gleam:Column` |
| kanban:Done | सिद्ध | siddha | Done | Coordination | 3 |  | Kanban column: verified and accepted. | `uos_swarm/tps.gleam:Column` |
| kanban:Failed | विफल | viphala | Failed | Coordination | 3 |  | Kanban column: verification failed, awaiting rework. | `uos_swarm/tps.gleam:Column` |
| lease | पट्टा | paṭṭā | Lease | Coordination | 3 |  | A fenced, time-bounded hold on a resource with a monotonically increasing epoch. | `uos_swarm/coord.gleam:Lease/acquire` |
| epoch | युग | yuga | Epoch (fencing token) | Coordination | 3 |  | The monotonically increasing token that fences a lease against a stale holder. | `uos_swarm/coord.gleam:Lease.epoch` |
| claim | अधिग्रहण | adhigrahaṇa | Claim | Coordination | 3 |  | A lease on `task:<id>` subject to the swarm's WIP limit. | `uos_swarm/coord.gleam:claim` |
| heartbeat | स्पन्दन | spandana | Heartbeat | Coordination | 3 |  | A periodic freshness pulse; its absence trips the dead-man's-switch. | `uos_swarm/coord.gleam:beat/stale; uos_swarm/board.gleam:Heartbeat kind` |
| reconcile | समन्वय | samanvaya | Reconcile | Coordination | 3 |  | Merge a remote view of the board into the local one; a differing prior digest is a conflict, quarantined by refusal. | `uos_swarm/coord.gleam:reconcile` |
| causal-gap | कारण-अन्तर | kāraṇa-antara | Causal gap | Coordination | 3 |  | An explicit record documenting a reply target that is provably lost, so it never has to be forged or recreated. | `uos_swarm/board.gleam:causal_gaps` |
| outbox | निर्गम-पेटिका | nirgama-peṭikā | Transactional outbox | Coordination | 3 |  | Durable ledger acceptance gates publication: a message is Outboxed before any Zenoh put is attempted. | `uos_swarm/board.gleam:deliver/delivery_state` |
| per-sender-chain | प्रेषक-शृङ्खला | preṣaka-śṛṅkhalā | Per-sender digest chain | Coordination | 3 |  | One SHA-256 hash chain per sender (multi-writer safe), ordered by id within the sender. | `uos_swarm/board.gleam:validate (per-sender chain check)` |
| signature | हस्ताक्षर | hastākṣara | Signature | Coordination | 3 |  | An HMAC over the message digest with a per-agent derived key; a shared master key never signs directly. | `uos_swarm/board.gleam:sign_with_agent_key/agent_key` |
| design-authority | अधिष्ठातृ | adhiṣṭhātṛ | Design authority | Governance | 0 |  | Design decisions (Plan/Dispatch/Integrate/Andon broadcasts) come only from the design authority model roster. | `uos_swarm/coord.gleam:Policy.design_models/authorize (DesignAuthorityRequired)` |
| rank-strict-intent | श्रेणी-नियत-सङ्कल्प | śreṇī-niyata-saṅkalpa | Rank-strict intent | Governance | 3 |  | An Intent message must target a strictly higher-ranked layer than its sender. | `uos_swarm/coord.gleam:authorize (IntentMustGoUpward)` |
| sovereign-review | सार्वभौम-परीक्षा | sārvabhauma-parīkṣā | Sovereign review | Governance | 0 |  | Tri-sovereign multi-agent review consensus (Antigravity/AGY, Claude, Codex) verified and ratified. | `uos_swarm/cockpit.gleam:CHK-17-SOV` |
| two-key-verification | द्वि-कुञ्चिका-सत्यापन | dvi-kuñcikā-satyāpana | Two-key verification | Governance | 0 |  | Trust requires BOTH fresh observed runtime behaviour AND a machine-verifiable formal specification. | `uos_swarm/system_audit.gleam:admissible (strict two-key admission)` |
| quarantine | सङ्गरोध | saṅgarodha | Quarantine | Governance | 0 |  | A malformed or refused artifact is preserved verbatim for inspection, never dropped and never silently absorbed. | `uos_swarm/board.gleam:quarantined/open (<ledger>.quarantine.jsonl)` |
| memory:working | कार्य-स्मृति | kārya-smṛti | Working memory | Intelligence | 4 |  | Namespace `working/`: scratch memory for the task in flight. | `uos_swarm/agent_runtime.gleam:Memory (working/)` |
| memory:episodic | प्रसङ्ग-स्मृति | prasaṅga-smṛti | Episodic memory | Intelligence | 4 |  | Namespace `episodic/<id>`: a remembered board message. | `uos_swarm/agent_runtime.gleam:remember (episodic/)` |
| memory:belief | मतम् | matam | Belief memory | Intelligence | 4 |  | Namespace `belief/`: doxastic state the agent holds but has not asserted. | `uos_swarm/agent_runtime.gleam:Memory (belief/)` |
| memory:goal | लक्ष्य | lakṣya | Goal memory | Intelligence | 4 |  | Namespace `goal/`: the agent's current objectives. | `uos_swarm/agent_runtime.gleam:Memory (goal/)` |
| grant | अनुज्ञा | anujñā | Grant | Intelligence | 4 |  | A scoped, expiring, opaque capability token minted only by L0/L1 and tracked as a board message. | `uos_swarm/agent_runtime.gleam:grant/Grant` |
| capability | सामर्थ्य | sāmarthya | Capability | Intelligence | 4 |  | A default-deny permission class (Memory, Rete, Bayes, Zenoh, Lean, Quint, STM) gated by a live grant. | `uos_swarm/agent_runtime.gleam:Capability/capability_label` |
| lifecycle:Idle | निष्क्रिय | niṣkriya | Idle | Intelligence | 4 |  | F´ lifecycle: unclaimed, no lease held. | `uos_swarm/agent_runtime.gleam:State/state_label` |
| lifecycle:Claimed | गृहीत | gṛhīta | Claimed | Intelligence | 4 |  | F´ lifecycle: claimed under a lease, not yet started. | `uos_swarm/agent_runtime.gleam:State/state_label` |
| lifecycle:Working | कार्यरत | kāryarata | Working | Intelligence | 4 |  | F´ lifecycle: actively being worked. | `uos_swarm/agent_runtime.gleam:State/state_label` |
| lifecycle:Verifying | परीक्ष्यमाण | parīkṣyamāṇa | Verifying | Intelligence | 4 |  | F´ lifecycle: submitted, awaiting verification. | `uos_swarm/agent_runtime.gleam:State/state_label` |
| lifecycle:Done | सिद्ध | siddha | Done | Intelligence | 4 |  | F´ lifecycle: verified and accepted. | `uos_swarm/agent_runtime.gleam:State/state_label` |
| lifecycle:Failed | विफल | viphala | Failed | Intelligence | 4 |  | F´ lifecycle: verification failed. | `uos_swarm/agent_runtime.gleam:State/state_label` |
| rete | नियम | niyama | Rete (rule matcher) | Intelligence | 4 |  | Bounded forward-chaining matcher over typed facts (naive unification, not a full Rete network). | `uos_swarm/agent_runtime.gleam:Fact/Pattern (ReteCap)` |
| bayes | सम्भावना | sambhāvanā | Bayes (Beta-Binomial belief) | Intelligence | 4 |  | Bayesian (Beta-Binomial) success belief per (agent, model), used for cheapest-adequate routing. | `uos_swarm/agent_runtime.gleam:BayesCap` |
| verdict:Pass | सिद्ध | siddha | Pass | Review | 0 |  | Freshly, positively evidenced. | `uos_tui/aspects.gleam:Verdict` |
| verdict:Declared | घोषित | ghoṣita | Declared | Review | 0 |  | Bound by declaration/config, not fresh observed behaviour. | `uos_tui/aspects.gleam:Verdict` |
| verdict:Fail | विफल | viphala | Fail | Review | 0 |  | Not positively evidenced; fail-closed default. | `uos_tui/aspects.gleam:Verdict` |
| admissible | स्वीकार्य | svīkārya | Admissible | Review | 0 |  | Strict two-key admission: zero Fail AND zero Declared findings. | `uos_tui/aspects.gleam:admissible; uos_swarm/system_audit.gleam:admissible` |
| no-failures | अविफल | aviphala | No-failures gate | Review | 0 |  | The softer gate: zero Fail findings, Declared tolerated (used for jidoka stop/resume). | `uos_tui/aspects.gleam:no_failures` |
| hold | अवरोध | avarodha | Hold | Review | 0 |  | The line-stopped state entered by jidoka when no_failures fails, pending a fix and sovereign review. | `uos_swarm/tps.gleam:Board.line_stopped` |
| guna | गुण | guṇa | Guṇa (the three qualities) | Review | 8 |  | Sāṃkhya's three qualities, used here as a state classification for system health: sattva, rajas, tamas. | `uos_swarm/system_ontology.gleam (state-classification mapping)` |
| guna:sattva | सत्त्व | sattva | Sattva (clarity) | Review | 8 |  | Clear, balanced quality; maps onto a subject with zero Fail and zero Declared findings. | `uos_tui/aspects.gleam:admissible` |
| guna:rajas | रजस् | rajas | Rajas (activity) | Review | 8 |  | Active, restless quality; maps onto churn — high Progress/Dispatch traffic on the board. | `uos_swarm/board.gleam:Progress kind` |
| guna:tamas | तमस् | tamas | Tamas (inertia) | Review | 8 |  | Dull, inert quality; maps onto a stale subject — no heartbeat, Dark OODA mode. | `uos_swarm/ooda.gleam:Dark mode` |
| tier | श्रेणी | śreṇī | Tier | Economy | 6 |  | Free or Paid classification of an allowlisted advisory model. | `uos_swarm/openrouter_worker.gleam:Tier` |
| routing-class:R0 | शून्य-श्रेणी | śūnya-śreṇī | R0 deterministic code | Economy | 6 |  | Runtime control: deterministic code, 0 tokens. | `contracts/rules/intelligence-routing-rule.md (SC-INTEL-ROUTING-001)` |
| routing-class:R1 | प्रथम-श्रेणी | prathama-śreṇī | R1 mechanical verification | Economy | 6 |  | Mechanical verification: script, else Haiku. | `contracts/rules/intelligence-routing-rule.md (SC-INTEL-ROUTING-001)` |
| routing-class:R2 | द्वितीय-श्रेणी | dvitīya-śreṇī | R2 docs/summaries | Economy | 6 |  | Docs/summaries: Haiku or OpenRouter nano. | `contracts/rules/intelligence-routing-rule.md (SC-INTEL-ROUTING-001)` |
| routing-class:R3 | तृतीय-श्रेणी | tṛtīya-śreṇī | R3 advisory second opinion | Economy | 6 |  | Advisory second opinion: free-first bounded OpenRouter. | `contracts/rules/intelligence-routing-rule.md (SC-INTEL-ROUTING-001)` |
| routing-class:R4 | चतुर्थ-श्रेणी | caturtha-śreṇī | R4 bounded implementation | Economy | 6 |  | Bounded implementation: Sonnet. | `contracts/rules/intelligence-routing-rule.md (SC-INTEL-ROUTING-001)` |
| routing-class:R5 | पञ्चम-श्रेणी | pañcama-śreṇī | R5 sovereign review | Economy | 6 |  | Sovereign security/architecture review: Codex Astra and Antigravity. | `contracts/rules/intelligence-routing-rule.md (SC-INTEL-ROUTING-001)` |
| routing-class:R6 | षष्ठ-श्रेणी | ṣaṣṭha-śreṇī | R6 design authority | Economy | 6 |  | Design authority, integration, admission: Fable only. | `contracts/rules/intelligence-routing-rule.md (SC-INTEL-ROUTING-001)` |
| budget | व्यय-सीमा | vyaya-sīmā | Budget | Economy | 6 |  | The USD ceiling an advisory call may not exceed (default 0.02 USD). | `uos_swarm/openrouter_worker.gleam:budget_usd_ceiling/Policy.budget_usd` |
| price-ceiling | मूल्य-सीमा | mūlya-sīmā | Price ceiling | Economy | 6 |  | The highest per-token price (USD) accepted for an allowlisted model. | `uos_swarm/openrouter_worker.gleam:Allowed.prompt_ceiling/completion_ceiling` |
| free-first | प्रथमतः-निःशुल्क | prathamataḥ-niḥśulka | Free-first | Economy | 6 |  | Free tiers are tried before any paid model; free-only is the default policy. | `uos_swarm/openrouter_worker.gleam:default_policy (free_only = True)` |
| antahkarana | अन्तःकरण | antaḥkaraṇa | Antaḥkaraṇa (inner instrument) | Thinking | 5 |  | The fourfold inner instrument of cognition; maps onto the agent's cognitive stack end to end. | `uos_swarm/system_ontology.gleam (Hindu thinking-structure mapping)` |
| antahkarana:manas | मनस् | manas | Manas (sensing mind) | Thinking | 5 |  | Manas gathers and filters sense-data; maps onto the OODA Observe phase. | `uos_swarm/ooda.gleam:step (Observe)` |
| antahkarana:buddhi | बुद्धि | buddhi | Buddhi (discerning intellect) | Thinking | 5 |  | Buddhi discriminates and decides; maps onto the OODA Decide phase and manager.step's control decision. The intelligence plane's own Sanskrit name is buddhi-tala. | `uos_swarm/manager.gleam:step (Decide); holon.gleam Intelligence plane = buddhi-tala` |
| antahkarana:ahamkara | अहंकार | ahaṃkāra | Ahaṃkāra (I-maker, self-model) | Thinking | 5 |  | Ahaṃkāra is the sense of 'I'; maps onto the agent's self-model as posted on the board (Agent id/layer/model). | `uos_swarm/board.gleam:Agent (self-model on the board)` |
| antahkarana:citta | चित्त | citta | Citta (mind-stuff, memory store) | Memory | 5 |  | Citta is the substrate that retains impressions; maps onto the agent's ETS live memory table. | `uos_swarm/agent_runtime.gleam:Memory; holon.gleam ets = smṛti` |
| pramana | प्रमाण | pramāṇa | Pramāṇa (valid means of knowledge) | Thinking | 5 |  | The four accepted means of valid cognition; maps onto the system's evidence sources for two-key verification. | `uos_swarm/system_ontology.gleam (epistemology mapping); DMC-TCM two-key verification` |
| pramana:pratyaksa | प्रत्यक्ष | pratyakṣa | Pratyakṣa (perception) | Thinking | 5 |  | Direct perception; maps onto observed runtime behaviour, the first key of two-key verification. | `DMC-TCM mandate: Fresh Empirical Behavior key` |
| pramana:anumana | अनुमान | anumāna | Anumāna (inference) | Thinking | 5 |  | Inference from evidence; maps onto Rete forward-chaining rules and Bayesian belief updates. | `uos_swarm/agent_runtime.gleam:ReteCap/BayesCap` |
| pramana:sabda | शब्द | śabda | Śabda (testimony) | Thinking | 5 |  | Verbal testimony from a trusted source; maps onto board Report messages and sovereign reviews. | `uos_swarm/board.gleam:Report kind; sovereign review` |
| pramana:upamana | उपमान | upamāna | Upamāna (comparison) | Thinking | 5 |  | Knowledge by comparison/analogy; maps onto differential oracles and the 17-aspect audit. | `uos_swarm/system_audit.gleam:Subject (audits); Hermes differential oracles` |
| citta-vrtti | चित्त-वृत्ति | citta-vṛtti | Citta-vṛtti (modifications of mind-stuff) | Memory | 5 |  | The five fluctuations of mind-stuff (Yoga Sūtra 1.6); maps onto the agent's cognitive/memory states. | `Yoga Sūtra 1.6; uos_swarm/agent_runtime.gleam:Memory` |
| citta-vrtti:pramana | प्रमाण | pramāṇa | Pramāṇa (valid cognition) | Memory | 5 |  | Valid cognition grounded in perception/inference/testimony; maps onto a verified, Pass-admitted evidence state. | `Yoga Sūtra 1.6; DMC-TCM evidence states` |
| citta-vrtti:viparyaya | विपर्यय | viparyaya | Viparyaya (error, misconception) | Memory | 5 |  | False cognition; maps onto a Fail verdict. | `Yoga Sūtra 1.6; uos_tui/aspects.gleam:Fail` |
| citta-vrtti:vikalpa | विकल्प | vikalpa | Vikalpa (imagination, conceptualisation) | Memory | 5 |  | Cognition built from words/imagination without a directly grounded object; maps onto the dream module's speculative output posted as a Hypothesize. | `Yoga Sūtra 1.6; uos_swarm/acl.gleam:Hypothesize (dream output)` |
| citta-vrtti:nidra | निद्रा | nidrā | Nidrā (sleep) | Memory | 5 |  | The vṛtti of contentless sleep; maps onto an agent's Idle lifecycle line. | `Yoga Sūtra 1.6; uos_swarm/agent_runtime.gleam:Idle` |
| citta-vrtti:smrti | स्मृति | smṛti | Smṛti (memory) | Memory | 5 |  | Retention of past experience; maps onto the ETS live table and the episodic memory namespace. | `holon.gleam:ets = smṛti; uos_swarm/agent_runtime.gleam:remember` |
| kosha | पञ्च-कोश | pañca-kośa | Pañca-kośa (the five sheaths) | Structure | 5 |  | The five sheaths from gross to subtle; maps onto the system's layers from hardware to admitted harmony. | `Taittirīya Upaniṣad 2; uos_swarm/system_ontology.gleam (layer mapping)` |
| kosha:annamaya | अन्नमय | annamaya | Annamaya-kośa (matter sheath) | Structure | 1 | 1 | The gross material sheath; maps onto the hardware substrate and the BEAM VM it runs on. | `uos_tui/aspects.gleam:SubstrateStorageSafety` |
| kosha:pranamaya | प्राणमय | prāṇamaya | Prāṇamaya-kośa (vital-breath sheath) | Structure | 4 | 4 | The sheath of vital energy; maps onto running BEAM processes and the OTP supervisor. | `uos_tui/aspects.gleam:GleamOtpSupervisor` |
| kosha:manomaya | मनोमय | manomaya | Manomaya-kośa (mind sheath) | Structure | 5 |  | The sheath of mind; maps onto the agents themselves and their OODA loops. | `uos_swarm/ooda.gleam (agent mind loop)` |
| kosha:vijnanamaya | विज्ञानमय | vijñānamaya | Vijñānamaya-kośa (discernment sheath) | Structure | 0 |  | The sheath of discerning knowledge; maps onto formal verification and the 17-aspect audit. | `uos_tui/aspects.gleam (verification)` |
| kosha:anandamaya | आनन्दमय | ānandamaya | Ānandamaya-kośa (bliss sheath) | Structure | 9 |  | The innermost sheath of bliss/harmony; maps onto the final `admitted` evidence state where discovered -> ... -> admitted closes without residue. | `CLAUDE.md Section 6: Evidence, Gates, and Completion Semantics (admitted)` |
| swara | स्वर | svara | Svara (musical note) | Music | 2 |  | The seven svara (sa ri ga ma pa dha ni), the base pitches used by the music module. | `music domain (definitions only; out of this worker's owned scope)` |
| thaat | थाट | thāṭ | Thāṭ (parent scale) | Music | 2 |  | A parent scale (one of the 10 Hindustani thāṭ) from which rāga are derived. | `music domain (definitions only; out of this worker's owned scope)` |
| raga | राग | rāga | Rāga (melodic framework) | Music | 2 |  | A melodic framework of specific notes, phrases and mood used by the music module. | `music domain (definitions only; out of this worker's owned scope)` |
| tala | ताल | tāla | Tāla (rhythmic cycle) | Music | 2 |  | A cyclic rhythmic pattern counted in beats (mātrā), used by the music module. | `music domain (definitions only; out of this worker's owned scope)` |
