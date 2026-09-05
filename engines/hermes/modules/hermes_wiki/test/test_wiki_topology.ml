(* The wiki/ZK system as an F Prime actor topology — every aspect of the
   build-out plan's monitor table (§4.1) as a component with telemetry
   channels, every control as a command, the two control loops as state
   machines. Lives inside the wiki folder (src/fpp), like the metamodel it
   instantiates; its base-id window comes from hermes_fpp_window_authority.

   Laws:
     - the model VALIDATES: Fpp_model.validate = [] (names, ids, ports,
       machine references all coherent — the same gate harness_topology
       passes);
     - every §4.1 gauge is a telemetry channel somewhere;
     - every §4.2 control is a command somewhere;
     - the two loops (Audit, Ratchet) are Internal_machines with an Idle
       initial state;
     - REPORT-ONLY (the R5-shaped law): in every graph, no connection
       from an auditor instance TARGETS corpusStore — monitors sense and
       report; nothing they emit can write the corpus;
     - actual Wiki instance intervals are internally disjoint. This does not
       claim global disjointness from Harness; the neutral window authority
       owns the narrower normative allocation theorem. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false ->
      incr failed;
      print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let m = Wiki_topology.model

let all_channels =
  List.concat_map (fun (c : Fpp_model.component) ->
      List.map (fun (ch : Fpp_model.channel) -> ch.Fpp_model.chan_name) c.Fpp_model.channels)
    m.Fpp_model.components

let all_commands =
  List.concat_map (fun (c : Fpp_model.component) ->
      List.map (fun (cmd : Fpp_model.command) -> cmd.Fpp_model.cmd_name) c.Fpp_model.commands)
    m.Fpp_model.components

let () =
  check "the wiki topology VALIDATES (Fpp_model.validate = [])" (fun () ->
      match Fpp_model.validate m with
      | [] -> true
      | ds ->
          List.iter (fun d -> print_endline ("  " ^ Fractal_diagnostic.render d)) ds;
          false)

let () =
  check "every monitor gauge from the build-out table is a telemetry channel" (fun () ->
      List.for_all
        (fun g ->
          List.mem g all_channels
          || (print_endline ("  missing gauge: " ^ g); false))
        [ "drift_count"; "schema_debt"; "dead_links"; "dead_anchors";
          "orphans"; "grounded_anomalies"; "ecc_hub"; "dead_cover";
          "query_rejects_named"; "ratchet_current"; "playwright_fail";
          "stale_declarations" ])

let () =
  check "every control is a command: audit, ratchet, pin (guarded)" (fun () ->
      List.for_all (fun c -> List.mem c all_commands)
        [ "RUN_AUDIT"; "RATCHET_CHECK"; "PIN_BASELINE" ])

let () =
  check "APPLY_BATCH is GUARDED — corpus-writing backfill is a deliberate act" (fun () ->
      List.exists
        (fun (c : Fpp_model.component) ->
          c.Fpp_model.comp_name = "backfiller"
          && List.exists
               (fun (cmd : Fpp_model.command) ->
                 cmd.Fpp_model.cmd_name = "APPLY_BATCH"
                 && cmd.Fpp_model.cmd_kind = Fpp_model.Guarded_cmd)
               c.Fpp_model.commands)
        m.Fpp_model.components)

let () =
  check "PIN_BASELINE is GUARDED — re-pinning is a deliberate act" (fun () ->
      List.exists
        (fun (c : Fpp_model.component) ->
          List.exists
            (fun (cmd : Fpp_model.command) ->
              cmd.Fpp_model.cmd_name = "PIN_BASELINE"
              && cmd.Fpp_model.cmd_kind = Fpp_model.Guarded_cmd)
            c.Fpp_model.commands)
        m.Fpp_model.components)

let () =
  check "the Audit and Ratchet loops are internal machines starting Idle" (fun () ->
      let starts_idle name =
        List.exists
          (function
            | Fpp_model.Internal_machine { machine_name; initial; _ } ->
                machine_name = name && snd initial = "Idle"
            | Fpp_model.External_machine _ -> false)
          m.Fpp_model.machines
      in
      starts_idle "AuditLoop" && starts_idle "RatchetLoop")

let () =
  check "REPORT-ONLY: no graph connection targets corpusStore from an auditor"
    (fun () ->
      let auditors =
        [ "linkAuditor"; "schemaAuditor"; "graphAnalyzer"; "browserProbe";
          "reconciler"; "journalKeeper" ]
      in
      List.for_all
        (fun (t : Fpp_model.topology) ->
          List.for_all
            (function
              | Fpp_model.Direct { connections; _ } ->
                  List.for_all
                    (fun (cn : Fpp_model.connection) ->
                      not
                        (List.mem cn.Fpp_model.from_.Fpp_model.ep_instance auditors
                        && cn.Fpp_model.to_.Fpp_model.ep_instance = "corpusStore"))
                    connections
              | Fpp_model.Pattern _ -> true)
            t.Fpp_model.graphs)
        m.Fpp_model.topologies)

let instance_interval (instance : Fpp_model.instance) =
  match
    List.find_opt
      (fun (component : Fpp_model.component) ->
        String.equal component.comp_name instance.of_component)
      m.Fpp_model.components
  with
  | None -> None
  | Some component -> Some (instance.base_id, Fpp_model.id_span component)

let intervals_overlap (left_base, left_span) (right_base, right_span) =
  left_base < right_base + right_span && right_base < left_base + left_span

let pairwise_disjoint intervals =
  let rec loop = function
    | [] -> true
    | first :: rest ->
        List.for_all (fun next -> not (intervals_overlap first next)) rest
        && loop rest
  in
  loop intervals

let () =
  check "actual Wiki instance intervals are internally disjoint" (fun () ->
      let intervals = List.filter_map instance_interval m.Fpp_model.instances in
      List.length intervals = List.length m.Fpp_model.instances
      && pairwise_disjoint intervals)

let () =
  check "interval overlap mutant is detected" (fun () ->
      match List.filter_map instance_interval m.Fpp_model.instances with
      | first :: _second :: rest -> not (pairwise_disjoint (first :: first :: rest))
      | _ -> false)

let () =
  check "meta-falsification: the gauge check can fail" (fun () ->
      not (List.mem "no-such-gauge" all_channels))

let () =
  Printf.printf "wiki_topology: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_topology" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_topology ]);
  exit (Wiki_suite_telemetry.exit_code self)
