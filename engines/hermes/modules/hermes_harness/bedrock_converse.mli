(** L3 contract candidate: OpenAI -> Bedrock Converse request shaping for
    [model_routing.cloud_vendor_adapters].

    Reference capability: [model_routing.cloud_vendor_adapters]
    Frozen anchor: [agent/bedrock_adapter.py] ([build_converse_kwargs] + helpers,
    plus [_forbids_sampling_params] from [agent/anthropic_adapter.py]).

    The whole request shaper, faithful to the frozen source: message conversion
    (system/tool/assistant/user with merging and leading/trailing placeholder
    fixes), content conversion ([_safe_text], "(empty)" placeholder, data-URL vs
    remote-URL images), tool conversion, the model-family sampling-param and
    cache/tool-support predicates, and the inferenceConfig / toolConfig / system
    / cachePoint assembly.

    Scope (first cut, matching the probe corpus): data-URL images (raw bytes) are
    out; tool-result content is strings plus one dict case serialized with a
    Python-json.dumps-compatible embedder ([python_json], ", "/": " separators,
    input key order); floats stay short-decimal. Proven by the captured fixture. *)

val is_anthropic_bedrock_model : string -> bool
val forbids_sampling_params : string -> bool
val safe_text : Yojson.Safe.t -> string
val python_json : Yojson.Safe.t -> string
val convert_tools_to_converse : Yojson.Safe.t list -> Yojson.Safe.t list
val convert_messages_to_converse :
  Yojson.Safe.t list -> Yojson.Safe.t list option * Yojson.Safe.t list
(** ([system_blocks] when non-empty, converse messages). *)

val build_converse_kwargs :
  model:string ->
  messages:Yojson.Safe.t list ->
  ?tools:Yojson.Safe.t list ->
  ?max_tokens:int ->
  ?temperature:float ->
  ?top_p:float ->
  ?stop_sequences:string list ->
  ?guardrail_config:Yojson.Safe.t ->
  unit ->
  Yojson.Safe.t
