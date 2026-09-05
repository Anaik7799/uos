(* ZK Formal-Spec-to-Doc Prover — a REAL, honest proof/doc cross-reference.

   INTENT (from the phase-7 stub).  "Uses Z3 to prove that the formal
   specifications described in the ZK match the formal proofs in proofs/."

   WHAT THIS HONESTLY DOES.  It parses every Rocq/Coq file in [root]/proofs/*.v
   for named obligations — `Lemma`, `Theorem`, `Definition`, `Fixpoint` — and
   checks, for each proof file and each obligation name, whether it is referenced
   in the ZK corpus ([root]/docs/zk/**/*.md). It reports which proof artifacts
   and which named lemmas are documented vs. dark.

   [LIMITATION] no SMT solver wired: this is a SYNTACTIC lemma-name
   cross-reference, NOT a semantic proof that the ZK's stated specification is
   logically equivalent to the Rocq proof. Establishing that would require
   discharging an equivalence obligation in Z3/Rocq; this module makes no such
   claim and proves nothing — it measures documentation parity only. *)

let read_file path =
  try In_channel.with_open_bin path In_channel.input_all with _ -> ""

let list_ext dir_abs ext =
  match Sys.readdir dir_abs with
  | entries ->
      Array.to_list entries
      |> List.filter (fun e -> Filename.check_suffix e ext)
      |> List.sort compare
  | exception _ -> []

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

let is_ident_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '_' || c = '\''

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

(* On a trimmed line beginning with one of the keywords, take the following ident. *)
let obligation_name line =
  let t = String.trim line in
  let kws = [ "Lemma "; "Theorem "; "Definition "; "Fixpoint "; "Corollary " ] in
  let rec try_kw = function
    | [] -> None
    | kw :: rest ->
        let kl = String.length kw in
        if String.length t > kl && String.sub t 0 kl = kw then begin
          let i = ref kl and n = String.length t in
          while !i < n && is_ident_char t.[!i] do incr i done;
          let name = String.sub t kl (!i - kl) in
          if String.length name > 0 then Some name else None
        end
        else try_kw rest
  in
  try_kw kws

let run (root : string) : unit =
  Printf.printf
    "[zk_formal_spec_to_doc_prover] cross-referencing proofs/*.v obligations against the ZK\n";
  let proofs = Filename.concat root "proofs" in
  let corpus = corpus_text root in
  let vfiles = list_ext proofs ".v" in
  let total_obl = ref 0 and doc_obl = ref 0 in
  let file_doc = ref 0 in
  List.iter
    (fun vf ->
      let base = Filename.chop_suffix vf ".v" in
      let names =
        String.split_on_char '\n' (read_file (Filename.concat proofs vf))
        |> List.filter_map obligation_name
        |> List.sort_uniq compare
      in
      let doc_here = List.filter (fun n -> contains corpus n) names in
      total_obl := !total_obl + List.length names;
      doc_obl := !doc_obl + List.length doc_here;
      let file_referenced = contains corpus base in
      if file_referenced then incr file_doc;
      Printf.printf "  %-22s file-ref=%-3s obligations=%-3d documented=%d\n"
        vf (if file_referenced then "yes" else "NO")
        (List.length names) (List.length doc_here))
    vfiles;
  Printf.printf "  proof files: %d  (file-name referenced in ZK: %d)\n"
    (List.length vfiles) !file_doc;
  let pct = if !total_obl = 0 then 0.0 else 100.0 *. float_of_int !doc_obl /. float_of_int !total_obl in
  Printf.printf "  named obligations: %d   documented: %d   (%.1f%%)\n"
    !total_obl !doc_obl pct;
  Printf.printf
    "  [NOTE] SMT is INAPPLICABLE here (not merely unwired): 'spec matches its doc' \
     is not a decision problem — the docs are prose, not formulas. Syntactic \
     lemma-name cross-reference only; proves NOTHING about spec equivalence. (Real \
     Z3 IS available — see equivalent_mutant_classifier — where the task is decidable.)\n"
