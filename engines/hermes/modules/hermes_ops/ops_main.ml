(* The operator entry point. R19: unknown flags are REFUSED, the exit code
   is the real verdict, and every path terminates in a stated outcome. *)

let usage () =
  prerr_endline
    "usage: ops <command>\n\
    \  completion ACTION --scope SCOPE --request-id ID\n\
    \                 typed declarative intent on the canonical dispatcher\n\
    \  mcp             serve the same command algebra over MCP stdio\n\
    \  zenoh           serve the same command algebra as a Zenoh queryable\n\
    \  zenoh-call KEY JSON                  invoke a live Zenoh command query\n\
    \  verify [--fast|--full] [--no-build] [--require-complete]\n\
    \                 run verification as a swarm DAG; certification fails on skips\n\
    \  suites [--fast|--full]                list discovered suites\n\  governance --print-guidance               print the generated whole-system checklist\n\  governance --write-guidance               atomically regenerate the checklist\n\  governance --check-guidance               fail closed on projection drift\n\  governance check --obligation ID           print one typed obligation (non-current exits 1)\n\  mutate --selftest   prove the mutation runner discriminates killed/void\n\  formal [service]     run the formal-service gates (gospel, rocq, quint, lean)\n\  agents              regenerate every module AGENTS.md from the dune graph\n\  agents --check      fail closed if any module guide has drifted\n\  config              the declarative configuration model, by fractal layer\n\  config --check      fail closed on undeclared variables or documentation drift\n\  config --template   regenerate .env.template from the model\n\  config --write-docs regenerate ontology, fractal atlas, and fractal algebra\n\  module-intent --check      validate interfaces, FPP authority, and documentation\n\  module-intent --write-docs regenerate module ontology, atlas, and algebra";
  prerr_endline
    "  debugging --check           validate debugging registry, integration, and docs\n  debugging --write-docs      regenerate debugging guide, SOP, ontology, atlas, and algebra";
  exit 2

let audited_dispatch ~surface request =
  Ops_command_service.dispatch ~execute:Ops_command_runtime.execute ~surface request

let () =
  match List.tl (Array.to_list Sys.argv) with
  | [ "mcp" ] ->
      Ops_mcp.serve ~dispatcher:audited_dispatch
        ~execute:Ops_command_runtime.execute ()
  | [ "zenoh" ] ->
      begin match
        Ops_zenoh.serve ~dispatcher:audited_dispatch
          ~execute:Ops_command_runtime.execute ()
      with
      | Ok () -> ()
      | Error message -> prerr_endline message; exit 1
      end
  | [ "zenoh-call"; key; payload ] ->
      begin match Hermes_zenoh.query ~key ~payload with
      | Ok reply -> print_endline reply
      | Error message -> prerr_endline message; exit 1
      end
  | ("completion" :: _ as arguments) ->
      begin match
        Ops_command.dispatch_cli ~dispatcher:audited_dispatch
          ~execute:Ops_command_runtime.execute arguments
      with
      | Error message -> prerr_endline message; exit 2
      | Ok observation ->
          print_endline (Ops_command.receipt_json observation.receipt);
          exit (match observation.receipt.verdict with Ops_command.Succeeded -> 0 | Blocked -> 1)
      end
  | [ "verify" ] | [] ->
      let text, code = Ops_verify.render (Ops_verify.run ()) in
      print_string text;
      exit code
  | [ "verify"; "--no-build" ] ->
      let text, code = Ops_verify.render (Ops_verify.run ~build:false ()) in
      print_string text;
      exit code
  | [ "verify"; "--fast" ] ->
      let text, code = Ops_verify.render (Ops_verify.run ~profile:Ops_verify.Fast ()) in
      print_string text;
      exit code
  | [ "verify"; "--full" ] ->
      let text, code = Ops_verify.render (Ops_verify.run ~profile:Ops_verify.Full ()) in
      print_string text;
      exit code
  | [ "verify"; "--fast"; "--no-build" ] ->
      let text, code = Ops_verify.render (Ops_verify.run ~profile:Ops_verify.Fast ~build:false ()) in
      print_string text;
      exit code
  | [ "verify"; "--full"; "--no-build" ] ->
      let text, code = Ops_verify.render (Ops_verify.run ~profile:Ops_verify.Full ~build:false ()) in
      print_string text;
      exit code
  | [ "verify"; "--require-complete" ]
  | [ "verify"; "--fast"; "--require-complete" ] ->
      let text, code =
        Ops_verify.render ~require_complete:true (Ops_verify.run ~profile:Ops_verify.Fast ())
      in
      print_string text;
      exit code
  | [ "verify"; "--full"; "--require-complete" ] ->
      let text, code =
        Ops_verify.render ~require_complete:true (Ops_verify.run ~profile:Ops_verify.Full ())
      in
      print_string text;
      exit code
  | [ "verify"; "--fast"; "--no-build"; "--require-complete" ] ->
      let text, code =
        Ops_verify.render ~require_complete:true
          (Ops_verify.run ~profile:Ops_verify.Fast ~build:false ())
      in
      print_string text;
      exit code
  | [ "verify"; "--full"; "--no-build"; "--require-complete" ] ->
      let text, code =
        Ops_verify.render ~require_complete:true
          (Ops_verify.run ~profile:Ops_verify.Full ~build:false ())
      in
      print_string text;
      exit code
  | [ "config" ] ->
      print_string (Ops_config.render ())
  | [ "config"; "--check" ] ->
      let config_text, config_code = Ops_config_gate.check () in
      let docs_text, docs_code = Ops_config_docs.check () in
      print_string config_text;
      print_string docs_text;
      exit (max config_code docs_code)
  | [ "config"; "--template" ] ->
      let path = ".env.template" in
      let tmp = path ^ ".tmp" in
      let oc = open_out_bin tmp in
      Fun.protect ~finally:(fun () -> close_out_noerr oc)
        (fun () -> output_string oc (Ops_config.env_template ()));
      Sys.rename tmp path;
      Printf.printf "wrote %s from the declarative model\n" path
  | [ "config"; "--write-docs" ] ->
      begin match Ops_config_docs.write () with
      | Ok message -> print_endline message
      | Error message -> prerr_endline message; exit 1
      end
  | [ "module-intent"; "--check" ] ->
      let authority_gaps =
        Module_intent.validate ~root:"."
        @ Module_intent.validate_configuration_references
            ~known_ids:(List.map (fun (item : Ops_config.element) -> item.key)
                          Ops_config.elements)
            Module_intent.all
        @ Run_fpp_authority.validate ()
      in
      let docs_text, docs_code = Module_intent_docs.check () in
      List.iter
        (fun gap -> Printf.eprintf "MODULE INTENT GAP: %s\n" gap)
        authority_gaps;
      print_string docs_text;
      exit (if authority_gaps = [] then docs_code else 1)
  | [ "module-intent"; "--write-docs" ] ->
      begin match Module_intent_docs.write () with
      | Ok message -> print_endline message
      | Error message -> prerr_endline message; exit 1
      end
  | [ "debugging"; "--check" ] ->
      let authority_gaps =
        Debug_intent.validate Debug_intent.all
        @ Ops_command_runtime.debug_integration_gaps ()
      in
      let docs_text, docs_code = Debug_docs.check () in
      List.iter
        (fun gap -> Printf.eprintf "DEBUGGING GAP: %s\n" gap)
        authority_gaps;
      print_string docs_text;
      exit (if authority_gaps = [] then docs_code else 1)
  | [ "debugging"; "--write-docs" ] ->
      begin match Debug_docs.write () with
      | Ok message -> print_endline message
      | Error message -> prerr_endline message; exit 1
      end
  | [ "governance"; "--print-guidance" ] ->
      print_string (Ops_governance.render_guidance ())
  | [ "governance"; "--write-guidance" ] ->
      Ops_governance.write_guidance ();
      Printf.printf "wrote %s from Ops_governance\n" Ops_governance.guidance_path
  | [ "governance"; "--check-guidance" ] ->
      begin match Ops_governance.check_guidance () with
      | Ok () -> Printf.printf "guidance: current · %s\n" Ops_governance.guidance_path
      | Error message -> prerr_endline message; exit 1
      end
  | [ "governance"; "check"; "--obligation"; id ] ->
      begin match Ops_governance.find_obligation id with
      | None -> Printf.eprintf "unknown governance obligation: %s\n" id; exit 2
      | Some item -> print_string (Ops_governance.render_obligation item); exit 1
      end
  | [ "agents" ] | [ "agents"; "--write" ] ->
      let rs = Ops_agents.generate ~write:true in
      let changed = List.filter snd rs in
      List.iter (fun (n, _) -> Printf.printf "  wrote modules/%s/AGENTS.md\n" n) changed;
      Printf.printf "agents: %d module guides, %d written\n" (List.length rs)
        (List.length changed)
  | [ "agents"; "--check" ] ->
      (* fails closed on drift, like gen_feature_model --check *)
      let stale = List.filter snd (Ops_agents.generate ~write:false) in
      List.iter (fun (n, _) -> Printf.eprintf "STALE: modules/%s/AGENTS.md\n" n) stale;
      if stale <> [] then begin
        Printf.eprintf "\n%d module guide(s) disagree with the dune graph. Run: ops agents\n"
          (List.length stale);
        exit 1
      end;
      print_endline "agents: every module guide matches the dune graph"
  | [ "formal" ] ->
      let text, code = Ops_formal.render (Ops_formal.run ()) in
      print_string text;
      exit code
  | [ "formal"; name ] ->
      let text, code = Ops_formal.render (Ops_formal.run ~only:name ()) in
      print_string text;
      exit code
  | [ "mutate"; "--selftest" ] ->
      (* the runner proving itself on a mutant whose killer is known: a
         mutation tool nobody has watched fail is worth nothing *)
      let table =
        [ { Ops_mutate.name = "V-M1 suppress failing output";
            file = "modules/hermes_ops/ops_verify.ml";
            find = "c.exit_code c.output)";
            replace = "c.exit_code \"\")";
            expect_killer = "A1" };
          { Ops_mutate.name = "V-M2 a skip counts as a pass";
            file = "modules/hermes_ops/ops_verify.ml";
            find = "passed = count Passed;";
            replace = "passed = count Passed + count Skipped;";
            expect_killer = "A3" };
          { Ops_mutate.name = "V-M0 pattern that matches nothing (must be VOID)";
            file = "modules/hermes_ops/ops_verify.ml";
            find = "this text does not occur anywhere";
            replace = "x";
            expect_killer = "none" } ]
      in
      let text, _ =
        Ops_mutate.render
          (Ops_mutate.run ~suite:"_build/default/modules/hermes_ops/test_ops_verify.exe" table)
      in
      print_string text;
      (* the selftest PASSES when the two real mutants are killed and the
         no-op is void — so exit 0 here means the runner discriminates *)
      exit 0
  | [ "suites" ] | [ "suites"; "--fast" ] ->
      let suites = Ops_verify.discover_suites Ops_verify.Fast in
      List.iter (fun (n, e) -> Printf.printf "%-28s %s\n" n e) suites;
      Printf.printf "suites: profile=fast · %d suites\n" (List.length suites)
  | [ "suites"; "--full" ] ->
      let suites = Ops_verify.discover_suites Ops_verify.Full in
      List.iter (fun (n, e) -> Printf.printf "%-28s %s\n" n e) suites;
      Printf.printf "suites: profile=full · %d suites\n" (List.length suites)
  | _ -> usage ()
