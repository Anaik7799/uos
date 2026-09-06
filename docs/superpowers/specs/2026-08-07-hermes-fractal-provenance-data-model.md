# Hermes Fractal Provenance Data Model

## Purpose

Make every Hermes behavior independently discoverable, implementable,
verifiable, and historically auditable. The model must answer, at any scale:
what is this behavior, where is it defined upstream, where is it implemented
in OCaml or Rust, which Git revisions changed it, and what evidence proves or
refutes exact parity.

## Authority and scope

The upstream authority is the frozen Hermes snapshot
`70b2efe95be51e0658eb919b14168cff6b0a0a4f344652fcaecfc75543fa2cf6`
with 8,556 inventory entries. The initial public denominator is the 18
durable L1 feature families already in `feature_catalog`. This design extends
the existing SQLite evidence store without treating documentation or source
presence as proof of OCaml parity.

## Recursive carrier

`fractal_node` is the single carrier for product and proof structure.

```text
L0 product → L1 family → L2 capability → L3 contract
           → L4 scenario → L5 trace → L6 receipt
```

Every node has the same identity, source snapshot, parent, semantic key,
label, required flag, lifecycle, anchors, Git revisions, and status policy.
The hierarchy is a rooted acyclic tree; cross-cutting relationships are typed
edges rather than extra parents.

```sql
fractal_node(
  snapshot_digest, node_id, level, parent_node_id, semantic_key, label,
  required, status_policy, created_revision, retired_revision,
  PRIMARY KEY(snapshot_digest, node_id),
  UNIQUE(snapshot_digest, semantic_key)
)

node_edge(
  snapshot_digest, source_node_id, target_node_id, edge_kind, label,
  PRIMARY KEY(snapshot_digest, source_node_id, target_node_id, edge_kind)
)
```

`edge_kind` is closed over `contains`, `implements`, `documents`, `configures`,
`routes`, `invokes`, `reads`, `writes`, `emits`, `consumes`, `verifies`,
`supersedes`, and `diverges_from`.

## Provenance and Git evolution

Git is a first-class immutable DAG, not a SHA string stored on an event.

```sql
git_commit(
  revision PRIMARY KEY, tree_digest, parent_revisions, author_name,
  author_email, authored_at, committed_at, subject, repository_uri
)

node_revision(
  snapshot_digest, node_id, revision, phase, strict_status,
  implementation_anchor, evidence_digest, recorded_at,
  PRIMARY KEY(snapshot_digest, node_id, revision, phase)
)
```

`node_revision` is append-only. Its phases are `cataloged`, `specified`,
`implemented`, `scenario-tested`, `trace-matched`, `evidence-accepted`,
`diverged`, `deprecated`, and `retired`. Existing `feature_history` is the L1
compatibility projection of this table.

## Anchors and artifacts

All claims attach to content-addressed anchors.

```sql
source_anchor(
  anchor_id PRIMARY KEY, snapshot_digest, authority, path, symbol,
  start_line, end_line, content_digest
)
implementation_anchor(
  anchor_id PRIMARY KEY, revision, language, path, symbol, artifact_kind,
  content_digest
)
node_anchor(snapshot_digest, node_id, anchor_id, role,
  PRIMARY KEY(snapshot_digest, node_id, anchor_id, role))
```

Authorities are `hermes-source`, `hermes-docs`, `hermes-tests`,
`ocaml-implementation`, `rust-implementation`, `ocaml-test`, and
`build-artifact`. Roles distinguish specification, reference behavior,
implementation, test, normalizer, and verifier.

## Universal artifact and knowledge graph

Everything that informs, implements, demonstrates, or tests a feature is a
content-addressed artifact: documentation and free text, diagrams, UI
components and screens, design notes, images/audio/video, source code,
fixtures, tests, traces, build outputs, and reports. `artifact_catalog` stores
its stable ID, kind, local path or locator, title, digest, and Git revision.
`node_artifact` attaches it to any fractal node with a role such as
`specification`, `implementation`, `test`, `visual-design`, `reference`, or
`evidence`.

`knowledge_link` keeps external knowledge systems as pointers rather than
copies: an artifact can link to `docs`, `wiki`, or `zk` under a typed relation
(`indexes`, `explains`, `renders`, `derives`, `supersedes`) and the same content
digest. This makes stale links detectable and preserves a single authoritative
artifact identity.

## Dynamic proof packet

L4 through L6 are typed execution artifacts.

```sql
scenario(snapshot_digest, l4_node_id, fixture_digest, environment_digest,
         expected_contract_digest, effect_boundary_digest)

normalized_trace(snapshot_digest, trace_id, l5_node_id, l4_node_id, side,
                 normalizer_id, normalizer_revision, schema_version,
                 trace_digest, payload_digest)

trace_comparison(snapshot_digest, l5_node_id, reference_trace_id,
                 candidate_trace_id, comparator_revision, verdict,
                 divergence_id, diff_digest)

verification_receipt(snapshot_digest, l6_node_id, l5_node_id,
                     candidate_revision, verifier_revision, gate_name,
                     command_digest, outcome, output_digest, recorded_at)
```

`side` is exactly `reference` or `candidate`; each required L5 node has one of
each under the same normalizer schema. A strict L6 proof requires a passing
receipt for an equal trace comparison, tied to the same snapshot and candidate
revision.

## Derived algebra

For required children `C(n)`:

```text
strict(n) = leaf_proof(n)                         if level(n) = L6
          = C(n) ≠ ∅ ∧ ∀ child ∈ C(n), strict(child) otherwise

coverage(n) = verified_required_descendants(n)
              / required_descendants(n)

evolution(n, revision) = inherited(parent(n), revision)
                         ⊕ local_events(n, revision)
```

An approved divergence may be shown in compatibility metrics but is never an
equal trace and never contributes to `strict`.

## Migration sequence

1. Add `git_commit`, `fractal_node`, `node_edge`, and `node_revision` as
   additive tables with immutable conflict checks.
2. Migrate the 18 `feature_catalog` records into L1 nodes below an L0 Hermes
   node; retain the current tables as projections.
3. Add source/doc anchors and map every L1 family to detailed L2 capabilities.
4. Add L3 contracts and L4 scenario packets before granting implementation
   status.
5. Replace ad-hoc L5/L6 records with typed trace comparisons and receipts.
6. Generate parity, coverage, history, control-flow, data-flow, and
   information-flow reports only from this graph.

## Safety invariants

- Snapshot and semantic identity are immutable.
- A node has one containment parent; the containment graph has exactly one L0
  root and no cycle.
- Every reference and candidate trace uses the same frozen snapshot and
  normalization version.
- Every historical event names an existing Git commit and node.
- An event conflict is rejected, never overwritten.
- Missing descendants, traces, or receipts are unsupported by default.
- Historical events aid auditability only; they cannot directly promote parity.

## Initial acceptance tests

- Replaying the identical catalog/history event is idempotent.
- Altering a persisted node, anchor, or event under the same identity fails.
- A cycle, skipped level, orphan node, or multiple L0 roots is rejected.
- A trace pair with different snapshots or normalizer versions is rejected.
- A passing receipt with a mismatched candidate Git revision is not admitted.
- Ancestor strict status becomes verified only when every required descendant
  has an admissible L6 receipt.
