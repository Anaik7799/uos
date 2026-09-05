(* ZK Comptime Logic Documenter — a REAL, honest comptime-density audit.

   INTENT (from the phase-7 stub).  "Forces comptime-heavy Zig files to have a
   corresponding ZK explanation note."

   WHAT THIS HONESTLY DOES.  It counts `comptime` token occurrences in every
   [root]/src/*.zig file, ranks them, and for each file whose density crosses a
   threshold it checks whether the module's base name (e.g. `map_algebra`) is
   mentioned anywhere in the ZK corpus ([root]/docs/zk/**/*.md). It reports the
   comptime-heavy files that lack any ZK explanation note.

   [NOTE] text-heuristic, not a real Zig AST: `comptime` is counted lexically
   (it will include occurrences inside comments/strings), and "documented" means
   the module base name appears verbatim in the ZK text — a real explanation is
   not verified, only a name reference. This is a documentation-pressure signal. *)

let comptime_threshold = 8

let read_file path =
  try In_channel.with_open_bin path In_channel.input_all with _ -> ""

let list_zig src =
  match Sys.readdir src with
  | entries ->
      Array.to_list entries
      |> List.filter (fun e -> Filename.check_suffix e ".zig")
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

(* count non-overlapping occurrences of needle in hay *)
let count_occ hay needle =
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 then 0
  else
    let c = ref 0 and i = ref 0 in
    while !i <= hl - nl do
      let rec at j = if j = nl then true else if hay.[!i + j] = needle.[j] then at (j + 1) else false in
      if at 0 then (incr c; i := !i + nl) else incr i
    done;
    !c

let run (root : string) : unit =
  Printf.printf
    "[zk_comptime_logic_documenter] auditing comptime-heavy Zig files (threshold=%d) for ZK notes\n"
    comptime_threshold;
  let src = Filename.concat root "src" in
  let corpus = corpus_text root in
  let rows =
    list_zig src
    |> List.map (fun f ->
           let n = count_occ (read_file (Filename.concat src f)) "comptime" in
           (f, n))
    |> List.filter (fun (_, n) -> n >= comptime_threshold)
    |> List.sort (fun (_, a) (_, b) -> compare b a)
  in
  let undoc = ref 0 in
  Printf.printf "  comptime-heavy files: %d\n" (List.length rows);
  List.iter
    (fun (f, n) ->
      let modname = Filename.chop_suffix f ".zig" in
      let documented = contains corpus modname in
      if not documented then incr undoc;
      Printf.printf "  %-9s %-28s comptime=%-4d %s\n"
        (if documented then "[doc]" else "[UNDOC]")
        f n
        (if documented then "" else "(no ZK note mentions module)"))
    rows;
  Printf.printf "  comptime-heavy files WITHOUT a ZK note: %d\n" !undoc;
  Printf.printf
    "  [NOTE] text-heuristic, not a real Zig AST: lexical `comptime` count (incl. comments/strings); name-reference only\n"
