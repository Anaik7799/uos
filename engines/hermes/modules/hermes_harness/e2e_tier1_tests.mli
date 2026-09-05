(** Tier 1 Feature Coverage Test Suite for Agent Loop capabilities (35 test cases).

    Covers nominal happy path execution for:
    - agent_loop.message_hygiene
    - agent_loop.interrupt_control
    - agent_loop.conversation_loop
    - agent_loop.prompt_assembly
    - agent_loop.context_engine
    - agent_loop.context_compression
    - agent_loop.turn_finalization
*)

val register_all : unit -> unit
