(** L3 contract: System prompt assembly, prompt builder, and developer role formatting.

    Reference capability: [agent_loop.prompt_assembly]
    Frozen anchor: [agent_loop.prompt_assembly.70b2efe95be5.json]
*)

(*@ predicate valid_model_id (s: string) =
      s <> "" *)

val model_uses_developer_role : string -> bool
(*@ uses_dev = model_uses_developer_role model_id
    pure *)

val apply_developer_role : model_id:string -> Yojson.Safe.t list -> Yojson.Safe.t list
(*@ formatted = apply_developer_role ~model_id messages
    pure
    requires valid_model_id model_id *)

val assemble : model_id:string -> messages:Yojson.Safe.t list -> Yojson.Safe.t
(*@ result = assemble ~model_id ~messages
    pure
    requires valid_model_id model_id *)
