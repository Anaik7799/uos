(** Tier 2 Boundary & Corner Cases Test Suite for Agent Loop capabilities (35 test cases).

    Covers resource exhaustion, token limits, UTF-8 surrogates, zero/negative budget clamping,
    missing context, and malformed payloads for:
    - agent_loop.message_hygiene
    - agent_loop.interrupt_control
    - agent_loop.conversation_loop
    - agent_loop.prompt_assembly
    - agent_loop.context_engine
    - agent_loop.context_compression
    - agent_loop.turn_finalization
*)

val register_all : unit -> unit
