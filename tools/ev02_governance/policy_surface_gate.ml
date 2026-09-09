(* Bounded EV-02 policy-surface observation.  It reports evidence only and
   deliberately cannot create an admission decision. *)
type outcome = Pass | Hold of string list

let max_rules = 64
let max_bytes = 1_048_576
let expected_families = 38
let surfaces = [".agents/rules"; ".claude/rules"; ".gemini/rules"; ".codex/rules"]

let sort_unique xs = List.sort_uniq String.compare xs
let subset xs ys = List.for_all (fun x -> List.mem x ys) xs
let names path =
  Sys.readdir path |> Array.to_list
  |> List.filter (fun n -> Filename.check_suffix n ".md") |> sort_unique

let read_bounded path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
    let length = in_channel_length channel in
    if length < 0 || length > max_bytes then None
    else Some (really_input_string channel length))

let evaluate ~expected inventories contents =
  let all_names = inventories |> List.concat |> sort_unique in
  let errors = ref [] in
  if List.length all_names > max_rules then errors := "rule-bound" :: !errors;
  if List.length all_names <> expected then errors := "family-count" :: !errors;
  List.iteri (fun index present ->
    if not (subset all_names present) then
      errors := ("missing-surface-" ^ string_of_int index) :: !errors) inventories;
  let first = match contents with [] -> [] | x :: _ -> x in
  if List.exists (fun values -> values <> first) contents then
    errors := "byte-divergence" :: !errors;
  match List.rev !errors with [] -> Pass | errors -> Hold errors

let observe root =
  let inventories = List.map (fun relative -> names (Filename.concat root relative)) surfaces in
  let all_names = inventories |> List.concat |> sort_unique in
  let contents = List.map2 (fun relative present ->
    List.map (fun name ->
      match read_bounded (Filename.concat root (Filename.concat relative name)) with
      | Some bytes -> name ^ "\000" ^ bytes
      | None -> name ^ "\000<oversize-or-unreadable>") present) surfaces inventories in
  evaluate ~expected:expected_families inventories contents, all_names, inventories

let print_json outcome all_names inventories =
  let escape = String.escaped in
  let names = all_names |> List.map (fun n -> "\"" ^ escape n ^ "\"") |> String.concat "," in
  let counts = inventories |> List.map (fun xs -> string_of_int (List.length xs)) |> String.concat "," in
  match outcome with
  | Pass -> Printf.printf "{\"schema\":\"uos.ev02-policy-surface/v1\",\"authority\":\"REPORT_ONLY\",\"admission\":\"NOT_GRANTED\",\"status\":\"PASS\",\"expected_families\":38,\"families\":[%s],\"surface_counts\":[%s]}\n" names counts
  | Hold errors ->
      let errors = errors |> List.map (fun e -> "\"" ^ escape e ^ "\"") |> String.concat "," in
      Printf.printf "{\"schema\":\"uos.ev02-policy-surface/v1\",\"authority\":\"REPORT_ONLY\",\"admission\":\"NOT_GRANTED\",\"status\":\"HOLD\",\"expected_families\":38,\"families\":[%s],\"surface_counts\":[%s],\"errors\":[%s]}\n" names counts errors

let selftest () =
  let exact = ["a"; "b"] in
  let same = ["a\000one"; "b\000two"] in
  let check label wanted got =
    if wanted <> got then failwith ("selftest failed: " ^ label) in
  check "complete" Pass (evaluate ~expected:2 [exact; exact] [same; same]);
  check "missing" (Hold ["missing-surface-1"])
    (evaluate ~expected:2 [exact; ["a"]] [same; same]);
  check "count" (Hold ["family-count"])
    (evaluate ~expected:3 [exact; exact] [same; same]);
  check "divergence" (Hold ["byte-divergence"])
    (evaluate ~expected:2 [exact; exact] [same; ["a\000one"; "b\000changed"]]);
  print_endline "PASS policy-surface selftest: complete/missing/count/divergence"

let () =
  match Array.to_list Sys.argv with
  | [_; "--selftest"] -> selftest ()
  | [_; "--observe"; root] ->
      let outcome, all_names, inventories = observe root in
      print_json outcome all_names inventories;
      (match outcome with Pass -> exit 0 | Hold _ -> exit 1)
  | _ -> failwith "usage: policy_surface_gate.ml --selftest | --observe ROOT"
