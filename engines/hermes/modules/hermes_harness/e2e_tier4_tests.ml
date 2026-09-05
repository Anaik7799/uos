open E2e_framework

let reg id name feature run =
  register_test { id; name; tier = Tier4_Application; feature; run }

let register_all () =
  (* ========================================================================= *)
  (* 1. t4.app.multi_turn_dialogue                                             *)
  (* ========================================================================= *)
  reg "t4.app.multi_turn_dialogue" "5-turn interactive dialogue with budget tracking and final receipt"
    "agent_loop.conversation_loop" (fun () ->
      let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:5 in
      let b0 = Turn_budget.create 5 in
      let rec loop i st b total_tokens =
        if i > 5 then (st, b, total_tokens)
        else
          let res = Turn_budget.consume b in
          if not res.allowed then (st, b, total_tokens)
          else
            let user_msg = `Assoc [ ("role", `String "user"); ("content", `String ("Question turn " ^ string_of_int i)) ] in
            let assistant_msg = `Assoc [ ("role", `String "assistant"); ("content", `String ("Answer turn " ^ string_of_int i)) ] in
            let st_next, _ = Conversation_loop.step_turn st ~messages:[ user_msg; assistant_msg ] in
            loop (i + 1) st_next res.budget (total_tokens + 150)
      in
      let _st_final, b_final, tokens_final = loop 1 st0 b0 0 in
      let res_extra = Turn_budget.consume b_final in
      if Turn_budget.used b_final = 5 && Turn_budget.remaining b_final = 0 && not res_extra.allowed then
        let executed_turns = Turn_budget.used b_final in
        let receipt = Turn_finalization.create_receipt ~turn_id:"app_t4_multi_turn" ~status:"success" ~turns:executed_turns ~tokens:tokens_final ~final_output:(Some "Interactive dialogue completed") in
        let summary = Turn_finalization.summarize receipt ~metadata:[ ("turns_requested", `Int 5) ] in
        if summary.receipt.status = "success" && summary.receipt.turns_executed = 5 && summary.receipt.total_tokens_used = 750 then Pass
        else Fail "Multi-turn dialogue receipt or summary verification failed"
      else Fail "Budget tracking across 5-turn dialogue failed");

  (* ========================================================================= *)
  (* 2. t4.app.budget_exhaustion_recovery                                     *)
  (* ========================================================================= *)
  reg "t4.app.budget_exhaustion_recovery" "Multi-turn session reaching 0 budget, clamping, refunding, and resuming"
    "agent_loop.interrupt_control" (fun () ->
      let b0 = Turn_budget.create 2 in
      let res1 = Turn_budget.consume b0 in
      let res2 = Turn_budget.consume res1.budget in
      if res1.allowed && res2.allowed && Turn_budget.remaining res2.budget = 0 then
        let res3 = Turn_budget.consume res2.budget in
        if not res3.allowed then
          let b_ref1 = Turn_budget.refund res2.budget in
          let b_ref2 = Turn_budget.refund b_ref1 in
          if Turn_budget.used b_ref2 = 0 && Turn_budget.remaining b_ref2 = 2 then
            let res4 = Turn_budget.consume b_ref2 in
            if res4.allowed && Turn_budget.used res4.budget = 1 && Turn_budget.remaining res4.budget = 1 then Pass
            else Fail "Resuming budget consumption after refund failed"
          else Fail "Refunding exhausted budget did not restore state"
        else Fail "3rd consume on 2-iteration budget was unexpectedly allowed"
      else Fail "Initial 2-iteration budget setup failed");

  (* ========================================================================= *)
  (* 3. t4.app.large_context_compression                                      *)
  (* ========================================================================= *)
  reg "t4.app.large_context_compression" "High token load triggering automatic context compression and prompt re-assembly"
    "agent_loop.context_compression" (fun () ->
      let sys_msg = `Assoc [ ("role", `String "system"); ("content", `String "System prompt instructions") ] in
      let turns =
        List.init 14 (fun i ->
            let role = if i mod 2 = 0 then "user" else "assistant" in
            `Assoc [ ("role", `String role); ("content", `String ("Long conversation history item " ^ string_of_int i ^ " with payload")) ])
      in
      let large_history = sys_msg :: turns in
      let strat = Context_compression.Truncate_oldest { keep_last_n = 4 } in
      let comp_res = Context_compression.compress_history ~strategy:strat large_history in
      if comp_res.original_count = 15 && comp_res.compressed_count = 5 && comp_res.tokens_saved > 0 then
        let assembled = Prompt_assembly.assemble ~model_id:"openai/gpt-5.4" ~messages:comp_res.compressed_messages in
        match assembled with
        | `Assoc fields -> (
            match List.assoc_opt "messages" fields with
            | Some (`List msgs) ->
                if List.length msgs = 5 then
                  match msgs with
                  | `Assoc sys_fields :: _ ->
                      if List.assoc_opt "role" sys_fields = Some (`String "developer") then Pass
                      else Fail "Compressed system message role is not developer"
                  | _ -> Fail "Assembled messages lead element invalid"
                else Fail "Assembled messages count does not match compressed count"
            | _ -> Fail "Assembled prompt missing messages list")
        | _ -> Fail "Assembled result is not JSON object"
      else Fail "Large context compression failed to truncate history");

  (* ========================================================================= *)
  (* 4. t4.app.tool_call_interruption                                         *)
  (* ========================================================================= *)
  reg "t4.app.tool_call_interruption" "Agent loop executing tool calls, handling interrupts, and finalizing turn state"
    "agent_loop.turn_finalization" (fun () ->
      let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:5 in
      let tool_msg =
        `Assoc
          [
            ("role", `String "assistant");
            ("tool_calls", `List [ `Assoc [ ("id", `String "call_interrupted_1"); ("type", `String "function") ] ]);
          ]
      in
      let st1, _ = Conversation_loop.step_turn st0 ~messages:[ tool_msg ] in
      if st1.step = Conversation_loop.ToolCall then
        let executed_turns = Turn_budget.used st1.budget in
        let receipt = Turn_finalization.create_receipt ~turn_id:"app_t4_tool_interrupt" ~status:"interrupted" ~turns:executed_turns ~tokens:180 ~final_output:None in
        let summary = Turn_finalization.summarize receipt ~metadata:[ ("interrupt_reason", `String "turn_budget_exceeded") ] in
        if summary.receipt.status = "interrupted" && summary.receipt.final_output = None &&
           List.assoc_opt "interrupt_reason" summary.metadata = Some (`String "turn_budget_exceeded") then Pass
        else Fail "Interrupted tool call receipt summary verification failed"
      else Fail "Conversation step turn did not reach ToolCall state");

  (* ========================================================================= *)
  (* 5. t4.app.surrogate_utf8_thought_sanitize                                *)
  (* ========================================================================= *)
  reg "t4.app.surrogate_utf8_thought_sanitize" "End-to-end multi-turn pipeline processing raw LLM output with UTF-8 surrogate replacement and thought signature filter"
    "agent_loop.message_hygiene" (fun () ->
      let raw_str = "Raw model stream output with surrogate \237\160\128 byte" in
      let cleaned_str = Message_hygiene.replace_surrogate_utf8 raw_str in
      let raw_msg =
        `Assoc
          [
            ("role", `String "assistant");
            ("content", `String cleaned_str);
            ("_internal_trace", `String "debug_123");
            ("codex_reasoning_items", `List [ `String "thought item" ]);
          ]
      in
      let sanitized_msg = Message_hygiene.sanitize_message ~model_id:"openai/gpt-5.4" raw_msg in
      let raw_tool_call =
        `Assoc
          [
            ("id", `String "tc_thought_1");
            ("type", `String "function");
            ("call_id", `String "cid_99");
            ("response_item_id", `String "rid_88");
          ]
      in
      let sanitized_tool = Message_hygiene.sanitize_tool_call ~keep_thought_signature:false raw_tool_call in
      let assembled = Prompt_assembly.assemble ~model_id:"openai/gpt-5.4" ~messages:[ sanitized_msg ] in
      match (sanitized_msg, sanitized_tool, assembled) with
      | (`Assoc msg_fields, `Assoc tool_fields, `Assoc assembled_fields) ->
          let msg_clean = not (List.mem_assoc "_internal_trace" msg_fields) && not (List.mem_assoc "codex_reasoning_items" msg_fields) in
          let tool_clean = not (List.mem_assoc "call_id" tool_fields) && not (List.mem_assoc "response_item_id" tool_fields) in
          let assembled_ok = List.mem_assoc "messages" assembled_fields in
          let receipt = Turn_finalization.create_receipt ~turn_id:"app_t4_e2e_hygiene" ~status:"success" ~turns:1 ~tokens:120 ~final_output:(Some "Clean output") in
          if msg_clean && tool_clean && assembled_ok && receipt.status = "success" then Pass
          else Fail "Surrogate UTF-8 and thought signature sanitization pipeline failed"
      | _ -> Fail "Pipeline stages produced non-Assoc JSON values");
  5
