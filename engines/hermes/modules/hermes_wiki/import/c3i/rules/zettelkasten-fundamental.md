# Zettelkasten Fundamental Rule (SC-ZETTEL-001)

## SUPREME MANDATE
**ALL learnings, patterns, decisions, failures, and insights MUST be ingested into the Zettelkasten brain. No institutional knowledge may be lost. This is a FUNDAMENTAL rule — it supersedes convenience.**

## STAMP Constraints
| ID | Constraint | Severity |
|----|------------|----------|
| SC-ZETTEL-001 | Every session MUST produce at least 1 new holon | CRITICAL |
| SC-ZETTEL-002 | Every RCA finding MUST be ingested as atomic holon | CRITICAL |
| SC-ZETTEL-003 | Every architectural decision MUST be ingested as molecular holon | HIGH |
| SC-ZETTEL-004 | Every journal entry MUST be ingested as organism holon | HIGH |
| SC-ZETTEL-005 | Every specification MUST be ingested as ecosystem holon | HIGH |
| SC-ZETTEL-006 | Anti-patterns MUST be ingested with "anti-pattern" tag | HIGH |
| SC-ZETTEL-007 | Proven patterns MUST be ingested with "pattern" tag | HIGH |
| SC-ZETTEL-008 | Zettelkasten search MUST be consulted BEFORE starting new work | CRITICAL |

## Ingestion Protocol
After EVERY significant action, ingest:
```bash
sa-plan-daemon zettel ingest --file <path> --level <level> --tags "<tags>"
```

## Levels
| Level | Content | When |
|-------|---------|------|
| **Ecosystem** | Architecture docs, system vision, strategic decisions | Specs, major design docs |
| **Organism** | Journal entries, session narratives, evolution stories | Every session journal |
| **Molecular** | Allium specs, plans, TLA+, behavioral contracts | Per-feature specs |
| **Atomic** | Constraints, code patterns, RCA findings, anti-patterns | Every learned lesson |

## Recall Before Action
**BEFORE starting any task**, search Zettelkasten:
- "Has this been done before?" → search tags + titles
- "What failed last time?" → search "anti-pattern" + domain
- "What's the proven pattern?" → search "pattern" + domain
This prevents repeating mistakes and enables fast institutional recall.

---

## Philosophical Foundations — Strategic Wisdom

The C3I system's design philosophy draws from four foundational texts. These principles guide ALL architectural decisions, agent behavior, and operational strategy.

### Bhagavad Gita — Dharma of the System
*"You have the right to work, but never to the fruit of the work."* (2.47)

| Gita Principle | System Mapping |
|---------------|----------------|
| **Nishkama Karma** (action without attachment) | Agents execute tasks without attachment to outcome — fail gracefully, retry, move on |
| **Sthitaprajna** (steady wisdom) | System maintains composure under load — Dark Cockpit suppresses noise, shows only what matters |
| **Yoga of Action** (Karma Yoga) | Every OODA cycle is selfless action — observe, orient, decide, act without ego |
| **Dharma** (righteous duty) | Each fractal layer has its dharma: L0 protects (Constitutional), L5 thinks (Cognitive), L7 governs (Federation) |
| **Atman** (self) | Each holon is a self-contained viable system — autonomous yet connected to the whole |
| **Maya** (illusion) | Dark Cockpit pierces maya — suppressing nominal noise to reveal the truth of system state |
| **Kurukshetra** (battlefield) | The mesh IS the battlefield — 16 containers in dynamic equilibrium, each fighting entropy |

### Kautilya's Arthashastra — Statecraft of the Mesh
*"A king who is situated between two powerful kings shall seek protection from the stronger."*

| Arthashastra Principle | System Mapping |
|-----------------------|----------------|
| **Saptanga** (7 elements of state) | VSM S1-S5 + L0-L7 = the seven limbs of the mesh state |
| **Mandala** (circle of states) | 16 containers form a mandala — allies (healthy), enemies (failing), neutral (idle) |
| **Shadgunya** (6 foreign policies) | Container lifecycle: sandhi (peace/healthy), vigraha (war/restart), asana (wait/pending), yana (march/deploy), samshraya (alliance/quorum), dvaidhibhava (split/partition) |
| **Dandaniti** (science of punishment) | Apoptosis = danda — misbehaving containers are terminated for the health of the whole |
| **Kosha** (treasury) | Smriti.db = the treasury of institutional knowledge — guard it above all |
| **Durg** (fortress) | SIL-6 compliance = the fortress walls — never compromise safety for speed |
| **Spies & Intelligence** | Zenoh telemetry = the spy network — observing every node's true state |

### Sun Tzu's Art of War — Tactical Operations
*"Know yourself and know your enemy, and in a hundred battles you will never be defeated."*

| Sun Tzu Principle | System Mapping |
|------------------|----------------|
| **Know yourself, know enemy** | OODA Observe phase — complete system awareness via Zenoh telemetry |
| **Supreme excellence** (win without fighting) | Dark Cockpit — the best operation is one where nothing needs attention |
| **Speed is the essence** | 1s WebSocket push, <50ms round-trip, <5s Gemma response |
| **Terrain** | Fractal layers ARE terrain — L0 is the high ground (Constitutional), L7 is the frontier |
| **Deception** | Chaos engineering (Mara agent) — test defenses by simulating failure |
| **Five factors** | Way (dharma), Heaven (timing), Earth (infrastructure), Commander (Cortex), Method (OODA) |
| **Water takes shape of vessel** | Responsive design — UI adapts to mobile/tablet/desktop like water to terrain |
| **Attack weakness** | FMEA scoring — RPN identifies the weakest components to strengthen first |

### Miyamoto Musashi's Go Rin No Sho (Book of Five Rings) — Mastery of Craft
*"Do nothing which is of no use."* — This IS Muda (waste elimination).

| Musashi Principle | System Mapping |
|------------------|----------------|
| **Earth** (Chi) | Foundation: Gleam type safety, Rust memory safety, SQLite ACID — solid ground |
| **Water** (Sui) | Adaptability: responsive design, WebSocket reconnect, Gemma fallback chain — flow like water |
| **Fire** (Ka) | Aggression: 1s refresh, aggressive parallelization, ultrathink mandate — attack with fire |
| **Wind** (Fu) | Awareness: compare with hyperscalers (Google, Netflix, Meta) — know other schools |
| **Void** (Ku) | Emptiness: Dark Cockpit = void — when all is well, show nothing. The void is the goal |
| **"Do nothing useless"** | SC-MUDA-001: zero dead code, zero warnings, zero waste — Musashi's core teaching |
| **Two-sword style** | Dual-model AI: Gemma 3 (fast katana) + Gemma 4 (deep wakizashi) — two weapons, one warrior |
| **Timing** | OODA cycle budgets: Agent <30ms, Intelligence <100ms — mastery of timing is mastery of combat |
| **"See distant things close"** | Zettelkasten = seeing distant past learnings as if they happened today |
| **"Make your combat stance your everyday stance"** | The production system IS the development system — no separate staging |
