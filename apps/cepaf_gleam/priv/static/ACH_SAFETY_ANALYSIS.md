# Assessment engine safety analysis

> **Restoration record:** reviewed v2.1 was restored after user confirmation and passed its bounded self-test. The prior overwritten engine remains archived. Verify the canonical source against SHA-256 `fc1aed0907ba587116d9ce5eead09d17395269f950377d397f5b933aaafffe7c` before relying on implementation claims. The independent safety-review hold remains unchanged.

Scope: advisory evidence path from operator packet through Codex/AGY/Claude to human reviewer. Loss L1: death or serious injury following an unsafe deployment justified by a misleading assessment. The operational plant/device is unknown; this is not its hazard analysis.

| Control action / unsafe context | Hazard | Constraint and mechanism | Residual |
|---|---|---|---|
| Provide an unsupported safety verdict | Incorrect deployment authorization | SC-ACH-1: report always emits deployment_authorized=false; no approval API; tested under unanimity | Human/downstream misuse requires independent integration controls |
| Fail to provide uncertainty, missing evidence or dissent | Hidden invalid assumptions | SC-ACH-2: required uncertainty/hazard fields, coverage validation, retained per-provider outputs | Text can be inaccurate or perfunctory; human review required |
| Provide outdated evidence or a late model response | Decision based on wrong system/version | SC-ACH-3: packet SHA-256, source freshness checks, CLI timeout, new run directories | Operator timestamps and verification strings are not authenticated |
| Continue assessment after conditions change, or stop before all assessors report | Partial/stale evidence mistaken for consensus | SC-ACH-4: all three provider outcomes recorded; any failure gives incomplete + nonzero; no retry/fallback | Collection snapshot does not monitor changes in operational system |
| Present repeated sources/models as independent confirmation | Common-cause false confidence | SC-ACH-5: no confidence averaging or voting; grade 1 requires distinct declared source groups | Semantic independence and underlying provider/model identity need verification |
| Store sensitive evidence on a shared mount or expose it through CLI arguments | Confidentiality loss and compromised evidence handling | SC-ACH-6: require private local output directory; keep supplied evidence sanitized | AGY prompt uses argv; an approved confidential execution boundary remains necessary for sensitive inputs |
| Leave hazard findings without review ownership or acceptance criteria | Unresolved hazard overlooked before decision | SC-ACH-7: export an open action per hazard retaining acceptance criteria and proposed owner; no fabricated completion or owner verification | External accountable assignment, execution and evidence-based closure are still required |
| Overweight several claims from the same underlying source | Fragile quantitative judgment | SC-ACH-8: remove all claims tied to a source together in sensitivity scenarios; reject ranking on empty evidence | Source-group declarations and substantive independence require independent inspection |
| Accept an injected authorization field within model output | Misleading nested approval consumed downstream | SC-ACH-9: reject unexpected fields at every assessment object boundary | Natural-language persuasion and downstream misuse remain human/integration review obligations |

All four STPA unsafe-control-action categories apply: not provided, provided unsafely, wrong timing/order, stopped too soon/applied too long. Each supplied hazard must receive a review of all four categories from every assessor.

Worst-case severity is catastrophic. Occurrence, detection probabilities and residual risk are **unknown**. No invented RPN, confidence average, or model quorum can lower the severity or accept risk. Priorities here identify work, not quantified safety assurance.

Required before operational use: identify the application and governing standard; nominate the safety authority; authenticate evidence and verification records; independently validate the tool and downstream handling; establish hazard-specific acceptance criteria, operational monitoring and rollback. The model report is a proposed review input, never an acceptance record.
