(* Structural RED for the Run_swarm_bridge namespace and execution authority.

   This is deliberately a repository-wide production-source census.  It does
   not claim semantic reachability; it proves the narrower structural law that
   no repository-authored production module owns the reserved bridge name or
   calls the engine outside the exact canonical/residual allowlist. *)

let failures = ref 0
let checks = ref 0

let check name condition =
  incr checks;
  if condition then Printf.printf "  [PASS] %s\n%!" name
  else begin
    incr failures;
    Printf.printf "  [FAIL] %s\n%!" name
  end

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec loop offset =
    offset + needle_length <= haystack_length
    &&
    (String.sub haystack offset needle_length = needle
    || loop (offset + 1))
  in
  needle_length > 0 && loop 0

let count_occurrences haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec loop offset count =
    if needle_length = 0 || offset + needle_length > haystack_length then count
    else if String.sub haystack offset needle_length = needle then
      loop (offset + needle_length) (count + 1)
    else loop (offset + 1) count
  in
  loop 0 0

let is_quoted_tag_byte = function
  | 'a' .. 'z' | '_' | '0' .. '9' -> true
  | _ -> false

let find_substring_from source ~start needle =
  let source_length = String.length source in
  let needle_length = String.length needle in
  let rec loop offset =
    if offset + needle_length > source_length then None
    else if String.sub source offset needle_length = needle then Some offset
    else loop (offset + 1)
  in
  loop start

let quoted_string_at source offset =
  let length = String.length source in
  if source.[offset] <> '{' then None
  else
    let rec tag_end cursor =
      if cursor < length && is_quoted_tag_byte source.[cursor] then
        tag_end (cursor + 1)
      else cursor
    in
    let delimiter_end = tag_end (offset + 1) in
    if delimiter_end >= length || source.[delimiter_end] <> '|' then None
    else
      let tag =
        String.sub source (offset + 1) (delimiter_end - offset - 1)
      in
      Some (tag, delimiter_end + 1)

let character_literal_end source offset =
  let length = String.length source in
  if source.[offset] <> '\'' || offset + 2 >= length then None
  else if source.[offset + 1] <> '\\' then
    if source.[offset + 2] = '\'' then Some (offset + 3) else None
  else
    let rec closing_quote cursor =
      if cursor >= length then None
      else if source.[cursor] = '\'' then Some (cursor + 1)
      else closing_quote (cursor + 1)
    in
    closing_quote (offset + 3)

(* Mirrors and strengthens the ZigVM replay-control scanner: OCaml comments
   nest; ordinary strings, tagged/untagged quoted strings, and character
   literals are opaque.  Malformed input refuses rather than yielding a
   partial source census. *)
let code_only source =
  let length = String.length source in
  let output = Buffer.create length in
  let offset = ref 0 in
  let comment_depth = ref 0 in
  let in_string = ref false in
  while !offset < length do
    let byte = source.[!offset] in
    let next =
      if !offset + 1 < length then Some source.[!offset + 1] else None
    in
    if !in_string then
      if byte = '\\' then offset := min length (!offset + 2)
      else begin
        if byte = '"' then begin
          in_string := false;
          if !comment_depth = 0 then Buffer.add_char output ' '
        end;
        incr offset
      end
    else if byte = '(' && next = Some '*' then begin
      incr comment_depth;
      offset := !offset + 2
    end
    else if byte = '*' && next = Some ')' && !comment_depth > 0 then begin
      decr comment_depth;
      offset := !offset + 2
    end
    else begin
      if !comment_depth = 0 then
        match quoted_string_at source !offset with
        | Some (tag, body_start) ->
            let closing = "|" ^ tag ^ "}" in
            (match find_substring_from source ~start:body_start closing with
            | None -> invalid_arg "unterminated OCaml quoted string"
            | Some close_start ->
                Buffer.add_char output ' ';
                offset := close_start + String.length closing)
        | None -> (
            match character_literal_end source !offset with
            | Some literal_end ->
                Buffer.add_char output ' ';
                offset := literal_end
            | None ->
                if byte = '"' then begin
                  in_string := true;
                  Buffer.add_char output ' '
                end
                else Buffer.add_char output byte;
                incr offset)
      else begin
        if byte = '\n' then Buffer.add_char output '\n';
        incr offset
      end
    end
  done;
  if !comment_depth <> 0 then invalid_arg "unterminated OCaml comment";
  if !in_string then invalid_arg "unterminated OCaml string literal";
  Buffer.contents output

let is_identifier_start = function
  | 'a' .. 'z' | 'A' .. 'Z' | '_' -> true
  | _ -> false

let is_identifier_continue = function
  | 'a' .. 'z' | 'A' .. 'Z' | '_' | '0' .. '9' | '\'' -> true
  | _ -> false

let execution_identifier_count source =
  let code = code_only source in
  let length = String.length code in
  let rec scan offset count =
    if offset >= length then count
    else if is_identifier_start code.[offset] then
      let rec identifier_end cursor =
        if cursor < length && is_identifier_continue code.[cursor] then
          identifier_end (cursor + 1)
        else cursor
      in
      let boundary = identifier_end (offset + 1) in
      let identifier = String.sub code offset (boundary - offset) in
      scan boundary
        (if identifier = "execute_sop_workflow" then count + 1 else count)
    else scan (offset + 1) count
  in
  scan 0 0

let canonical_call_count_admitted count = count = 1

let recursive_bridge_call_count source =
  count_occurrences (code_only source) "Run_swarm_bridge.execute"

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let rec repository_root directory =
  let marker = Filename.concat directory "dune-project" in
  let swarm_dune = Filename.concat directory "modules/swarm/dune" in
  if Sys.file_exists marker && Sys.file_exists swarm_dune then directory
  else
    let parent = Filename.dirname directory in
    if parent = directory then
      failwith "repository root not found from the current working directory"
    else repository_root parent

let rec source_files directory =
  let entries =
    Sys.readdir directory |> Array.to_list |> List.sort String.compare
  in
  List.concat_map
    (fun entry ->
      let path = Filename.concat directory entry in
      if Sys.is_directory path then source_files path
      else if Filename.extension path = ".ml" && not (Filename.check_suffix path ".pp.ml") then [ path ]
      else [])
    entries

let relative_to root path =
  let prefix = root ^ Filename.dir_sep in
  if String.starts_with ~prefix path then
    String.sub path (String.length prefix) (String.length path - String.length prefix)
  else path

let is_test_source path =
  String.starts_with ~prefix:"test_" (Filename.basename path)

let canonical_bridge = "modules/hermes_ops_dashboard/run_swarm_bridge.ml"
let engine_implementation = "modules/swarm/sop_execution.ml"

let residual_calls =
  [ ("modules/hermes_ops/ops_command_runtime.ml", 1);
    ("modules/hermes_ops/ops_verify.ml", 1) ]

let allowed_call_count path =
  if path = canonical_bridge then Some 1
  else List.assoc_opt path residual_calls

type call_finding = { path : string; count : int }

let call_findings root production_sources =
  List.filter_map
    (fun absolute_path ->
      let path = relative_to root absolute_path in
      let count = execution_identifier_count (read_file absolute_path) in
      if path = engine_implementation || count = 0 then None
      else
        match allowed_call_count path with
        | Some expected when count = expected -> None
        | Some _ | None -> Some { path; count })
    production_sources

let missing_residuals root production_sources =
  List.filter_map
    (fun (path, expected) ->
      let absolute_path = Filename.concat root path in
      let observed =
        if List.mem absolute_path production_sources then
          execution_identifier_count (read_file absolute_path)
        else 0
      in
      if observed = expected then None else Some { path; count = observed })
    residual_calls

let reserved_module_owners root production_sources =
  List.filter_map
    (fun absolute_path ->
      let path = relative_to root absolute_path in
      if Filename.basename path = "run_swarm_bridge.ml" && path <> canonical_bridge
      then Some path
      else None)
    production_sources

let vision_forbidden_tokens root =
  let candidates =
    [ "modules/swarm/run_swarm_bridge.ml";
      "modules/swarm/run_swarm_bridge.mli";
      "modules/swarm/vision_swarm_adapter.ml";
      "modules/swarm/vision_swarm_adapter.mli";
      (* Task 2: vision_swarm was the sole unauthorized direct caller.
         Removing its call is not enough — without a standing token
         prohibition the next edit can reintroduce the engine, the
         controller or a raw Domain and only the call census would
         notice, and only for one exact spelling. *)
      "modules/hermes_vision/vision_swarm.ml";
      "modules/hermes_vision/vision_swarm.mli" ]
  in
  let forbidden =
    [ "Sop_execution.";
      "Vision_controller.";
      "Domain.";
      "Ffmpeg_controller.execute_intent";
      "Swarm_zenoh.";
      "effector" ]
  in
  List.concat_map
    (fun path ->
      let absolute_path = Filename.concat root path in
      if not (Sys.file_exists absolute_path) then []
      else
        let code = code_only (read_file absolute_path) in
        List.filter_map
          (fun token ->
            let count = count_occurrences code token in
            if count = 0 then None else Some (path, token, count))
          forbidden)
    candidates

let datarhei_posture root =
  let dune = read_file (Filename.concat root "modules/swarm/dune") in
  let test_source =
    code_only (read_file (Filename.concat root "modules/swarm/test_datarhei_vision.ml"))
  in
  let admitted =
    contains dune "(name test_datarhei_vision)"
    && contains dune "(modules test_datarhei_vision)"
  in
  let names_reserved_module = contains test_source "Run_swarm_bridge." in
  (admitted, names_reserved_module)

let print_call_finding label ({ path; count } : call_finding) =
  Printf.printf "        %s: %s count=%d\n%!" label path count

let test_scanner_model () =
  check "scanner ignores a call in an OCaml comment"
    (execution_identifier_count
       "let x = 1 (* Sop_execution.execute_sop_workflow () *)"
     = 0);
  check "scanner respects nested OCaml comments"
    (execution_identifier_count
       "(* outer (* Sop_execution.execute_sop_workflow () *) *)"
     = 0);
  check "scanner ignores a call in a string literal"
    (execution_identifier_count
       "let x = \"Sop_execution.execute_sop_workflow\""
     = 0);
  check "scanner detects an executable call"
    (execution_identifier_count
       "let x = Sop_execution.execute_sop_workflow ()"
     = 1);
  check "scanner detects an unqualified executable call after open"
    (execution_identifier_count
       "open Sop_execution\nlet x = execute_sop_workflow ()"
     = 1);
  check "scanner detects a module-aliased executable call"
    (execution_identifier_count
       "module E = Sop_execution\nlet x = E.execute_sop_workflow ()"
     = 1);
  check "scanner detects a local-open executable call"
    (execution_identifier_count
       "let x = Sop_execution.(execute_sop_workflow ())"
     = 1);
  check "scanner ignores the identifier in an untagged quoted string"
    (execution_identifier_count
       "let fixture = {| execute_sop_workflow () |}"
     = 0);
  check "scanner ignores the identifier in a tagged quoted string"
    (execution_identifier_count
       "let fixture = {gate| E.execute_sop_workflow () |gate}"
     = 0);
  check "scanner handles character literals without inventing identifiers"
    (execution_identifier_count "let quote = '\\''" = 0);
  check "scanner matches whole identifiers rather than apostrophe-prefixed names"
    (execution_identifier_count "let execute_sop_workflow' = ()" = 0);
  check "scanner counts every spelling in one source"
    (execution_identifier_count
       "open Sop_execution\nlet a = execute_sop_workflow ()\nlet b = E.execute_sop_workflow ()"
     = 2);
  check "scanner refuses an unterminated nested comment"
    (match execution_identifier_count "let x = 1 (* missing" with
    | _ -> false
    | exception Invalid_argument _ -> true);
  check "scanner refuses an unterminated ordinary string"
    (match execution_identifier_count "let x = \"missing" with
    | _ -> false
    | exception Invalid_argument _ -> true);
  check "scanner refuses an unterminated quoted string"
    (match execution_identifier_count "let x = {gate| missing" with
    | _ -> false
    | exception Invalid_argument _ -> true);
  check "presence ratchet rejects a zero-call bridge"
    (not (canonical_call_count_admitted 0));
  check "presence ratchet admits exactly one bridge call"
    (canonical_call_count_admitted 1);
  check "presence ratchet rejects a two-call bridge"
    (not (canonical_call_count_admitted 2));
  check "recursion scanner detects a direct bridge self-call"
    (recursive_bridge_call_count
       "let recurse x = Run_swarm_bridge.execute x" = 1)

let test_exact_current_repository () =
  let root = repository_root (Sys.getcwd ()) in
  let production_sources =
    source_files (Filename.concat root "modules")
    |> List.filter (fun path -> not (is_test_source path))
  in
  check "production census is non-vacuous"
    (List.length production_sources > 100
    && List.exists
         (fun path ->
           relative_to root path = "modules/swarm/sop_execution.ml")
         production_sources);

  let reserved = reserved_module_owners root production_sources in
  check "Run_swarm_bridge has exactly one canonical dashboard owner"
    (reserved = []);
  List.iter
    (fun path -> Printf.printf "        reserved-name owner: %s\n%!" path)
    reserved;

  let canonical_path = Filename.concat root canonical_bridge in
  check "canonical bridge production source exists"
    (Sys.file_exists canonical_path);
  let canonical_source =
    if Sys.file_exists canonical_path then read_file canonical_path else ""
  in
  check "canonical bridge contains exactly one production engine call"
    (canonical_call_count_admitted
       (execution_identifier_count canonical_source));
  check "canonical bridge does not recursively invoke its own execute surface"
    (recursive_bridge_call_count canonical_source = 0);

  let unauthorized = call_findings root production_sources in
  check "no production source calls the engine outside canonical and named residual sites"
    (unauthorized = []);
  List.iter (print_call_finding "unauthorized engine call") unauthorized;

  let missing = missing_residuals root production_sources in
  check "the two Task15 residual calls remain exact and explicitly classified"
    (missing = []);
  List.iter (print_call_finding "residual census drift") missing;

  let forbidden = vision_forbidden_tokens root in
  check "the vision adapter is pure preparation with no engine, effector, or simulated Zenoh"
    (forbidden = []);
  List.iter
    (fun (path, token, count) ->
      Printf.printf "        forbidden vision token: %s token=%s count=%d\n%!"
        path token count)
    forbidden;

  let datarhei_admitted, datarhei_names_reserved = datarhei_posture root in
  check "the tracked Datarhei test is admitted by Dune" datarhei_admitted;
  check "the tracked Datarhei test no longer names the reserved bridge module"
    (not datarhei_names_reserved)

let () =
  print_endline "Swarm bridge namespace and call-census authority";
  test_scanner_model ();
  test_exact_current_repository ();
  Printf.printf "\n%d/%d checks passed\n" (!checks - !failures) !checks;
  let self =
    Suite_telemetry.observe ~suite:"test_swarm_bridge_reservation"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)
