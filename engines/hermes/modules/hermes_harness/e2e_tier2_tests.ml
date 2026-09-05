open E2e_framework

let reg id name feature run =
  register_test { id; name; tier = Tier2_Boundary; feature; run }

let register_all () =
  (* ========================================================================= *)
  (* 1. agent_loop.message_hygiene (5 Tier 2 TCs)                              *)
  (* ========================================================================= *)
  reg "t2.hyg.1" "UTF-8 surrogate sequence replacement"
    "agent_loop.message_hygiene" (fun () ->
      let surrogate_str = "Invalid \237\160\128 UTF-8" in
      let cleaned = Message_hygiene.replace_surrogate_utf8 surrogate_str in
      if cleaned = "Invalid \239\191\189 UTF-8" then Pass
      else Fail ("Surrogate sequence replacement failed: " ^ cleaned));

  reg "t2.hyg.2" "Sanitization of empty message list"
    "agent_loop.message_hygiene" (fun () ->
      let sanitized = Message_hygiene.sanitize_messages ~model_id:"openai/gpt-5.4" [] in
      if sanitized = [] then Pass
      else Fail "Empty message list output is not empty");

  reg "t2.hyg.3" "Sanitization of non-Assoc JSON message node"
    "agent_loop.message_hygiene" (fun () ->
      let non_assoc = `String "invalid_message_node" in
      let sanitized = Message_hygiene.sanitize_message ~model_id:"openai/gpt-5.4" non_assoc in
      if sanitized = non_assoc then Pass
      else Fail "Non-assoc JSON message was corrupted during fallback");

  reg "t2.hyg.4" "Message hygiene idempotence verification"
    "agent_loop.message_hygiene" (fun () ->
      let msg =
        `Assoc
          [
            ("role", `String "user");
            ("content", `String "Test \237\160\128");
            ("_secret", `String "123");
            ("codex_reasoning_items", `List []);
          ]
      in
      let pass1 = Message_hygiene.sanitize_message ~model_id:"openai/gpt-5.4" msg in
      let pass2 = Message_hygiene.sanitize_message ~model_id:"openai/gpt-5.4" pass1 in
      if pass1 = pass2 then Pass
      else Fail "Sanitization is not idempotent");

  reg "t2.hyg.5" "Sanitization of tool call with missing fields"
    "agent_loop.message_hygiene" (fun () ->
      let malformed_tool = `Assoc [ ("id", `String "tc_1") ] in
      let sanitized = Message_hygiene.sanitize_tool_call ~keep_thought_signature:false malformed_tool in
      match sanitized with
      | `Assoc fields ->
          if List.assoc_opt "id" fields = Some (`String "tc_1") then Pass
          else Fail "Tool call ID corrupted in malformed tool call"
      | _ -> Fail "Tool call non-assoc result");

  (* ========================================================================= *)
  (* 2. agent_loop.interrupt_control (5 Tier 2 TCs)                            *)
  (* ========================================================================= *)
  reg "t2.int.1" "Create budget with max = 0 (immediate refusal)"
    "agent_loop.interrupt_control" (fun () ->
      let b = Turn_budget.create 0 in
      let res = Turn_budget.consume b in
      if not res.allowed && Turn_budget.remaining b = 0 && Turn_budget.used res.budget = 0 then Pass
      else Fail "Zero budget did not refuse consumption immediately");

  reg "t2.int.2" "Create budget with negative max (clamped to 0)"
    "agent_loop.interrupt_control" (fun () ->
      let b = Turn_budget.create (-5) in
      let res = Turn_budget.consume b in
      if not res.allowed && Turn_budget.remaining b = 0 && b.maximum = -5 then Pass
      else Fail "Negative budget creation allowed consumption");

  reg "t2.int.3" "Attempt refund when consumed = 0"
    "agent_loop.interrupt_control" (fun () ->
      let b0 = Turn_budget.create 3 in
      let b_refunded = Turn_budget.refund b0 in
      if Turn_budget.used b_refunded = 0 && Turn_budget.remaining b_refunded = 3 then Pass
      else Fail "Refunding zero-consumed budget produced negative consumption");

  reg "t2.int.4" "Alternating consume-refund-consume at maximum boundary"
    "agent_loop.interrupt_control" (fun () ->
      let b0 = Turn_budget.create 1 in
      let r1 = Turn_budget.consume b0 in
      let b_ref = Turn_budget.refund r1.budget in
      let r2 = Turn_budget.consume b_ref in
      if r1.allowed && Turn_budget.used r1.budget = 1 && r2.allowed && Turn_budget.used r2.budget = 1 then Pass
      else Fail "Alternating consume-refund sequence at limit failed");

  reg "t2.int.5" "Invariant preservation under negative input clamping"
    "agent_loop.interrupt_control" (fun () ->
      let b = Turn_budget.create (-10) in
      if Turn_budget.used b >= 0 && Turn_budget.remaining b >= 0 then Pass
      else Fail "Negative budget violated non-negative remaining/used invariant");

  (* ========================================================================= *)
  (* 3. agent_loop.conversation_loop (5 Tier 2 TCs)                           *)
  (* ========================================================================= *)
  reg "t2.cnv.1" "Process with empty messages list []"
    "agent_loop.conversation_loop" (fun () ->
      let res = Conversation_loop.process ~model_id:"openai/gpt-5.4" ~messages:[] in
      match res with
      | `Assoc fields ->
          if List.assoc_opt "messages" fields = Some (`List []) then Pass
          else Fail "Empty messages input did not produce empty messages list"
      | _ -> Fail "Result not JSON object");

  reg "t2.cnv.2" "Negative max_turns in init_state (clamped safely)"
    "agent_loop.conversation_loop" (fun () ->
      let st = Conversation_loop.init_state ~model_id:"m" ~max_turns:(-3) in
      let res = Turn_budget.consume st.budget in
      if not res.allowed then Pass
      else Fail "Negative max_turns allowed consumption");

  reg "t2.cnv.3" "Budget exhaustion during step_turn transitions to Interrupted"
    "agent_loop.conversation_loop" (fun () ->
      let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:1 in
      let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "turn 1") ] ] in
      let st1, _ = Conversation_loop.step_turn st0 ~messages:msgs in
      let st2, _ = Conversation_loop.step_turn st1 ~messages:msgs in
      if st2.step = Conversation_loop.Interrupted then Pass
      else Fail "Budget exhaustion did not set state to Interrupted");

  reg "t2.cnv.4" "Process with empty provider model string"
    "agent_loop.conversation_loop" (fun () ->
      let res = Conversation_loop.process ~model_id:"" ~messages:[] in
      match res with
      | `Assoc fields ->
          if List.assoc_opt "model" fields = Some (`String "") then Pass
          else Fail "Empty model string handling failed"
      | _ -> Fail "Result not JSON object");

  reg "t2.cnv.5" "Step turn on assistant message with malformed tool_calls"
    "agent_loop.conversation_loop" (fun () ->
      let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:5 in
      let bad_msg = `Assoc [ ("role", `String "assistant"); ("tool_calls", `Null) ] in
      let st1, _ = Conversation_loop.step_turn st0 ~messages:[ bad_msg ] in
      if st1.step = Conversation_loop.Complete then Pass
      else Fail "Malformed tool_calls null did not fall back safely");

  (* ========================================================================= *)
  (* 4. agent_loop.prompt_assembly (5 Tier 2 TCs)                             *)
  (* ========================================================================= *)
  reg "t2.prm.1" "System message positioned after user message"
    "agent_loop.prompt_assembly" (fun () ->
      let msgs =
        [
          `Assoc [ ("role", `String "user"); ("content", `String "Hi") ];
          `Assoc [ ("role", `String "system"); ("content", `String "Sys") ];
        ]
      in
      let formatted = Prompt_assembly.apply_developer_role ~model_id:"openai/gpt-5.4" msgs in
      match formatted with
      | [ _; `Assoc fields ] ->
          if List.assoc_opt "role" fields = Some (`String "system") then Pass
          else Fail "Non-index-0 system message was modified"
      | _ -> Fail "Message list structure invalid");

  reg "t2.prm.2" "Model name string with uppercase/mixed case"
    "agent_loop.prompt_assembly" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "system"); ("content", `String "Sys") ] ] in
      let formatted = Prompt_assembly.apply_developer_role ~model_id:"OPENAI/GPT-5.4" msgs in
      match formatted with
      | [ `Assoc fields ] ->
          if List.assoc_opt "role" fields = Some (`String "developer") then Pass
          else Fail "Uppercase model name failed developer role detection"
      | _ -> Fail "Formatted message structure invalid");

  reg "t2.prm.3" "Empty prompt config with zero tools and empty messages"
    "agent_loop.prompt_assembly" (fun () ->
      let res = Prompt_assembly.assemble ~model_id:"openai/gpt-5.4" ~messages:[] in
      match res with
      | `Assoc fields ->
          if List.assoc_opt "messages" fields = Some (`List []) then Pass
          else Fail "Empty messages assembly output failed"
      | _ -> Fail "Result not JSON object");

  reg "t2.prm.4" "Model without developer role leaves system role intact"
    "agent_loop.prompt_assembly" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "system"); ("content", `String "Sys") ] ] in
      let formatted = Prompt_assembly.apply_developer_role ~model_id:"anthropic/claude-3-5-sonnet" msgs in
      match formatted with
      | [ `Assoc fields ] ->
          if List.assoc_opt "role" fields = Some (`String "system") then Pass
          else Fail "System role changed for non-developer model"
      | _ -> Fail "Message structure invalid");

  reg "t2.prm.5" "Non-Assoc elements in message list handled safely"
    "agent_loop.prompt_assembly" (fun () ->
      let msgs = [ `String "raw_string_msg" ] in
      let formatted = Prompt_assembly.apply_developer_role ~model_id:"openai/gpt-5.4" msgs in
      if formatted = msgs then Pass
      else Fail "Non-assoc message node changed by prompt assembly");

  (* ========================================================================= *)
  (* 5. agent_loop.context_engine (5 Tier 2 TCs)                               *)
  (* ========================================================================= *)
  reg "t2.ctx.1" "Add reference causing total tokens to exceed max"
    "agent_loop.context_engine" (fun () ->
      let st0 = Context_engine.create ~max_context_tokens:100 in
      let r1 = { Context_engine.ref_id = "huge"; kind = "file"; uri = "a"; content = "big"; token_count = 500 } in
      let st1 = Context_engine.add_reference st0 r1 in
      if st1.total_tokens = 500 && st1.total_tokens > st1.max_context_tokens then Pass
      else Fail "Token count overflow tracking failed");

  reg "t2.ctx.2" "Remove reference from empty context state"
    "agent_loop.context_engine" (fun () ->
      let st0 = Context_engine.create ~max_context_tokens:1000 in
      let st1 = Context_engine.remove_reference st0 ~ref_id:"non_existent" in
      if st1.total_tokens = 0 && st1.active_references = [] then Pass
      else Fail "Removing reference from empty state corrupted context state");

  reg "t2.ctx.3" "Add reference with negative token count (clamped)"
    "agent_loop.context_engine" (fun () ->
      let st0 = Context_engine.create ~max_context_tokens:1000 in
      let r1 = { Context_engine.ref_id = "neg"; kind = "file"; uri = "a"; content = "a"; token_count = (-50) } in
      let st1 = Context_engine.add_reference st0 r1 in
      if st1.total_tokens = 0 then Pass
      else Fail "Negative token count was not clamped to zero");

  reg "t2.ctx.4" "Duplicate reference ID deduplication and update"
    "agent_loop.context_engine" (fun () ->
      let st0 = Context_engine.create ~max_context_tokens:1000 in
      let r1 = { Context_engine.ref_id = "same"; kind = "file"; uri = "a"; content = "a"; token_count = 100 } in
      let r2 = { Context_engine.ref_id = "same"; kind = "file"; uri = "a"; content = "updated"; token_count = 200 } in
      let st1 = Context_engine.add_reference st0 r1 in
      let st2 = Context_engine.add_reference st1 r2 in
      if List.length st2.active_references = 1 && st2.total_tokens = 200 then Pass
      else Fail "Deduplication of duplicate ref_id failed");

  reg "t2.ctx.5" "Negative max_context_tokens in create (clamped)"
    "agent_loop.context_engine" (fun () ->
      let st = Context_engine.create ~max_context_tokens:(-100) in
      if st.max_context_tokens = 0 && st.total_tokens = 0 then Pass
      else Fail "Negative max_context_tokens was not clamped to zero");

  (* ========================================================================= *)
  (* 6. agent_loop.context_compression (5 Tier 2 TCs)                         *)
  (* ========================================================================= *)
  reg "t2.cmp.1" "Compress empty message list []"
    "agent_loop.context_compression" (fun () ->
      let strat = Context_compression.Truncate_oldest { keep_last_n = 5 } in
      let res = Context_compression.compress_history ~strategy:strat [] in
      if res.original_count = 0 && res.compressed_count = 0 && res.tokens_saved = 0 then Pass
      else Fail "Compress empty list failed");

  reg "t2.cmp.2" "Compress history where List.length msgs < keep_last_n"
    "agent_loop.context_compression" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "Short") ] ] in
      let strat = Context_compression.Truncate_oldest { keep_last_n = 5 } in
      let res = Context_compression.compress_history ~strategy:strat msgs in
      if res.original_count = 1 && res.compressed_count = 1 && res.tokens_saved = 0 then Pass
      else Fail "Compress history with length < keep_last_n modified messages");

  reg "t2.cmp.3" "Compress history consisting entirely of system messages"
    "agent_loop.context_compression" (fun () ->
      let sys1 = `Assoc [ ("role", `String "system"); ("content", `String "Sys 1") ] in
      let sys2 = `Assoc [ ("role", `String "developer"); ("content", `String "Sys 2") ] in
      let strat = Context_compression.Truncate_oldest { keep_last_n = 1 } in
      let res = Context_compression.compress_history ~strategy:strat [ sys1; sys2 ] in
      if res.compressed_count >= 1 then Pass
      else Fail "System messages list compression failed");

  reg "t2.cmp.4" "Compress with keep_last_n = 0"
    "agent_loop.context_compression" (fun () ->
      let sys = `Assoc [ ("role", `String "system"); ("content", `String "Sys") ] in
      let u1 = `Assoc [ ("role", `String "user"); ("content", `String "U1") ] in
      let strat = Context_compression.Truncate_oldest { keep_last_n = 0 } in
      let res = Context_compression.compress_history ~strategy:strat [ sys; u1 ] in
      if res.compressed_count = 1 && res.compressed_messages = [ sys ] then Pass
      else Fail "keep_last_n = 0 did not drop all non-system messages");

  reg "t2.cmp.5" "Summarization of single non-system message (no-op fallback)"
    "agent_loop.context_compression" (fun () ->
      let u1 = `Assoc [ ("role", `String "user"); ("content", `String "U1") ] in
      let strat = Context_compression.Summarize_history { summary_prefix = "P:" } in
      let res = Context_compression.compress_history ~strategy:strat [ u1 ] in
      if res.compressed_count = 1 && res.tokens_saved = 0 then Pass
      else Fail "Summarizing single message should be a no-op");

  (* ========================================================================= *)
  (* 7. agent_loop.turn_finalization (5 Tier 2 TCs)                           *)
  (* ========================================================================= *)
  reg "t2.fin.1" "Finalize turn with 0 turns executed and 0 tokens"
    "agent_loop.turn_finalization" (fun () ->
      let r = Turn_finalization.create_receipt ~turn_id:"zero" ~status:"success" ~turns:0 ~tokens:0 ~final_output:None in
      if r.turns_executed = 0 && r.total_tokens_used = 0 && r.turn_id = "zero" then Pass
      else Fail "Zero turn/token receipt creation failed");

  reg "t2.fin.2" "Finalize turn with negative turns/tokens (clamped safely)"
    "agent_loop.turn_finalization" (fun () ->
      let r = Turn_finalization.create_receipt ~turn_id:"neg" ~status:"error" ~turns:(-5) ~tokens:(-100) ~final_output:None in
      if r.turns_executed = 0 && r.total_tokens_used = 0 then Pass
      else Fail "Negative turns/tokens were not clamped to 0");

  reg "t2.fin.3" "Finalize turn with final_output = None"
    "agent_loop.turn_finalization" (fun () ->
      let r = Turn_finalization.create_receipt ~turn_id:"t3" ~status:"timeout" ~turns:1 ~tokens:10 ~final_output:None in
      if r.final_output = None && r.status = "timeout" then Pass
      else Fail "final_output None receipt creation failed");

  reg "t2.fin.4" "Empty turn_id string (clamped safely to unknown)"
    "agent_loop.turn_finalization" (fun () ->
      let r = Turn_finalization.create_receipt ~turn_id:"" ~status:"success" ~turns:1 ~tokens:10 ~final_output:None in
      if r.turn_id = "unknown" then Pass
      else Fail "Empty turn_id was not clamped to default 'unknown'");

  reg "t2.fin.5" "Finalization metadata with empty key or complex JSON"
    "agent_loop.turn_finalization" (fun () ->
      let r = Turn_finalization.create_receipt ~turn_id:"t5" ~status:"success" ~turns:1 ~tokens:10 ~final_output:None in
      let meta = [ ("", `Null); ("complex", `Assoc [ ("a", `Int 1) ]) ] in
      let summary = Turn_finalization.summarize r ~metadata:meta in
      if List.length summary.metadata = 2 then Pass
      else Fail "Complex metadata summary failed")

