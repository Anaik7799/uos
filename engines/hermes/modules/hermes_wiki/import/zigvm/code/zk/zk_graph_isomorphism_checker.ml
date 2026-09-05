(* ZK Graph Isomorphism Checker — a REAL two-representation graph diff.

   Promoted from a phase-7 printf stub. Intent: verify that the in-memory ZK
   graph (parsed from markdown) matches the SQLite persistent representation.

   WHAT IT REALLY DOES.  It builds two labelled directed graphs under [root]:
     - IN-MEMORY: parse every docs/zk/**/*.md, slug = filename without ".md",
       and for each [[target|...]] / [[target]] wikilink emit an edge
       slug -> target-slug.
     - PERSISTENT: the live edges in the `zk_edge_history` table (rows whose
       `removed_commit` is NULL/empty are the present graph).
   It then compares NODE sets and EDGE sets and reports the exact overlap:
   |V| and |E| on each side, the intersection, and the edges present in only
   one representation.

   Since both graphs carry canonical node LABELS (slugs), "isomorphic" here is
   label-equality of the two edge sets — an exact set comparison, which is
   decidable and computed directly (no NP graph-iso search needed).

   HONESTY.  "match" (labelled-isomorphic) is printed ONLY when both symmetric
   differences are empty. Otherwise the divergence counts are reported as-is.
   The two sides use DIFFERENT slug conventions (the persistent side normalises
   path separators to `--`, MoCs use synthetic ids like `doc-map`), so a large
   diff is expected and is reported honestly rather than papered over.

   [LIMITATION] Slug derivation for the markdown side is the bare filename;
   it does not replicate the harness's exact slug-normalisation, so this
   measures representational OVERLAP, not a certified round-trip. *)

let rec walk dir f =
  Array.iter
    (fun e ->
      let p = Filename.concat dir e in
      match (try Some (Sys.is_directory p) with _ -> None) with
      | Some true -> walk p f
      | Some false -> f p
      | None -> ())
    (try Sys.readdir dir with _ -> [||])

let read_file p =
  try
    let ic = open_in_bin p in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic;
    Some s
  with _ -> None

(* Parse [[target|label]] / [[target]] -> target slugs. *)
let wikilink_targets text =
  let hl = String.length text in
  let out = ref [] and i = ref 0 in
  while !i < hl - 1 do
    if text.[!i] = '[' && text.[!i + 1] = '[' then begin
      let j = ref (!i + 2) in
      let b = Buffer.create 32 in
      while !j < hl - 1 && not (text.[!j] = ']' && text.[!j + 1] = ']') do
        Buffer.add_char b text.[!j];
        incr j
      done;
      let inner = Buffer.contents b in
      let target =
        match String.index_opt inner '|' with
        | Some k -> String.sub inner 0 k
        | None -> inner
      in
      let t = String.trim target in
      (* drop transclusion embeds and section anchors for the node id *)
      let t = match String.index_opt t '#' with Some k -> String.sub t 0 k | None -> t in
      if String.length t > 0 && not (String.contains t ' ') then out := t :: !out;
      i := !j + 2
    end
    else incr i
  done;
  !out

module PS = Set.Make (struct type t = string * string let compare = compare end)
module SS = Set.Make (String)

let run (root : string) : unit =
  Printf.printf
    "[zk_graph_isomorphism_checker] diffing markdown-graph vs SQLite zk_edge_history...\n";
  (* in-memory side *)
  let mem = ref PS.empty and md_files = ref 0 in
  walk (Filename.concat root "docs/zk") (fun p ->
      if Filename.check_suffix p ".md" then
        match read_file p with
        | Some t ->
            incr md_files;
            let src = Filename.remove_extension (Filename.basename p) in
            List.iter (fun dst -> mem := PS.add (src, dst) !mem) (wikilink_targets t)
        | None -> ());
  (* persistent side *)
  let per = ref PS.empty in
  let db_path = Filename.concat root "harness/state/zigvm_harness.sqlite3" in
  if Sys.file_exists db_path then
    (match (try `Db (Sqlite3.db_open ~mode:`READONLY db_path) with e -> `Err e) with
     | `Err _ -> ()
     | `Db db ->
         Fun.protect
           ~finally:(fun () -> ignore (Sqlite3.db_close db))
           (fun () ->
             let cb (row : Sqlite3.row) _ =
               match (row.(0), row.(1)) with
               | Some s, Some d -> per := PS.add (s, d) !per
               | _ -> ()
             in
             ignore
               (Sqlite3.exec db ~cb
                  "SELECT src, dst FROM zk_edge_history WHERE removed_commit IS \
                   NULL OR removed_commit='';")));
  let nodes ps = PS.fold (fun (a, b) acc -> SS.add a (SS.add b acc)) ps SS.empty in
  let vm = nodes !mem and vp = nodes !per in
  let e_common = PS.inter !mem !per in
  let only_mem = PS.diff !mem !per and only_per = PS.diff !per !mem in
  let n_common = SS.inter vm vp in
  Printf.printf "  markdown graph : |V|=%d |E|=%d  (from %d notes)\n"
    (SS.cardinal vm) (PS.cardinal !mem) !md_files;
  Printf.printf "  persistent graph: |V|=%d |E|=%d\n" (SS.cardinal vp) (PS.cardinal !per);
  Printf.printf
    "  shared nodes=%d ; shared edges=%d ; edges only-in-md=%d ; edges only-in-db=%d\n"
    (SS.cardinal n_common) (PS.cardinal e_common)
    (PS.cardinal only_mem) (PS.cardinal only_per);
  if PS.is_empty only_mem && PS.is_empty only_per && not (PS.is_empty !mem) then
    Printf.printf "  labelled-isomorphic: the two edge sets are EQUAL\n"
  else
    Printf.printf
      "  NOT labelled-isomorphic: %d edges diverge between representations\n"
      (PS.cardinal only_mem + PS.cardinal only_per);
  Printf.printf
    "  [LIMITATION] markdown slug = bare filename; the persistent side uses the \
     harness's `--` slug normalisation, so this reports OVERLAP, not a certified \
     round-trip\n"
