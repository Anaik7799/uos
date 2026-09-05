(* Full-text search + block hits — see wiki_search.mli. *)

type index = {
  pages : (string * (string * int) list) list; (* slug -> sorted (token, count) *)
  blocks : (string * string * string list) list; (* slug, ^id, sorted tokens *)
}

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

(* fence-aware body lines *)
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

let build (m : Hermes_wiki.model) =
  let pages =
    m.Hermes_wiki.pages
    |> List.map (fun (p : Hermes_wiki.page) ->
           let counts = Hashtbl.create 64 in
           let add w t =
             Hashtbl.replace counts t (w + Option.value ~default:0 (Hashtbl.find_opt counts t))
           in
           (* headings weigh 3x — the title convention *)
           List.iter (fun (_, text, _) -> List.iter (add 3) (tokens text)) p.Hermes_wiki.headings;
           (* HW.1.3.10 declared keywords BOOST, weight 2. Additive by
              construction: [add] accumulates, so a keyword that repeats
              a body word raises that word's score and a body word the
              author never declared still scores on its own. Declaring
              keywords can therefore only ever ADD reachable queries —
              it cannot hide a page from a search for its own words. *)
           List.iter (fun k -> List.iter (add 2) (tokens k)) p.Hermes_wiki.meta.Hermes_wiki.keywords;
           (* HW.1.3.9 the declared description, weight 1. Its row's law
              is "feeds ranking", and a field nothing consumes is data
              rather than a feature — the same trap keywords was wired to
              avoid. Weight 1, below a keyword's 2: a keyword is a
              deliberate search term, a description is prose that happens
              to be about the page. Additive by the same construction. *)
           List.iter (add 1) (tokens p.Hermes_wiki.meta.Hermes_wiki.description);
           List.iter
             (fun line ->
               (* headings are already counted at weight 3 — never twice *)
               if not (String.length (String.trim line) > 0 && (String.trim line).[0] = '#')
               then begin
                 let text, _ = Wiki_ast.block_anchor_split line in
                 List.iter (add 1) (tokens text)
               end)
             (body_lines p.Hermes_wiki.raw);
           ( p.Hermes_wiki.slug,
             Hashtbl.fold (fun t c acc -> (t, c) :: acc) counts [] |> List.sort compare ))
    |> List.sort compare
  in
  let blocks =
    m.Hermes_wiki.pages
    |> List.concat_map (fun (p : Hermes_wiki.page) ->
           body_lines p.Hermes_wiki.raw
           |> List.filter_map (fun line ->
                  match Wiki_ast.block_anchor_split line with
                  | text, Some id ->
                      Some (p.Hermes_wiki.slug, id, List.sort_uniq compare (tokens text))
                  | _, None -> None))
    |> List.sort compare
  in
  { pages; blocks }

let canonical idx =
  let b = Buffer.create 4096 in
  List.iter
    (fun (slug, ts) ->
      List.iter (fun (t, c) -> Buffer.add_string b (Printf.sprintf "%s %s %d\n" slug t c)) ts)
    idx.pages;
  List.iter
    (fun (slug, id, ts) ->
      Buffer.add_string b (Printf.sprintf "%s %s %s\n" slug id (String.concat "," ts)))
    idx.blocks;
  Buffer.contents b

(* an in-process identity for index equality — NOT an evidence pin; a
   pinned index goes through the sha256 oracle like the render baseline *)
let digest idx = Digest.to_hex (Digest.string (canonical idx))

let search idx q =
  match tokens q with
  | [] -> []
  | qs ->
      idx.pages
      |> List.filter_map (fun (slug, counts) ->
             let scores = List.map (fun t -> Option.value ~default:0 (List.assoc_opt t counts)) qs in
             if List.exists (fun s -> s = 0) scores then None
             else Some (slug, List.fold_left ( + ) 0 scores))
      |> List.sort (fun (s1, x1) (s2, x2) -> if x1 = x2 then compare s1 s2 else compare x2 x1)

let block_hits idx q =
  match tokens q with
  | [] -> []
  | qs ->
      idx.blocks
      |> List.filter_map (fun (slug, id, ts) ->
             if List.for_all (fun t -> List.mem t ts) qs then Some (slug, id) else None)
      |> List.sort compare
