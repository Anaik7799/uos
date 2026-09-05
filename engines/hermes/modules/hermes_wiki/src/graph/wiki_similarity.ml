(* HW.4.3.2 / HW.4.1.7 / HW.4.2.4 / HW.4.5.2 / HW.4.6.2 / HW.4.6.3 — see
   wiki_similarity.mli for the laws. Two disciplines run through every
   function here and are worth restating at the top of the code that has
   to obey them:

     NOTHING LEAVES A FOLD. [Hashtbl.fold] visits in insertion-history
     order, so every table is drained into a list and SORTED before it is
     returned. Every ranked list ends with an explicit slug tie-break.

     ARITHMETIC RUNS IN CANONICAL ORDER. Pages are sorted by slug and
     terms by term before any float is added, so the operation sequence
     is a function of the corpus and not of the input list's order. *)

(* ================================================================== *)
(* Tokenisation — an R14 mirror of Wiki_search.tokens, byte for byte.  *)
(* The similarity library may not depend on the search library, so the *)
(* function is copied; a test pins the copy by value. If this ever     *)
(* diverges, two halves of the system disagree about what a word is.   *)
(* ================================================================== *)

let tokens s =
  let lower = String.lowercase_ascii s in
  let out = ref [] and buf = Buffer.create 16 in
  let flush () =
    if Buffer.length buf >= 2 then out := Buffer.contents buf :: !out;
    Buffer.clear buf
  in
  String.iter
    (fun c ->
      if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') then Buffer.add_char buf c
      else flush ())
    lower;
  flush ();
  List.rev !out

(* fence-aware body lines — the search index's rule, mirrored *)
let body_lines raw =
  let in_fence = ref false in
  String.split_on_char '\n' raw
  |> List.filter (fun line ->
         let t = String.trim line in
         if String.length t >= 3 && String.sub t 0 3 = "```" then begin
           in_fence := not !in_fence;
           false
         end
         else not !in_fence)

(* the text half of Wiki_ast.block_anchor_split, mirrored: `^a1b2` is an
   ADDRESS, not a word, so it is removed before tokenisation. *)
let strip_block_anchor line =
  let is_id_char c =
    c = '-' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
  in
  let rstrip s =
    let stop = ref (String.length s) in
    while !stop > 0 && (s.[!stop - 1] = ' ' || s.[!stop - 1] = '\t') do
      decr stop
    done;
    String.sub s 0 !stop
  in
  let trimmed = rstrip line in
  let n = String.length trimmed in
  match String.rindex_opt trimmed ' ' with
  | Some sp when sp + 1 < n && trimmed.[sp + 1] = '^' ->
      let id = String.sub trimmed (sp + 2) (n - sp - 2) in
      let text = rstrip (String.sub trimmed 0 sp) in
      if id <> "" && String.for_all is_id_char id && text <> "" then text else line
  | Some _ | None -> line

let document_text (p : Hermes_wiki.page) =
  List.map strip_block_anchor (body_lines p.Hermes_wiki.raw)

(* ================================================================== *)
(* HW.4.3.2 — TF-IDF cosine similarity                                 *)
(* ================================================================== *)

type vectors = {
  n : int;
  df : (string * int) list;                     (* sorted term -> n_t *)
  docs : (string * (string * float) list) list; (* sorted slug -> sorted weights *)
  norms : (string * float) list;                (* sorted slug -> ||d|| *)
}

let quantum = 1e-6

(* 1e6 is exactly representable in binary; 1e-6 is not. Scaling by the
   exact value and dividing by it keeps round(1.0 * s) / s = 1.0 exactly,
   which is what makes the IDENTITY law survive quantisation. *)
let quantum_scale = 1e6

let quantize x = Float.round (x *. quantum_scale) /. quantum_scale

let clamp01 x =
  if Float.is_nan x then 0.0 else if x < 0.0 then 0.0 else if x > 1.0 then 1.0 else x

let sorted_pages (m : Hermes_wiki.model) =
  List.sort
    (fun (a : Hermes_wiki.page) b -> compare a.Hermes_wiki.slug b.Hermes_wiki.slug)
    m.Hermes_wiki.pages

let term_frequencies (p : Hermes_wiki.page) =
  let counts = Hashtbl.create 64 in
  List.iter
    (fun line ->
      List.iter
        (fun t -> Hashtbl.replace counts t (1 + Option.value ~default:0 (Hashtbl.find_opt counts t)))
        (tokens line))
    (document_text p);
  (* drained and sorted — never emitted in fold order *)
  Hashtbl.fold (fun t c acc -> (t, c) :: acc) counts [] |> List.sort compare

let idf_of ~n ~dfreq = if n <= 0 || dfreq <= 0 then 0.0 else 1.0 +. log (float_of_int n /. float_of_int dfreq)

let vectors (m : Hermes_wiki.model) =
  let pages = sorted_pages m in
  let tfs = List.map (fun (p : Hermes_wiki.page) -> (p.Hermes_wiki.slug, term_frequencies p)) pages in
  let n = List.length tfs in
  let df_tbl = Hashtbl.create 256 in
  List.iter
    (fun (_, ts) ->
      List.iter
        (fun (t, _) ->
          Hashtbl.replace df_tbl t (1 + Option.value ~default:0 (Hashtbl.find_opt df_tbl t)))
        ts)
    tfs;
  let df = Hashtbl.fold (fun t c acc -> (t, c) :: acc) df_tbl [] |> List.sort compare in
  let docs =
    List.map
      (fun (slug, ts) ->
        ( slug,
          List.map
            (fun (t, c) ->
              let dfreq = Option.value ~default:0 (Hashtbl.find_opt df_tbl t) in
              (t, float_of_int c *. idf_of ~n ~dfreq))
            ts ))
      tfs
  in
  let norms =
    List.map
      (fun (slug, ws) ->
        (* accumulated in ascending term order — the canonical sequence *)
        (slug, sqrt (List.fold_left (fun acc (_, w) -> acc +. (w *. w)) 0.0 ws)))
      docs
  in
  { n; df; docs; norms }

let corpus_size v = v.n
let document_frequency v t = Option.value ~default:0 (List.assoc_opt t v.df)
let idf v t = idf_of ~n:v.n ~dfreq:(document_frequency v t)
let weights v slug = Option.value ~default:[] (List.assoc_opt slug v.docs)

(* merge join over two ascending term lists: the products are summed in
   ascending term order, and IEEE multiplication is commutative, so
   dot a b and dot b a are BIT-identical. *)
let dot xs ys =
  let rec go acc xs ys =
    match (xs, ys) with
    | [], _ | _, [] -> acc
    | (t1, w1) :: r1, (t2, w2) :: r2 ->
        let c = compare t1 t2 in
        if c = 0 then go (acc +. (w1 *. w2)) r1 r2
        else if c < 0 then go acc r1 ys
        else go acc xs r2
  in
  go 0.0 xs ys

let similarity v a b =
  match (List.assoc_opt a v.docs, List.assoc_opt b v.docs) with
  | None, _ | Some _, None -> 0.0
  | Some wa, Some wb ->
      if a = b then 1.0 (* DEFINED, not computed — see the .mli *)
      else
        let na = Option.value ~default:0.0 (List.assoc_opt a v.norms) in
        let nb = Option.value ~default:0.0 (List.assoc_opt b v.norms) in
        if na <= 0.0 || nb <= 0.0 then 0.0 else quantize (clamp01 (dot wa wb /. (na *. nb)))

let related ?limit v slug =
  match List.assoc_opt slug v.docs with
  | None -> []
  | Some _ ->
      let ranked =
        List.filter_map
          (fun (other, _) ->
            if other = slug then None
            else
              let s = similarity v slug other in
              if s > 0.0 then Some (other, s) else None)
          v.docs
        |> List.sort (fun (s1, x1) (s2, x2) -> if x1 = x2 then compare s1 s2 else compare x2 x1)
      in
      (match limit with
      | None -> ranked
      | Some k ->
          if k <= 0 then []
          else
            let rec take i = function [] -> [] | x :: r -> if i >= k then [] else x :: take (i + 1) r in
            take 0 ranked)

let canonical v =
  let b = Buffer.create 4096 in
  Buffer.add_string b (Printf.sprintf "n %d\n" v.n);
  List.iter (fun (t, c) -> Buffer.add_string b (Printf.sprintf "df %s %d\n" t c)) v.df;
  List.iter
    (fun (slug, ws) ->
      List.iter (fun (t, w) -> Buffer.add_string b (Printf.sprintf "w %s %s %.17g\n" slug t w)) ws)
    v.docs;
  List.iter (fun (slug, nm) -> Buffer.add_string b (Printf.sprintf "norm %s %.17g\n" slug nm)) v.norms;
  Buffer.contents b

(* ================================================================== *)
(* HW.4.1.7 — nested tags                                              *)
(* ================================================================== *)

let tag_segments t =
  String.split_on_char '/' t
  |> List.map String.trim
  |> List.filter (fun s -> s <> "")

let tag_normalise s =
  let s = String.lowercase_ascii (String.trim s) in
  let s =
    if String.length s > 0 && s.[0] = '#' then String.sub s 1 (String.length s - 1) else s
  in
  String.concat "/" (tag_segments s)

let tag_segments t = tag_segments (tag_normalise t)

let tag_ancestors t =
  let segs = tag_segments t in
  let rec build acc prefix = function
    | [] -> List.rev acc
    | s :: rest ->
        let p = if prefix = "" then s else prefix ^ "/" ^ s in
        build (p :: acc) p rest
  in
  build [] "" segs

(* SEGMENT-WISE prefix. A string-prefix test would file `#abstract`
   under `#a`, which is a coincidence of spelling, not a hierarchy. *)
let tag_covers ~parent ~child =
  let p = tag_segments parent and c = tag_segments child in
  let rec pref a b =
    match (a, b) with
    | [], _ -> true
    | _ :: _, [] -> false
    | x :: ra, y :: rb -> x = y && pref ra rb
  in
  p <> [] && c <> [] && pref p c

let page_tags (p : Hermes_wiki.page) =
  p.Hermes_wiki.tags @ p.Hermes_wiki.meta.Hermes_wiki.topics
  |> List.map tag_normalise
  |> List.filter (fun t -> t <> "")
  |> List.sort_uniq compare

let tag_members (m : Hermes_wiki.model) t =
  if tag_normalise t = "" then []
  else
    sorted_pages m
    |> List.filter (fun (p : Hermes_wiki.page) ->
           List.exists (fun u -> tag_covers ~parent:t ~child:u) (page_tags p))
    |> List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug)
    |> List.sort compare

let tag_tree (m : Hermes_wiki.model) =
  let all =
    sorted_pages m
    |> List.concat_map (fun p -> List.concat_map tag_ancestors (page_tags p))
    |> List.sort_uniq compare
  in
  List.map (fun t -> (t, tag_members m t)) all

(* ================================================================== *)
(* The shared neighbourhood relation                                   *)
(* ================================================================== *)

(* Wiki_graph.of_model's resolution rule, mirrored exactly: pages sorted
   by slug, an outlink counts only when its target is a page, self-loops
   dropped, duplicates collapsed. The mirror is CHECKED against
   Wiki_graph.edge_count by the suite. *)
let indexed (m : Hermes_wiki.model) =
  let pages = sorted_pages m in
  let names = Array.of_list (List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug) pages) in
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
          | Some _ | None -> ())
        p.Hermes_wiki.outlinks)
    pages;
  let out_ = Array.map (fun l -> Array.of_list (List.sort_uniq compare l)) out_sets in
  (names, out_)

let directed_edges m =
  let names, out_ = indexed m in
  Array.to_list out_
  |> List.mapi (fun i os -> Array.to_list (Array.map (fun j -> (names.(i), names.(j))) os))
  |> List.concat
  |> List.sort compare

let adjacency m =
  let names, out_ = indexed m in
  let n = Array.length names in
  let neigh = Array.make n [] in
  Array.iteri
    (fun u os ->
      Array.iter
        (fun v ->
          neigh.(u) <- v :: neigh.(u);
          neigh.(v) <- u :: neigh.(v))
        os)
    out_;
  (names, Array.map (fun l -> List.sort_uniq compare l) neigh)

let edges m =
  let names, neigh = adjacency m in
  Array.to_list neigh
  |> List.mapi (fun i ns ->
         List.filter_map (fun j -> if i < j then Some (names.(i), names.(j)) else None) ns)
  |> List.concat
  |> List.sort_uniq compare

let degrees m =
  let names, neigh = adjacency m in
  Array.to_list neigh
  |> List.mapi (fun i ns -> (names.(i), List.length ns))
  |> List.sort compare

let find_index names slug =
  let n = Array.length names in
  let rec go i = if i >= n then None else if names.(i) = slug then Some i else go (i + 1) in
  go 0

(* undirected BFS distances; unreachable pages are ABSENT, never
   present at a fabricated infinity *)
let distances m slug =
  let names, neigh = adjacency m in
  match find_index names slug with
  | None -> []
  | Some s ->
      let n = Array.length names in
      let dist = Array.make n (-1) in
      dist.(s) <- 0;
      let q = Queue.create () in
      Queue.add s q;
      while not (Queue.is_empty q) do
        let v = Queue.take q in
        List.iter
          (fun w ->
            if dist.(w) < 0 then begin
              dist.(w) <- dist.(v) + 1;
              Queue.add w q
            end)
          neigh.(v)
      done;
      Array.to_list dist
      |> List.mapi (fun i d -> (names.(i), d))
      |> List.filter (fun (_, d) -> d >= 0)
      |> List.sort compare

let hops m slug = distances m slug

(* ================================================================== *)
(* HW.4.5.2 — local graph (neighbourhood)                              *)
(* ================================================================== *)

type neighbourhood = {
  center : string;
  nodes : string list;
  edges : (string * string) list;
}

let local_graph m ~radius slug =
  let r = if radius < 0 then 0 else radius in
  match distances m slug with
  | [] -> { center = slug; nodes = []; edges = [] }
  | ds ->
      let nodes =
        List.filter_map (fun (s, d) -> if d <= r then Some s else None) ds |> List.sort compare
      in
      let inside s = List.mem s nodes in
      let edges = List.filter (fun (u, v) -> inside u && inside v) (edges m) in
      { center = slug; nodes; edges }

(* ================================================================== *)
(* HW.4.2.4 — structural holes                                         *)
(* ================================================================== *)

(* the ONE partition the rest of the system uses — never a fresh
   clustering, which would eventually disagree with this one *)
let community_of m =
  let g = Wiki_graph.of_model m in
  List.concat_map
    (fun (key, members) -> List.map (fun s -> (s, key)) members)
    (Wiki_graph.communities g)

let structural_holes m =
  let names, neigh = adjacency m in
  let comm = community_of m in
  let key_of s = Option.value ~default:s (List.assoc_opt s comm) in
  Array.to_list neigh
  |> List.mapi (fun i ns ->
         let mine = key_of names.(i) in
         let spanned =
           List.map (fun j -> key_of names.(j)) ns
           |> List.filter (fun k -> k <> mine)
           |> List.sort_uniq compare
         in
         (names.(i), List.length spanned))
  |> List.sort (fun (s1, x1) (s2, x2) -> if x1 = x2 then compare s1 s2 else compare x2 x1)

(* ================================================================== *)
(* HW.4.6.2 — community-grounded MoCs                                  *)
(* ================================================================== *)

let community_mocs m =
  let g = Wiki_graph.of_model m in
  let deg = degrees m in
  let degree_of s = Option.value ~default:0 (List.assoc_opt s deg) in
  Wiki_graph.communities g
  |> List.filter_map (fun (_, members) ->
         let sorted = List.sort compare members in
         (* members are ascending, so the first strict maximum is the
            smallest slug among the maxima — the stated tie-break *)
         let hub =
           List.fold_left
             (fun acc s ->
               match acc with
               | None -> Some s
               | Some best -> if degree_of s > degree_of best then Some s else Some best)
             None sorted
         in
         match hub with
         | None -> None
         | Some h -> if degree_of h > 0 then Some (h, sorted) else None)
  |> List.sort compare

(* ================================================================== *)
(* HW.4.6.3 — rollup / aggregation                                     *)
(* ================================================================== *)

let rollup (m : Hermes_wiki.model) ~key ~value =
  let tbl = Hashtbl.create 32 in
  List.iter
    (fun (p : Hermes_wiki.page) ->
      let k = key p in
      (* every page lands in a bucket, INCLUDING the "" one — dropping it
         would answer a different question with a number that still
         looks right *)
      Hashtbl.replace tbl k (value p + Option.value ~default:0 (Hashtbl.find_opt tbl k)))
    m.Hermes_wiki.pages;
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) tbl [] |> List.sort compare

let rollup_count m ~key = rollup m ~key ~value:(fun _ -> 1)

let rollup_communities m =
  let g = Wiki_graph.of_model m in
  Wiki_graph.communities g
  |> List.map (fun (key, members) -> (key, List.length members))
  |> List.sort compare
