---
migrated_from: docs/zk/20260807-hermes-architecture-decisions.md (zigvm-era tree, authored for Hermes)
---
# Architectural Decision: OpenRouter for Local LLM & TUI Rust FFI

**Date:** August 7, 2026
**Topic:** Hermes OCaml Port Architecture

## Decision
1. **Local LLM Backend:** We will use **OpenRouter** exclusively as the backend for the Local LLM functionality in the OCaml port of Hermes. This replaces previous local-only vLLM default assumptions, routing all inference through OpenRouter.
2. **Terminal User Interface:** We will utilize Rust's `ratatui` crate via a Foreign Function Interface (FFI). The Rust logic will live in `external/hermes_tui_rs` and be linked via C ABI.
3. **Verification Infrastructure:** The project will strictly adhere to the `zigvm_harness` SDLC and SRE specifications. All OCaml code will be validated against the L0-L9 verification gate.

## Rationale
- **OpenRouter** provides a standardized, unified API surface for multiple state-of-the-art models, simplifying the OCaml HTTP client integration while providing maximum model flexibility.
- **Rust FFI** allows us to bypass OCaml's limited native TUI ecosystem, tapping directly into the rich, async-capable Ratatui ecosystem to achieve parity with the original Python/React+Ink Hermes UI.
- **Harness Integration** ensures that the port remains structurally compliant with the existing homeostasis radar and safety boundaries of the parent system.