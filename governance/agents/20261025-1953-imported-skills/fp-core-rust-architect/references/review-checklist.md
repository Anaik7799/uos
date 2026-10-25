# fp-core Rust Review Checklist

## Required

- Touched Rust logic is expression-oriented and mostly pure.
- `fp-core = "0.1.9"` is present for crates with modified functional logic, unless exception is documented.
- Touched modules import `fp_core` where functional abstractions are used.
- Missing/error paths use `Option`/`Result`; no new `unwrap`, `expect`, or `panic!`.
- Accumulation uses folds/reduces.
- Transformations use iterator combinators and/or `Functor`.
- Nested optional/result flow uses `and_then`/`chain`/`?`.
- Side effects are isolated at IO/FFI/runtime boundaries.
- New algebraic abstractions have law tests or documented law reasoning.
- Touched logic meets the 95% functional target or documents an exception.

## Reject

- Mutation-heavy business logic.
- New panic paths in runtime code.
- Index loops where iterator/fold fits.
- Global mutable state.
- Unbounded imperative retry loops.
- Adding a Rust dependency without verifying docs/crates availability.

## Commands

```bash
rg -n "unwrap\\(|expect\\(|panic!|for .* in |while " <changed-rust-paths>
rg -n "fp_core|fp-core" <changed-rust-paths> Cargo.toml
rg -n "\\.map\\(|\\.and_then\\(|\\.filter_map\\(|\\.fold\\(|\\.try_fold\\(|compose|reduce\\(" <changed-rust-paths>
```
