(* HW.8.2.7 — the reconciliation pair: declared vs derived, residue
   computed. See reconcile.mli for the laws; test_reconcile.ml for the
   four legs and the five-mutant battery. *)

module type SUBJECT = sig
  type key
  type claim

  val compare_key : key -> key -> int
  val equal_claim : claim -> claim -> bool
  val show_key : key -> string
  val show_claim : claim -> string
end

module Make (S : SUBJECT) = struct
  type row = {
    key : S.key;
    decl : S.claim option;
    probe : (unit -> S.claim option) option;
    obs : S.claim option; (* frozen by [snapshot]; never read before *)
  }

  type t = { rows : row list (* sorted by key, unique by construction *) }

  let sort_rows rows = List.sort (fun a b -> S.compare_key a.key b.key) rows

  let register entries =
    let keys = List.map (fun (k, _, _) -> k) entries |> List.sort S.compare_key in
    let rec first_dup = function
      | a :: b :: _ when S.compare_key a b = 0 -> Some a
      | _ :: rest -> first_dup rest
      | [] -> None
    in
    match first_dup keys with
    | Some k -> Error ("duplicate key refused (write functionality): " ^ S.show_key k)
    | None -> (
        let neither =
          List.find_opt
            (fun (_, d, p) ->
              (match d with None -> true | Some _ -> false)
              && match p with None -> true | Some _ -> false)
            entries
        in
        match neither with
        | Some (k, _, _) ->
            Error ("a key with neither declaration nor probe is a claim nobody made: " ^ S.show_key k)
        | None ->
            Ok
              {
                rows =
                  sort_rows
                    (List.map (fun (key, decl, probe) -> { key; decl; probe; obs = None }) entries);
              })

  let snapshot t =
    {
      rows =
        List.map
          (fun r ->
            match r.probe with
            | None -> r
            | Some p -> { r with obs = (try p () with _ -> None) })
          t.rows;
    }

  let find t k = List.find_opt (fun r -> S.compare_key r.key k = 0) t.rows

  (* The ONLY reader: probe answer, else declaration, else None. *)
  let status t k =
    match find t k with
    | None -> None
    | Some r -> ( match r.obs with Some c -> Some c | None -> r.decl)

  (* Both defined and differing — both directions, sorted (rows are). *)
  let residue t =
    List.filter_map
      (fun r ->
        match (r.decl, r.obs) with
        | Some d, Some o when not (S.equal_claim d o) -> Some (r.key, d, o)
        | _ -> None)
      t.rows

  let unknown t ~claimed =
    List.filter (fun k -> find t k = None) claimed |> List.sort_uniq S.compare_key

  (* Meta-falsification overlay. On a known key: replace the observation.
     On an unknown key: add an observation-only row (register would refuse
     a neither-row; an injected observation is, by definition, observed). *)
  let inject t k c =
    match find t k with
    | Some _ ->
        {
          rows =
            List.map
              (fun r -> if S.compare_key r.key k = 0 then { r with obs = Some c } else r)
              t.rows;
        }
    | None -> { rows = sort_rows ({ key = k; decl = None; probe = None; obs = Some c } :: t.rows) }

  type report = { rows : int; probed : int; stale : int; unknown : int }

  let report (t : t) ~claimed =
    {
      rows = List.length t.rows;
      probed =
        List.length (List.filter (fun r -> match r.probe with Some _ -> true | None -> false) t.rows);
      stale = List.length (residue t);
      unknown = List.length (unknown t ~claimed);
    }
end
