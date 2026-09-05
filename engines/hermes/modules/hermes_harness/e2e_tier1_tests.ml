open E2e_framework

let reg id name feature run =
  register_test { id; name; tier = Tier1_Feature; feature; run }

let register_all () =
  (* ========================================================================= *)
  (* 1. agent_loop.message_hygiene (5 Tier 1 TCs)                              *)
  (* ========================================================================= *)
  reg "t1.hyg.1" "Basic message sanitization with role and content"
    "agent_loop.message_hygiene" (fun () ->
      let msg = `Assoc [ ("role", `String "user"); ("content", `String "Hello world") ] in
      let sanitized = Message_hygiene.sanitize_message ~model_id:"openai/gpt-5.4" msg in
      match sanitized with
      | `Assoc fields ->
          if List.assoc_opt "role" fields = Some (`String "user") &&
             List.assoc_opt "content" fields = Some (`String "Hello world") then Pass
          else Fail "Role or content field corrupted"
      | _ -> Fail "Sanitized message is not an object");

  reg "t1.hyg.2" "Strip private fields starting with _"
    "agent_loop.message_hygiene" (fun () ->
      let msg =
        `Assoc
          [
            ("role", `String "user");
            ("content", `String "Test");
            ("_internal_id", `String "secret_123");
            ("_debug_info", `Bool true);
          ]
      in
      let sanitized = Message_hygiene.sanitize_message ~model_id:"openai/gpt-5.4" msg in
      match sanitized with
      | `Assoc fields ->
          if List.mem_assoc "_internal_id" fields || List.mem_assoc "_debug_info" fields then
            Fail "Private keys starting with _ were not stripped"
          else Pass
      | _ -> Fail "Sanitized message is not an object");

  reg "t1.hyg.3" "Strip codex reasoning and message items"
    "agent_loop.message_hygiene" (fun () ->
      let msg =
        `Assoc
          [
            ("role", `String "assistant");
            ("content", `String "Result");
            ("codex_reasoning_items", `List [ `String "step 1" ]);
            ("codex_message_items", `List [ `String "item 1" ]);
          ]
      in
      let sanitized = Message_hygiene.sanitize_message ~model_id:"openai/gpt-5.4" msg in
      match sanitized with
      | `Assoc fields ->
          if List.mem_assoc "codex_reasoning_items" fields || List.mem_assoc "codex_message_items" fields then
            Fail "Codex tracking fields were not stripped"
          else Pass
      | _ -> Fail "Sanitized message is not an object");

  reg "t1.hyg.4" "Strip call_id and response_item_id for non-Gemini models"
    "agent_loop.message_hygiene" (fun () ->
      let tool_call =
        `Assoc
          [
            ("id", `String "call_1");
            ("type", `String "function");
            ("call_id", `String "internal_call");
            ("response_item_id", `String "resp_123");
          ]
      in
      let sanitized = Message_hygiene.sanitize_tool_call ~keep_thought_signature:false tool_call in
      match sanitized with
      | `Assoc fields ->
          if List.mem_assoc "call_id" fields || List.mem_assoc "response_item_id" fields then
            Fail "Thought signature fields call_id/response_item_id were not stripped for non-Gemini"
          else Pass
      | _ -> Fail "Tool call is not an object");

  reg "t1.hyg.5" "Retain extra_content for Gemini models"
    "agent_loop.message_hygiene" (fun () ->
      let tool_call =
        `Assoc
          [
            ("id", `String "call_gemini");
            ("type", `String "function");
            ("extra_content", `String "thought_signature_payload");
          ]
      in
      let is_gemini = Message_hygiene.model_consumes_thought_signature "google/gemini-2.5-pro" in
      let sanitized = Message_hygiene.sanitize_tool_call ~keep_thought_signature:is_gemini tool_call in
      match sanitized with
      | `Assoc fields ->
          if List.mem_assoc "extra_content" fields then Pass
          else Fail "extra_content was erroneously stripped for Gemini model"
      | _ -> Fail "Tool call is not an object");

  (* ========================================================================= *)
  (* 2. agent_loop.interrupt_control (5 Tier 1 TCs)                            *)
  (* ========================================================================= *)
  reg "t1.int.1" "Create turn budget and verify initial state"
    "agent_loop.interrupt_control" (fun () ->
      let b = Turn_budget.create 5 in
      if Turn_budget.used b = 0 && Turn_budget.remaining b = 5 && b.maximum = 5 then Pass
      else Fail "Initial budget state mismatch");

  reg "t1.int.2" "Consume iteration and verify usage update"
    "agent_loop.interrupt_control" (fun () ->
      let b0 = Turn_budget.create 3 in
      let res = Turn_budget.consume b0 in
      if res.allowed && Turn_budget.used res.budget = 1 && Turn_budget.remaining res.budget = 2 then Pass
      else Fail "Consume operation did not update budget state correctly");

  reg "t1.int.3" "Consume until budget exhaustion"
    "agent_loop.interrupt_control" (fun () ->
      let b0 = Turn_budget.create 2 in
      let res1 = Turn_budget.consume b0 in
      let res2 = Turn_budget.consume res1.budget in
      let res3 = Turn_budget.consume res2.budget in
      if res1.allowed && res2.allowed && not res3.allowed && Turn_budget.used res3.budget = 2 then Pass
      else Fail "Budget exhaustion boundary failed");

  reg "t1.int.4" "Refund budget consumption"
    "agent_loop.interrupt_control" (fun () ->
      let b0 = Turn_budget.create 4 in
      let res1 = Turn_budget.consume b0 in
      let b_refunded = Turn_budget.refund res1.budget in
      if Turn_budget.used b_refunded = 0 && Turn_budget.remaining b_refunded = 4 then Pass
      else Fail "Refund did not restore budget iteration count");

  reg "t1.int.5" "Verify budget state projection"
    "agent_loop.interrupt_control" (fun () ->
      let b = Turn_budget.create 10 in
      let res = Turn_budget.consume b in
      if Turn_budget.used res.budget + Turn_budget.remaining res.budget = 10 then Pass
      else Fail "Budget sum invariant used + remaining = max failed");

  (* ========================================================================= *)
  (* 3. agent_loop.conversation_loop (5 Tier 1 TCs)                           *)
  (* ========================================================================= *)
  reg "t1.cnv.1" "Initialize conversation loop state"
    "agent_loop.conversation_loop" (fun () ->
      let st = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:5 in
      if st.step = Conversation_loop.Init && st.model_id = "openai/gpt-5.4" && st.message_count = 0 then Pass
      else Fail "Conversation loop initialization state mismatch");

  reg "t1.cnv.2" "Step state machine on assistant text response"
    "agent_loop.conversation_loop" (fun () ->
      let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:5 in
      let msgs = [ `Assoc [ ("role", `String "assistant"); ("content", `String "Hello") ] ] in
      let st1, sanitized = Conversation_loop.step_turn st0 ~messages:msgs in
      if st1.step = Conversation_loop.Complete && List.length sanitized = 1 then Pass
      else Fail "Step turn assistant response did not reach Complete state");

  reg "t1.cnv.3" "Step state machine on tool call response"
    "agent_loop.conversation_loop" (fun () ->
      let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:5 in
      let tool_msg =
        `Assoc
          [
            ("role", `String "assistant");
            ("tool_calls", `List [ `Assoc [ ("id", `String "call_1"); ("type", `String "function") ] ]);
          ]
      in
      let st1, _ = Conversation_loop.step_turn st0 ~messages:[ tool_msg ] in
      if st1.step = Conversation_loop.ToolCall then Pass
      else Fail "Step turn tool calls response did not reach ToolCall state");

  reg "t1.cnv.4" "Process single-turn request into canonical JSON"
    "agent_loop.conversation_loop" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "Hi") ] ] in
      let res = Conversation_loop.process ~model_id:"openai/gpt-5.4" ~messages:msgs in
      match res with
      | `Assoc fields ->
          if List.assoc_opt "model" fields = Some (`String "openai/gpt-5.4") &&
             List.mem_assoc "messages" fields then Pass
          else Fail "Process JSON output fields mismatch"
      | _ -> Fail "Process result is not JSON object");

  reg "t1.cnv.5" "Check state completion status helper"
    "agent_loop.conversation_loop" (fun () ->
      let st_init = Conversation_loop.init_state ~model_id:"m" ~max_turns:1 in
      let is_c0 = Conversation_loop.is_complete st_init in
      let st_comp = { st_init with step = Conversation_loop.Complete } in
      let is_c1 = Conversation_loop.is_complete st_comp in
      if not is_c0 && is_c1 then Pass
      else Fail "is_complete check failed");

  (* ========================================================================= *)
  (* 4. agent_loop.prompt_assembly (5 Tier 1 TCs)                             *)
  (* ========================================================================= *)
  reg "t1.prm.1" "Format system role as developer for GPT-5 model"
    "agent_loop.prompt_assembly" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "system"); ("content", `String "Instructions") ] ] in
      let formatted = Prompt_assembly.apply_developer_role ~model_id:"openai/gpt-5.4" msgs in
      match formatted with
      | [ `Assoc fields ] ->
          if List.assoc_opt "role" fields = Some (`String "developer") then Pass
          else Fail "System role was not mapped to developer for gpt-5"
      | _ -> Fail "Formatted message structure invalid");

  reg "t1.prm.2" "Format system role as system for Claude model"
    "agent_loop.prompt_assembly" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "system"); ("content", `String "Instructions") ] ] in
      let formatted = Prompt_assembly.apply_developer_role ~model_id:"anthropic/claude-sonnet-4.5" msgs in
      match formatted with
      | [ `Assoc fields ] ->
          if List.assoc_opt "role" fields = Some (`String "system") then Pass
          else Fail "System role was erroneously changed for Claude model"
      | _ -> Fail "Formatted message structure invalid");

  reg "t1.prm.3" "Format system role as developer for Codex model"
    "agent_loop.prompt_assembly" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "system"); ("content", `String "Code prompt") ] ] in
      let formatted = Prompt_assembly.apply_developer_role ~model_id:"openai/codex-mini" msgs in
      match formatted with
      | [ `Assoc fields ] ->
          if List.assoc_opt "role" fields = Some (`String "developer") then Pass
          else Fail "System role was not mapped to developer for codex"
      | _ -> Fail "Formatted message structure invalid");

  reg "t1.prm.4" "Assemble prompt with developer role formatting"
    "agent_loop.prompt_assembly" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "system"); ("content", `String "Sys") ] ] in
      let assembled = Prompt_assembly.assemble ~model_id:"openai/gpt-5.4" ~messages:msgs in
      match assembled with
      | `Assoc fields -> (
          match List.assoc_opt "messages" fields with
          | Some (`List [ `Assoc msg_fields ]) ->
              if List.assoc_opt "role" msg_fields = Some (`String "developer") then Pass
              else Fail "Assembled message role is not developer"
          | _ -> Fail "Assembled messages list invalid")
      | _ -> Fail "Assemble result is not object");

  reg "t1.prm.5" "Assemble prompt JSON output structure"
    "agent_loop.prompt_assembly" (fun () ->
      let res = Prompt_assembly.assemble ~model_id:"model_a" ~messages:[] in
      match res with
      | `Assoc fields ->
          if List.assoc_opt "model" fields = Some (`String "model_a") then Pass
          else Fail "Model ID mismatch in assemble"
      | _ -> Fail "Result not JSON object");

  (* ========================================================================= *)
  (* 5. agent_loop.context_engine (5 Tier 1 TCs)                               *)
  (* ========================================================================= *)
  reg "t1.ctx.1" "Initialize empty context state"
    "agent_loop.context_engine" (fun () ->
      let st = Context_engine.create ~max_context_tokens:8192 in
      if st.total_tokens = 0 && st.max_context_tokens = 8192 && st.active_references = [] then Pass
      else Fail "Context engine initial state mismatch");

  reg "t1.ctx.2" "Add file reference and track total tokens"
    "agent_loop.context_engine" (fun () ->
      let st0 = Context_engine.create ~max_context_tokens:8192 in
      let r1 = { Context_engine.ref_id = "f1"; kind = "file"; uri = "file:///a.txt"; content = "hello"; token_count = 100 } in
      let st1 = Context_engine.add_reference st0 r1 in
      if st1.total_tokens = 100 && List.length st1.active_references = 1 then Pass
      else Fail "Add reference did not update total tokens correctly");

  reg "t1.ctx.3" "Add tool output reference and accumulate tokens"
    "agent_loop.context_engine" (fun () ->
      let st0 = Context_engine.create ~max_context_tokens:8192 in
      let r1 = { Context_engine.ref_id = "f1"; kind = "file"; uri = "file:///a.txt"; content = "a"; token_count = 100 } in
      let r2 = { Context_engine.ref_id = "t1"; kind = "tool"; uri = "tool://exec"; content = "b"; token_count = 250 } in
      let st1 = Context_engine.add_reference st0 r1 in
      let st2 = Context_engine.add_reference st1 r2 in
      if st2.total_tokens = 350 && List.length st2.active_references = 2 then Pass
      else Fail "Token accumulation across references failed");

  reg "t1.ctx.4" "Remove reference by ID and update tokens"
    "agent_loop.context_engine" (fun () ->
      let st0 = Context_engine.create ~max_context_tokens:8192 in
      let r1 = { Context_engine.ref_id = "f1"; kind = "file"; uri = "a"; content = "a"; token_count = 100 } in
      let st1 = Context_engine.add_reference st0 r1 in
      let st2 = Context_engine.remove_reference st1 ~ref_id:"f1" in
      if st2.total_tokens = 0 && st2.active_references = [] then Pass
      else Fail "Remove reference did not deduct tokens correctly");

  reg "t1.ctx.5" "Process context engine candidate request"
    "agent_loop.context_engine" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "stub for context_engine") ] ] in
      let res = Context_engine.process ~model_id:"openai/gpt-5.4" ~messages:msgs in
      match res with
      | `Assoc fields ->
          if List.assoc_opt "model" fields = Some (`String "openai/gpt-5.4") then Pass
          else Fail "Context engine process output mismatch"
      | _ -> Fail "Result not JSON object");

  (* ========================================================================= *)
  (* 6. agent_loop.context_compression (5 Tier 1 TCs)                         *)
  (* ========================================================================= *)
  reg "t1.cmp.1" "Truncate history with keep_last_n strategy"
    "agent_loop.context_compression" (fun () ->
      let msgs =
        List.init 10 (fun i ->
            `Assoc [ ("role", `String "user"); ("content", `String ("Msg " ^ string_of_int i)) ])
      in
      let strat = Context_compression.Truncate_oldest { keep_last_n = 4 } in
      let res = Context_compression.compress_history ~strategy:strat msgs in
      if res.original_count = 10 && res.compressed_count = 4 && res.tokens_saved = 60 then Pass
      else Fail "Truncate_oldest strategy did not compress history as expected");

  reg "t1.cmp.2" "Preserve system message during truncation"
    "agent_loop.context_compression" (fun () ->
      let sys = `Assoc [ ("role", `String "system"); ("content", `String "Instructions") ] in
      let msgs =
        sys :: List.init 6 (fun i ->
            `Assoc [ ("role", `String "user"); ("content", `String ("Msg " ^ string_of_int i)) ])
      in
      let strat = Context_compression.Truncate_oldest { keep_last_n = 2 } in
      let res = Context_compression.compress_history ~strategy:strat msgs in
      match res.compressed_messages with
      | first :: _ when Context_compression.is_system_msg first ->
          if res.compressed_count = 3 then Pass else Fail "Compressed count mismatch"
      | _ -> Fail "System message was not preserved as leading message");

  reg "t1.cmp.3" "Summarize early history into summary block"
    "agent_loop.context_compression" (fun () ->
      let msgs =
        List.init 5 (fun i ->
            `Assoc [ ("role", `String "user"); ("content", `String ("Turn " ^ string_of_int i)) ])
      in
      let strat = Context_compression.Summarize_history { summary_prefix = "Summary:" } in
      let res = Context_compression.compress_history ~strategy:strat msgs in
      if res.compressed_count = 1 && res.tokens_saved > 0 then Pass
      else Fail "Summarize_history strategy failed");

  reg "t1.cmp.4" "Apply ephemeral prompt caching strategy"
    "agent_loop.context_compression" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "Test") ] ] in
      let strat = Context_compression.Cache_ephemeral_prompts in
      let res = Context_compression.compress_history ~strategy:strat msgs in
      match res.compressed_messages with
      | [ `Assoc fields ] ->
          if List.mem_assoc "cache_control" fields then Pass
          else Fail "cache_control annotation missing"
      | _ -> Fail "Compressed messages structure invalid");

  reg "t1.cmp.5" "Process context compression candidate request"
    "agent_loop.context_compression" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "stub for context_compression") ] ] in
      let res = Context_compression.compress ~model_id:"openai/gpt-5.4" ~messages:msgs in
      match res with
      | `Assoc fields ->
          if List.assoc_opt "model" fields = Some (`String "openai/gpt-5.4") then Pass
          else Fail "Context compression output mismatch"
      | _ -> Fail "Result not JSON object");

  (* ========================================================================= *)
  (* 7. agent_loop.turn_finalization (5 Tier 1 TCs)                           *)
  (* ========================================================================= *)
  reg "t1.fin.1" "Create turn receipt for successful turn"
    "agent_loop.turn_finalization" (fun () ->
      let r = Turn_finalization.create_receipt ~turn_id:"turn_1" ~status:"success" ~turns:3 ~tokens:450 ~final_output:(Some "Done") in
      if r.turn_id = "turn_1" && r.status = "success" && r.turns_executed = 3 && r.total_tokens_used = 450 then Pass
      else Fail "Turn receipt fields mismatch");

  reg "t1.fin.2" "Create turn receipt for interrupted turn"
    "agent_loop.turn_finalization" (fun () ->
      let r = Turn_finalization.create_receipt ~turn_id:"turn_2" ~status:"interrupted" ~turns:5 ~tokens:1000 ~final_output:None in
      if r.status = "interrupted" && r.final_output = None then Pass
      else Fail "Interrupted turn receipt creation failed");

  reg "t1.fin.3" "Summarize turn receipt with metadata"
    "agent_loop.turn_finalization" (fun () ->
      let r = Turn_finalization.create_receipt ~turn_id:"t" ~status:"success" ~turns:1 ~tokens:50 ~final_output:(Some "ok") in
      let meta = [ ("duration_ms", `Int 120) ] in
      let summary = Turn_finalization.summarize r ~metadata:meta in
      if summary.receipt.turn_id = "t" && List.length summary.metadata = 1 then Pass
      else Fail "Summarize receipt failed");

  reg "t1.fin.4" "Verify receipt fields execution count and tokens"
    "agent_loop.turn_finalization" (fun () ->
      let r = Turn_finalization.create_receipt ~turn_id:"t4" ~status:"success" ~turns:12 ~tokens:3400 ~final_output:None in
      if r.turns_executed = 12 && r.total_tokens_used = 3400 then Pass
      else Fail "Execution count or token usage verification failed");

  reg "t1.fin.5" "Finalize candidate request into JSON output"
    "agent_loop.turn_finalization" (fun () ->
      let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "stub for turn_finalization") ] ] in
      let res = Turn_finalization.finalize ~model_id:"openai/gpt-5.4" ~messages:msgs in
      match res with
      | `Assoc fields ->
          if List.assoc_opt "model" fields = Some (`String "openai/gpt-5.4") then Pass
          else Fail "Turn finalization process output mismatch"
      | _ -> Fail "Result not JSON object")

