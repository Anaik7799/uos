(* tools/tri_language_state_runner.ml
   Cross-language state runner for OCaml (Hermes Engine) communicating with
   Gleam (BEAM ETS) and Mojo (MAX SIMD) via Zenoh (port 8080/7447) and Wisp (port 4100).
   STAMP: SC-GLM-UI-001, SC-ZMOF-001, SC-CHECKLIST-001
*)

let zenoh_base = "http://127.0.0.1:8080"
let gleam_wisp_base = "http://127.0.0.1:4100"

let exec_cmd cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 1024 in
  (try
     while true do
       let line = input_line ic in
       Buffer.add_string buf line;
       Buffer.add_char buf '\n'
     done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  (status, Buffer.contents buf)

let http_get url =
  let cmd = Printf.sprintf "curl -s -m 5 '%s'" url in
  let (status, output) = exec_cmd cmd in
  match status with
  | Unix.WEXITED 0 -> Some output
  | _ -> None

let http_put url body =
  let cmd = Printf.sprintf "curl -s -m 5 -X PUT -d '%s' '%s'" body url in
  let (status, output) = exec_cmd cmd in
  match status with
  | Unix.WEXITED 0 -> Some output
  | _ -> None

let string_contains haystack needle =
  let h_len = String.length haystack in
  let n_len = String.length needle in
  if n_len = 0 then true
  else if h_len < n_len then false
  else
    let found = ref false in
    for i = 0 to h_len - n_len do
      if not !found && String.sub haystack i n_len = needle then
        found := true
    done;
    !found

let publish_zenoh_state key value =
  let url = Printf.sprintf "%s/c3i/a2a/ets/%s" zenoh_base key in
  Printf.printf "[OCAML-HERMES] Publishing to Zenoh: %s -> %s\n%!" url value;
  match http_put url value with
  | Some _ ->
      Printf.printf "[OCAML-HERMES] Successfully published '%s' to Zenoh\n%!" key;
      true
  | None ->
      Printf.eprintf "[OCAML-HERMES] Failed to publish '%s' to Zenoh\n%!" key;
      false

let get_zenoh_state key =
  let url = Printf.sprintf "%s/c3i/a2a/ets/%s" zenoh_base key in
  http_get url

let put_ets_state key value =
  let url = Printf.sprintf "%s/api/v1/ets/put?key=%s&val=%s" gleam_wisp_base key value in
  Printf.printf "[OCAML-HERMES] Putting to BEAM ETS via Wisp: %s\n%!" url;
  match http_get url with
  | Some out ->
      Printf.printf "[OCAML-HERMES] ETS put response: %s\n%!" (String.trim out);
      true
  | None ->
      Printf.eprintf "[OCAML-HERMES] ETS put failed for %s\n%!" key;
      false

let get_ets_state key =
  let url = Printf.sprintf "%s/api/v1/ets/%s" gleam_wisp_base key in
  http_get url

let get_tri_language_state () =
  let url = Printf.sprintf "%s/api/v1/state/tri_language" gleam_wisp_base in
  http_get url

let run_test () =
  Printf.printf "========================================================\n%!";
  Printf.printf "[OCAML-HERMES] Starting Tri-Language Zenoh & ETS Test...\n%!";
  Printf.printf "========================================================\n%!";

  (* 1. Publish OCaml state to Zenoh *)
  let ocaml_payload = "OCAML_HERMES_ORACLE_ACTIVE" in
  let pub_ok = publish_zenoh_state "ocaml_state" ocaml_payload in
  assert pub_ok;

  (* 2. Put OCaml state directly to ETS as well for bidirectional parity *)
  let ets_ok = put_ets_state "ocaml_state" ocaml_payload in
  assert ets_ok;

  (* 3. Read back from Zenoh *)
  (match get_zenoh_state "ocaml_state" with
   | Some content ->
       Printf.printf "[OCAML-HERMES] Readback from Zenoh: %s\n%!" (String.trim content);
       assert (String.length content > 0)
   | None ->
       failwith "Failed to read ocaml_state from Zenoh");

  (* 4. Read back from ETS *)
  (match get_ets_state "ocaml_state" with
   | Some content ->
       Printf.printf "[OCAML-HERMES] Readback from ETS: %s\n%!" (String.trim content);
       assert (string_contains content "OCAML_HERMES_ORACLE_ACTIVE")
   | None ->
       failwith "Failed to read ocaml_state from ETS");

  (* 5. Verify Gleam state in ETS / Zenoh *)
  (match get_ets_state "gleam_state" with
   | Some content ->
       Printf.printf "[OCAML-HERMES] Observed Gleam state in ETS: %s\n%!" (String.trim content);
       assert (string_contains content "GLEAM_OTP29_SUPERVISOR_ACTIVE")
   | None ->
       Printf.printf "[OCAML-HERMES] Warning: gleam_state not yet in ETS\n%!");

  (* 6. Read tri-language state summary *)
  (match get_tri_language_state () with
   | Some content ->
       Printf.printf "[OCAML-HERMES] Tri-Language State Summary: %s\n%!" (String.trim content);
       assert (string_contains content "GLEAM_OTP29_SUPERVISOR_ACTIVE");
       assert (string_contains content "OCAML_HERMES_ORACLE_ACTIVE")
   | None ->
       failwith "Failed to fetch /api/v1/state/tri_language");

  (* 7. Publish fractal telemetry hooks to Zenoh & ETS *)
  let now = Unix.gettimeofday () in
  let telem_payload = Printf.sprintf "{\"subsystem\":\"Hermes_Engine\",\"language\":\"OCaml\",\"status\":\"PASSED\",\"fractal_layer\":\"L3_TRANSACTION\",\"timestamp\":%.3f}" now in
  let _ = http_put (Printf.sprintf "%s/c3i/testing/events/ocaml" zenoh_base) telem_payload in
  let _ = http_put (Printf.sprintf "%s/indrajaal/otel/ops/testing/ocaml" zenoh_base) telem_payload in
  let _ = put_ets_state "test:ocaml:status" "PASSED" in
  let _ = put_ets_state "test:ocaml:timestamp" (Printf.sprintf "%.3f" now) in
  let _ = put_ets_state "test:ocaml:runner" "tools/tri_language_state_runner.ml" in
  Printf.printf "[OCAML-HERMES] Telemetry hooks published to Zenoh (c3i/testing/events/ocaml) and ETS (test:ocaml:status)\n%!";

  Printf.printf "========================================================\n%!";
  Printf.printf "[OCAML-HERMES] ALL OCAML ZENOH/ETS PARITY CHECKS PASSED!\n%!";
  Printf.printf "========================================================\n%!"

let () =
  try
    run_test ();
    exit 0
  with exn ->
    Printf.eprintf "[OCAML-HERMES] Test encountered exception: %s\n%!" (Printexc.to_string exn);
    exit 1
