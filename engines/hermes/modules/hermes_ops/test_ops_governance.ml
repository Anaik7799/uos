let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let domains =
  Ops_governance.
    [ Authority; Prompting; Surfaces; Fractal; Fast_ooda; Sysml; Oml; Openmbee;
      Fpp; Formal; Safety; Reliability; Security; Provenance; Supply_chain;
      Lifecycle; Evidence; Observability; Metrics; Performance; Recovery;
      Data_governance; Human_control; Publication ]

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let contains text needle =
  let n = String.length text and k = String.length needle in
  let rec loop i = i + k <= n && (String.sub text i k = needle || loop (i + 1)) in
  k > 0 && loop 0

let () =
  check "D1 every comprehensive domain has a typed obligation" (fun () ->
      List.for_all
        (fun domain ->
          List.exists
            (fun (item : Ops_governance.obligation) -> item.domain = domain)
            Ops_governance.obligations)
        domains);
  check "D2 obligation ids are stable and unique" (fun () ->
      let ids = List.map (fun (item : Ops_governance.obligation) -> item.id)
          Ops_governance.obligations in
      ids <> [] && List.length ids = List.length (List.sort_uniq compare ids));
  check "D3 every item is an executable semantic obligation" (fun () ->
      List.for_all
        (fun (item : Ops_governance.obligation) ->
          item.path <> [] && item.command <> "" && item.declaration_id <> ""
          && item.required_evidence <> [] && item.gates <> []
          && String.length item.guidance >= 40
          && String.length item.completion_criterion >= 24)
        Ops_governance.obligations);
  check "D4 control and data plane obligations are both present" (fun () ->
      List.exists
        (fun (item : Ops_governance.obligation) -> item.plane = Ops_capability.Control_plane)
        Ops_governance.obligations
      && List.exists
           (fun (item : Ops_governance.obligation) -> item.plane = Ops_capability.Data_plane)
           Ops_governance.obligations);
  check "D5 every reported metric is a unique FPP-safe channel" (fun () ->
      let metrics = List.map (fun (item : Ops_governance.obligation) -> item.metric)
          Ops_governance.obligations in
      List.for_all
        (fun metric -> metric <> "" && String.for_all
          (fun c -> (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '_') metric)
        metrics
      && List.length metrics = List.length (List.sort_uniq compare metrics));
  check "D6 every governance metric has an FPP telemetry channel" (fun () ->
      let channels =
        List.map (fun (channel : Fpp_model.channel) -> channel.chan_name)
          Ops_topology.verifier.channels
      in
      List.for_all
        (fun (item : Ops_governance.obligation) -> List.mem item.metric channels)
        Ops_governance.obligations);
  check "D7 FPP models command, evidence, MBSE, formal, and history flow" (fun () ->
      let names =
        List.map (fun (component : Fpp_model.component) -> component.comp_name)
          Ops_completion_topology.model.components
      in
      List.for_all (fun name -> List.mem name names)
        [ "commandGateway"; "completionHistory"; "mbseProjector"; "formalOracle" ]
      && List.length Ops_completion_topology.instances = 4
      && match Ops_completion_topology.command_flow with
         | Fpp_model.Direct { connections; _ } -> List.length connections = 4
         | Pattern _ -> false);
  check "O1 the whole-system SOP is causal Observe-Orient-Decide-Act-Observe" (fun () ->
      List.map (fun (step : Ops_governance.sop_step) -> step.phase)
        Ops_governance.whole_system_sop
      = Ops_capability.[ Observe; Orient; Decide; Act; Observe ]);
  check "O2 every SOP step after the first depends on its predecessor" (fun () ->
      let rec loop = function
        | [] | [ _ ] -> true
        | (left : Ops_governance.sop_step) :: ((right : Ops_governance.sop_step) :: _ as rest) ->
            List.mem left.step_id right.dependencies && loop rest
      in
      loop Ops_governance.whole_system_sop);
  check "G1 fail-closed model validation has no structural gaps" (fun () ->
      Ops_governance.validate () = []);
  check "G2 rendered guidance contains every domain, item, prompt, and SOP" (fun () ->
      let text = Ops_governance.render_guidance () in
      contains text "What to write in every prompt"
      && contains text "Whole-system Fast OODA SOP"
      && List.for_all
           (fun domain -> contains text (Ops_governance.string_of_domain domain)) domains
      && List.for_all
           (fun (item : Ops_governance.obligation) -> contains text item.id)
           Ops_governance.obligations);
  check "G3 checked-in guidance is the exact OCaml projection" (fun () ->
      Sys.file_exists Ops_governance.guidance_path
      && read Ops_governance.guidance_path = Ops_governance.render_guidance ());

  Printf.printf "ops_governance: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_governance" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_governance ]);
  exit (Suite_telemetry.exit_code self)
