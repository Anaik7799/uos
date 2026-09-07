(* Repository packaging checks only. No application or agent behavior authority. *)
open Yojson.Basic.Util
let require ok msg = if not ok then failwith msg
let string obj key = obj |> member key |> to_string
let array obj key = obj |> member key |> to_list
let starts s prefix = String.starts_with ~prefix s
let contains s part =
  try ignore (Str.search_forward (Str.regexp_string part) s 0); true
  with Not_found -> false
let sha s = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let read path =
  let st = Unix.stat path in
  require (st.Unix.st_kind = Unix.S_REG && st.Unix.st_size <= 524288)
    "not a bounded regular file";
  let ch = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ch)
    (fun () -> really_input_string ch st.Unix.st_size)
let resolve root relative =
  require (Filename.is_relative relative && not (String.contains relative '\000'))
    "path must be relative";
  let path = Unix.realpath (Filename.concat root relative) in
  require (starts path (root ^ "/")) "path escapes repository";
  path
let unique values label =
  require (List.length values = List.length (List.sort_uniq String.compare values))
    ("duplicate " ^ label)
let nonempty obj key = require (String.trim (string obj key) <> "") ("empty " ^ key)
let scenario_check json =
  require (json |> member "schema_version" |> to_int = 1) "scenario schema";
  require (string json "independent_agent_evaluation" = "UNRUN_SIDE_SESSION_PROHIBITED")
    "cannot self-certify independent skill behavior";
  let cases = array json "scenarios" in
  require (List.length cases = 12) "scenario count";
  unique (List.map (fun c -> string c "id") cases) "scenario";
  List.iter (fun c ->
    List.iter (nonempty c) ["id"; "surface"; "prompt"; "required"; "basis"];
    require (List.mem (string c "baseline") ["FAIL"; "UNTESTED"])
      "baseline cannot claim application pass") cases
let markdown_links root path body =
  let re = Str.regexp {|](\([^ )]+\))|} in
  let rec loop pos =
    match (try Some (Str.search_forward re body pos) with Not_found -> None) with
    | None -> ()
    | Some _ ->
        let url = Str.matched_group 1 body and next = Str.match_end () in
        if not (starts url "https://" || starts url "http://" || starts url "#")
        then ignore (resolve root (Filename.concat (Filename.dirname path)
          (List.hd (String.split_on_char '#' url))));
        require (not (starts url "file:")) "file URL in guidance";
        loop next in
  loop 0
let validate root catalog =
  require (catalog |> member "schema_version" |> to_int = 1) "catalog schema";
  require (string catalog "status" = "LOCAL_CANDIDATE_NOT_ADMITTED") "admission claim";
  let resources = array catalog "resources" in
  require (List.length resources >= 9 && List.length resources <= 32) "resource bounds";
  unique (List.map (fun r -> string r "path") resources) "resource";
  List.iter (fun r ->
    let path = string r "path" in
    let bytes = read (resolve root path) in
    require (sha bytes = string r "sha256") ("changed resource: " ^ path);
    if Filename.check_suffix path ".md" then (
      for i = 1 to 18 do
        require (contains bytes (Printf.sprintf "CHK-%02d" i)) "missing checklist marker"
      done;
      markdown_links root path bytes)) resources;
  let skills = array catalog "skills" in
  require (List.length skills = 3) "skill count";
  unique (List.map (fun s -> string s "name") skills) "skill name";
  List.iter (fun s ->
    let name = string s "name" and entry = string s "entry" in
    let resolved = resolve root entry in
    let bytes = read resolved in
    require (starts bytes ("---\nname: " ^ name ^ "\ndescription: ")) "skill frontmatter";
    require (contains bytes "\n---\n") "unterminated frontmatter";
    require (List.exists (fun r -> resolve root (string r "path") = resolved) resources)
      "skill body absent from resource manifest";
    let aliases = array s "aliases" |> List.map to_string in
    let expected = List.map (fun a -> a ^ "/skills/" ^ name)
      [".agents"; ".codex"; ".claude"; ".gemini"] in
    require (List.sort String.compare aliases = List.sort String.compare expected)
      "discovery alias set";
    List.iter (fun a ->
      let raw = Filename.concat root a in
      require ((Unix.lstat raw).Unix.st_kind = Unix.S_LNK) "alias must be a local symlink";
      require (Filename.is_relative (Unix.readlink raw)) "absolute discovery alias";
      require (resolve root (a ^ "/SKILL.md") = resolved) "alias target mismatch"
    ) aliases
  ) skills;
  scenario_check (Yojson.Basic.from_string (read (resolve root (string catalog "scenarios"))));
  let sources = Yojson.Basic.from_string (read (resolve root (string catalog "sources"))) in
  require (List.length (array sources "sources") = 10) "source inventory count";
  List.iter (fun s ->
    require (starts (string s "url") "https://") "primary source URL";
    List.iter (nonempty s) ["id"; "revision"; "use"]
  ) (array sources "sources");
  List.length resources
let replace key value = function
  | `Assoc entries -> `Assoc ((key,value) :: List.remove_assoc key entries)
  | _ -> failwith "expected object"
let map_first f = function
  | `List (x::xs) -> `List (f x::xs)
  | _ -> failwith "expected nonempty list"
let selftest root catalog =
  let test name f =
    let rejected = try f (); false with
      | Failure _ | Sys_error _ | Unix.Unix_error _ | Type_error _ -> true in
    require rejected ("mutant survived: " ^ name) in
  let check c () = ignore (validate root c) in
  test "false admission" (check (replace "status" (`String "ADMITTED") catalog));
  test "missing alias" (check (replace "skills"
    (map_first (replace "aliases" (`List [])) (member "skills" catalog)) catalog));
  test "wrong frontmatter" (check (replace "skills"
    (map_first (replace "name" (`String "wrong-name")) (member "skills" catalog)) catalog));
  test "outside resource" (check (replace "resources"
    (map_first (replace "path" (`String "/outside")) (member "resources" catalog)) catalog));
  test "changed digest" (check (replace "resources"
    (map_first (replace "sha256" (`String (String.make 64 '0')))
      (member "resources" catalog)) catalog));
  let scenarios = Yojson.Basic.from_string (read (resolve root (string catalog "scenarios"))) in
  test "self-issued peer pass" (fun () ->
    scenario_check (replace "independent_agent_evaluation" (`String "PASS") scenarios));
  test "empty scenario expectation" (fun () ->
    scenario_check (replace "scenarios"
      (map_first (replace "required" (`String "")) (member "scenarios" scenarios)) scenarios));
  test "invented baseline pass" (fun () ->
    scenario_check (replace "scenarios"
      (map_first (replace "baseline" (`String "PASS")) (member "scenarios" scenarios)) scenarios));
  8
let () =
  try
    require (Array.length Sys.argv = 3 || Array.length Sys.argv = 4)
      "usage: check REPO CATALOG [--selftest]";
    let root = Unix.realpath Sys.argv.(1) in
    let catalog = Yojson.Basic.from_string (read (resolve root Sys.argv.(2))) in
    let resources = validate root catalog in
    let mutants = if Array.length Sys.argv = 4 then (
      require (Sys.argv.(3) = "--selftest") "unknown option";
      selftest root catalog) else 0 in
    `Assoc [
      "status", `String "PACKAGE_CHECK_PASS";
      "resources_checked", `Int resources;
      "skills_checked", `Int 3; "discovery_aliases_checked", `Int 12;
      "scenario_records_checked", `Int 12; "negative_fixtures_rejected", `Int mutants;
      "application_tests", `String "NOT_RUN_BY_THIS_CHECKER";
      "independent_skill_behavior", `String "UNRUN";
      "runtime_admission", `String "NOT_GRANTED"
    ] |> Yojson.Basic.to_string |> print_endline
  with exn ->
    `Assoc ["status", `String "PACKAGE_CHECK_FAIL";
      "error", `String (Printexc.to_string exn);
      "runtime_admission", `String "NOT_GRANTED"]
    |> Yojson.Basic.to_string |> print_endline;
    exit 1

