# 20260907-1837 — Detailed product specification and feature list

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Review](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260907-1837-zigvm-harness-product-feature-oracle-review.md) · [Raw source](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-1837-agentic-product-detailed-specification.md)

Status: requirements and source mapping; production NOT_ADMITTED. 46 features: 21 infrastructure services and 25 management capabilities. All 138 acceptance definitions remain UNRUN until their own evidence is collected. Catalog software test receipts are separate.

## Feature index

| ID | Feature | State | Reference oracle |
|---|---|---|---|
| AINF-S01 | Cryptographic workload IAM | MAPPED | go-spiffe, spiffe |
| AINF-S02 | RBAC / ABAC / PBAC | MAPPED | opa, cedar |
| AINF-S03 | Principal propagation and delegated authorization | MAPPED | arcade-ai, openbao |
| AINF-S04 | Ephemeral secret and credential broker | MAPPED | openbao |
| AINF-S05 | Input, output and tool guardrails | MAPPED | nemo-guardrails |
| AINF-S06 | Agent naming, registry and discovery | MAPPED | consul-reference |
| AINF-S07 | MCP and dynamic tool gateway | MAPPED | modelcontextprotocol |
| AINF-S08 | Asynchronous agent messaging and event bus | MAPPED | nats-server |
| AINF-S09 | Session state and scratchpads | MAPPED | dragonfly, valkey |
| AINF-S10 | Vector retrieval and long-term memory | MAPPED | qdrant |
| AINF-S11 | Knowledge graph and ontology | MAPPED | openCypher |
| AINF-S12 | Context routing, compaction and memory budget | MAPPED | letta |
| AINF-S13 | Isolated sandbox and bounded execution | MAPPED | E2B |
| AINF-S14 | Durable workflow and transaction orchestration | MAPPED | temporal |
| AINF-S15 | Human approval and escalation gateway | MAPPED | arcade-ai |
| AINF-S16 | Circuit breakers, anti-loop controls and dead letters | MAPPED | langgraph |
| AINF-S17 | Model gateway, routing, failover and cache | MAPPED | litellm |
| AINF-S18 | Step-level tracing and semantic telemetry | MAPPED | langfuse, trace-context, opentelemetry-specification |
| AINF-S19 | Cost, quota and budget enforcement | MAPPED | litellm |
| AINF-S20 | Immutable audit and compliance evidence | MAPPED | immudb |
| AINF-S21 | Continuous evaluation, regression and red teaming | MAPPED | promptfoo, deepeval |
| PM-01 | Product definition and outcomes | REVIEWED | zigvm-management, harness-management |
| PM-02 | Feature hierarchy and ownership | REVIEWED | zigvm-management, harness-management |
| PM-03 | Typed feature definition and use cases | REVIEWED | zigvm-management, harness-management |
| PM-04 | Requirements and contract ownership | REVIEWED | zigvm-management, harness-management |
| PM-05 | Specification and model projections | REVIEWED | zigvm-management, harness-management |
| PM-06 | Traceability across engineering artifacts | REVIEWED | zigvm-management, harness-management |
| PM-07 | Sa-plan execution linkage | REVIEWED | zigvm-management, harness-management |
| PM-08 | Truthful feature state | REVIEWED | zigvm-management, harness-management |
| PM-09 | Versioned change history | REVIEWED | zigvm-management, harness-management |
| PM-10 | SQLite artifact body storage | REVIEWED | zigvm-management, harness-management |
| PM-11 | Knowledge and document linkage | REVIEWED | zigvm-management, harness-management |
| PM-12 | Evidence retention at claim granularity | REVIEWED | zigvm-management, harness-management |
| PM-13 | Strict product completion | REVIEWED | zigvm-management, harness-management |
| PM-14 | Oracle inventory and provenance | REVIEWED | zigvm-management, harness-management |
| PM-15 | Oracle pin, license and executable identity | REVIEWED | zigvm-management, harness-management |
| PM-16 | Oracle recipe discovery and coverage | REVIEWED | zigvm-management, harness-management |
| PM-17 | Bounded oracle execution | REVIEWED | zigvm-management, harness-management |
| PM-18 | Normalization and fixture identity | REVIEWED | zigvm-management, harness-management |
| PM-19 | Differential verdict and divergence handling | REVIEWED | zigvm-management, harness-management |
| PM-20 | Regression, mutation and adversarial evidence | REVIEWED | zigvm-management, harness-management |
| PM-21 | Risk and dependency prioritization | REVIEWED | zigvm-management, harness-management |
| PM-22 | Desired-state reconciliation | REVIEWED | zigvm-management, harness-management |
| PM-23 | Operational analytics and cost evidence | REVIEWED | zigvm-management, harness-management |
| PM-24 | Release baseline and change control | REVIEWED | zigvm-management, harness-management |
| PM-25 | Feedback and outcome learning | REVIEWED | zigvm-management, harness-management |

## AINF-S01 — Cryptographic workload IAM

**Use case:** Provide Cryptographic workload IAM within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse WorkloadIdentityActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Per-agent short-lived identity, rotation and authenticated tenant binding remain unverified.

**AINF-R01:** Validate workload certificate/JWT signature, issuer, audience, tenant binding, not-before, expiry, revocation epoch and proof of possession at every ingress. Rotate short-lived identities; fail closed on unknown trust roots. A SPIFFE-shaped identifier alone SHALL NOT authenticate a caller.

- [apps/cepaf_gleam/src/cepaf_gleam/iam/supervisor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/iam/supervisor.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/iam/jwks_cache_actor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/iam/jwks_cache_actor.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T01-1 — Accept an enrolled workload using the admitted trust bundle.
- [ ] AINF-T01-2 — Reject forged, expired, wrong-audience and cross-tenant identities.
- [ ] AINF-T01-3 — Rotate roots with a bounded overlap; reject a revoked identity before its former expiry.

## AINF-S02 — RBAC / ABAC / PBAC

**Use case:** Provide RBAC / ABAC / PBAC within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse PolicyDecisionActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Typed policy runs on MCP dispatch; externalized policy and durable approvals are incomplete.

**AINF-R02:** Compute effective permission as the intersection of initiating principal, workload, delegation chain, tenant policy, resource ACL and environmental restrictions. Explicit deny dominates; missing attributes, stale policies, evaluator errors and timeouts deny. Rete recommendations cannot grant authority.

- [apps/cepaf_gleam/src/cepaf_gleam/auth/rbac.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/auth/rbac.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/rules/engine.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/rules/engine.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T02-1 — Permit a registered read tool for an authorized tenant principal.
- [ ] AINF-T02-2 — Deny when any grant is absent even if the workload has administrative privileges.
- [ ] AINF-T02-3 — Revoke a policy while a request is queued; reject its stale authorization at dispatch.

## AINF-S03 — Principal propagation and delegated authorization

**Use case:** Provide Principal propagation and delegated authorization within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse DelegationBrokerActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Generic delegated user scope and provider lifecycle need end-to-end verification.

**AINF-R03:** Carry the initiating principal and ordered actor chain through every handoff. Issue audience-specific, short-lived down-scoped credentials through the existing IAM boundary; enforce maximum depth, expiry and revocation. Exchange source and upstream tokens remain opaque to models and ordinary logs.

- [apps/cepaf_gleam/src/cepaf_gleam/auth/token_exchange.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/auth/token_exchange.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/iam/sts_token_cache_actor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/iam/sts_token_cache_actor.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T03-1 — Exchange to a narrower audience and scope for the same principal and tenant.
- [ ] AINF-T03-2 — Reject cyclic chains, depth overflow, scope escalation and confused-deputy token reuse.
- [ ] AINF-T03-3 — Revoke the root delegation and demonstrate invalidation of cached descendants.

## AINF-S04 — Ephemeral secret and credential broker

**Use case:** Provide Ephemeral secret and credential broker within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse CredentialLeaseActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Opaque credential leases and secure key custody at the actual tool boundary remain unverified.

**AINF-R04:** Issue opaque credential lease references bound to tenant, subject, tool, endpoint, request digest, epoch and expiry. Inject secret bytes only at the isolated adapter boundary, scrub inheritance and perform verified cleanup. No secret bytes, secret hashes, refresh tokens or private keys enter prompts, retained audit payloads or specification artifacts.

- [apps/cepaf_gleam/src/cepaf_gleam/vault.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/vault.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/vault_supervisor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/vault_supervisor.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [engines/hermes/modules/hermes_dependability/dependability_credential.mli](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_dependability/dependability_credential.mli) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T04-1 — Obtain a lease and use it only for the bound tool and endpoint.
- [ ] AINF-T04-2 — Reject lease replay after expiry, tenant mismatch, cancellation or revocation.
- [ ] AINF-T04-3 — Scan model inputs, telemetry and replay records to prove fixture secrets are absent.

## AINF-S05 — Input, output and tool guardrails

**Use case:** Provide Input, output and tool guardrails within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse GuardrailActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Output guardrails, injection evaluation and strict transport/schema boundaries need executed acceptance.

**AINF-R05:** Separate trusted policy from untrusted retrieved/tool content, enforce typed schemas and size limits, and redact classified fields before export. Combine deterministic controls with separately evaluated advisory classifiers. Prompt text, classifier approval or SQL substring filtering alone SHALL NOT authorize effects or replace parameterized SQL.

- [apps/cepaf_gleam/src/cepaf_gleam/vault_pii_scrub.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/vault_pii_scrub.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [engines/hermes/modules/system_engg/agent_dispatch_hook.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/system_engg/agent_dispatch_hook.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T05-1 — Retain an adversarial retrieved document as untrusted data while rejecting its requested privileged action.
- [ ] AINF-T05-2 — Reject NUL, malformed JSON and oversized arguments before adapter invocation.
- [ ] AINF-T05-3 — Redact seeded PII/credentials and quarantine a schema-invalid model result even after HTTP 200.

## AINF-S06 — Agent naming, registry and discovery

**Use case:** Provide Agent naming, registry and discovery within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse CapabilityRegistryActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Health/lease/capability registration exists in pieces; Consul behavioral oracle is not pinned locally.

**AINF-R06:** Register versioned capability descriptors with tenant visibility, schema and implementation digests, endpoint identity, supported protocols, lease expiry, health evidence and capacity. Discovery returns authorized, compatible and freshly leased candidates; discovery never grants execution authority.

- [apps/cepaf_gleam/src/cepaf_gleam/ontology/adk_c3i_master_ontology.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ontology/adk_c3i_master_ontology.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/uos_swarm/src/uos_swarm/swarm.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/swarm.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T06-1 — Discover two compatible authorized workers and select one with available capacity.
- [ ] AINF-T06-2 — Exclude expired, incompatible, unhealthy and other-tenant descriptors.
- [ ] AINF-T06-3 — Change a tool/schema digest after planning and require re-resolution and authorization.

## AINF-S07 — MCP and dynamic tool gateway

**Use case:** Provide MCP and dynamic tool gateway within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse ToolGatewayActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Protocol/policy components exist; tenant, schemas, framing and effect preflight need joint acceptance.

**AINF-R07:** Normalize admitted MCP, OpenAPI and internal MoZ calls into one typed invocation envelope. Negotiate pinned protocol versions; validate argument/result schemas, identity, deadline, payload bound, egress target and idempotency at the same boundary. HTTP auth, stdio framing and Zenoh ACLs remain distinct transport contracts; unknown protocol versions fail closed.

- [apps/cepaf_gleam/src/cepaf_gleam/mcp/protocol.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/mcp/protocol.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/bridge/zenoh_mcp.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/bridge/zenoh_mcp.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T07-1 — Invoke an admitted read tool through two transports and compare normalized outcomes and trace bindings.
- [ ] AINF-T07-2 — Reject unsupported versions, schema drift, unauthorized redirects and wrong token audiences.
- [ ] AINF-T07-3 — Cancel or time out a real worker and reap its process tree; never retry a non-idempotent ambiguous call.

## AINF-S08 — Asynchronous agent messaging and event bus

**Use case:** Provide Asynchronous agent messaging and event bus within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse TenantMailboxActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Zenoh is the native backplane; durable outbox/inbox, tenant ACL and delivery parity need evidence.

**AINF-R08:** Use Zenoh as the UOS backplane with explicit per-tenant namespace ACLs, persistent transactional outbox/inbox, deduplication keys, bounded mailbox depth, acknowledgements, retry policy and dead letters. Define ordering per workflow, not globally. Internal messages are not claims of external A2A protocol conformance.

- [apps/cepaf_gleam/src/cepaf_gleam/bridge/zenoh_mcp.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/bridge/zenoh_mcp.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/uos_swarm/src/uos_swarm/board.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/board.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T08-1 — Deliver a durable message after a broker disconnect and restart.
- [ ] AINF-T08-2 — Redeliver duplicates without duplicating an admitted effect; reject cross-tenant subscription.
- [ ] AINF-T08-3 — Saturate one mailbox and observe backpressure/dead letters without starving a second tenant.

## AINF-S09 — Session state and scratchpads

**Use case:** Provide Session state and scratchpads within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse SessionContextActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** ETS/cache components exist; tenant/principal partitions, quotas and crash recovery are unverified.

**AINF-R09:** Keep volatile working state in protected OTP/ETS partitions keyed by tenant, principal, session and authorization epoch, with item and byte quotas and TTLs. Durable checkpoints are referenced through Hermes. Cache contents cannot be authoritative for quota, approval, lease or completed-effect recovery.

- [apps/cepaf_gleam/src/cepaf_gleam/substrate/beam_cache.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/substrate/beam_cache.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/ha/context_cache.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/context_cache.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T09-1 — Read and update an owned session within byte and item bounds.
- [ ] AINF-T09-2 — Reject guessed identifiers, expired sessions and a cache entry after policy-epoch change.
- [ ] AINF-T09-3 — Restart a session actor and recover only authorized checkpoint data; never reset durable spend.

## AINF-S10 — Vector retrieval and long-term memory

**Use case:** Provide Vector retrieval and long-term memory within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse RetrievalActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Native similarity/index code exists; real versioned embeddings and authorization before scoring remain gaps.

**AINF-R10:** Extend the Hermes retrieval substrate with versioned embeddings produced only by admitted MAX inference. Authorize tenant, principal ACL, time bounds, retention and residency before scoring and again before release. Bind model, dimension, tokenizer, corpus and index revisions to every result; treat indexes as rebuildable projections.

- [engines/hermes/modules/hermes_wiki/src/graph/wiki_similarity.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_wiki/src/graph/wiki_similarity.ml) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T10-1 — Retrieve authorized evidence with source citations and model/index revision bindings.
- [ ] AINF-T10-2 — Exclude other-tenant and revoked documents before top-k selection and on final return.
- [ ] AINF-T10-3 — Rebuild an index and verify recall against a pinned labeled corpus; do not label TF-IDF as neural embeddings.

## AINF-S11 — Knowledge graph and ontology

**Use case:** Provide Knowledge graph and ontology within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse KnowledgeGraphActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Pure BEAM/Hermes graph reuse; provenance and ACL on derived paths need runtime checks.

**AINF-R11:** Use the existing KM triad and typed Hermes/BEAM graph operations. Enforce authorization on every vertex, edge and derived fact, track provenance and cap traversal depth/result size. Inference may propose relationships; only validated evidence can become authoritative facts or permission inputs.

- [engines/hermes/modules/hermes_wiki/src/graph/wiki_graph.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_wiki/src/graph/wiki_graph.ml) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/ontology/adk_c3i_master_ontology.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ontology/adk_c3i_master_ontology.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T11-1 — Resolve an authorized multi-hop relation with complete provenance.
- [ ] AINF-T11-2 — Reject a traversal through a hidden intermediary and prevent inferred permission escalation.
- [ ] AINF-T11-3 — Withdraw source evidence and invalidate dependent graph facts and caches.

## AINF-S12 — Context routing, compaction and memory budget

**Use case:** Provide Context routing, compaction and memory budget within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse ContextBudgetActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Compaction components exist; preserved policy, unresolved tool pairs and model tokenizer bounds need evidence.

**AINF-R12:** Assemble context using the selected model's admitted tokenizer and explicit input/output reservations. Preserve immutable policy, task constraints, delegation/approval references, unresolved tool pairs and evidence identifiers. Summaries remain versioned, untrusted derivatives with source references; fail if protected context cannot fit instead of dropping constraints.

- [apps/cepaf_gleam/src/cepaf_gleam/ha/context_manager.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/context_manager.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/ha/token_budget.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/token_budget.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/ha/workflow_compactor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/workflow_compactor.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T12-1 — Compact an over-budget session while preserving protected entries and tool-call/result pairing.
- [ ] AINF-T12-2 — Reject negative token counts, model/tokenizer mismatch and protected content exceeding capacity.
- [ ] AINF-T12-3 — Compare pre/post-compaction task answers on a pinned corpus and reject lost safety constraints.

## AINF-S13 — Isolated sandbox and bounded execution

**Use case:** Provide Isolated sandbox and bounded execution within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse SandboxLeaseActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Deterministic VFS is not a hostile-code sandbox; real isolation, egress and descendant reaping remain unverified.

**AINF-R13:** Route admitted deterministic programs to ZigVM and hostile host-tool execution to an independently isolated Hermes-Bionic process/container profile. Verify filesystem, privilege, network, CPU, memory, PID, output and wall-time limits before dispatch; cancel and reap descendants. Neither an OTP actor nor descriptor-relative VFS alone is a host-code security sandbox. Preserve the host OS storage interlock.

- [apps/cepaf_gleam/src/cepaf_gleam/harness/hermes_bionic_bridge.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/harness/hermes_bionic_bridge.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [engines/hermes/modules/hermes_dependability/dependability_process.mli](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_dependability/dependability_process.mli) — SOURCE_PRESENT; runtime UNRUN.
- [engines/zigvm/build.zig](http://nas-1.tail55d152.ts.net:4100/files/engines/zigvm/build.zig) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T13-1 — Run a bounded admitted task and retain a sanitized result with the sandbox profile digest.
- [ ] AINF-T13-2 — Attempt path escape, symlink race, credential mount access, forbidden egress and resource exhaustion; require containment.
- [ ] AINF-T13-3 — Deny execution when isolation attestation is absent and verify descendant cleanup after timeout.

## AINF-S14 — Durable workflow and transaction orchestration

**Use case:** Provide Durable workflow and transaction orchestration within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse WorkflowLeaseActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Sa-plan durability/control replay exists; model/tool outcome replay and ambiguous-effect reconciliation need integration.

**AINF-R14:** Use Sa-Plan leases and Hermes WAL transactions to persist workflow events, step intent, budget reservation and outbox atomically. Keep nondeterministic model/tool outcomes in versioned history and replay the pure transition function. Use idempotency keys for retryable effects and an explicit reconciliation state for ambiguous non-idempotent outcomes; compensation is an authorized action, not automatic reversal.

- [apps/cepaf_gleam/src/cepaf_gleam/planning/sa_plan_bridge.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/planning/sa_plan_bridge.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/sdlc/sa_plan_engine.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/sdlc/sa_plan_engine.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [engines/hermes/modules/sa_plan/sa_plan_store.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/sa_plan/sa_plan_store.ml) — SOURCE_PRESENT; runtime UNRUN.
- [engines/hermes/modules/sa_plan/sa_plan_temporal.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/sa_plan/sa_plan_temporal.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T14-1 — Kill the worker at every intent/effect/receipt boundary and recover committed workflow state.
- [ ] AINF-T14-2 — Replay completed model/tool steps from recorded outcomes without calling providers again.
- [ ] AINF-T14-3 — Fence a stale writer and reconcile an effect whose remote success was not durably acknowledged.

## AINF-S15 — Human approval and escalation gateway

**Use case:** Provide Human approval and escalation gateway within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse ApprovalQueueActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Signed approval primitives exist; durable per-action approval consumption and reauthorization need integration.

**AINF-R15:** Persist approvals bound to tenant, initiating principal, approver authority, exact canonical action digest, policy version, cost ceiling, expiry, lease epoch and a single-use nonce. Resume with current authorization and budget checks. Approval cannot override constitutional storage or scope denials; stale, altered or replayed approvals fail closed.

- [apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [engines/hermes/modules/sa_plan/guardian.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/sa_plan/guardian.ml) — SOURCE_PRESENT; runtime UNRUN.
- [engines/hermes/modules/hermes_dependability/dependability_approval_crypto.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_dependability/dependability_approval_crypto.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T15-1 — Pause a policy-designated high-impact action and resume exactly the approved request.
- [ ] AINF-T15-2 — Reject altered payloads, cross-tenant approvers, expired approval and nonce replay.
- [ ] AINF-T15-3 — Cancel a waiting workflow, then prove a delayed approval cannot dispatch it.

## AINF-S16 — Circuit breakers, anti-loop controls and dead letters

**Use case:** Provide Circuit breakers, anti-loop controls and dead letters within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse LoopGuardActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Prajna breakers exist; semantic repeated-state, no-progress and recursion limits need dispatch integration.

**AINF-R16:** Enforce maximum steps, delegation depth, repeated semantic tool signatures, no-progress window, absolute deadline and aggregate retry allowance. Apply tenant/provider circuit breakers with bounded half-open probes. On exhaustion, revoke pending dispatch permits and store a redacted, quota-bounded dead letter; stochastic hallucination detection remains an evaluated signal.

- [apps/cepaf_gleam/src/cepaf_gleam/prajna/circuit_breaker.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/prajna/circuit_breaker.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/ha/freshness_monitor.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/freshness_monitor.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T16-1 — Terminate a repeated tool loop within the configured count without another effect.
- [ ] AINF-T16-2 — Open a failing provider breaker, permit one half-open probe and avoid a retry storm.
- [ ] AINF-T16-3 — Show malformed or negative limits are rejected and one tenant's failures do not open another tenant's local breaker.

## AINF-S17 — Model gateway, routing, failover and cache

**Use case:** Provide Model gateway, routing, failover and cache within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse ModelRouterActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Provider/advisory routing exists; fallback spend reservations and actual MAX inference need evidence.

**AINF-R17:** Route through UOS Gleam policy to admitted MAX or already admitted provider adapters whose manifest satisfies tenant policy, model capabilities, residency, context and cost limits. Reserve worst-case spend per attempt including hedges before dispatch. Cache only eligible sanitized results with complete tenant/principal/policy/model/context bindings; default semantic cache off. Static acknowledgements cannot count as successful inference.

- [apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_provider.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_provider.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/inference_api.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/inference_api.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [services/inference/max/max_worker.py](http://nas-1.tail55d152.ts.net:4100/files/services/inference/max/max_worker.py) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T17-1 — Invoke a real pinned inference backend and verify tokenizer usage and structured result against evidence.
- [ ] AINF-T17-2 — Fail over only to an authorized compatible provider with a fresh reservation; reject forbidden residency.
- [ ] AINF-T17-3 — Demonstrate no cache reuse across tenants, ACL epochs, tool schemas, corpus versions or model changes.

## AINF-S18 — Step-level tracing and semantic telemetry

**Use case:** Provide Step-level tracing and semantic telemetry within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse TrajectoryTelemetryActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Trace emitters exist; propagation/schema parity, persisted trajectory and usage correlation need evidence.

**AINF-R18:** Emit correlated W3C spans and C3I coordinates for authorized decisions, routing, retrieval, compaction, approvals, attempts, results, usage and eval verdicts. Record observable actions and concise redacted rationale/evidence references; exclude hidden chain-of-thought, secrets and unrestricted raw context. Distinguish transport success, task success and admission. Telemetry loss cannot rewrite authoritative evidence.

- [apps/cepaf_gleam/src/cepaf_gleam/ha/trace_context.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/trace_context.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/agui/sse.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/agui/sse.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [contracts/evidence/c3i_fractal_observability_spec.json](http://nas-1.tail55d152.ts.net:4100/files/contracts/evidence/c3i_fractal_observability_spec.json) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T18-1 — Reconstruct a multi-step trajectory across transports using valid nonzero trace/span IDs.
- [ ] AINF-T18-2 — Return HTTP 200 with a semantically wrong answer and record task failure independently.
- [ ] AINF-T18-3 — Drop telemetry under load while preserving the durable audit chain and admitting no unaudited effect.

## AINF-S19 — Cost, quota and budget enforcement

**Use case:** Provide Cost, quota and budget enforcement within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse TenantQuotaActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Per-request caps exist; atomic simultaneous global/tenant/user/workflow budgets remain incomplete.

**AINF-R19:** Maintain integer micro-unit monetary and token/resource budgets with durable compare-and-swap reservation, settlement and refund records. Scope global, tenant, principal and workflow limits and enforce all simultaneously. Concurrent attempts reserve before dispatch; cancellation retains uncertain liability until reconciliation. Unknown pricing or usage fails closed for additional spend.

- [apps/cepaf_gleam/src/cepaf_gleam/ha/token_budget.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/token_budget.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [apps/uos_swarm/src/uos_swarm/coord.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_swarm/coord.gleam) — SOURCE_PRESENT; runtime UNRUN.
- [engines/hermes/modules/sa_plan/sa_plan_store.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/sa_plan/sa_plan_store.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T19-1 — Race concurrent requests at an exact tenant/global budget boundary and prevent oversubscription.
- [ ] AINF-T19-2 — Charge hedges/retries and settle duplicate usage receipts once.
- [ ] AINF-T19-3 — Restart/fail over the quota owner without resetting balances or releasing an ambiguous in-flight reservation.

## AINF-S20 — Immutable audit and compliance evidence

**Use case:** Provide Immutable audit and compliance evidence within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse EvidenceAppendActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** SQLite evidence and signed receipts exist; anchored tamper-evident history and restore proofs need integration.

**AINF-R20:** Use the existing authoritative Hermes SQLite WAL evidence plane with a fenced single writer, append-only API and cryptographic chaining of canonical redacted records. Anchor chain heads outside the writer's trust domain; verify backup restoration and retention. Describe guarantees as tamper evidence with a stated threat model, not absolute tamper proofing. Persistence failure blocks new effects.

- [engines/hermes/modules/hermes_harness/evidence_store.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/evidence_store.ml) — SOURCE_PRESENT; runtime UNRUN.
- [engines/hermes/modules/hermes_dependability/dependability_writer_lease.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_dependability/dependability_writer_lease.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T20-1 — Detect modification, omission, reordering and a truncated tail against an independently stored checkpoint.
- [ ] AINF-T20-2 — Refuse a dispatch when the ledger is unwritable, full or its writer lease is stale.
- [ ] AINF-T20-3 — Restore an encrypted backup, verify chain/sequence/tenant isolation and execute a documented retention procedure.

## AINF-S21 — Continuous evaluation, regression and red teaming

**Use case:** Provide Continuous evaluation, regression and red teaming within the initiating user's authorized UOS workflow.

**Native implementation:** Reuse EvaluationGateActor role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.

**Remaining gap:** Native contract/differential suites exist; versioned trajectory and prompt regression rollout gates remain unverified.

**AINF-R21:** Extend Hermes differential evaluation with pinned datasets, prompts, model/tokenizer versions, policy snapshots and deterministic control oracles. Score task success, groundedness, tool/approval correctness, injection resistance, isolation, context preservation, latency and spend. Separate deterministic contract checks from stochastic model measurements; require regression thresholds and confidence intervals before a controlled rollout.

- [engines/hermes/modules/hermes_harness/test_parity_algebra.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/test_parity_algebra.ml) — SOURCE_PRESENT; runtime UNRUN.
- [engines/hermes/modules/hermes_harness/test_parity_compare.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/test_parity_compare.ml) — SOURCE_PRESENT; runtime UNRUN.
- [apps/cepaf_gleam/src/cepaf_gleam/testing/coverage_math.gleam](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/testing/coverage_math.gleam) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] AINF-T21-1 — Run held-out normal and adversarial trajectories and reject a deliberately wrong but syntactically valid response.
- [ ] AINF-T21-2 — Introduce policy, cache-isolation, compaction and quota mutants and observe failing gates.
- [ ] AINF-T21-3 — Mark missing judge/backend, empty datasets, stale receipts and unavailable formal tools UNRUN or UNKNOWN, never PASS.

## PM-01 — Product definition and outcomes

**Use case:** Define who a product serves, the problem, measurable outcome hypotheses and scope before classifying engineering work.

**Native implementation:** Product specification metadata plus existing typed catalogs; outcomes remain unmeasured.

**Remaining gap:** Business outcome and customer-feedback lifecycle is not fully represented by the engineering catalogs.

**PM-01-R1:** Product specifications SHALL preserve a stable identity, purpose, stakeholder/source, outcome hypothesis, metric definition, scope and explicit unknowns.

- [engines/hermes/modules/hermes_harness/feature_catalog.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/feature_catalog.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-01-T1 — Product specifications SHALL preserve a stable identity, purpose, stakeholder/source, outcome hypothesis, metric definition, scope and explicit unknowns.
- [ ] PM-01-T2 — Reject a product with missing purpose or fabricated measured outcome.
- [ ] PM-01-T3 — Repeat the Product definition and outcomes operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-02 — Feature hierarchy and ownership

**Use case:** Navigate product, family, capability, contract, scenario, trace and receipt without losing the denominator.

**Native implementation:** Adapt the current Hermes fractal catalog and SQLite foreign-key graph.

**Remaining gap:** The inspected external product hierarchy tables are empty; candidate-bound graph completion needs a collector.

**PM-02-R1:** Every required feature SHALL have one containment parent and stable semantic identity; cross-relations SHALL NOT create extra parents or cycles.

- [engines/hermes/modules/hermes_harness/fractal_catalog.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/fractal_catalog.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-02-T1 — Every required feature SHALL have one containment parent and stable semantic identity; cross-relations SHALL NOT create extra parents or cycles.
- [ ] PM-02-T2 — Reject duplicate IDs, missing parents, skipped required levels and empty completion trees.
- [ ] PM-02-T3 — Repeat the Feature hierarchy and ownership operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-03 — Typed feature definition and use cases

**Use case:** Inspect each capability's behavior, use case, UI controls and scenario references.

**Native implementation:** Use the existing InfraNodus typed registry shape and versioned product rows.

**Remaining gap:** InfraNodus metadata tests do not execute every referenced scenario.

**PM-03-R1:** A feature SHALL preserve ID, category, behavior, use case, control references, scenario references, declared state and observed evidence separately.

- [engines/hermes/modules/hermes_wiki/import/zigvm/code/infranodus/infranodus_feature.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_wiki/import/zigvm/code/infranodus/infranodus_feature.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-03-T1 — A feature SHALL preserve ID, category, behavior, use case, control references, scenario references, declared state and observed evidence separately.
- [ ] PM-03-T2 — Reject implementation claims backed only by a label or empty evidence list.
- [ ] PM-03-T3 — Repeat the Typed feature definition and use cases operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-04 — Requirements and contract ownership

**Use case:** Trace each requested behavior to a falsifiable law and responsible component.

**Native implementation:** Existing Hermes contracts, Gospel methods and the new requirements projection.

**Remaining gap:** Formal ownership/registration must be distinguished from checked proof.

**PM-04-R1:** Each requirement SHALL have a stable ID, shall statement, owner, contract/formal method, runtime acceptance and source reference.

- [engines/hermes/modules/hermes_harness/contract_catalog.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/contract_catalog.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-04-T1 — Each requirement SHALL have a stable ID, shall statement, owner, contract/formal method, runtime acceptance and source reference.
- [ ] PM-04-T2 — Reject a verified requirement with missing or stale contract/runtime receipt.
- [ ] PM-04-T3 — Repeat the Requirements and contract ownership operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-05 — Specification and model projections

**Use case:** Produce consistent SysML, ontology and product views from one versioned specification.

**Native implementation:** Reuse Feature_model projections; new catalog exposes canonical source records.

**Remaining gap:** Projection generation alone does not validate an official SysML/OML toolchain.

**PM-05-R1:** All derived model surfaces SHALL retain the same IDs, requirements and dependency edges and identify their source version.

- [engines/hermes/modules/hermes_wiki/src/mbse/feature_model.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_wiki/src/mbse/feature_model.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-05-T1 — All derived model surfaces SHALL retain the same IDs, requirements and dependency edges and identify their source version.
- [ ] PM-05-T2 — Detect a missing feature or changed dependency in a generated model; preserve toolchain validation as UNRUN.
- [ ] PM-05-T3 — Repeat the Specification and model projections operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-06 — Traceability across engineering artifacts

**Use case:** Find the code, test, document, UI and design behind a requirement.

**Native implementation:** Hermes artifact/node/knowledge-link concepts with additive SQLite artifact links.

**Remaining gap:** Graph completeness and semantic validity require more than foreign keys.

**PM-06-R1:** Typed artifact links SHALL preserve role, origin, digest and revision and resolve to an artifact version.

- [engines/hermes/modules/hermes_harness/reference_artifacts.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/reference_artifacts.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-06-T1 — Typed artifact links SHALL preserve role, origin, digest and revision and resolve to an artifact version.
- [ ] PM-06-T2 — Reject dangling artifact links and mismatched digest or semantic owner.
- [ ] PM-06-T3 — Repeat the Traceability across engineering artifacts operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-07 — Sa-plan execution linkage

**Use case:** Execute product work with durable task dependencies and recoverable ownership.

**Native implementation:** Existing Sa-plan CLI and preflight; catalog verifies current task ownership.

**Remaining gap:** Two-database observation is not atomic effect-time fencing.

**PM-07-R1:** Plans, tasks, jobs and workflows SHALL remain in canonical Sa-plan; catalog rows SHALL carry references only.

- [engines/hermes/modules/sa_plan/sa_plan_store.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/sa_plan/sa_plan_store.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-07-T1 — Plans, tasks, jobs and workflows SHALL remain in canonical Sa-plan; catalog rows SHALL carry references only.
- [ ] PM-07-T2 — Reject expired worker/attempt and never execute from an advisory product priority.
- [ ] PM-07-T3 — Repeat the Sa-plan execution linkage operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-08 — Truthful feature state

**Use case:** Compare declaration, available source, observed runtime and admitted behavior.

**Native implementation:** Reuse stale-declaration diagnostics; preserve a separate conservative catalog status.

**Remaining gap:** Legacy register can return Built when no probe exists.

**PM-08-R1:** Declared, mapped, implemented, tested, verified and admitted observations SHALL remain distinguishable; missing evidence SHALL NOT imply completion.

- [engines/hermes/modules/hermes_wiki/src/register/feature_register.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_wiki/src/register/feature_register.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-08-T1 — Declared, mapped, implemented, tested, verified and admitted observations SHALL remain distinguishable; missing evidence SHALL NOT imply completion.
- [ ] PM-08-T2 — A declaration of Built without executed matching evidence must not increase strict coverage.
- [ ] PM-08-T3 — Repeat the Truthful feature state operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-09 — Versioned change history

**Use case:** Review changes without destroying prior evidence.

**Native implementation:** Existing immutable-key pattern adapted into product import records and SQL protection triggers.

**Remaining gap:** Administrative replacement of a SQLite file remains outside ordinary API protection.

**PM-09-R1:** An identical object/version replay SHALL be idempotent and a changed payload at that identity SHALL be rejected; new versions retain prior history.

- [engines/hermes/modules/hermes_harness/evidence_store.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/evidence_store.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-09-T1 — An identical object/version replay SHALL be idempotent and a changed payload at that identity SHALL be rejected; new versions retain prior history.
- [ ] PM-09-T2 — Change a stored requirement under the same version and confirm rejection and unchanged history.
- [ ] PM-09-T3 — Repeat the Versioned change history operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-10 — SQLite artifact body storage

**Use case:** Recover the original architecture and authored reviews without depending on a filesystem copy.

**Native implementation:** New native OCaml product_catalog import/artifact commands in existing tracking database.

**Remaining gap:** External sources must not be copied before quiescence, sanitization and two-key admission.

**PM-10-R1:** Generated/user artifact bodies SHALL be stored with media kind, SHA-256, source locator and immutable revision; source-code oracles remain reference-only.

- [engines/hermes/modules/hermes_harness/evidence_store.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/evidence_store.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-10-T1 — Generated/user artifact bodies SHALL be stored with media kind, SHA-256, source locator and immutable revision; source-code oracles remain reference-only.
- [ ] PM-10-T2 — Tamper with an artifact body or supply a mismatched hash and reject import; byte-identical readback succeeds.
- [ ] PM-10-T3 — Repeat the SQLite artifact body storage operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-11 — Knowledge and document linkage

**Use case:** Navigate between source architecture, wiki, decision records and detailed features.

**Native implementation:** Current Hermes Wiki datastore/graph and Tailscale document serving.

**Remaining gap:** All rendered graph links require separate navigation validation.

**PM-11-R1:** Knowledge pointers SHALL preserve locator, source revision, digest and relationship; rendered views SHALL remain projections.

- [engines/hermes/modules/hermes_wiki/src/engine/wiki_datastore.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_wiki/src/engine/wiki_datastore.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-11-T1 — Knowledge pointers SHALL preserve locator, source revision, digest and relationship; rendered views SHALL remain projections.
- [ ] PM-11-T2 — Detect an unresolved or stale knowledge reference without manufacturing runtime failure.
- [ ] PM-11-T3 — Repeat the Knowledge and document linkage operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-12 — Evidence retention at claim granularity

**Use case:** Ask which specific scenario passed at a particular candidate.

**Native implementation:** Hermes trace/receipt tables and ZigVM evidence-census retention semantics.

**Remaining gap:** The new manifest defines acceptance cases; it does not synthesize their execution receipts.

**PM-12-R1:** Per-case assertions SHALL retain per-case evidence; aggregate logs SHALL remain labeled aggregate; absence SHALL remain unknown.

- [engines/hermes/modules/hermes_harness/parity_ledger.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/parity_ledger.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-12-T1 — Per-case assertions SHALL retain per-case evidence; aggregate logs SHALL remain labeled aggregate; absence SHALL remain unknown.
- [ ] PM-12-T2 — Reject converting a suite count into fabricated per-case pass rows.
- [ ] PM-12-T3 — Repeat the Evidence retention at claim granularity operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-13 — Strict product completion

**Use case:** Prevent partial or stale child evidence from admitting an entire product.

**Native implementation:** Reuse the required-child fold behind a stronger evidence-binding collector.

**Remaining gap:** Existing low-level Boolean readers are insufficient alone.

**PM-13-R1:** Completion SHALL require every required child and matching candidate, reference, scenario, normalizer, runtime and formal receipt; empty sets SHALL NOT pass.

- [engines/hermes/modules/hermes_harness/evidence_rollup.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/evidence_rollup.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-13-T1 — Completion SHALL require every required child and matching candidate, reference, scenario, normalizer, runtime and formal receipt; empty sets SHALL NOT pass.
- [ ] PM-13-T2 — A single missing child, stale candidate or mismatched trace pair must block strict completion.
- [ ] PM-13-T3 — Repeat the Strict product completion operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-14 — Oracle inventory and provenance

**Use case:** Locate each behavioral reference and know what authority it can provide.

**Native implementation:** Existing source registry and generated pin-observation artifact.

**Remaining gap:** Generic recursive inventory is not a sanitized UOS ingestion policy.

**PM-14-R1:** Oracles SHALL distinguish specification, source, executable, recorded fixture and advisory model roles and preserve origin, owner and revision.

- [engines/hermes/modules/hermes_harness/inventory.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/inventory.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-14-T1 — Oracles SHALL distinguish specification, source, executable, recorded fixture and advisory model roles and preserve origin, owner and revision.
- [ ] PM-14-T2 — A cloned repository alone must not be classified as an executed differential oracle.
- [ ] PM-14-T3 — Repeat the Oracle inventory and provenance operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-15 — Oracle pin, license and executable identity

**Use case:** Reproduce a comparison against the intended reference build.

**Native implementation:** Use UOS source authorities; adopt ZigVM source/runtime checks as separate observations.

**Remaining gap:** OTP-major equality plus Git HEAD is not exact executable provenance.

**PM-15-R1:** An oracle execution SHALL bind full source revision, dirty-state receipt, license, build/toolchain, executable identity and observation time.

- [engines/hermes/modules/hermes_harness/reference_capture.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/reference_capture.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-15-T1 — An oracle execution SHALL bind full source revision, dirty-state receipt, license, build/toolchain, executable identity and observation time.
- [ ] PM-15-T2 — Wrong major, modified source, mismatched license or unknown executable identity must withhold exact-pin credit.
- [ ] PM-15-T3 — Repeat the Oracle pin, license and executable identity operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-16 — Oracle recipe discovery and coverage

**Use case:** Account for every fixture including ones not yet runnable.

**Native implementation:** ZigVM vector discovery-totality and Hermes capability/scenario catalog patterns.

**Remaining gap:** Current service oracle registrations need executable differential adapters.

**PM-16-R1:** Each discovered vector SHALL have a typed bounded execution recipe or explicit nonpassing reason; no fixture may disappear from the denominator.

- [engines/hermes/modules/hermes_harness/capability_catalog.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/capability_catalog.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-16-T1 — Each discovered vector SHALL have a typed bounded execution recipe or explicit nonpassing reason; no fixture may disappear from the denominator.
- [ ] PM-16-T2 — Introduce an undiscovered recipe or compare two empty outputs; registry must report missing coverage or vacuity.
- [ ] PM-16-T3 — Repeat the Oracle recipe discovery and coverage operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-17 — Bounded oracle execution

**Use case:** Run behavioral probes without letting the reference control the host.

**Native implementation:** Existing supervised bounded process boundary; use OTP for lifecycle control.

**Remaining gap:** Legacy Reference_capture only kills the direct child and does not establish these limits.

**PM-17-R1:** Execution SHALL enforce deadline, memory/output/process limits, sanitized environment and egress policy and reap the full process tree.

- [engines/hermes/modules/hermes_dependability/dependability_process.mli](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_dependability/dependability_process.mli) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-17-T1 — Execution SHALL enforce deadline, memory/output/process limits, sanitized environment and egress policy and reap the full process tree.
- [ ] PM-17-T2 — Hanging, forking, noisy and network-denied fixtures must terminate within the declared budget and remain nonpassing.
- [ ] PM-17-T3 — Repeat the Bounded oracle execution operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-18 — Normalization and fixture identity

**Use case:** Compare outputs fairly without erasing meaningful differences.

**Native implementation:** Existing Hermes versioned JSON normalizer with stronger surrounding identity checks.

**Remaining gap:** Reference_capture.load presently does not compare all requested identity fields.

**PM-18-R1:** Normalizer identity and rules SHALL be versioned with the fixture; load SHALL verify full scenario, snapshot and content identity.

- [engines/hermes/modules/hermes_harness/parity_normalizer.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/parity_normalizer.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-18-T1 — Normalizer identity and rules SHALL be versioned with the fixture; load SHALL verify full scenario, snapshot and content identity.
- [ ] PM-18-T2 — A forged scenario ID or altered normalizer must be rejected even when the trace's self-digest matches.
- [ ] PM-18-T3 — Repeat the Normalization and fixture identity operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-19 — Differential verdict and divergence handling

**Use case:** Explain exactly where native behavior differs from a reference.

**Native implementation:** Current Hermes comparators, initial/final oracles and parity algebra.

**Remaining gap:** Service-level differential runs remain UNRUN in this review.

**PM-19-R1:** Comparison SHALL retain both normalized observations, comparator version and locality; unavailable or vacuous results SHALL never become equivalent.

- [engines/hermes/modules/hermes_harness/parity_compare.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/parity_compare.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-19-T1 — Comparison SHALL retain both normalized observations, comparator version and locality; unavailable or vacuous results SHALL never become equivalent.
- [ ] PM-19-T2 — Known mismatches and empty outputs must be detected; a failed reference is blocked evidence rather than candidate success.
- [ ] PM-19-T3 — Repeat the Differential verdict and divergence handling operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-20 — Regression, mutation and adversarial evidence

**Use case:** Prove a checker can detect the defects it claims to prevent.

**Native implementation:** Existing Hermes negative-case and mutation mechanisms; focused catalog transaction tests.

**Remaining gap:** Full imported suites and production chaos were not executed.

**PM-20-R1:** Regression and mutation records SHALL retain candidate, inputs, expected law, observed result and killed/surviving/unrun status.

- [engines/hermes/modules/hermes_harness/test_parity_compare.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/test_parity_compare.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-20-T1 — Regression and mutation records SHALL retain candidate, inputs, expected law, observed result and killed/surviving/unrun status.
- [ ] PM-20-T2 — A deliberately corrupted candidate must fail the relevant acceptance; a survivor must remain a finding.
- [ ] PM-20-T3 — Repeat the Regression, mutation and adversarial evidence operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-21 — Risk and dependency prioritization

**Use case:** Choose safe, ready work based on explicit impact and hazards.

**Native implementation:** Canonical UOS risk checker and Sa-plan selection evidence.

**Remaining gap:** Legacy wiki numeric priorities and onto_task repair records remain advisory.

**PM-21-R1:** Selection SHALL apply safety class and readiness before C×T×F×Dep×I and record all four UCAs, raw FMEA and current evidence.

- [engines/hermes/modules/sa_plan/sa_plan_management.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/sa_plan/sa_plan_management.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-21-T1 — Selection SHALL apply safety class and readiness before C×T×F×Dep×I and record all four UCAs, raw FMEA and current evidence.
- [ ] PM-21-T2 — An unready high-score task must not displace its prerequisite or grant execution authority.
- [ ] PM-21-T3 — Repeat the Risk and dependency prioritization operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-22 — Desired-state reconciliation

**Use case:** Compare a desired product state with observed evidence and expose drift.

**Native implementation:** Existing Blueprint validation, drift diagnostics and convergence logic.

**Remaining gap:** Never route a converged advisory model directly to deployment.

**PM-22-R1:** Reconciliation SHALL preserve explicit desired/actual states, unknown targets, dependency cycles and non-vacuous convergence.

- [engines/hermes/modules/hermes_harness/blueprint.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/blueprint.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-22-T1 — Reconciliation SHALL preserve explicit desired/actual states, unknown targets, dependency cycles and non-vacuous convergence.
- [ ] PM-22-T2 — Reject unresolved dependencies and empty success; changed evidence must invalidate the affected observation.
- [ ] PM-22-T3 — Repeat the Desired-state reconciliation operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-23 — Operational analytics and cost evidence

**Use case:** Measure reliability and regressions without inflated sample counts.

**Native implementation:** Hermes receipt reliability, surprisal ledger and UOS quota accounting boundaries.

**Remaining gap:** Analytics are advisory and do not establish budget enforcement.

**PM-23-R1:** Reliability, cost and coverage summaries SHALL state population, retention, candidate and uncertainty; repeated samples SHALL NOT fabricate independent evidence.

- [engines/hermes/modules/hermes_harness/receipt_reliability.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/receipt_reliability.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-23-T1 — Reliability, cost and coverage summaries SHALL state population, retention, candidate and uncertainty; repeated samples SHALL NOT fabricate independent evidence.
- [ ] PM-23-T2 — No sample or unknown provider cost must yield UNKNOWN or refusal rather than a favorable default.
- [ ] PM-23-T3 — Repeat the Operational analytics and cost evidence operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-24 — Release baseline and change control

**Use case:** Admit an exact product version and retain recovery evidence.

**Native implementation:** Existing run assurance, Sa-plan leases and UOS two-key admission rules.

**Remaining gap:** An integrated product release-baseline collector remains a gap.

**PM-24-R1:** A release baseline SHALL bind requirements, dependency snapshot, JJ candidate, approvals, runtime/formal receipts and rollback; no status label alone admits release.

- [engines/hermes/modules/hermes_ops_dashboard/run_assurance.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_ops_dashboard/run_assurance.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-24-T1 — A release baseline SHALL bind requirements, dependency snapshot, JJ candidate, approvals, runtime/formal receipts and rollback; no status label alone admits release.
- [ ] PM-24-T2 — A changed candidate, revoked approval or stale evidence must withhold release authorization.
- [ ] PM-24-T3 — Repeat the Release baseline and change control operation at a new candidate and prove stale evidence does not carry verification credit.

## PM-25 — Feedback and outcome learning

**Use case:** Connect observed user feedback to requirements and measured product benefit.

**Native implementation:** Current journals/knowledge history plus explicit product metadata fields.

**Remaining gap:** A complete customer research and business-outcome workflow was not found in the inspected management models.

**PM-25-R1:** Feedback SHALL retain its source, consent/scope, linked feature, hypothesis and measured outcome separately from proposed changes.

- [engines/hermes/modules/hermes_harness/orientation_history.ml](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_harness/orientation_history.ml) — SOURCE_PRESENT; runtime UNRUN.

**Acceptance:**

- [ ] PM-25-T1 — Feedback SHALL retain its source, consent/scope, linked feature, hypothesis and measured outcome separately from proposed changes.
- [ ] PM-25-T2 — Unmeasured outcomes must stay unknown and feedback must not silently rewrite a historical requirement.
- [ ] PM-25-T3 — Repeat the Feedback and outcome learning operation at a new candidate and prove stale evidence does not carry verification credit.

## Comprehensive verification checklist

<details><summary>Domain 1 — Metadata, timestamp and navigation</summary>

- [x] CHK-01-TIME — Host clock and chrony receipt observed; timestamps distinguish intake and later observations.
- [x] CHK-02-TAIL — Full Tailscale FQDN links included; live delivery measured separately.
- [x] CHK-03-FRACT — L0–L9 tags included; product hierarchy and system layers kept distinct.
- [x] CHK-04-KM — Source, review, detailed specification and journal are linked.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [x] CHK-05-MUDA — No third-party runtime dependency or external executable source imported by this package.
- [ ] CHK-06-GRAPH — Fleet graph/NIF conformance UNRUN; catalog uses OCaml and SQLite.
- [ ] CHK-07-DRIVE — Storage interlock execution UNRUN; no drive operations in scope.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full web UI categories UNRUN; this change supplies a CLI and read-only document views.
- [ ] CHK-09-MATH — Fleet mathematical quality gates UNRUN; no invented scores.
- [ ] CHK-10-9MOD — Targeted catalog tests executed; full nine modalities UNRUN.
- [ ] CHK-11-REGR — Production UI regression and sustained monitoring UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Production supervision behavior not changed or verified by catalog import.
- [x] CHK-13-HERMES — Native OCaml/SQLite catalog transaction and readback checked at package scope.
- [ ] CHK-14-ZIGVM — External VM runtime/parity execution UNRUN.
- [ ] CHK-15-MAX — Inference execution UNRUN.
- [ ] CHK-16-OTEL — Fleet trace contract execution UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent sovereign review and production admission NOT_ADMITTED.
- [x] CHK-18-JJ — UOS uses standalone JJ; external Git reads are provenance only.

</details>

**Previous:** [Management review](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260907-1837-zigvm-harness-product-feature-oracle-review.md) · **Next:** [Completion journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1837-agentic-product-management-review-journal.md)

**UOS footer:** versioned product and artifact catalog; Sa-plan owns execution; acceptance definitions remain UNRUN.
