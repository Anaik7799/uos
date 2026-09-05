(* Fail-closed availability boundary for the one-query linked Smtml/Z3 worker.

   The request protocol and resource-envelope decision remain pure and can be
   checked here.  Operational resource observation is intentionally
   [Implemented_unavailable] until an R31-controlled owner can supply opaque,
   receipt-bound observations.  Consequently this suite must not spawn the
   worker: every check that requires live execution is disclosed as skipped,
   never converted into green evidence. *)

let passed = ref 0
let failures = ref []
let skipped = ref []

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let skip label detail = skipped := (label, detail) :: !skipped

let live_execution_labels =
  [ "EXECUTION first frame is an admitted containment handshake";
    "EXECUTION query is withheld until that handshake";
    "EXECUTION exact stdin write succeeds after that handshake";
    "EXECUTION completes before the total monotonic deadline";
    "EXECUTION exits through Completed_exit";
    "EXECUTION stderr is bounded and empty";
    "EXECUTION transcript is completed";
    "EXECUTION applied-limit and owned-group handshake validates";
    "EXECUTION worker executable identity is stable";
    "EXECUTION query capture is 0700/0600, stable, read back, and removed";
    "EXECUTION result binds the exact executed query" ]

let prepared_request () =
  let open Run_analysis_z3_worker_protocol in
  match
    make_limits ~virtual_memory_bytes:536_870_912L ~cpu_seconds:2
      ~maximum_query_bytes:4096 ~maximum_output_bytes:16_384
  with
  | Error errors -> Error errors
  | Ok limits ->
      prepare ~obligation_id:"test-linked-worker-process"
        ~worker_executable_digest:(digest_bytes "synthetic-worker-object")
        ~query:
          ("(set-logic QF_LIA)\n"
           ^ "(declare-const x Int)\n"
           ^ "(assert (= x 1))\n"
           ^ "(assert (> x 0))\n"
           ^ "(check-sat)\n")
        ~limits

let protocol_is_safe prepared =
  let open Run_analysis_z3_worker_protocol in
  match decode_argv (argv prepared) with
  | Error _ -> false
  | Ok request ->
      match admit_stdin request (stdin_bytes prepared) with
      | Error _ -> false
      | Ok query ->
          query.length = request.query_bytes
          && query.digest = request.query_digest
          && String.equal query.bytes (stdin_bytes prepared)

let unavailable_preflight () =
  let open Run_analysis_z3_worker_protocol in
  let expected = Resource_envelope.{ device = 7; inode = 11 } in
  let resources =
    resource_requirements ~worker_path:"run_analysis_z3_worker.exe" ~expected
  in
  let checks = Resource_envelope.preflight resources in
  match Resource_envelope.operational_status with
  | Resource_envelope.Implemented_unavailable reason ->
      let exact_refusal =
        reason <> ""
        && List.length resources = 4
        && List.length checks = 4
        && not (Resource_envelope.satisfied checks)
        && List.length (Resource_envelope.unmet_checks checks) = 4
        && List.for_all
             (fun (check : Resource_envelope.check) ->
               not check.met
               && not check.receipt_bound
               && String.ends_with ~suffix:reason check.detail)
             checks
      in
      exact_refusal, reason

let behavior_layer () =
  match prepared_request () with
  | Error errors ->
      check false "PROTOCOL request preparation and admission remain safe"
        (String.concat "; " errors);
      check false "PREFLIGHT non-empty envelope refuses without owned receipts"
        "protocol preparation failed before preflight"
  | Ok prepared ->
      check (protocol_is_safe prepared)
        "PROTOCOL request preparation and admission remain safe" "";
      let refused, reason = unavailable_preflight () in
      check refused
        "PREFLIGHT non-empty envelope refuses without owned receipts" reason;
      List.iter
        (fun label ->
          skip label
            ("Unavailable_observed: " ^ reason
             ^ "; no worker was spawned and no execution evidence was granted"))
        live_execution_labels

let () =
  print_endline "run_analysis linked-Z3 isolated worker suite";
  behavior_layer ();
  Printf.printf "\npassed: %d   failed: %d   skipped: %d\n" !passed
    (List.length !failures) (List.length !skipped);
  List.iter
    (fun failure -> print_endline ("  FAIL  " ^ failure))
    (List.rev !failures);
  List.iter
    (fun (label, detail) -> Printf.printf "  SKIP  %s :: %s\n" label detail)
    (List.rev !skipped);
  let self =
    Suite_telemetry.observe ~suite:"test_run_analysis_z3_worker" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:(List.length !skipped)
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
