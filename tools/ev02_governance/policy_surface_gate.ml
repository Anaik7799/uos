(* Bounded EV-02 policy-surface observation.  It reports evidence only and
   deliberately cannot create an admission decision. *)
type outcome = Pass | Hold of string list

let max_rules = 64
let max_bytes = 1_048_576
let surfaces = [".agents/rules"; ".claude/rules"; ".gemini/rules"; ".codex/rules"]

let sort_unique xs = List.sort_uniq String.compare xs
let subset xs ys = List.for_all (fun x -> List.mem x ys) xs
let names path =
  Sys.readdir path |> Array.to_list
  |> List.filter (fun n -> Filename.check_suffix n ".md" && n <> "README.md") |> sort_unique

let read_bounded path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
    let length = in_channel_length channel in
    if length < 0 || length > max_bytes then None
    else Some (really_input_string channel length))

let replace_all ~needle ~replacement text =
  let n = String.length needle in
  if n = 0 then text else
  let b = Buffer.create (String.length text) in
  let rec go start =
    match String.index_from_opt text start needle.[0] with
    | None -> Buffer.add_substring b text start (String.length text - start)
    | Some i when i + n <= String.length text && String.sub text i n = needle ->
        Buffer.add_substring b text start (i - start); Buffer.add_string b replacement; go (i + n)
    | Some i -> Buffer.add_substring b text start (i - start + 1); go (i + 1)
  in go 0; Buffer.contents b

let normalize body =
  let header = "---\ntrigger: always_on\n---\n\n" in
  let body = if String.starts_with ~prefix:header body then
      String.sub body (String.length header) (String.length body - String.length header) else body in
  ["http://nas-1.tail55d152.ts.net:4100/docs/.agents/rules/";
   "http://nas-1.tail55d152.ts.net:4100/docs/.claude/rules/";
   "http://nas-1.tail55d152.ts.net:4100/docs/.gemini/rules/";
   "http://nas-1.tail55d152.ts.net:4100/docs/.codex/rules/";
   "http://nas-1.tail55d152.ts.net:4100/files/.agents/rules/";
   "http://nas-1.tail55d152.ts.net:4100/files/.claude/rules/";
   "http://nas-1.tail55d152.ts.net:4100/files/.gemini/rules/";
   "http://nas-1.tail55d152.ts.net:4100/files/.codex/rules/"]
  |> List.fold_left (fun text locator -> replace_all ~needle:locator ~replacement:"<surface-policy-link>/" text) body

let intersection = function
  | [] -> []
  | first :: rest -> List.filter (fun n -> List.for_all (List.mem n) rest) first
let evaluate ~directive_count inventories contents =
  let shared = intersection inventories in
  let errors = ref [] in
  if List.length shared > max_rules then errors := "rule-bound" :: !errors;
  if directive_count <> 38 then errors := "directive-count" :: !errors;
  List.iteri (fun index present ->
    if present <> shared then
      errors := ("missing-surface-" ^ string_of_int index) :: !errors) inventories;
  let first = match contents with [] -> [] | x :: _ -> x in
  if List.exists (fun values -> values <> first) contents then
    errors := "normalized-body-divergence" :: !errors;
  (* The canonical TOML enumerates directives but does not map any directive ID
     to a rule document.  Do not infer that a file count establishes closure. *)
  errors := "no-directive-to-rule-mapping" :: !errors;
  match List.rev !errors with [] -> Pass | errors -> Hold errors

let directive_count path =
  let channel = open_in path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
    let count = ref 0 in
    try while true do if String.trim (input_line channel) = "[[directive]]" then incr count done; 0
    with End_of_file -> !count)

let observe root =
  let inventories = List.map (fun relative -> names (Filename.concat root relative)) surfaces in
  let shared = intersection inventories in
  let contents = List.map (fun relative ->
    List.map (fun name ->
      match read_bounded (Filename.concat root (Filename.concat relative name)) with
      | Some bytes -> name ^ "\000" ^ normalize bytes
      | None -> name ^ "\000<oversize-or-unreadable>") shared) surfaces in
  let count = directive_count (Filename.concat root "governance/agents/policy/superset.toml") in
  evaluate ~directive_count:count inventories contents, shared, inventories, count

let divergent_names shared contents =
  List.mapi (fun index name ->
    let at index values = try List.nth values index with Failure _ -> "" in
    let baseline = match contents with [] -> "" | values :: _ -> at index values in
    if List.for_all (fun values -> at index values = baseline) contents then None else Some name) shared
  |> List.filter_map (fun x -> x)
let print_json outcome shared inventories directive_count contents =
  let escape = String.escaped in
  let names = shared |> List.map (fun n -> "\"" ^ escape n ^ "\"") |> String.concat "," in
  let divergent = divergent_names shared contents |> List.map (fun n -> "\"" ^ escape n ^ "\"") |> String.concat "," in
  let counts = inventories |> List.map (fun xs -> string_of_int (List.length xs)) |> String.concat "," in
  match outcome with
  | Pass -> Printf.printf "{\"schema\":\"uos.ev02-policy-surface/v1\",\"authority\":\"REPORT_ONLY\",\"admission\":\"NOT_GRANTED\",\"status\":\"PASS\",\"directive_count\":%d,\"shared_rule_files\":[%s],\"surface_counts\":[%s],\"normalized_divergent_rule_files\":[%s]}\n" directive_count names counts divergent
  | Hold errors ->
      let errors = errors |> List.map (fun e -> "\"" ^ escape e ^ "\"") |> String.concat "," in
      Printf.printf "{\"schema\":\"uos.ev02-policy-surface/v1\",\"authority\":\"REPORT_ONLY\",\"admission\":\"NOT_GRANTED\",\"status\":\"HOLD\",\"directive_count\":%d,\"shared_rule_files\":[%s],\"surface_counts\":[%s],\"normalized_divergent_rule_files\":[%s],\"errors\":[%s]}\n" directive_count names counts divergent errors

let selftest () =
  let exact = ["a"; "b"] in
  let same = ["a\000one"; "b\000two"] in
  let check label actual =
    if not actual then failwith ("selftest failed: " ^ label) in
  let has expected = function Hold errors -> List.mem expected errors | Pass -> false in
  check "mapping-hold" (has "no-directive-to-rule-mapping"
    (evaluate ~directive_count:38 [exact; exact] [same; same]));
  check "missing" (has "missing-surface-0"
    (evaluate ~directive_count:38 [exact; ["a"]] [same; same]));
  check "directive-count" (has "directive-count"
    (evaluate ~directive_count:37 [exact; exact] [same; same]));
  check "divergence" (has "normalized-body-divergence"
    (evaluate ~directive_count:38 [exact; exact] [same; ["a\000one"; "b\000changed"]]));
  check "header-and-link-normalization"
    (normalize "---\ntrigger: always_on\n---\n\nSee http://nas-1.tail55d152.ts.net:4100/docs/.agents/rules/x" = "See <surface-policy-link>/x");
  check "normative-prose-retained"
    (normalize "MUST keep .agents/rules/x in this sentence" = "MUST keep .agents/rules/x in this sentence");
  print_endline "PASS policy-surface selftest: mapping/missing/directive-count/divergence"

let () =
  match Array.to_list Sys.argv with
  | [_; "--selftest"] -> selftest ()
  | [_; "--observe"; root] ->
      let outcome, shared, inventories, count = observe root in
      let contents = List.map (fun relative ->
        List.map (fun name -> Option.value ~default:"" (read_bounded (Filename.concat root (Filename.concat relative name)) |> Option.map normalize)) shared) surfaces in
      print_json outcome shared inventories count contents;
      (match outcome with Pass -> exit 0 | Hold _ -> exit 1)
  | _ -> failwith "usage: policy_surface_gate.ml --selftest | --observe ROOT"
