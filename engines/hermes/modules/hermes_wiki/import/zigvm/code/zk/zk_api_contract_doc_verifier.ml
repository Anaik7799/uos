(* ZK API Contract Doc Verifier — a REAL, honest doc-vs-code contract check.

   INTENT (from the phase-7 stub).  "Verifies that API endpoints mentioned in ZK
   notes match actual code signatures."

   WHAT THIS HONESTLY DOES.  The harness's public API surface is its CLI: every
   `--kebab-flag` the harness accepts. This module extracts every `--flag` token
   mentioned in the ZK corpus ([root]/docs/zk/**/*.md), then verifies each one is
   actually implemented — i.e. appears as a literal in the OCaml harness sources
   ([root]/harness/*.ml). It reports documented-but-unimplemented flags (doc
   drift / phantom endpoints) and the match rate.

   [NOTE] text-heuristic, not a real AST: flags are lexically scraped from prose
   and verified by substring presence in harness source text (not by parsing the
   argument dispatcher). A flag mentioned in a narrative counter-example, or one
   built as a runtime-concatenated string, could be mis-classified. It is a
   doc-drift signal on the CLI contract, not a proof of the dispatch table. *)

let read_file path =
  try In_channel.with_open_bin path In_channel.input_all with _ -> ""

let corpus_text root =
  let base = Filename.concat (Filename.concat root "docs") "zk" in
  let buf = Buffer.create (1 lsl 16) in
  let rec go dir =
    match Sys.readdir dir with
    | entries ->
        Array.iter
          (fun e ->
            let p = Filename.concat dir e in
            if (try Sys.is_directory p with _ -> false) then go p
            else if Filename.check_suffix e ".md" then
              Buffer.add_string buf (read_file p))
          entries
    | exception _ -> ()
  in
  if (try Sys.is_directory base with _ -> false) then go base;
  Buffer.contents buf

let harness_text root =
  let dir = Filename.concat root "harness" in
  let buf = Buffer.create (1 lsl 18) in
  (match Sys.readdir dir with
   | entries ->
       Array.iter
         (fun e ->
           if Filename.check_suffix e ".ml" then
             Buffer.add_string buf (read_file (Filename.concat dir e)))
         entries
   | exception _ -> ());
  Buffer.contents buf

let is_flag_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '-'

(* Extract `--flag` tokens (>=2 trailing chars, must contain a letter). *)
let extract_flags text =
  let n = String.length text in
  let set = Hashtbl.create 128 in
  let i = ref 0 in
  while !i < n - 2 do
    if text.[!i] = '-' && text.[!i + 1] = '-' && is_flag_char text.[!i + 2]
       && (!i = 0 || not (is_flag_char text.[!i - 1]))
    then begin
      let j = ref (!i + 2) in
      while !j < n && is_flag_char text.[!j] do incr j done;
      let flag = String.sub text !i (!j - !i) in
      (* require at least one alphabetic char and length > 3 *)
      let has_alpha =
        String.exists (fun c -> (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) flag
      in
      if has_alpha && String.length flag > 3
         && flag.[String.length flag - 1] <> '-' then
        Hashtbl.replace set flag ();
      i := !j
    end
    else incr i
  done;
  Hashtbl.fold (fun k () acc -> k :: acc) set [] |> List.sort compare

let contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 || nl > hl then false
  else
    let rec at i j =
      if j = nl then true
      else if hay.[i + j] = needle.[j] then at i (j + 1) else false
    in
    let rec scan i = if i > hl - nl then false else if at i 0 then true else scan (i + 1) in
    scan 0

let run (root : string) : unit =
  Printf.printf
    "[zk_api_contract_doc_verifier] verifying documented CLI flags against harness/*.ml\n";
  let flags = extract_flags (corpus_text root) in
  let code = harness_text root in
  let matched = ref 0 in
  let phantom = ref [] in
  List.iter
    (fun fl ->
      if contains code fl then incr matched else phantom := fl :: !phantom)
    flags;
  let total = List.length flags in
  let rate = if total = 0 then 0.0 else 100.0 *. float_of_int !matched /. float_of_int total in
  Printf.printf "  distinct --flags mentioned in ZK: %d\n" total;
  Printf.printf "  implemented in harness source: %d   (%.1f%%)\n" !matched rate;
  Printf.printf "  documented-but-UNIMPLEMENTED (phantom endpoints): %d\n"
    (List.length !phantom);
  List.iter (fun f -> Printf.printf "    [phantom] %s\n" f) (List.rev !phantom);
  Printf.printf
    "  [NOTE] text-heuristic, not a real AST: flags scraped from prose, verified by substring in harness source\n"
