#use "topfind";;
#require "yojson";;

(* Bounded EV-02 mapping verifier.  The mapping is a current amendment
   proposal: even a structurally complete map reports HOLD until an
   independent semantic review.  Full rule bodies are compared after only the
   surface adaptations agreed with AGY: the known always_on header and surface
   local link prefixes. *)

type rule = { id : string; file : string; anchor : string }

let max_rules = 64
let max_bytes = 1_048_576
let surfaces = [".agents/rules"; ".claude/rules"; ".gemini/rules"; ".codex/rules"]

let sort_unique xs = List.sort_uniq String.compare xs
let contains xs value = List.mem value xs
let read_bounded path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
    let length = in_channel_length channel in
    if length < 0 || length > max_bytes then None
    else Some (really_input_string channel length))

let replace_all ~needle ~replacement text =
  let n = String.length needle in
  if n = 0 then text else
  let buffer = Buffer.create (String.length text) in
  let rec loop start =
    match String.index_from_opt text start needle.[0] with
    | None -> Buffer.add_substring buffer text start (String.length text - start)
    | Some at when at + n <= String.length text && String.sub text at n = needle ->
        Buffer.add_substring buffer text start (at - start);
        Buffer.add_string buffer replacement;
        loop (at + n)
    | Some at ->
        Buffer.add_substring buffer text start (at - start + 1);
        loop (at + 1)
  in
  loop 0;
  Buffer.contents buffer

let normalize body =
  let header = "---\ntrigger: always_on\n---\n\n" in
  let without_header =
    if String.starts_with ~prefix:header body then
      String.sub body (String.length header) (String.length body - String.length header)
    else body
  in
  List.fold_left
    (fun text locator -> replace_all ~needle:locator ~replacement:"<surface-policy-link>/" text)
    without_header [
      "http://nas-1.tail55d152.ts.net:4100/docs/.agents/rules/";
      "http://nas-1.tail55d152.ts.net:4100/docs/.claude/rules/";
      "http://nas-1.tail55d152.ts.net:4100/docs/.gemini/rules/";
      "http://nas-1.tail55d152.ts.net:4100/docs/.codex/rules/";
      "http://nas-1.tail55d152.ts.net:4100/files/.agents/rules/";
      "http://nas-1.tail55d152.ts.net:4100/files/.claude/rules/";
      "http://nas-1.tail55d152.ts.net:4100/files/.gemini/rules/";
      "http://nas-1.tail55d152.ts.net:4100/files/.codex/rules/" ]

let ids_from_superset path =
  let channel = open_in path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
    let ids = ref [] in
    let awaiting_id = ref false in
    try
      while true do
        let line = String.trim (input_line channel) in
        if line = "[[directive]]" then awaiting_id := true
        else if !awaiting_id && String.starts_with ~prefix:"id = \"" line then begin
          let start = String.length "id = \"" in
          match String.index_from_opt line start '"' with
          | None -> raise (Failure "unterminated directive id")
          | Some stop ->
              ids := String.sub line start (stop - start) :: !ids;
              awaiting_id := false
        end
      done;
      []
    with End_of_file -> List.rev !ids)

let rules_from_json path =
  let json = Yojson.Basic.from_file path in
  match json with
  | `Assoc fields -> begin match List.assoc_opt "rules" fields with
      | Some (`List rows) ->
          rows |> List.map (function
            | `List [`String id; `String file; `String anchor] -> { id; file; anchor }
            | _ -> raise (Failure "mapping rule must be [id,file,anchor]"))
      | _ -> raise (Failure "mapping has no rules list")
    end
  | _ -> raise (Failure "mapping root must be an object")

let exact_line text expected =
  String.split_on_char '\n' text |> List.exists (fun line -> line = expected)

let duplicate values =
  let rec loop seen = function
    | [] -> false
    | value :: rest -> if contains seen value then true else loop (value :: seen) rest
  in loop [] values

let quote value = Yojson.Basic.to_string (`String value)
let json_strings values = values |> List.map quote |> String.concat ","

type observation = {
  directive_ids : string list;
  rules : rule list;
  rule_rows : (rule * bool * int * bool) list;
  mapping_errors : string list;
  body_differences : (string * string) list;
  unmapped_shared_files : string list;
}

let observe root mapping_path =
  let directive_ids = ids_from_superset (Filename.concat root "governance/agents/policy/superset.toml") in
  let rules = rules_from_json mapping_path in
  let ids = List.map (fun rule -> rule.id) rules in
  let mapping_errors = ref [] in
  if List.length directive_ids <> 38 then mapping_errors := "superset-directive-count" :: !mapping_errors;
  if List.length rules <> 38 then mapping_errors := "mapping-rule-count" :: !mapping_errors;
  if duplicate ids then mapping_errors := "duplicate-mapping-id" :: !mapping_errors;
  if sort_unique ids <> sort_unique directive_ids then mapping_errors := "directive-id-set" :: !mapping_errors;
  let mapped_files = rules |> List.map (fun rule -> rule.file) |> sort_unique in
  let rule_rows = List.map (fun rule ->
    let canonical_path = Filename.concat root (Filename.concat ".claude/rules" rule.file) in
    match read_bounded canonical_path with
    | None ->
        mapping_errors := ("unreadable-canonical:" ^ rule.id) :: !mapping_errors;
        rule, false, 0, false
    | Some canonical ->
        let anchor_present = exact_line canonical rule.anchor in
        if not anchor_present then
          mapping_errors := ("missing-anchor:" ^ rule.id) :: !mapping_errors;
        let bodies = surfaces |> List.filter_map (fun surface ->
          let path = Filename.concat root (Filename.concat surface rule.file) in
          read_bounded path |> Option.map (fun body -> surface, normalize body)) in
        if List.length bodies <> List.length surfaces then
          mapping_errors := ("missing-surface:" ^ rule.id) :: !mapping_errors;
        let normalized_equal = match bodies with
          | [] -> false
          | (_, first) :: rest -> List.for_all (fun (_, body) -> body = first) rest in
        rule, anchor_present, List.length bodies, normalized_equal
  ) rules in
  let body_differences =
    rule_rows |> List.filter_map (fun (rule, _, surface_count, normalized_equal) ->
      if surface_count = List.length surfaces && not normalized_equal then Some (rule.id, rule.file) else None) in
  let shared_files =
    surfaces |> List.map (fun surface ->
      Sys.readdir (Filename.concat root surface) |> Array.to_list
      |> List.filter (fun name -> Filename.check_suffix name ".md" && name <> "README.md")
      |> sort_unique)
    |> function [] -> [] | first :: rest -> List.filter (fun name -> List.for_all (fun names -> contains names name) rest) first
  in
  { directive_ids; rules; rule_rows; mapping_errors = List.rev !mapping_errors;
    body_differences;
    unmapped_shared_files = List.filter (fun file -> not (contains mapped_files file)) shared_files }

let print observation =
  let errors = observation.mapping_errors @
    (if observation.body_differences = [] then [] else ["normalized-body-difference"]) @
    ["proposal-not-independently-reviewed"] in
  let status = if errors = ["proposal-not-independently-reviewed"] then "HOLD" else "HOLD" in
  let body_differences = observation.body_differences |> List.map (fun (id, file) ->
    "{\"id\":" ^ quote id ^ ",\"file\":" ^ quote file ^ "}") |> String.concat "," in
  let rule_rows = observation.rule_rows |> List.map (fun (rule, anchor_present, surface_count, normalized_equal) ->
    "{\"id\":" ^ quote rule.id ^ ",\"canonical_file\":" ^ quote rule.file ^
    ",\"anchor\":" ^ quote rule.anchor ^ ",\"anchor_present\":" ^ string_of_bool anchor_present ^
    ",\"surface_count\":" ^ string_of_int surface_count ^
    ",\"normalized_body_equal\":" ^ string_of_bool normalized_equal ^ "}") |> String.concat "," in
  Printf.printf
    "{\"schema\":\"uos.ev02-directive-mapping/v1\",\"authority\":\"REPORT_ONLY\",\"historical_lineage\":\"MISSING_HISTORICAL_LINEAGE\",\"admission\":\"NOT_GRANTED\",\"status\":\"%s\",\"directive_count\":%d,\"mapping_rule_count\":%d,\"rule_rows\":[%s],\"mapping_errors\":[%s],\"normalized_body_differences\":[%s],\"unmapped_shared_rule_files\":[%s],\"errors\":[%s]}\n"
    status (List.length observation.directive_ids) (List.length observation.rules)
    rule_rows (json_strings observation.mapping_errors) body_differences
    (json_strings observation.unmapped_shared_files) (json_strings errors)

let selftest () =
  let check label actual = if not actual then failwith ("selftest failed: " ^ label) in
  check "known-header" (normalize "---\ntrigger: always_on\n---\n\nSee http://nas-1.tail55d152.ts.net:4100/docs/.agents/rules/a" = "See <surface-policy-link>/a");
  check "prose-not-erased" (normalize "MUST preserve .agents/rules/a as normative prose" = "MUST preserve .agents/rules/a as normative prose");
  check "duplicate-id" (duplicate ["DIR-A"; "DIR-A"]);
  check "set-mismatch" (sort_unique ["DIR-A"] <> sort_unique ["DIR-B"]);
  check "anchor-is-line" (not (exact_line "## Section x" "## Section"));
  print_endline "PASS directive-mapping selftest: normalization/duplicate/set/anchor"

let () =
  match Array.to_list Sys.argv with
  | [_; "--selftest"] -> selftest ()
  | [_; "--observe"; root; mapping] ->
      let result = observe root mapping in
      print result;
      exit 1
  | _ -> failwith "usage: directive_mapping_gate.ml --selftest | --observe ROOT MAPPING"
