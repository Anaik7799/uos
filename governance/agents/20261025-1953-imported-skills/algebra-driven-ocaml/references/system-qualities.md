# System Qualities And Distributed Criteria

## Contents

1. Quality packet
2. Structure and planes
3. Functional-system criteria
4. Distributed-system criteria
5. Messaging, actors, and Zenoh
6. Observability, logging, debugging, and tracing
7. Evolution and operations
8. Fractal acceptance matrix

## 1. Quality Packet

For every system, context, service, module, and operation, complete this packet
at the smallest meaningful scale:

```text
carrier and state ownership
control plane and allowed commands
data plane and message/value flow
observations and telemetry
failure model and recovery
consistency and ordering model
capacity, latency, and resource bounds
upgrade/evolution protocol
durability and availability target
debugging and trace correlation
oracle, laws, generators, mutants, judge, governor
```

Do not label a quality "supported" without an observation, target/bound, and
verification path.

## 2. Structure And Planes

Separate these planes even when one process implements several:

| Plane | Owns | Must not do |
|---|---|---|
| Semantic | domain meaning and invariants | depend on timing, storage layout, or transport |
| Control | commands, policy, admission, lifecycle | fabricate data-plane success |
| Data | values, events, messages, streams | decide its own authority policy |
| Evidence | logs, metrics, traces, verdicts, revision identity | mutate semantic state covertly |
| Management | configuration, deployment, health, recovery | bypass normal authorization |
| Knowledge | ontology, docs, decisions, handoff | substitute stale prose for live facts |

State ownership must be singular or have an explicit merge algebra. Identify
aggregate boundaries, actor mailboxes, database writer ownership, caches,
replicas, and externally owned resources.

## 3. Functional-System Criteria

Check:

- totality over the declared input domain;
- deterministic observations where promised;
- referential transparency in the algebraic core;
- closure of combinators;
- invariant establishment by constructors and preservation by transitions;
- compositional errors and explicit partiality;
- idempotence of retries where commands may be repeated;
- cancellation and teardown semantics for effects;
- resource ownership and leak freedom;
- exact distinction between unavailable, rejected, unknown, and successful;
- backward/forward codec and schema compatibility;
- accessibility and responsive behavior for user interfaces.

Representative laws:

```text
valid(make(x)) or make(x)=Error
valid(s) and step(s,c)=Ok(s') implies valid(s')
observe(run(pure_program)) = denote(pure_program)
retry(idempotent_command,k) ~= once(idempotent_command)
cancel(start(x)) leaves no owned live resource
```

## 4. Distributed-System Criteria

Specify, do not imply:

| Criterion | Required decision and observation |
|---|---|
| Identity | node/service/actor/message identity and uniqueness scope |
| Discovery | static, registry, gossip, broker, or queryable discovery behavior |
| Addressing | logical key, actor id, endpoint, topic, or route translation |
| Delivery | at-most-once, at-least-once, effectively-once, or exactly-once under stated scope |
| Ordering | none, per-sender, per-key, causal, total, or transactional |
| Consistency | linearizable, serializable, causal, eventual, or application-specific merge |
| Partition behavior | reject, degrade, queue, reconcile, or continue with bounded divergence |
| Replication | source of truth, replica role, quorum, merge, lag observation |
| Backpressure | bounded queue/fuel, shedding, blocking, credits, or demand protocol |
| Retry | retryable errors, budget, jitter policy, idempotency key |
| Timeout | clock source, deadline propagation, cleanup, late-result handling |
| Failure detection | heartbeat/lease/process monitor and false-positive bound |
| Recovery | restart, replay, snapshot, reconciliation, poison-message handling |
| Membership | join/leave/failure transitions and split-brain policy |
| Security | identity, authentication, authorization, integrity, confidentiality, audit |
| Versioning | wire/schema negotiation and rolling-upgrade compatibility |

Useful laws:

```text
dedupe(deliver(m) @ deliver(m)) ~= deliver(m)       only when idempotency is promised
replay(log_before_crash) ~= state_before_crash
merge(a,b) ~= merge(b,a)                            only for commutative replicas
merge(a,a) ~= a                                     only for idempotent replicas
partition(chunks) then combine ~= process(all)      when chunking is licensed
accepted(message) implies eventually handled or durably classified
queue_length <= capacity
deadline expiration implies no later untracked state mutation
```

Exactly-once is never a bare transport claim. Define the transaction boundary,
deduplication identity, durable commit point, retry model, and observation.

## 5. Messaging, Actors, And Zenoh

### Actor packet

For each actor define:

- identity and supervisor;
- mailbox carrier, capacity, ordering, and ownership;
- message algebra and version;
- accepted/rejected/unknown message behavior;
- state transition function;
- reply/correlation protocol;
- restart strategy and state recovery;
- cancellation, timeout, and shutdown protocol;
- dead-letter or poison-message policy;
- trace context propagation.

Actor laws include per-sender ordering only when guaranteed, exactly-one state
transition per accepted command, mailbox capacity, restart/replay agreement,
and supervisor containment of failure.

### Zenoh packet

Treat Zenoh as an effectful transport interpretation, not domain meaning.
Specify key expressions, session ownership, publisher/subscriber/queryable
lifecycle, reliability/congestion settings, payload codec, discovery/router
dependency, authentication, liveliness, backpressure, timeout, and teardown.

Admission requires an in-memory transport oracle or reference path plus live
round-trip evidence. Compare payload values and ordering guarantees, not log
format. A live publish/ping surface does not imply every UI or service uses
Zenoh.

In zigvm, native `zenoh-c` is an external C dependency accessed through OCaml
Ctypes. MCP exposes live publish and ping operations, and the Zig mesh has its
own CRDT/message verification. The Bonsai/Dream data path remains HTTP plus the
OCaml `Db` actor; there is no Zenoh-to-Bonsai pipe.

## 6. Observability, Logging, Debugging, And Tracing

Observability is an algebra of questions, not a quantity of logs. Define the
minimal observation family needed to distinguish healthy, degraded, failed,
unknown, and stale states.

### Logs

Require structured fields for timestamp/source, severity, component, action,
outcome, correlation or trace id, revision/run id, and redacted detail. Laws:

- semantic operation results do not depend on log enablement;
- secrets and private payloads never enter logs;
- every accepted durable command has a correlated terminal classification;
- log loss is observable where audit durability is required.

### Metrics

Define unit, denominator, aggregation window, cardinality bound, freshness, and
missing-data semantics. A missing metric is unknown, never zero. Performance
metrics need warmup, sample count, dispersion, host identity, and oracle/baseline.

### Traces

Define span identity, parentage, propagation boundaries, sampling, and clock
assumptions. Test trace transparency: enabling tracing preserves domain
observations. For asynchronous work, correlation survives queue, retry,
restart, and remote transport.

### Debugging and introspection

Provide typed snapshots, state-machine status, queue depth, ownership,
configuration provenance, active version, health reasons, and bounded recent
events. Introspection must be read-only unless a separately authorized control
action exists. Representation-coupled internals are diagnostic and must not be
misreported as semantic equality.

## 7. Evolution And Operations

| Quality | Law/acceptance shape |
|---|---|
| Evolvability | old readers handle new optional fields; new readers handle old data; exhaustive variants force intentional change |
| Robustness | malformed, duplicated, delayed, reordered, and unavailable inputs have explicit outcomes |
| Durability | acknowledged state survives declared crash/restart model; restore is replay-equivalent |
| Availability | define SLI, window, exclusions, degraded modes, and dependency budget; never infer from one successful request |
| Scalability | completed work remains constant while concurrency/input size changes; report speedup and saturation |
| Performance | latency/throughput/resource targets use repeatable workloads and ratcheted baselines |
| Maintainability | ownership, dependency direction, law coverage, and change blast radius are explicit |
| Operability | health, readiness, config, capacity, backup, restore, incident, and rollback paths are exercised |
| Security | least privilege, fail-closed authorization, provenance, secret handling, and audit are verified |

Durability levels must name the failure domain: process, host, disk, site, or
region. Availability and disaster recovery are different. A local SQLite file
can be process-crash durable without being host- or site-durable.

## 8. Fractal Acceptance Matrix

For each L0-L10 layer and each affected component, mark:

```text
N/A with rationale | specified | implemented | observed | lawed | mutated |
formally verified | gate-enforced | residual
```

At minimum review these columns:

```text
functional correctness
control/data/evidence separation
security and safety
robustness and recovery
durability and availability
capacity, scalability, and performance
observability, logging, tracing, introspection
evolution and compatibility
messaging and actor lifecycle
distributed consistency and partition behavior
```

The matrix is a completeness tool, not a claim that every cell needs a new
mechanism. Mark honest non-applicability and residuals instead of manufacturing
features or evidence.
