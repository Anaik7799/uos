(* Unit cases for the Gemini schema sanitizer. The captured fixture PROVES
   faithfulness; these guard the branches: disallowed-key stripping, recursion
   into properties/items, enum stringify+dedupe for integer type, required
   filtered against properties, nested required-without-properties dropped, and
   the empty-result object stub. *)

let json = Yojson.Safe.from_string
let s v = Yojson.Safe.to_string v

let () =
  let open Gemini_schema in
  (* empty result -> object stub *)
  assert (s (sanitize_tool_parameters (json "{}")) = {|{"type":"object","properties":{}}|});
  assert (s (sanitize_tool_parameters (json "42")) = {|{"type":"object","properties":{}}|});

  (* the S11 shape, end to end *)
  let params =
    json
      {|{"$schema":"x","type":"object","additionalProperties":false,"properties":{"q":{"type":"string","minLength":1},"mode":{"type":"integer","enum":[1,2,1]},"tags":{"type":"array","items":{"type":"string","format":"slug"},"required":["oops"]}},"required":["q","missing"]}|}
  in
  assert (
    s (sanitize_tool_parameters params)
    = {|{"type":"object","properties":{"q":{"type":"string","minLength":1},"mode":{"type":"integer","enum":["1","2"]},"tags":{"type":"array","items":{"type":"string","format":"slug"}}},"required":["q"]}|});

  (* anyOf keeps only dict elements, each sanitized *)
  assert (
    s (sanitize (json {|{"anyOf":[{"type":"string","bogus":1},"junk",{"type":"integer"}]}|}))
    = {|{"anyOf":[{"type":"string"},{"type":"integer"}]}|});

  (* required dropped entirely when nothing survives *)
  assert (
    s (sanitize (json {|{"type":"object","required":["gone"]}|})) = {|{"type":"object"}|});

  print_endline "gemini_schema: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_gemini_schema" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_gemini_schema ]);
  exit (Suite_telemetry.exit_code self)
