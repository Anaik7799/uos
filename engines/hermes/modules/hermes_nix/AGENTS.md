# `modules/hermes_nix` — agent guide

Read `AGENTS.md` at the repository root first; it governs. This file records what is true of **this module** and nothing else.

## Shape

| | |
|---|---:|
| libraries / executables declared | 9 |
| implementation files (`.ml`) | 21 |
| interfaces (`.mli`) | 12 |
| test executables | 8 |
| dune files | 1 |

**Declared:** `hermes_nix`, `test_nix_algebra`, `test_nix_command_contract`, `test_nix_intent`, `test_nix_ontology`, `test_nix_operation`, `test_nix_policy`, `test_nix_receipt`, `test_nix_sysml`

**Suites:** `test_nix_algebra`, `test_nix_command_contract`, `test_nix_intent`, `test_nix_ontology`, `test_nix_operation`, `test_nix_policy`, `test_nix_receipt`, `test_nix_sysml`

## Depends on

- `digestif`
- `hermes_harness_suite_telemetry`
- `hermes_stanza`
- `unix`
- `yojson`

## What binds work here

- **Interfaces first.** Write the `.mli` with each law in prose — what is true and *why it must be* — then the `.ml`. Never ship an `.mli` stating a law the `.ml` does not enforce.
- **Total at the edges.** Malformed input clamps to a defined value or returns a named error; it never raises and never silently drops an author's text.
- **R31 Intent-only control.** No raw shell strings or unvalidated child process executions; all effects require declarative `Nix_intent.t` admission and immutable `Nix_receipt_core.t` output.
- **Verify with the offload layer**: `dune exec modules/hermes_ops/ops_main.exe -- verify` (R22).

## Verify

```
eval $(opam env --switch=/home/an/dev/ver/zigvm --set-switch)
dune build
dune exec modules/hermes_nix/test_nix_intent.exe
dune exec modules/hermes_nix/test_nix_ontology.exe
dune exec modules/hermes_nix/test_nix_algebra.exe
dune exec modules/hermes_nix/test_nix_sysml.exe
dune exec modules/hermes_nix/test_nix_policy.exe
dune exec modules/hermes_nix/test_nix_receipt.exe
dune exec modules/hermes_nix/test_nix_command_contract.exe
dune exec modules/hermes_nix/test_nix_operation.exe
```
