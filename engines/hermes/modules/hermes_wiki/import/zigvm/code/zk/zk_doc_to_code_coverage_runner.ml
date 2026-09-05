(* ZK Doc-to-Code Coverage Runner — a REAL, honest documentation-coverage meter.

   INTENT (from the phase-7 stub).  "Checks what percentage of Zig `pub`
   functions are directly mentioned in the ZK."

   WHAT THIS HONESTLY DOES.  It scans every [root]/src/*.zig file for
   `pub fn <name>` declarations, builds the set of exported function names, loads
   the full ZK corpus text ([root]/docs/zk/**/*.md), and counts how many exported
   names appear verbatim in that text. It reports the coverage percentage and
   lists a sample of undocumented exports.

   [NOTE] text-heuristic, not a real Zig AST: `pub fn` is matched lexically
   (whole-line prefix after trimming), and "mentioned" is a verbatim substring
   test on the doc corpus — a name that is a common English word could match
   spuriously, and a paraphrase would be missed. The number is a documentation-
   pressure signal, not a semantic cross-reference. *)

let read_file path =
  try In_channel.with_open_bin path In_channel.input_all with _ -> ""

let list_ext dir_abs ext =
  match Sys.readdir dir_abs with
  | entries ->
      Array.to_list entries
      |> List.filter (fun e -> Filename.check_suffix e ext)
      |> List.map (Filename.concat dir_abs)
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
  || c = '_'

(* Extract identifier following a `pub fn ` prefix on a trimmed line. *)
let pub_fn_name line =
  let t = String.trim line in
  let pfx = "pub fn " in
  let pl = String.length pfx in
  if String.length t > pl && String.sub t 0 pl = pfx then begin
    let i = ref pl in
    let n = String.length t in
    while !i < n && is_ident_char t.[!i] do incr i done;
    let name = String.sub t pl (!i - pl) in
    if String.length name > 0 then Some name else None
  end
  else None

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
    "[zk_doc_to_code_coverage_runner] measuring `pub fn` coverage in the ZK corpus\n";
  let src = Filename.concat root "src" in
  let names = Hashtbl.create 512 in
  List.iter
    (fun f ->
      String.split_on_char '\n' (read_file f)
      |> List.iter (fun l ->
             match pub_fn_name l with
             | Some n -> Hashtbl.replace names n ()
             | None -> ()))
    (list_ext src ".zig");
  let corpus = corpus_text root in
  let total = Hashtbl.length names in
  let documented = ref 0 in
  let undoc = ref [] in
  Hashtbl.iter
    (fun n () ->
      if contains corpus n then incr documented
      else undoc := n :: !undoc)
    names;
  let pct = if total = 0 then 0.0 else 100.0 *. float_of_int !documented /. float_of_int total in
  Printf.printf "  exported `pub fn` names: %d\n" total;
  Printf.printf "  mentioned in ZK: %d   coverage: %.2f%%\n" !documented pct;
  let sample = List.sort compare !undoc in
  let shown = List.filteri (fun i _ -> i < 25) sample in
  Printf.printf "  undocumented (%d total, first %d): %s\n"
    (List.length sample) (List.length shown) (String.concat ", " shown);
  Printf.printf
    "  [NOTE] text-heuristic, not a real Zig AST: verbatim substring match, no paraphrase/alias resolution\n"
