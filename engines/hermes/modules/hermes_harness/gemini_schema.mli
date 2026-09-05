(** L3 contract candidate (first cut): Gemini tool-parameter schema sanitization
    for [model_routing.gemini_adapter].

    Reference capability: [model_routing.gemini_adapter]
    Frozen anchor: [agent/gemini_schema.py] ([sanitize_gemini_tool_parameters])

    The self-contained pure core of the gemini adapter (importable without httpx,
    unlike the full build_gemini_request, which is the documented depth of this
    slice). [sanitize_tool_parameters] keeps only the Gemini-allowed schema keys
    in input order, recurses into properties/items/anyOf, stringifies+dedupes
    enums for integer/number/boolean types, filters required against the node's
    own properties, and stubs an empty result to {"type":"object","properties":{}}.

    Faithful to the frozen source; proven by the captured fixture. Float enum
    entries use Python str() (out of the first-cut corpus, which uses integer
    enums; documented). *)

val sanitize : Yojson.Safe.t -> Yojson.Safe.t
val sanitize_tool_parameters : Yojson.Safe.t -> Yojson.Safe.t
