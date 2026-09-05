(* Battle-testing the session fixture keystone.

   The load-bearing property, mirrored from Reference_capture and the zigvm
   fixture-freshness law: a session's normalized digest is re-derived from its
   stored reference decode on load, so an edited fixture is REJECTED, never
   trusted (HZ-FIX-01). Plus a clean round-trip and honest absence handling. *)

let normalizer = Parity_normalizer.default

let temp_dir () =
  let path = Filename.temp_file "session-fixture-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let read_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let write_file path contents =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel contents)

(* naive substring replace of the first occurrence *)
let replace_first haystack needle replacement =
  let hl = String.length haystack and nl = String.length needle in
  let rec find i = if i + nl > hl then -1 else if String.sub haystack i nl = needle then i else find (i + 1) in
  match find 0 with
  | -1 -> haystack
  | i -> String.sub haystack 0 i ^ replacement ^ String.sub haystack (i + nl) (hl - i - nl)

let () =
  let root = temp_dir () in
  let snapshot = "abc123def456ff" in
  let request =
    Session_fixture.{ endpoint = "https://replay.invalid"; body = `Assoc [ ("model", `String "m") ] }
  in
  let provider_response = `Assoc [ ("id", `String "c1"); ("choices", `List []) ] in
  let reference_decode =
    `Assoc [ ("content", `String "hi"); ("finish_reason", `String "stop") ]
  in
  let session =
    Session_fixture.make ~normalizer ~session_id:"sess.basic" ~snapshot_digest:snapshot
      ~reference_revision:"rev1" ~request ~provider_response ~reference_decode
  in
  assert (String.length session.Session_fixture.normalized_digest = 64);

  (* Round-trip: save then load yields the same session. *)
  let path = Session_fixture.save ~root session in
  assert (Filename.check_suffix path ".json");
  (match Session_fixture.load ~root ~normalizer "sess.basic" ~snapshot_digest:snapshot with
  | Ok loaded -> assert (loaded = session)
  | Error e -> failwith ("round-trip load: " ^ Session_fixture.describe e));

  (* The freshness law: tamper the stored reference decode; load must reject it
     because the re-derived digest no longer matches. *)
  let tampered = replace_first (read_file path) "\"hi\"" "\"TAMPERED\"" in
  write_file path tampered;
  (match Session_fixture.load ~root ~normalizer "sess.basic" ~snapshot_digest:snapshot with
  | Error (Session_fixture.Digest_mismatch _) -> ()
  | Ok _ -> failwith "an edited session must be rejected, not trusted"
  | Error e -> failwith ("expected Digest_mismatch, got " ^ Session_fixture.describe e));

  (* Absence is Missing, never a silent empty. *)
  (match Session_fixture.load ~root ~normalizer "sess.nope" ~snapshot_digest:snapshot with
  | Error (Session_fixture.Missing _) -> ()
  | _ -> failwith "a missing session must be Missing");

  (* fixture_path keys on session id and the short snapshot digest. *)
  let p = Session_fixture.fixture_path ~root "sess.k" ~snapshot_digest:snapshot in
  assert (
    let base = Filename.basename p in
    String.length base > 0
    && (let contains s n =
          let sl = String.length s and nl = String.length n in
          let rec f i = i + nl <= sl && (String.sub s i nl = n || f (i + 1)) in
          f 0
        in
        contains base "sess.k" && contains base (String.sub snapshot 0 12)));

  print_endline "session_fixture: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_session_fixture" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_session_fixture ]);
  exit (Suite_telemetry.exit_code self)
