(** Tier 4 Application Workflow Test Suite for Agent Loop capabilities (5 test cases).

    Covers real-world application scenarios and end-to-end multi-turn workflows:
    - t4.app.multi_turn_dialogue: 5-turn interactive dialogue with budget tracking and final receipt
    - t4.app.budget_exhaustion_recovery: Multi-turn session reaching 0 budget, clamping, refunding, and resuming
    - t4.app.large_context_compression: High token load triggering automatic context compression and prompt re-assembly
    - t4.app.tool_call_interruption: Agent loop executing tool calls, handling interrupts, and finalizing turn state
    - t4.app.surrogate_utf8_thought_sanitize: End-to-end multi-turn pipeline processing raw LLM output with UTF-8 surrogate replacement and thought signature filter
*)

val register_all : unit -> int
(*@ count = register_all ()
    ensures count = 5 *)
