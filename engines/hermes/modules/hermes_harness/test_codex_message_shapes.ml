(* Unit cases for the Codex Responses shaping trio. The captured fixture PROVES
   faithfulness; these guard the branches: role-driven text_type, text/image part
   handling, the dict-image detail override, status normalization, and the
   summary with image counting. *)

let json = Yojson.Safe.from_string
let s v = Yojson.Safe.to_string v

let () =
  let open Codex_message_shapes in
  (* text parts: role assistant -> output_text, else input_text; empty dropped *)
  assert (
    s (chat_content_to_responses_parts ~role:"user" ~content:(json {|["hi","",{"type":"text","text":"there"}]|}))
    = {|[{"type":"input_text","text":"hi"},{"type":"input_text","text":"there"}]|});
  assert (
    s (chat_content_to_responses_parts ~role:"assistant" ~content:(json {|["yo"]|}))
    = {|[{"type":"output_text","text":"yo"}]|});
  (* non-list content -> [] *)
  assert (s (chat_content_to_responses_parts ~role:"user" ~content:(json {|"x"|})) = "[]");
  (* image dict with url + dict image_url detail override *)
  assert (
    s (chat_content_to_responses_parts ~role:"user"
         ~content:(json {|[{"type":"image_url","image_url":{"url":"http://x/i.png","detail":"high"}}]|}))
    = {|[{"type":"input_image","image_url":"http://x/i.png","detail":"high"}]|});
  (* image with missing/empty url -> dropped *)
  assert (
    s (chat_content_to_responses_parts ~role:"user" ~content:(json {|[{"type":"input_image","image_url":""}]|}))
    = "[]");
  (* a text-typed part never falls into the image branch *)
  assert (
    s (chat_content_to_responses_parts ~role:"user"
         ~content:(json {|[{"type":"text","text":"t","image_url":"http://x"}]|}))
    = {|[{"type":"input_text","text":"t"}]|});

  (* status normalization *)
  assert (normalize_responses_message_status (json {|"Completed"|}) ~default:"completed" = "completed");
  assert (normalize_responses_message_status (json {|" in-progress "|}) ~default:"completed" = "in_progress");
  assert (normalize_responses_message_status (json {|"in  progress"|}) ~default:"completed" = "completed");
  assert (normalize_responses_message_status (json {|"weird"|}) ~default:"completed" = "completed");
  assert (normalize_responses_message_status `Null ~default:"completed" = "completed");
  assert (normalize_responses_message_status (json {|"incomplete"|}) ~default:"completed" = "incomplete");

  (* summary: null/string, list with text + images *)
  assert (summarize_user_message_for_log ~content:`Null ~sep:" " = "");
  assert (summarize_user_message_for_log ~content:(json {|"  keep  "|}) ~sep:" " = "  keep  ");
  assert (
    summarize_user_message_for_log ~sep:" "
      ~content:(json {|["a","b",{"type":"input_image","image_url":"u"}]|})
    = "[1 image] a b");
  assert (
    summarize_user_message_for_log ~sep:" "
      ~content:(json {|[{"type":"input_image","image_url":"u"},{"type":"image_url"}]|})
    = "[2 images]");
  assert (summarize_user_message_for_log ~content:(json "42") ~sep:" " = "42");

  print_endline "codex_message_shapes: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_codex_message_shapes" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_codex_message_shapes ]);
  exit (Suite_telemetry.exit_code self)
