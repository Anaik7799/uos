let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let execute (request : Ops_command.request) =
  Ok ("zenoh:" ^ Ops_command.action_name request.action ^ ":" ^ Ops_command.scope_name request.scope)

let () =
  let key = "hermes/data/completion/metrics-observe" in
  let payload = "{\"request_id\":\"zenoh-1\",\"scope\":\"data-plane\"}" in
  check "Z1 queryable key expression covers control and data commands" (fun () ->
      Ops_zenoh.command_keyexpr = "hermes/*/completion/*");
  check "Z2 handler is the canonical Zenoh adapter receipt" (fun () ->
      match Ops_zenoh.handle ~execute ~key ~payload (),
            Ops_command.dispatch_zenoh ~execute ~key ~payload () with
      | Ok wire, Ok observation -> wire = Ops_command.receipt_json observation.receipt
      | _ -> false);
  check "Z3 malformed keys and payloads fail closed before transport effects" (fun () ->
      Result.is_error (Ops_zenoh.handle ~execute ~key:"wrong" ~payload ())
      && Result.is_error (Ops_zenoh.handle ~execute ~key ~payload:"not-json" ()));
  check "Z4 control key refuses a data-plane scope mismatch" (fun () ->
      Result.is_error
        (Ops_zenoh.handle ~execute ~key:"hermes/control/completion/check"
           ~payload:"{\"request_id\":\"z\",\"scope\":\"data-plane\"}" ()));
  check "Z5 blocked execution is a successful command receipt with blocked verdict" (fun () ->
      let blocked _ = Error "evidence incomplete" in
      match Ops_zenoh.handle ~execute:blocked ~key ~payload () with
      | Error _ -> false
      | Ok wire ->
          let json = Yojson.Safe.from_string wire in
          Yojson.Safe.Util.member "verdict" json = `String "blocked");

  Printf.printf "ops_zenoh: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_zenoh" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)
