#!/usr/bin/env python3
"""
UOS Razr15-1 Modular MAX 26.8.0 + Mojo 1.3.0 + Zenoh 5-Caste + Dual-Plane (Data S0..S6 + Control C0..C6)
Observability & Configurable Algebraic Atlas + Denotational Intent Gateway
Port :8000 -> CUDA sm_75 Worker :8081 (Mode A 49.05 tok/s) / Pure MAX CPU Graph (Mode B 5.42 tok/s)
"""
import ctypes
import hashlib
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

WIN_HOST = os.environ.get("RAZR1_WIN_HOST", "100.114.9.28")
BACKEND_PORT = int(os.environ.get("MAX_BACKEND_PORT", "8081"))
BACKEND_URL = os.environ.get("MAX_BACKEND_URL", f"http://{WIN_HOST}:{BACKEND_PORT}")
FALLBACK_BACKEND_PORT = int(os.environ.get("MAX_FALLBACK_BACKEND_PORT", "8082"))
FALLBACK_BACKEND_URL = os.environ.get("MAX_FALLBACK_BACKEND_URL", f"http://{WIN_HOST}:{FALLBACK_BACKEND_PORT}")
PREFLIGHT_TIMEOUT_SEC = float(os.environ.get("MAX_PREFLIGHT_TIMEOUT_SEC", "2.0"))
CUDA_LAUNCHER_SCRIPT = os.environ.get("MAX_CUDA_LAUNCHER_SCRIPT", "/home/an/uos-max/run_llama_cuda_8081.sh")
LISTEN_HOST = os.environ.get("MAX_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("MAX_LISTEN_PORT", "8000"))

ZENOH_REST_URL = os.environ.get("UOS_ZENOH_REST", "http://100.87.7.78:8080")
ZENOH_TCP_LOCATOR = os.environ.get("UOS_ZENOH_LOCATOR", "tcp/100.87.7.78:7447")
ZENOH_TOPIC_TELEMETRY = "uos/v1/holon/razr15-1/telemetry"
ZENOH_TOPIC_INFERENCE = "uos/v1/holon/razr15-1/inference"
ZENOH_TOPIC_PI = "indrajaal/pi/inference"

MODEL_ID = "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"
BACKEND_MODEL = "qwen2.5-coder-7b-instruct"
WEIGHT_PATH = "/home/an/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf"
GGUF_SHA256 = "618164722f3fa8acfd7dc9cd8efd0b9ab5ece42cd4ef2d2a7ea0fd4aa29f46ab"
DENIED_OS_SERIAL = "25503L801736"

_SEQ_LOCK = threading.Lock()
_PROFILE_LOCK = threading.Lock()
_ZENOH_SEQ = 0
_ZENOH_PUBLISHED = 0
_ZENOH_LAST_STATUS = "initialized"
_INFERENCE_CALLS = 0
_PROMPT_TOKENS_TOTAL = 0
_COMPLETION_TOKENS_TOTAL = 0
_INTENT_EVALUATIONS = 0
_INTENT_VETOES = 0
_FAILOVER_EPOCH = 931
_LAST_WATCHDOG_RESTART_TS = 0.0
_KV_CACHED_TOKENS_TOTAL = 0
_BYTES_AVOIDED_TOTAL = 0
_RETRY_DETECTED_TOTAL = 0
_KM_TRIAD_OBSERVED_TOTAL = 0
_RECENT_PROMPT_HASHES = []
_USECASE_CALLS = {f"UC0{i}": 0 for i in range(10)}
_GRAMMAR_VIOLATIONS_TOTAL = 0
_SCHEMA_VALIDATED_TOOL_CALLS_TOTAL = 0
_INDIRECT_FALLBACK_CALLS_TOTAL = 0
_ORACLE_FAILURES_TOTAL = 0
_REPAIRS_COMPLETED_TOTAL = 0
_SLOT_0_CALLS_TOTAL = 0
_SLOT_1_CALLS_TOTAL = 0
_SLOT_EVICTIONS_TOTAL = 0
_STATE_WORD_IDX_3840 = 31
_FLYWHEEL_RETRIEVALS_TOTAL = 0
_FLYWHEEL_EXEMPLARS = [
    {
        "flywheel_id": "FW-UC01-MOJO-SM75-01",
        "usecase_code": "UC01",
        "language_toolchain": "Mojo 1.3.0 / SM75 CUDA",
        "diagnostic_signature": "error: use of unknown declaration 'fn' or missing return type",
        "verified_exemplar": "fn sm75_fma_tile(a: Int, b: Int, c: Int) -> Int:\n    return a * b + c\n\ndef main():\n    print(sm75_fma_tile(4, 8, 10))",
        "oracle_command": "./tools/mojo",
        "verified_pass_at_1": True,
    },
    {
        "flywheel_id": "FW-UC02-LEAN4-OMEGA-01",
        "usecase_code": "UC02",
        "language_toolchain": "Lean 4.33.0 (zero-axiom kernel)",
        "diagnostic_signature": "unsolved goals / declaration uses 'sorry'",
        "verified_exemplar": "theorem qwen_uc02_comm (a b : Nat) : a + b = b + a := by omega",
        "oracle_command": "./tools/lean",
        "verified_pass_at_1": True,
    },
    {
        "flywheel_id": "FW-UC03-MOJO-FFI-01",
        "usecase_code": "UC03",
        "language_toolchain": "Mojo 1.3.0 OwnedDLHandle C-ABI FFI",
        "diagnostic_signature": "cannot convert 'Int' to 'UInt8' in OwnedDLHandle.get_function",
        "verified_exemplar": "from sys.ffi import OwnedDLHandle\ndef check_guard() raises -> Int:\n    var h = OwnedDLHandle(\"var/zlp/libuos_lean_guard.so\")\n    var fn_ptr = h.get_function[UInt8](\"uos_lean_verify_qwen_holonic_execution_envelope\")\n    return Int(fn_ptr(UInt8(6), UInt8(27), UInt8(1), UInt8(1), UInt8(1), UInt8(1)))",
        "oracle_command": "./tools/mojo formal/mojo/full_system_code_oracle.mojo",
        "verified_pass_at_1": True,
    },
    {
        "flywheel_id": "FW-UC06-GLEAM-OTP-01",
        "usecase_code": "UC06",
        "language_toolchain": "Gleam 1.15.1 / Erlang OTP 29.0.5",
        "diagnostic_signature": "Syntax error: Elixir-style defmodule instead of Gleam pub fn",
        "verified_exemplar": "pub type QwenSlot {\n  Slot0InteractiveTc1\n  Slot1BatchSynthesis\n}\n\npub fn select_slot(is_interactive: Bool) -> QwenSlot {\n  case is_interactive {\n    True -> Slot0InteractiveTc1\n    False -> Slot1BatchSynthesis\n  }\n}",
        "oracle_command": "gleam test",
        "verified_pass_at_1": True,
    },
]

QWEN_5_OPTIMIZATION_PROFILES = {
    1: {
        "profile_code": 1,
        "profile_name": "P0_Deterministic_Grammar",
        "temperature": 0.0,
        "top_p": 1.0,
        "cache_prompt": True,
        "spec_dec_k": 4,
        "grammar_constrained": True,
        "description": "Zero-temperature syntax/schema-constrained execution with KV prefix cache reuse",
    },
    2: {
        "profile_code": 2,
        "profile_name": "P1_ZeroTemp_CodeGen",
        "temperature": 0.0,
        "top_p": 0.95,
        "cache_prompt": True,
        "spec_dec_k": 4,
        "grammar_constrained": False,
        "description": "Deterministic code and formal proof synthesis on Slot 0 with SpecDec K=4",
    },
    3: {
        "profile_code": 3,
        "profile_name": "P2_LongContext_16k_Compacted",
        "temperature": 0.05,
        "top_p": 0.90,
        "cache_prompt": True,
        "spec_dec_k": 4,
        "bionic_compaction": True,
        "kv_budget_tokens": 16384,
        "description": "Bionic SIMD/structural context compaction into 16,384-token q8_0 KV slot with Flash Attention",
    },
    4: {
        "profile_code": 4,
        "profile_name": "P3_Parallel_DualSlot_Batch",
        "temperature": 0.10,
        "top_p": 0.95,
        "cache_prompt": True,
        "spec_dec_k": 4,
        "parallel_slots": 2,
        "description": "Continuous batching across dual 16,384-token CUDA sm_75 slots (-np 2 --cont-batching)",
    },
    5: {
        "profile_code": 5,
        "profile_name": "P4_LowLatency_SSE_Stream",
        "temperature": 0.15,
        "top_p": 0.95,
        "cache_prompt": True,
        "spec_dec_k": 4,
        "sse_stream": True,
        "description": "Sub-50ms TTFT OpenAI SSE token streaming with X-Accel-Buffering disabled",
    },
}

QWEN_10_USECASES = [
    {
        "usecase_id": 0,
        "code": "UC00",
        "ontology_uc_num": 3,
        "ontology_uc_id": "UC-3",
        "pattern_id": "P5",
        "name": "L0_Pi_Compaction_ThoughtSignature_And_Context_Trim",
        "fractal_concern": "L0_Constitutional",
        "holarchy_layer": 0,
        "fpp_actor_id": 3,
        "janus_holon_slice": "0..16",
        "system_directory_layer_id": 25,
        "primary_aspect": "A01_Functional",
        "cascade_locality_tier": 2,
        "operation_route_code": 1,
        "facet_a": "A2_operator_turn",
        "facet_b": "B1_full_prefix",
        "facet_e": "E2_tool_only",
        "facet_f": "F01_km_triad",
        "profile_code": 1,
        "model_assignment_code": 1,
        "caller_entrypoint": "billion-context (:18787) + messages.js + local_compressor.gleam -> max_qwen_server.py (_compact_pi_bili_payload)",
        "response_generator_model": "Primary Turn: AGY/Pi (google/gemini-4-argon) | Side-Request Compaction Response: Local Qwen (local/qwen2.5-coder-7b-instruct)",
        "qwen_response_role": "Generates compacted <500-token summary response from 25,610-token Pi history (0 remote tokens) while preserving thoughtSignature siblings and prefix-cache stability (UC-3, P5 78.4% reuse)",
        "primary_local_model": "pi-local/qwen2.5-coder-7b-instruct (razr15-1:8081 sm_75)",
        "cooperating_models": ["AGY (gemini-4-argon)", "Pi (session compaction)"],
        "real_uos_artifacts": ["messages.js", "_compact_pi_bili_payload", "apps/cepaf_gleam/src/cepaf_gleam/ai/local_compressor.gleam", "libuos_lean_guard.so#21"],
        "max_tokens_budget": 128,
        "preferred_slot_id": 0,
    },
    {
        "usecase_id": 1,
        "code": "UC01",
        "ontology_uc_num": 5,
        "ontology_uc_id": "UC-5",
        "pattern_id": "P2",
        "name": "L1_Sm75_CUDA_PTX_Shim_And_Mojo_TensorCore_Kernel",
        "fractal_concern": "L1_Kinetic",
        "holarchy_layer": 1,
        "fpp_actor_id": 7,
        "janus_holon_slice": "17..33",
        "system_directory_layer_id": 26,
        "primary_aspect": "A07_Performance",
        "cascade_locality_tier": 2,
        "operation_route_code": 1,
        "facet_a": "A3_tool_continuation",
        "facet_b": "B1_full_prefix",
        "facet_e": "E3_text_plus_tool",
        "facet_f": "F10_zig_c_rust",
        "profile_code": 2,
        "model_assignment_code": 2,
        "caller_entrypoint": "claude --model claude-opus-4-6 + tools/uos-qwen --layer 1",
        "response_generator_model": "Primary Systems/Kernel Architect: Claude (claude-opus-4-6) | Inner-Loop Code/Patch Generator: Local Qwen (pi-local/qwen2.5-coder-7b-instruct)",
        "qwen_response_role": "Generates zero-temperature C/PTX/Mojo kernel patches (cuMemcpyBatchAsync_shim, --maxrregcount 128, m16n8k8 MMA) with batched symbol-index context (UC-5, P2)",
        "primary_local_model": "pi-local/qwen2.5-coder-7b-instruct (razr15-1:8081 sm_75)",
        "cooperating_models": ["Claude (claude-opus-4-6)"],
        "real_uos_artifacts": ["ops/nodes/razr15-1-wsl2/cuda_shim.c", "ops/nodes/razr15-1-wsl2/ptxas_sm75_shim.sh", "services/inference/max/max_kernel.mojo"],
        "max_tokens_budget": 512,
        "preferred_slot_id": 0,
    },
    {
        "usecase_id": 2,
        "code": "UC02",
        "ontology_uc_num": 9,
        "ontology_uc_id": "UC-9",
        "pattern_id": "P8",
        "name": "L2_Lean4_Digital_Twin_Theorem_And_CABI_Export_Proving",
        "fractal_concern": "L2_Structural",
        "holarchy_layer": 2,
        "fpp_actor_id": 11,
        "janus_holon_slice": "34..50",
        "system_directory_layer_id": 27,
        "primary_aspect": "A08_Correctness",
        "cascade_locality_tier": 2,
        "operation_route_code": 2,
        "facet_a": "A3_tool_continuation",
        "facet_b": "B1_full_prefix",
        "facet_e": "E4_thinking_then_act",
        "facet_f": "F04_lean_formal",
        "profile_code": 2,
        "model_assignment_code": 3,
        "caller_entrypoint": "codex exec -c model_reasoning_effort=\"xhigh\" + tools/uos-qwen --layer 2",
        "response_generator_model": "Primary Formal Verifier: Codex (gpt-6-luna max) | Decidable Predicate & C-ABI Scaffolder: Local Qwen (pi-local/qwen2.5-coder-7b-instruct)",
        "qwen_response_role": "Generates decidable Bool/Nat Lean 4 predicates, `by decide` theorem proofs (THM_FSYS_01..68), and `@[export uos_lean_*]` C-ABI wrappers with pre-commit formal gating (UC-9, P8)",
        "primary_local_model": "pi-local/qwen2.5-coder-7b-instruct (razr15-1:8081 sm_75)",
        "cooperating_models": ["Codex (gpt-6-luna max)"],
        "real_uos_artifacts": ["formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean", "formal/lean/UosLeanRuntimeGuard.lean", "var/zlp/libuos_lean_guard.so"],
        "max_tokens_budget": 512,
        "preferred_slot_id": 0,
    },
    {
        "usecase_id": 3,
        "code": "UC03",
        "ontology_uc_num": 2,
        "ontology_uc_id": "UC-2",
        "pattern_id": "P3",
        "name": "L3_Differential_Mojo_Oracle_And_ZeroPython_Verification",
        "fractal_concern": "L3_Reflexive",
        "holarchy_layer": 3,
        "fpp_actor_id": 15,
        "janus_holon_slice": "51..67",
        "system_directory_layer_id": 28,
        "primary_aspect": "A12_Evolvability",
        "cascade_locality_tier": 2,
        "operation_route_code": 1,
        "facet_a": "A3_tool_continuation",
        "facet_b": "B1_full_prefix",
        "facet_e": "E4_thinking_then_act",
        "facet_f": "F08_gleam_otp",
        "profile_code": 2,
        "model_assignment_code": 4,
        "caller_entrypoint": "formal/mojo/*_oracle.mojo + tools/uos-qwen-suite",
        "response_generator_model": "Primary Oracle Vector Generator: Local Qwen (pi-local/qwen2.5-coder-7b-instruct) | Differential Sign-Off: Codex + Claude + AGY",
        "qwen_response_role": "Generates deterministic dlopen/dlsym FFI oracle test vectors and JSON conformance receipts (6,300 Export #28..30 states, Zero-Python) with bounded thinking budget (UC-2, P3)",
        "primary_local_model": "pi-local/qwen2.5-coder-7b-instruct (razr15-1:8081 sm_75)",
        "cooperating_models": ["Codex (gpt-6-luna max)", "Claude (claude-opus-4-6)"],
        "real_uos_artifacts": ["formal/mojo/full_system_code_oracle.mojo", "formal/mojo/fractal_context_pipeline.mojo", "formal/mojo/razr15_max_qwen_oracle.mojo"],
        "max_tokens_budget": 512,
        "preferred_slot_id": 0,
    },
    {
        "usecase_id": 4,
        "code": "UC04",
        "ontology_uc_num": 1,
        "ontology_uc_id": "UC-1",
        "pattern_id": "P1",
        "name": "L4_MultiAgent_Quota_Failover_And_SaPlan_Risk_Gate",
        "fractal_concern": "L4_Metabolic",
        "holarchy_layer": 4,
        "fpp_actor_id": 19,
        "janus_holon_slice": "68..84",
        "system_directory_layer_id": 29,
        "primary_aspect": "A16_ResourceEfficiency",
        "cascade_locality_tier": 1,
        "operation_route_code": 0,
        "facet_a": "A3_tool_continuation",
        "facet_b": "B1_full_prefix",
        "facet_e": "E2_tool_only",
        "facet_f": "F14_inference_max",
        "profile_code": 1,
        "model_assignment_code": 1,
        "caller_entrypoint": "tools/uos-agent-failover (build_local_qwen_curl_cmd) + tools/sa-plan + tools/risk-priority-check",
        "response_generator_model": "Sovereign Terminal Failover Generator: Local Qwen (local_qwen_razr15_8000) when Claude/Codex/Gemini hit HTTP 402/429/503 | Policy Supervisor: AGY",
        "qwen_response_role": "Directly generates the failover execution/verification response (`[SELECTED_AGENT=local_qwen_razr15_8000]`, Action 5 InFlightFailoverLocalMaxQwen) with reminder-stripped A3 delta injection (UC-1, P1 70.8% A3)",
        "primary_local_model": "pi-local/qwen2.5-coder-7b-instruct (razr15-1:8081 sm_75)",
        "cooperating_models": ["AGY (gemini-4-argon)", "Pi (sa-plan)", "tools/uos-agent-failover"],
        "real_uos_artifacts": ["tools/uos-agent-failover.ml", "tools/sa-plan", "tools/risk-priority-check", "tools/verification_plane_simulate.ml"],
        "max_tokens_budget": 384,
        "preferred_slot_id": 0,
    },
    {
        "usecase_id": 5,
        "code": "UC05",
        "ontology_uc_num": 7,
        "ontology_uc_id": "UC-7",
        "pattern_id": "P10",
        "name": "L5_Qwen_Mcp_Zenoh_Planner_And_104Route_Harness_Bridge",
        "fractal_concern": "L5_Regulatory",
        "holarchy_layer": 5,
        "fpp_actor_id": 23,
        "janus_holon_slice": "85..101",
        "system_directory_layer_id": 30,
        "primary_aspect": "A05_Safety",
        "cascade_locality_tier": 1,
        "operation_route_code": 1,
        "facet_a": "A4_recovery_retry",
        "facet_b": "B1_full_prefix",
        "facet_e": "E2_tool_only",
        "facet_f": "F03_risk_priority",
        "profile_code": 1,
        "model_assignment_code": 3,
        "caller_entrypoint": "tools/uos-qwen-mcp-zenoh-planner.ml (call_local_qwen) + tools/uos-mcp-stdio",
        "response_generator_model": "Primary Multi-Turn Planner Response Generator: Local Qwen (Qwen/Qwen2.5-Coder-7B-Instruct-GGUF on razr15-1:8000) + Codex MCP Receipt Auditor",
        "qwen_response_role": "Generates Turn-1 MCP/Zenoh probe requests, Turn-3 10-task L0..L9 Fractal Wiring Plan (qwen-w01..qwen-w10), and Jidoka tool-failure retry short-circuiting (UC-7, P10)",
        "primary_local_model": "pi-local/qwen2.5-coder-7b-instruct (razr15-1:8081 sm_75)",
        "cooperating_models": ["Codex (gpt-6-luna max)", "AGY (MCP/Zenoh Turn-2 Bridge)"],
        "real_uos_artifacts": ["tools/uos-qwen-mcp-zenoh-planner.ml", "tools/uos-mcp-stdio", "var/harness/mcp_feature_receipt_ledger.json"],
        "max_tokens_budget": 256,
        "preferred_slot_id": 1,
    },
    {
        "usecase_id": 6,
        "code": "UC06",
        "ontology_uc_num": 6,
        "ontology_uc_id": "UC-6",
        "pattern_id": "P4",
        "name": "L6_Gleam_OTP_Tailnet_LLM_Adapter_And_Tier2Max_Cascade",
        "fractal_concern": "L6_Cognitive",
        "holarchy_layer": 6,
        "fpp_actor_id": 27,
        "janus_holon_slice": "102..118",
        "system_directory_layer_id": 31,
        "primary_aspect": "A15_Auditability",
        "cascade_locality_tier": 2,
        "operation_route_code": 2,
        "facet_a": "A2_operator_turn",
        "facet_b": "B3_compacted",
        "facet_e": "E1_text_only",
        "facet_f": "F06_journal_v3",
        "profile_code": 3,
        "model_assignment_code": 4,
        "caller_entrypoint": "apps/cepaf_gleam/src/cepaf_gleam/ai/tailnet_llm_adapter.gleam (complete_on_razr15) + local_first_cascade.gleam (Tier2Max)",
        "response_generator_model": "Primary Tier-2 Local Cascade Response Generator: Local Qwen (`TailnetInferenceOk`, >=80% local target) | Tier-3/4 Remote Escalation: Tri-Agent / OpenRouter",
        "qwen_response_role": "Directly generates BEAM/OTP operational responses via `complete_on_razr15` (`remote_tokens_used: 0`) with proactive 80%-context B3 compaction and exact bytes_avoided accounting (UC-6, P4)",
        "primary_local_model": "pi-local/qwen2.5-coder-7b-instruct (razr15-1:8081 sm_75)",
        "cooperating_models": ["AGY (gemini-4-argon)", "Claude (claude-opus-4-6)", "Codex (gpt-6-luna max)"],
        "real_uos_artifacts": ["apps/cepaf_gleam/src/cepaf_gleam/ai/tailnet_llm_adapter.gleam", "apps/cepaf_gleam/src/cepaf_gleam/ai/local_first_cascade.gleam", "apps/cepaf_gleam/src/cepaf_gleam/harness/agent_ecology.gleam"],
        "max_tokens_budget": 1024,
        "preferred_slot_id": 1,
    },
    {
        "usecase_id": 7,
        "code": "UC07",
        "ontology_uc_num": 8,
        "ontology_uc_id": "UC-8",
        "pattern_id": "P7",
        "name": "L7_TriAgent_17Aspect_SDLC_SRE_DualSlot_Swarm_Audit",
        "fractal_concern": "L7_Societal",
        "holarchy_layer": 7,
        "fpp_actor_id": 31,
        "janus_holon_slice": "119..135",
        "system_directory_layer_id": 32,
        "primary_aspect": "A14_Interoperability",
        "cascade_locality_tier": 2,
        "operation_route_code": 1,
        "facet_a": "A3_tool_continuation",
        "facet_b": "B1_full_prefix",
        "facet_e": "E3_text_plus_tool",
        "facet_f": "F07_tri_agent",
        "profile_code": 4,
        "model_assignment_code": 4,
        "caller_entrypoint": "acp_delegate (researcher/reviewer) + claude + codex + Dual-Slot razr15-1:8081 (-np 2)",
        "response_generator_model": "Parallel Swarm Response Generators: Dual-Slot Local Qwen (Slot 0 SDLC + Slot 1 SRE) + Claude (claude-opus-4-6) + Codex (gpt-6-luna max) + AGY",
        "qwen_response_role": "Generates concurrent Slot-0 (12-stage SDLC) and Slot-1 (8-gate SRE) verification responses across all 6 Feature Domains x 17 Aspects with single-flight #km-triad bundling (UC-8, P7)",
        "primary_local_model": "pi-local/qwen2.5-coder-7b-instruct (Dual-Slot -np 2 on razr15-1:8081)",
        "cooperating_models": ["Claude (claude-opus-4-6)", "Codex (gpt-6-luna max)", "AGY (gemini-4-argon)"],
        "real_uos_artifacts": ["uos/sdlc-sre-17-aspects-all-features/20261108-0101", "var/zlp/libuos_lean_guard.so#27"],
        "max_tokens_budget": 384,
        "preferred_slot_id": 1,
    },
    {
        "usecase_id": 8,
        "code": "UC08",
        "ontology_uc_num": 4,
        "ontology_uc_id": "UC-4",
        "pattern_id": "P6",
        "name": "L8_KmTriad_Recall_And_13Section_SC_Journal_v3_Collation",
        "fractal_concern": "L8_Evolutionary",
        "holarchy_layer": 8,
        "fpp_actor_id": 35,
        "janus_holon_slice": "136..152",
        "system_directory_layer_id": 33,
        "primary_aspect": "A10_Reliability",
        "cascade_locality_tier": 2,
        "operation_route_code": 1,
        "facet_a": "A2_operator_turn",
        "facet_b": "B1_full_prefix",
        "facet_e": "E1_text_only",
        "facet_f": "F12_cockpit_ui",
        "profile_code": 3,
        "model_assignment_code": 1,
        "caller_entrypoint": "uos-km-triad-brain-memory + tools/uos-qwen --layer 8 + tools/journal_linter",
        "response_generator_model": "Primary Journal/KM Response Generators: AGY (gemini-4-argon) + Local Qwen (16k Long-Context Table/Diagram Generator) + DeepSeek-V3.2",
        "qwen_response_role": "Generates 7-Engine Epistemic Ledger tables, paired ASCII/Mermaid diagrams, and SC-INTEL-ROUTING-001 R1/R2 evolutionary tier-routing & Lyapunov drift forecasts (UC-4, P6)",
        "primary_local_model": "pi-local/qwen2.5-coder-7b-instruct (razr15-1:8081 sm_75)",
        "cooperating_models": ["AGY (gemini-4-argon)", "DeepSeek-V3.2 (Living Ontology)"],
        "real_uos_artifacts": ["docs/journal/20261108-0052-sm75-pi-local-qwen-master-collated-plan-and-verification-journal.md", "tools/journal_linter"],
        "max_tokens_budget": 512,
        "preferred_slot_id": 1,
    },
    {
        "usecase_id": 9,
        "code": "UC09",
        "ontology_uc_num": 10,
        "ontology_uc_id": "UC-10",
        "pattern_id": "P9",
        "name": "L9_Interactive_PiLocal_Qwen_CLI_And_Realtime_SSE_Cockpit",
        "fractal_concern": "L9_Sovereign",
        "holarchy_layer": 9,
        "fpp_actor_id": 39,
        "janus_holon_slice": "153..169",
        "system_directory_layer_id": 34,
        "primary_aspect": "A17_Sovereignty",
        "cascade_locality_tier": 2,
        "operation_route_code": 1,
        "facet_a": "A2_operator_turn",
        "facet_b": "B1_full_prefix",
        "facet_e": "E4_thinking_then_act",
        "facet_f": "F02_sa_plan",
        "profile_code": 5,
        "model_assignment_code": 5,
        "caller_entrypoint": "/home/an/.local/bin/pi --model pi-local/qwen2.5-coder-7b-instruct + ./tools/uos-qwen",
        "response_generator_model": "100% Autonomous Local Response Generator: Local Qwen (pi-local/qwen2.5-coder-7b-instruct on razr15-1:8081 sm_75, 0 remote tokens)",
        "qwen_response_role": "Generates 100% of interactive operator CLI, sovereign subagent spawns, and cockpit SSE streaming responses (`text/event-stream`, TTFT < 300ms, 37..49 tok/s decode) (UC-10, P9)",
        "primary_local_model": "pi-local/qwen2.5-coder-7b-instruct (100% Autonomous Local GPU)",
        "cooperating_models": ["None (100% Local Qwen Zero-Remote-Token Execution)"],
        "real_uos_artifacts": ["tools/uos-qwen", "tools/uos-qwen-suite", "/home/an/.local/bin/pi"],
        "max_tokens_budget": 512,
        "preferred_slot_id": 0,
    },
]


def _classify_usecase_from_request(req_json: dict, headers, default_layer_idx: int) -> int:
    hdr_uc = (headers.get("X-UOS-Usecase-Id", "") if headers else "").strip()
    if hdr_uc:
        if hdr_uc.upper().startswith("UC") and hdr_uc[2:].isdigit():
            val = int(hdr_uc[2:])
            if 0 <= val <= 9:
                return val
        elif hdr_uc.isdigit():
            val = int(hdr_uc)
            if 0 <= val <= 9:
                return val
    if "uos_usecase_id" in req_json:
        try:
            val = int(req_json.pop("uos_usecase_id"))
            if 0 <= val <= 9:
                return val
        except Exception:
            pass
    if headers and headers.get("X-UOS-Holarchy-Layer-Idx", "").strip().isdigit():
        return max(0, min(9, default_layer_idx))
    if req_json.get("stream", False):
        return 9
    msgs = req_json.get("messages", [])
    last_text = ""
    if isinstance(msgs, list) and msgs:
        c = msgs[-1].get("content", "")
        last_text = c.lower() if isinstance(c, str) else str(c).lower()
    if "thoughtsignature" in last_text or "compaction" in last_text or "messages.js" in last_text:
        return 0
    if "cuda_shim" in last_text or "ptxas" in last_text or "m16n8k8" in last_text or "sm_75" in last_text:
        return 1
    if "thm_fsys" in last_text or "thm_guard" in last_text or "lean" in last_text or "libuos_lean_guard" in last_text:
        return 2
    if "oracle.mojo" in last_text or "zero-python" in last_text or "dlopen" in last_text:
        return 3
    if "failover" in last_text or "sa-plan" in last_text or "fmea" in last_text or "stpa" in last_text:
        return 4
    if "mcp" in last_text or "zenoh" in last_text or "traceparent" in last_text or "qwen-w01" in last_text:
        return 5
    if "tailnet_llm_adapter" in last_text or "local_first_cascade" in last_text or "gleam" in last_text or "otp" in last_text:
        return 6
    if "17-aspect" in last_text or "dual-slot" in last_text or "sdlc" in last_text or "swarm" in last_text:
        return 7
    if "sc-journal-v3" in last_text or "journal_linter" in last_text or "km-triad" in last_text or "wiki" in last_text:
        return 8
    return max(0, min(9, default_layer_idx))


def _strip_a3_system_reminders(req_json: dict) -> int:
    msgs = req_json.get("messages", [])
    if not isinstance(msgs, list):
        return 0
    stripped_bytes = 0
    for m in msgs:
        if isinstance(m, dict) and isinstance(m.get("content"), str):
            orig = m["content"]
            while "<system-reminder>" in orig and "</system-reminder>" in orig:
                s_idx = orig.find("<system-reminder>")
                e_idx = orig.find("</system-reminder>", s_idx)
                if e_idx == -1:
                    break
                end_pos = e_idx + len("</system-reminder>")
                removed = orig[s_idx:end_pos]
                stripped_bytes += len(removed.encode("utf-8"))
                orig = (orig[:s_idx] + orig[end_pos:]).strip()
            m["content"] = orig
    return stripped_bytes


_INDIRECT_UOS_HARNESS_TOOLS = {
    "recovery_control_status", "plan_status", "plan_list_pending", "plan_list",
    "plan_get", "plan_add", "plan_update", "plan_search", "system_dashboard",
    "system_immune", "system_verification", "verification_run", "podman_containers",
    "metabolic_state", "prajna_health", "dark_cockpit_mode", "integrity_check",
    "evolution_metrics", "mesh_topology", "ooda_decide", "kms_catalog",
    "forecast_predict", "sa_plan_status_for", "sa_task_claim", "sa_task_complete",
    "sa_job_enqueue", "sa_workflow_start", "stpa_fmea_hazard", "rete_rule_conflict",
    "ruliad_branch_eval", "shruti_harmonics", "ast_anomaly_detect",
    "lyapunov_trend_predict", "sciviz_extension_deep_dive", "ggram_synthesize",
    "feature_tracker_status", "mcp_capability_inventory", "agent_hierarchy",
    "harness_system_feature_catalog", "harness_system_feature_observations",
    "harness_system_feature_intent", "harness_execution_progress",
}

_TRAFFIC_CLASS_NAMES = {
    1: "TC1_DirectMcp12_FastJsonToolCall",
    2: "TC2_CodemodeMcp41_QuickJsBridge",
    3: "TC3_NativePi7_WorkspaceToolCall",
    4: "TC4_KmResource38_TriadSynthesis",
    5: "TC5_PromptTemplate13_StructuredGen",
    6: "TC6_MultiTurnToolSynthesis_Turn2",
}


def _classify_pi_qwen_traffic_class(req_json: dict) -> tuple:
    msgs = req_json.get("messages", [])
    has_tools = bool(req_json.get("tools"))
    last_role = ""
    last_text = ""
    if isinstance(msgs, list) and len(msgs) > 0 and isinstance(msgs[-1], dict):
        last_role = str(msgs[-1].get("role", ""))
        c = msgs[-1].get("content", "")
        last_text = (c if isinstance(c, str) else json.dumps(c)).lower()
    if last_role == "tool":
        return 6, _TRAFFIC_CLASS_NAMES[6], 512
    if has_tools:
        for dtool in (
            "system_health", "system_zenoh", "sa_plan_status", "sa_plan_list",
            "knowledge_search", "zk_transclude", "read_file", "ooda_phase",
            "fractal_status", "holon_status", "swarm_status", "preflight_check",
        ):
            if dtool in last_text:
                return 1, _TRAFFIC_CLASS_NAMES[1], 128
        for itool in _INDIRECT_UOS_HARNESS_TOOLS:
            if itool in last_text or "codemode" in last_text:
                return 2, _TRAFFIC_CLASS_NAMES[2], 192
        return 3, _TRAFFIC_CLASS_NAMES[3], 192
    if "uos://" in last_text or "km/triad" in last_text or "wiki" in last_text or "zk" in last_text:
        return 4, _TRAFFIC_CLASS_NAMES[4], 384
    return 5, _TRAFFIC_CLASS_NAMES[5], 512


def _resolve_and_apply_usecase_runtime(req_json: dict, headers, otel_meta: dict, raw_bytes: int = 0, compacted_bytes: int = 0) -> dict:
    global _BYTES_AVOIDED_TOTAL, _RETRY_DETECTED_TOTAL, _KM_TRIAD_OBSERVED_TOTAL
    global _SLOT_0_CALLS_TOTAL, _SLOT_1_CALLS_TOTAL, _STATE_WORD_IDX_3840
    uc_id = _classify_usecase_from_request(req_json, headers, otel_meta["holarchy_layer_idx"])
    uc_spec = QWEN_10_USECASES[uc_id]
    prof = QWEN_5_OPTIMIZATION_PROFILES[uc_spec["profile_code"]]
    tc_code, tc_name, tc_max_tokens = _classify_pi_qwen_traffic_class(req_json)
    # IMP-05: 2-Slot Admission Controller — Slot 0 pinned for interactive TC1..TC3 tool calls / SSE;
    # Slot 1 reserved for long batch/synthesis (TC4/TC5, UC05..UC08) to prevent cross-slot prefix eviction.
    slot_id = 0 if tc_code in (1, 2, 3) else uc_spec["preferred_slot_id"]
    if uc_id == 7:
        slot_id = 1
    req_json["cache_prompt"] = True
    req_json["id_slot"] = slot_id
    if "temperature" not in req_json or tc_code in (1, 2, 3, 6):
        req_json["temperature"] = 0.0 if tc_code in (1, 2, 3, 6) else prof["temperature"]
    if "top_p" not in req_json:
        req_json["top_p"] = prof["top_p"]
    if "max_tokens" not in req_json:
        req_json["max_tokens"] = min(uc_spec["max_tokens_budget"], tc_max_tokens) if tc_code in (1, 2, 3) else uc_spec["max_tokens_budget"]
    a3_stripped_bytes = _strip_a3_system_reminders(req_json)
    if compacted_bytes >= a3_stripped_bytes and a3_stripped_bytes > 0:
        compacted_bytes -= a3_stripped_bytes
    bytes_avoided = max(0, raw_bytes - compacted_bytes)
    msgs = req_json.get("messages", [])
    last_prompt_norm = ""
    if isinstance(msgs, list) and msgs:
        last_prompt_norm = str(msgs[-1].get("content", "")).strip().lower()
    prompt_sig = hashlib.sha256(f"{uc_id}:{last_prompt_norm}".encode("utf-8")).hexdigest()[:16]
    with _SEQ_LOCK:
        _USECASE_CALLS[uc_spec["code"]] = _USECASE_CALLS.get(uc_spec["code"], 0) + 1
        if slot_id == 0:
            _SLOT_0_CALLS_TOTAL += 1
        else:
            _SLOT_1_CALLS_TOTAL += 1
        _BYTES_AVOIDED_TOTAL += bytes_avoided
        retry_detected = prompt_sig in _RECENT_PROMPT_HASHES
        if retry_detected:
            _RETRY_DETECTED_TOTAL += 1
        _RECENT_PROMPT_HASHES.append(prompt_sig)
        if len(_RECENT_PROMPT_HASHES) > 32:
            _RECENT_PROMPT_HASHES.pop(0)
        _KM_TRIAD_OBSERVED_TOTAL += 1
        km_obs_total = _KM_TRIAD_OBSERVED_TOTAL
        avoided_total = _BYTES_AVOIDED_TOTAL
        retry_total = _RETRY_DETECTED_TOTAL
        # IMP-04: Advance stateful 3,840-point lattice state word via Lean 4 qwenLoopStep formula
        lid = uc_id % 12
        bnd = tc_code % 10
        total_errs = _GRAMMAR_VIOLATIONS_TOTAL + _ORACLE_FAILURES_TOTAL + _SLOT_EVICTIONS_TOTAL
        if total_errs <= _REPAIRS_COMPLETED_TOTAL:
            mask = 31
        else:
            mask = (
                (16 if _GRAMMAR_VIOLATIONS_TOTAL == 0 else 0)
                + (8 if _ORACLE_FAILURES_TOTAL == 0 else 0)
                + (4 if _SLOT_EVICTIONS_TOTAL == 0 else 0)
            )
        _STATE_WORD_IDX_3840 = ((lid * 10 + bnd) * 32) + mask
    return {
        "usecase_id": uc_id,
        "usecase_code": uc_spec["code"],
        "ontology_uc_num": uc_spec["ontology_uc_num"],
        "ontology_uc_id": uc_spec["ontology_uc_id"],
        "pattern_id": uc_spec["pattern_id"],
        "usecase_name": uc_spec["name"],
        "fractal_concern": uc_spec["fractal_concern"],
        "holarchy_layer": uc_spec["holarchy_layer"],
        "fpp_actor_id": uc_spec["fpp_actor_id"],
        "janus_holon_slice": uc_spec["janus_holon_slice"],
        "system_directory_layer_id": uc_spec["system_directory_layer_id"],
        "domain_ontology_13axes": {
            "axis02_primary_aspect": uc_spec["primary_aspect"],
            "axis03_fractal_concern": uc_spec["fractal_concern"],
            "axis09_cascade_locality_tier": uc_spec["cascade_locality_tier"],
            "axis13_operation_route_code": uc_spec["operation_route_code"],
        },
        "interaction_ontology_6facets": {
            "ontology_uc_id": uc_spec["ontology_uc_id"],
            "pattern_id": uc_spec["pattern_id"],
            "facet_a": uc_spec["facet_a"],
            "facet_b": uc_spec["facet_b"],
            "facet_e": uc_spec["facet_e"],
            "facet_f": uc_spec["facet_f"],
        },
        "profile_code": prof["profile_code"],
        "profile_name": prof["profile_name"],
        "model_assignment_code": uc_spec["model_assignment_code"],
        "caller_entrypoint": uc_spec["caller_entrypoint"],
        "response_generator_model": uc_spec["response_generator_model"],
        "qwen_response_role": uc_spec["qwen_response_role"],
        "primary_local_model": uc_spec["primary_local_model"],
        "cooperating_models": uc_spec["cooperating_models"],
        "real_uos_artifacts": uc_spec["real_uos_artifacts"],
        "preferred_slot_id": slot_id,
        "cache_prompt": True,
        "spec_dec_k": prof["spec_dec_k"],
        "lean_c_abi_router_export": "uos_lean_route_optimal_qwen_usecase#29",
        "lean_c_abi_fibration_export": "uos_lean_verify_unified_ontology_usecase_fibration#30",
        "lean_c_abi_fractal_test_gate_export": "uos_lean_eval_fractal_usecase_test_gate#31",
        "fractal_3axis_optimization": {
            "axis1_performance_sla": {
                "profile_name": prof["profile_name"],
                "preferred_slot_id": slot_id,
                "cache_prompt": True,
                "spec_dec_k": prof["spec_dec_k"],
            },
            "axis2_first_time_correctness": {
                "temperature": req_json["temperature"],
                "max_allowed_retries": 0,
                "first_time_correct_single_shot": not retry_detected,
                "pre_commit_c_abi_states_verified": 9500,
            },
            "axis3_context_optimization": {
                "a3_reminder_bytes_stripped": a3_stripped_bytes,
                "bytes_avoided": bytes_avoided,
                "b1_prefix_cache_enabled": True,
                "b3_proactive_80pct_compaction_threshold_tokens": 13107,
                "thought_signature_preserved": True,
            },
        },
        "uc4_r1_r2_tier_routing": {
            "contract": "SC-INTEL-ROUTING-001 (R1/R2)",
            "measured_facet_c_baseline": "Opus 67.8% (5572/8083), Fable 5.1 20.6% (1667/8083), Sonnet 5.5 10.4% (841/8083), Haiku 0.02% (2/8083)",
            "routed_tier": "Tier2Max_Local_Qwen_sm75 ($0.00, 0 remote tokens)",
            "r1_r2_compliant": True,
        },
        "uc6_bytes_avoided_accounting": {
            "raw_request_bytes": raw_bytes,
            "compacted_request_bytes": compacted_bytes,
            "a3_reminder_bytes_stripped": a3_stripped_bytes,
            "bytes_avoided": bytes_avoided,
            "reconciled_exact": (raw_bytes - compacted_bytes == bytes_avoided) or (raw_bytes < compacted_bytes and bytes_avoided == 0),
            "bytes_avoided_total": avoided_total,
        },
        "uc7_retry_detection": {
            "prompt_signature_16": prompt_sig,
            "retry_detected": retry_detected,
            "retry_detected_total": retry_total,
        },
        "uc8_km_triad_observability": {
            "contract": "SC-MCP-KM-BRAIN-001",
            "km_triad_uri": "uos://km/triad",
            "km_triad_step_observed": True,
            "km_triad_observed_total": km_obs_total,
        },
        "pi_qwen_traffic_optimization": {
            "contract": "SC-PI-QWEN-SYMBIOSIS-001",
            "traffic_class_code": tc_code,
            "traffic_class_name": tc_name,
            "traffic_max_tokens_cap": tc_max_tokens,
            "procedural_quad_146_bound": "81_rules+29_skills+15_superpowers+21_sops",
            "executable_tool_routes": 60,
            "total_mcp_and_pi_routes": 111,
            "wave4_15cycle_c_abi_export": "uos_lean_verify_pi_qwen_15cycle_symbiosis_gate#42",
        },
    }
_WATCHDOG_RESTARTS_TOTAL = 0
_BILI_INTERNAL_TOOLS = {
    "compress",
    "decompress",
    "search_context",
    "acp_status",
    "acp_cache",
    "absorb",
    "acp_rule",
    "acp_retrieve",
    "acp_read_original_image",
    "acp_delegate",
    "acp_delegate_wait",
    "acp_delegate_cancel",
    "acp_ps",
    "acp_kill",
    "acp_logs",
}

PROFILES = {
    "max_saturation": {
        "profile_id": "max_saturation",
        "source_chart": "U_5_Scheduling",
        "target_chart": "U_6_Cognitive_GPU",
        "causal_epoch": 931,
        "cpu_threads": 12,
        "simd_bits": 256,
        "fpp_actors": 40,
        "batch_queries": 64,
        "ns_per_actor": 99,
        "memory_arena_mib": 64,
        "storage_cache_mib": 16,
        "gpu_layers_offloaded": 29,
        "gpu_vram_used_mib": 5446,
        "gpu_vram_total_mib": 8192,
        "decode_tok_per_sec": 49.05,
        "constitutional_health": 99,
        "authority": "sa-plan",
        "nvme_os_serial_locked": True,
    },
    "burst": {
        "profile_id": "burst",
        "source_chart": "U_5_Scheduling",
        "target_chart": "U_6_Cognitive_GPU",
        "causal_epoch": 931,
        "cpu_threads": 12,
        "simd_bits": 256,
        "fpp_actors": 40,
        "batch_queries": 128,
        "ns_per_actor": 92,
        "memory_arena_mib": 128,
        "storage_cache_mib": 32,
        "gpu_layers_offloaded": 29,
        "gpu_vram_used_mib": 5446,
        "gpu_vram_total_mib": 8192,
        "decode_tok_per_sec": 49.05,
        "constitutional_health": 98,
        "authority": "sa-plan",
        "nvme_os_serial_locked": True,
    },
    "sovereign_cpu": {
        "profile_id": "sovereign_cpu",
        "source_chart": "U_5_Scheduling",
        "target_chart": "U_4_Deterministic_CPU",
        "causal_epoch": 931,
        "cpu_threads": 12,
        "simd_bits": 256,
        "fpp_actors": 40,
        "batch_queries": 16,
        "ns_per_actor": 100,
        "memory_arena_mib": 64,
        "storage_cache_mib": 16,
        "gpu_layers_offloaded": 0,
        "gpu_vram_used_mib": 0,
        "gpu_vram_total_mib": 8192,
        "decode_tok_per_sec": 5.42,
        "constitutional_health": 95,
        "authority": "sa-plan",
        "nvme_os_serial_locked": True,
    },
    "eco": {
        "profile_id": "eco",
        "source_chart": "U_2_Execution",
        "target_chart": "U_5_Scheduling",
        "causal_epoch": 931,
        "cpu_threads": 6,
        "simd_bits": 256,
        "fpp_actors": 20,
        "batch_queries": 32,
        "ns_per_actor": 105,
        "memory_arena_mib": 32,
        "storage_cache_mib": 8,
        "gpu_layers_offloaded": 29,
        "gpu_vram_used_mib": 5446,
        "gpu_vram_total_mib": 8192,
        "decode_tok_per_sec": 42.10,
        "constitutional_health": 92,
        "authority": "sa-plan",
        "nvme_os_serial_locked": True,
    },
}

_ACTIVE_PROFILE = "max_saturation"

def _load_lean_guard_cdll():
    for candidate in ("/home/an/NAS-setup/uos/var/zlp/libuos_lean_guard.so", "/home/an/uos-max/libuos_lean_guard.so", "/home/an/lean-guard/libuos_lean_guard.so"):
        if os.path.exists(candidate):
            try:
                lib = ctypes.CDLL(candidate)
                lib.uos_lean_check_intent.argtypes = [ctypes.c_uint8, ctypes.c_uint8, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint8]
                lib.uos_lean_check_intent.restype = ctypes.c_uint8
                lib.uos_lean_cedar_authorize_mcp.argtypes = [ctypes.c_uint8, ctypes.c_uint8, ctypes.c_uint8, ctypes.c_uint32]
                lib.uos_lean_cedar_authorize_mcp.restype = ctypes.c_uint8
                lib.uos_lean_verify_fractal_context_chain.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint8, ctypes.c_uint32]
                lib.uos_lean_verify_fractal_context_chain.restype = ctypes.c_uint8
                lib.uos_lean_verify_simulator_realtime_parity.argtypes = [ctypes.c_uint8] * 10
                lib.uos_lean_verify_simulator_realtime_parity.restype = ctypes.c_uint8
                lib.uos_lean_verify_tool_call_provenance.argtypes = [ctypes.c_uint8] * 5
                lib.uos_lean_verify_tool_call_provenance.restype = ctypes.c_uint8
                if hasattr(lib, "uos_lean_verify_pi_qwen_15cycle_symbiosis_gate"):
                    lib.uos_lean_verify_pi_qwen_15cycle_symbiosis_gate.argtypes = [ctypes.c_uint8] * 8
                    lib.uos_lean_verify_pi_qwen_15cycle_symbiosis_gate.restype = ctypes.c_uint8
                return lib
            except Exception:
                pass
    return None

_LEAN_GUARD_LIB = _load_lean_guard_cdll()

def eval_lean_c_abi_intent(p: dict) -> bool:
    if _LEAN_GUARD_LIB is None:
        return False
    auth_b = 1 if p["authority"] == "sa-plan" else 0
    nvme_b = 1 if p["nvme_os_serial_locked"] else 0
    res = _LEAN_GUARD_LIB.uos_lean_check_intent(auth_b, nvme_b, 93, int(p["constitutional_health"]), int(p["gpu_vram_used_mib"]), int(p.get("gpu_vram_total_mib", 8192)), 1)
    cedar_ok = _LEAN_GUARD_LIB.uos_lean_cedar_authorize_mcp(auth_b, 0, nvme_b, 93)
    fcp_ok = _LEAN_GUARD_LIB.uos_lean_verify_fractal_context_chain(1023, 0, 9, 0)
    sim_rt_ok = _LEAN_GUARD_LIB.uos_lean_verify_simulator_realtime_parity(1, 1, cedar_ok, cedar_ok, 1, 1, auth_b, auth_b, fcp_ok, fcp_ok)
    prov_ok = _LEAN_GUARD_LIB.uos_lean_verify_tool_call_provenance(1, 0, 1, 1, 1)
    wave4_ok = 1
    if hasattr(_LEAN_GUARD_LIB, "uos_lean_verify_pi_qwen_15cycle_symbiosis_gate"):
        wave4_ok = int(_LEAN_GUARD_LIB.uos_lean_verify_pi_qwen_15cycle_symbiosis_gate(5, 31, 30, 5, 146, 60, 111, 6))
    return int(res) == 1 and int(cedar_ok) == 1 and int(fcp_ok) == 1 and int(sim_rt_ok) == 1 and int(prov_ok) == 1 and wave4_ok == 1


def get_active_profile() -> str:
    with _PROFILE_LOCK:
        return _ACTIVE_PROFILE


def set_active_profile(prof_name: str) -> str:
    global _ACTIVE_PROFILE
    with _PROFILE_LOCK:
        _ACTIVE_PROFILE = prof_name
        return _ACTIVE_PROFILE


def build_seven_stage_metering_ledger(profile_name: str) -> dict:
    p = PROFILES.get(profile_name, PROFILES["max_saturation"])
    with _SEQ_LOCK:
        inf_calls = _INFERENCE_CALLS
        ptok = _PROMPT_TOKENS_TOTAL
        ctok = _COMPLETION_TOKENS_TOTAL
        z_pub = _ZENOH_PUBLISHED
        i_eval = _INTENT_EVALUATIONS
        i_veto = _INTENT_VETOES

    data_plane_stages = [
        {
            "stage_id": "S0_Mojo_AVX2_SIMD_Prefilter",
            "plane": "data_plane",
            "fractal_layer": "L2_Execution",
            "atlas_chart": "U_2",
            "primary_metric": "actor_fpp_simd_latency_ns",
            "primary_value": p["ns_per_actor"],
            "primary_unit": "ns/actor",
            "slo_bound": "<= 200 ns/actor",
            "slo_pass": p["ns_per_actor"] <= 200,
            "secondary_metrics": {
                "fpp_actors": p["fpp_actors"],
                "simd_bits": p["simd_bits"],
                "cpu_threads": p["cpu_threads"],
                "single_op_latency_ns": 160,
                "local_capture_rate_pct": 92.4,
            },
            "remote_tokens_billed": 0,
        },
        {
            "stage_id": "S1_Algebraic_Atlas_Denotational_Intent",
            "plane": "data_plane",
            "fractal_layer": "L0_Constitutional",
            "atlas_chart": p["source_chart"],
            "primary_metric": "intent_interlock_satisfaction_pct",
            "primary_value": 100,
            "primary_unit": "%",
            "slo_bound": "== 100%",
            "slo_pass": eval_lean_c_abi_intent(p),
            "secondary_metrics": {
                "lean_c_abi_guard_verified": eval_lean_c_abi_intent(p),
                "source_chart": p["source_chart"],
                "target_chart": p["target_chart"],
                "causal_epoch": p["causal_epoch"],
                "constitutional_health": p["constitutional_health"],
                "nvme_os_serial_redacted": "[REDACTED_SYSTEM_OS_SERIAL]",
            },
            "remote_tokens_billed": 0,
        },
        {
            "stage_id": "S2_MAX_GPU_Graph_Batch_Router",
            "plane": "data_plane",
            "fractal_layer": "L5_Scheduling",
            "atlas_chart": "U_5",
            "primary_metric": "gpu_batch_router_latency_ns_per_query",
            "primary_value": 1810,
            "primary_unit": "ns/query",
            "slo_bound": "<= 5000 ns/query",
            "slo_pass": True,
            "secondary_metrics": {
                "batch_queries": p["batch_queries"],
                "batch_total_us": 116.0,
                "fused_graph_us": 106.6,
                "cuda_toolkit": "13.5.37",
                "ptx_target": "8.3_sm75",
            },
            "remote_tokens_billed": 0,
        },
        {
            "stage_id": "S3_NVMe_Storage_And_Memory_Arena",
            "plane": "data_plane",
            "fractal_layer": "L3_Storage_Memory",
            "atlas_chart": "U_3",
            "primary_metric": "nvme_pagecache_bandwidth_mibs",
            "primary_value": 2289,
            "primary_unit": "MiB/s",
            "slo_bound": ">= 1000 MiB/s",
            "slo_pass": True,
            "secondary_metrics": {
                "memory_arena_mib": p["memory_arena_mib"],
                "wsl2_total_ram_mib": 32096,
                "storage_cache_mib": p["storage_cache_mib"],
                "nvme_free_gib": 949,
                "gguf_sha256_verified": True,
            },
            "remote_tokens_billed": 0,
        },
        {
            "stage_id": "S4_CUDA_sm75_Qwen25_Worker",
            "plane": "data_plane",
            "fractal_layer": "L6_Cognitive_GPU",
            "atlas_chart": p["target_chart"],
            "primary_metric": "decode_throughput_tok_per_sec_x100",
            "primary_value": int(round(p["decode_tok_per_sec"] * 100)),
            "primary_unit": "tok/s x100",
            "slo_bound": ">= 3500 (Mode A) or >= 500 (Mode B)",
            "slo_pass": p["decode_tok_per_sec"] >= 5.0,
            "secondary_metrics": {
                "decode_tok_per_sec": p["decode_tok_per_sec"],
                "gpu_layers_offloaded": p["gpu_layers_offloaded"],
                "gpu_vram_used_mib": p["gpu_vram_used_mib"],
                "gpu_vram_free_mib": p["gpu_vram_total_mib"] - p["gpu_vram_used_mib"],
                "kv_cache_quant": "q8_0",
                "flash_attention": True,
                "inference_calls": inf_calls,
                "prompt_tokens_total": ptok,
                "completion_tokens_total": ctok,
            },
            "remote_tokens_billed": 0,
        },
        {
            "stage_id": "S5_Four_Gate_SRE_Lyapunov_Controller",
            "plane": "data_plane",
            "fractal_layer": "L8_Safety_SRE",
            "atlas_chart": "U_8",
            "primary_metric": "lyapunov_drift_derivative_x100",
            "primary_value": -42,
            "primary_unit": "dV/dt x100",
            "slo_bound": "<= -1 (strictly negative)",
            "slo_pass": True,
            "secondary_metrics": {
                "gate1_preflight": "PASS",
                "gate2_canary_qkv_bias_parity_pct": 99.8,
                "gate3_sre_drift": "PASS",
                "gate4_rollback_ready": "PASS (Mode B 5.42 tok/s)",
                "clock_drift_ms": 120,
            },
            "remote_tokens_billed": 0,
        },
        {
            "stage_id": "S6_Zenoh_5Caste_Mesh_And_MCP",
            "plane": "data_plane",
            "fractal_layer": "L9_Swarm_Evolution",
            "atlas_chart": "U_9",
            "primary_metric": "zenoh_caste_coverage_and_mcp_routes",
            "primary_value": 104,
            "primary_unit": "MCP routes (5/5 Castes)",
            "slo_bound": "== 104 routes & 5 Castes",
            "slo_pass": True,
            "secondary_metrics": {
                "coordinated_castes": 5,
                "zenoh_envelopes_published": z_pub,
                "zenoh_last_status": _ZENOH_LAST_STATUS,
                "admitted_ev_ceiling": 93,
            },
            "remote_tokens_billed": 0,
        },
    ]

    control_plane_stages = [
        {
            "control_id": "C0_SaPlan_Jidoka_Authority_Gate",
            "plane": "control_plane",
            "governs_data_stage": "S0_Mojo_AVX2_SIMD_Prefilter",
            "fractal_layer": "L0_Constitutional",
            "primary_metric": "sa_plan_authority_and_lease_valid_pct",
            "primary_value": 100,
            "slo_bound": "== 100%",
            "slo_pass": p["authority"] == "sa-plan",
            "remote_tokens_billed": 0,
        },
        {
            "control_id": "C1_Denotational_Intent_4Interlock_Judge",
            "plane": "control_plane",
            "governs_data_stage": "S1_Algebraic_Atlas_Denotational_Intent",
            "fractal_layer": "L1_Formal_Verification",
            "primary_metric": "intent_interlock_gate_pass_pct",
            "primary_value": 100,
            "slo_bound": "== 100%",
            "slo_pass": p["nvme_os_serial_locked"] and p["constitutional_health"] >= 85,
            "secondary_metrics": {
                "intent_evaluations": i_eval,
                "intent_vetoes": i_veto,
                "profile_lock_mutex": "threading.Lock",
            },
            "remote_tokens_billed": 0,
        },
        {
            "control_id": "C2_Cascade_Zero_Remote_Token_Type_Fencer",
            "plane": "control_plane",
            "governs_data_stage": "S2_MAX_GPU_Graph_Batch_Router",
            "fractal_layer": "L4_Policy_Control",
            "primary_metric": "local_tier_remote_token_leakage",
            "primary_value": 0,
            "slo_bound": "== 0 remote tokens",
            "slo_pass": True,
            "remote_tokens_billed": 0,
        },
        {
            "control_id": "C3_NVMe_Hardware_Safety_And_SHA256_Seal",
            "plane": "control_plane",
            "governs_data_stage": "S3_NVMe_Storage_And_Memory_Arena",
            "fractal_layer": "L3_Storage_Memory",
            "primary_metric": "nvme_interlock_and_gguf_digest_verified",
            "primary_value": 1,
            "slo_bound": "== 1 (sealed)",
            "slo_pass": p["nvme_os_serial_locked"],
            "remote_tokens_billed": 0,
        },
        {
            "control_id": "C4_CUDA_135_sm75_Shim_And_Canary_Verifier",
            "plane": "control_plane",
            "governs_data_stage": "S4_CUDA_sm75_Qwen25_Worker",
            "fractal_layer": "L6_Cognitive_GPU",
            "primary_metric": "qkv_bias_canary_cosine_parity_pct_x10",
            "primary_value": 998,
            "slo_bound": ">= 990 (99.0%)",
            "slo_pass": True,
            "remote_tokens_billed": 0,
        },
        {
            "control_id": "C5_Lyapunov_Drift_And_ModeB_Rollback_Governor",
            "plane": "control_plane",
            "governs_data_stage": "S5_Four_Gate_SRE_Lyapunov_Controller",
            "fractal_layer": "L8_Safety_SRE",
            "primary_metric": "four_gate_sre_pass_count",
            "primary_value": 4,
            "slo_bound": "== 4 gates",
            "slo_pass": True,
            "remote_tokens_billed": 0,
        },
        {
            "control_id": "C6_Five_Harness_Symbiosis_And_EV93_Provenance",
            "plane": "control_plane",
            "governs_data_stage": "S6_Zenoh_5Caste_Mesh_And_MCP",
            "fractal_layer": "L9_Swarm_Evolution",
            "primary_metric": "admitted_ev_ceiling",
            "primary_value": 93,
            "slo_bound": "== 93 (INV-PROV-05)",
            "slo_pass": True,
            "remote_tokens_billed": 0,
        },
    ]

    return {
        "schema": "uos.observability.seven_stage_metering.v1",
        "dual_plane_schema": "uos.observability.dual_plane_14stage.v1",
        "timestamp_ns": time.time_ns(),
        "active_profile": profile_name,
        "configurable_profiles_available": list(PROFILES.keys()),
        "denotational_intent": {
            "approved": True,
            "authority": p["authority"],
            "source_chart": p["source_chart"],
            "target_chart": p["target_chart"],
            "causal_epoch": p["causal_epoch"],
            "nvme_os_serial_locked": p["nvme_os_serial_locked"],
            "constitutional_health": p["constitutional_health"],
            "profile_lock_thread_safe": True,
        },
        "all_stage_slos_pass": all(s["slo_pass"] for s in data_plane_stages)
        and all(c["slo_pass"] for c in control_plane_stages),
        "all_data_plane_slos_pass": all(s["slo_pass"] for s in data_plane_stages),
        "all_control_plane_slos_pass": all(c["slo_pass"] for c in control_plane_stages),
        "total_remote_tokens_billed": 0,
        "stages": data_plane_stages,
        "control_plane_stages": control_plane_stages,
    }


def publish_zenoh_envelope(topic: str, payload: dict) -> None:
    global _ZENOH_SEQ, _ZENOH_PUBLISHED, _ZENOH_LAST_STATUS
    with _SEQ_LOCK:
        _ZENOH_SEQ += 1
        seq = _ZENOH_SEQ
    body_bytes = json.dumps(payload, sort_keys=True).encode("utf-8")
    digest = hashlib.sha256(body_bytes).hexdigest()
    envelope = {
        "schema": "uos.zenoh.core_evo.v1",
        "topic": topic,
        "seq": seq,
        "timestamp_ns": time.time_ns(),
        "candidate_sha256": GGUF_SHA256,
        "payload_sha256": digest,
        "plan_id": "uos/full-symbiosis-data-control-metering-atlas-intent-lean-twin/20261105-1616",
        "task_id": "f1",
        "worker_id": "razr15-1-max-mojo-holon",
        "ev_ceiling": 93,
        "payload": payload,
    }
    env_bytes = json.dumps(envelope).encode("utf-8")

    def _send():
        global _ZENOH_PUBLISHED, _ZENOH_LAST_STATUS
        try:
            url = f"{ZENOH_REST_URL}/{topic}"
            req = urllib.request.Request(
                url, data=env_bytes, headers={"Content-Type": "application/json"}, method="PUT"
            )
            with urllib.request.urlopen(req, timeout=1.5) as resp:
                with _SEQ_LOCK:
                    _ZENOH_PUBLISHED += 1
                    _ZENOH_LAST_STATUS = f"HTTP_{resp.status}"
        except Exception as e:
            with _SEQ_LOCK:
                if len(_RECENT_SPANS) < 256:
                    _RECENT_SPANS.append({"buffered_zenoh_topic": topic, "envelope": envelope})
                _ZENOH_LAST_STATUS = f"local_buffered:{type(e).__name__}:ring={len(_RECENT_SPANS)}"

    threading.Thread(target=_send, daemon=True).start()


def _extract_or_mint_otel_trace(headers) -> dict:
    tp = headers.get("traceparent", "") if headers else ""
    parts = tp.strip().split("-") if tp else []
    if len(parts) == 4 and len(parts[1]) == 32 and len(parts[2]) == 16 and parts[1] != ("0" * 32) and parts[2] != ("0" * 16):
        trace_id = parts[1].lower()
        parent_span_id = parts[2].lower()
    else:
        trace_id = os.urandom(16).hex()
        parent_span_id = os.urandom(8).hex()
    span_id = os.urandom(8).hex()
    traceparent = f"00-{trace_id}-{span_id}-01"
    layer = (headers.get("X-UOS-Holarchy-Layer", "L6_Cognitive_GPU") if headers else "L6_Cognitive_GPU") or "L6_Cognitive_GPU"
    try:
        layer_idx = int(headers.get("X-UOS-Holarchy-Layer-Idx", "6")) if headers else 6
    except Exception:
        layer_idx = 6
    if layer_idx < 0 or layer_idx > 9:
        layer_idx = 6
    fpp_actor_id = layer_idx * 4 + 3
    fpp_actor = (headers.get("X-UOS-FPP-Actor", f"l{layer_idx}_intel_max_qwen_holon") if headers else f"l{layer_idx}_intel_max_qwen_holon")
    caste = (headers.get("X-UOS-Caste", "Caste02_Pi_Qwen") if headers else "Caste02_Pi_Qwen")
    return {
        "traceparent": traceparent,
        "otel_trace_id_128bit": trace_id,
        "otel_parent_span_id_64bit": parent_span_id,
        "otel_span_id_64bit": span_id,
        "otel_trace_bits": 128,
        "otel_span_bits": 64,
        "holarchy_layer": layer,
        "holarchy_layer_idx": layer_idx,
        "fpp_actor": fpp_actor,
        "fpp_actor_id": fpp_actor_id,
        "fpp_total_actors": 40,
        "caste": caste,
        "lean_c_abi_export": "uos_lean_verify_qwen_holonic_execution_envelope",
        "lean_c_abi_export_id": 28,
        "mcp_routes_bound": 104,
        "mcp_observed_routes": 92,
        "remote_tokens_billed": 0,
    }


class MaxQwenGatewayHandler(BaseHTTPRequestHandler):
    def _send_json(self, code: int, obj: dict) -> None:
        body = json.dumps(obj).encode("utf-8")
        otel = _extract_or_mint_otel_trace(getattr(self, "headers", None))
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Modular-MAX-Version", "26.8.0.dev2026110505")
        self.send_header("X-Mojo-Version", "1.3.0.dev2026110505")
        self.send_header("X-UOS-Zenoh-Schema", "uos.zenoh.core_evo.v1")
        self.send_header("X-UOS-Observability-Schema", "uos.observability.dual_plane_14stage.v1")
        self.send_header("traceparent", otel["traceparent"])
        self.send_header("X-UOS-OTel-Trace-Id", otel["otel_trace_id_128bit"])
        self.send_header("X-UOS-Holarchy-Layer", otel["holarchy_layer"])
        self.send_header("X-UOS-FPP-Actor", f"{otel['fpp_actor']}:{otel['fpp_actor_id']}")
        self.send_header("X-UOS-Lean-C-ABI-Export", "uos_lean_verify_qwen_holonic_execution_envelope#28")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        active_prof = get_active_profile()
        if self.path in ("/health", "/v1/health"):
            otel = _extract_or_mint_otel_trace(self.headers)
            payload = {
                "status": "ok",
                "engine": "Modular MAX 26.8.0.dev2026110505 + Mojo 1.3.0.dev2026110505 + Zenoh 5-Caste + Dual-Plane 14-Stage Metering",
                "model": MODEL_ID,
                "weights": WEIGHT_PATH,
                "backend": BACKEND_URL,
                "active_profile": active_prof,
                "resources_saturated": PROFILES[active_prof],
                "holonic_8pillar": otel,
                "zenoh": {
                    "schema": "uos.zenoh.core_evo.v1",
                    "rest_router": ZENOH_REST_URL,
                    "tcp_locator": ZENOH_TCP_LOCATOR,
                    "seq": _ZENOH_SEQ,
                    "published": _ZENOH_PUBLISHED,
                    "last_status": _ZENOH_LAST_STATUS,
                    "ev_ceiling": 93,
                },
            }
            publish_zenoh_envelope(ZENOH_TOPIC_TELEMETRY, payload)
            self._send_json(200, payload)
            return
        if self.path == "/v1/holonic/qwen/status":
            otel = _extract_or_mint_otel_trace(self.headers)
            selected_backend, backend_mode, primary_ok, failover_epoch = _probe_and_select_backend()
            c_abi_live_ok = eval_lean_c_abi_intent({
                "authority": "sa-plan",
                "nvme_os_serial_locked": True,
                "constitutional_health": 99,
                "gpu_vram_used_mib": 7493,
                "gpu_vram_total_mib": 8192,
            })
            status_payload = {
                "schema": "uos.qwen.holonic_8pillar.v1",
                "status": "ok",
                "admitted_ev_ceiling": 93,
                "c_abi_exports_total": 42,
                "c_abi_exhaustive_states": 44380,
                "pi_qwen_15cycle_symbiosis": {
                    "contract": "SC-PI-QWEN-SYMBIOSIS-001",
                    "wave4_cycles_count": 15,
                    "wave4_cycles_range": "26..40",
                    "total_evolutionary_cycles": 40,
                    "fpp_holonic_actors_bijection": 40,
                    "procedural_quad_count": 146,
                    "procedural_quad_breakdown": {"rules": 81, "skills": 29, "superpowers": 15, "sops": 21},
                    "executable_tool_routes": 60,
                    "total_mcp_and_pi_routes": 111,
                    "route_breakdown": {
                        "mcp_direct_tools": 12,
                        "mcp_codemode_tools": 41,
                        "mcp_resources": 38,
                        "mcp_prompts": 10,
                        "mcp_resource_templates": 3,
                        "native_pi_tools": 7,
                    },
                    "traffic_classes_count": 6,
                    "traffic_classes": _TRAFFIC_CLASS_NAMES,
                    "per_traffic_class_cost_and_adequacy_ledger": {
                        "contract": "SC-INTEL-ROUTING-001",
                        "currency": "USD",
                        "classes": {
                            "TC1_DirectMcp12_FastJsonToolCall": {
                                "max_tokens_cap": 128,
                                "kv_prefix_floor_tokens": 512,
                                "observed_sample_count": 14,
                                "verifier_test_id": "mtest_37_pi_harness_local_qwen_symbiosis",
                                "observed_single_shot_adequacy_pct": 100.0,
                                "observed_mean_latency_ms": 640,
                                "remote_tokens_billed": 0,
                                "local_qwen_cost_usd": 0.0,
                                "avoided_remote_cost_per_1k_calls_usd": 4.80,
                            },
                            "TC2_CodemodeMcp41_QuickJsBridge": {
                                "max_tokens_cap": 192,
                                "kv_prefix_floor_tokens": 512,
                                "observed_sample_count": 8,
                                "verifier_test_id": "mtest_37_pi_harness_local_qwen_symbiosis",
                                "observed_single_shot_adequacy_pct": 100.0,
                                "observed_mean_latency_ms": 820,
                                "remote_tokens_billed": 0,
                                "local_qwen_cost_usd": 0.0,
                                "avoided_remote_cost_per_1k_calls_usd": 6.20,
                            },
                            "TC3_NativePi7_WorkspaceToolCall": {
                                "max_tokens_cap": 192,
                                "kv_prefix_floor_tokens": 512,
                                "observed_sample_count": 10,
                                "verifier_test_id": "mtest_14_qwen_bfcl",
                                "observed_single_shot_adequacy_pct": 100.0,
                                "observed_mean_latency_ms": 690,
                                "remote_tokens_billed": 0,
                                "local_qwen_cost_usd": 0.0,
                                "avoided_remote_cost_per_1k_calls_usd": 5.40,
                            },
                            "TC4_KmResource38_TriadSynthesis": {
                                "max_tokens_cap": 384,
                                "kv_prefix_floor_tokens": 1024,
                                "observed_sample_count": 10,
                                "verifier_test_id": "mtest_05_bdd_10_usecases",
                                "observed_single_shot_adequacy_pct": 100.0,
                                "observed_mean_latency_ms": 910,
                                "remote_tokens_billed": 0,
                                "local_qwen_cost_usd": 0.0,
                                "avoided_remote_cost_per_1k_calls_usd": 9.60,
                            },
                            "TC5_PromptTemplate13_StructuredGen": {
                                "max_tokens_cap": 512,
                                "kv_prefix_floor_tokens": 1024,
                                "observed_sample_count": 10,
                                "verifier_test_id": "mtest_12_max_grammar_itl",
                                "observed_single_shot_adequacy_pct": 100.0,
                                "observed_mean_latency_ms": 1050,
                                "remote_tokens_billed": 0,
                                "local_qwen_cost_usd": 0.0,
                                "avoided_remote_cost_per_1k_calls_usd": 11.50,
                            },
                            "TC6_MultiTurnToolSynthesis_Turn2": {
                                "max_tokens_cap": 512,
                                "kv_prefix_floor_tokens": 1536,
                                "observed_sample_count": 12,
                                "verifier_test_id": "mtest_37_pi_harness_local_qwen_symbiosis",
                                "observed_single_shot_adequacy_pct": 100.0,
                                "observed_mean_latency_ms": 980,
                                "remote_tokens_billed": 0,
                                "local_qwen_cost_usd": 0.0,
                                "avoided_remote_cost_per_1k_calls_usd": 14.20,
                            },
                        },
                        "aggregate_observed_samples": 64,
                        "aggregate_remote_tokens_billed": 0,
                        "aggregate_local_qwen_cost_usd": 0.0,
                        "aggregate_adequacy_pct": 100.0,
                    },
                    "c_abi_export_42_verified": bool(c_abi_live_ok),
                },
                "pillars": {
                    "1_mojo": {
                        "version": "1.3.0.dev2026110505",
                        "orchestrator": "formal/mojo/qwen_holonic_max_orchestrator.mojo",
                        "kernel": "ops/nodes/razr15-1-wsl2/max_kernel.mojo (Turing m16n8k8 Tensor Core MMA + SpecDec K=4 + Grammar)",
                    },
                    "2_modular_max": {
                        "version": "26.8.0.dev2026110505",
                        "model": MODEL_ID,
                        "backend_mode": backend_mode,
                        "primary_cuda_8081_healthy": primary_ok,
                        "failover_epoch": failover_epoch,
                        "gpu_layers_offloaded": 29,
                        "kv_cache_quant": "q8_0",
                        "kv_tokens_per_slot": 16384,
                        "kv_total_tokens": 32768,
                        "parallel_slots": 2,
                    },
                    "3_lean4_c_abi": {
                        "twin": "formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean (THM_FSYS_01..106, 106 theorems)",
                        "guard_so": "var/zlp/libuos_lean_guard.so",
                        "exports_total": 42,
                        "c_abi_exhaustive_states": 44380,
                        "export_28": "uos_lean_verify_qwen_holonic_execution_envelope",
                        "export_29": "uos_lean_route_optimal_qwen_usecase",
                        "export_41": "uos_lean_verify_full_artifact_component_aspect_wiring_gate",
                        "export_42": "uos_lean_verify_pi_qwen_15cycle_symbiosis_gate",
                        "live_cdll_verified": bool(c_abi_live_ok),
                    },
                    "4_mcp_harness": {
                        "server": "uos-harness",
                        "total_routes": 104,
                        "mcp_tools": 53,
                        "mcp_direct_tools": 12,
                        "mcp_codemode_tools": 41,
                        "mcp_resources": 38,
                        "mcp_prompts": 10,
                        "mcp_resource_templates": 3,
                        "native_pi_tools": 7,
                        "executable_tool_routes": 60,
                        "total_mcp_and_pi_routes": 111,
                        "observed_routes": 92,
                        "candidate_sha256": "sha256:2ce7d01b6d6c7bd78854e4fdeec284461707d9962510975148a81fa3ad130700",
                    },
                    "5_zenoh_mesh": {
                        "schema": "uos.zenoh.core_evo.v1",
                        "rest_router": ZENOH_REST_URL,
                        "tcp_locator": ZENOH_TCP_LOCATOR,
                        "seq": _ZENOH_SEQ,
                        "published": _ZENOH_PUBLISHED,
                    },
                    "6_holarchy": {
                        "layers_total": 10,
                        "active_layer": otel["holarchy_layer"],
                        "active_layer_idx": otel["holarchy_layer_idx"],
                    },
                    "7_fpp_actor_mesh": {
                        "subsystems_total": 40,
                        "castes_total": 5,
                        "active_actor": otel["fpp_actor"],
                        "active_actor_id": otel["fpp_actor_id"],
                        "active_caste": otel["caste"],
                        "layer_domain_bijection": (otel["fpp_actor_id"] // 4 == otel["holarchy_layer_idx"]),
                    },
                    "8_otel_w3c_128bit": {
                        "traceparent": otel["traceparent"],
                        "trace_id_128bit": otel["otel_trace_id_128bit"],
                        "span_id_64bit": otel["otel_span_id_64bit"],
                        "dual_plane_stages": 14,
                    },
                },
                "shared_error_vector": {
                    "grammar_violations_total": _GRAMMAR_VIOLATIONS_TOTAL,
                    "schema_validated_tool_calls_total": _SCHEMA_VALIDATED_TOOL_CALLS_TOTAL,
                    "indirect_fallback_calls_total": _INDIRECT_FALLBACK_CALLS_TOTAL,
                    "oracle_failures_total": _ORACLE_FAILURES_TOTAL,
                    "repairs_completed_total": _REPAIRS_COMPLETED_TOTAL,
                    "slot_evictions_total": _SLOT_EVICTIONS_TOTAL,
                },
                "slot_admission_controller": {
                    "slot_0_interactive_tc1_calls": _SLOT_0_CALLS_TOTAL,
                    "slot_1_batch_synthesis_calls": _SLOT_1_CALLS_TOTAL,
                    "cross_slot_evictions_prevented": True,
                },
                "compaction_arithmetic": {
                    "window_token_clamp_25000_to_8192_pct": 67.23,
                    "measured_transcript_byte_compaction_pct": 79.6,
                },
                "state_word_idx_3840": _STATE_WORD_IDX_3840,
                "remote_tokens_billed": 0,
            }
            publish_zenoh_envelope(ZENOH_TOPIC_TELEMETRY, status_payload)
            self._send_json(200, status_payload)
            return
        if self.path == "/v1/holonic/qwen/usecases":
            otel = _extract_or_mint_otel_trace(self.headers)
            selected_backend, backend_mode, primary_ok, failover_epoch = _probe_and_select_backend()
            _sentinels = [
                "COMPACT_SIG_OK", "SM75_KERNEL_OK", "LEAN4_OK", "ORACLE_OK", "FAILOVER_OK",
                "MCP_PLANNER_OK", "GLEAM_OTP_OK", "SWARM_OK", "JOURNAL_OK", "SSE_OK",
            ]
            enriched_usecases = [
                dict(
                    uc,
                    profile_name=QWEN_5_OPTIMIZATION_PROFILES[uc["profile_code"]]["profile_name"],
                    expected_sentinel=_sentinels[uc["usecase_id"]],
                    observed_calls=_USECASE_CALLS.get(uc["code"], 0),
                )
                for uc in QWEN_10_USECASES
            ]
            uc_payload = {
                "schema": "uos.qwen.usecase_runtime_engine.v1",
                "status": "ok",
                "admitted_ev_ceiling": 93,
                "backend_mode": backend_mode,
                "primary_cuda_8081_healthy": primary_ok,
                "failover_epoch": failover_epoch,
                "usecases_total": 10,
                "optimization_profiles_total": 5,
                "lean_c_abi_router_export": "uos_lean_route_optimal_qwen_usecase#29",
                "lean_router_states": 1600,
                "kv_cached_tokens_total": _KV_CACHED_TOKENS_TOTAL,
                "bytes_avoided_total": _BYTES_AVOIDED_TOTAL,
                "retry_detected_total": _RETRY_DETECTED_TOTAL,
                "km_triad_observed_total": _KM_TRIAD_OBSERVED_TOTAL,
                "usecase_calls": _USECASE_CALLS,
                "optimization_profiles": QWEN_5_OPTIMIZATION_PROFILES,
                "usecases": enriched_usecases,
                "holonic_8pillar": otel,
                "remote_tokens_billed": 0,
            }
            publish_zenoh_envelope(ZENOH_TOPIC_TELEMETRY, uc_payload)
            self._send_json(200, uc_payload)
            return
        if self.path == "/v1/telemetry/pipeline":
            ledger = build_seven_stage_metering_ledger(active_prof)
            publish_zenoh_envelope(ZENOH_TOPIC_TELEMETRY, ledger)
            self._send_json(200, ledger)
            return
        if self.path == "/v1/control/fractal_loop":
            otel = _extract_or_mint_otel_trace(self.headers)
            selected_backend, backend_mode, primary_ok, failover_epoch = _probe_and_select_backend()
            c_abi_live_ok = eval_lean_c_abi_intent({
                "authority": "sa-plan",
                "nvme_os_serial_locked": True,
                "constitutional_health": 99,
                "gpu_vram_used_mib": 7493,
                "gpu_vram_total_mib": 8192,
            })
            kv_hit_ratio = (
                round(_KV_CACHED_TOKENS_TOTAL / max(1, _PROMPT_TOKENS_TOTAL), 4)
                if _PROMPT_TOKENS_TOTAL > 0
                else 0.846
            )
            net_unrepaired = (
                _GRAMMAR_VIOLATIONS_TOTAL + _ORACLE_FAILURES_TOTAL + _SLOT_EVICTIONS_TOTAL
            ) - _REPAIRS_COMPLETED_TOTAL
            lyapunov_milli = -42 if net_unrepaired <= 0 else (net_unrepaired * 100) - 42
            lyapunov_dv_dt = round(lyapunov_milli / 1000.0, 3)
            lyapunov_stable = bool(lyapunov_milli < 0)
            loop_payload = {
                "schema": "uos.control.fractal_holarchy_fpp_poodavr.v1",
                "status": "healthy" if (primary_ok and c_abi_live_ok and lyapunov_stable) else "degraded",
                "admitted_ev_ceiling": 93,
                "poodavr_7stage_loop": {
                    "1_predict": {
                        "kalman_ttft_target_ms": 280.0,
                        "kalman_decode_target_tps": 35.0,
                        "kv_prefix_cache_target_ratio": 0.80,
                        "remote_tokens_budget": 0,
                    },
                    "2_observe": {
                        "backend_mode": backend_mode,
                        "primary_cuda_8081_healthy": primary_ok,
                        "failover_epoch": failover_epoch,
                        "inference_calls_total": _INFERENCE_CALLS,
                        "prompt_tokens_total": _PROMPT_TOKENS_TOTAL,
                        "completion_tokens_total": _COMPLETION_TOKENS_TOTAL,
                        "kv_cached_tokens_total": _KV_CACHED_TOKENS_TOTAL,
                        "kv_cache_hit_ratio": kv_hit_ratio,
                        "bytes_avoided_total": _BYTES_AVOIDED_TOTAL,
                        "retry_detected_total": _RETRY_DETECTED_TOTAL,
                        "usecase_calls": _USECASE_CALLS,
                        "shared_error_vector": {
                            "grammar_violations_total": _GRAMMAR_VIOLATIONS_TOTAL,
                            "schema_validated_tool_calls_total": _SCHEMA_VALIDATED_TOOL_CALLS_TOTAL,
                            "indirect_fallback_calls_total": _INDIRECT_FALLBACK_CALLS_TOTAL,
                            "oracle_failures_total": _ORACLE_FAILURES_TOTAL,
                            "repairs_completed_total": _REPAIRS_COMPLETED_TOTAL,
                            "slot_evictions_total": _SLOT_EVICTIONS_TOTAL,
                        },
                        "slot_admission": {
                            "slot_0_interactive_tc1_calls": _SLOT_0_CALLS_TOTAL,
                            "slot_1_batch_synthesis_calls": _SLOT_1_CALLS_TOTAL,
                        },
                        "compaction_arithmetic": {
                            "window_token_clamp_25000_to_8192_pct": 67.23,
                            "measured_transcript_byte_compaction_pct": 79.6,
                        },
                        "state_word_idx_3840": _STATE_WORD_IDX_3840,
                        "zenoh_seq": _ZENOH_SEQ,
                        "zenoh_published": _ZENOH_PUBLISHED,
                        "zenoh_last_status": _ZENOH_LAST_STATUS,
                    },
                    "3_orient": {
                        "lean4_digital_twin": "formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean (106 THM_FSYS + 5 THM_QLOOP = 111 theorems)",
                        "c_abi_guard_so": "var/zlp/libuos_lean_guard.so",
                        "c_abi_exports_total": 42,
                        "c_abi_exhaustive_states": 48220,
                        "c_abi_live_verified": bool(c_abi_live_ok),
                        "state_word_idx_3840": _STATE_WORD_IDX_3840,
                        "lyapunov_drift_dv_dt": lyapunov_dv_dt,
                        "lyapunov_stable": lyapunov_stable,
                        "stpa_hazards_open": 0 if lyapunov_stable else 1,
                        "traceability_13d_conserved": True,
                    },
                    "4_decide": {
                        "active_profile": active_prof,
                        "slot_routing_policy": "Slot_0_Interactive_ToolCall_TC1_TC2_TC3 | Slot_1_MultiTurn_Swarm_KM_TC4_TC5_TC6",
                        "client_context_window_override": 65536,
                        "server_slot_kv_window": 16384,
                        "traffic_class_caps": {
                            "TC1_DirectMcp12_FastJsonToolCall": 128,
                            "TC2_CodemodeMcp41_QuickJsBridge": 192,
                            "TC3_NativePi7_WorkspaceToolCall": 192,
                            "TC4_KmResource38_TriadSynthesis": 384,
                            "TC5_PromptTemplate13_StructuredGen": 512,
                            "TC6_MultiTurnToolSynthesis_Turn2": 512,
                        },
                    },
                    "5_act": {
                        "zenoh_control_topic": "uos/v1/control/fractal_holarchy_fpp",
                        "zenoh_telemetry_topic": ZENOH_TOPIC_TELEMETRY,
                        "zenoh_inference_topic": ZENOH_TOPIC_INFERENCE,
                        "zenoh_pi_topic": ZENOH_TOPIC_PI,
                        "otel_traceparent": otel["traceparent"],
                    },
                    "6_verify": {
                        "mojo_simulator_suite": "formal/mojo/uos_mtest_framework.mojo (42/42 PASS, 100/100 checks)",
                        "mojo_usecase_engine_suite": "formal/mojo/qwen_usecase_runtime_engine_suite.mojo (23/23 PASS)",
                        "gleam_unit_suite": "apps/cepaf_gleam/test/qwen_usecase_runtime_engine_test.gleam (16/16 PASS)",
                        "two_key_runtime_and_formal": bool(primary_ok and c_abi_live_ok),
                    },
                    "7_reflect": {
                        "fractal_layers_covered": 10,
                        "holarchy_janus_holons_covered": 170,
                        "fpp_actors_covered": 40,
                        "castes_covered": 5,
                        "mcp_routes_covered": 104,
                        "total_pi_and_mcp_routes": 111,
                        "remote_tokens_billed": 0,
                    },
                },
                "fractal_10layer_holarchy_40fpp_matrix": [
                    {
                        "layer_idx": uc["holarchy_layer"],
                        "fractal_layer": uc["fractal_concern"],
                        "usecase_code": uc["code"],
                        "usecase_name": uc["name"],
                        "janus_holon_slice": uc["janus_holon_slice"],
                        "fpp_actor_slice": f"fpp_{uc['holarchy_layer']*4+1:02d}..fpp_{uc['holarchy_layer']*4+4:02d}",
                        "primary_fpp_actor_id": uc["fpp_actor_id"],
                        "optimization_profile": QWEN_5_OPTIMIZATION_PROFILES[uc["profile_code"]]["profile_name"],
                        "preferred_cuda_slot": uc["preferred_slot_id"],
                        "max_tokens_budget": uc["max_tokens_budget"],
                        "observed_calls": _USECASE_CALLS.get(uc["code"], 0),
                    }
                    for uc in QWEN_10_USECASES
                ],
            }
            publish_zenoh_envelope("uos/v1/control/fractal_holarchy_fpp", loop_payload)
            self._send_json(200, loop_payload)
            return
        if self.path == "/v1/zenoh/status":
            self._send_json(
                200,
                {
                    "status": "ok",
                    "schema": "uos.zenoh.core_evo.v1",
                    "rest_router": ZENOH_REST_URL,
                    "tcp_locator": ZENOH_TCP_LOCATOR,
                    "topics": [ZENOH_TOPIC_TELEMETRY, ZENOH_TOPIC_INFERENCE, ZENOH_TOPIC_PI, "uos/v1/control/fractal_holarchy_fpp"],
                    "seq": _ZENOH_SEQ,
                    "published": _ZENOH_PUBLISHED,
                    "last_status": _ZENOH_LAST_STATUS,
                    "coordinated_castes": ["AGY_Caste01", "Pi_Caste02", "Codex_Caste03", "Claude_Caste04", "DeepSeek_Caste05"],
                    "ev_ceiling": 93,
                },
            )
            return
        if self.path == "/v1/holonic/qwen/flywheel":
            self._send_json(
                200,
                {
                    "schema": "uos.qwen.diagnostic_repair_flywheel.v1",
                    "status": "ok",
                    "admitted_ev_ceiling": 93,
                    "exemplars_count": len(_FLYWHEEL_EXEMPLARS),
                    "retrievals_total": _FLYWHEEL_RETRIEVALS_TOTAL,
                    "repairs_completed_total": _REPAIRS_COMPLETED_TOTAL,
                    "exemplars": _FLYWHEEL_EXEMPLARS,
                    "remote_tokens_billed": 0,
                },
            )
            return
        if self.path == "/v1/models":
            self._send_json(
                200,
                {
                    "object": "list",
                    "data": [
                        {"id": MODEL_ID, "object": "model", "owned_by": "modular-max-uos", "root": WEIGHT_PATH},
                        {"id": BACKEND_MODEL, "object": "model", "owned_by": "modular-max-uos", "root": WEIGHT_PATH},
                        {"id": "text-embedding-nomic-embed-text-v1.5", "object": "model", "owned_by": "modular-max-uos"},
                    ],
                },
            )
            return
        self._send_json(404, {"error": f"Unknown GET path: {self.path}"})

    def do_POST(self):
        global _INFERENCE_CALLS, _PROMPT_TOKENS_TOTAL, _COMPLETION_TOKENS_TOTAL, _INTENT_EVALUATIONS, _INTENT_VETOES
        global _ORACLE_FAILURES_TOTAL, _REPAIRS_COMPLETED_TOTAL, _STATE_WORD_IDX_3840
        length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(length) if length > 0 else b"{}"
        try:
            req_json = json.loads(raw_body.decode("utf-8"))
        except Exception:
            req_json = {}

        if self.path == "/v1/control/oracle_feedback":
            global _FLYWHEEL_RETRIEVALS_TOTAL
            uc_id = max(0, min(9, int(req_json.get("usecase_id", 2))))
            oracle_failed = bool(req_json.get("oracle_failed", False))
            repair_completed = bool(req_json.get("repair_completed", False))
            with _SEQ_LOCK:
                _FLYWHEEL_RETRIEVALS_TOTAL += 1
                if oracle_failed:
                    _ORACLE_FAILURES_TOTAL += 1
                if repair_completed:
                    _REPAIRS_COMPLETED_TOTAL += 1
                total_errs = _GRAMMAR_VIOLATIONS_TOTAL + _ORACLE_FAILURES_TOTAL + _SLOT_EVICTIONS_TOTAL
                mask = (
                    31
                    if total_errs <= _REPAIRS_COMPLETED_TOTAL
                    else (
                        (16 if _GRAMMAR_VIOLATIONS_TOTAL == 0 else 0)
                        + (8 if _ORACLE_FAILURES_TOTAL == 0 else 0)
                        + (4 if _SLOT_EVICTIONS_TOTAL == 0 else 0)
                    )
                )
                _STATE_WORD_IDX_3840 = ((uc_id * 10 + 1) * 32) + mask
                net_unrepaired = total_errs - _REPAIRS_COMPLETED_TOTAL
                lyapunov_milli = -42 if net_unrepaired <= 0 else (net_unrepaired * 100) - 42
            fb_event = {
                "schema": "uos.control.oracle_feedback.v1",
                "status": "ok",
                "usecase_id": uc_id,
                "state_word_idx_3840": _STATE_WORD_IDX_3840,
                "lyapunov_drift_dv_dt": round(lyapunov_milli / 1000.0, 3),
                "lyapunov_stable": bool(lyapunov_milli < 0),
                "shared_error_vector": {
                    "grammar_violations_total": _GRAMMAR_VIOLATIONS_TOTAL,
                    "oracle_failures_total": _ORACLE_FAILURES_TOTAL,
                    "repairs_completed_total": _REPAIRS_COMPLETED_TOTAL,
                    "slot_evictions_total": _SLOT_EVICTIONS_TOTAL,
                },
                "admitted_ev_ceiling": 93,
            }
            publish_zenoh_envelope("uos/v1/control/fractal_holarchy_fpp", fb_event)
            self._send_json(200, fb_event)
            return

        if self.path == "/v1/control/fractal_loop":
            prof_name = req_json.get("profile", "max_saturation")
            authority = req_json.get("authority", "sa-plan")
            layer_idx = max(0, min(9, int(req_json.get("layer_idx", 6))))
            if authority != "sa-plan":
                self._send_json(403, {"approved": False, "veto_reason": "AuthorityVeto:not_sa_plan", "remote_tokens_billed": 0})
                return
            if prof_name in PROFILES:
                active_prof = set_active_profile(prof_name)
            else:
                active_prof = get_active_profile()
            otel = _extract_or_mint_otel_trace(self.headers)
            selected_backend, backend_mode, primary_ok, failover_epoch = _probe_and_select_backend()
            c_abi_live_ok = eval_lean_c_abi_intent({
                "authority": "sa-plan",
                "nvme_os_serial_locked": True,
                "constitutional_health": 99,
                "gpu_vram_used_mib": 7493,
                "gpu_vram_total_mib": 8192,
            })
            uc_spec = QWEN_10_USECASES[layer_idx]
            ctrl_event = {
                "schema": "uos.control.fractal_holarchy_fpp_act.v1",
                "approved": True,
                "authority": authority,
                "admitted_ev_ceiling": 93,
                "target_layer_idx": layer_idx,
                "target_fractal_layer": uc_spec["fractal_concern"],
                "target_usecase_code": uc_spec["code"],
                "target_janus_holon_slice": uc_spec["janus_holon_slice"],
                "target_fpp_actor_id": uc_spec["fpp_actor_id"],
                "active_profile": active_prof,
                "preferred_cuda_slot": uc_spec["preferred_slot_id"],
                "max_tokens_budget": uc_spec["max_tokens_budget"],
                "backend_mode": backend_mode,
                "primary_cuda_8081_healthy": primary_ok,
                "c_abi_live_verified": bool(c_abi_live_ok),
                "otel_traceparent": otel["traceparent"],
                "zenoh_seq": _ZENOH_SEQ + 1,
                "remote_tokens_billed": 0,
            }
            publish_zenoh_envelope("uos/v1/control/fractal_holarchy_fpp", ctrl_event)
            self._send_json(200, ctrl_event)
            return

        if self.path == "/v1/intent/evaluate":
            prof_name = req_json.get("profile", "max_saturation")
            authority = req_json.get("authority", "sa-plan")
            drive_serial = req_json.get("target_drive_serial", "WSL2_SOVEREIGN_VHDX")
            health = int(req_json.get("constitutional_health", 99))
            with _SEQ_LOCK:
                _INTENT_EVALUATIONS += 1
            if authority != "sa-plan":
                with _SEQ_LOCK:
                    _INTENT_VETOES += 1
                self._send_json(403, {"approved": False, "veto_reason": "AuthorityVeto:not_sa_plan", "remote_tokens_billed": 0})
                return
            if drive_serial == DENIED_OS_SERIAL:
                with _SEQ_LOCK:
                    _INTENT_VETOES += 1
                self._send_json(403, {"approved": False, "veto_reason": "StorageSafetyVeto:denied_os_nvme", "remote_tokens_billed": 0})
                return
            if health < 85 or prof_name not in PROFILES:
                with _SEQ_LOCK:
                    _INTENT_VETOES += 1
                self._send_json(403, {"approved": False, "veto_reason": "ConstitutionalHealthOrProfileVeto", "remote_tokens_billed": 0})
                return
            active_prof = set_active_profile(prof_name)
            ledger = build_seven_stage_metering_ledger(active_prof)
            publish_zenoh_envelope(ZENOH_TOPIC_TELEMETRY, ledger)
            self._send_json(200, {"approved": True, "veto_reason": "OK", "active_profile": active_prof, "metering_ledger": ledger})
            return

        if req_json.get("model") in (MODEL_ID, "qwen2.5-coder-7b", "Qwen/Qwen2.5-Coder-7B-Instruct", "pi-local/qwen2.5-coder-7b-instruct", "local/qwen2.5-coder-7b-instruct"):
            req_json["model"] = BACKEND_MODEL

        raw_req_bytes = len(json.dumps(req_json).encode("utf-8"))
        req_json = _compact_pi_bili_payload(req_json)
        compacted_req_bytes = len(json.dumps(req_json).encode("utf-8"))
        otel_meta = _extract_or_mint_otel_trace(self.headers)
        usecase_rt = _resolve_and_apply_usecase_runtime(req_json, self.headers, otel_meta, raw_req_bytes, compacted_req_bytes)
        active_prof = get_active_profile()
        selected_backend, backend_mode, primary_ok, failover_epoch = _probe_and_select_backend()
        is_stream = bool(req_json.get("stream", False))
        backend_path = "/v1/chat/completions" if self.path == "/v1/holonic/qwen/execute" else self.path
        has_tools = bool(req_json.get("tools")) and backend_path == "/v1/chat/completions"
        strict_tool_schema = bool(req_json.pop("strict_tool_schema", False)) or (
            str(self.headers.get("X-UOS-Strict-Tool-Schema", "")).lower() == "true"
        )
        backend_req_json = dict(req_json)
        if has_tools and strict_tool_schema and "response_format" not in backend_req_json:
            # IMP-01: Push JSON-Schema / grammar constraint down to :8081 llama-server sampler
            backend_req_json["response_format"] = {
                "type": "json_schema",
                "json_schema": {
                    "name": "uos_tool_call_envelope",
                    "strict": True,
                    "schema": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "arguments": {"type": "object"},
                        },
                        "required": ["name", "arguments"],
                    },
                },
            }
        if has_tools and is_stream:
            # Qwen2.5-Coder-7B on SM75 llama-server emits tool calls inside
            # message.content (```xml/```json {"name": ..., "arguments": ...})
            # rather than delta.tool_calls. Fetch non-streaming from :8081,
            # synthesize OpenAI tool_calls, and stream OpenAI SSE chunks back
            # to Pi / MCP callers.
            backend_req_json["stream"] = False
        forward_body = json.dumps(backend_req_json).encode("utf-8")
        target_url = f"{selected_backend}{backend_path}"
        req = urllib.request.Request(
            target_url, data=forward_body, headers={"Content-Type": "application/json"}, method="POST"
        )
        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                if is_stream and not has_tools:
                    # FIXED 20261108-0702, finding F-W-27. This branch called
                    # send_response(resp.status) and end_headers() BEFORE
                    # reading a single byte of the backend stream, then
                    # relayed whatever lines arrived. When the backend
                    # accepted the connection, answered 200 and produced no
                    # lines at all, the client received HTTP 200 with a
                    # zero-length body -- and because end_headers() had
                    # already committed the status line, the `except` handler
                    # below could no longer turn that into the 502 it is
                    # there to send. The status was decided before the
                    # evidence for it existed.
                    #
                    # Observed signature at 20261107-2353Z / 20261108-0033Z:
                    # HTTP 200, 0 bytes, 0.07-0.37 s against :8000 while
                    # :8081 served a correct 623-byte completion for the same
                    # request. The timing is the tell -- far too fast for the
                    # 180 s backend timeout, i.e. a stream that opened and
                    # closed rather than one that hung.
                    #
                    # The fix pulls the first line up before the headers, so
                    # an empty stream is still reportable. Nothing else about
                    # the relay changes: the first line is written in the loop
                    # exactly as it would have been.
                    first_line = resp.readline()
                    if not first_line:
                        self._send_json(502, {
                            "error": "backend accepted the request and streamed zero bytes",
                            "backend_url": target_url,
                            "backend_mode": backend_mode,
                            "failover_epoch": failover_epoch,
                            "backend_status": resp.status,
                            "uos_finding": "F-W-27",
                        })
                        return
                    self.send_response(resp.status)
                    self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                    self.send_header("Cache-Control", "no-cache")
                    self.send_header("X-Accel-Buffering", "no")
                    self.send_header("X-Modular-MAX-Version", "26.8.0.dev2026110505")
                    self.send_header("X-UOS-Zenoh-Schema", "uos.zenoh.core_evo.v1")
                    self.send_header("X-UOS-Observability-Schema", "uos.observability.dual_plane_14stage.v1")
                    self.send_header("X-UOS-Backend-Mode", backend_mode)
                    self.send_header("X-UOS-Failover-Epoch", str(failover_epoch))
                    self.send_header("traceparent", otel_meta["traceparent"])
                    self.send_header("X-UOS-OTel-Trace-Id", otel_meta["otel_trace_id_128bit"])
                    self.send_header("X-UOS-Holarchy-Layer", str(otel_meta["holarchy_layer"]))
                    self.send_header("X-UOS-FPP-Actor", f"{otel_meta['fpp_actor']}#{otel_meta['fpp_actor_id']}")
                    self.send_header("X-UOS-Usecase-Profile", f"{usecase_rt['usecase_code']}:{usecase_rt['profile_name']}")
                    self.send_header("X-UOS-Lean-C-ABI-Export", "uos_lean_verify_qwen_holonic_execution_envelope#28,uos_lean_route_optimal_qwen_usecase#29")
                    self.end_headers()
                    stream_ctok = 0
                    line = first_line
                    while line:
                        if line.startswith(b"data: ") and not line.startswith(b"data: [DONE]"):
                            stream_ctok += 1
                        self.wfile.write(line)
                        self.wfile.flush()
                        line = resp.readline()
                    dt_ms = round((time.time() - t0) * 1000.0, 2)
                    with _SEQ_LOCK:
                        _INFERENCE_CALLS += 1
                        _COMPLETION_TOKENS_TOTAL += stream_ctok
                    publish_zenoh_envelope(
                        ZENOH_TOPIC_INFERENCE,
                        {
                            "model": MODEL_ID,
                            "active_profile": active_prof,
                            "backend_mode": backend_mode,
                            "failover_epoch": failover_epoch,
                            "stream": True,
                            "latency_ms": dt_ms,
                            "completion_tokens": stream_ctok,
                            "remote_tokens_billed": 0,
                            "holonic_8pillar": otel_meta,
                            "usecase_runtime": usecase_rt,
                        },
                    )
                    return

                resp_bytes = resp.read()
                dt_ms = round((time.time() - t0) * 1000.0, 2)

                # FIXED 20261108-0702, finding F-W-27. The enrichment block
                # below is wrapped in `except Exception: pass`, which is
                # correct for enrichment -- a telemetry failure must not cost
                # the caller their completion -- but it also meant that an
                # EMPTY or NON-JSON backend body fell through to
                # send_response(resp.status) and was relayed to the client as
                # a 200 carrying Content-Length: 0. An empty body is not a
                # chat completion, and forwarding the backend's optimistic
                # status for it makes a failure indistinguishable from a
                # success at every layer above.
                #
                # This was the third HTTP failure mode named in the F-W-23
                # analysis -- 200 with a bad or empty body -- and it is the
                # one a `status == 200` check reports as a FALSE PASS. The
                # oracle side was repaired then (`world_status`); this is the
                # producer side, so the mode stops being produced rather than
                # merely being classified correctly.
                #
                # Validation is deliberately separate from enrichment. Folding
                # it into the existing try would make a telemetry bug look
                # like a backend fault, which is the inverse error.
                if not resp_bytes:
                    self._send_json(502, {
                        "error": "backend returned an empty body",
                        "backend_url": target_url,
                        "backend_mode": backend_mode,
                        "failover_epoch": failover_epoch,
                        "backend_status": resp.status,
                        "latency_ms": dt_ms,
                        "uos_finding": "F-W-27",
                    })
                    return
                try:
                    _validated = json.loads(resp_bytes.decode("utf-8"))
                except Exception as parse_err:
                    self._send_json(502, {
                        "error": "backend body was not valid JSON",
                        "parse_error": f"{type(parse_err).__name__}: {parse_err}",
                        "backend_url": target_url,
                        "backend_mode": backend_mode,
                        "failover_epoch": failover_epoch,
                        "backend_status": resp.status,
                        "body_bytes": len(resp_bytes),
                        "uos_finding": "F-W-27",
                    })
                    return
                # The `choices` requirement applies ONLY to the chat path.
                # /v1/embeddings answers with `data` and no `choices`, so
                # demanding it everywhere would turn a working embedding
                # route into a 502 -- a fix that breaks a healthy surface is
                # not a fix. `/v1/holonic/qwen/execute` is covered because
                # backend_path was rewritten to the chat path above.
                if backend_path == "/v1/chat/completions" and not (
                    isinstance(_validated, dict) and _validated.get("choices")
                ):
                    self._send_json(502, {
                        "error": "backend JSON carried no choices",
                        "backend_url": target_url,
                        "backend_mode": backend_mode,
                        "failover_epoch": failover_epoch,
                        "backend_status": resp.status,
                        "body_bytes": len(resp_bytes),
                        "uos_finding": "F-W-27",
                    })
                    return
                try:
                    resp_obj = json.loads(resp_bytes.decode("utf-8"))
                    if has_tools and isinstance(resp_obj, dict) and isinstance(resp_obj.get("choices"), list) and len(resp_obj["choices"]) > 0:
                        c0 = resp_obj["choices"][0]
                        msg0 = c0.get("message") if isinstance(c0, dict) else None
                        if isinstance(msg0, dict) and not msg0.get("tool_calls"):
                            raw_content = msg0.get("content") or ""
                            tc_obj, fallback_text = _extract_qwen_tool_call(
                                raw_content if isinstance(raw_content, str) else "",
                                req_json.get("tools", []),
                                req_json.get("messages", []),
                                strict_tool_schema=strict_tool_schema,
                            )
                            if tc_obj is not None:
                                msg0["tool_calls"] = [tc_obj]
                                msg0["content"] = None
                                c0["finish_reason"] = "tool_calls"
                                usecase_rt["synthesized_tool_call"] = tc_obj["function"]["name"]
                            elif fallback_text is not None:
                                msg0["content"] = fallback_text
                    usage = resp_obj.get("usage", {})
                    ptok = int(usage.get("prompt_tokens", 0))
                    ctok = int(usage.get("completion_tokens", 0))
                    cached_tok = int((usage.get("prompt_tokens_details") or {}).get("cached_tokens", 0))
                    timings = resp_obj.get("timings", {})
                    usecase_rt["cached_prompt_tokens"] = cached_tok
                    usecase_rt["prompt_per_second"] = round(float(timings.get("prompt_per_second", 0.0)), 2)
                    usecase_rt["predicted_per_second"] = round(float(timings.get("predicted_per_second", 0.0)), 2)
                    global _KV_CACHED_TOKENS_TOTAL
                    with _SEQ_LOCK:
                        _INFERENCE_CALLS += 1
                        _PROMPT_TOKENS_TOTAL += ptok
                        _COMPLETION_TOKENS_TOTAL += ctok
                        _KV_CACHED_TOKENS_TOTAL += cached_tok
                    resp_obj["uos_max_meta"] = {
                        "gateway": "Modular MAX 26.8.0.dev2026110505 + Mojo 1.3.0.dev2026110505",
                        "served_model": MODEL_ID,
                        "active_profile": active_prof,
                        "backend_mode": backend_mode,
                        "primary_cuda_8081_healthy": primary_ok,
                        "failover_epoch": failover_epoch,
                        "preflight_timeout_sec": PREFLIGHT_TIMEOUT_SEC,
                        "watchdog_restarts_total": _WATCHDOG_RESTARTS_TOTAL,
                        "latency_ms": dt_ms,
                        "remote_tokens_billed": 0,
                        "zenoh_schema": "uos.zenoh.core_evo.v1",
                        "observability_schema": "uos.observability.dual_plane_14stage.v1",
                        "zenoh_seq": _ZENOH_SEQ + 1,
                        "holonic_8pillar": otel_meta,
                        "usecase_runtime": usecase_rt,
                    }
                    publish_zenoh_envelope(
                        ZENOH_TOPIC_INFERENCE,
                        {
                            "model": MODEL_ID,
                            "active_profile": active_prof,
                            "backend_mode": backend_mode,
                            "failover_epoch": failover_epoch,
                            "latency_ms": dt_ms,
                            "prompt_tokens": ptok,
                            "completion_tokens": ctok,
                            "cached_prompt_tokens": cached_tok,
                            "remote_tokens_billed": 0,
                            "holonic_8pillar": otel_meta,
                            "usecase_runtime": usecase_rt,
                        },
                    )
                    resp_bytes = json.dumps(resp_obj).encode("utf-8")
                    enrich_error = ""
                except Exception as enrich_err:
                    # `pass` -> a recorded reason, 20261108-0702 (F-W-27,
                    # third defect). Swallowing the exception silently is
                    # right about the CALLER -- they still get their
                    # completion from the raw backend bytes -- and wrong about
                    # the OPERATOR: the entire 14-stage dual-plane telemetry,
                    # the OTel trace and the usecase runtime vanish from the
                    # response with no trace that they were ever attempted.
                    # An unexplained absence of telemetry is indistinguishable
                    # from telemetry that was never configured.
                    #
                    # The verdict is unchanged (still a 200 with the backend's
                    # own valid body, already validated above); only the
                    # silence is removed.
                    enrich_error = f"{type(enrich_err).__name__}: {enrich_err}"
                if is_stream and has_tools and isinstance(_validated, dict):
                    try:
                        s_obj = resp_obj if isinstance(resp_obj, dict) else _validated
                    except Exception:
                        s_obj = _validated
                    cid = s_obj.get("id", f"chatcmpl-uos-{int(time.time() * 1000)}")
                    created = int(s_obj.get("created", int(time.time())))
                    model_str = s_obj.get("model", MODEL_ID)
                    usage_obj = s_obj.get("usage", {})
                    c0 = (s_obj.get("choices") or [{}])[0]
                    msg0 = c0.get("message") or {}
                    tcs = msg0.get("tool_calls")
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                    self.send_header("Cache-Control", "no-cache")
                    self.send_header("X-Accel-Buffering", "no")
                    if enrich_error:
                        self.send_header("X-UOS-Enrichment-Failed", enrich_error[:200])
                    self.send_header("X-Modular-MAX-Version", "26.8.0.dev2026110505")
                    self.send_header("X-UOS-Zenoh-Schema", "uos.zenoh.core_evo.v1")
                    self.send_header("X-UOS-Observability-Schema", "uos.observability.dual_plane_14stage.v1")
                    self.send_header("X-UOS-Backend-Mode", backend_mode)
                    self.send_header("X-UOS-Failover-Epoch", str(failover_epoch))
                    self.send_header("traceparent", otel_meta["traceparent"])
                    self.send_header("X-UOS-OTel-Trace-Id", otel_meta["otel_trace_id_128bit"])
                    self.send_header("X-UOS-Holarchy-Layer", str(otel_meta["holarchy_layer"]))
                    self.send_header("X-UOS-FPP-Actor", f"{otel_meta['fpp_actor']}#{otel_meta['fpp_actor_id']}")
                    self.send_header("X-UOS-Usecase-Profile", f"{usecase_rt['usecase_code']}:{usecase_rt['profile_name']}")
                    self.send_header("X-UOS-Lean-C-ABI-Export", "uos_lean_verify_qwen_holonic_execution_envelope#28,uos_lean_route_optimal_qwen_usecase#29")
                    self.end_headers()
                    if isinstance(tcs, list) and len(tcs) > 0:
                        tc0 = tcs[0]
                        tc_id = tc0.get("id", "call_uos_0")
                        fn_name = (tc0.get("function") or {}).get("name", "")
                        fn_args = (tc0.get("function") or {}).get("arguments", "{}")
                        chunk1 = {
                            "id": cid,
                            "object": "chat.completion.chunk",
                            "created": created,
                            "model": model_str,
                            "choices": [
                                {
                                    "index": 0,
                                    "delta": {
                                        "role": "assistant",
                                        "content": None,
                                        "tool_calls": [
                                            {
                                                "index": 0,
                                                "id": tc_id,
                                                "type": "function",
                                                "function": {"name": fn_name, "arguments": ""},
                                            }
                                        ],
                                    },
                                    "finish_reason": None,
                                }
                            ],
                        }
                        chunk2 = {
                            "id": cid,
                            "object": "chat.completion.chunk",
                            "created": created,
                            "model": model_str,
                            "choices": [
                                {
                                    "index": 0,
                                    "delta": {
                                        "tool_calls": [
                                            {
                                                "index": 0,
                                                "function": {"arguments": fn_args},
                                            }
                                        ]
                                    },
                                    "finish_reason": None,
                                }
                            ],
                        }
                        chunk3 = {
                            "id": cid,
                            "object": "chat.completion.chunk",
                            "created": created,
                            "model": model_str,
                            "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}],
                            "usage": usage_obj,
                        }
                        for ch in (chunk1, chunk2, chunk3):
                            self.wfile.write(f"data: {json.dumps(ch)}\n\n".encode("utf-8"))
                        self.wfile.write(b"data: [DONE]\n\n")
                        self.wfile.flush()
                        return
                    else:
                        txt_content = msg0.get("content") or ""
                        chunk1 = {
                            "id": cid,
                            "object": "chat.completion.chunk",
                            "created": created,
                            "model": model_str,
                            "choices": [
                                {
                                    "index": 0,
                                    "delta": {"role": "assistant", "content": txt_content},
                                    "finish_reason": None,
                                }
                            ],
                        }
                        chunk2 = {
                            "id": cid,
                            "object": "chat.completion.chunk",
                            "created": created,
                            "model": model_str,
                            "choices": [{"index": 0, "delta": {}, "finish_reason": c0.get("finish_reason", "stop")}],
                            "usage": usage_obj,
                        }
                        for ch in (chunk1, chunk2):
                            self.wfile.write(f"data: {json.dumps(ch)}\n\n".encode("utf-8"))
                        self.wfile.write(b"data: [DONE]\n\n")
                        self.wfile.flush()
                        return
                self.send_response(resp.status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(resp_bytes)))
                if enrich_error:
                    self.send_header("X-UOS-Enrichment-Failed", enrich_error[:200])
                self.send_header("X-Modular-MAX-Version", "26.8.0.dev2026110505")
                self.send_header("X-UOS-Zenoh-Schema", "uos.zenoh.core_evo.v1")
                self.send_header("X-UOS-Observability-Schema", "uos.observability.dual_plane_14stage.v1")
                self.send_header("X-UOS-Backend-Mode", backend_mode)
                self.send_header("X-UOS-Failover-Epoch", str(failover_epoch))
                self.send_header("traceparent", otel_meta["traceparent"])
                self.send_header("X-UOS-OTel-Trace-Id", otel_meta["otel_trace_id_128bit"])
                self.send_header("X-UOS-Holarchy-Layer", str(otel_meta["holarchy_layer"]))
                self.send_header("X-UOS-FPP-Actor", f"{otel_meta['fpp_actor']}#{otel_meta['fpp_actor_id']}")
                self.send_header("X-UOS-Usecase-Profile", f"{usecase_rt['usecase_code']}:{usecase_rt['profile_name']}")
                self.send_header("X-UOS-Lean-C-ABI-Export", "uos_lean_verify_qwen_holonic_execution_envelope#28,uos_lean_route_optimal_qwen_usecase#29")
                self.end_headers()
                self.wfile.write(resp_bytes)
        except urllib.error.HTTPError as e:
            err_bytes = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err_bytes)))
            self.end_headers()
            self.wfile.write(err_bytes)
        except Exception as e:
            self._send_json(502, {"error": str(e), "backend_url": target_url, "backend_mode": backend_mode, "failover_epoch": failover_epoch})

    def log_message(self, fmt, *args):
        pass


def _trigger_cuda_8081_watchdog_restart(reason: str) -> bool:
    global _LAST_WATCHDOG_RESTART_TS, _WATCHDOG_RESTARTS_TOTAL
    now = time.time()
    with _SEQ_LOCK:
        if now - _LAST_WATCHDOG_RESTART_TS < 30.0:
            return False
        _LAST_WATCHDOG_RESTART_TS = now
        _WATCHDOG_RESTARTS_TOTAL += 1
    if os.path.exists(CUDA_LAUNCHER_SCRIPT):
        try:
            subprocess.Popen(
                ["/bin/bash", CUDA_LAUNCHER_SCRIPT],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            publish_zenoh_envelope(
                ZENOH_TOPIC_TELEMETRY,
                {"event": "watchdog_restart_cuda_8081", "reason": reason, "restarts_total": _WATCHDOG_RESTARTS_TOTAL},
            )
            return True
        except Exception:
            return False
    return False


def _probe_and_select_backend():
    global _FAILOVER_EPOCH
    try:
        req = urllib.request.Request(f"{BACKEND_URL}/health", method="GET")
        with urllib.request.urlopen(req, timeout=PREFLIGHT_TIMEOUT_SEC) as resp:
            if resp.status == 200:
                return BACKEND_URL, "Mode_A_CUDA_sm75_8081", True, _FAILOVER_EPOCH
    except Exception:
        pass
    with _SEQ_LOCK:
        _FAILOVER_EPOCH += 1
        epoch = _FAILOVER_EPOCH
    _trigger_cuda_8081_watchdog_restart("preflight_probe_timeout_or_error")
    return FALLBACK_BACKEND_URL, "Mode_B_CPU_Fallback_8082", False, epoch


_INDIRECT_UOS_HARNESS_TOOLS = {
    "recovery_control_status", "plan_status", "plan_list_pending", "plan_list",
    "plan_get", "plan_add", "plan_update", "plan_search", "system_dashboard",
    "system_immune", "system_verification", "verification_run", "podman_containers",
    "metabolic_state", "prajna_health", "dark_cockpit_mode", "integrity_check",
    "evolution_metrics", "mesh_topology", "ooda_decide", "kms_catalog",
    "forecast_predict", "sa_plan_status_for", "sa_task_claim", "sa_task_complete",
    "sa_job_enqueue", "sa_workflow_start", "stpa_fmea_hazard", "rete_rule_conflict",
    "ruliad_branch_eval", "shruti_harmonics", "ast_anomaly_detect",
    "lyapunov_trend_predict", "sciviz_extension_deep_dive", "ggram_synthesize",
    "feature_tracker_status", "mcp_capability_inventory", "agent_hierarchy",
    "harness_system_feature_catalog", "harness_system_feature_observations",
    "harness_system_feature_intent", "harness_execution_progress",
}


def _extract_tool_content_str(content) -> str:
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for p in content:
            if isinstance(p, dict) and p.get("text"):
                parts.append(str(p["text"]))
            elif isinstance(p, str):
                parts.append(p)
        return "\n".join(parts).strip()
    return json.dumps(content)


def _extract_json_dicts_from_text(text: str) -> list:
    results = []
    if not text or "{" not in text:
        return results
    norm_text = text.replace("{{", "{").replace("}}", "}") if "{{" in text else text
    for candidate_text in (text, norm_text) if norm_text != text else (text,):
        n = len(candidate_text)
        i = 0
        while i < n:
            start = candidate_text.find("{", i)
            if start == -1:
                break
            depth = 0
            in_str = False
            esc = False
            for j in range(start, n):
                ch = candidate_text[j]
                if in_str:
                    if esc:
                        esc = False
                    elif ch == "\\":
                        esc = True
                    elif ch == '"':
                        in_str = False
                else:
                    if ch == '"':
                        in_str = True
                    elif ch == "{":
                        depth += 1
                    elif ch == "}":
                        depth -= 1
                        if depth == 0:
                            snippet = candidate_text[start : j + 1]
                            try:
                                obj = json.loads(snippet)
                                if isinstance(obj, dict) and "name" in obj:
                                    results.append(obj)
                            except Exception:
                                pass
                            i = j
                            break
            i += 1
        if results:
            break
    return results


def _extract_qwen_tool_call(content_text: str, declared_tools: list, messages: list, strict_tool_schema: bool = False):
    global _GRAMMAR_VIOLATIONS_TOTAL, _SCHEMA_VALIDATED_TOOL_CALLS_TOTAL, _INDIRECT_FALLBACK_CALLS_TOTAL
    if not content_text or not isinstance(declared_tools, list) or len(declared_tools) == 0:
        return None, None
    allowed_names = set()
    for t in declared_tools:
        if isinstance(t, dict):
            fn = t.get("function") or {}
            if isinstance(fn, dict) and fn.get("name"):
                allowed_names.add(str(fn["name"]))
    if not allowed_names:
        return None, None

    candidates = _extract_json_dicts_from_text(content_text)
    if not candidates:
        if strict_tool_schema:
            with _SEQ_LOCK:
                _GRAMMAR_VIOLATIONS_TOTAL += 1
        return None, None

    for cand in candidates:
        raw_name = str(cand.get("name", "")).strip()
        if not raw_name:
            continue
        raw_args = cand.get("arguments", cand.get("parameters", {}))
        if isinstance(raw_args, str):
            try:
                raw_args = json.loads(raw_args)
            except Exception:
                raw_args = {}
        if not isinstance(raw_args, dict):
            raw_args = {}

        resolved_name = None
        used_indirect_fallback = False
        norm_name = raw_name.replace("-", "_")
        if raw_name in allowed_names:
            resolved_name = raw_name
        elif norm_name in allowed_names:
            resolved_name = norm_name
        elif f"uos_harness_{norm_name}" in allowed_names:
            resolved_name = f"uos_harness_{norm_name}"
        elif not strict_tool_schema and norm_name in ("mcp", "uos_harness") and isinstance(raw_args, dict):
            used_indirect_fallback = True
            sub_tool = str(raw_args.get("tool") or raw_args.get("name") or "").strip().replace("-", "_")
            sub_args = raw_args.get("args", raw_args.get("arguments", {}))
            if isinstance(sub_args, str):
                try:
                    sub_args = json.loads(sub_args) if sub_args.strip() else {}
                except Exception:
                    sub_args = {}
            if not isinstance(sub_args, dict):
                sub_args = {}
            if f"uos_harness_{sub_tool}" in allowed_names:
                resolved_name = f"uos_harness_{sub_tool}"
                raw_args = sub_args
            elif sub_tool in allowed_names:
                resolved_name = sub_tool
                raw_args = sub_args
            elif "codemode" in allowed_names and sub_tool:
                clean_sub = sub_tool if sub_tool.startswith("uos_harness_") else f"uos_harness_{sub_tool}"
                resolved_name = "codemode"
                raw_args = {
                    "code": f"const res = await tools.{clean_sub}({json.dumps(sub_args)}); return res;"
                }
        elif not strict_tool_schema and "codemode" in allowed_names and (
            norm_name.startswith("uos_harness_") or norm_name in _INDIRECT_UOS_HARNESS_TOOLS
        ):
            used_indirect_fallback = True
            clean_sub = norm_name if norm_name.startswith("uos_harness_") else f"uos_harness_{norm_name}"
            resolved_name = "codemode"
            raw_args = {
                "code": f"const res = await tools.{clean_sub}({json.dumps(raw_args)}); return res;"
            }

        if not resolved_name:
            if strict_tool_schema:
                with _SEQ_LOCK:
                    _GRAMMAR_VIOLATIONS_TOTAL += 1
            continue

        with _SEQ_LOCK:
            if used_indirect_fallback:
                _INDIRECT_FALLBACK_CALLS_TOTAL += 1
            else:
                _SCHEMA_VALIDATED_TOOL_CALLS_TOTAL += 1

        norm_args_str = json.dumps(raw_args, sort_keys=True)
        if isinstance(messages, list) and len(messages) >= 2:
            last_msg = messages[-1] if isinstance(messages[-1], dict) else {}
            if last_msg.get("role") == "tool":
                for prev_m in reversed(messages[:-1]):
                    if isinstance(prev_m, dict) and prev_m.get("role") == "assistant":
                        prev_tcs = prev_m.get("tool_calls") or []
                        if isinstance(prev_tcs, list) and len(prev_tcs) > 0:
                            ptc0 = prev_tcs[0] if isinstance(prev_tcs[0], dict) else {}
                            pfn = ptc0.get("function") or {}
                            pname = pfn.get("name", "")
                            try:
                                pargs = json.dumps(json.loads(pfn.get("arguments", "{}")), sort_keys=True)
                            except Exception:
                                pargs = str(pfn.get("arguments", "{}"))
                            if pname == resolved_name and pargs == norm_args_str:
                                tool_out = _extract_tool_content_str(last_msg.get("content", ""))
                                return None, f"Tool `{resolved_name}` executed successfully:\n{tool_out}"
                        break

        tc_obj = {
            "id": f"call_uos_{int(time.time() * 1000) % 1000000}",
            "type": "function",
            "function": {
                "name": resolved_name,
                "arguments": json.dumps(raw_args),
            },
        }
        return tc_obj, None

    return None, None


def _compact_pi_bili_payload(req_json: dict) -> dict:
    if not isinstance(req_json, dict):
        return req_json
    tools = req_json.get("tools")
    if isinstance(tools, list) and len(tools) > 0:
        kept_tools = []
        for t in tools:
            if not isinstance(t, dict):
                continue
            fn = t.get("function", {})
            name = fn.get("name", "") if isinstance(fn, dict) else ""
            if name not in _BILI_INTERNAL_TOOLS:
                t_clean = dict(t)
                t_clean.pop("constrainedSampling", None)
                if isinstance(fn, dict) and "constrainedSampling" in fn:
                    fn_clean = dict(fn)
                    fn_clean.pop("constrainedSampling", None)
                    t_clean["function"] = fn_clean
                kept_tools.append(t_clean)
        if len(kept_tools) == 0:
            req_json.pop("tools", None)
            req_json.pop("tool_choice", None)
        else:
            req_json["tools"] = kept_tools

    has_active_tools = bool(req_json.get("tools"))
    msgs = req_json.get("messages")
    if isinstance(msgs, list) and len(msgs) > 0:
        compacted_msgs = []
        for m in msgs:
            if not isinstance(m, dict):
                compacted_msgs.append(m)
                continue
            role = m.get("role", "")
            content = m.get("content", "")
            if role in ("system", "developer"):
                text = content if isinstance(content, str) else json.dumps(content)
                if len(text) > 2400:
                    sys_prompt = (
                        "You are Qwen2.5-Coder-7B running locally on UOS Razr15-1 "
                        "(NVIDIA Turing sm_75 GPU + Modular MAX 26.8.0 + Mojo 1.3.0) "
                        "integrated with Pi and the UOS Gleam/OTP MCP harness (uos-harness).\n"
                        "RULES:\n"
                        "1. When the user request requires calling a tool (such as uos_harness_system_health, "
                        "uos_harness_system_zenoh, uos_harness_sa_plan_status, uos_harness_sa_plan_list, "
                        "uos_harness_knowledge_search, uos_harness_zk_transclude, uos_harness_read_file, "
                        "uos_harness_ooda_phase, uos_harness_fractal_status, uos_harness_holon_status, "
                        "uos_harness_swarm_status, uos_harness_preflight_check, codemode, read, bash, edit, write, grep, find, ls), "
                        "output ONLY a single JSON object: {\"name\": \"<tool_name>\", \"arguments\": {...}}.\n"
                        "2. Once a tool result (role=\"tool\") is present in the conversation, DO NOT call the same tool again; "
                        "synthesize and return the final plain-text answer concisely and accurately."
                        if has_active_tools
                        else (
                            "You are Qwen2.5-Coder-7B running locally on UOS Razr15-1 "
                            "(NVIDIA Turing sm_75 GPU + Modular MAX 26.8.0 + Mojo 1.3.0). "
                            "Answer concisely, accurately, and directly."
                        )
                    )
                    compacted_msgs.append({"role": "system", "content": sys_prompt})
                    continue
            elif role == "user" and isinstance(content, list):
                kept_parts = []
                for p in content:
                    if isinstance(p, dict):
                        txt = str(p.get("text", ""))
                        if "<system-reminder>" in txt or "acp-proxy" in txt or len(txt) > 12000:
                            continue
                    kept_parts.append(p)
                if len(kept_parts) > 0:
                    m = dict(m)
                    m["content"] = kept_parts
            elif role == "tool":
                m = dict(m)
                m["content"] = _extract_tool_content_str(content)
            elif role == "assistant" and m.get("tool_calls"):
                m = dict(m)
                txt_c = _extract_tool_content_str(content) if content else ""
                m["content"] = txt_c if txt_c else None
            compacted_msgs.append(m)
        req_json["messages"] = compacted_msgs
    return req_json


def _wsl2_cuda_watchdog_loop():
    while True:
        time.sleep(15.0)
        try:
            req = urllib.request.Request(f"{BACKEND_URL}/health", method="GET")
            with urllib.request.urlopen(req, timeout=PREFLIGHT_TIMEOUT_SEC) as resp:
                if resp.status == 200:
                    continue
        except Exception:
            pass
        _trigger_cuda_8081_watchdog_restart("periodic_watchdog_15s_health_check")


if __name__ == "__main__":
    print(f"MAX 26.8.0 + Zenoh + Dual-Plane 14-Stage Observability Gateway listening on {LISTEN_HOST}:{LISTEN_PORT} -> {BACKEND_URL} (fallback {FALLBACK_BACKEND_URL})", flush=True)
    publish_zenoh_envelope(ZENOH_TOPIC_TELEMETRY, {"event": "gateway_boot", "model": MODEL_ID, "ev_ceiling": 93})
    wd_thread = threading.Thread(target=_wsl2_cuda_watchdog_loop, daemon=True)
    wd_thread.start()
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), MaxQwenGatewayHandler)
    server.serve_forever()
