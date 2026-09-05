(* HW.1.4.1 — the visibility split. See the mli: three states, mutually
   exclusive and total, decided by a closed sum rather than two booleans
   that would admit a fourth state nobody defined. *)

type t = Draft | Unlisted | Listed

let name = function Draft -> "draft" | Unlisted -> "unlisted" | Listed -> "listed"

let of_page (p : Hermes_wiki.page) =
  let m = p.Hermes_wiki.meta in
  match m.Hermes_wiki.visibility with
  | "draft" -> Draft
  | "unlisted" -> Unlisted
  | "listed" -> Listed
  | _ -> (
      (* no explicit visibility: fall back to the editorial status, which
         is what the corpus has always used *)
      match m.Hermes_wiki.status with "draft" -> Draft | _ -> Listed)

let in_build = function Draft -> false | Unlisted | Listed -> true
let in_index = function Listed -> true | Draft | Unlisted -> false
let in_search = in_index

let known = [ ""; "draft"; "unlisted"; "listed" ]

let malformed (m : Hermes_wiki.model) =
  m.Hermes_wiki.pages
  |> List.filter_map (fun (p : Hermes_wiki.page) ->
         let v = p.Hermes_wiki.meta.Hermes_wiki.visibility in
         if List.mem v known then None
         else
           Some
             (Printf.sprintf
                "unknown visibility %S on %s — not silently listed; the three states are draft, unlisted, listed"
                v p.Hermes_wiki.slug))
  |> List.sort_uniq compare

let census (m : Hermes_wiki.model) =
  let of_state s =
    ( s,
      m.Hermes_wiki.pages
      |> List.filter_map (fun (p : Hermes_wiki.page) ->
             if of_page p = s then Some p.Hermes_wiki.slug else None)
      |> List.sort_uniq compare )
  in
  [ of_state Draft; of_state Unlisted; of_state Listed ]
