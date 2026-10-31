#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "str";;

(* Adapted by LOCAL CODEX relay from UOS's corrected independent_oracle.ml,
   SHA256 bd76dee8d39af1b155cde62585a55c0b22727c9fe31f09fe26715e45fbcb2920.
   Fixed-fixture corrections and the original procedural oracle are preserved;
   the bounded regular-file boundary and repeatable controls are local additions.
   @agent_intent: Read-only, independent procedural evaluation of retained SMT
   model values and the complete 16-bit receipt-prefix presence space.
   @laws: No source/task/runtime mutation; fail closed on malformed input,
   unexpected verdicts or any finite counterexample. Report-only evidence, not
   native refinement, signature verification or sovereign admission. *)

type value = Boolean of bool | Integer of int

let require condition message = if not condition then failwith message

let before marker text =
  let at = Str.search_forward (Str.regexp_string marker) text 0 in
  String.sub text 0 at

let after marker text =
  let at = Str.search_forward (Str.regexp_string marker) text 0 in
  let start = at + String.length marker in
  String.sub text start (String.length text - start)

let parse text =
  let pattern = Str.regexp {|(\([A-Za-z0-9]+\) \(true\|false\|-[0-9]+\|[0-9]+\))|} in
  let rec scan start values =
    match Str.search_forward pattern text start with
    | _ ->
        let key = Str.matched_group 1 text in
        let raw = Str.matched_group 2 text in
        let next = Str.match_end () in
        let value = match raw with
          | "true" -> Boolean true | "false" -> Boolean false
          | number -> Integer (int_of_string number)
        in
        require (not (List.mem_assoc key values)) ("duplicate model field: " ^ key);
        scan next ((key, value) :: values)
    | exception Not_found -> values
  in
  scan 0 []

let number values name = match List.assoc_opt name values with
  | Some (Integer n) -> n | _ -> failwith ("missing/integer field: " ^ name)

let boolean values name = match List.assoc_opt name values with
  | Some (Boolean b) -> b | _ -> failwith ("missing/boolean field: " ^ name)

(* The SAT control is a FIXED fixture, not merely an arbitrary point satisfying
   the generic eligibility guard. Check its complete returned assignment before
   interpreting the guard, so coherent substitutions cannot masquerade as the
   solver's stated witness. Unreturned variables of the endpoint projection are
   not claimed to have been evaluated. *)
let positive_fixture =
  List.map (fun (k,v) -> k,Integer v)
    ["target",95; "lower",94; "candidate",101; "source",202;
     "runtimeCandidate",101; "formalCandidate",101;
     "runtimeSource",202; "formalSource",202;
     "runtimeSigner",1; "formalSigner",2;
     "utcRaw",5; "monoRaw",7; "observed",5; "now",5; "expires",10;
     "codexCandidate",101; "agyCandidate",101;
     "codexSource",202; "agySource",202;
     "codexTarget",95; "agyTarget",95; "codexSigner",10; "agySigner",11] @
  List.map (fun k -> k,Boolean true)
    ["runtimePresent"; "formalPresent"; "runtimeSigned"; "formalSigned";
     "runtimeOrigin"; "formalOrigin"; "runtimeConfirmed"; "formalConfirmed";
     "rebindInformation"; "codexRecorded"; "agyRecorded"; "codexSigned";
     "agySigned"; "codexOrigin"; "agyOrigin"; "jointFresh";
     "r94"; "r95"; "eligible"] @ ["r96",Boolean false]

let endpoint_fixture = ["target",Integer 95; "r94",Boolean false; "r95",Boolean true]

let exact_fixture label expected actual =
  let keys = List.map fst in
  require (List.sort String.compare (keys expected) = List.sort String.compare (keys actual))
    (label ^ ": unexpected/missing model fields");
  List.iter (fun (key,value) ->
    require (List.assoc_opt key actual = Some value) (label ^ ": fixed assertion mismatch: " ^ key)) expected

let check log =
  let m = parse (before "missing_intermediate_refutation" log) in
  exact_fixture "positive_target95" positive_fixture m;
  let n = number m and b = boolean m in
  require (n "target" = 95 && n "lower" = 94) "unexpected control target/range";
  let flags = ["runtimePresent"; "formalPresent"; "runtimeSigned"; "formalSigned";
    "runtimeOrigin"; "formalOrigin"; "runtimeConfirmed"; "formalConfirmed";
    "codexRecorded"; "agyRecorded"; "codexSigned"; "agySigned"; "codexOrigin";
    "agyOrigin"; "jointFresh"; "rebindInformation"] in
  let keys = List.for_all b flags &&
    n "runtimeCandidate" = n "candidate" && n "formalCandidate" = n "candidate" &&
    n "runtimeSource" = n "source" && n "formalSource" = n "source" &&
    n "runtimeSigner" > 0 && n "formalSigner" > 0 && n "runtimeSigner" <> n "formalSigner" in
  let clock = List.for_all (fun key -> n key >= 0)
      ["utcRaw"; "monoRaw"; "observed"; "now"; "expires"] &&
    n "utcRaw" <> n "monoRaw" && n "utcRaw" = n "observed" &&
    n "observed" <= n "now" && n "now" < n "expires" in
  let joint = n "codexCandidate" = n "candidate" && n "agyCandidate" = n "candidate" &&
    n "codexSource" = n "source" && n "agySource" = n "source" &&
    n "codexTarget" = n "target" && n "agyTarget" = n "target" &&
    n "codexSigner" > 0 && n "agySigner" > 0 && n "codexSigner" <> n "agySigner" in
  let coverage = List.init (n "target" - 93) (fun i -> b ("r" ^ string_of_int (94 + i)))
    |> List.for_all Fun.id in
  require (n "target" = 95 && n "lower" = 94 && keys && clock && joint && coverage && b "eligible")
    "concrete SAT model failed independent arithmetic/boolean evaluation";
  let lines = String.split_on_char '\n' log |> List.map String.trim in
  let statuses = lines
    |> List.filter (fun line -> line = "sat" || line = "unsat") in
  require (statuses = ["sat"; "unsat"; "unsat"; "unsat"; "unsat"; "unsat"; "unsat"; "unsat"; "sat"])
    "unexpected solver status sequence";
  require (not (List.exists (fun line -> line="unknown" || String.starts_with ~prefix:"(error" line)
    lines)) "unexpected unknown/error solver record";
  let pairs = ref 0 and counterexamples = ref 0 in
  for mask = 0 to 65535 do
    let covered = Array.make 16 false in
    let prefix = ref true in
    for i = 0 to 15 do
      prefix := !prefix && (mask land (1 lsl i)) <> 0;
      covered.(i) <- !prefix
    done;
    for q = 0 to 15 do
      for p = 0 to q do
        incr pairs;
        if covered.(q) && not covered.(p) then incr counterexamples
      done
    done
  done;
  require (!counterexamples = 0) "prefix monotonicity has a concrete counterexample";
  let bad = parse (after "bad_endpoint_only_mutant_witness" log) in
  exact_fixture "bad_endpoint_only_mutant_witness" endpoint_fixture bad;
  require (number bad "target" = 95 && boolean bad "r95" && not (boolean bad "r94"))
    "endpoint-only mutant model not reproduced";
  Printf.printf
    {|{"scope":"QF_LIA/Bool projection only","runtime":"OCaml %s","concrete_sat_model_reevaluated":true,"positive_fixed_fields":%d,"endpoint_fixed_fields":%d,"receipt_patterns":65536,"prefix_pairs":%d,"prefix_monotonicity_counterexamples":%d,"endpoint_only_mutant_reproduced":true,"native_refinement":"UNPROVED","signature_truth":"EXTERNAL_PREMISE"}%!|}
    Sys.ocaml_version (List.length positive_fixture) (List.length endpoint_fixture) !pairs !counterexamples;
  print_newline ()

let max_log_bytes = 262144

type opened_log = {path:string; fd:Unix.file_descr; initial:Unix.stats}

let same_identity a b =
  a.Unix.st_dev=b.Unix.st_dev && a.Unix.st_ino=b.Unix.st_ino

let same_snapshot a b =
  same_identity a b && b.Unix.st_kind=Unix.S_REG &&
  a.Unix.st_size=b.Unix.st_size && a.Unix.st_mtime=b.Unix.st_mtime &&
  a.Unix.st_ctime=b.Unix.st_ctime

(* Check every explicitly traversed component, including one preceding '..'.
   Do not realpath a symlink into apparent acceptability. The fd/path identity
   checks below also catch replacement between this inspection and open. *)
let inspect_path path =
  require (String.length path>0 && String.length path<=4096 &&
    not(String.contains path '\000')) "invalid log path";
  let parts=String.split_on_char '/' path |> List.filter(fun p->p<>"") in
  let rec walk prefix = function
    | [] -> Unix.lstat prefix
    | part::rest ->
        let next=Filename.concat prefix part in
        let stat=Unix.lstat next in
        require(stat.Unix.st_kind<>Unix.S_LNK) "symlink log path refused";
        if rest<>[] then require(stat.Unix.st_kind=Unix.S_DIR) "non-directory log parent";
        match rest with []->stat|_->walk next rest
  in
  walk (if Filename.is_relative path then Sys.getcwd() else "/") parts

let open_log path =
  let before=inspect_path path in
  require(before.Unix.st_kind=Unix.S_REG) "nonregular log refused";
  require(before.Unix.st_size>=0 && before.Unix.st_size<=max_log_bytes)
    "log exceeds 262144-byte evidence bound";
  (* O_NONBLOCK prevents a raced FIFO from waiting for a writer. No payload is
     read until both fd kind/identity and the re-inspected path match. *)
  let fd=Unix.openfile path [Unix.O_RDONLY;Unix.O_NONBLOCK;Unix.O_CLOEXEC] 0 in
  try
    let actual=Unix.fstat fd in
    require(same_snapshot before actual) "log changed during open";
    require(same_snapshot before (inspect_path path)) "log path changed during open";
    {path;fd;initial=before}
  with error->Unix.close fd;raise error

let unchanged opened =
  require(same_snapshot opened.initial (Unix.fstat opened.fd)) "log changed during read";
  require(same_snapshot opened.initial (inspect_path opened.path)) "log path changed during read"

let read_opened opened =
  unchanged opened;
  let chunk=Bytes.create 4096 and contents=Buffer.create opened.initial.Unix.st_size in
  let rec read total =
    unchanged opened;
    let capacity=min (Bytes.length chunk) (max_log_bytes+1-total) in
    require(capacity>0) "log exceeds 262144-byte EOF bound";
    let amount=Unix.read opened.fd chunk 0 capacity in
    if amount=0 then (
      require(total=opened.initial.Unix.st_size) "log length changed before EOF";
      unchanged opened;
      Buffer.contents contents)
    else (
      require(total+amount<=max_log_bytes && total+amount<=opened.initial.Unix.st_size)
        "log grew beyond captured size";
      Buffer.add_subbytes contents chunk 0 amount;
      read(total+amount))
  in
  read 0

let read_regular path =
  let opened=open_log path in
  Fun.protect ~finally:(fun()->Unix.close opened.fd)(fun()->read_opened opened)

let run () =
  require (Array.length Sys.argv = 2)
    "usage: provenance_adjudication_smt_oracle.ml <retained-z3-log>";
  check(read_regular Sys.argv.(1))

let main () =
  try run () with
  | Failure message | Sys_error message -> Printf.eprintf "HOLD: %s\n" message; exit 2
  | Not_found -> Printf.eprintf "HOLD: required evidence marker missing\n"; exit 2
  | Unix.Unix_error (error, fn, arg) ->
      Printf.eprintf "HOLD: %s(%s): %s\n" fn arg (Unix.error_message error); exit 2

(* Standard #use library loading for the OCaml controls; there is no CLI flag
   that skips validation. Normal noninteractive invocation always calls main.
   This is an observed-change detector, not an atomic filesystem snapshot or
   permission to read arbitrary corpora. External process timeout remains needed
   for an unresponsive filesystem; native read cannot be preempted in OCaml. *)
let () = if not !Sys.interactive then main ()
