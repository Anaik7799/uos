(** L3 contract candidate: Anthropic tool/model shaping for
    [model_routing.anthropic_adapter].

    Reference capability: [model_routing.anthropic_adapter]
    Frozen anchors: [agent/anthropic_adapter.py], [tools/schema_sanitizer.py]

    Three pure functions, faithful to the frozen source:

    - [convert_tools_to_anthropic]: OpenAI tool list -> Anthropic tool list.
      Falsy -> []; per tool build {name, description, input_schema} (+ a copied
      cache_control dict if present); non-empty names dedup first-wins,
      empty names never dedup.
    - [normalize_model_name] (preserve_dots = false): strip a leading
      case-insensitive "anthropic/"; a Bedrock id passes verbatim; a claude-/
      doubled-anthropic id has ALL dots replaced by "-"; anything else passes.
    - [sanitize_tool_id]: empty -> "tool_0"; else every char outside
      [A-Za-z0-9_-] becomes "_". ASCII-scoped (Python replaces per Unicode
      codepoint; multibyte input is outside the corpus, documented).

    [input_schema] normalization mirrors [strip_nullable_unions] (recursive
    anyOf/oneOf collapse dropping null branches, no nullable hint) then the
    top-level banned-key strip and object/properties repair. Proven by the
    captured fixture, not by hand-derived expectations. *)

val is_bedrock_model_id : string -> bool
val normalize_model_name : string -> string
val sanitize_tool_id : string -> string
val strip_nullable_unions : Yojson.Safe.t -> Yojson.Safe.t
val normalize_tool_input_schema : Yojson.Safe.t -> Yojson.Safe.t
val convert_tools_to_anthropic : Yojson.Safe.t -> Yojson.Safe.t
