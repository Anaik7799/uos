(* Unit cases for the Anthropic shaping trio. The captured differential fixture
   PROVES faithfulness; these guard the load-bearing branches, especially the
   recursive anyOf/oneOf collapse in strip_nullable_unions. *)

let json = Yojson.Safe.from_string
let s v = Yojson.Safe.to_string v

let () =
  let open Anthropic_adapter in
  (* sanitize_tool_id *)
  assert (sanitize_tool_id "" = "tool_0");
  assert (sanitize_tool_id "call.abc:9/z" = "call_abc_9_z");
  assert (sanitize_tool_id "!!!" = "___");
  assert (sanitize_tool_id "keep-9_A" = "keep-9_A");

  (* is_bedrock + normalize_model_name *)
  assert (is_bedrock_model_id "us.anthropic.claude-3");
  assert (is_bedrock_model_id "anthropic.claude-v2");
  assert (not (is_bedrock_model_id "claude-3.5-sonnet"));
  assert (normalize_model_name "anthropic/claude-3.5-sonnet" = "claude-3-5-sonnet");
  assert (normalize_model_name "claude-3.7" = "claude-3-7");
  assert (normalize_model_name "us.anthropic.claude-3.5" = "us.anthropic.claude-3.5");
  assert (normalize_model_name "gpt-5.4" = "gpt-5.4");
  assert (normalize_model_name "gemini-2.5-pro" = "gemini-2.5-pro");

  (* strip_nullable_unions: {anyOf:[{type:string},{type:null}]} collapses to
     {type:string}, dropping the null branch, carrying no nullable hint. *)
  assert (
    s (strip_nullable_unions (json {|{"anyOf":[{"type":"string"},{"type":"null"}]}|}))
    = {|{"type":"string"}|});
  (* two non-null branches -> NOT collapsed *)
  assert (
    s (strip_nullable_unions (json {|{"anyOf":[{"type":"string"},{"type":"number"}]}|}))
    = {|{"anyOf":[{"type":"string"},{"type":"number"}]}|});
  (* metadata carried when absent from the survivor *)
  assert (
    s (strip_nullable_unions (json {|{"description":"d","anyOf":[{"type":"integer"},{"type":"null"}]}|}))
    = {|{"type":"integer","description":"d"}|});
  (* collapse applies inside properties (nested) *)
  assert (
    s (strip_nullable_unions
         (json {|{"type":"object","properties":{"x":{"anyOf":[{"type":"boolean"},{"type":"null"}]}}}|}))
    = {|{"type":"object","properties":{"x":{"type":"boolean"}}}|});

  (* normalize_tool_input_schema: falsy -> default object *)
  assert (s (normalize_tool_input_schema `Null) = {|{"type":"object","properties":{}}|});
  assert (s (normalize_tool_input_schema (json "{}")) = {|{"type":"object","properties":{}}|});
  (* top-level banned key stripped, type appended if missing *)
  assert (
    s (normalize_tool_input_schema (json {|{"oneOf":[{"type":"object"}],"properties":{}}|}))
    = {|{"properties":{},"type":"object"}|});
  (* type:object with non-dict properties -> properties repaired to {} *)
  assert (
    s (normalize_tool_input_schema (json {|{"type":"object","properties":"nope"}|}))
    = {|{"type":"object","properties":{}}|});

  (* convert_tools_to_anthropic: falsy -> [] *)
  assert (s (convert_tools_to_anthropic (`List [])) = "[]");
  assert (s (convert_tools_to_anthropic `Null) = "[]");
  (* one tool: name/description/input_schema, default schema when no parameters *)
  assert (
    s (convert_tools_to_anthropic
         (json {|[{"type":"function","function":{"name":"f","description":"d"}}]|}))
    = {|[{"name":"f","description":"d","input_schema":{"type":"object","properties":{}}}]|});
  (* dedup first-wins on non-empty name *)
  (match convert_tools_to_anthropic
           (json {|[{"function":{"name":"g","description":"1"}},{"function":{"name":"g","description":"2"}}]|})
   with
  | `List [ `Assoc first ] -> assert (List.assoc_opt "description" first = Some (`String "1"))
  | _ -> failwith "dedup first-wins failed");
  (* cache_control dict is copied through, after input_schema *)
  (match convert_tools_to_anthropic
           (json {|[{"function":{"name":"h"},"cache_control":{"type":"ephemeral"}}]|})
   with
  | `List [ `Assoc t ] ->
      assert (List.mem_assoc "cache_control" t);
      assert (List.assoc_opt "cache_control" t = Some (`Assoc [ ("type", `String "ephemeral") ]))
  | _ -> failwith "cache_control passthrough failed");

  print_endline "anthropic_adapter: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_anthropic_adapter" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_anthropic_adapter ]);
  exit (Suite_telemetry.exit_code self)
