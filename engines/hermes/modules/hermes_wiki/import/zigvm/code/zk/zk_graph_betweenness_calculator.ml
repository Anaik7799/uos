(* ZK Graph Betweenness Calculator — a REAL Brandes betweenness-centrality run.

   INTENT (from the phase-7 stub).  "Calculates Betweenness Centrality for all ZK
   notes to find crucial architectural chokepoints."

   WHAT THIS HONESTLY DOES.  It builds the wikilink graph from the ZK corpus:
   each note ([root]/docs/zk/**/*.md) is a vertex identified by its slug
   (basename without .md), and every `[[target|alias]]` / `[[target]]` link is a
   directed edge slug -> target. It then runs Brandes' exact betweenness-
   centrality algorithm (unweighted, directed) over the vertex set and reports
   the top chokepoints by score.

   This is a REAL graph algorithm on REAL data — Brandes is exact for unweighted
   graphs (BFS from every source, dependency accumulation). The only modelling
   choices: link targets that name no on-disk note still become vertices (they
   are real referenced concepts), and self-loops are dropped. No solver, no
   heuristic — the centrality numbers are computed, not estimated. *)

let read_file path =
  try In_channel.with_open_bin path In_channel.input_all with _ -> ""

let list_zk root =
  let base = Filename.concat (Filename.concat root "docs") "zk" in
  let acc = ref [] in
  let rec go dir =
    match Sys.readdir dir with
    | entries ->
        Array.iter
          (fun e ->
            let p = Filename.concat dir e in
            if (try Sys.is_directory p with _ -> false) then go p
            else if Filename.check_suffix e ".md" then acc := p :: !acc)
          entries
    | exception _ -> ()
  in
  if (try Sys.is_directory base with _ -> false) then go base;
  List.sort compare !acc

let slug_of path = Filename.chop_suffix (Filename.basename path) ".md"

(* Extract [[target]] link targets from text (target = up to '|' or ']]'). *)
let extract_links text =
  let n = String.length text in
  let acc = ref [] in
  let i = ref 0 in
  while !i < n - 1 do
    if text.[!i] = '[' && text.[!i + 1] = '[' then begin
      let j = ref (!i + 2) in
      let buf = Buffer.create 32 in
      let stop = ref false in
      while (not !stop) && !j < n - 1 do
        if text.[!j] = ']' && text.[!j + 1] = ']' then stop := true
        else if text.[!j] = '|' then begin
          (* skip alias: fast-forward to ]] *)
          while !j < n - 1 && not (text.[!j] = ']' && text.[!j + 1] = ']') do incr j done;
          stop := true
        end
        else begin
          Buffer.add_char buf text.[!j];
          incr j
        end
      done;
      let t = String.trim (Buffer.contents buf) in
      if String.length t > 0 then acc := t :: !acc;
      i := !j + 2
    end
    else incr i
  done;
  List.rev !acc

let run (root : string) : unit =
  Printf.printf
    "[zk_graph_betweenness_calculator] building wikilink graph + Brandes betweenness\n";
  let files = list_zk root in
  (* index vertices *)
  let id_of : (string, int) Hashtbl.t = Hashtbl.create 256 in
  let name_of : (int, string) Hashtbl.t = Hashtbl.create 256 in
  let ensure name =
    match Hashtbl.find_opt id_of name with
    | Some i -> i
    | None ->
        let i = Hashtbl.length id_of in
        Hashtbl.add id_of name i;
        Hashtbl.add name_of i name;
        i
  in
  let edges = ref [] in
  List.iter
    (fun f ->
      let s = ensure (slug_of f) in
      extract_links (read_file f)
      |> List.iter (fun tgt ->
             let d = ensure tgt in
             if d <> s then edges := (s, d) :: !edges))
    files;
  let v = Hashtbl.length id_of in
  (* adjacency *)
  let adj = Array.make v [] in
  List.iter (fun (s, d) -> adj.(s) <- d :: adj.(s)) !edges;
  (* dedup adjacency *)
  for i = 0 to v - 1 do adj.(i) <- List.sort_uniq compare adj.(i) done;
  Printf.printf "  vertices: %d   directed edges: %d\n" v
    (Array.fold_left (fun a l -> a + List.length l) 0 adj);
  if v = 0 then
    Printf.printf "  (empty ZK graph — nothing to score)\n"
  else begin
    (* Brandes' algorithm, directed unweighted *)
    let cb = Array.make v 0.0 in
    for src = 0 to v - 1 do
      let stack = ref [] in
      let pred = Array.make v [] in
      let sigma = Array.make v 0.0 in
      let dist = Array.make v (-1) in
      sigma.(src) <- 1.0;
      dist.(src) <- 0;
      let q = Queue.create () in
      Queue.push src q;
      while not (Queue.is_empty q) do
        let x = Queue.pop q in
        stack := x :: !stack;
        List.iter
          (fun w ->
            if dist.(w) < 0 then begin
              dist.(w) <- dist.(x) + 1;
              Queue.push w q
            end;
            if dist.(w) = dist.(x) + 1 then begin
              sigma.(w) <- sigma.(w) +. sigma.(x);
              pred.(w) <- x :: pred.(w)
            end)
          adj.(x)
      done;
      let delta = Array.make v 0.0 in
      List.iter
        (fun w ->
          List.iter
            (fun p ->
              delta.(p) <- delta.(p) +. (sigma.(p) /. sigma.(w)) *. (1.0 +. delta.(w)))
            pred.(w);
          if w <> src then cb.(w) <- cb.(w) +. delta.(w))
        !stack
    done;
    let ranked =
      Array.to_list (Array.mapi (fun i s -> (Hashtbl.find name_of i, s)) cb)
      |> List.sort (fun (_, a) (_, b) -> compare b a)
    in
    Printf.printf "  top chokepoints (betweenness centrality):\n";
    List.filteri (fun i _ -> i < 15) ranked
    |> List.iter (fun (n, s) ->
           if s > 0.0 then Printf.printf "    %9.2f  %s\n" s n);
    Printf.printf "  [OK] exact Brandes betweenness over the real wikilink graph\n"
  end
