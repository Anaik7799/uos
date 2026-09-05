(* Capture pinned SESSION fixtures for the deterministic-replay track.

   Offline (option a): each session's provider response is a pinned decode input,
   run through the reference decoder via the normalize_response adapter to produce
   the reference decode half. The request, provider response and reference decode
   are bound into a digest-pinned Session_fixture. No network -- normalize_response
   is a pure decode of a recorded response. Deliberate and explicit: it writes
   evidence. *)

let git_revision root =
  let command = "git -C " ^ Filename.quote root ^ " rev-parse HEAD" in
  try
    let channel = Unix.open_process_in command in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> Ok (String.trim (input_line channel)))
  with End_of_file -> Error "cannot determine reference revision"
     | Unix.Unix_error (_, _, message) -> Error message

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  let reference_root = Bootstrap.reference_root root in
  match Inventory.scan ~root:reference_root with
  | Error message -> prerr_endline message; exit 1
  | Ok entries -> (
      let snapshot_digest = Inventory.snapshot_digest entries in
      match git_revision reference_root with
      | Error message -> prerr_endline message; exit 1
      | Ok reference_revision ->
          let normalizer = Parity_normalizer.default in
          Printf.printf "snapshot: %s\nreference: %s\n\n" snapshot_digest reference_revision;
          let failures = ref 0 in
          List.iter
            (fun (session_id, request, provider_response) ->
              (* Decode the provider response through the reference to get the
                 oracle decode half -- the same adapter capture_decode_traces uses. *)
              let scenario : Reference_capture.scenario =
                { id = session_id; model = ""; messages = []; tools = None;
                  params = [ ("response", provider_response) ] }
              in
              match
                Reference_capture.capture ~adapter_basename:"normalize_response_adapter.py"
                  ~root ~snapshot_digest ~reference_revision ~normalizer scenario
              with
              | Error failure ->
                  incr failures;
                  Printf.printf "  %-22s FAILED %s\n" session_id
                    (Reference_capture.describe failure)
              | Ok capture ->
                  let session =
                    Session_fixture.make ~normalizer ~session_id ~snapshot_digest
                      ~reference_revision ~request ~provider_response
                      ~reference_decode:capture.Reference_capture.trace
                  in
                  let path = Session_fixture.save ~root session in
                  Printf.printf "  %-22s %s\n    %s\n" session_id
                    session.Session_fixture.normalized_digest (Filename.basename path))
            Parity_compare.session_scenarios;
          Printf.printf "\ncaptured %d/%d session fixtures\n"
            (List.length Parity_compare.session_scenarios - !failures)
            (List.length Parity_compare.session_scenarios);
          if !failures > 0 then exit 1)
