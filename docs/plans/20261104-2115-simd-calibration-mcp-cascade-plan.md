# Plan: Mojo SIMD Domain Calibration & MCP Cascade Ingress with Tailnet LLM/Embedding Accelerators

**Plan ID**: `uos/simd-calibration-mcp-cascade/20261104-2115`
**Timestamp**: 20261104-2115-
**Fractal Layer**: `#fractal-l0` `#fractal-l2` `#fractal-l5` `#zero-muda` `#km-triad`
**Sovereigns**: Codex (`gpt-6-luna`), Claude (`claude-opus-4-6`), Pi (`pi-caste02`)
**Canonical Contracts**: `SC-HARNESS-MCP-001`, `SC-LOCAL-CASCADE-001`, `SC-ZERO-REMOTE-TOKEN-001`

---

## 1. Summary & Verified Accelerators
We held host NVMe model download (Item 1) and focused on:
- **Item 2**: Domain-Specific Embedding Calibration for Mojo SIMD Prefilter.
- **Item 3**: MCP Tool Ingress Routing via Cascade.

We verified live network model inference accelerators on the Tailnet:
1. **`razr15-1` (`100.114.9.28:1234`)**:
   - `google/gemma-4-e4b`: Fast local LLM text generation (verified working, ~25 tokens generated in <500ms).
   - `text-embedding-nomic-embed-text-v1.5`: 768-dimensional dense vector embeddings (verified working, 42ms latency).
2. **`vm-1` (`100.78.98.18`)**:
   - Intel Core Ultra 9 285H (10 cores).
   - Ollama with `gemma3`, `gemma4`, `tinyllama`, `nomic-embed-text`.

---

## 2. Architecture: End-to-End Pipeline

```text
+----------------------------------------------------------------------------------------------------+
|                UOS TAILNET ACCELERATED SIMD CALIBRATION & MCP INGRESS CASCADE                      |
+----------------------------------------------------------------------------------------------------+
|                                                                                                    |
|    [ MCP Ingress: uos-mcp-stdio ]              [ Wisp HTTP: /api/v1/ai/resolve ]                   |
|    53 declared tools + ai_resolve_cascade                                                          |
|                    \                                   /                                           |
|                     v                                 v                                            |
|              [ cepaf_gleam/ai/stage0_mojo_probe ]                                                  |
|              Domain-Calibrated Mojo SIMD Prefilter (768-dim hash / UOS vocabulary)                 |
|                                     |                                                              |
|                     +---------------+---------------+                                              |
|                     |                               |                                              |
|            Score >= 700 (Match)           Score < 700 (Miss)                                       |
|                     |                               |                                              |
|                     v                               v                                              |
|             Stage 0 SIMD Ok                Stage 1: Shannon Compressor                             |
|             (0 Remote Tokens)                       |                                              |
|                                             Score < 0.85                                           |
|                                                     |                                              |
|                                                     v                                              |
|                                            Stage 2: Local Tailnet LLM                              |
|                                            (razr15-1: gemma-4-e4b / vm-1)                          |
|                                            Zero Remote Tokens Billed                               |
|                                                     |                                              |
|                                           (If Local Unavailable)                                   |
|                                                     v                                              |
|                                            Prajna Circuit Breaker                                  |
|                                            Cap: $2.00/hr ($0 Remote Billed Local)                  |
|                                                     v                                              |
|                                            [ C3I OTel Telemetry ]                                  |
|                                            "remote_tokens_billed": 0                               |
|                                                                                                    |
+----------------------------------------------------------------------------------------------------+
```

---

## 3. Work Breakdown & Tasks

- **Task c1**: Author domain vocabulary & 768-dim calibration projection in `apps/cepaf_gleam/src/cepaf_gleam/ai/mojo_prefilter_nif.gleam` and Mojo runner to calibrate UOS domain tokens (Lean, Gospel, ZK, STPA, CEPAF, Wisp, Lustre, Prajna).
- **Task c2**: Benchmark & verify calibrated Mojo SIMD prefilter achieves $\ge 90\%$ capture rate on UOS domain tokens with zero false rejections.
- **Task c3**: Integrate Tailnet Local LLM tier (`razr15-1` / `vm-1`) in `apps/cepaf_gleam/src/cepaf_gleam/ai/tailnet_llm_adapter.gleam` supporting local completions with 0 remote tokens.
- **Task c4**: Add `ai_resolve_cascade` and `ai_local_first_route` MCP tools in `apps/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam` and wire into `apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam`.
- **Task c5**: Comprehensive E2E test covering MCP cascade invocation and Tailnet LLM adapter (`apps/cepaf_gleam/test/mcp_cascade_ingress_test.gleam`).
- **Task c6**: Prove Lean 4 invariant theorem in `formal/lean/Tailnet_MCP_Cascade_Theorems.lean` proving Tailnet LLM local execution preserves zero remote billing.
- **Task c7**: 13-section journal `docs/journal/20261104-2130-simd-calibration-mcp-cascade-journal.md` with complete verification records.
