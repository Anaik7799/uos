(* Graph kernels — ported from the imported ZK calculators (R14 mirrors:
   zk_page_rank_calculator.ml, zk_graph_betweenness_calculator.ml) onto
   the model's own link graph, hardened for determinism: sorted nodes,
   sorted deduplicated edges, fixed summation order, slug ties. *)

type g = {
  names : string array;
  out_ : int array array;
  in_ : int array array;
}

let of_model (m : Hermes_wiki.model) =
  let pages =
    List.sort
      (fun (a : Hermes_wiki.page) b -> compare a.Hermes_wiki.slug b.Hermes_wiki.slug)
      m.Hermes_wiki.pages
  in
  let names = Array.of_list (List.map (fun p -> p.Hermes_wiki.slug) pages) in
  let n = Array.length names in
  let index = Hashtbl.create ((2 * n) + 1) in
  Array.iteri (fun i s -> Hashtbl.replace index s i) names;
  let out_sets = Array.make n [] in
  List.iteri
    (fun i (p : Hermes_wiki.page) ->
      List.iter
        (fun t ->
          match Hashtbl.find_opt index t with
          | Some j when j <> i -> out_sets.(i) <- j :: out_sets.(i)
          | _ -> ())
        p.Hermes_wiki.outlinks)
    pages;
  let out_ = Array.map (fun l -> Array.of_list (List.sort_uniq compare l)) out_sets in
  let in_sets = Array.make n [] in
  Array.iteri (fun u os -> Array.iter (fun v -> in_sets.(v) <- u :: in_sets.(v)) os) out_;
  let in_ = Array.map (fun l -> Array.of_list (List.sort_uniq compare l)) in_sets in
  { names; out_; in_ }

let nodes t = Array.to_list t.names
let edge_count t = Array.fold_left (fun acc os -> acc + Array.length os) 0 t.out_

let by_rank names scores =
  let paired = Array.to_list (Array.mapi (fun i s -> (names.(i), s)) scores) in
  List.sort
    (fun (s1, x1) (s2, x2) -> if x1 = x2 then compare s1 s2 else compare x2 x1)
    paired

(* the imported power iteration, structure preserved: d=0.85, dangling
   mass to the teleport, L1 delta < 1e-9, <=200 rounds; summation over
   the SORTED in-edge arrays — the fixed order the row's law demands. *)
let pagerank ?(seeds = []) t =
  let n = Array.length t.names in
  if n = 0 then []
  else begin
    let teleport = Array.make n 0.0 in
    let seed_idx =
      List.filter_map
        (fun s ->
          let rec find i =
            if i >= n then None else if t.names.(i) = s then Some i else find (i + 1)
          in
          find 0)
        (List.sort_uniq compare seeds)
    in
    (match seed_idx with
    | [] -> Array.fill teleport 0 n (1.0 /. float_of_int n)
    | s ->
        let w = 1.0 /. float_of_int (List.length s) in
        List.iter (fun i -> teleport.(i) <- teleport.(i) +. w) s);
    let d = 0.85 in
    let r = Array.make n (1.0 /. float_of_int n) in
    let converged = ref false and iter = ref 0 in
    while (not !converged) && !iter < 200 do
      incr iter;
      let dangling = ref 0.0 in
      for i = 0 to n - 1 do
        if Array.length t.out_.(i) = 0 then dangling := !dangling +. r.(i)
      done;
      let nr = Array.make n 0.0 in
      for v = 0 to n - 1 do
        let inflow = ref 0.0 in
        Array.iter
          (fun u -> inflow := !inflow +. (r.(u) /. float_of_int (Array.length t.out_.(u))))
          t.in_.(v);
        nr.(v) <- ((1.0 -. d) *. teleport.(v)) +. (d *. (!inflow +. (!dangling *. teleport.(v))))
      done;
      let delta = ref 0.0 in
      for i = 0 to n - 1 do
        delta := !delta +. abs_float (nr.(i) -. r.(i));
        r.(i) <- nr.(i)
      done;
      if !delta < 1e-9 then converged := true
    done;
    by_rank t.names r
  end

(* Brandes 2001, directed, fixed vertex order (the sorted node array). *)
let betweenness t =
  let n = Array.length t.names in
  let cb = Array.make n 0.0 in
  for s = 0 to n - 1 do
    let sigma = Array.make n 0.0 in
    let dist = Array.make n (-1) in
    let preds = Array.make n [] in
    let stack = ref [] in
    sigma.(s) <- 1.0;
    dist.(s) <- 0;
    let q = Queue.create () in
    Queue.add s q;
    while not (Queue.is_empty q) do
      let v = Queue.take q in
      stack := v :: !stack;
      Array.iter
        (fun w ->
          if dist.(w) < 0 then begin
            dist.(w) <- dist.(v) + 1;
            Queue.add w q
          end;
          if dist.(w) = dist.(v) + 1 then begin
            sigma.(w) <- sigma.(w) +. sigma.(v);
            preds.(w) <- v :: preds.(w)
          end)
        t.out_.(v)
    done;
    let delta = Array.make n 0.0 in
    List.iter
      (fun w ->
        List.iter
          (fun v -> delta.(v) <- delta.(v) +. (sigma.(v) /. sigma.(w) *. (1.0 +. delta.(w))))
          preds.(w);
        if w <> s then cb.(w) <- cb.(w) +. delta.(w))
      !stack
  done;
  by_rank t.names cb

(* HW.4.2.2 — CONSTRAINED label propagation: slug-order sweep, undirected
   neighbourhoods, ties to the smallest label, bounded rounds. *)
let communities t =
  let n = Array.length t.names in
  let neigh = Array.make n [] in
  Array.iteri
    (fun u os ->
      Array.iter
        (fun v ->
          neigh.(u) <- v :: neigh.(u);
          neigh.(v) <- u :: neigh.(v))
        os)
    t.out_;
  let neigh = Array.map (fun l -> List.sort_uniq compare l) neigh in
  let label = Array.init n (fun i -> i) in
  let changed = ref true and rounds = ref 0 in
  while !changed && !rounds < 100 do
    changed := false;
    incr rounds;
    for i = 0 to n - 1 do
      match neigh.(i) with
      | [] -> ()
      | ns ->
          let counts = Hashtbl.create 8 in
          List.iter
            (fun j ->
              let l = label.(j) in
              Hashtbl.replace counts l (1 + Option.value ~default:0 (Hashtbl.find_opt counts l)))
            ns;
          let best = ref label.(i) and best_count = ref 0 in
          List.iter
            (fun j ->
              let l = label.(j) in
              let c = Hashtbl.find counts l in
              if c > !best_count || (c = !best_count && l < !best) then begin
                best := l;
                best_count := c
              end)
            ns;
          if !best <> label.(i) then begin
            label.(i) <- !best;
            changed := true
          end
    done
  done;
  let groups = Hashtbl.create 16 in
  Array.iteri
    (fun i l ->
      Hashtbl.replace groups l
        (t.names.(i) :: Option.value ~default:[] (Hashtbl.find_opt groups l)))
    label;
  Hashtbl.fold (fun _ members acc -> members :: acc) groups []
  |> List.map (fun members ->
         let sorted = List.sort compare members in
         (List.hd sorted, sorted))
  |> List.sort compare

let orphans t =
  Array.to_list t.names
  |> List.filteri (fun i _ -> Array.length t.in_.(i) = 0)

let ecc_from t slug =
  let n = Array.length t.names in
  let rec find i = if i >= n then None else if t.names.(i) = slug then Some i else find (i + 1) in
  match find 0 with
  | None -> None
  | Some s ->
      let dist = Array.make n (-1) in
      dist.(s) <- 0;
      let q = Queue.create () in
      Queue.add s q;
      let m = ref 0 in
      while not (Queue.is_empty q) do
        let v = Queue.take q in
        if dist.(v) > !m then m := dist.(v);
        Array.iter
          (fun w ->
            if dist.(w) < 0 then begin
              dist.(w) <- dist.(v) + 1;
              Queue.add w q
            end)
          t.out_.(v)
      done;
      Some !m
