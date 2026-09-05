(* The acceptance ratchet for the render baseline.

   `gen_render_baseline` had solid R19 discipline — unknown flags refused,
   validate-before-write, an atomic rename, a refusal when the corpus cannot
   be determined — but no per-diff CLASSIFICATION. Its only content guard was
   a floor on document COUNT, so a change that gutted a hundred pages while
   keeping the count would have been accepted in silence.

   That is the gap the fractal-evidence-orientation skill's own acceptance
   table describes and nothing enforced: acceptance is a privileged operation
   and must be classified, never blanket. Re-pinning 240 documents in one
   command is exactly where a silent regression enters, and re-pinning is the
   moment nobody re-reads the diff.

   The classes below are ordered by how much trust each requires. The
   load-bearing one is REMOVED: a page that stopped rendering looks identical
   to a page that was deliberately deleted, and a regression looks exactly
   like intent. So removals block by default and need an explicit
   acknowledgement — which is a claim the operator makes, recorded in the
   command line, rather than an inference the tool draws. *)

type delta =
  | Unchanged
  | Added of string          (* a page that renders now and did not before *)
  | Removed of string        (* a page that rendered before and does not now *)
  | Source_only of string    (* the source moved, the render did not — a no-op render *)
  | Rendered of string       (* the render moved: the reviewable, expected case *)

type verdict = Auto | Review | Block

(* A baseline line is `<source_digest> <render_digest> <path>`. A line that
   does not parse is not skipped: an unreadable baseline entry means the
   comparison is over an unknown population, and a ratchet over an unknown
   population is decoration. *)
let parse_line line =
  match String.split_on_char ' ' (String.trim line) with
  | [ source; render; path ] when String.length source = 64 && String.length render = 64 ->
      Ok (path, (source, render))
  | _ -> Error line

let parse text =
  let lines =
    String.split_on_char '\n' text |> List.filter (fun l -> String.trim l <> "")
  in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | line :: rest -> (
        match parse_line line with
        | Ok entry -> loop (entry :: acc) rest
        | Error bad ->
            Error
              (Printf.sprintf
                 "unparseable baseline line (%d chars): %S — refusing to classify a diff \
                  over an unknown population"
                 (String.length bad)
                 (if String.length bad > 60 then String.sub bad 0 60 ^ "…" else bad)))
  in
  loop [] lines

let classify ~before ~after =
  let paths =
    List.sort_uniq compare (List.map fst before @ List.map fst after)
  in
  List.filter_map
    (fun path ->
      match (List.assoc_opt path before, List.assoc_opt path after) with
      | None, None -> None
      | None, Some _ -> Some (Added path)
      | Some _, None -> Some (Removed path)
      | Some (s0, r0), Some (s1, r1) ->
          if s0 = s1 && r0 = r1 then Some Unchanged
          else if r0 = r1 then Some (Source_only path)
          else Some (Rendered path))
    paths

(* Removals block; everything else is reviewable. Additions do NOT block — a
   new page cannot regress an old one — but they are not silent either, since
   the counts are always printed. *)
let verdict ?(accept_removals = false) deltas =
  let removed = List.filter (function Removed _ -> true | _ -> false) deltas in
  if removed <> [] && not accept_removals then Block
  else if List.exists (function Unchanged -> false | _ -> true) deltas then Review
  else Auto

let verdict_name = function Auto -> "auto" | Review -> "review" | Block -> "block"

(* Exit codes are the interface for automation: 0 auto-acceptable, 1 needs
   review, 2 must not be accepted (R19 clause 4 — the verdict IS the exit
   code). *)
let exit_code = function Auto -> 0 | Review -> 1 | Block -> 2

let name = function
  | Unchanged -> "unchanged"
  | Added p -> "added " ^ p
  | Removed p -> "REMOVED " ^ p
  | Source_only p -> "source-only " ^ p
  | Rendered p -> "rendered " ^ p

let render deltas =
  let count f = List.length (List.filter f deltas) in
  let unchanged = count (function Unchanged -> true | _ -> false) in
  let added = count (function Added _ -> true | _ -> false) in
  let removed = count (function Removed _ -> true | _ -> false) in
  let source_only = count (function Source_only _ -> true | _ -> false) in
  let rendered = count (function Rendered _ -> true | _ -> false) in
  let b = Buffer.create 512 in
  Printf.bprintf b
    "triage: %d unchanged, %d rendered, %d source-only, %d added, %d REMOVED\n" unchanged
    rendered source_only added removed;
  (* Name the removals — the fix is a lookup, not a hunt. Bounded, with the
     remainder disclosed, so a mass removal cannot push the verdict off the
     end of a terminal. *)
  let named = List.filter (function Removed _ | Added _ -> true | _ -> false) deltas in
  List.iteri
    (fun i d -> if i < 10 then Printf.bprintf b "  %s\n" (name d))
    named;
  let hidden = List.length named - 10 in
  if hidden > 0 then Printf.bprintf b "  … %d more\n" hidden;
  Buffer.contents b
