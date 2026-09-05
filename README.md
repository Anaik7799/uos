# Unified Operational System (UOS)

Unified Operational System (UOS) is a high-assurance, verified cybernetic operational monorepo integrating:
- **Supervision & Policy**: Pure Gleam/OTP (`apps/cepaf_gleam`, `apps/*`)
- **Evidence & Formal Oracles**: Hermes OCaml/Dune (`engines/hermes`)
- **Deterministic Low-Level Runtime**: ZigVM (`engines/zigvm`)
- **Isolated AI Inference**: Pinned Modular MAX/Mojo (`services/inference/max`)
- **Version Control**: Standalone, non-colocated Jujutsu (`.jj/`)

---

## 1. Zero-Muda & Security Invariants

1. **Standalone Jujutsu VCS**: Git commands are prohibited inside UOS. All changes use `jj` change, commit, bookmark, and operation semantics.
2. **Permanent Exclusions**: Bevy and Graphite are permanently barred from source trees, dependencies, runtime roles, and imported history.
3. **Secret Quarantine**: Credentials, private keys, live database/WAL files, and session states are never checked in or hashed.
4. **Two-Key Verification**: No operational credit is granted without fresh working behavior and machine-verifiable formal specification.
5. **Language Boundaries**:
   - Live control, APIs, and agent supervision are strictly Gleam/OTP.
   - Runtime engine kernels are Zig.
   - Formal oracles and evidence engines are OCaml.
   - Python is strictly confined to `services/inference/max`.
   - C/C++/Rust/OCaml NIFs are short, deterministic, bounded kernels or dispatch facades only.

---

## 2. Directory Taxonomy

| Directory | Ownership & Language Authority | Description |
| :--- | :--- | :--- |
| `apps/` | Gleam/OTP | Live operational applications, agent swarms, CEPAF coordinator |
| `engines/` | Zig / OCaml | `engines/zigvm` (Zig) and `engines/hermes` (OCaml) |
| `services/` | Isolated daemons | Supervised isolated subsystems (e.g. Modular MAX inference) |
| `native/` | C, C++, Rust, OCaml | Bounded, deterministic native kernel libraries / NIF dispatch |
| `intelligence/`| Gleam / OCaml | Rete-UL evaluation, semantic routing, knowledge networks |
| `formal/` | OCaml, Gospel, Z3 | Formal specifications, mathematical contracts, verification oracles |
| `contracts/` | Schema / IDL | Cross-boundary data and message definitions |
| `tests/` | Gleam / OCaml / Zig | System-level integration, fuzzing, and conformance suites |
| `ops/` | Nix / Gleam | Declarative environment, telemetry, operational supervision |
| `tools/` | Gleam / OCaml | Certified internal developer tooling and CLI utilities |
| `data/` | Data / SQL | Canonical schemas, baseline tables, static ontologies |
| `governance/` | Declarative TOML | Policies, capability inventories, timestamp and journal contracts |
| `docs/` | Markdown | System designs, specifications, handovers, and architecture records |
| `third_party/` | External | Pinned, audited vendor projections (zero-Muda compliant) |
| `migration/` | Transitory | Source maps, quarantine ledgers, baseline migration evidence |
| `legacy/` | Read-only | Historical evidence and differential reference oracles |
| `generated/` | Projection | Machine-generated projections from canonical registries |
| `var/` | Local ephemeral | Local runtime scratch, sockets, logs (never committed) |

---

## 3. Governance Authority

The canonical authority for operational conduct, agent behavior, and coding standards is [`AGENTS.md`](AGENTS.md). All AI agents and human operators must comply with its directives.
