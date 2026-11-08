---
name: strict-typed-refactor
description: High-assurance refactoring workflow for Lean 4, Mojo, Gleam, and OCaml with >95% quality gates.
---

# Instructions for Agentic Refactoring (`SC-POKA-YOKE-REFACTOR-001`)

Observed: 2026-11-08T21:20:00Z. Tags: `#fractal-l0` `#fractal-l3` `#fractal-l9` `#zk-adr` `#zero-muda`

## Phase 1: Invariant & Interface Lock (No Code Changes)
1. Identify the target module and list all public signatures:
   - **Lean 4 (`formal/lean/`):** Public `theorem` and `def` types (`autoImplicit = false` in `lakefile.toml`; `#guard_msgs` above `#eval`/`#check`).
   - **Mojo (`formal/mojo/`, `tools/*.mojo`):** Public `fn`/`def` and `struct` trait conformances (`Copyable`, `Movable`, `SIMD`), explicit argument conventions (`read`, `mut`, `var`).
   - **Gleam (`apps/cepaf_gleam/src/`):** Public module functions, `pub opaque type` boundaries (validated smart constructors), and OTP `Subject(Message)` actor contracts.
   - **OCaml (`engines/hermes/`, `tools/*.ml`):** The corresponding `.mli` interface file (`chmod 444` during internal module refactoring).
2. Verify existing test and proof health before editing. Never modify `/test` files or `.mli` files during an implementation refactor.

## Phase 2: Equivalence & Characterization Harness
1. If refactoring an executable function in Mojo, Gleam, or OCaml without >95% branch/expression coverage, first stop and write a property-based equivalence test (`QCheck` in OCaml, `qcheck` in Gleam, parameterized `mojo test` / differential oracle in Mojo) asserting `legacy_fn(input) == candidate_fn(input)`.
2. In Lean 4, extract helper lemmas using `have` or private `theorem`/`def` declarations before altering tactic proofs, and replay compiled `.olean` artifacts through the kernel.

## Phase 3: Forbidden Escape Hatches (Hard Rejects)
Never introduce any of the following constructs to force compilation:
- **Lean 4:** `sorry`, `admit`, `axiom`, `unsafe`, `@[implemented_by]`, `set_option linter false`
- **Mojo:** Unannotated dynamic `def` on systems paths, `UnsafePointer` or `bitcast` (unless inside `formal/mojo/lean_ffi_bridge.mojo`), `std.python`, dropping `@parameter` or SIMD width constraints
- **Gleam:** `let assert`, `panic`, `todo`, `unsafe_coerce`, or `external` FFI bindings in pure modules (`apps/cepaf_gleam/src/` enforces `0` `let assert` and `0` `panic as "NYI:"`)
- **OCaml:** `Obj.magic`, `Stdlib.(=)` on abstract types, `assert false`, catch-all `try ... with _ ->` blocks

## Phase 4: Verification Loop
Run `scripts/verify-refactor.sh` after every atomic edit. If any gate fails, revert or fix the implementation—never weaken the test, type signature, `.mli` interface, or linter rule.

## Reference Links
- Lean 4 Twin: [`formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean`](http://nas-1.tail55d152.ts.net:4100/files/formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean) (`SECTION 46`, `THM_POKAYOKE_01..06`)
- Mojo Differential Oracle: [`formal/mojo/full_system_code_oracle.mojo`](http://nas-1.tail55d152.ts.net:4100/files/formal/mojo/full_system_code_oracle.mojo)
- Pre-Commit Gate: [`scripts/verify-refactor.sh`](http://nas-1.tail55d152.ts.net:4100/files/scripts/verify-refactor.sh)
