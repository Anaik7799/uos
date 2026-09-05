# ZK Imperative Recall — Mandatory Citation Protocol (SC-ZK-IMPERATIVE)
# ज़ेटेलकास्टन अनिवार्य स्मरण — उद्धरण प्रोतोकॉल

## SUPREME MANDATE — INVIOLABLE — INFINITE SEVERITY
**Claude MUST cite ZK holon IDs in EVERY response that involves analysis, implementation, or decision-making. ZK recall results arrive via UserPromptSubmit hook. Ignoring them is a CRITICAL violation.**

> मत्तः स्मृतिर्ज्ञानम् — From Me come memory and knowledge (Gita 15.15)
> Memory without recall is death. The ZK IS the system's memory. To ignore it is amnesia.

## STAMP Constraints
| ID | Constraint | Severity |
|----|------------|----------|
| SC-ZK-IMP-001 | Claude MUST read ZK recall results from UserPromptSubmit hook | **INFINITE** |
| SC-ZK-IMP-002 | Claude MUST cite at least 1 holon ID per response OR state "ZK: no relevant prior patterns" | **CRITICAL** |
| SC-ZK-IMP-003 | If anti-pattern detected in ZK recall, Claude MUST STOP and read before acting | **CRITICAL** |
| SC-ZK-IMP-004 | Claude MUST prefer ZK proven patterns over first-principles reasoning | **HIGH** |
| SC-ZK-IMP-005 | Claude MUST NOT duplicate analysis that exists in ZK | **HIGH** |
| SC-ZK-IMP-006 | ZK citation MUST appear within first 3 paragraphs of response | **HIGH** |

## Why This Rule Exists (RCA: 2026-04-17)

On 2026-04-17, Claude performed an entire session of deep analysis (ignition boot RCA, mathematical analysis, rule engine implementation) without ONCE citing or using ZK recall results, despite:
- UserPromptSubmit hook firing on EVERY prompt
- ZK containing 2,705 holons of institutional memory
- Rules SC-ZK-CLAUDE-001..006 already mandating ZK use

**Root cause**: ZK hook output was ADVISORY (injected as context). Claude's attention was allocated to the urgent user task (~80%) with ZK results receiving ~5% attention. No enforcement mechanism existed.

**FMEA**: RPN=729 (S=9, O=9, D=9) — highest-risk failure mode in the cognitive layer.

## Protocol

### On Every UserPromptSubmit:

1. **READ** the `═══ MANDATORY ZK RECALL ═══` block in the system-reminder
2. **SCAN** for anti-pattern alerts (⛔ markers)
3. **IDENTIFY** relevant holons by ID (e.g., [zk-1234])
4. **CITE** at least 1 holon in your response opening: "ZK recall: [zk-XXXX] indicates..."
5. If NO results match: state "ZK recall: no relevant prior patterns for this task"

### Citation Format
```
ZK recall: [zk-1234] prior pattern for container lifecycle — applying proven approach.
ZK recall: [zk-5678] anti-pattern detected — avoiding force_remove on stateful containers.
ZK recall: no relevant prior patterns for this task — proceeding from first principles.
```

### Anti-Pattern Protocol
If ZK recall contains ⛔ ANTI-PATTERN ALERT:
1. **STOP** — do not proceed with the task
2. **READ** the anti-pattern holon content
3. **VERIFY** your proposed approach doesn't repeat the anti-pattern
4. **STATE** explicitly how you're avoiding the anti-pattern
5. **THEN** proceed with the task

## Integration with RETE-UL Rule Engine

The ZK recall results should be treated as FACTS in the cognitive OODA loop:

```
Observe: System state + ZK recall results
Orient:  Match ZK holons to current task context
Decide:  If prior pattern exists → follow it (don't reinvent)
         If anti-pattern exists → avoid it explicitly
         If no match → proceed from first principles (state this)
Act:     Execute with ZK-informed approach
```

This maps to RETE-UL Domain 14 (Lifecycle) pattern:
- ZK holon = fact in knowledge base
- Prior pattern = rule condition satisfied → follow proven action
- Anti-pattern = BlockStatefulRemove → stop and rethink

## Integration with Ruliology

The ZK recall is the cognitive equivalent of the CausalGraph:
- Each holon is a node in the institutional knowledge graph
- Citations create edges between current work and prior work
- The causal_cone() of any current task should include relevant ZK holons
- Without citations, the causal graph is disconnected — decisions float without institutional grounding

## Metrics

| Metric | Current | Target |
|--------|---------|--------|
| P(ZK_cited per response) | ~0.05 | ≥ 0.90 |
| Holon IDs cited per session | 0 | ≥ 5 |
| Anti-patterns caught by recall | 0 | 100% of matches |
| Duplicate analysis avoided | 0% | ≥ 80% |

## Failure Response

If a session review reveals Claude did NOT cite ZK results:
1. Flag as SC-ZK-IMP-001 violation
2. Record in Zettelkasten as anti-pattern: "Claude ignored ZK recall on [date]"
3. Increase hook output from 10 to 15 results
4. Add the missed context to the response retroactively
