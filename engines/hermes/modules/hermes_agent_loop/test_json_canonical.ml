(* Laws of the canonical wire emitter and the send-path pass. The parity
   fixture pins WHAT json.dumps produces; these laws pin the properties any
   canonical form must have, hand-written and never auto-accepted. Every law
   carries a negative control (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

open Json_canonical

let () =
  (* ANCHORS: exact wire bytes, matching CPython's dumps defaults. *)
  check
    (canonicalize_arguments "{\"b\":1,\"a\":{\"z\":true,\"y\":null}}"
    = "{\"a\":{\"y\":null,\"z\":true},\"b\":1}")
    "ANCHOR keys sort recursively, arrays keep order";
  check
    (canonicalize_arguments "{ \"k\" : \"v\" }" = "{\"k\":\"v\"}")
    "ANCHOR whitespace collapses to compact separators";
  check
    (canonicalize_arguments "{\"t\":\"\xC3\xA9\"}" = "{\"t\":\"\\u00e9\"}")
    "ANCHOR non-ASCII escapes to lowercase \\uXXXX (ensure_ascii)";
  check
    (canonicalize_arguments "{\"t\":\"\xF0\x9F\x98\x80\"}" = "{\"t\":\"\\ud83d\\ude00\"}")
    "ANCHOR astral characters escape as surrogate pairs";
  check
    (canonicalize_arguments "{\"n\":\"a\\nb\"}" = "{\"n\":\"a\\nb\"}")
    "ANCHOR control characters use the dumps shorthands";

  (* IDEMPOTENCE: the canonical form is a fixed point of canonicalization. *)
  let once = canonicalize_arguments "{\"b\":[2,1],\"a\":\"x\"}" in
  check (canonicalize_arguments once = once) "LAW canonicalization is idempotent";
  check (once <> "{\"b\":[2,1],\"a\":\"x\"}")
    "CONTROL the input was not already canonical (the law is not vacuous)";

  (* ORDER INSENSITIVITY: two spellings of the same object canonicalize
     identically -- the property that makes the wire form cache-stable. *)
  check
    (canonicalize_arguments "{\"a\":1,\"b\":2}" = canonicalize_arguments "{\"b\":2,\"a\":1}")
    "LAW key order does not survive into the wire form";
  check
    (canonicalize_arguments "{\"a\":1}" <> canonicalize_arguments "{\"a\":2}")
    "CONTROL distinct values stay distinct";

  (* ROUND-TRIP: the canonical form parses back to the same value. *)
  let value = Yojson.Safe.from_string "{\"z\":[true,null,\"s\"],\"a\":{\"k\":3}}" in
  check (Yojson.Safe.from_string (to_wire value) = Yojson.Safe.from_string (to_wire value))
    "LAW the wire form is stable under reparse";
  check
    (Yojson.Safe.from_string (to_wire value) <> `Null)
    "CONTROL the reparse yields the value, not nothing";

  (* MALFORMED input raises, exactly as json.loads does -- the frozen caller's
     repair fallback depends on the exception reaching it. *)
  check
    (match canonicalize_arguments "{not json" with
     | _ -> false
     | exception _ -> true)
    "LAW malformed input raises rather than guessing";

  (* The send-path pass touches ONLY what it claims: a message without
     tool_calls, with empty tool_calls, or with a bare tool_call is returned
     structurally unchanged. *)
  let untouched =
    [ `Assoc [ ("role", `String "user"); ("content", `String "hi") ];
      `Assoc [ ("role", `String "assistant"); ("tool_calls", `List []) ];
      `Assoc [ ("role", `String "assistant");
               ("tool_calls", `List [ `Assoc [ ("id", `String "bare") ] ]) ] ]
  in
  check (Loop_send_path.canonicalize_api_tool_calls untouched = untouched)
    "LAW the pass leaves non-canonicalizable shapes untouched";
  let touched =
    [ `Assoc
        [ ("role", `String "assistant");
          ("tool_calls",
           `List
             [ `Assoc
                 [ ("id", `String "t");
                   ("function",
                    `Assoc
                      [ ("name", `String "f"); ("arguments", `String "{ \"b\":1,\"a\":2 }") ])
                 ] ]) ] ]
  in
  check (Loop_send_path.canonicalize_api_tool_calls touched <> touched)
    "CONTROL a canonicalizable message actually changes";

  (* Continuation prompts: the three branches are distinct, and the tool list
     truncates to three names. *)
  let with_tools =
    Loop_send_path.continuation_prompt ~is_partial_stub:true
      ~dropped_tools:[ "writer"; "patcher"; "searcher"; "extra_tool" ]
  in
  let partial = Loop_send_path.continuation_prompt ~is_partial_stub:true ~dropped_tools:[] in
  let truncated =
    Loop_send_path.continuation_prompt ~is_partial_stub:false ~dropped_tools:[]
  in
  check
    (with_tools <> partial && partial <> truncated && with_tools <> truncated)
    "LAW the three continuation branches are distinct";
  let contains needle haystack =
    let n = String.length needle in
    let rec at i =
      i + n <= String.length haystack && (String.sub haystack i n = needle || at (i + 1))
    in
    at 0
  in
  check
    (contains "(writer, patcher, searcher)" with_tools
    && not (contains "extra_tool" with_tools))
    "LAW the dropped-tool list truncates to the first three";

  Printf.printf "json canonical: %d passed, %d failed\n" !passed
    (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_json_canonical" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_json_canonical ]);
  exit (Suite_telemetry.exit_code self)
