(* Battle-testing the deterministic replay executor.

   The load-bearing property, borrowed from the prior zigvm harness's
   "proven-not-differential trap": it is not enough that submit returns
   something -- the decoded output must genuinely reflect the RECORDED response,
   so a different recording yields a different decode. Otherwise a replay could
   pass while exercising nothing. Plus: replay is byte-identical run to run, and
   a miss refuses rather than reaching the network. *)

let body = `Assoc [ ("model", `String "m"); ("messages", `List []) ]
let body_str = Yojson.Safe.to_string body
let req = Openrouter_contract.{ endpoint = "https://replay.invalid"; api_key = Some "k"; body }

let response ~content ~id =
  Printf.sprintf {|{"id":"%s","choices":[{"finish_reason":"stop","message":{"content":"%s"}}]}|} id content

let () =
  let open Replay_executor in
  let run response_body =
    Openrouter_transport.submit
      ~execute:(executor (record ~request_body:body_str ~status:200 ~response_body empty))
      req
  in
  (* Hit: the decode reflects the recorded response. *)
  (match run (response ~content:"hi" ~id:"c1") with
  | Ok r ->
      assert (r.Openrouter_transport.content = Some "hi");
      assert (r.Openrouter_transport.id = Some "c1")
  | Error _ -> assert false);

  (* Proven differential: a DIFFERENT recording yields a DIFFERENT decode, so
     submit genuinely consumes the recorded response. *)
  (match run (response ~content:"bye" ~id:"c2") with
  | Ok r ->
      assert (r.Openrouter_transport.content = Some "bye");
      assert (r.Openrouter_transport.id = Some "c2")
  | Error _ -> assert false);

  (* Deterministic: identical replays are byte-identical. *)
  let recording = record ~request_body:body_str ~status:200 ~response_body:(response ~content:"hi" ~id:"c1") empty in
  assert (
    Openrouter_transport.submit ~execute:(executor recording) req
    = Openrouter_transport.submit ~execute:(executor recording) req);

  (* Miss: an unrecorded request refuses -- there is no network path to take. *)
  (match Openrouter_transport.submit ~execute:(executor empty) req with
  | Error (Openrouter_transport.Transport_error message) ->
      assert (String.length message > 0)
  | _ -> assert false);

  (* A non-2xx recorded status is surfaced as an Http_error, faithfully. *)
  (match
     Openrouter_transport.submit
       ~execute:(executor (record ~request_body:body_str ~status:503 ~response_body:"overloaded" empty))
       req
   with
  | Error (Openrouter_transport.Http_error 503) -> ()
  | _ -> assert false);

  assert (size empty = 0);
  assert (size (of_list [ (body_str, (200, response ~content:"hi" ~id:"c1")) ]) = 1);
  print_endline "replay_executor: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_replay_executor" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_replay_executor ]);
  exit (Suite_telemetry.exit_code self)
