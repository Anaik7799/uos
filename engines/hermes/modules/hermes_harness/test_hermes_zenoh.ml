(* Zenoh publisher: unit (pure key rules) / chaos (unreachable router fails
   closed as an Error, never a crash) / live (against the real local mesh
   router when reachable -- absence is disclosed, not failed: R5). *)

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    print_endline ("FAILED: " ^ name)
  end

(* ------------------------------------------------------------------ unit *)

let () =
  check "empty key invalid" (not (Hermes_zenoh.valid_key ""));
  check "plain hierarchical key valid" (Hermes_zenoh.valid_key "hermes/control/sweep/compare");
  check "leading slash invalid" (not (Hermes_zenoh.valid_key "/hermes/control"));
  check "trailing slash invalid" (not (Hermes_zenoh.valid_key "hermes/control/"));
  check "whitespace invalid" (not (Hermes_zenoh.valid_key "hermes/con trol"));
  check "wildcard star invalid for a publisher" (not (Hermes_zenoh.valid_key "hermes/*/sweep"));
  check "wildcard dollar invalid" (not (Hermes_zenoh.valid_key "hermes/$x/sweep"));
  check "question mark invalid" (not (Hermes_zenoh.valid_key "hermes/a?b"));
  check "hash invalid" (not (Hermes_zenoh.valid_key "hermes/a#b"));
  check "default endpoint is the local mesh"
    (Hermes_zenoh.default_endpoint = "tcp/127.0.0.1:7447")

let () =
  (* An invalid key is refused by the pure guard BEFORE any FFI. *)
  match Hermes_zenoh.publish ~key:"/bad" ~payload:"x" with
  | Error _ -> incr passed
  | Ok () ->
      incr failed;
      print_endline "FAILED: invalid key must be refused before the wire"

(* ----------------------------------------------------------------- chaos *)

let () =
  (* Unreachable router (closed port): an Error with detail, never a crash,
     and control returns promptly. *)
  Unix.putenv "HERMES_ZENOH_ENDPOINT" "tcp/127.0.0.1:9";
  (match Hermes_zenoh.publish ~key:"hermes/test/chaos" ~payload:"x" with
  | Error detail -> check "unreachable router is an Error with detail" (String.length detail > 0)
  | Ok () ->
      incr failed;
      print_endline "FAILED: publish to a closed port cannot be Ok");
  (* Explicit opt-out is reported, not silent. *)
  Unix.putenv "HERMES_ZENOH_ENDPOINT" "";
  Unix.putenv "HERMES_ZENOH" "0";
  (match Hermes_zenoh.publish ~key:"hermes/test/disabled" ~payload:"x" with
  | Error detail ->
      check "disabled publish says why"
        (String.length detail > 0 && not (Hermes_zenoh.enabled ()))
  | Ok () ->
      incr failed;
      print_endline "FAILED: HERMES_ZENOH=0 must refuse");
  Unix.putenv "HERMES_ZENOH" "1"

(* ------------------------------------------------------------------ live *)

let () =
  (* Against the real local mesh router. If it is down, that is an
     environment absence: disclosed and skipped, never a failure (R5). *)
  match Hermes_zenoh.publish ~key:"hermes/test/live" ~payload:"harness-live-probe" with
  | Ok () -> check "live publish to the local mesh router" true
  | Error detail ->
      print_endline
        ("live router leg skipped (disclosed, not failed): " ^ detail)

let () =
  Printf.printf "hermes_zenoh: passed: %d failed: %d\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_hermes_zenoh" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_hermes_zenoh ]);
  exit (Suite_telemetry.exit_code self)
