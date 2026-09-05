(* The corpus render differential. See wiki_baseline.mli.

   The whole design turns on the second digest. With only a render digest,
   an edited document and a drifted renderer look identical, and the only
   way to make the checker green is to re-baseline — which silently
   accepts whatever changed. Carrying the content digest lets the checker
   say "the source moved, so I am not judging this render", which is the
   honest answer and the one that cannot be gamed. *)

type entry = { render_digest : string; content_digest : string; path : string }

type verdict =
  | Checked
  | Drifted of string * string
  | Edited_since
  | Unlisted

type outcome = { path : string; verdict : verdict }

(* One digest implementation in the repository: the harness's own. *)
let digest value = Wiki_digest.sha256 value

let build documents =
  List.sort
    (fun (a : entry) (b : entry) -> compare a.path b.path)
    (List.map
       (fun (path, content, render) ->
         { render_digest = digest render; content_digest = digest content; path })
       documents)

let to_lines entries =
  List.sort compare
    (List.map
       (fun (e : entry) ->
         Printf.sprintf "%s %s %s" e.render_digest e.content_digest e.path)
       entries)

let of_lines lines =
  List.sort
    (fun (a : entry) (b : entry) -> compare a.path b.path)
    (List.filter_map
       (fun line ->
         match String.split_on_char ' ' (String.trim line) with
         | [ render_digest; content_digest; path ] when path <> "" ->
             Some { render_digest; content_digest; path }
         | _ -> None)
       lines)

let check_one ~baseline ~path ~content ~render =
  match List.find_opt (fun (e : entry) -> e.path = path) baseline with
  | None -> { path; verdict = Unlisted }
  | Some entry ->
      if digest content <> entry.content_digest then { path; verdict = Edited_since }
      else
        let actual = digest render in
        if actual = entry.render_digest then { path; verdict = Checked }
        else { path; verdict = Drifted (entry.render_digest, actual) }

let check ~baseline documents =
  List.map
    (fun (path, content, render) -> check_one ~baseline ~path ~content ~render)
    documents

let drift outcomes =
  List.filter_map
    (fun outcome ->
      match outcome.verdict with
      | Drifted (expected, actual) ->
          Some
            (Printf.sprintf "%s: render drifted (baseline %s, now %s)" outcome.path
               expected actual)
      | Checked | Edited_since | Unlisted -> None)
    outcomes
