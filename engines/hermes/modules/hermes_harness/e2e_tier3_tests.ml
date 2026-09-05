open E2e_framework

let reg id name feature run =
  register_test { id; name; tier = Tier3_Pairwise; feature; run }

let register_all () =
  (* ========================================================================= *)
  (* 1. t3.pair.hyg_prm: Sanitized messages assembled into system prompt       *)
  (* ========================================================================= *)
  reg "t3.pair.hyg_prm" "Sanitized messages assembled into system prompt"
    "agent_loop.message_hygiene" (fun () ->
      let surrogate_str = "Instruction \237\160\128" in
      let raw_msgs =
        [
          `Assoc [ ("role", `String "system"); ("content", `String surrogate_str) ];
          `Assoc
            [
              ("role", `String "user");
              ("content", `String "Hello");
              ("_internal_id", `String "secret_123");
              ("codex_reasoning_items", `List [ `String "thought" ]);
            ];
        ]
      in
      let sanitized = Message_hygiene.sanitize_messages ~model_id:"openai/gpt-5.4" raw_msgs in
      let assembled = Prompt_assembly.assemble ~model_id:"openai/gpt-5.4" ~messages:sanitized in
      match assembled with
      | `Assoc fields -> (
          match List.assoc_opt "messages" fields with
          | Some (`List msgs) -> (
              match msgs with
              | `Assoc sys_fields :: `Assoc user_fields :: [] ->
                  let sys_role_ok = List.assoc_opt "role" sys_fields = Some (`String "developer") in
                  let sys_content_ok =
                    match List.assoc_opt "content" sys_fields with
                    | Some (`String s) -> String.contains s '\239'
                    | _ -> false
                  in
                  let user_no_secret = not (List.mem_assoc "_internal_id" user_fields) in
                  let user_no_codex = not (List.mem_assoc "codex_reasoning_items" user_fields) in
                  if sys_role_ok && sys_content_ok && user_no_secret && user_no_codex then Pass
                  else Fail "Sanitization or prompt assembly pairwise interaction failed"
              | _ -> Fail "Assembled messages list length or structure mismatch")
          | _ -> Fail "Assembled prompt missing messages list")
      | _ -> Fail "Assembled result is not JSON object");

  (* ========================================================================= *)
  (* 2. t3.pair.int_cnv: Interrupt budget consumed inside conversation turn loop*)
  (* ========================================================================= *)
  reg "t3.pair.int_cnv" "Interrupt budget consumed inside conversation turn loop"
    "agent_loop.interrupt_control" (fun () ->
      let b0 = Turn_budget.create 2 in
      let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:5 in
      let tool_msg =
        `Assoc
          [
            ("role", `String "assistant");
            ("tool_calls", `List [ `Assoc [ ("id", `String "c1"); ("type", `String "function") ] ]);
          ]
      in
      let r1 = Turn_budget.consume b0 in
      let st1, _ = Conversation_loop.step_turn st0 ~messages:[ tool_msg ] in
      let r2 = Turn_budget.consume r1.budget in
      let st2, _ = Conversation_loop.step_turn st1 ~messages:[ tool_msg ] in
      let r3 = Turn_budget.consume r2.budget in
      if r1.allowed && r2.allowed && not r3.allowed &&
         Turn_budget.used r3.budget = 2 && Turn_budget.remaining r3.budget = 0 &&
         st2.step = Conversation_loop.ToolCall then Pass
      else Fail "Interrupt budget and conversation turn loop interaction failed");

  (* ========================================================================= *)
  (* 3. t3.pair.ctx_cmp: Context engine references compressed when token budget is exceeded *)
  (* ========================================================================= *)
  reg "t3.pair.ctx_cmp" "Context engine references compressed when token budget is exceeded"
    "agent_loop.context_engine" (fun () ->
      let ce0 = Context_engine.create ~max_context_tokens:500 in
      let ref1 = { Context_engine.ref_id = "r1"; kind = "file"; uri = "f1.txt"; content = "Data 1"; token_count = 200 } in
      let ref2 = { Context_engine.ref_id = "r2"; kind = "tool"; uri = "t1"; content = "Data 2"; token_count = 200 } in
      let ref3 = { Context_engine.ref_id = "r3"; kind = "file"; uri = "f2.txt"; content = "Data 3"; token_count = 200 } in
      let ce1 = Context_engine.add_reference ce0 ref1 in
      let ce2 = Context_engine.add_reference ce1 ref2 in
      let ce3 = Context_engine.add_reference ce2 ref3 in
      if ce3.total_tokens > ce3.max_context_tokens then
        let msgs =
          List.map
            (fun (r : Context_engine.context_reference) ->
              `Assoc [ ("role", `String "user"); ("content", `String r.content) ])
            ce3.active_references
        in
        let strat = Context_compression.Truncate_oldest { keep_last_n = 2 } in
        let comp_res = Context_compression.compress_history ~strategy:strat msgs in
        if comp_res.original_count = 3 && comp_res.compressed_count = 2 && comp_res.tokens_saved = 10 then Pass
        else Fail "Context engine reference compression failed"
      else Fail "Total tokens did not exceed max_context_tokens threshold");

  (* ========================================================================= *)
  (* 4. t3.pair.cnv_fin: Conversation turn finalization generates completion receipt *)
  (* ========================================================================= *)
  reg "t3.pair.cnv_fin" "Conversation turn finalization generates completion receipt"
    "agent_loop.conversation_loop" (fun () ->
      let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:5 in
      let assistant_msg = `Assoc [ ("role", `String "assistant"); ("content", `String "Final answer") ] in
      let st1, _ = Conversation_loop.step_turn st0 ~messages:[ assistant_msg ] in
      if Conversation_loop.is_complete st1 then
        let turns_count = Turn_budget.used st1.budget in
        let r = Turn_finalization.create_receipt ~turn_id:"turn_cnv_fin_1" ~status:"success" ~turns:turns_count ~tokens:350 ~final_output:(Some "Final answer") in
        let meta = [ ("model", `String st1.model_id) ] in
        let summary = Turn_finalization.summarize r ~metadata:meta in
        if summary.receipt.turn_id = "turn_cnv_fin_1" && summary.receipt.status = "success" &&
           summary.receipt.turns_executed = 1 && summary.receipt.total_tokens_used = 350 &&
           List.assoc_opt "model" summary.metadata = Some (`String "openai/gpt-5.4") then Pass
        else Fail "Turn finalization receipt fields mismatch"
      else Fail "Conversation step turn did not reach complete status");

  (* ========================================================================= *)
  (* 5. t3.pair.prm_ctx: Prompt assembly with injected tool context references  *)
  (* ========================================================================= *)
  reg "t3.pair.prm_ctx" "Prompt assembly with injected tool context references"
    "agent_loop.prompt_assembly" (fun () ->
      let ce0 = Context_engine.create ~max_context_tokens:4096 in
      let ref_tool = { Context_engine.ref_id = "tc_out"; kind = "tool"; uri = "tool://bash"; content = "ls -la output"; token_count = 50 } in
      let ce1 = Context_engine.add_reference ce0 ref_tool in
      let sys_msg = `Assoc [ ("role", `String "system"); ("content", `String "System prompt") ] in
      let ctx_msgs =
        List.map
          (fun (r : Context_engine.context_reference) ->
            `Assoc [ ("role", `String "user"); ("content", `String ("Tool Context: " ^ r.content)) ])
          ce1.active_references
      in
      let all_msgs = sys_msg :: ctx_msgs in
      let assembled = Prompt_assembly.assemble ~model_id:"openai/gpt-5.4" ~messages:all_msgs in
      match assembled with
      | `Assoc fields -> (
          match List.assoc_opt "messages" fields with
          | Some (`List [ `Assoc sys_fields; `Assoc ctx_fields ]) ->
              let sys_dev = List.assoc_opt "role" sys_fields = Some (`String "developer") in
              let ctx_content =
                match List.assoc_opt "content" ctx_fields with
                | Some (`String s) -> String.length s > 0 && String.contains s 'l'
                | _ -> false
              in
              if sys_dev && ctx_content then Pass
              else Fail "Prompt assembly with injected context validation failed"
          | _ -> Fail "Assembled messages list length mismatch")
      | _ -> Fail "Assembled result is not JSON object");

  (* ========================================================================= *)
  (* 6. t3.pair.cmp_fin: Compressed context history finalized with turn receipt summary *)
  (* ========================================================================= *)
  reg "t3.pair.cmp_fin" "Compressed context history finalized with turn receipt summary"
    "agent_loop.context_compression" (fun () ->
      let msgs =
        List.init 8 (fun i ->
            `Assoc [ ("role", `String "user"); ("content", `String ("History item " ^ string_of_int i)) ])
      in
      let strat = Context_compression.Truncate_oldest { keep_last_n = 3 } in
      let comp_res = Context_compression.compress_history ~strategy:strat msgs in
      let r = Turn_finalization.create_receipt ~turn_id:"turn_cmp_fin" ~status:"success" ~turns:8 ~tokens:240 ~final_output:(Some "Compressed result") in
      let meta =
        [
          ("original_messages", `Int comp_res.original_count);
          ("compressed_messages", `Int comp_res.compressed_count);
          ("tokens_saved", `Int comp_res.tokens_saved);
        ]
      in
      let summary = Turn_finalization.summarize r ~metadata:meta in
      if summary.receipt.turn_id = "turn_cmp_fin" &&
         List.assoc_opt "original_messages" summary.metadata = Some (`Int 8) &&
         List.assoc_opt "compressed_messages" summary.metadata = Some (`Int 3) &&
         List.assoc_opt "tokens_saved" summary.metadata = Some (`Int 50) then Pass
      else Fail "Compressed context finalization summary metadata mismatch");

  (* ========================================================================= *)
  (* 7. t3.prop.fuzz: QCheck property test verifying budget invariants        *)
  (* ========================================================================= *)
  reg "t3.prop.fuzz" "QCheck property test verifying budget clamping and state invariant preservation"
    "agent_loop.turn_finalization" (fun () ->
      let open QCheck in
      let op_gen =
        Gen.oneof
          [
            Gen.map (fun max -> `Create max) Gen.nat_small;
            Gen.return `Consume;
            Gen.return `Refund;
          ]
      in
      let ops_gen = Gen.list_size (Gen.int_range 1 30) op_gen in
      let arbitrary_ops = make ops_gen in
      let prop ops =
        let init_b = Turn_budget.create 10 in
        let final_b =
          List.fold_left
            (fun b op ->
              match op with
              | `Create max -> Turn_budget.create max
              | `Consume -> (Turn_budget.consume b).budget
              | `Refund -> Turn_budget.refund b)
            init_b ops
        in
        let u = Turn_budget.used final_b in
        let r = Turn_budget.remaining final_b in
        u >= 0 && r >= 0
      in
      let qcheck_test = Test.make ~count:100 ~name:"budget_invariants" arbitrary_ops prop in
      match Test.check_exn qcheck_test with
      | () -> Pass
      | exception e -> Fail ("QCheck property failed: " ^ Printexc.to_string e));
  7
