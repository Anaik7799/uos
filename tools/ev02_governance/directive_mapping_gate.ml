#use "topfind";;
#require "yojson";;
#load "unix.cma";;

(* Bounded EV-02 mapping verifier.  The mapping is a current amendment
   proposal: even a structurally complete map reports HOLD until an
   independent semantic review.  Full rule bodies are compared after only the
   surface adaptations agreed with AGY: the known always_on header and surface
   local link prefixes. *)

type rule = { id : string; file : string; anchor : string }

let max_rules = 64
let max_bytes = 1_048_576
let max_total_bytes = 16_777_216
let surfaces = [".agents/rules"; ".claude/rules"; ".gemini/rules"; ".codex/rules"]

let sort_unique xs = List.sort_uniq String.compare xs
let contains xs value = List.mem value xs
let has_duplicate values =
  let rec loop seen = function
    | [] -> false
    | value :: rest -> if contains seen value then true else loop (value :: seen) rest
  in loop [] values
let bounded_error label = raise (Failure ("invalid-input:" ^ label))
let attempt thunk = try Ok (thunk ()) with Failure detail -> Error detail
let regular stat = stat.Unix.st_kind = Unix.S_REG
let same_file a b = a.Unix.st_dev = b.Unix.st_dev && a.Unix.st_ino = b.Unix.st_ino

let read_regular ~budget path =
  let listed = try Unix.lstat path with Unix.Unix_error _ -> bounded_error "missing-or-unreadable" in
  if not (regular listed) then bounded_error ("not-regular:" ^ path);
  if listed.Unix.st_size < 0 || listed.Unix.st_size > max_bytes then bounded_error "file-size";
  if !budget + listed.Unix.st_size > max_total_bytes then bounded_error "aggregate-size";
  (* This OCaml runtime lacks O_NOFOLLOW.  We lstat, open without reading,
     fstat the descriptor, and refuse any identity change before Unix.read. *)
  let fd = try Unix.openfile path [Unix.O_RDONLY; Unix.O_NONBLOCK; Unix.O_CLOEXEC] 0
    with Unix.Unix_error _ -> bounded_error "open-refused" in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
    let opened = Unix.fstat fd in
    if not (regular opened) || not (same_file listed opened) || opened.Unix.st_size <> listed.Unix.st_size then
      bounded_error "file-identity";
    let bytes = Bytes.create opened.Unix.st_size in
    let rec read_at offset =
      if offset = Bytes.length bytes then () else
      let read = Unix.read fd bytes offset (Bytes.length bytes - offset) in
      if read = 0 then bounded_error "short-read" else read_at (offset + read)
    in
    read_at 0;
    let closed = Unix.fstat fd in
    if not (same_file opened closed) || closed.Unix.st_size <> opened.Unix.st_size then bounded_error "file-changed";
    budget := !budget + Bytes.length bytes;
    Bytes.to_string bytes)

let list_rule_names path =
  let stat = try Unix.lstat path with Unix.Unix_error _ -> bounded_error "missing-rule-directory" in
  if stat.Unix.st_kind <> Unix.S_DIR then bounded_error "rule-directory-not-directory";
  let directory = try Unix.opendir path with Unix.Unix_error _ -> bounded_error "rule-directory-open" in
  Fun.protect ~finally:(fun () -> Unix.closedir directory) (fun () ->
    let rec loop names seen =
      match Unix.readdir directory with
      | entry ->
          if entry = "." || entry = ".." then loop names seen
          else if Filename.check_suffix entry ".md" && entry <> "README.md" then
            if seen >= max_rules then bounded_error "rule-directory-count"
            else loop (entry :: names) (seen + 1)
          else loop names seen
      | exception End_of_file -> sort_unique names
    in loop [] 0)

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

let ids_from_superset ~budget path =
  let lines = String.split_on_char '\n' (read_regular ~budget path) in
  let ids = ref [] in
  let awaiting_id = ref false in
  List.iter (fun raw ->
    let line = String.trim raw in
    if line = "[[directive]]" then awaiting_id := true
    else if !awaiting_id && String.starts_with ~prefix:"id = \"" line then begin
      let start = String.length "id = \"" in
      match String.index_from_opt line start '"' with
      | None -> bounded_error "unterminated-directive-id"
      | Some stop ->
          ids := String.sub line start (stop - start) :: !ids;
          awaiting_id := false
    end) lines;
  if !awaiting_id || List.length !ids > max_rules then bounded_error "directive-count";
  List.rev !ids

let rules_from_json ~budget path =
  let raw = read_regular ~budget path in
  let json = try Yojson.Basic.from_string raw with Yojson.Json_error _ -> bounded_error "mapping-json" in
  match json with
  | `Assoc fields -> begin match List.assoc_opt "rules" fields with
      | Some (`List rows) ->
          let allowed = ["schema"; "authority"; "historical_lineage"; "admission"; "normalization_base"; "rules"; "limits"] in
          if has_duplicate (List.map fst fields) || List.exists (fun (key, _) -> not (contains allowed key)) fields then
            bounded_error "mapping-schema";
          if List.length rows > max_rules then bounded_error "mapping-row-count";
          rows |> List.map (function
            | `List [`String id; `String file; `String anchor] -> { id; file; anchor }
            | _ -> bounded_error "mapping-rule-shape")
      | _ -> bounded_error "mapping-rules"
    end
  | _ -> bounded_error "mapping-root"

let exact_line text expected =
  String.split_on_char '\n' text |> List.exists (fun line -> line = expected)

let duplicate = has_duplicate

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
  let budget = ref 0 in
  let directive_ids = ids_from_superset ~budget (Filename.concat root "governance/agents/policy/superset.toml") in
  let rules = rules_from_json ~budget mapping_path in
  let shared_files =
    surfaces |> List.map (fun surface -> list_rule_names (Filename.concat root surface))
    |> function [] -> [] | first :: rest -> List.filter (fun name -> List.for_all (fun names -> contains names name) rest) first
  in
  let ids = List.map (fun rule -> rule.id) rules in
  let mapping_errors = ref [] in
  if List.length directive_ids <> 38 then mapping_errors := "superset-directive-count" :: !mapping_errors;
  if List.length rules <> 38 then mapping_errors := "mapping-rule-count" :: !mapping_errors;
  if duplicate ids then mapping_errors := "duplicate-mapping-id" :: !mapping_errors;
  if sort_unique ids <> sort_unique directive_ids then mapping_errors := "directive-id-set" :: !mapping_errors;
  let valid_file file =
    file = Filename.basename file && Filename.check_suffix file ".md" &&
    file <> "." && file <> ".." && not (String.contains file '/') && not (String.contains file '\\') in
  let mapped_files = rules |> List.map (fun rule -> rule.file) |> sort_unique in
  let rule_rows = List.map (fun rule ->
    if String.length rule.id = 0 || String.length rule.id > 128 ||
       String.length rule.anchor = 0 || String.length rule.anchor > 512 ||
       not (valid_file rule.file) || not (contains shared_files rule.file) then begin
        mapping_errors := ("invalid-rule-reference:" ^ rule.id) :: !mapping_errors;
        rule, false, 0, false
    end else begin
        let canonical_path = Filename.concat root (Filename.concat ".claude/rules" rule.file) in
        match attempt (fun () -> read_regular ~budget canonical_path) with
        | Error _ ->
            mapping_errors := ("canonical-read-refused:" ^ rule.id) :: !mapping_errors;
            rule, false, 0, false
        | Ok canonical ->
            let anchor_present = exact_line canonical rule.anchor in
            if not anchor_present then
              mapping_errors := ("missing-anchor:" ^ rule.id) :: !mapping_errors;
            let bodies = surfaces |> List.filter_map (fun surface ->
              let path = Filename.concat root (Filename.concat surface rule.file) in
              match attempt (fun () -> normalize (read_regular ~budget path)) with
              | Ok body -> Some (surface, body)
              | Error _ -> None) in
            if List.length bodies <> List.length surfaces then
              mapping_errors := ("surface-read-refused:" ^ rule.id) :: !mapping_errors;
            let normalized_equal = match bodies with
              | [] -> false
              | (_, first) :: rest -> List.for_all (fun (_, body) -> body = first) rest in
            rule, anchor_present, List.length bodies, normalized_equal
    end
  ) rules in
  let body_differences =
    rule_rows |> List.filter_map (fun (rule, _, surface_count, normalized_equal) ->
      if surface_count = List.length surfaces && not normalized_equal then Some (rule.id, rule.file) else None) in
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
    let source_clause, semantic_status, missing_facet =
      if rule.id = "DIR-TIME-001" then
        ("format_mandate=YYYYMMDD-HHSS-; description requires timestamp prefix; enforcement=tools/uos timestamp-check",
         "PARTIAL_HOLD", "Anchor presence and body parity do not prove enforcement execution or historic provenance")
      else
        ("status=CLASSIFIED_MAPPED; authority_role=AUT-OPERATOR; lifecycle=active; disposition=NORMALIZED",
         "UNSUPPORTED_HOLD", "superset.toml provides no directive-specific normative clause to establish anchor coverage") in
    "{\"id\":" ^ quote rule.id ^ ",\"canonical_file\":" ^ quote rule.file ^
    ",\"anchor\":" ^ quote rule.anchor ^ ",\"anchor_present\":" ^ string_of_bool anchor_present ^
    ",\"surface_count\":" ^ string_of_int surface_count ^
    ",\"normalized_body_equal\":" ^ string_of_bool normalized_equal ^
    ",\"superset_supporting_text\":" ^ quote source_clause ^
    ",\"semantic_coverage\":" ^ quote semantic_status ^
    ",\"missing_facet\":" ^ quote missing_facet ^ "}") |> String.concat "," in
  Printf.printf
    "{\"schema\":\"uos.ev02-directive-mapping/v1\",\"authority\":\"REPORT_ONLY\",\"historical_lineage\":\"MISSING_HISTORICAL_LINEAGE\",\"admission\":\"NOT_GRANTED\",\"status\":\"%s\",\"directive_count\":%d,\"mapping_rule_count\":%d,\"rule_rows\":[%s],\"mapping_errors\":[%s],\"normalized_body_differences\":[%s],\"unmapped_shared_rule_files\":[%s],\"errors\":[%s]}\n"
    status (List.length observation.directive_ids) (List.length observation.rules)
    rule_rows (json_strings observation.mapping_errors) body_differences
    (json_strings observation.unmapped_shared_files) (json_strings errors)

let write path text =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr channel) (fun () -> output_string channel text)
let make_dir path = if not (Sys.file_exists path) then Unix.mkdir path 0o700
let private_root label =
  let path = Filename.temp_file ("ev02-" ^ label ^ "-") "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path
let ids = List.init 38 (fun index -> Printf.sprintf "DIR-%02d" (index + 1))
let superset_text =
  ids |> List.map (fun id -> "[[directive]]\nid = \"" ^ id ^ "\"\n") |> String.concat "\n"
let mapping_text rows =
  Yojson.Basic.to_string (`Assoc [
    "schema", `String "uos.ev02.current-directive-rule-amendment/v1";
    "authority", `String "CURRENT_AMENDMENT_PROPOSAL";
    "historical_lineage", `String "MISSING_HISTORICAL_LINEAGE";
    "admission", `String "NOT_GRANTED";
    "normalization_base", `String ".claude/rules";
    "rules", `List (List.map (fun (id, file, anchor) -> `List [`String id; `String file; `String anchor]) rows);
    "limits", `List [] ])
let build_fixture root ~all_surfaces ~body =
  make_dir (Filename.concat root "governance");
  make_dir (Filename.concat root "governance/agents");
  make_dir (Filename.concat root "governance/agents/policy");
  write (Filename.concat root "governance/agents/policy/superset.toml") superset_text;
  List.iter (fun surface ->
    if all_surfaces || surface <> ".codex/rules" then begin
      make_dir (Filename.concat root (Filename.dirname surface));
      make_dir (Filename.concat root surface);
      write (Filename.concat root (Filename.concat surface "rule.md")) body
    end) surfaces
let expect_refusal label thunk =
  try ignore (thunk ()); failwith ("selftest accepted: " ^ label)
  with Failure detail when String.starts_with ~prefix:"invalid-input:" detail -> ()
let expect_mapping_hold label thunk =
  let result = thunk () in
  if result.mapping_errors = [] then failwith ("selftest accepted: " ^ label)

let fixture_selftest () =
  let root = private_root "mapping-valid" in
  build_fixture root ~all_surfaces:true ~body:"# Anchor\ncontent\n";
  let valid = Filename.concat root "mapping.json" in
  let rows = List.map (fun id -> id, "rule.md", "# Anchor") ids in
  write valid (mapping_text rows);
  let result = observe root valid in
  if result.mapping_errors <> [] || result.body_differences <> [] then failwith "selftest valid fixture held";
  let duplicate = Filename.concat root "duplicate.json" in
  write duplicate "{\"rules\":[],\"rules\":[]}";
  expect_refusal "duplicate-schema-key" (fun () -> observe root duplicate);
  let unknown = Filename.concat root "unknown.json" in
  write unknown "{\"rules\":[],\"unknown\":true}";
  expect_refusal "unknown-schema-key" (fun () -> observe root unknown);
  let traversal = Filename.concat root "traversal.json" in
  write traversal (mapping_text (List.map (fun id -> id, "../secret.md", "# Anchor") ids));
  expect_mapping_hold "traversal-file" (fun () -> observe root traversal);
  let symlink = Filename.concat root "mapping-link.json" in
  Unix.symlink valid symlink;
  expect_refusal "symlink-map" (fun () -> observe root symlink);
  let partial = private_root "mapping-missing" in
  build_fixture partial ~all_surfaces:false ~body:"# Anchor\ncontent\n";
  let partial_map = Filename.concat partial "mapping.json" in
  write partial_map (mapping_text rows);
  expect_refusal "missing-surface" (fun () -> observe partial partial_map);
  let budget_root = private_root "mapping-budget" in
  let large_body = "# Anchor\n" ^ String.make 600_000 'x' in
  build_fixture budget_root ~all_surfaces:true ~body:large_body;
  let budget_map = Filename.concat budget_root "mapping.json" in
  write budget_map (mapping_text rows);
  expect_mapping_hold "aggregate-budget" (fun () -> observe budget_root budget_map);
  print_endline "PASS directive-mapping fixture selftest: valid/duplicate/unknown/traversal/symlink/missing/budget"

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
  | [_; "--fixture-selftest"] -> fixture_selftest ()
  | [_; "--observe"; root; mapping] ->
      (try let result = observe root mapping in print result
       with Failure detail ->
         Printf.printf "{\"schema\":\"uos.ev02-directive-mapping/v1\",\"authority\":\"REPORT_ONLY\",\"admission\":\"NOT_GRANTED\",\"status\":\"HOLD\",\"errors\":[%s]}\n" (quote detail));
      exit 1
  | _ -> failwith "usage: directive_mapping_gate.ml --selftest | --fixture-selftest | --observe ROOT MAPPING"
