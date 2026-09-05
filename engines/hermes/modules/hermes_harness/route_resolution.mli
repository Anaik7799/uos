(** L3 contract candidate: fallback route-chain resolution for
    [model_routing.route_resolution].

    Reference capability: [model_routing.route_resolution]
    Frozen anchor: [hermes_cli/fallback_config.py] ([get_fallback_chain])

    Resolves the effective fallback provider chain from a config mapping:
    - coerce provider/model with Python [str(v or "").strip()] semantics (a
      falsy value -> "", else the string form, stripped);
    - normalize base_url: a non-string -> ""; else strip whitespace then strip
      all trailing "/";
    - an entry missing provider or model (after coercion) is skipped;
    - each surviving entry is a shallow copy with provider/model overwritten in
      place and base_url overwritten only when its normalization is non-empty
      (else the original value survives) -- key order and extra keys preserved;
    - dedup across [fallback_providers] then [fallback_model] by the lowercased
      (provider, model, normalized-base_url) identity, first occurrence winning.

    Faithful to the frozen source; proven by the captured differential fixture,
    never by the hand-derived expectations in the probe. The container-coercion
    and float-repr branches are outside the scenario corpus and left conservative
    (documented in the .ml). *)

val get_fallback_chain : Yojson.Safe.t -> Yojson.Safe.t
(*@ chain = get_fallback_chain config
    pure *)
