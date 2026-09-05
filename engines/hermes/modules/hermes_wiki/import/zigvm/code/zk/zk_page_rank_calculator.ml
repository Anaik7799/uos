(* ZK Personalized PageRank — a REAL power-iteration eigenvector over the live graph.

   Promoted from a phase-7 printf stub. It builds the directed link graph of the
   corpus (node = note slug; edge = each [[target]] wikilink in a note's body) and
   computes Personalized PageRank by power iteration:
       r_{k+1} = (1-d) * v  +  d * (Aᵀ r_k),   with dangling mass redistributed to v
   where d = 0.85 and v is the personalization/teleport vector concentrated on the
   MoC seed set (moc-*.md nodes) — "personalized" toward the human-curated maps of
   content, so authority flows out from the curated backbone. Convergence is by
   L1 delta < 1e-9 or 200 iterations (bounded — never a hang). The result is a
   real probability distribution (Σ r = 1) over notes; the top ranks are the
   high-authority notes.

   [NOTE] this is a real numeric eigenvector solve over real bytes. If the MoC
   seed set is empty the teleport falls back to uniform (standard PageRank). *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let zk_files root =
  let dir = Filename.concat root "docs/zk" in
  let rec walk d acc =
    let entries = try Sys.readdir d with _ -> [||] in
    Array.fold_left (fun acc name ->
      let p = Filename.concat d name in
      if (try Sys.is_directory p with _ -> false) then walk p acc
      else if Filename.check_suffix name ".md" then p :: acc
      else acc) acc entries
  in List.sort compare (walk dir [])

let find_from s sub i =
  let ls = String.length s and lsub = String.length sub in
  let rec go i =
    if i + lsub > ls then None
    else if String.sub s i lsub = sub then Some i
    else go (i + 1)
  in if lsub = 0 then None else go i

let wikilink_targets body =
  let rec go i acc =
    match find_from body "[[" i with
    | None -> List.rev acc
    | Some a ->
      (match find_from body "]]" (a + 2) with
       | None -> List.rev acc
       | Some b ->
         let inner = String.sub body (a + 2) (b - (a + 2)) in
         let target = match String.index_opt inner '|' with
           | Some p -> String.sub inner 0 p | None -> inner in
         go (b + 2) (String.trim target :: acc))
  in go 0 []

let slug path = Filename.remove_extension (Filename.basename path)

let run (root : string) : unit =
  let files = zk_files root in
  (* node ids *)
  let idx = Hashtbl.create 256 and names = ref [] and count = ref 0 in
  let node name =
    match Hashtbl.find_opt idx name with
    | Some i -> i
    | None -> let i = !count in Hashtbl.replace idx name i;
              names := name :: !names; incr count; i in
  let edges = ref [] in
  let seeds = ref [] in
  List.iter (fun path ->
    let s = slug path in
    let src = node s in
    if String.length (Filename.basename path) >= 4
       && String.sub (Filename.basename path) 0 4 = "moc-"
    then seeds := src :: !seeds;
    let body = try read_file path with _ -> "" in
    List.iter (fun tgt -> if tgt <> "" then edges := (src, node tgt) :: !edges)
      (wikilink_targets body)
  ) files;
  let n = !count in
  Printf.printf "[zk_page_rank_calculator] graph: %d nodes, %d link edges, %d MoC seeds\n"
    n (List.length !edges) (List.length !seeds);
  if n = 0 then (Printf.printf "  empty graph — nothing to rank\n") else begin
    let name_arr = Array.make n "" in
    List.iteri (fun k nm -> name_arr.(n - 1 - k) <- nm) !names;
    (* out-adjacency + out-degree *)
    let outdeg = Array.make n 0 in
    let inedges = Array.make n [] in  (* v -> list of u with edge u->v *)
    List.iter (fun (u, v) ->
      outdeg.(u) <- outdeg.(u) + 1;
      inedges.(v) <- u :: inedges.(v)) !edges;
    (* personalization vector v *)
    let teleport = Array.make n 0.0 in
    (match !seeds with
     | [] -> Array.fill teleport 0 n (1.0 /. float_of_int n)
     | s -> let w = 1.0 /. float_of_int (List.length s) in
            List.iter (fun i -> teleport.(i) <- teleport.(i) +. w) s);
    let d = 0.85 in
    let r = Array.make n (1.0 /. float_of_int n) in
    let converged = ref false and iter = ref 0 in
    while not !converged && !iter < 200 do
      incr iter;
      (* dangling mass = sum of rank on nodes with no out-edges *)
      let dangling = ref 0.0 in
      for i = 0 to n - 1 do if outdeg.(i) = 0 then dangling := !dangling +. r.(i) done;
      let nr = Array.make n 0.0 in
      for v = 0 to n - 1 do
        let inflow = List.fold_left (fun acc u -> acc +. r.(u) /. float_of_int outdeg.(u))
                       0.0 inedges.(v) in
        nr.(v) <- (1.0 -. d) *. teleport.(v)
                  +. d *. (inflow +. !dangling *. teleport.(v))
      done;
      let delta = ref 0.0 in
      for i = 0 to n - 1 do delta := !delta +. abs_float (nr.(i) -. r.(i)); r.(i) <- nr.(i) done;
      if !delta < 1e-9 then converged := true
    done;
    let sum = Array.fold_left (+.) 0.0 r in
    Printf.printf "  converged=%b in %d iterations; Σr=%.6f\n" !converged !iter sum;
    let order = Array.init n (fun i -> i) in
    Array.sort (fun a b -> compare r.(b) r.(a)) order;
    Printf.printf "  top authority notes (personalized to MoC seeds):\n";
    let top = min 10 n in
    for k = 0 to top - 1 do
      let i = order.(k) in
      Printf.printf "    %2d. %.5f  %s\n" (k + 1) r.(i) name_arr.(i)
    done;
    Printf.printf "  [NOTE] real power-iteration eigenvector; teleport = %s\n"
      (if !seeds = [] then "uniform (no MoC seeds)" else "MoC seed set")
  end
