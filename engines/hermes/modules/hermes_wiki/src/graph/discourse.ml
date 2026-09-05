(* Grounded semantics — see discourse.mli. Att = @opposes only. *)

let grounded ~attacks ~nodes =
  let nodes = List.sort_uniq compare nodes in
  let attackers_of n = List.filter_map (fun (a, b) -> if b = n then Some a else None) attacks in
  let attacked_by s a = List.exists (fun (d, b) -> b = a && List.mem d s) attacks in
  let step s =
    List.filter (fun n -> List.for_all (fun a -> attacked_by s a) (attackers_of n)) nodes
  in
  let rec ascend s rounds =
    if rounds > List.length nodes + 1 then s
    else
      let s2 = step s in
      if s2 = s then s else ascend s2 (rounds + 1)
  in
  ascend [] 0

let anomalies (m : Hermes_wiki.model) =
  let nodes = List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug) m.Hermes_wiki.pages in
  let attacks =
    List.concat_map
      (fun (p : Hermes_wiki.page) ->
        List.filter_map
          (fun (target, rel) -> if rel = "opposes" then Some (p.Hermes_wiki.slug, target) else None)
          p.Hermes_wiki.typed)
      m.Hermes_wiki.pages
  in
  let ext = grounded ~attacks ~nodes in
  m.Hermes_wiki.pages
  |> List.filter_map (fun (p : Hermes_wiki.page) ->
         if p.Hermes_wiki.meta.Hermes_wiki.ntype = "claim" && not (List.mem p.Hermes_wiki.slug ext)
         then Some p.Hermes_wiki.slug
         else None)
  |> List.sort compare
