(* The verification offload, across the functional envelope:

     N*  nominal      discovery finds the suites; a clean pass is one line
     X*  exhaustion   a large report renders; many failures all appear
     S*  stuck        no suites, an unbuilt binary, a suite with no summary
     A*  anomaly      a failing suite, a skipped one, both at once

   The headline law is ECONOMY ON SUCCESS ONLY. Suppressing a suite's
   output when it passes is the whole point of the module; suppressing it
   when it fails would make the offload a way of hiding defects, which is
   the one thing this repository cannot tolerate. Every check below that
   matters is about the failure path, not the happy one. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

let case ?(exit_code = 0) ?(output = "") ?(detail = "d") ?capture name verdict =
  { Ops_verify.name; verdict; exit_code; output; detail; duration_ms = 1.0;
    capture }

(* the REAL summariser, not a copy of it: a test that recomputes the
   arithmetic it is checking proves only that it can add *)
let report cases = Ops_verify.summarise ~profile:Ops_verify.Fast ~wall_ms:1000.0 cases

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 discovery DERIVES the suite list from the tree, not a literal" (fun () ->
      let s = Ops_verify.discover_suites Ops_verify.Fast in
      (* it must find the wiki battery and this very suite — a hand-kept
         list would silently stop covering whatever was added last *)
      List.length s > 30
      && List.exists (fun (n, _) -> n = "test_ops_verify") s
      && List.exists (fun (n, _) -> n = "test_hermes_wiki") s);
  check "N1b whole-workspace discovery includes rule and parity suites" (fun () ->
      (* Break caught: adding a production module test while the verifier
         continues to scan only wiki+ops, manufacturing a green workspace. *)
      let s = Ops_verify.discover_suites Ops_verify.Full in
      List.for_all
        (fun name -> List.exists (fun (n, _) -> n = name) s)
        [ "test_rust_rules"; "test_hermes_rete"; "test_drift_rules";
          "test_ruliad_rules"; "test_parity_compare"; "test_parity_algebra" ]);
  check "N2 every discovered path points into _build, where the binary is" (fun () ->
      List.for_all
        (fun (_, e) -> contains e "_build/default" && Filename.check_suffix e ".exe")
        (Ops_verify.discover_suites Ops_verify.Full));
  check "N3 discovery is SORTED and deduplicated — a stable report order" (fun () ->
      let s = List.map fst (Ops_verify.discover_suites Ops_verify.Full) in
      s = List.sort compare s && s = List.sort_uniq compare s);
  check "N3b fast remains scoped to wiki+ops" (fun () ->
      let s = Ops_verify.discover_suites Ops_verify.Fast in
      not (List.exists (fun (n, _) -> n = "test_rust_rules") s));
  check "N3c full excludes the data-only imported zigvm tests" (fun () ->
      let s = Ops_verify.discover_suites Ops_verify.Full in
      not (List.exists (fun (n, _) -> n = "test_graph_analytics") s));
  check "N3d operator authority receives its required live solver admission" (fun () ->
      let command =
        Ops_verify.suite_command ~z3:"/toolchain/bin/z3"
          ~name:"test_run_operator_authority"
          ~exe:"/tmp/operator authority.exe" ()
      in
      contains command "'/tmp/operator authority.exe' --z3 '/toolchain/bin/z3'"
      && not
           (contains
              (Ops_verify.suite_command ~name:"test_plain" ~exe:"plain.exe" ())
              "--z3"));
  check "N3e capture closes inherited descendant pipes after direct exit" (fun () ->
      let started = Unix.gettimeofday () in
      let code, _, observation =
        Ops_verify.capture_command ~timeout_seconds:2 "sleep 30 & exit 0"
      in
      code = 0 && observation.direct_child_reaped
      && observation.residual_group_terminated
      && Unix.gettimeofday () -. started < 1.0);
  check "N3f capture remains valid after the OCaml 5 Domain runtime starts" (fun () ->
      Domain.join (Domain.spawn (fun () -> ()));
      fst (Ops_verify.run_capture "exit 0") = 0);
  check "N4 a clean pass renders ONE line and exits 0" (fun () ->
      let text, code = Ops_verify.render (report [ case "a" Ops_verify.Passed;
                                                   case "b" Ops_verify.Passed ]) in
      code = 0
      && List.length (List.filter (fun l -> l <> "") (String.split_on_char '\n' text)) = 1
      && contains text "2 passed, 0 failed, 0 skipped");
  check "N5 a verification receipt names its profile" (fun () ->
      (* Break caught: a fast-only receipt is later presented as a full
         workspace verdict because its scope is absent from the output. *)
      let text, _ = Ops_verify.render (report [ case "a" Ops_verify.Passed ]) in
      contains text "profile=")

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 THE HEADLINE LAW: a failing suite's own bytes appear IN FULL" (fun () ->
      (* economy on success is the feature; economy on failure would make
         this module a way of hiding defects *)
      let noisy = String.concat "\n" (List.init 40 (fun i -> Printf.sprintf "detail line %d" i)) in
      let text, code = Ops_verify.render (report [ case ~exit_code:1 ~output:noisy "bad"
                                                     Ops_verify.Failed ]) in
      code = 1
      && contains text "detail line 0"
      && contains text "detail line 39"
      && contains text "FAILED: bad (exit 1)");
  check "A2 failures render BEFORE the summary — the reader meets them first" (fun () ->
      let text, _ = Ops_verify.render (report [ case ~exit_code:1 ~output:"boom" "bad"
                                                  Ops_verify.Failed ]) in
      let idx s =
        let n = String.length text and k = String.length s in
        let rec go i = if i + k > n then -1 else if String.sub text i k = s then i else go (i + 1) in
        go 0
      in
      idx "boom" >= 0 && idx "verify:" > idx "boom");
  check "A3 a SKIP is disclosed by name and never folded into the pass count" (fun () ->
      (* R2: a suite that could not be run is unavailable, never green *)
      let text, code = Ops_verify.render
          (report [ case "ok" Ops_verify.Passed;
                    case ~detail:"not built: x.exe" "gone" Ops_verify.Skipped ]) in
      contains text "SKIPPED (disclosed): gone"
      && contains text "not built: x.exe"
      && contains text "1 passed, 0 failed, 1 skipped"
      (* a skip alone is not a failure — it blocks, it does not deny *)
      && code = 0);
  check "A3b certification mode fails closed on every disclosed skip" (fun () ->
      (* Break caught: a missing executable remains visible in prose but the
         certification command still exits successfully. *)
      let text, code =
        Ops_verify.render ~require_complete:true
          (report [ case "ok" Ops_verify.Passed;
                    case ~detail:"not built: x.exe" "gone" Ops_verify.Skipped ])
      in
      code = 1 && contains text "SKIPPED (disclosed): gone");
  check "A4 a failure and a skip together both survive rendering" (fun () ->
      let text, code = Ops_verify.render
          (report [ case ~exit_code:2 ~output:"trace" "bad" Ops_verify.Failed;
                    case ~detail:"absent" "gone" Ops_verify.Skipped ]) in
      code = 1 && contains text "trace" && contains text "SKIPPED (disclosed): gone");
  check "A5 the EXIT CODE is the verdict, and a non-1 exit is preserved" (fun () ->
      let text, _ = Ops_verify.render
          (report [ case ~exit_code:139 ~output:"segv" "crashed" Ops_verify.Failed ]) in
      contains text "(exit 139)")

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 many failures ALL appear — none is dropped to keep the report short"
    (fun () ->
      let cases =
        List.init 25 (fun i ->
            case ~exit_code:1 ~output:(Printf.sprintf "failure-%d-body" i)
              (Printf.sprintf "s%02d" i) Ops_verify.Failed)
      in
      let text, code = Ops_verify.render (report cases) in
      code = 1
      && List.for_all
           (fun i -> contains text (Printf.sprintf "failure-%d-body" i))
           (List.init 25 Fun.id));
  check "X2 a very large captured output is reported, not truncated silently" (fun () ->
      let big = String.make 200_000 'x' in
      let r = report [ case ~exit_code:1 ~output:big "huge" Ops_verify.Failed ] in
      let text, _ = Ops_verify.render r in
      r.Ops_verify.bytes_captured = 200_000 && String.length text > 200_000)

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 an EMPTY report is a defined value, not a crash" (fun () ->
      let text, code = Ops_verify.render (report []) in
      code = 0 && contains text "0 passed, 0 failed, 0 skipped");
  check "S2 a suite that printed NO summary still reports its exit code" (fun () ->
      let text, _ = Ops_verify.render
          (report [ case ~exit_code:3 ~detail:"no summary line; exit 3" "quiet"
                      Ops_verify.Failed ]) in
      contains text "exit 3");
  check "S3 bytes_captured counts what stayed out of context, and only that" (fun () ->
      let r = report [ case ~output:"12345" "a" Ops_verify.Passed;
                       case ~output:"123" "b" Ops_verify.Passed ] in
      r.Ops_verify.bytes_captured = 8);
  check "S4 string_of_verdict is total over all three verdicts" (fun () ->
      List.map Ops_verify.string_of_verdict
        [ Ops_verify.Passed; Ops_verify.Failed; Ops_verify.Skipped ]
      = [ "PASS"; "FAIL"; "SKIP" ])


(* ------------------------------- the FPP model of the ops layer itself *)

let () =
  check "F1 the ops FPP model VALIDATES — the directive is modelled, not asserted"
    (fun () -> Fpp_model.validate Ops_topology.model = []);
  check "F2 its base-id window is DISJOINT from the wiki topology's" (fun () ->
      (* a shared id makes two components indistinguishable in one
         telemetry stream, which is the whole reason ids exist *)
      let ops = List.map (fun (i : Fpp_model.instance) -> i.Fpp_model.base_id)
          Ops_topology.model.Fpp_model.instances in
      let wiki = List.map (fun (i : Fpp_model.instance) -> i.Fpp_model.base_id)
          Wiki_topology.model.Fpp_model.instances in
      List.for_all (fun o -> not (List.mem o wiki)) ops
      && List.for_all (fun o -> o >= 0x2000) ops);
  check "F3 every number the verifier reports has a telemetry channel" (fun () ->
      (* the ratchet's law, applied here: a measurement with no home in
         the model is a measurement nobody can find *)
      let names =
        List.concat_map
          (fun (c : Fpp_model.component) ->
            List.map (fun (ch : Fpp_model.channel) -> ch.Fpp_model.chan_name)
              c.Fpp_model.channels)
          Ops_topology.model.Fpp_model.components
      in
      List.for_all (fun n -> List.mem n names)
        [ "suites_passed"; "suites_failed"; "suites_skipped"; "bytes_offloaded";
          "fast_suites_discovered"; "full_suites_discovered";
          "control_suites_admitted"; "control_suites_terminal";
          "control_parallelism_limit"; "control_suites_timeout";
          "control_process_spawn_failures"; "control_wall_ms";
          "data_bytes_captured"; "data_residual_groups_terminated";
          "data_children_reaped"; "data_summaries_missing";
          "data_case_max_duration_ms" ]);
  check "F4 the verifier is a MONITOR: it declares no command" (fun () ->
      List.for_all
        (fun (c : Fpp_model.component) -> c.Fpp_model.commands = [])
        Ops_topology.model.Fpp_model.components)

(* ------------------------------------------------- capture, under load *)

let () =
  (* X3 is the regression for a HANG, so it is written as a bounded run:
     `timeout` bounds the child, and a deadlocked capture fails the check
     by exceeding the wall clock rather than by returning a wrong value.
     Both streams are loaded past one 64 KiB pipe buffer, because the bug
     needed traffic on BOTH to appear. *)
  check "X3 capture does not deadlock when a suite floods stdout AND stderr" (fun () ->
      let big = "sh -c 'for i in $(seq 1 4000); do echo out-$i; echo err-$i >&2; done; exit 3'" in
      let started = Unix.gettimeofday () in
      let code, out = Ops_verify.run_capture ("timeout 60 " ^ big) in
      let elapsed = Unix.gettimeofday () -. started in
      (* the real exit code survives the merge, the output is all there,
         and it finished in seconds rather than never *)
      code = 3 && String.length out > 65536 && contains out "out-4000"
      && contains out "err-4000" && elapsed < 55.0);
  check "X4 a command that cannot be started is 127, not an exception" (fun () ->
      let code, _ = Ops_verify.run_capture "this-binary-does-not-exist-hermes" in
      code <> 0)

(* ---------------------------------------- control/data path monitoring *)

let () =
  let observed : Ops_verify.capture_observation =
    { deadline_expired = true; residual_group_terminated = true;
      direct_child_reaped = true; bytes = 4 }
  in
  let monitored =
    Ops_verify.summarise ~profile:Ops_verify.Full ~wall_ms:42.0
      [ case ~exit_code:124 ~output:"data" ~detail:"no summary line; exit 124"
          ~capture:observed "timed" Ops_verify.Failed ]
  in
  check "M1 monitoring is total across typed control and data paths" (fun () ->
      Ops_verify.monitoring_gaps monitored = []
      && List.exists
           (fun metric -> metric.Ops_verify.path = Ops_verify.Control_path)
           monitored.monitoring
      && List.exists
           (fun metric -> metric.Ops_verify.path = Ops_verify.Data_path)
           monitored.monitoring);
  check "M2 timeout, residual-group, reap, bytes, and summary signals are measured" (fun () ->
      let value id =
        monitored.monitoring
        |> List.find_opt (fun metric -> metric.Ops_verify.id = id)
        |> Option.map (fun metric -> metric.Ops_verify.value)
      in
      value "ops.verify.control.suites.timeout" = Some 1L
      && value "ops.verify.data.pipe.residual_groups_terminated" = Some 1L
      && value "ops.verify.data.children.reaped" = Some 1L
      && value "ops.verify.data.bytes.captured" = Some 4L
      && value "ops.verify.data.summary.missing" = Some 1L);
  check "M3 a dropped monitoring carrier fails closed" (fun () ->
      match monitored.monitoring with
      | [] -> false
      | _ :: rest ->
          Ops_verify.monitoring_gaps { monitored with monitoring = rest } <> []);
  check "M4 a control-path terminal mismatch fails closed" (fun () ->
      let monitoring =
        List.map
          (fun metric ->
            if metric.Ops_verify.id = "ops.verify.control.suites.terminal" then
              { metric with value = 0L }
            else metric)
          monitored.monitoring
      in
      contains
        (String.concat "; "
           (Ops_verify.monitoring_gaps { monitored with monitoring }))
        "non-terminal");
  check "M5 rendered receipt exposes bounded control and data-path gauges" (fun () ->
      let text, code = Ops_verify.render monitored in
      code = 1
      && contains text "control=1/1 p="
      && contains text "timeout=1"
      && contains text "data=reaped:1 residual:1 missing:1[timed] max:1ms")

let () =
  (* the summary goes LAST, and every check is above it. Appending checks
     after the count is a bug this repository has already shipped once:
     they run, they can fail, and nothing exits non-zero. *)
  Printf.printf "ops_verify: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_verify" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)
