# Native Subsystem (`native/`)

- **Ownership & Language Authority**: Bounded C, C++, Rust, and OCaml libraries.
- **Scope**: Short, deterministic, bounded native computational kernels or dispatch facades with strict ABI specifications.
- **Invariants**: Never perform unbounded work or blocking I/O in NIFs. Failsafe timeout bounds on all native calls.
