| IAST | Devanagari | English | Definition |
|---|---|---|---|
| abhisandhi | अभिसन्धि | Intent | A declared intent, rank-strict (must target L0/L1). |
| abhisandhi-utsarjana | अभिसन्धि-उत्सर्जन | emit_intent | STPA control action `emit_intent` dispatched by CTRL-TUI-APP. |
| acala-sthāpana | अचल-स्थापन | Immutable commit | A commit past the configured immutable boundary (e.g. already integrated); jj refuses to rewrite it, protecting shared history from silent mutation. |
| adhigrahaṇa | अधिग्रहण | Claim | An agent claims a task under a fenced lease. |
| adhigrahaṇa | अधिग्रहण | Claim | A lease on `task:<id>` subject to the swarm's WIP limit. |
| adhikāra | अधिकार | Hierarchical authority | Holon uos/holon/L3/policy (uos_tui/coord (authorize)), whole coord. |
| adhiṣṭhātṛ | अधिष्ठातृ | L0 design authority (Fable) | Holon uos/holon/L0/supervisor (uos_tui/coord (policy)), whole uos. |
| adhiṣṭhātṛ | अधिष्ठातृ | Design authority | Design decisions (Plan/Dispatch/Integrate/Andon broadcasts) come only from the design authority model roster. |
| adhyakṣa | अध्यक्ष | Gleam/OTP Root Supervisor | 17-aspect audit check #4: Gleam/OTP Root Supervisor. |
| ahaṃkāra | अहंकार | Ahaṃkāra (I-maker, self-model) | Ahaṃkāra is the sense of 'I'; maps onto the agent's self-model as posted on the board (Agent id/layer/model). |
| andhakāra | अन्धकार | Dark | Cockpit mode: minimum draw, only heartbeats. |
| annamaya | अन्नमय | Annamaya-kośa (matter sheath) | The gross material sheath; maps onto the hardware substrate and the BEAM VM it runs on. |
| antaḥkaraṇa | अन्तःकरण | Antaḥkaraṇa (inner instrument) | The fourfold inner instrument of cognition; maps onto the agent's cognitive stack end to end. |
| anujñā | अनुज्ञा | Grant | A scoped, expiring, opaque capability token minted only by L0/L1 and tracked as a board message. |
| anumāna | अनुमान | Anumāna (inference) | Inference from evidence; maps onto Rete forward-chaining rules and Bayesian belief updates. |
| atiprakriyā | अतिप्रक्रिया | Overprocessing | Muda: doing more work on a slice than the spec requires. |
| atyutpādana | अत्युत्पादन | Overproduction | Muda: producing more, sooner, or faster than the next station needs. |
| avalokana | अवलोकन | observe | OODA: gather the observation window (manas). |
| avarodha | अवरोध | Hold | The line-stopped state entered by jidoka when no_failures fails, pending a fix and sovereign review. |
| aviphala | अविफल | No-failures gate | The softer gate: zero Fail findings, Declared tolerated (used for jidoka stop/resume). |
| aṅga | अङ्ग | Widget | textual.widget.Widget -> uos_tui/widget.Widget(msg) (Homomorphic). class hierarchy becomes one closed sum type; state lives in the model |
| aṅga | अङ्ग | Widget catalog (17 families) | Holon uos/holon/L3/widgets (uos_tui/widget), whole app. |
| bandhana | बन्धन | Binding / action | textual.binding.Binding -> uos_tui/widget.Binding(msg) (Isomorphic). key -> msg with description shown in Footer |
| bhāṣā-tala | भाषा-तल | Language plane | Holon uos/holon/L1/language-plane (uos_tui/acl), whole planes. |
| buddhi | बुद्धि | Buddhi (discerning intellect) | Buddhi discriminates and decides; maps onto the OODA Decide phase and manager.step's control decision. The intelligence plane's own Sanskrit name is buddhi-tala. |
| buddhi-tala | बुद्धि-तल | Intelligence plane | Holon uos/holon/L1/intelligence-plane (uos_tui/manager), whole planes. |
| cakra | चक्र | Fast OODA controller | Holon uos/holon/L3/ooda (uos_tui/ooda), whole manager. |
| caturtha-śreṇī | चतुर्थ-श्रेणी | R4 bounded implementation | Bounded implementation: Sonnet. |
| citra-kāra | चित्र-कार | Compositor | textual._compositor -> uos_tui/render.compose/arrange (Homomorphic). placements blitted into a frame; no dirty-region diffing yet |
| citra-kāra | चित्र-कार | Compositor | Holon uos/holon/L3/render (uos_tui/render), whole app. |
| citrāṅkana | चित्राङ्कन | paint_frame | STPA control action `paint_frame` dispatched by CTRL-TUI-DRIVER. |
| citta | चित्त | Citta (mind-stuff, memory store) | Citta is the substrate that retains impressions; maps onto the agent's ETS live memory table. |
| citta-vṛtti | चित्त-वृत्ति | Citta-vṛtti (modifications of mind-stuff) | The five fluctuations of mind-stuff (Yoga Sūtra 1.6); maps onto the agent's cognitive/memory states. |
| cālaka | चालक | Driver | textual.driver -> uos_tui/live.run/child_spec (Homomorphic). OTP actor + reader process; raw mode via pure Erlang shell API |
| dattāṃśa-sāraṇī | दत्तांश-सारणी | DataTable | textual.widgets.DataTable -> uos_tui/widget.DataTable (Homomorphic). row cursor only |
| dattāṃśa-tala | दत्तांश-तल | Data plane | Holon uos/holon/L1/data-plane (uos_tui/board (ledger)), whole planes. |
| doṣa | दोष | Defects | Muda: rework caused by a verification failure that should have been caught earlier. |
| dvi-kuñcikā-satyāpana | द्वि-कुञ्चिका-सत्यापन | Two-key verification | Trust requires BOTH fresh observed runtime behaviour AND a machine-verifiable formal specification. |
| dvitīya-śreṇī | द्वितीय-श्रेणी | R2 docs/summaries | Docs/summaries: Haiku or OpenRouter nano. |
| dūra-mitī | दूर-मिती | Zenoh OoZ & MoZ Mesh Telemetry | 17-aspect audit check #10: Zenoh OoZ & MoZ Mesh Telemetry. |
| dṛṣṭi-śṛṅkhalā | दृष्टि-शृङ्खला | Focus chain | textual.screen.focus_chain -> uos_tui/app.move_focus (Isomorphic). document-order Tab/Shift-Tab |
| ekīkṛta-kārya-tantra | एकीकृत-कार्य-तन्त्र | Unified Operational System | Holon uos/holon/L0/uos (apps/uos_tui), whole (root). |
| gati | गति | Motion | Muda: unnecessary context switching or re-reading by an agent. |
| gati-kāla | गति-काल | Takt time | The target minutes per card that keeps the swarm at customer pace. |
| gaṇita-adhikāra | गणित-अधिकार | Mathematical Authority & Conservation | 17-aspect audit check #7: Mathematical Authority & Conservation. |
| ghaṭanā-srota | घटना-स्रोत | AG-UI 32-Event SSE Stream | 17-aspect audit check #11: AG-UI 32-Event SSE Stream. |
| ghoṣita | घोषित | Declared | Bound by declaration/config, not fresh observed behaviour. |
| guṇa | गुण | Guṇa (the three qualities) | Sāṃkhya's three qualities, used here as a state classification for system health: sattva, rajas, tamas. |
| gṛhīta | गृहीत | Claimed | F´ lifecycle: claimed under a lease, not yet started. |
| hastākṣara | हस्ताक्षर | Signature | An HMAC over the message digest with a per-agent derived key; a shared master key never signs directly. |
| jñāna-trika | ज्ञान-त्रिक | Knowledge Management Triad | 17-aspect audit check #16: Knowledge Management Triad. |
| jāla-mārga-darśana | जाल-मार्ग-दर्शन | Universal Tailscale FQDN Web Navigation | 17-aspect audit check #14: Universal Tailscale FQDN Web Navigation. |
| jāla-sevā | जाल-सेवा | Textual Web / serve | textual-serve -> uos_tui/frame.to_text/to_ansi (Deferred). projection to Wisp at :4100 is a follow-on |
| jīrṇa-kārya-pratilipi | जीर्ण-कार्य-प्रतिलिपि | Stale working copy | A workspace's working copy that no longer matches its recorded commit because another process wrote to the shared repository; readers avoid provoking it against a workspace they do not own (`--ignore-working-copy`). |
| jīva-cālaka | जीव-चालक | OTP live driver | Holon uos/holon/L2/live (uos_tui/live), whole runtime-plane. |
| jīva-saṅketa-vijñāna | जीव-सङ्केत-विज्ञान | Biosemiotic Cybernetics & Rocha Cut | 17-aspect audit check #8: Biosemiotic Cybernetics & Rocha Cut. |
| kaccā-praveśa | कच्चा-प्रवेश | enter_raw | STPA control action `enter_raw` dispatched by CTRL-TUI-DRIVER. |
| kalpanā | कल्पना | Hypothesize | Offers an unproven proposition for testing (the dream module's output). |
| khaṇḍa | खण्ड | Segment / Strip | rich.segment / textual.strip -> uos_tui/segment.Strip (Isomorphic). styled runs with cached cell length; crop/extend/simplify |
| khaṇḍa-satyāpana | खण्ड-सत्यापन | verify_slice | STPA control action `verify_slice` dispatched by CTRL-SWARM-VERIFIER. |
| khaṇḍa-saṃyojana | खण्ड-संयोजन | integrate_slice | STPA control action `integrate_slice` dispatched by CTRL-SWARM-L0. |
| kośa | कोश | Sanskrit/English lexicon | Holon uos/holon/L3/lexicon (uos_tui/acl (lexicon)), whole acl. |
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
| lekhā | लेखा | Append-only JSONL ledger | Holon uos/holon/L2/ledger (uos_tui/board (jsonl)), whole data-plane. |
| manas | मनस् | Manas (sensing mind) | Manas gathers and filters sense-data; maps onto the OODA Observe phase. |
| manda | मन्द | Dim | Cockpit mode: low draw, occasional repaint. |
| manomaya | मनोमय | Manomaya-kośa (mind sheath) | The sheath of mind; maps onto the agents themselves and their OODA loops. |
| matam | मतम् | Belief memory | Namespace `belief/`: doxastic state the agent holds but has not asserted. |
| megha-smṛti | मेघ-स्मृति | Zenoh memory storages | Holon uos/holon/L2/zenoh-storage (ops/zenoh (storage_manager)), whole data-plane. |
| mukhya-saṅketa | मुख्य-सङ्केत | Main bookmark | The `main` bookmark, left uncreated until final system admission (EV-15); until then work proceeds only on feature and `integration/*` bookmarks. |
| mārga-darśaka | मार्ग-दर्शक | Zenoh router c3i-zenoh-router-1 | Holon uos/holon/L2/zenoh-router (ops/zenoh), whole messaging-plane. |
| mātrā | मात्रा | Scalar / fr units | textual.css.scalar -> uos_tui/layout.Scalar (Isomorphic). Cells, Fraction, Percent, Auto |
| mūla-yantra | मूल-यन्त्र | TEA application core | Holon uos/holon/L2/app (uos_tui/app), whole runtime-plane. |
| mūlya-sīmā | मूल्य-सीमा | Price ceiling | The highest per-token price (USD) accepted for an allowlisted model. |
| mṛta-patra | मृत-पत्र | DeadLetter | A message retried past its limit and dead-lettered. |
| navīna | नवीन | New | Creating a new, empty working-copy change on top of one or more parents (`jj new`), the usual way work begins. |
| nidrā | निद्रा | Nidrā (sleep) | The vṛtti of contentless sleep; maps onto an agent's Idle lifecycle line. |
| nirgama-peṭikā | निर्गम-पेटिका | Transactional outbox | Durable ledger acceptance gates publication: a message is Outboxed before any Zenoh put is attempted. |
| nirākaraṇa | निराकरण | Reject | Rejects a prior Request/Propose, with a reason. |
| nirṇaya | निर्णय | Verdict | A verifier's admit/reject decision. |
| nirṇaya | निर्णय | decide | OODA: choose the mode and actions (buddhi). |
| niyama | नियम | Rete (rule matcher) | Bounded forward-chaining matcher over typed facts (naive unification, not a full Rete network). |
| niyantraṇa-tala | नियन्त्रण-तल | Control plane | Holon uos/holon/L1/control-plane (uos_tui/coord), whole planes. |
| niyata-yantra | नियत-यन्त्र | ZigVM Deterministic Engine & VFS Laws | 17-aspect audit check #5: ZigVM Deterministic Engine & VFS Laws. |
| niṣkriya | निष्क्रिय | Idle | F´ lifecycle: unclaimed, no lease held. |
| nāma-paṭṭikā | नाम-पट्टिका | Static/Label | textual.widgets.Static -> uos_tui/widget.Static (Isomorphic).  |
| parityāga | परित्याग | Abandon | Discarding a change (and rebasing its descendants onto its parent); recorded in the operation log and reversible by undo, never a silent deletion. |
| parivahana | परिवहन | Transport | Muda: unnecessary movement of work or artifacts between agents. |
| parivartana-cayana | परिवर्तन-चयन | Revset | A revset-language expression that selects a set of changes (by id, bookmark, ancestry, or predicate) for a command to act on. |
| parivartana-nāma | परिवर्तन-नाम | Change id | The stable identity of an edit across rewrites (rebase/squash/split change its content but never its change id) — the primary handle a worker or reviewer names. |
| parivartana-sthāpana-bheda | परिवर्तन-स्थापन-भेद | Change vs. commit | The fundamental Jujutsu distinction: change id is stable identity, commit id is a content hash of one revision of that identity — a worker must never equate the two. |
| parivartana-tantra | परिवर्तन-तन्त्र | Jujutsu version control | Holon uos/holon/L2/jujutsu (uos_swarm/jj), whole structure-plane. |
| parīkṣaka | परीक्षक | Pilot / run_test | textual.pilot.Pilot -> uos_tui/headless.run (Isomorphic). scripted events, captured frames |
| parīkṣaka | परीक्षक | Headless pilot | Holon uos/holon/L2/headless (uos_tui/headless), whole runtime-plane. |
| parīkṣyamāṇa | परीक्ष्यमाण | Verifying | Kanban column: submitted, awaiting verification. |
| parīkṣyamāṇa | परीक्ष्यमाण | Verifying | F´ lifecycle: submitted, awaiting verification. |
| pañca-kośa | पञ्च-कोश | Pañca-kośa (the five sheaths) | The five sheaths from gross to subtle; maps onto the system's layers from hardware to admitted harmony. |
| pañca-stara-sulabhatā | पञ्च-स्तर-सुलभता | Penta-Stack Multi-Interface Accessibility | 17-aspect audit check #13: Penta-Stack Multi-Interface Accessibility. |
| pañcama-śreṇī | पञ्चम-श्रेणी | R5 sovereign review | Sovereign security/architecture review: Codex Astra and Antigravity. |
| paṭala | पटल | Screen | textual.screen.Screen -> uos_tui/app.Screen (Isomorphic). named view over the model; push/pop via PushScreen/PopScreen effects |
| paṭala-parīkṣā | पटल-परीक्षा | audit_screen | STPA control action `audit_screen` dispatched by CTRL-TUI-ASPECTS. |
| paṭṭa-niyantrita-mukhya-gamana | पट्ट-नियन्त्रित-मुख्य-गमन | Lease-gated main move | The rule that the `main` bookmark (once created) may move only under a live `integration/main` lease together with a recorded decision — never by an unaudited direct move (BG 18.63: full analysis offered, the choice remains the authority's). |
| paṭṭā | पट्टा | Fenced leases | Holon uos/holon/L3/leases (uos_tui/coord (acquire/renew/release)), whole coord. |
| paṭṭā | पट्टा | Lease | A fenced, time-bounded hold on a resource with a monotonically increasing epoch. |
| paṭṭā-anujñā | पट्टा-अनुज्ञा | LeaseGrant | Grant of a fenced lease/epoch. |
| paṭṭā-mukti | पट्टा-मुक्ति | LeaseRelease | Release of a held lease. |
| prabandhaka | प्रबन्धक | F´ managing agent | Holon uos/holon/L2/manager (uos_tui/manager), whole intelligence-plane. |
| pragati | प्रगति | Progress | An in-flight progress update. |
| pragati-paṭṭī | प्रगति-पट्टी | ProgressBar | textual.widgets.ProgressBar -> uos_tui/widget.ProgressBar (Isomorphic).  |
| prakāśa | प्रकाश | Bright | Cockpit mode: elevated cadence plus an aspect audit. |
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
| pravartana-tala | प्रवर्तन-तल | Runtime plane | Holon uos/holon/L1/runtime-plane (uos_tui/live), whole planes. |
| praveśa | प्रवेश | Input | textual.widgets.Input -> uos_tui/widget.Input (Homomorphic). no validators/suggester |
| praśna | प्रश्न | Question | A question posted to another agent. |
| praśna | प्रश्न | Query | Asks the receiver to Inform on a proposition. |
| preṣaka-śṛṅkhalā | प्रेषक-शृङ्खला | Per-sender digest chain | One SHA-256 hash chain per sender (multi-writer safe), ordered by id within the sender. |
| preṣaṇa | प्रेषण | Dispatch | L0/L1 dispatch of work to an agent. |
| prākṛta-git-vikāra | प्राकृत-गिट्-विकार | Native git mutation | Any direct Git-mutating command (`git commit`, `git push`, `git checkout`, etc.); strictly prohibited inside the standalone UOS repository regardless of tooling convenience. |
| prārthanā | प्रार्थना | Request | Requests the receiver to accept or reject doing an action. |
| prāṇamaya | प्राणमय | Prāṇamaya-kośa (vital-breath sheath) | The sheath of vital energy; maps onto running BEAM processes and the OTP supervisor. |
| punar-ādhāra | पुनराधार | Rebase | Replaying a change (and its descendants) onto a new parent, producing new commit ids while preserving change ids; the mechanism by which integration serializes worker changes in order. |
| puṣṭi | पुष्टि | Confirm | Confirms a belief the receiver was uncertain of. |
| puṣṭi-paṭala-preṣaṇa | पुष्टि-पटल-प्रेषण | push_confirm_screen | STPA control action `push_confirm_screen` dispatched by CTRL-TUI-APP. |
| pātra | पात्र | Container | textual.containers -> uos_tui/widget.Container, Grid (Isomorphic). border + title like Textual border-title |
| racanā | रचना | compose() | Widget.compose -> uos_tui/app.Screen.view (Isomorphic). pure function model -> tree |
| rajas | रजस् | Rajas (activity) | Active, restless quality; maps onto churn — high Progress/Dispatch traffic on the board. |
| rekhā | रेखा | Rule | textual.widgets.Rule -> uos_tui/widget.Rule (Isomorphic).  |
| rekhā-śṛṅkhala-saṃyojana | रेखा-शृङ्खला-संयोजन | Linear-chain integration | The integration pattern by which verified worker changes are rebased onto the integration bookmark one after another, in order, rather than merged concurrently; a conflict stops the chain. |
| rāga | राग | Rāga (melodic framework) | A melodic framework of specific notes, phrases and mood used by the music module. |
| sahasthita-nikṣepa | सहस्थित-निक्षेप | Colocated repository | A `.jj/` repository backed by a sibling `.git/` directory; permitted by upstream Jujutsu but strictly barred inside `/home/an/NAS-setup/uos`. |
| sahodara-kārya-kṣetra | सहोदर-कार्य-क्षेत्र | Sibling workspace | One of the `.uos-workspaces/*` peer workspaces used for parallel work streams (e.g. this worker's `jj-2`); each owns a disjoint file scope (BG 3.35, svadharma). |
| samagra-sūcī-patra | समग्र-सूची-पत्र | Comprehensive Verification Checklist | 17-aspect audit check #15: Comprehensive Verification Checklist. |
| samanvaya | समन्वय | Coordination & sync | Holon uos/holon/L2/coord (uos_tui/coord), whole control-plane. |
| samanvaya | समन्वय | Reconcile | Merge a remote view of the board into the local one; a differing prior digest is a conflict, quarantined by refusal. |
| sambhāvanā | सम्भावना | Bayes (Beta-Binomial belief) | Bayesian (Beta-Binomial) success belief per (agent, model), used for cheapest-adequate routing. |
| sambhāṣā | सम्भाषा | Agent communication language | Holon uos/holon/L2/acl (uos_tui/acl), whole language-plane. |
| sandeśa | सन्देश | Message / Event | textual.message / textual.events -> uos_tui/event.Event, msg (Homomorphic). system events typed; widget messages are user-typed msg |
| sandeśa-phalaka | सन्देश-फलक | Message board | Holon uos/holon/L2/board (uos_tui/board), whole messaging-plane. |
| sandeśa-tala | सन्देश-तल | Messaging plane | Holon uos/holon/L1/messaging-plane (uos_tui/board), whole planes. |
| sapta-tala | सप्त-तल | Seven planes | Holon uos/holon/L1/planes (uos_tui/holon), whole uos. |
| saptadaśa-pakṣa | सप्तदश-पक्ष | 17 Aspect audit | (none) -> uos_tui/aspects.audit (Reinterpreted). UOS-only: fail-closed structural verification of a composed screen |
| saptadaśa-pakṣa | सप्तदश-पक्ष | 17-aspect audit | Holon uos/holon/L2/aspects (uos_tui/aspects), whole structure-plane. |
| sarva-parīkṣā | सर्व-परीक्षा | System-wide audit | Holon uos/holon/L2/system-audit (uos_tui/system_audit), whole intelligence-plane. |
| sattva | सत्त्व | Sattva (clarity) | Clear, balanced quality; maps onto a subject with zero Fail and zero Declared findings. |
| sattā-śāstra | सत्ता-शास्त्र | Fractal Textual ontology | Holon uos/holon/L2/ontology (uos_tui/ontology), whole structure-plane. |
| saṃgraha | संग्रह | Inventory | Muda: unclaimed or unmerged work piling up (WIP above takt capacity). |
| saṃgraha-surakṣā | संग्रह-सुरक्षा | Substrate & Hardware Storage Safety | 17-aspect audit check #1: Substrate & Hardware Storage Safety. |
| saṃracanā-tala | संरचना-तल | Structure plane | Holon uos/holon/L1/structure-plane (uos_tui/ontology), whole planes. |
| saṃyojana | संयोजन | Integrate | L0/L1 integration of a verified slice. |
| saṃyojana-saṅketa | संयोजन-सङ्केत | Integration bookmark | An `integration/*` bookmark (e.g. `integration/main`) where verified sibling-workspace slices are rebased in and serialized under a live lease. |
| saṅgarodha | सङ्गरोध | Quarantine | A malformed or refused artifact is preserved verbatim for inspection, never dropped and never silently absorbed. |
| saṅgarodhita-anumāna | सङ्गरोधित-अनुमान | Quarantined Modular MAX Inference | 17-aspect audit check #9: Quarantined Modular MAX Inference. |
| saṅkalpa | सङ्कल्प | Commit | Commits the speaker to completing an action by a deadline. |
| saṅketa | सङ्केत | Bookmark | A named, movable pointer to a change (Jujutsu's analogue of a Git branch); moved explicitly, never implicitly by commit. |
| saṅkoca | सङ्कोच | Squash | Folding a change's content into its parent, contracting two commits into one while the parent's change id survives. |
| saṅkocanīya | सङ्कोचनीय | Collapsible | textual.widgets.Collapsible -> uos_tui/widget.Checklist (Reinterpreted). UOS 5-domain/18-item checklist accordion (SC-CHECKLIST-001) |
| siddha | सिद्ध | Done | Kanban column: verified and accepted. |
| siddha | सिद्ध | Done | F´ lifecycle: verified and accepted. |
| siddha | सिद्ध | Pass | Freshly, positively evidenced. |
| smṛti | स्मृति | ETS live table | Holon uos/holon/L2/ets (uos_swarm_ffi.erl (ets)), whole data-plane. |
| smṛti | स्मृति | Smṛti (memory) | Retention of past experience; maps onto the ETS live table and the episodic memory namespace. |
| spandana | स्पन्दन | Freshness monitor | Holon uos/holon/L3/heartbeats (uos_tui/coord (beat/stale)), whole coord. |
| spandana | स्पन्दन | Heartbeat | A freshness pulse from a live agent. |
| spandana | स्पन्दन | Heartbeat | A periodic freshness pulse; its absence trips the dead-man's-switch. |
| sparśaka | स्पर्शक | Button | textual.widgets.Button -> uos_tui/widget.Button (Isomorphic).  |
| sthāpita-sāra | स्थापित-सार | Commit id | The content hash of one specific snapshot of a change; every rewrite (rebase, squash, describe) produces a new commit id even though the change id is unchanged. |
| sthāyitā-yojanā | स्थायिता-योजना | Sa-Plan & Bionic Durable Workflows | 17-aspect audit check #17: Sa-Plan & Bionic Durable Workflows. |
| surakṣā | सुरक्षा | STPA & FMEA safety | Holon uos/holon/L2/stpa (uos_tui/stpa), whole control-plane. |
| svara | स्वर | Svara (musical note) | The seven svara (sa ri ga ma pa dha ni), the base pitches used by the music module. |
| svatantra-nikṣepa | स्वतन्त्र-निक्षेप | Standalone repository | A non-colocated `.jj/` repository with no backing `.git/` directory — the sole VCS mode admitted for UOS (CLAUDE.md §4). |
| svatantra-saṃskaraṇa | स्वतन्त्र-संस्करण | Standalone Jujutsu Monorepo Discipline | 17-aspect audit check #2: Standalone Jujutsu Monorepo Discipline. |
| svayaṃ-nirodha | स्वयं-निरोध | Jidoka | A stop-the-line signal. |
| svayaṃ-nirodha | स्वयं-निरोध | Jidoka (stop-the-line) | Autonomation: stop the line the instant a defect is detected, rather than pass it on. |
| svāmitva-patra-lekhana | स्वामित्व-पत्र-लेखन | write_owned_file | STPA control action `write_owned_file` dispatched by CTRL-SWARM-L0. |
| svīkāra | स्वीकार | Accept | Accepts a prior Request/Propose; the speaker now intends to act. |
| svīkārya | स्वीकार्य | Admissible | Strict two-key admission: zero Fail AND zero Declared findings. |
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
| tamas | तमस् | Tamas (inertia) | Dull, inert quality; maps onto a stale subject — no heartbeat, Dark OODA mode. |
| thāṭ | थाट | Thāṭ (parent scale) | A parent scale (one of the 10 Hindustani thāṭ) from which rāga are derived. |
| tāla | ताल | Tāla (rhythmic cycle) | A cyclic rhythmic pattern counted in beats (mātrā), used by the music module. |
| tṛtīya-śreṇī | तृतीय-श्रेणी | R3 advisory second opinion | Advisory second opinion: free-first bounded OpenRouter. |
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
| śabda-kośa | शब्द-कोश | F´ dictionaries | Holon uos/holon/L2/fprime (uos_tui/fprime), whole structure-plane. |
| śailī | शैली | TCSS | textual.css -> uos_tui/style.Style (Reinterpreted). no CSS parser; typed style records with a combine monoid |
| śiras-pāda | शिरस्-पाद | Header/Footer | textual.widgets -> uos_tui/widget.Header, Footer (Isomorphic).  |
| śreṇī | श्रेणी | Tier | Free or Paid classification of an allowlisted advisory model. |
| śreṇī-niyata-saṅkalpa | श्रेणी-नियत-सङ्कल्प | Rank-strict intent | An Intent message must target a strictly higher-ranked layer than its sender. |
| śūnya-vyartha-śuddhi | शून्य-व्यर्थ-शुद्धि | Zero-Muda Purity & Waste Elimination | 17-aspect audit check #3: Zero-Muda Purity & Waste Elimination. |
| śūnya-śreṇī | शून्य-श्रेणी | R0 deterministic code | Runtime control: deterministic code, 0 tokens. |
| ṣaṣṭha-śreṇī | षष्ठ-श्रेणी | R6 design authority | Design authority, integration, admission: Fable only. |
