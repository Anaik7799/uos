(** Tier 3 Cross-Feature Pairwise & Property Test Suite for Agent Loop capabilities (7 test cases).

    Covers pairwise feature interactions and property-based invariant verification for:
    - t3.pair.hyg_prm: Sanitized messages assembled into system prompt
    - t3.pair.int_cnv: Interrupt budget consumed inside conversation turn loop
    - t3.pair.ctx_cmp: Context engine references compressed when token budget is exceeded
    - t3.pair.cnv_fin: Conversation turn finalization generates completion receipt
    - t3.pair.prm_ctx: Prompt assembly with injected tool context references
    - t3.pair.cmp_fin: Compressed context history finalized with turn receipt summary
    - t3.prop.fuzz: QCheck property test verifying budget clamping and state invariant preservation
*)

val register_all : unit -> int
(*@ count = register_all ()
    ensures count = 7 *)
