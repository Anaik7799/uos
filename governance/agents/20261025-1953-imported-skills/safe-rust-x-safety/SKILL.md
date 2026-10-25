---
name: safe-rust-x-safety
description: Use when creating, reviewing, or refactoring Rust code that must be safe-by-construction, especially protocol parsers, networking, async handlers, concurrency, FFI, unsafe wrappers, serialization, crypto, zero-copy, or domain APIs. Applies the RustConf 2024 Safety in an Unsafe World / Netstack3 X-safety method.
---

# Safe Rust X-Safety

## Core Method

Make invalid programs fail to compile.

1. **Define** the invariant on a Rust object: type, lifetime, trait, const generic, marker, capability token, typestate, or sealed module.
2. **Enforce** the invariant at construction/modification boundaries with private fields, smart constructors, checked conversions, RAII guards, exhaustive enums, or local unsafe wrappers.
3. **Consume** the invariant only through APIs whose signatures prove the preconditions are satisfied.

If source context is needed, read `docs/rust-safety/safe-rust-x-safety-source-map.md`.

## Implementation Workflow

1. Write down the safety properties before changing code.
2. Identify raw boundaries: CLI args, HTTP, JSON, DB rows, FFI, bytes, env vars, files, network packets, user input.
3. Parse raw values into refined/domain types at the boundary.
4. Keep internals total: no production `unwrap`, `expect`, `panic!`, unchecked indexing, unchecked slicing, or unchecked narrowing conversions.
5. Use typed errors that mirror the domain/protocol instead of strings or booleans.
6. Hide invariants behind private fields and constructors.
7. For async/concurrency, document or encode lock ordering and never hold blocking guards across `.await`.
8. For unsafe, isolate the unsafe operation, document `SAFETY:`, expose only safe APIs, and verify with focused tests plus Miri/Kani when available.

## Preferred Patterns

- Newtype for validated domain values: `UserId`, `RoomId`, `NonEmptyName`, `BoundedPort`.
- Typestate for lifecycle: `Socket<Open>`, `Request<Parsed>`, `Token<Verified>`.
- Phantom or zero-sized markers for capabilities, lock order, protocol version, or address family.
- Exhaustive enums for protocol outcomes and recovery actions.
- `TryFrom` and `FromStr` for boundary parsing.
- `NonZero*`, bounded integer wrappers, and checked arithmetic.
- Sealed traits for invariants that external crates must not implement.
- `#[must_use]` on values whose result must be consumed.

## Unsafe Checklist

- Can a safe library API remove the need for unsafe?
- Is the unsafe block the smallest possible scope?
- Is there a nearby `SAFETY:` comment explaining why all preconditions hold?
- Does every `unsafe fn` / `unsafe trait` have a `# Safety` section?
- Can safe callers trigger UB through the public API? If yes, the wrapper is unsound.
- Are aliasing, alignment, initialization, validity, lifetime, and unwind paths covered?
- Is there Miri or Kani coverage for the safe wrapper or proof harness?

## Review Output

When reviewing Rust, report:

- Invariants found or missing.
- Panic/partial-function sites.
- Unsafe boundaries and whether contracts are documented.
- Raw values that should become domain types.
- Numeric conversion and indexing risks.
- Async lock/await risks.
- Dependency safety gaps.
- Exact validation commands run or skipped.
