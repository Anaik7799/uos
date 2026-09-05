(* ZK Transclusion Depth Limiter — a REAL corpus scan + bounded-BFS depth guard.

   Promoted from a phase-7 printf stub. Obsidian-style transclusion embeds one
   note inside another with the `![[target]]` syntax. Unbounded transclusion can
   loop (A embeds B embeds A) or fan out into a lockup, so the guard imposes a
   hard hop limit (MAX_DEPTH).

   This module (1) SCANS the real corpus (docs/zk/**/*.md) for `![[ ]]`
   transclusion edges, (2) builds the transclusion graph, and (3) runs a bounded
   BFS from every node reporting any path that would exceed MAX_DEPTH or revisit
   a node (a cycle). The BFS is depth-capped, so it TERMINATES by construction —
   the very lockup-prevention property the limiter promises.

   [N/A] The `![[ ]]` transclusion feature is currently UNUSED in the corpus
   (0 occurrences at time of writing; the wiki uses plain `[[ ]]` wikilinks
   only). The scanner and the bounded BFS are real and correct; they report an
   empty transclusion graph rather than fabricating edges. If transclusion is
   adopted later this guard becomes live with no code change. *)

let max_depth = 3

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(* recursively list *.md under dir *)
let rec md_files dir acc =
  match Sys.readdir dir with
  | entries ->
      Array.fold_left
        (fun acc e ->
          let p = Filename.concat dir e in
          if Sys.is_directory p then md_files p acc
          else if Filename.check_suffix p ".md" then p :: acc
          else acc)
        acc entries
  | exception Sys_error _ -> acc

(* extract every ![[target]] target from [text] (target = text up to | or ]] ) *)
let transclusion_targets text =
  let n = String.length text in
  let out = ref [] in
  let i = ref 0 in
  while !i < n - 2 do
    if text.[!i] = '!' && text.[!i + 1] = '[' && text.[!i + 2] = '[' then begin
      let j = ref (!i + 3) in
      let buf = Buffer.create 32 in
      let stop = ref false in
      while (not !stop) && !j < n do
        if !j + 1 < n && text.[!j] = ']' && text.[!j + 1] = ']' then begin
          stop := true; j := !j + 2
        end else if text.[!j] = '|' then begin
          (* skip display alias: consume to ]] *)
          while !j + 1 < n && not (text.[!j] = ']' && text.[!j + 1] = ']') do incr j done
        end else begin
          Buffer.add_char buf text.[!j]; incr j
        end
      done;
      let t = String.trim (Buffer.contents buf) in
      if t <> "" then out := t :: !out;
      i := !j
    end else incr i
  done;
  List.rev !out

(* bounded BFS from [start] over [graph]; returns (max_reached_depth, cycle?) *)
let bounded_bfs graph start =
  let seen = Hashtbl.create 16 in
  let cycle = ref false and reached = ref 0 in
  let rec go frontier depth =
    if depth > max_depth || frontier = [] then ()
    else begin
      reached := max !reached depth;
      let next =
        List.concat_map
          (fun node ->
            List.filter
              (fun t ->
                if Hashtbl.mem seen t then (cycle := true; false)
                else (Hashtbl.replace seen t (); true))
              (try Hashtbl.find graph node with Not_found -> []))
          frontier
      in
      go next (depth + 1)
    end
  in
  Hashtbl.replace seen start ();
  go [ start ] 0;
  (!reached, !cycle)

let run (root : string) : unit =
  Printf.printf "[zk_transclusion_depth_limiter] scanning corpus (MAX_DEPTH=%d)\n" max_depth;
  let zk_dir = Filename.concat root "docs/zk" in
  let files = if Sys.file_exists zk_dir then md_files zk_dir [] else [] in
  let graph = Hashtbl.create 256 in
  let edges = ref 0 in
  List.iter
    (fun f ->
      match read_file f with
      | text ->
          let slug = Filename.remove_extension (Filename.basename f) in
          let ts = transclusion_targets text in
          edges := !edges + List.length ts;
          if ts <> [] then Hashtbl.replace graph slug ts
      | exception _ -> ())
    files;
  Printf.printf "[zk_transclusion_depth_limiter] %d note(s), %d transclusion edge(s)\n"
    (List.length files) !edges;
  if !edges = 0 then
    Printf.printf
      "[zk_transclusion_depth_limiter] [N/A] transclusion feature unused (0 ![[ ]] edges); \
       bounded-BFS guard idle but armed\n"
  else begin
    let violations = ref 0 and cycles = ref 0 in
    Hashtbl.iter
      (fun start _ ->
        let reached, cyc = bounded_bfs graph start in
        if reached >= max_depth then begin
          incr violations;
          Printf.printf "  [DEPTH] %s reaches transclusion depth %d (cap %d)\n"
            start reached max_depth
        end;
        if cyc then begin incr cycles;
          Printf.printf "  [CYCLE] %s participates in a transclusion cycle\n" start end)
      graph;
    Printf.printf
      "[zk_transclusion_depth_limiter] %d depth-limit hit(s), %d cycle(s) detected\n"
      !violations !cycles
  end
