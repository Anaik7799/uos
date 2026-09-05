(* L3 contracts: Gospel-specified OCaml interfaces that a candidate capability
   must satisfy.

   A contract is an obligation, not evidence. Its Gospel specification is only
   an observation until a `gospel` binary checks it, and even a checked
   contract grants no parity credit on its own — that still requires L4
   fixtures, L5 normalized traces, and an L6 verifier receipt. *)

type contract = {
  id : string;
  capability_key : string;
  interface : string;
  law : string;
}

(* Only capabilities with a candidate interface in the harness appear here. The
   remaining slices earn contracts as they are implemented in dependency
   order.

   agent_loop.message_hygiene is checkable via the Yojson stub in
   hermes_harness/gospel_stubs, which supplies the type name gospel cannot
   resolve on its own. The stub is strictly weaker than the real type, so it
   can only cause a false rejection, never a false acceptance. *)
let all =
  [
    { id = "agent_loop.message_hygiene.sanitize";
      capability_key = "agent_loop.message_hygiene";
      interface = "modules/hermes_harness/message_hygiene.mli";
      law = "MESSAGE-HYGIENE-SANITIZATION-IDEMPOTENCE" };
    { id = "agent_loop.interrupt_control.iteration_budget";
      capability_key = "agent_loop.interrupt_control";
      interface = "modules/hermes_harness/turn_budget.mli";
      law = "TURN-BUDGET-MONOTONIC-CONSUMPTION" };
    { id = "model_routing.provider_transports.request_shaping";
      capability_key = "model_routing.provider_transports";
      interface = "modules/hermes_harness/openrouter_contract.mli";
      law = "REQUEST-SHAPING-PURITY" };
    { id = "model_routing.provider_transports.response_decoding";
      capability_key = "model_routing.provider_transports";
      interface = "modules/hermes_harness/openrouter_transport.mli";
      law = "RESPONSE-DECODING-TOTALITY" };
    { id = "model_routing.rate_and_retry.retry_after";
      capability_key = "model_routing.rate_and_retry";
      interface = "modules/hermes_harness/retry_utils.mli";
      law = "RETRY-AFTER-DETERMINISTIC-BRANCHES" };
    { id = "model_routing.route_resolution.fallback_chain";
      capability_key = "model_routing.route_resolution";
      interface = "modules/hermes_harness/route_resolution.mli";
      law = "FALLBACK-CHAIN-DEDUP-ORDER-PRESERVING" };
    { id = "tool_execution.path_and_url_safety.has_traversal_component";
      capability_key = "tool_execution.path_and_url_safety";
      interface = "modules/hermes_harness/path_safety.mli";
      law = "PATH-TRAVERSAL-COMPONENT-DETECTION" };
    { id = "model_routing.anthropic_adapter.tool_and_model_shaping";
      capability_key = "model_routing.anthropic_adapter";
      interface = "modules/hermes_harness/anthropic_adapter.mli";
      law = "ANTHROPIC-TOOL-SCHEMA-NORMALIZATION" };
    { id = "model_routing.codex_runtime.responses_message_shaping";
      capability_key = "model_routing.codex_runtime";
      interface = "modules/hermes_harness/codex_message_shapes.mli";
      law = "CODEX-RESPONSES-MESSAGE-SHAPING" };
    { id = "model_routing.gemini_adapter.tool_schema_sanitization";
      capability_key = "model_routing.gemini_adapter";
      interface = "modules/hermes_harness/gemini_schema.mli";
      law = "GEMINI-TOOL-SCHEMA-SANITIZATION" };
    { id = "model_routing.cloud_vendor_adapters.bedrock_converse";
      capability_key = "model_routing.cloud_vendor_adapters";
      interface = "modules/hermes_harness/bedrock_converse.mli";
      law = "BEDROCK-CONVERSE-REQUEST-SHAPING" };
  ]

let node_id contract = "hermes." ^ contract.capability_key

let for_capability capability_key =
  List.filter (fun contract -> contract.capability_key = capability_key) all
