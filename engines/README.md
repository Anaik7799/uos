# Engines Subsystem (`engines/`)

- **Ownership & Language Authority**: Zig (`engines/zigvm`) and OCaml/Dune (`engines/hermes`).
- **Scope**:
  - `engines/zigvm`: High-performance deterministic virtual machine and descriptor-relative VFS backend.
  - `engines/hermes`: Formal evidence oracle, Gospel specification checker, and bounded analysis engine.
- **Invariants**: No Bevy, no Graphite. Pure deterministic kernels.
