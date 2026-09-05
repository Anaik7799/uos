# Formal Verification Subsystem (`formal/`)

- **Ownership & Language Authority**: OCaml / Gospel / Z3 SMT solver.
- **Scope**: Formal specifications, Gospel contract definitions (`.mli`), Z3 translation passes, mathematical models.
- **Invariants**: All solver invocations run in isolated, bounded child processes with strict timeouts and memory quotas. Undeclared axioms or timeouts fail closed.
