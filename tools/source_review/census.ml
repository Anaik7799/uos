#use "topfind";;
#require "yojson";;
#require "cryptokit";;

(** Bounded source and test census.

    The pure classifier records what is known about each supplied source.  The
    partition verifier is a separate effectful interpretation over already
    admitted UOS index artifacts.  It never traverses an external source root. *)

type read_depth = Unreadable | Indexed | Hashed | Close_read

type source_kind = Test_source | Helper_source | Document | Generated | Binary

type registration =
  | Registered of string
  | Unregistered

type execution_state = Unrun | Passed | Failed | Skipped | Unknown

type browser_class =
  | No_browser_driver_observed
  | Server_or_component
  | Simulated_browser
  | Real_browser_declared
  | Browser_review_required

type transfer = Retain_evidence | Port_candidate | Exclude of string

type span = { start_line : int; end_line : int }

type source_record = {
  source_id : string;
  path : string;
  locator : string;
  span : span option;
  kind : source_kind;
  registration : registration;
  oracle : string;
  coverage_scope : string;
  browser_class : browser_class;
  transfer : transfer;
  runner : string;
  execution_state : execution_state;
  read_depth : read_depth;
}

type input = {
  files : string list;
  registered_tests : string list;
  ast_sites : int;
  unreadable : string list;
}

type summary = {
  records : source_record list;
  files_accounted : int;
  unreadable_count : int;
  complete_review : bool;
  executed_tests : int;
  registered_test_files : int;
  ast_sites : int;
  reviewed_files : int;
  classified_exclusions : int;
  frontier_count : int;
  review_frontier : string list;
}

type error = Invalid_input of string | Invalid_index of string | Io_error of string

let string_of_error = function
  | Invalid_input message -> "invalid input: " ^ message
  | Invalid_index message -> "invalid index: " ^ message
  | Io_error message -> "I/O error: " ^ message

let sha256 value =
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) value
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
  |> String.lowercase_ascii

let has_nul value = String.contains value '\000'

let canonical_relative_path path =
  let parts = String.split_on_char '/' path in
  path <> "" && path.[0] <> '/' && not (has_nul path)
  && not (String.contains path '\\')
  && List.for_all (fun part -> part <> "" && part <> "." && part <> "..") parts

let duplicates values =
  let sorted = List.sort String.compare values in
  let rec loop previous duplicates = function
    | [] -> List.rev duplicates
    | head :: tail ->
        if Some head = previous then loop (Some head) (head :: duplicates) tail
        else loop (Some head) duplicates tail
  in
  loop None [] sorted |> List.sort_uniq String.compare

let subset ~members values = List.for_all (fun value -> List.mem value members) values

let validate_input input =
  if input.files = [] then Error (Invalid_input "files must be nonempty")
  else if List.length input.files > 100_000 then
    Error (Invalid_input "files exceeds 100000 entries")
  else if input.ast_sites < 0 || input.ast_sites > 10_000_000 then
    Error (Invalid_input "ast_sites is outside 0..10000000")
  else if not (List.for_all canonical_relative_path input.files) then
    Error (Invalid_input "files contains a noncanonical relative path")
  else if duplicates input.files <> [] then
    Error (Invalid_input "files contains duplicate paths")
  else if duplicates input.registered_tests <> [] then
    Error (Invalid_input "registered_tests contains duplicate paths")
  else if duplicates input.unreadable <> [] then
    Error (Invalid_input "unreadable contains duplicate paths")
  else if not (subset ~members:input.files input.registered_tests) then
    Error (Invalid_input "registered_tests must be a subset of files")
  else if not (subset ~members:input.files input.unreadable) then
    Error (Invalid_input "unreadable must be a subset of files")
  else Ok input

let ends_with suffix value =
  let suffix_length = String.length suffix in
  let value_length = String.length value in
  value_length >= suffix_length
  && String.sub value (value_length - suffix_length) suffix_length = suffix

let kind_of_path ~registered path =
  if registered then Test_source
  else if ends_with ".md" path then Document
  else if ends_with ".beam" path || ends_with ".cmx" path || ends_with ".cmo" path
  then Binary
  else if ends_with ".generated" path || String.contains path '~' then Generated
  else Helper_source

let runner_of_path ~registered path =
  if not registered then "none"
  else if ends_with ".ml" path then "dune/ocaml test registration"
  else if ends_with ".gleam" path then "gleeunit"
  else if ends_with ".exs" path then "exunit"
  else if ends_with ".feature" path then "gherkin"
  else "registered runner requires review"

let source_id path = "uos:census:v1:" ^ String.sub (sha256 path) 0 24

let classify_record input path =
  let registered = List.mem path input.registered_tests in
  let unreadable = List.mem path input.unreadable in
  let kind = kind_of_path ~registered path in
  {
    source_id = source_id path;
    path;
    locator = path;
    span = None;
    kind;
    registration =
      (if registered then Registered (runner_of_path ~registered path)
       else Unregistered);
    oracle =
      (if registered then "oracle pending per-case close reading"
       else "not a registered test case");
    coverage_scope =
      (if registered then "registered file; AST sites are aggregate input evidence"
       else "source classification only");
    browser_class = Browser_review_required;
    transfer =
      (match kind with
       | Test_source -> Port_candidate
       | Binary | Generated -> Exclude "generated or binary artifact"
       | Helper_source | Document -> Retain_evidence);
    runner = runner_of_path ~registered path;
    execution_state = Unrun;
    read_depth = if unreadable then Unreadable else Indexed;
  }

let is_executed = function Passed | Failed | Skipped -> true | Unrun | Unknown -> false

let summarize input records =
  let excluded record = match record.transfer with Exclude _ -> true | _ -> false in
  let review_frontier =
    List.filter_map
      (fun record ->
        if excluded record then None
        else
          match record.read_depth with
          | Close_read -> None
          | Unreadable -> Some (record.path ^ ":unreadable")
          | Indexed -> Some (record.path ^ ":indexed_not_close_read")
          | Hashed -> Some (record.path ^ ":hashed_not_close_read"))
      records
  in
  {
    records;
    files_accounted = List.length records;
    unreadable_count =
      List.fold_left
        (fun count record -> if record.read_depth = Unreadable then count + 1 else count)
        0 records;
    complete_review = review_frontier = [];
    executed_tests =
      List.fold_left
        (fun count record -> if is_executed record.execution_state then count + 1 else count)
        0 records;
    registered_test_files = List.length input.registered_tests;
    ast_sites = input.ast_sites;
    reviewed_files =
      List.fold_left
        (fun count record ->
          if record.read_depth = Close_read && not (excluded record) then count + 1 else count)
        0 records;
    classified_exclusions =
      List.fold_left (fun count record -> if excluded record then count + 1 else count) 0 records;
    frontier_count = List.length review_frontier;
    review_frontier;
  }

(** Initial list interpretation. *)
let classify_reference input =
  match validate_input input with
  | Error _ as error -> error
  | Ok input ->
      let records = List.map (classify_record input) input.files in
      Ok (summarize input records)

(** Final fold interpretation. *)
let classify input =
  match validate_input input with
  | Error _ as error -> error
  | Ok input ->
      let records =
        List.fold_left (fun rows path -> classify_record input path :: rows) [] input.files
        |> List.rev
      in
      Ok (summarize input records)

let observe_summary summary =
  (summary.files_accounted, summary.unreadable_count, summary.complete_review,
   summary.executed_tests, summary.registered_test_files, summary.ast_sites,
   summary.reviewed_files, summary.classified_exclusions, summary.frontier_count,
   summary.review_frontier)

type syntax_kind = Dune | Gleeunit | Exunit | Gherkin

type syntax_case = {
  case_id : string;
  syntax : syntax_kind;
  declaration : string;
  span : span;
  oracle_lines : int list;
  imports : string list;
  calls : string list;
  confidence : string;
  review_frontier : string;
}

let trim = String.trim

let starts_with prefix value =
  let prefix_length = String.length prefix in
  String.length value >= prefix_length
  && String.sub value 0 prefix_length = prefix

let contains_substring needle value =
  let needle_length = String.length needle in
  let value_length = String.length value in
  let rec loop index =
    index + needle_length <= value_length
    && (String.sub value index needle_length = needle || loop (index + 1))
  in
  needle_length = 0 || loop 0

let indexed_lines text =
  String.split_on_char '\n' text |> List.mapi (fun index line -> (index + 1, line))

let strip_comments text =
  let length = String.length text in
  let output = Buffer.create length in
  let rec scan index block in_string escaped line_nonspace =
    if index >= length then Buffer.contents output
    else
      let character = text.[index] in
      let next = if index + 1 < length then Some text.[index + 1] else None in
      match block with
      | Some close ->
          if character = '\n' then begin
            Buffer.add_char output '\n';
            scan (index + 1) block false false false
          end else if Some character = Some (fst close) && next = Some (snd close) then begin
            Buffer.add_string output "  ";
            scan (index + 2) None false false line_nonspace
          end else begin
            Buffer.add_char output ' ';
            scan (index + 1) block false false line_nonspace
          end
      | None when in_string ->
          Buffer.add_char output character;
          if character = '\n' then scan (index + 1) None false false false
          else if escaped then scan (index + 1) None true false true
          else if character = '\\' then scan (index + 1) None true true true
          else if character = '"' then scan (index + 1) None false false true
          else scan (index + 1) None true false true
      | None ->
          if character = '/' && next = Some '*' then begin
            Buffer.add_string output "  ";
            scan (index + 2) (Some ('*', '/')) false false line_nonspace
          end else if character = '(' && next = Some '*' then begin
            Buffer.add_string output "  ";
            scan (index + 2) (Some ('*', ')')) false false line_nonspace
          end else if character = '/' && next = Some '/' then begin
            Buffer.add_string output "  ";
            skip_line (index + 2)
          end else if character = ';' || (character = '#' && not line_nonspace) then begin
            Buffer.add_char output ' ';
            skip_line (index + 1)
          end else begin
            Buffer.add_char output character;
            if character = '\n' then scan (index + 1) None false false false
            else if character = '"' then scan (index + 1) None true false true
            else
              scan (index + 1) None false false
                (line_nonspace || (character <> ' ' && character <> '\t' && character <> '\r'))
          end
  and skip_line index =
    if index >= length then Buffer.contents output
    else if text.[index] = '\n' then begin
      Buffer.add_char output '\n';
      scan (index + 1) None false false false
    end else begin
      Buffer.add_char output ' ';
      skip_line (index + 1)
    end
  in
  scan 0 None false false false

let is_gherkin_step value =
  List.exists (fun prefix -> starts_with prefix value)
    [ "Given "; "When "; "Then "; "And "; "But "; "* " ]

let declaration_syntax value =
  let dune_stanza name =
    let prefix = "(" ^ name in
    starts_with prefix value
    && (String.length value = String.length prefix
        || let next = value.[String.length prefix] in
           next = ' ' || next = '\t' || next = '\r' || next = '\n' || next = ')')
  in
  if dune_stanza "test" || dune_stanza "tests" then Some Dune
  else if starts_with "pub fn " value && String.contains value '(' &&
     (String.contains value '_' &&
      (ends_with "_test() {" value || ends_with "_test()" value))
  then Some Gleeunit
  else if starts_with "test \"" value || starts_with "feature \"" value
       || starts_with "property \"" value
  then Some Exunit
  else if starts_with "Scenario:" value || starts_with "Scenario Outline:" value
  then Some Gherkin
  else None

let oracle_line value =
  List.exists (fun prefix -> starts_with prefix value)
    [ "assert "; "refute "; "assert_"; "refute_"; "|> should."; "should." ]
  || contains_substring "|> should." value
  || is_gherkin_step value

let import_line value =
  List.exists (fun prefix -> starts_with prefix value)
    [ "import "; "open "; "include "; "use "; "alias " ]

let call_tokens value =
  let is_ident = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '.' -> true
    | _ -> false
  in
  let length = String.length value in
  let rec left index =
    if index < 0 || not (is_ident value.[index]) then index + 1 else left (index - 1)
  in
  let rec loop index calls =
    if index >= length then List.rev calls |> List.sort_uniq String.compare
    else if value.[index] = '(' then
      let start = left (index - 1) in
      if start < index then
        let token = String.sub value start (index - start) in
        loop (index + 1) (token :: calls)
      else loop (index + 1) calls
    else loop (index + 1) calls
  in
  loop 0 []

let syntax_name = function
  | Dune -> "dune"
  | Gleeunit -> "gleeunit"
  | Exunit -> "exunit"
  | Gherkin -> "gherkin"

let stable_case_id path syntax line declaration =
  let key = String.concat ":" [ path; syntax_name syntax; string_of_int line; declaration ] in
  "uos:case:v1:" ^ String.sub (sha256 key) 0 24

(** Declaration-oriented lexical interpretation.  Assertions and Gherkin steps
    are attached as oracle evidence; they never become additional cases. *)
let enumerate_syntax_cases ~path ~text =
  let lines = indexed_lines (strip_comments text) in
  let imports =
    List.filter_map
      (fun (_, line) -> let value = trim line in if import_line value then Some value else None)
      lines
  in
  let declarations =
    List.filter_map
      (fun (line, source) ->
        let declaration = trim source in
        Option.map (fun syntax -> (line, syntax, declaration))
          (declaration_syntax declaration))
      lines
  in
  let with_end =
    List.mapi
      (fun index (line, syntax, declaration) ->
        let end_line =
          match List.nth_opt declarations (index + 1) with
          | Some (next_line, _, _) -> next_line - 1
          | None -> List.length lines
        in
        let region =
          List.filter (fun (line_number, _) -> line_number >= line && line_number <= end_line) lines
        in
        let oracle_lines =
          List.filter_map
            (fun (line_number, source) ->
              if oracle_line (trim source) then Some line_number else None)
            region
        in
        let calls =
          List.concat_map (fun (_, source) -> call_tokens source) region
          |> List.sort_uniq String.compare
        in
        { case_id = stable_case_id path syntax line declaration; syntax; declaration;
          span = { start_line = line; end_line }; oracle_lines; imports; calls;
          confidence = "LEXICAL_CANDIDATE_NOT_AST_OR_RUNNER_CONFIRMED";
          review_frontier = "registration_and_AST_confirmation_open" })
      declarations
  in
  with_end

type partition_report = {
  index_path : string;
  verified_parts : int;
  verified_records : int;
  unique_records : int;
  duplicate_records : int;
  declarations : int;
  cases : int;
  imports : int;
  headings : int;
  execution_unknown : int;
  execution_unrun : int;
  bindings : Yojson.Basic.t list;
  source_ledger : Yojson.Basic.t list;
  case_ledger : Yojson.Basic.t list;
}

let max_index_bytes = 4 * 1024 * 1024
let max_part_bytes = 16 * 1024 * 1024
let max_parts = 128
let max_records = 100_000

let read_regular_bounded ~limit path =
  try
    let before = Unix.lstat path in
    if before.Unix.st_kind <> Unix.S_REG then Error (Io_error (path ^ ": not a regular file"))
    else if before.Unix.st_size < 0 || before.Unix.st_size > limit then
      Error (Io_error (path ^ ": byte limit exceeded"))
    else
      let descriptor = Unix.openfile path [ Unix.O_RDONLY; Unix.O_NONBLOCK; Unix.O_CLOEXEC ] 0 in
      Fun.protect
        ~finally:(fun () -> try Unix.close descriptor with Unix.Unix_error _ -> ())
        (fun () ->
          let opened = Unix.fstat descriptor in
          if opened.Unix.st_kind <> Unix.S_REG
             || opened.Unix.st_dev <> before.Unix.st_dev
             || opened.Unix.st_ino <> before.Unix.st_ino
          then Error (Io_error (path ^ ": identity changed before read"))
          else
            let buffer = Bytes.create 65_536 in
            let output = Buffer.create (min opened.Unix.st_size limit) in
            let rec read total =
              if total > limit then Error (Io_error (path ^ ": byte limit exceeded"))
              else
                match Unix.read descriptor buffer 0 (Bytes.length buffer) with
                | 0 ->
                    let after = Unix.fstat descriptor in
                    let path_after = Unix.lstat path in
                    let stable left right =
                      left.Unix.st_kind = right.Unix.st_kind
                      && left.Unix.st_dev = right.Unix.st_dev
                      && left.Unix.st_ino = right.Unix.st_ino
                      && left.Unix.st_size = right.Unix.st_size
                      && left.Unix.st_mtime = right.Unix.st_mtime
                      && left.Unix.st_ctime = right.Unix.st_ctime
                    in
                    if Buffer.length output <> opened.Unix.st_size
                       || not (stable opened after)
                       || not (stable before path_after)
                       || not (stable opened path_after)
                    then Error (Io_error (path ^ ": identity or metadata changed during read"))
                    else Ok (Buffer.contents output)
                | count ->
                    if total + count > limit then
                      Error (Io_error (path ^ ": byte limit exceeded"))
                    else (Buffer.add_subbytes output buffer 0 count; read (total + count))
            in
            read 0)
  with
  | Unix.Unix_error (_, _, message) -> Error (Io_error (path ^ ": " ^ message))
  | Sys_error message -> Error (Io_error (path ^ ": " ^ message))

let ( let* ) result function_ = Result.bind result function_

let preflight_json path text =
  let length = String.length text in
  let rec prefix_at index token =
    let token_length = String.length token in
    index + token_length <= length
    && String.sub text index token_length = token
  in
  let matching open_char close_char =
    (open_char = '{' && close_char = '}') || (open_char = '[' && close_char = ']')
  in
  let rec scan index stack in_string escaped structural =
    if structural > 500_000 then
      Error (Invalid_index (path ^ ": JSON structural token limit exceeded"))
    else if index = length then
      if in_string || escaped || stack <> [] then
        Error (Invalid_index (path ^ ": unterminated JSON token"))
      else Ok ()
    else
      let character = text.[index] in
      if in_string then
        if escaped then scan (index + 1) stack true false structural
        else if character = '\\' then scan (index + 1) stack true true structural
        else if character = '"' then scan (index + 1) stack false false structural
        else scan (index + 1) stack true false structural
      else if character = '"' then scan (index + 1) stack true false structural
      else if character = '{' || character = '[' then
        let next = character :: stack in
        if List.length next > 64 then
          Error (Invalid_index (path ^ ": JSON depth limit exceeded before parsing"))
        else scan (index + 1) next false false (structural + 1)
      else if character = '}' || character = ']' then
        (match stack with
         | open_char :: tail when matching open_char character ->
             scan (index + 1) tail false false (structural + 1)
         | _ -> Error (Invalid_index (path ^ ": mismatched JSON delimiter")))
      else if character = ',' || character = ':' then
        scan (index + 1) stack false false (structural + 1)
      else if prefix_at index "NaN" || prefix_at index "Infinity"
           || prefix_at index "-Infinity" then
        Error (Invalid_index (path ^ ": nonfinite number before parsing"))
      else scan (index + 1) stack false false structural
  in
  scan 0 [] false false 0

let validate_json_tree path json =
  let nodes = ref 0 in
  let rec visit depth value =
    incr nodes;
    if !nodes > 500_000 then Error (Invalid_index (path ^ ": JSON node limit exceeded"))
    else if depth > 64 then Error (Invalid_index (path ^ ": JSON depth limit exceeded"))
    else
      match value with
      | `Assoc fields ->
          let names = List.map fst fields in
          if List.length fields > 4096 then
            Error (Invalid_index (path ^ ": object field limit exceeded"))
          else if duplicates names <> [] then
            Error (Invalid_index (path ^ ": duplicate object field"))
          else visit_all (depth + 1) (List.map snd fields)
      | `List values ->
          if List.length values > 100_000 then
            Error (Invalid_index (path ^ ": array length limit exceeded"))
          else visit_all (depth + 1) values
      | `Float value when not (Float.is_finite value) ->
          Error (Invalid_index (path ^ ": nonfinite number"))
      | `Null | `Bool _ | `Int _ | `Float _ | `String _ -> Ok ()
  and visit_all depth = function
    | [] -> Ok ()
    | head :: tail ->
        let* () = visit depth head in
        visit_all depth tail
  in
  visit 0 json

let parse_json path text =
  try
    let* () = preflight_json path text in
    let json = Yojson.Basic.from_string text in
    let* () = validate_json_tree path json in
    Ok json
  with Yojson.Json_error message -> Error (Invalid_index (path ^ ": " ^ message))

let assoc_field path name = function
  | `Assoc fields ->
      (match List.assoc_opt name fields with
       | Some value -> Ok value
       | None -> Error (Invalid_index (path ^ ": missing field " ^ name)))
  | _ -> Error (Invalid_index (path ^ ": expected object"))

let string_field path name json =
  match assoc_field path name json with
  | Ok (`String value) -> Ok value
  | Ok _ -> Error (Invalid_index (path ^ ": " ^ name ^ " must be string"))
  | Error _ as error -> error

let int_field path name json =
  match assoc_field path name json with
  | Ok (`Int value) -> Ok value
  | Ok _ -> Error (Invalid_index (path ^ ": " ^ name ^ " must be integer"))
  | Error _ as error -> error

let list_field path name json =
  match assoc_field path name json with
  | Ok (`List values) -> Ok values
  | Ok _ -> Error (Invalid_index (path ^ ": " ^ name ^ " must be array"))
  | Error _ as error -> error

let record_key path = function
  | `Assoc fields ->
      let value name = match List.assoc_opt name fields with Some (`String v) -> v | _ -> "" in
      let project = value "project" and root = value "root" and source = value "path" in
      if project = "" || root = "" || source = "" then
        Error (Invalid_index (path ^ ": record lacks project/root/path identity"))
      else Ok (String.concat "\000" [ project; root; source ])
  | _ -> Error (Invalid_index (path ^ ": record must be object"))

let count_list_field name = function
  | `Assoc fields ->
      (match List.assoc_opt name fields with Some (`List values) -> List.length values | _ -> 0)
  | _ -> 0

let execution_of_record = function
  | `Assoc fields ->
      (match List.assoc_opt "execution" fields with
       | Some (`String "UNRUN") -> `Unrun
       | Some (`String _) -> `Other
       | _ -> `Unknown)
  | _ -> `Unknown

let optional_string name fields =
  match List.assoc_opt name fields with Some (`String value) -> value | _ -> ""

let runner_of_language = function
  | "gleam" -> "gleeunit_candidate"
  | "elixir" -> "exunit_candidate"
  | "gherkin" -> "gherkin_candidate"
  | "ocaml" -> "dune_candidate"
  | _ -> "runner_unresolved"

let partition_ledger_rows ~scope ~index_path ~index_sha256 ~part_path ~part_sha256 record =
  match record with
  | `Assoc fields ->
      let project = optional_string "project" fields in
      let root = optional_string "root" fields in
      let source = optional_string "path" fields in
      let language = optional_string "language" fields in
      let review = optional_string "review" fields in
      let execution = optional_string "execution" fields in
      let browser =
        let value = optional_string "browser" fields in
        if value <> "" then value else
          let value = optional_string "browser_class" fields in
          if value = "" then "UNKNOWN" else value
      in
      let excluded = review = "EXCLUDED_SENSITIVE_OR_OVERSIZE" in
      let identity = String.concat "\000" [ scope; project; root; source ] in
      let source_id = "uos:source:v1:" ^ String.sub (sha256 identity) 0 32 in
      let coverage =
        let value = optional_string "purpose_and_scope" fields in
        if value = "" then "static index scope only; close reading open" else value
      in
      let transfer =
        let value = optional_string "gleam_use" fields in
        if value = "" then "UNDECIDED_RETAIN_AS_EVIDENCE" else value
      in
      let source_row =
        `Assoc
          [ ("source_id", `String source_id); ("scope", `String scope);
            ("project", `String project); ("root", `String root);
            ("path", `String source); ("locator", `String (root ^ "/" ^ source));
            ("bound_index", `String index_path);
            ("bound_index_sha256", `String index_sha256);
            ("bound_part", `String part_path); ("bound_part_sha256", `String part_sha256);
            ("review_state", `String (if review = "" then "UNKNOWN" else review));
            ("close_read", `Bool false); ("excluded", `Bool excluded);
            ("frontier", if excluded then `Null else `String "close_read_and_runtime_confirmation_open");
            ("registration_state", `String "STATIC_LEXICAL_INDEX_NOT_RUNNER_CONFIRMED");
            ("browser_class", `String browser); ("transfer_decision", `String transfer);
            ("runner", `String (runner_of_language language));
            ("execution_state", `String (if execution = "" then "UNKNOWN" else execution));
            ("coverage_scope", `String coverage) ]
      in
      let cases = match List.assoc_opt "cases" fields with Some (`List values) -> values | _ -> [] in
      let rec project_cases rows = function
        | [] -> Ok (List.rev rows)
        | `Assoc case_fields :: tail ->
            let declaration = optional_string "declaration" case_fields in
            let kind = optional_string "kind" case_fields in
            let line = match List.assoc_opt "line" case_fields with Some (`Int value) -> value | _ -> -1 in
            if declaration = "" || kind = "" || line < 1 then
              Error (Invalid_index (part_path ^ ": invalid lexical case candidate"))
            else
              let assertions =
                match List.assoc_opt "assertion_lines" case_fields with
                | Some (`List values) -> List.length values
                | _ -> 0
              in
              let case_identity =
                String.concat "\000"
                  [ identity; string_of_int line; kind; declaration ]
              in
              let row =
                `Assoc
                  [ ("case_id", `String ("uos:case:v1:" ^ String.sub (sha256 case_identity) 0 32));
                    ("source_id", `String source_id); ("scope", `String scope);
                    ("locator", `String (root ^ "/" ^ source));
                    ("span", `Assoc [ ("start_line", `Int line); ("end_line", `Int line);
                                       ("confidence", `String "DECLARATION_LINE_ONLY") ]);
                    ("declaration_kind", `String kind);
                    ("oracle_state", `String
                      (if assertions = 0 then "UNRESOLVED"
                       else "LEXICAL_ASSERTION_ROWS_PRESENT_UNEXECUTED"));
                    ("oracle_line_count", `Int assertions);
                    ("coverage_scope", `String coverage); ("browser_class", `String browser);
                    ("transfer_decision", `String transfer);
                    ("runner", `String (runner_of_language language));
                    ("execution_state", `String (if execution = "" then "UNKNOWN" else execution));
                    ("review_state", `String "LEXICAL_CANDIDATE_NOT_AST_OR_RUNNER_CONFIRMED");
                    ("frontier", `String "registration_AST_oracle_and_execution_confirmation_open");
                    ("bound_part", `String part_path); ("bound_part_sha256", `String part_sha256) ]
              in
              project_cases (row :: rows) tail
        | _ :: _ -> Error (Invalid_index (part_path ^ ": case candidate must be object"))
      in
      let* case_rows = project_cases [] cases in
      Ok (source_row, case_rows)
  | _ -> Error (Invalid_index (part_path ^ ": record must be object"))

let verify_partitioned_index ~index_path ~expected_sha256 ~expected_parts ~expected_records =
  let* index_text = read_regular_bounded ~limit:max_index_bytes index_path in
  if sha256 index_text <> expected_sha256 then
    Error (Invalid_index (index_path ^ ": bound index SHA256 mismatch"))
  else
  let* index_json = parse_json index_path index_text in
  let* declared_records = int_field index_path "record_count" index_json in
  let* parts = list_field index_path "parts" index_json in
  if declared_records <> expected_records then
    Error (Invalid_index (Printf.sprintf "%s: declared records %d, expected %d"
                            index_path declared_records expected_records))
  else if List.length parts <> expected_parts || List.length parts > max_parts then
    Error (Invalid_index (Printf.sprintf "%s: part count %d, expected %d"
                            index_path (List.length parts) expected_parts))
  else
    let rec verify part_count record_count keys declarations cases imports headings unknown unrun
        bindings source_ledger case_ledger = function
      | [] ->
          if record_count <> declared_records then
            Error (Invalid_index (Printf.sprintf "%s: observed records %d, declared %d"
                                    index_path record_count declared_records))
          else
            let unique_records = List.length (List.sort_uniq String.compare keys) in
            Ok { index_path; verified_parts = part_count; verified_records = record_count;
                 unique_records; duplicate_records = record_count - unique_records;
                 declarations; cases; imports; headings;
                 execution_unknown = unknown; execution_unrun = unrun;
                 bindings =
                   `Assoc [ ("path", `String index_path); ("sha256", `String expected_sha256);
                            ("records", `Int declared_records);
                            ("bytes", `Int (String.length index_text));
                            ("kind", `String "TOP_INDEX") ]
                   :: List.rev bindings;
                 source_ledger = List.rev source_ledger;
                 case_ledger = List.rev case_ledger }
      | part :: tail ->
          let label = Printf.sprintf "%s.parts[%d]" index_path part_count in
          let* path = string_field label "path" part in
          let* declared_part_records = int_field label "records" part in
          let* declared_bytes = int_field label "bytes" part in
          let* declared_sha256 = string_field label "sha256" part in
          if not (canonical_relative_path path) || not (starts_with "docs/design/" path) then
            Error (Invalid_index (label ^ ": part path is outside docs/design"))
          else if declared_bytes < 0 || declared_bytes > max_part_bytes then
            Error (Invalid_index (label ^ ": invalid declared byte size"))
          else
            let* text = read_regular_bounded ~limit:max_part_bytes path in
            if String.length text <> declared_bytes then
              Error (Invalid_index (label ^ ": byte count mismatch"))
            else if sha256 text <> declared_sha256 then
              Error (Invalid_index (label ^ ": SHA256 mismatch"))
            else
              let* json = parse_json path text in
              let* records = list_field path "records" json in
              if List.length records <> declared_part_records then
                Error (Invalid_index (label ^ ": record count mismatch"))
              else if record_count + List.length records > max_records then
                Error (Invalid_index (index_path ^ ": aggregate record limit exceeded"))
              else
                let binding = `Assoc
                  [ ("path", `String path); ("sha256", `String declared_sha256);
                    ("records", `Int declared_part_records); ("bytes", `Int declared_bytes);
                    ("kind", `String "PART") ] in
                let rec collect keys declarations cases imports headings unknown unrun
                    source_ledger case_ledger = function
                  | [] -> Ok (keys, declarations, cases, imports, headings, unknown, unrun,
                              source_ledger, case_ledger)
                  | record :: rest ->
                      let* key = record_key path record in
                      let* source_row, case_rows =
                        partition_ledger_rows ~scope:index_path ~index_path
                          ~index_sha256:expected_sha256 ~part_path:path
                          ~part_sha256:declared_sha256 record in
                      let state = execution_of_record record in
                      collect (key :: keys)
                        (declarations + count_list_field "declarations" record)
                        (cases + count_list_field "cases" record)
                        (imports + count_list_field "imports" record)
                        (headings + count_list_field "heading_index" record)
                        (unknown + if state = `Unknown then 1 else 0)
                        (unrun + if state = `Unrun then 1 else 0)
                        (source_row :: source_ledger)
                        (List.rev_append case_rows case_ledger) rest
                in
                let* keys, declarations, cases, imports, headings, unknown, unrun,
                     source_ledger, case_ledger =
                  collect keys declarations cases imports headings unknown unrun
                    source_ledger case_ledger records
                in
                verify (part_count + 1) (record_count + List.length records)
                  keys declarations cases imports headings unknown unrun
                  (binding :: bindings) source_ledger case_ledger tail
    in
    verify 0 0 [] 0 0 0 0 0 0 [] [] [] parts

type ocaml_inventory_report = {
  inventory_records : int;
  raw_sites : int;
  unique_sites : int;
  duplicate_sites : int;
  parsed_records : int;
  unrun_records : int;
  bindings : Yojson.Basic.t list;
  source_ledger : Yojson.Basic.t list;
  case_ledger : Yojson.Basic.t list;
}

let verify_ocaml_inventory ?expected_sha256 path =
  let valid_digest value =
    String.length value = 64
    && String.for_all
         (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
         value
  in
  let* expected_sha256 =
    match expected_sha256 with
    | Some digest when valid_digest digest -> Ok digest
    | Some _ -> Error (Invalid_index (path ^ ": invalid bound inventory SHA256"))
    | None -> Error (Invalid_index (path ^ ": bound inventory SHA256 is required"))
  in
  let* text = read_regular_bounded ~limit:max_index_bytes path in
  if sha256 text <> expected_sha256 then
    Error (Invalid_index (path ^ ": bound inventory SHA256 mismatch"))
  else
  let* json = parse_json path text in
  let* records = list_field path "records" json in
  let* source_root = string_field path "source_root" json in
  if List.length records > max_records then Error (Invalid_index (path ^ ": too many records"))
  else
    let rec collect keys raw parsed unrun source_ledger case_ledger = function
      | [] ->
          let unique_sites = List.length (List.sort_uniq String.compare keys) in
          Ok { inventory_records = List.length records; raw_sites = raw; unique_sites;
               duplicate_sites = raw - unique_sites; parsed_records = parsed;
               unrun_records = unrun;
               bindings = [ `Assoc [ ("path", `String path);
                                      ("sha256", `String expected_sha256);
                                      ("records", `Int (List.length records));
                                      ("bytes", `Int (String.length text)) ] ];
               source_ledger = List.rev source_ledger;
               case_ledger = List.rev case_ledger }
      | `Assoc fields :: tail ->
          let source = match List.assoc_opt "path" fields with Some (`String v) -> v | _ -> "" in
          if source = "" then Error (Invalid_index (path ^ ": record lacks path"))
          else
            let sites = match List.assoc_opt "sites" fields with Some (`List v) -> v | _ -> [] in
            let source_identity = String.concat "\000" [ "ocaml_inventory"; source_root; source ] in
            let source_id = "uos:source:v1:" ^ String.sub (sha256 source_identity) 0 32 in
            let coverage = optional_string "coverage" fields in
            let transfer = optional_string "port" fields in
            let execution = optional_string "execution_status" fields in
            let source_sha = optional_string "sha256" fields in
            let source_row =
              `Assoc
                [ ("source_id", `String source_id); ("scope", `String "ocaml_inventory");
                  ("project", `String "zigvm"); ("root", `String source_root);
                  ("path", `String source); ("locator", `String (source_root ^ "/" ^ source));
                  ("source_sha256", `String source_sha); ("bound_index", `String path);
                  ("bound_index_sha256", `String expected_sha256);
                  ("review_state", `String "HASHED_AND_STATICALLY_PARSED_NOT_CLOSE_READ");
                  ("close_read", `Bool false); ("excluded", `Bool false);
                  ("frontier", `String "Dune_registration_oracle_and_execution_confirmation_open");
                  ("registration_state", `String "DUNE_REGISTRATION_UNVERIFIED");
                  ("browser_class", `String "BX_REVIEW_REQUIRED");
                  ("transfer_decision", `String (if transfer = "" then "UNDECIDED" else transfer));
                  ("runner", `String "dune_candidate");
                  ("execution_state", `String (if execution = "" then "UNKNOWN" else execution));
                  ("coverage_scope", `String
                    (if coverage = "" then "static site inventory only" else coverage)) ]
            in
            let rec site_keys index keys case_ledger = function
              | [] -> Ok (keys, case_ledger)
              | `Assoc site :: rest ->
                  let string name = match List.assoc_opt name site with Some (`String v) -> v | _ -> "" in
                  let integer name = match List.assoc_opt name site with Some (`Int v) -> v | _ -> -1 in
                  let kind = string "kind" and label = string "label" in
                  let line = integer "line" and end_line = integer "end_line" in
                  if kind = "" || label = "" || line < 1 || end_line < line then
                    Error (Invalid_index (Printf.sprintf "%s: invalid site at %s[%d]" path source index))
                  else
                    let key = String.concat "\000"
                      [ source; kind; label; string_of_int line; string_of_int end_line ] in
                    let case_identity = source_identity ^ "\000" ^ key in
                    let row =
                      `Assoc
                        [ ("case_id", `String
                            ("uos:case:v1:" ^ String.sub (sha256 case_identity) 0 32));
                          ("source_id", `String source_id); ("scope", `String "ocaml_inventory");
                          ("locator", `String (source_root ^ "/" ^ source));
                          ("span", `Assoc [ ("start_line", `Int line); ("end_line", `Int end_line);
                                             ("confidence", `String "STATIC_PARSER_SPAN") ]);
                          ("declaration_kind", `String kind);
                          ("oracle_state", `String "STATIC_SITE_LABEL_ONLY_ORACLE_UNCONFIRMED");
                          ("oracle_label", `String label); ("coverage_scope", `String coverage);
                          ("browser_class", `String "BX_REVIEW_REQUIRED");
                          ("transfer_decision", `String transfer); ("runner", `String "dune_candidate");
                          ("execution_state", `String (if execution = "" then "UNKNOWN" else execution));
                          ("review_state", `String "STATIC_SITE_NOT_REGISTERED_OR_EXECUTED_CASE");
                          ("frontier", `String "Dune_registration_oracle_and_execution_confirmation_open");
                          ("bound_index", `String path); ("bound_index_sha256", `String expected_sha256) ]
                    in
                    site_keys (index + 1) (key :: keys) (row :: case_ledger) rest
              | _ :: _ -> Error (Invalid_index (path ^ ": site must be object"))
            in
            let* keys, case_ledger = site_keys 0 keys case_ledger sites in
            let parsed = parsed +
              (match List.assoc_opt "parse_status" fields with Some (`String "parsed") -> 1 | _ -> 0) in
            let unrun = unrun +
              (match List.assoc_opt "execution_status" fields with Some (`String "UNRUN") -> 1 | _ -> 0) in
            collect keys (raw + List.length sites) parsed unrun
              (source_row :: source_ledger) case_ledger tail
      | _ :: _ -> Error (Invalid_index (path ^ ": record must be object"))
    in
    collect [] 0 0 0 [] [] records

let summary_to_yojson summary =
  let string_of_read_depth = function
    | Unreadable -> "UNREADABLE"
    | Indexed -> "INDEXED"
    | Hashed -> "HASHED"
    | Close_read -> "CLOSE_READ"
  in
  let string_of_kind = function
    | Test_source -> "TEST_SOURCE"
    | Helper_source -> "HELPER_SOURCE"
    | Document -> "DOCUMENT"
    | Generated -> "GENERATED"
    | Binary -> "BINARY"
  in
  let string_of_registration = function
    | Registered runner -> `Assoc [ ("state", `String "REGISTERED"); ("runner", `String runner) ]
    | Unregistered -> `Assoc [ ("state", `String "UNREGISTERED"); ("runner", `Null) ]
  in
  let string_of_browser = function
    | No_browser_driver_observed -> "B0_NO_BROWSER_DRIVER_OBSERVED"
    | Server_or_component -> "B1_SERVER_OR_COMPONENT"
    | Simulated_browser -> "B2_SIMULATED_BROWSER"
    | Real_browser_declared -> "B3_REAL_BROWSER_DECLARED"
    | Browser_review_required -> "BX_REVIEW_REQUIRED"
  in
  let string_of_transfer = function
    | Retain_evidence -> "RETAIN_EVIDENCE"
    | Port_candidate -> "PORT_CANDIDATE"
    | Exclude reason -> "EXCLUDE:" ^ reason
  in
  let string_of_execution = function
    | Unrun -> "UNRUN" | Passed -> "PASSED" | Failed -> "FAILED"
    | Skipped -> "SKIPPED" | Unknown -> "UNKNOWN"
  in
  let record_to_json record =
    `Assoc
      [ ("source_id", `String record.source_id); ("path", `String record.path);
        ("locator", `String record.locator);
        ("span", match record.span with None -> `Null | Some span ->
          `Assoc [ ("start_line", `Int span.start_line); ("end_line", `Int span.end_line) ]);
        ("kind", `String (string_of_kind record.kind));
        ("registration", string_of_registration record.registration);
        ("oracle", `String record.oracle);
        ("coverage_scope", `String record.coverage_scope);
        ("browser_class", `String (string_of_browser record.browser_class));
        ("transfer", `String (string_of_transfer record.transfer));
        ("runner", `String record.runner);
        ("execution_state", `String (string_of_execution record.execution_state));
        ("read_depth", `String (string_of_read_depth record.read_depth)) ]
  in
  `Assoc
    [ ("files_accounted", `Int summary.files_accounted);
      ("unreadable", `Int summary.unreadable_count);
      ("complete_review", `Bool summary.complete_review);
      ("executed_tests", `Int summary.executed_tests);
      ("registered_test_files", `Int summary.registered_test_files);
      ("ast_sites", `Int summary.ast_sites);
      ("reviewed_files", `Int summary.reviewed_files);
      ("classified_exclusions", `Int summary.classified_exclusions);
      ("frontier_count", `Int summary.frontier_count);
      ("accounting_closed",
        `Bool
          (summary.files_accounted =
           summary.reviewed_files + summary.classified_exclusions + summary.frontier_count));
      ("review_frontier", `List (List.map (fun item -> `String item) summary.review_frontier));
      ("records", `List (List.map record_to_json summary.records)) ]

let verify_artifact_digest path expected =
  let* text = read_regular_bounded ~limit:max_index_bytes path in
  let observed = sha256 text in
  if observed = expected then Ok ()
  else
    Error
      (Invalid_index
        (Printf.sprintf "%s: digest mismatch, expected %s, observed %s"
          path expected observed))

let repository_evidence () =
  let* ocaml = verify_ocaml_inventory
    ~expected_sha256:"d9b9a71e32de595ff2d04f1dd027ba05ebd743b7c92dc9313bcf155a0f9eb5ee"
    "docs/journal/20260906-0428-ocaml-web-tests-inventory.json" in
  let* corpus = verify_partitioned_index
    ~index_path:"docs/design/20260906-0631-source-corpus-index.json"
    ~expected_sha256:"7f2b1f93824211ebd8fe6e37756adc299760952fd7fe879bded1eb5b85cae1c7"
    ~expected_parts:24 ~expected_records:8047 in
  let* catalogue = verify_partitioned_index
    ~index_path:"docs/design/20260906-0631-cross-project-test-catalogue.json"
    ~expected_sha256:"475739f4b9485b01fee471fd130bb7adc7d2c95351178458f070cc29ccced603"
    ~expected_parts:12 ~expected_records:770 in
  Ok (ocaml, corpus, catalogue)

let scope_accounting name files_accounted reviewed classified_exclusions frontier =
  `Assoc
    [ ("scope", `String name); ("files_accounted", `Int files_accounted);
      ("reviewed_close_read", `Int reviewed);
      ("classified_exclusions", `Int classified_exclusions);
      ("explicit_frontier", `Int frontier);
      ("accounting_closed",
        `Bool (files_accounted = reviewed + classified_exclusions + frontier)) ]

let ledger_id field = function
  | `Assoc fields ->
      (match List.assoc_opt field fields with Some (`String value) -> value | _ -> "")
  | _ -> ""

let repository_ledger_from (ocaml : ocaml_inventory_report)
    (corpus : partition_report) (catalogue : partition_report) =
  let source_records =
    ocaml.source_ledger @ corpus.source_ledger @ catalogue.source_ledger in
  let case_records = ocaml.case_ledger @ catalogue.case_ledger in
  let source_ids = List.map (ledger_id "source_id") source_records in
  let case_ids = List.map (ledger_id "case_id") case_records in
  let source_unique = List.length (List.sort_uniq String.compare source_ids) in
  let case_unique = List.length (List.sort_uniq String.compare case_ids) in
  `Assoc
    [ ("schema", `String "uos.source-census-ledger.v1");
      ("authority", `String "checked UOS static indexes; external bytes not reobserved");
      ("complete_review", `Bool false); ("executed_tests", `Int 0);
      ("bindings", `List (ocaml.bindings @ corpus.bindings @ catalogue.bindings));
      ("scope_accounting",
        `List
          [ scope_accounting "ocaml_inventory" ocaml.inventory_records 0 0
              ocaml.inventory_records;
            scope_accounting "source_corpus" corpus.verified_records 0
              corpus.execution_unknown corpus.execution_unrun;
            scope_accounting "selected_test_catalogue" catalogue.verified_records 0 0
              catalogue.verified_records ]);
      ("identity_checks",
        `Assoc
          [ ("source_rows", `Int (List.length source_records));
            ("unique_source_ids", `Int source_unique);
            ("source_ids_unique", `Bool (source_unique = List.length source_records));
            ("case_rows", `Int (List.length case_records));
            ("unique_case_ids", `Int case_unique);
            ("case_ids_unique", `Bool (case_unique = List.length case_records)) ]);
      ("source_records", `List source_records); ("case_records", `List case_records) ]

let repository_ledger () =
  let* ocaml, corpus, catalogue = repository_evidence () in
  let ledger = repository_ledger_from ocaml corpus catalogue in
  let source_ids =
    match List.assoc_opt "source_records" (match ledger with `Assoc fields -> fields | _ -> []) with
    | Some (`List rows) -> List.map (ledger_id "source_id") rows
    | _ -> [] in
  let case_ids =
    match List.assoc_opt "case_records" (match ledger with `Assoc fields -> fields | _ -> []) with
    | Some (`List rows) -> List.map (ledger_id "case_id") rows
    | _ -> [] in
  if List.exists (( = ) "") (source_ids @ case_ids)
     || List.length (List.sort_uniq String.compare source_ids) <> List.length source_ids
     || List.length (List.sort_uniq String.compare case_ids) <> List.length case_ids
  then Error (Invalid_index "census ledger contains empty or duplicate stable identities")
  else Ok ledger

let repository_report () =
  let* ocaml, corpus, catalogue = repository_evidence () in
  let ledger = repository_ledger_from ocaml corpus catalogue in
  let ledger_text = Yojson.Basic.to_string ledger ^ "\n" in
  Ok
    (`Assoc
      [ ("schema", `String "uos.source-census.v1");
        ("status", `String "INDEXES_VERIFIED_REVIEW_FRONTIER_OPEN");
        ("complete_review", `Bool false);
        ("external_source_bytes_reobserved", `Bool false);
        ("source_files_modified", `Int 0);
        ("scope_accounting",
          `List
            [ scope_accounting "ocaml_inventory" ocaml.inventory_records 0 0
                ocaml.inventory_records;
              scope_accounting "source_corpus" corpus.verified_records 0
                corpus.execution_unknown corpus.execution_unrun;
              scope_accounting "selected_test_catalogue" catalogue.verified_records 0 0
                catalogue.verified_records ]);
        ("ledger",
          `Assoc
            [ ("schema", `String "uos.source-census-ledger.v1");
              ("source_rows", `Int
                (List.length ocaml.source_ledger + List.length corpus.source_ledger
                 + List.length catalogue.source_ledger));
              ("case_rows", `Int
                (List.length ocaml.case_ledger + List.length catalogue.case_ledger));
              ("sha256", `String (sha256 ledger_text));
              ("bytes", `Int (String.length ledger_text));
              ("materialization", `String "use --write-ledger /tmp/PATH") ]);
        ("ocaml_inventory",
          `Assoc
            [ ("records", `Int ocaml.inventory_records);
              ("raw_sites", `Int ocaml.raw_sites);
              ("unique_sites", `Int ocaml.unique_sites);
              ("duplicate_sites", `Int ocaml.duplicate_sites);
              ("parsed_records", `Int ocaml.parsed_records);
              ("executed_tests", `Int 0) ]);
        ("source_corpus",
          `Assoc
            [ ("parts", `Int corpus.verified_parts);
              ("records", `Int corpus.verified_records);
              ("unique_records", `Int corpus.unique_records);
              ("duplicate_records", `Int corpus.duplicate_records);
              ("execution_unrun", `Int corpus.execution_unrun);
              ("execution_unknown", `Int corpus.execution_unknown);
              ("linked_heading_rows", `Int corpus.headings) ]);
        ("selected_test_catalogue",
          `Assoc
            [ ("parts", `Int catalogue.verified_parts);
              ("records", `Int catalogue.verified_records);
              ("unique_records", `Int catalogue.unique_records);
              ("duplicate_records", `Int catalogue.duplicate_records);
              ("lexical_case_candidates", `Int catalogue.cases);
              ("lexical_import_candidates", `Int catalogue.imports);
              ("execution_unrun", `Int catalogue.execution_unrun) ]);
        ("review_frontier",
          `List
            (List.map (fun value -> `String value)
              [ "registration_edges:Dune/Gleeunit/ExUnit/Gherkin:close_read_open";
                "AST/import/call_edges:selected_case_close_read_open";
                "linked_documents_and_journals:relationship_review_open";
                "external_root:indrajaal_nested:indexed_not_reobserved";
                "external_root:sutra_symlink:topology_review_open";
                "generated/binary/unreadable/excluded:external_rescan_requires_fresh_source_binding" ])) ])

let max_ledger_bytes = 64 * 1024 * 1024

let write_all descriptor value =
  let rec loop offset =
    if offset < String.length value then
      let count = Unix.write_substring descriptor value offset (String.length value - offset) in
      if count = 0 then raise (Sys_error "zero-byte ledger write") else loop (offset + count)
  in
  loop 0

let write_ledger_atomic path value =
  if not (starts_with "/tmp/" path) || has_nul path || String.length value > max_ledger_bytes then
    Error (Io_error "ledger path or byte bound is invalid")
  else
    let temporary =
      Printf.sprintf "%s.%d.%08x.tmp" path (Unix.getpid ()) (Random.bits ()) in
    let renamed = ref false in
    try
      let descriptor = Unix.openfile temporary
        [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC ] 0o600 in
      Fun.protect
        ~finally:(fun () ->
          (try Unix.close descriptor with Unix.Unix_error _ -> ());
          if not !renamed then (try Unix.unlink temporary with Unix.Unix_error _ -> ()))
        (fun () ->
          write_all descriptor value;
          Unix.fsync descriptor;
          Unix.close descriptor;
          Unix.rename temporary path;
          renamed := true;
          let directory = Unix.openfile (Filename.dirname path)
            [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 in
          Fun.protect ~finally:(fun () -> Unix.close directory)
            (fun () -> Unix.fsync directory));
      Ok ()
    with
    | Unix.Unix_error (_, _, message) | Sys_error message -> Error (Io_error message)

let census_direct_invocation () = Filename.basename Sys.argv.(0) = "census.ml"

let census_main () =
  match Array.to_list Sys.argv with
  | [ _; "--verify-indexes" ] ->
      (match repository_report () with
       | Error error -> prerr_endline (string_of_error error); 1
       | Ok report -> print_endline (Yojson.Basic.pretty_to_string report); 0)
  | [ _; "--write-ledger"; path ] ->
      (match repository_ledger () with
       | Error error -> prerr_endline (string_of_error error); 1
       | Ok ledger ->
           let value = Yojson.Basic.to_string ledger ^ "\n" in
           (match write_ledger_atomic path value with
            | Error error -> prerr_endline (string_of_error error); 1
            | Ok () ->
                print_endline (Yojson.Basic.to_string
                  (`Assoc [ ("ledger_path", `String path);
                            ("ledger_sha256", `String (sha256 value));
                            ("ledger_bytes", `Int (String.length value)) ]));
                0))
  | _ ->
      prerr_endline
        "usage: ocaml tools/source_review/census.ml (--verify-indexes | --write-ledger /tmp/PATH)";
      2

let () = if census_direct_invocation () then exit (census_main ())
