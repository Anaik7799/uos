(* The harness described AS an F Prime topology, and the differential law
   tying the new encoding to the existing one: every instance must be a
   registered fractal-ontology component, and every direct connection must
   lie over an ontology edge. Two independent encodings of the same system
   must agree — where they cannot, one of them is wrong. *)

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

let contains text needle =
  let n = String.length needle and h = String.length text in
  let rec go i = i + n <= h && (String.sub text i n = needle || go (i + 1)) in
  go 0

(* ------------------------------------------------------------- validity *)

let () =
  check "the harness model is FPP-valid (zero diagnostics)" (fun () ->
      match Harness_topology.validate () with
      | [] -> true
      | diagnostics ->
          List.iter
            (fun d -> print_endline ("  " ^ Fractal_diagnostic.render d))
            diagnostics;
          false);
  check "every instance is named after its component" (fun () ->
      List.for_all
        (fun (i : Fpp_model.instance) -> Harness_topology.component_of_instance i.inst_name = i.of_component)
        Harness_topology.model.Fpp_model.instances);
  check "the model covers at least eleven real harness components" (fun () ->
      List.length Harness_topology.model.Fpp_model.instances >= 11);
  check "harness_config is the active component carrying the converge machine"
    (fun () ->
      List.exists
        (fun (c : Fpp_model.component) ->
          c.comp_name = "harness_config" && c.kind = Fpp_model.Active
          && List.mem_assoc "converge" c.machines)
        Harness_topology.model.Fpp_model.components);
  check "the converge OODA machine has the six loop states" (fun () ->
      List.exists
        (function
          | Fpp_model.Internal_machine m ->
              m.machine_name = "ConvergeLoop"
              && List.for_all
                   (fun s ->
                     List.exists
                       (fun st -> st.Fpp_model.state_name = s)
                       m.states)
                   [ "Idle"; "Preflight"; "Observing"; "Converged"; "Blocked"; "Anomalous" ]
          | Fpp_model.External_machine _ -> false)
        Harness_topology.model.Fpp_model.machines)

(* -------------------------------------------------------- differential law *)

let () =
  check "topology <-> ontology: zero gaps" (fun () ->
      match Harness_topology.ontology_gaps () with
      | [] -> true
      | gaps ->
          List.iter (fun g -> print_endline ("  gap: " ^ g)) gaps;
          false);
  check "the law can fail: an unmirrored connection is reported" (fun () ->
      (* inventory -> hermes_zenoh has no ontology edge; injecting that
         connection must produce a gap. Meta-falsification: a law that
         cannot fail proves nothing. *)
      let open Fpp_model in
      let injected =
        { from_ = { ep_instance = "inventory"; ep_port = "timeGetIn"; ep_index = None };
          to_ = { ep_instance = "hermes_zenoh"; ep_port = "publish"; ep_index = None } }
      in
      let gaps = Harness_topology.gaps_for_connections [ injected ] in
      gaps <> []);
  check "the law can fail: an unregistered instance is reported" (fun () ->
      let open Fpp_model in
      let ghost =
        { inst_name = "ghost"; of_component = "not_in_ontology"; base_id = 0xF000;
          queue_size = None; stack_size = None; inst_priority = None; cpu = None }
      in
      Harness_topology.gaps_for_instances [ ghost ] <> [])

(* ------------------------------------------- the two-lattice boundary, structural *)

let () =
  check "no direct connection carries alerts into the evidence side" (fun () ->
      (* The forbidden morphism (alert -> verdict) must be structurally
         absent: nothing flows from the control side into the components
         that produce or store parity verdicts. *)
      let control = [ "control_plane"; "homeostasis"; "hermes_zenoh" ] in
      let evidence = [ "parity_compare"; "parity_algebra"; "evidence_store" ] in
      List.for_all
        (fun (c : Fpp_model.connection) ->
          not
            (List.mem c.Fpp_model.from_.Fpp_model.ep_instance control
            && List.mem c.Fpp_model.to_.Fpp_model.ep_instance evidence))
        (Harness_topology.direct_connections ()))

(* ------------------------------------------------------------ expansion *)

let () =
  check "health pattern pings every participating instance" (fun () ->
      match
        Fpp_model.connections Harness_topology.model Harness_topology.topology
      with
      | Error e ->
          print_endline e;
          false
      | Ok all ->
          let pings =
            List.filter
              (fun (c : Fpp_model.connection) ->
                c.Fpp_model.from_.Fpp_model.ep_instance = "control_plane"
                && c.Fpp_model.from_.Fpp_model.ep_port = "pingOut")
              all
          in
          List.length pings >= 4);
  check "time pattern serves every time consumer" (fun () ->
      match
        Fpp_model.connections Harness_topology.model Harness_topology.topology
      with
      | Error _ -> false
      | Ok all ->
          let time_links =
            List.filter
              (fun (c : Fpp_model.connection) ->
                c.Fpp_model.to_.Fpp_model.ep_instance = "inventory"
                && c.Fpp_model.to_.Fpp_model.ep_port = "timeGetIn")
              all
          in
          List.length time_links >= 5)

(* ------------------------------------------------------------- emitters *)

let () =
  check "the FPP rendering names the real components" (fun () ->
      let text = Harness_topology.to_fpp () in
      contains text "active component harness_config"
      && contains text "passive component evidence_store"
      && contains text "state machine ConvergeLoop"
      && contains text "topology hermes_harness");
  check "the dictionary is emitted and instance-qualified" (fun () ->
      match Harness_topology.dictionary () with
      | Error e ->
          print_endline e;
          false
      | Ok json -> (
          match json with
          | `Assoc fields -> (
              match List.assoc_opt "commands" fields with
              | Some (`List commands) ->
                  List.exists
                    (fun c ->
                      match c with
                      | `Assoc f ->
                          List.assoc_opt "name" f
                          = Some (`String "harness_config.RUN_PIPELINE")
                      | _ -> false)
                    commands
              | _ -> false)
          | _ -> false));
  check "the sweep-P0 event is FATAL in the dictionary (the exit-2 teeth)" (fun () ->
      match Harness_topology.dictionary () with
      | Error _ -> false
      | Ok (`Assoc fields) -> (
          match List.assoc_opt "events" fields with
          | Some (`List events) ->
              List.exists
                (fun e ->
                  match e with
                  | `Assoc f ->
                      List.assoc_opt "name" f = Some (`String "control_plane.SWEEP_P0")
                      && List.assoc_opt "severity" f = Some (`String "FATAL")
                  | _ -> false)
                events
          | _ -> false)
      | Ok _ -> false);
  check "the verdict semilattice is an FPP enum with the rank order" (fun () ->
      let text = Harness_topology.to_fpp () in
      contains text "enum Verdict : U8 { VERIFIED = 0, UNMAPPED = 1, BLOCKED = 2, DIVERGENT = 3 }");
  check "the alert lattice is a separate FPP enum" (fun () ->
      let text = Harness_topology.to_fpp () in
      contains text "enum Alert : U8 { GREEN = 0, P2 = 1, P1 = 2, P0 = 3 }")

let () =
  Printf.printf "harness_topology: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_harness_topology" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_harness_topology ]);
  exit (Suite_telemetry.exit_code self)
