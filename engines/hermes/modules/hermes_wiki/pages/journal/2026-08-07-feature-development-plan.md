# Hermes Feature Development Plan — Journal

## Trigger and objective

Record the product feature-development plan for the Hermes Harness. The
harness repository and its SQLite state are the sole tracking authority.

## Current state

- Frozen Hermes snapshot: `70b2efe95be51e0658eb919b14168cff6b0a0a4f344652fcaecfc75543fa2cf6`
- Frozen inventory: 8,556 entries across 31 source domains
- Public product denominator: 18 L1 feature families
- Strict parity: `0 / 18` families, fail-closed
- Sa-plan projection: 18 durable feature tasks
- Harness commit at planning observation: `541dab8`

## Completed foundation

The harness has deterministic reference inventory, snapshot-bound feature
catalog rows, append-only Git feature history, a generic L0–L6 proof reducer,
artifact catalog and Docs/Wiki/ZK pointers, early scenario/trace/receipt
records, a Sa-plan bridge, and an executable lifecycle model with BDD/TDD and
chaos cases.

## Development sequence

1. Persist the complete fractal graph: L0–L6 nodes, containment and typed
   cross-edges, Git commits/revisions, and source/implementation anchors.
2. Migrate the 18 L1 catalog rows into the graph and create an L0 product root.
3. Expand each L1 family into source-anchored L2 capabilities and L3 contracts.
4. Define L4 fixtures, then collect normalized L5 reference/candidate traces.
5. Attach L6 verifier receipts and calculate strict status only by recursive
   all-required-child conjunction.
6. Implement behavior in dependency order: agent/provider/tool core;
   persistence/context/skills/MCP/delegation; CLI/automation/gateway; media,
   browser, execution backends, and applications.
7. Project database state into dashboard, documentation, wiki, and ZK links;
   these views remain non-authoritative.

## Quality protocol

Every capability requires a red-first test, a Given/When/Then scenario,
algebraic/property laws, deterministic chaos cases, Git-bound artifact links,
and snapshot-bound differential evidence. A regression is an append-only
`diverged` event; a repair returns to implementation and must create new trace
and proof records.

## Governing laws

- One L0 root; one containment parent per node; no cycles or skipped levels.
- Identical event replay is idempotent; same identity with changed payload is
  rejected.
- Source, scenario, traces, and receipt share one frozen snapshot.
- A strict receipt requires an equal normalized reference/candidate trace and
  matching candidate revision.
- Missing evidence, stale links, and unmodeled transitions count as unsupported.

## Immediate next slice

Implement durable `git_commit`, `fractal_node`, `node_edge`, and
`node_revision` tables, with immutable conflict tests; then seed L0 Hermes and
the existing 18 L1 families. This unlocks detailed L2–L6 materialization while
preserving the current catalog/history tables as compatibility projections.

## References

- [Product feature tracking](../product-feature-tracking.md)
- [Fractal provenance data model](../../superpowers/specs/2026-08-07-hermes-fractal-provenance-data-model.md)
- [Formal evolution model](../formal-evolution-model.md)
