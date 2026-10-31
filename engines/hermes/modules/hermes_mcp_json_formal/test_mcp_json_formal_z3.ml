(* Source-bound abstract checks, not parser extraction or system admission.
   Integrated: dune exec modules/hermes_mcp_json_formal/test_mcp_json_formal_z3.exe
   Dune: the supplied (test ... (libraries unix)) stanza.
   Every solver invocation passes through tools/ecology_process.ml; there is
   no shell, direct Z3 spawn, or unbounded solver fallback. Temp files and the
   receipt stay in the current directory (or MCP_JSON_FORMAL_WORKDIR).
   UOS_ROOT wins; otherwise ancestors of cwd/executable are searched for .jj.
   The read-only deployment anchor is the final standalone-scratch fallback.
   SMT is_object means a VALID RPC object; shape_object denotes JSON shape.
   Malformed no-id objects still emit -32600, as the explicit SAT control shows.
   Seven outcomes = five standard error codes, notification silence, success.
   Batch and all eight strata are covered in the companion Lean model.
*)

let require condition message = if not condition then failwith message
let anchor = "/home/an/NAS-setup/uos"
let join = Filename.concat
let exists path = Sys.file_exists path

let absolute path =
  if Filename.is_relative path then join (Sys.getcwd ()) path else path

let rec find_root path =
  if exists (join path ".jj") && exists (join path "tools/ecology_process.ml")
  then Some path
  else
    let parent = Filename.dirname path in
    if parent = path then None else find_root parent

let resolve_root () =
  match Sys.getenv_opt "UOS_ROOT" with
  | Some root when root <> "" ->
      let root = Unix.realpath (absolute root) in
      require (exists (join root "tools/ecology_process.ml")) "invalid UOS_ROOT";
      root, "UOS_ROOT"
  | _ ->
      let candidates = [Sys.getcwd (); Filename.dirname (absolute Sys.argv.(0))] in
      match List.find_map find_root candidates with
      | Some root -> root, "ancestor .jj discovery"
      | None ->
          require (exists (join anchor ".jj") &&
                   exists (join anchor "tools/ecology_process.ml"))
            "UOS root unavailable; set UOS_ROOT";
          anchor, "read-only standalone deployment anchor"

let executable path =
  try Unix.access path [Unix.X_OK]; not (Sys.is_directory path) with _ -> false

let resolve_z3 root =
  let pinned = join root "toolchains/nix-profile/bin/z3" in
  if executable pinned then pinned, false
  else
    let paths = Option.value (Sys.getenv_opt "PATH") ~default:"" in
    let found = String.split_on_char ':' paths
      |> List.find_map (fun dir ->
           let path = absolute (join (if dir = "" then "." else dir) "z3") in
           if executable path then Some path else None) in
    match found with
    | Some path ->
        Printf.eprintf "[FALLBACK] pinned Z3 unavailable; using %s through ecology_process\n%!" path;
        path, true
    | None -> failwith "Z3 unavailable (pinned and PATH); verification fails closed"

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let write_file path contents =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_string oc contents)

let json_string value =
  let b = Buffer.create (String.length value + 8) in
  Buffer.add_char b '"';
  String.iter (function
    | '"' -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c when Char.code c < 32 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char b c) value;
  Buffer.add_char b '"'; Buffer.contents b

let json_list f xs = "[" ^ String.concat "," (List.map f xs) ^ "]"
let json_obj xs = "{" ^ String.concat "," (List.map (fun (k,v) -> json_string k ^ ":" ^ v) xs) ^ "}"
let jbool x = if x then "true" else "false"

type process_result = { argv : string list; status : int; output : string; seconds : float }

let run_capture executable arguments =
  let argv = Array.of_list (executable :: arguments) in
  let rd, wr = Unix.pipe ~cloexec:true () in
  let started = Unix.gettimeofday () in
  let pid =
    try Unix.create_process executable argv Unix.stdin wr wr
    with exn -> Unix.close rd; Unix.close wr; raise exn in
  Unix.close wr;
  let ic = Unix.in_channel_of_descr rd in
  let b = Buffer.create 1024 in
  let bytes = Bytes.create 4096 in
  let rec pump () =
    let n = input ic bytes 0 (Bytes.length bytes) in
    if n > 0 then (Buffer.add_subbytes b bytes 0 n; pump ()) in
  let capture_error = try pump (); None with exn -> Some exn in
  close_in_noerr ic;
  let rec wait () =
    try snd (Unix.waitpid [] pid)
    with Unix.Unix_error (Unix.EINTR, _, _) -> wait () in
  let status = match wait () with
    | Unix.WEXITED code -> code
    | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 125 in
  (match capture_error with Some exn -> raise exn | None -> ());
  { argv = Array.to_list argv; status; output = Buffer.contents b;
    seconds = Unix.gettimeofday () -. started }

let process_json r = json_obj [
  "argv", json_list json_string r.argv; "exit_code", string_of_int r.status;
  "stdout_stderr", json_string r.output; "elapsed_seconds", Printf.sprintf "%.6f" r.seconds]

let guarded ocaml guardian executable arguments =
  run_capture ocaml (["-I"; "+unix"; guardian; "5000"; "65536"; "merged"; executable] @ arguments)

let parse_verdict output =
  match String.trim output with
  | "sat" -> Some "sat"
  | "unsat" -> Some "unsat"
  | _ -> None

type query = { name : string; expected : string; control : string option; script : string }

let smt logic body = "(set-logic " ^ logic ^ ")\n" ^ body ^ "\n(check-sat)\n(exit)\n"
let sat name logic body = { name; expected = "sat"; control = None; script = smt logic body }
let proof name control logic body =
  { name; expected = "unsat"; control = Some control; script = smt logic body }

let duplicate_base n =
  let declarations = List.init n (fun i ->
    Printf.sprintf "(declare-const k%d Int)\n(declare-const v%d Int)" i i) in
  let lookup order = List.fold_right (fun i rest ->
    Printf.sprintf "(ite (= target k%d) v%d %s)" i i rest) order "(- 1)" in
  let indices = List.init n Fun.id in
  String.concat "\n" declarations ^ "\n(declare-const target Int)\n" ^
  "(define-fun first_lookup () Int " ^ lookup indices ^ ")\n" ^
  "(define-fun last_lookup () Int " ^ lookup (List.rev indices) ^ ")\n"

let unique_constraint n =
  "(assert (distinct " ^ String.concat " " (List.init n (Printf.sprintf "k%d")) ^ "))\n"

let unique_control n =
  String.concat "\n" (List.init n (fun i ->
    Printf.sprintf "(assert (= k%d %d))\n(assert (= v%d %d))" i i i (i+10))) ^
  "\n(assert (= target 0))\n(assert (= first_lookup last_lookup))\n"

let depth_base = {|
(declare-const d Int)
(declare-const d_next Int)
(define-fun reachable () Bool (and (<= 0 d) (<= d 32)))
(define-fun accepted_push () Bool (and reachable (< d 32) (= d_next (+ d 1))))
|}

let unicode_base = {|
(declare-const u Int)
(assert (<= 0 u))
(define-fun accepted_scalar () Bool
  (or (and (<= 1 u) (<= u 55295)) (and (<= 57344 u) (<= u 1114111))))
|}

let taxonomy_base = {|
(declare-const parse_ok Bool)
(declare-const shape_object Bool)
(declare-const version_ok Bool)
(declare-const method_string Bool)
(declare-const has_id Bool)
(declare-const id_type_ok Bool)
(declare-const known_method Bool)
(declare-const params_valid Bool)
(declare-const handler_ok Bool)
; Shape alone does NOT imply notification validity.
(define-fun envelope_valid () Bool
  (and shape_object version_ok method_string (or (not has_id) id_type_ok)))
; is_object is the valid-RPC-object domain, including successful JSON parsing.
(define-fun is_object () Bool (and parse_ok envelope_valid))
(define-fun parse_error () Bool (not parse_ok))
(define-fun notification_shape () Bool (and shape_object method_string (not has_id)))
(define-fun invalid_request () Bool (and parse_ok (not notification_shape) (not envelope_valid)))
(define-fun silent () Bool (and parse_ok notification_shape))
(define-fun method_not_found () Bool (and is_object has_id (not known_method)))
(define-fun invalid_params () Bool (and is_object has_id known_method (not params_valid)))
(define-fun internal_error () Bool (and is_object has_id known_method params_valid (not handler_ok)))
(define-fun success () Bool (and is_object has_id known_method params_valid handler_ok))
; Independently encode dispatch priority as an integer-valued decision tree.
; 0 = no reply, 1 = success, negatives = the five JSON-RPC standard errors.
(define-fun wire_code () Int
  (ite (not parse_ok) (- 32700)
    (ite notification_shape 0
      (ite (not envelope_valid) (- 32600)
        (ite (not known_method) (- 32601)
          (ite (not params_valid) (- 32602)
            (ite (not handler_ok) (- 32603) 1)))))))
(define-fun emits_bytes () Bool (not (= wire_code 0)))
|}

let classes = ["parse_error", -32700; "invalid_request", -32600; "silent", 0;
               "method_not_found", -32601; "invalid_params", -32602;
               "internal_error", -32603; "success", 1]

let overlap =
  let rec pairs = function
    | [] -> []
    | (x,_) :: xs -> List.map (fun (y,_) -> "(and " ^ x ^ " " ^ y ^ ")") xs @ pairs xs in
  "(or " ^ String.concat " " (pairs classes) ^ ")"

let success_state = {|
(assert parse_ok) (assert shape_object) (assert version_ok) (assert method_string)
(assert has_id) (assert id_type_ok) (assert known_method) (assert params_valid) (assert handler_ok)
|}

let notification_state = {|
(assert parse_ok) (assert shape_object) (assert version_ok) (assert method_string)
(assert (not has_id))
|}

let int_smt n = if n < 0 then Printf.sprintf "(- %d)" (-n) else string_of_int n

let core_queries () =
  let duplicate_proofs = List.concat_map (fun n ->
    let id = Printf.sprintf "control1_unique_n%d_sat" n in
    let base = duplicate_base n ^ unique_constraint n in
    [sat id "QF_LIA" (base ^ unique_control n);
     proof (Printf.sprintf "proof1_unique_n%d_unsat" n) id "QF_LIA"
       (base ^ "(assert (not (= first_lookup last_lookup)))")]) [3;4] in
  [sat "control1_duplicate_attack_sat" "QF_LIA" (duplicate_base 3 ^ {|
(assert (= target 7)) (assert (= k0 7)) (assert (= k1 9)) (assert (= k2 7))
(assert (= v0 10)) (assert (= v1 20)) (assert (= v2 30))
(assert (= first_lookup 10)) (assert (= last_lookup 30))
(assert (not (= first_lookup last_lookup)))
|})] @ duplicate_proofs @ [
  sat "control2_reachable_depth32_sat" "QF_LIA"
    (depth_base ^ "(assert reachable)\n(assert (= d 32))");
  sat "control2_accepted_push_to32_sat" "QF_LIA"
    (depth_base ^ "(assert accepted_push)\n(assert (= d 31))\n(assert (= d_next 32))");
  proof "proof2_accepted_overflow_unsat" "control2_accepted_push_to32_sat" "QF_LIA"
    (depth_base ^ "(assert accepted_push)\n(assert (> d_next 32))");
  sat "control3_scalar_A_sat" "QF_LIA"
    (unicode_base ^ "(assert accepted_scalar)\n(assert (= u 65))");
  proof "proof3_nul_surrogate_above_max_unsat" "control3_scalar_A_sat" "QF_LIA"
    (unicode_base ^ {|
(assert accepted_scalar)
(assert (or (= u 0) (and (<= 55296 u) (<= u 57343)) (> u 1114111)))
|});
  sat "control4_total_success_sat" "QF_LIA" (taxonomy_base ^ success_state);
  proof "proof4_taxonomy_total_unsat" "control4_total_success_sat" "QF_LIA"
    (taxonomy_base ^ "(assert (not (or " ^ String.concat " " (List.map fst classes) ^ ")))");
  sat "control4_single_class_sat" "QF_LIA" (taxonomy_base ^ success_state ^ "(assert success)");
  proof "proof4_taxonomy_pairwise_disjoint_unsat" "control4_single_class_sat" "QF_LIA"
    (taxonomy_base ^ "(assert " ^ overlap ^ ")");
  sat "control4_valid_notification_sat" "QF_LIA"
    (taxonomy_base ^ notification_state ^ "(assert (= wire_code 0))");
  proof "proof4_notification_no_emission_unsat" "control4_valid_notification_sat" "QF_LIA"
    (taxonomy_base ^ "(assert (and is_object (not has_id) emits_bytes))");
  sat "control4_unknown_notification_sat" "QF_LIA"
    (taxonomy_base ^ notification_state ^ "(assert (not known_method))\n(assert (= wire_code 0))");
  proof "proof4_unknown_notification_no_emission_unsat" "control4_unknown_notification_sat" "QF_LIA"
    (taxonomy_base ^ notification_state ^ "(assert (not known_method))\n(assert emits_bytes)");
  sat "control4_known_notification_sat" "QF_LIA"
    (taxonomy_base ^ notification_state ^ "(assert known_method)\n(assert (= wire_code 0))");
  proof "proof4_known_notification_no_emission_unsat" "control4_known_notification_sat" "QF_LIA"
    (taxonomy_base ^ notification_state ^ "(assert known_method)\n(assert emits_bytes)");
  sat "control4_invalid_no_id_object_emits_error_sat" "QF_LIA"
    (taxonomy_base ^ {|
(assert parse_ok) (assert shape_object) (assert (not version_ok))
(assert (not has_id)) (assert emits_bytes) (assert (= wire_code (- 32600)))
|});
  sat "control4_code_correspondence_sat" "QF_LIA" (taxonomy_base ^ success_state);
  proof "proof4_seven_code_correspondence_unsat" "control4_code_correspondence_sat" "QF_LIA"
    (taxonomy_base ^ "(assert (not (and " ^
     String.concat " " (List.map (fun (name,code) ->
       "(= " ^ name ^ " (= wire_code " ^ int_smt code ^ "))") classes) ^ ")))")
  ] @ List.map (fun (name,code) ->
    sat ("control4_reachable_" ^ name ^ "_sat") "QF_LIA"
      (taxonomy_base ^ "(assert " ^ name ^ ")\n(assert (= wire_code " ^ int_smt code ^ "))")) classes

(* Full gateway taxonomy extends the seven standard core outcomes with bounded
   overload and resource absence. Tool-domain refusals remain successful RPC
   envelopes, with result.isError, rather than forged protocol failures. *)
let extended_taxonomy = {|
(declare-const parsed Bool) (declare-const envelope Bool)
(declare-const has_id Bool) (declare-const known Bool)
(declare-const params Bool) (declare-const overloaded Bool)
(declare-const resource_missing Bool) (declare-const handler_ok Bool)
(declare-const domain_refused Bool)
(define-fun parse_error () Bool (not parsed))
(define-fun invalid_request () Bool (and parsed (not envelope)))
(define-fun notification () Bool (and parsed envelope (not has_id)))
(define-fun routed () Bool (and parsed envelope has_id))
(define-fun method_error () Bool (and routed (not known)))
(define-fun params_error () Bool (and routed known (not params)))
(define-fun capacity_error () Bool (and routed known params overloaded))
(define-fun resource_error () Bool (and routed known params (not overloaded) resource_missing))
(define-fun internal_error () Bool (and routed known params (not overloaded) (not resource_missing) (not handler_ok)))
(define-fun complete_or_refused () Bool (and routed known params (not overloaded) (not resource_missing) handler_ok))
(define-fun code () Int
  (ite (not parsed) (- 32700) (ite (not envelope) (- 32600)
    (ite (not has_id) 0 (ite (not known) (- 32601)
      (ite (not params) (- 32602) (ite overloaded (- 32001)
        (ite resource_missing (- 32002) (ite (not handler_ok) (- 32603) 1)))))))))
(define-fun emits () Bool (not (= code 0)))
(define-fun result_is_error () Bool (and complete_or_refused domain_refused))
|}

let extended_classes = ["parse_error", -32700; "invalid_request", -32600;
  "notification", 0; "method_error", -32601; "params_error", -32602;
  "capacity_error", -32001; "resource_error", -32002;
  "internal_error", -32603; "complete_or_refused", 1]

let extended_queries () =
  let controls = List.map (fun (name, code) ->
    sat ("control5_" ^ name ^ "_sat") "QF_LIA"
      (extended_taxonomy ^ "(assert " ^ name ^ ")\n(assert (= code " ^ int_smt code ^ "))")) extended_classes in
  let rec pairs = function [] -> [] | (x,_)::xs ->
    List.map (fun (y,_) -> "(and " ^ x ^ " " ^ y ^ ")") xs @ pairs xs in
  let control = "control5_complete_or_refused_sat" in
  controls @ [
    proof "proof5_full_taxonomy_no_gap_unsat" control "QF_LIA"
      (extended_taxonomy ^ "(assert (not (or " ^ String.concat " " (List.map fst extended_classes) ^ ")))");
    proof "proof5_full_taxonomy_no_overlap_unsat" control "QF_LIA"
      (extended_taxonomy ^ "(assert (or " ^ String.concat " " (pairs extended_classes) ^ "))");
    proof "proof5_full_code_correspondence_unsat" control "QF_LIA"
      (extended_taxonomy ^ "(assert (not (and " ^ String.concat " "
        (List.map (fun (name,code) -> "(= " ^ name ^ " (= code " ^ int_smt code ^ "))") extended_classes) ^ ")))");
    proof "proof5_notification_never_emits_unsat" "control5_notification_sat" "QF_LIA"
      (extended_taxonomy ^ "(assert notification) (assert emits)");
    sat "control5_tool_refusal_is_rpc_result_sat" "QF_LIA"
      (extended_taxonomy ^ "(assert complete_or_refused) (assert domain_refused) (assert result_is_error) (assert (= code 1))");
    proof "proof5_tool_refusal_not_protocol_error_unsat" "control5_tool_refusal_is_rpc_result_sat" "QF_LIA"
      (extended_taxonomy ^ "(assert complete_or_refused) (assert domain_refused) (assert (< code 0))")
  ]

let queries () = core_queries () @ extended_queries () @ [
  sat "control6_notification_invalid_version_sat" "QF_LIA"
    (taxonomy_base ^ "(assert parse_ok) (assert notification_shape) (assert (not version_ok)) (assert (= wire_code 0))");
  proof "proof6_notification_even_validation_failure_no_emission_unsat" "control6_notification_invalid_version_sat" "QF_LIA"
    (taxonomy_base ^ "(assert parse_ok) (assert notification_shape) (assert emits_bytes)")
]

(* Independent finite OCaml checks expose mistakes in the model encodings.
   These are cross-checks, not replacements for the unbounded Lean theorems. *)
let independent_oracles () =
  require (parse_verdict "sat\n" = Some "sat" && parse_verdict "unsat\n" = Some "unsat")
    "verdict parser rejects normal verdicts";
  List.iter (fun s -> require (parse_verdict s = None) "verdict parser failed open")
    [""; "unknown"; "timeout"; "sat\n(error bad)"; "unsat\nsat"; "warning\nsat"];
  let rec first k = function [] -> None | (key,value)::xs -> if key=k then Some value else first k xs in
  let last k xs = List.fold_left (fun acc (key,value) -> if key=k then Some value else acc) None xs in
  let unique xs =
    let keys = List.map fst xs in List.length (List.sort_uniq compare keys) = List.length keys in
  let witness = [7,10; 9,20; 7,30] in
  require (first 7 witness = Some 10 && last 7 witness = Some 30) "duplicate witness mismatch";
  let alphabet = List.concat_map (fun k -> List.map (fun v -> k,v) [0;1]) [0;1;2;3] in
  let rec objects n = if n=0 then [[]] else
    List.concat_map (fun tail -> List.map (fun pair -> pair::tail) alphabet) (objects (n-1)) in
  let lookup_checks = ref 0 in
  List.iter (fun n -> List.iter (fun obj ->
    for target=0 to 4 do
      incr lookup_checks;
      require (not (unique obj) || first target obj = last target obj)
        "independent lookup conservation failed"
    done) (objects n)) [3;4];
  for d=0 to 64 do
    let push = if d < 32 then Some (d+1) else None in
    require (match push with None -> true | Some next -> next<=32) "depth oracle failed"
  done;
  let scalar_checks = ref 0 in
  for u=0 to 0x110100 do
    let guard = (u>=1 && u<=0xD7FF) || (u>=0xE000 && u<=0x10FFFF) in
    let excluded = u=0 || (0xD800<=u && u<=0xDFFF) || u>0x10FFFF in
    require (guard <> excluded) "scalar interval oracle failed";
    incr scalar_checks
  done;
  let outcomes_seen = Hashtbl.create 7 in
  for bits=0 to 511 do
    let bit i = bits land (1 lsl i) <> 0 in
    let p=bit 0 and shape=bit 1 and version=bit 2 and meth=bit 3 and id=bit 4
    and id_ok=bit 5 and known=bit 6 and params=bit 7 and handler=bit 8 in
    let valid = shape && version && meth && ((not id) || id_ok) in
    let notification = shape && meth && not id in
    let code = if not p then -32700 else if notification then 0 else if not valid then -32600 else
      if not known then -32601 else
      if not params then -32602 else if not handler then -32603 else 1 in
    let guards = [not p; p && not notification && not valid; p && notification;
      p && valid && id && not known; p && valid && id && known && not params;
      p && valid && id && known && params && not handler;
      p && valid && id && known && params && handler] in
    require (List.length (List.filter Fun.id guards)=1) "taxonomy total/disjoint oracle failed";
    List.iter2 (fun guard (_,expected_code) ->
      require (guard = (code=expected_code)) "taxonomy code oracle failed") guards classes;
    require (not (p && notification) || code=0) "notification silence oracle failed";
    Hashtbl.replace outcomes_seen code ()
  done;
  require (Hashtbl.length outcomes_seen=7) "unreachable taxonomy outcome";
  json_obj ["status", json_string "pass"; "lookup_cases", string_of_int !lookup_checks;
    "depth_cases", "65"; "scalar_cases", string_of_int !scalar_checks;
    "taxonomy_boolean_states", "512"; "reachable_outcomes", "7";
    "strict_verdict_parser_negative_cases", "6"]

let extended_independent_oracle () =
  let seen = Hashtbl.create 16 in
  for mask = 0 to 511 do
    let b i = mask land (1 lsl i) <> 0 in
    let p=b 0 and e=b 1 and h=b 2 and k=b 3 and v=b 4
    and o=b 5 and r=b 6 and good=b 7 and refused=b 8 in
    let routed=p && e && h in
    let guards=[not p; p && not e; p && e && not h;
      routed && not k; routed && k && not v; routed && k && v && o;
      routed && k && v && not o && r;
      routed && k && v && not o && not r && not good;
      routed && k && v && not o && not r && good] in
    require (List.length (List.filter Fun.id guards)=1) "extended taxonomy gap/overlap";
    let code=if not p then -32700 else if not e then -32600
      else if not h then 0 else if not k then -32601 else if not v then -32602
      else if o then -32001 else if r then -32002 else if not good then -32603 else 1 in
    List.iter2 (fun guard (_,expected) -> require (guard=(code=expected))
      "extended taxonomy code differs from independent decision tree") guards extended_classes;
    if p && e && not h then require (code=0) "notification emitted in independent oracle";
    if routed && k && v && not o && not r && good && refused
      then require (code=1) "tool refusal forged protocol error";
    Hashtbl.replace seen code ()
  done;
  require (Hashtbl.length seen=9) "extended class unreachable";
  json_obj ["status",json_string "pass";"boolean_states","512";"reachable_outcomes","9"]

let forbidden_lean_tokens contents =
  let is_word = function 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '\'' -> true | _ -> false in
  String.map (fun c -> if is_word c then c else ' ') contents
  |> String.split_on_char ' '
  |> List.filter (fun s -> List.mem s ["sorry"; "admit"; "axiom"])

let main () =
  let started = Unix.gettimeofday () in
  let root, root_resolution = resolve_root () in
  let workdir = match Sys.getenv_opt "MCP_JSON_FORMAL_WORKDIR" with
    | Some p when p<>"" -> Unix.realpath (absolute p) | _ -> Sys.getcwd () in
  Unix.putenv "TMPDIR" workdir;
  let receipt_path = join workdir "verification_receipt.json" in
  let receipt_tmp = join workdir "verification_receipt.json.partial" in
  let ocaml = join root "toolchains/opam-ocaml/bin/ocaml" in
  let guardian = join root "tools/ecology_process.ml" in
  require (executable ocaml && exists guardian) "bounded process guardian unavailable";
  let z3, z3_fallback = resolve_z3 root in
  let receipts = ref [] and failures = ref [] in
  let passed_checks = ref 0 in
  let successful_controls = Hashtbl.create 32 in
  let extended_oracle_receipt = try
    let receipt = extended_independent_oracle () in incr passed_checks; receipt
  with exn ->
    failures := ("extended oracle: " ^ Printexc.to_string exn)::!failures;
    json_obj ["status",json_string "fail";"error",json_string (Printexc.to_string exn)] in
  let oracle_receipt = try
    let receipt = independent_oracles () in incr passed_checks; receipt
  with exn ->
    failures := ("independent oracle: " ^ Printexc.to_string exn)::!failures;
    json_obj ["status", json_string "fail"; "error", json_string (Printexc.to_string exn)] in
  List.iter (fun query ->
    let path, oc = Filename.open_temp_file ~temp_dir:workdir "mcp-json-formal-" ".smt2" in
    close_out oc;
    let outcome =
      try
        write_file path query.script;
        let result = guarded ocaml guardian z3 ["-smt2"; "-T:3"; "-memory:256"; path] in
        let actual = parse_verdict result.output in
        let paired = match query.control with
          | None -> true | Some id -> Hashtbl.mem successful_controls id in
        let passed = result.status=0 && actual=Some query.expected && paired in
        if passed then incr passed_checks;
        if passed && query.expected="sat" then Hashtbl.replace successful_controls query.name ();
        if not passed then failures := (query.name ^ ": verdict/process/control failure") :: !failures;
        Printf.printf "%s %s expected=%s actual=%s exit=%d\n%!"
          (if passed then "[PASS]" else "[FAIL]") query.name query.expected
          (Option.value actual ~default:"invalid-output") result.status;
        ["pass", jbool passed; "actual", (match actual with None -> "null" | Some s -> json_string s);
         "paired_control_passed", jbool paired; "process", process_json result]
      with exn ->
        failures := (query.name ^ ": " ^ Printexc.to_string exn) :: !failures;
        ["pass", "false"; "exception", json_string (Printexc.to_string exn)] in
    let cleanup_error = try Sys.remove path; None with exn -> Some (Printexc.to_string exn) in
    let cleaned = not (exists path) && cleanup_error=None in
    if not cleaned then failures := (query.name ^ ": temp-file cleanup failed") :: !failures;
    receipts := json_obj (["name", json_string query.name; "expected", json_string query.expected;
      "sat_control", (match query.control with None -> "null" | Some id -> json_string id);
      "logic", json_string "QF_LIA"; "normalized_smt2", json_string query.script;
      "temporary_file", json_string path; "temporary_file_removed", jbool cleaned] @ outcome) :: !receipts
  ) (queries ());
  let local_lean = join workdir "McpJsonProcessingFormal.lean" in
  let lean_path = if exists local_lean then local_lean else join root "formal/lean/McpJsonProcessingFormal.lean" in
  let lean_receipt = if exists lean_path then (
    let tokens = forbidden_lean_tokens (read_file lean_path) in
    let lean = join root "tools/lean" in
    let result = run_capture lean [lean_path] in
    let passed = result.status=0 && tokens=[] in
    if passed then incr passed_checks
    else failures := "Lean compilation or forbidden-token scan failed" :: !failures;
    Printf.printf "%s Lean exit=%d forbidden_tokens=%d\n%!"
      (if passed then "[PASS]" else "[FAIL]") result.status (List.length tokens);
    json_obj ["status", json_string (if passed then "pass" else "fail");
      "source", json_string lean_path; "source_digest_algorithm", json_string "MD5 (byte identity only)";
      "source_digest", json_string (Digest.to_hex (Digest.file lean_path));
      "forbidden_tokens", json_list json_string tokens; "process", process_json result]
  ) else json_obj ["status", json_string "not requested (companion Lean source absent from workdir)"] in
  let failures_list = List.rev !failures in
  let qs = queries () in
  let receipt = json_obj [
    "schema", json_string "uos.mcp-json-formal.verification.v1";
    "status", json_string (if failures_list=[] then "pass" else "fail");
    "admitted_ev_ceiling", "93"; "system_admission", "false";
    "scope", json_string "Source-bound abstract models; no runtime-parser refinement or cryptographic admission";
    "notification_domain", json_string "Notification shape requires parsed object, string method and absent id; validation failures stay silent; objects without a method can emit -32600";
    "canonical_scope", json_string "Finite-key lookup equivalence, not a hash/serialization proof";
    "uos_root", json_string root; "root_resolution", json_string root_resolution;
    "workdir", json_string workdir; "solver", json_string z3; "solver_path_fallback", jbool z3_fallback;
    "bounds", json_obj ["wall_timeout_ms", "5000"; "output_limit_bytes", "65536";
      "z3_timeout_seconds", "3"; "z3_memory_mb", "256";
      "process_group_reaping", "true"; "guardian", json_string guardian];
    "query_count", string_of_int (List.length qs);
    "sat_controls", string_of_int (List.length (List.filter (fun q -> q.expected="sat") qs));
    "unsat_proofs", string_of_int (List.length (List.filter (fun q -> q.expected="unsat") qs));
    "independent_finite_oracles", oracle_receipt; "extended_taxonomy_oracle", extended_oracle_receipt; "lean", lean_receipt;
    "queries", "[" ^ String.concat "," (List.rev !receipts) ^ "]";
    "failures", json_list json_string failures_list;
    "elapsed_seconds", Printf.sprintf "%.6f" (Unix.gettimeofday () -. started)] in
  write_file receipt_tmp (receipt ^ "\n");
  Unix.rename receipt_tmp receipt_path;
  Printf.printf "Receipt: %s\nQueries: %d; SAT controls: %d; UNSAT proofs: %d; failures: %d\n%!"
    receipt_path (List.length qs) (Hashtbl.length successful_controls)
    (List.length (List.filter (fun q -> q.expected="unsat") qs)) (List.length failures_list);
  let observation = Suite_telemetry.observe ~suite:"test_mcp_json_formal_z3"
    ~passed:!passed_checks ~failed:(List.length failures_list) ~skipped:0 in
  print_string (Suite_telemetry.emit observation ~targets:[]);
  exit (Suite_telemetry.exit_code observation)

let () =
  try main () with exn ->
    let message = Printexc.to_string exn in
    Printf.eprintf "[FAIL CLOSED] %s\n%!" message;
    (* An early preflight error must also replace any stale green receipt. *)
    (try
       let workdir = match Sys.getenv_opt "MCP_JSON_FORMAL_WORKDIR" with
         | Some p when p<>"" -> absolute p | _ -> Sys.getcwd () in
       let path = join workdir "verification_receipt.json" in
       let tmp = path ^ ".partial" in
       write_file tmp (json_obj [
         "schema", json_string "uos.mcp-json-formal.verification.v1";
         "status", json_string "fail"; "system_admission", "false";
         "admitted_ev_ceiling", "93"; "failures", json_list json_string [message]] ^ "\n");
       Unix.rename tmp path
     with _ -> ());
    let observation = Suite_telemetry.observe ~suite:"test_mcp_json_formal_z3"
      ~passed:0 ~failed:1 ~skipped:0 in
    print_string (Suite_telemetry.emit observation ~targets:[]);
    exit (Suite_telemetry.exit_code observation)
