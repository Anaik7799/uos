(* Schema backfill — the backfiller actor's IO shell around the pure core
   (Backfill.propose). Report-only by default: proposals with evidence,
   Asks for a human. `--apply N` (the actor's GUARDED command) rewrites at
   most N pages' frontmatter with the Set proposals only — a deliberate,
   reviewed act, like a re-pin: run the battery and the audit afterwards.

   R16: `created` comes from git first-add, read here and passed in;
   the pure core never invents a value. *)

let required = [ "ktype"; "maturity"; "domain"; "topics"; "created" ]

let first_add path =
  let cmd = Printf.sprintf "git log --diff-filter=A --follow --format=%%as -- %s" (Filename.quote path) in
  let ic = Unix.open_process_in cmd in
  let rec last acc = match input_line ic with l -> last (Some l) | exception End_of_file -> acc in
  let date = last None in
  (match Unix.close_process_in ic with _ -> ());
  match date with Some d when String.length d = 10 -> Some d | _ -> None

let missing_of (p : Hermes_wiki.page) =
  let m = p.Hermes_wiki.meta in
  List.filter
    (fun f ->
      match f with
      | "ktype" -> m.Hermes_wiki.ktype = ""
      | "maturity" -> m.Hermes_wiki.maturity = ""
      | "domain" -> m.Hermes_wiki.domain = ""
      | "topics" -> m.Hermes_wiki.topics = []
      | "created" -> m.Hermes_wiki.created = ""
      | _ -> false)
    required

(* The frontmatter keys a document ACTUALLY carries, read from the file
   because [p.raw] is the body with the block already stripped. Per KEY,
   not per block: a page can carry frontmatter and still never author
   `status:`, and [meta_of] would hand back its default "published" —
   which the pure core must not be allowed to cite. *)
let authored_keys path =
  (* guarded around the WHOLE body (R19.1): `match open_in with |
     exception` catches the scrutinee only, and open_in_bin succeeds on a
     directory — in_channel_length then raises out of here. *)
  match
    try
      let ic = open_in_bin path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr ic)
        (fun () -> Some (really_input_string ic (in_channel_length ic)))
    with _ -> None
  with
  | Some s ->
      (match String.split_on_char '\n' s with
      | "---" :: rest ->
          let rec go acc = function
            | "---" :: _ -> List.rev acc
            | line :: more -> (
                match String.index_opt line ':' with
                | Some i -> go (String.trim (String.sub line 0 i) :: acc) more
                | None -> go acc more)
            | [] -> [] (* unterminated block: no authored keys, fail closed *)
          in
          go [] rest
      | _ -> [])
  | None -> []

let facts_of (p : Hermes_wiki.page) =
  let authored = authored_keys p.Hermes_wiki.path in
  {
    Backfill.slug = p.Hermes_wiki.slug;
    group = p.Hermes_wiki.group;
    authored;
    ntype = (if List.mem "type" authored then p.Hermes_wiki.meta.Hermes_wiki.ntype else "");
    status = (if List.mem "status" authored then p.Hermes_wiki.meta.Hermes_wiki.status else "");
    tags = p.Hermes_wiki.tags;
    first_add = first_add p.Hermes_wiki.path;
    missing = missing_of p;
  }

(* insert set-fields into the page's frontmatter, before the closing --- *)
let apply_to_source raw sets =
  let lines = String.split_on_char '\n' raw in
  match lines with
  | "---" :: rest ->
      let rec split_front acc = function
        | "---" :: tail -> Some (List.rev acc, tail)
        | l :: tail -> split_front (l :: acc) tail
        | [] -> None
      in
      (match split_front [] rest with
      | None -> None
      | Some (front, body) ->
          let added =
            List.map
              (function
                | Backfill.Set { field; value; _ } -> Printf.sprintf "%s: %s" field value
                | Backfill.Ask _ -> assert false)
              sets
          in
          Some (String.concat "\n" (("---" :: front) @ added @ ("---" :: body))))
  | _ -> None (* no frontmatter block: worklisted, never synthesized here *)

let usage () =
  prerr_endline
    "usage: schema_backfill [--apply N]\n\
    \  (no flag)   report-only: print every proposal and Ask\n\
    \  --apply N   write the Set proposals for at most N pages (deliberate)";
  exit 2

let () =
  (* R19 — an unknown flag is REFUSED, never ignored. `--aply 5` used to
     fall through and silently run report-only with exit 0, so an
     operator could not tell a refused flag from a completed run. *)
  let apply_n =
    match Array.to_list Sys.argv with
    | [ _ ] -> None
    | [ _; "--apply"; n ] -> (
        match int_of_string_opt n with
        | Some v when v > 0 -> Some v
        | _ ->
            prerr_endline "--apply takes a positive count";
            exit 2)
    | _ -> usage ()
  in
  let files = Hermes_wiki.read_tracked "modules/hermes_wiki/pages" @ Hermes_wiki.read_tracked "docs/hermes" in
  let m = Hermes_wiki.build ~read_source:Hermes_wiki.read_source_file files in
  let incomplete =
    List.filter (fun p -> missing_of p <> []) m.Hermes_wiki.pages
    |> List.sort (fun a b -> compare a.Hermes_wiki.slug b.Hermes_wiki.slug)
  in
  Printf.printf "[backfiller] %d of %d pages incomplete\n" (List.length incomplete)
    (List.length m.Hermes_wiki.pages);
  match apply_n with
  | None ->
      List.iter
        (fun p ->
          let ps = Backfill.propose (facts_of p) in
          List.iter (fun pr -> print_endline ("  " ^ Backfill.render ~slug:p.Hermes_wiki.slug pr)) ps)
        incomplete;
      print_endline "[backfiller] report-only. --apply N writes the Set proposals (deliberate)."
  | Some n ->
      let appliable =
        List.filter (fun p -> p.Hermes_wiki.meta.Hermes_wiki.has_frontmatter) incomplete
      in
      Printf.printf "[backfiller] %d appliable (frontmatter present); %d worklisted without one\n"
        (List.length appliable)
        (List.length incomplete - List.length appliable);
      let batch = List.filteri (fun i _ -> i < n) appliable in
      let applied =
        List.filter_map
          (fun p ->
            let sets =
              List.filter
                (function Backfill.Set _ -> true | Backfill.Ask _ -> false)
                (Backfill.propose (facts_of p))
            in
            if sets = [] then None
            else
              (* p.raw is the BODY (frontmatter already stripped by the
                 model); the rewrite needs the file as authored. *)
              (* R19.1 — guarded around the WHOLE body. This sits INSIDE
                 the --apply loop, so an escape here aborts a batch that
                 has already renamed some documents, leaving no record of
                 which. The sibling `authored_keys` was fixed for the same
                 shape; this one was missed. *)
              let source =
                try
                  let ic = open_in_bin p.Hermes_wiki.path in
                  Fun.protect
                    ~finally:(fun () -> close_in_noerr ic)
                    (fun () -> Some (really_input_string ic (in_channel_length ic)))
                with _ -> None
              in
              match Option.bind source (fun s -> apply_to_source s sets) with
              | None ->
                  Printf.printf "  SKIPPED %-40s (unreadable, or no frontmatter block)\n"
                    p.Hermes_wiki.slug;
                  None
              | Some raw' ->
                  (* Write via a temp file and rename: [open_out]
                     truncates in place, so an interrupt mid-batch would
                     leave a TRUNCATED document. rename(2) is atomic
                     within a filesystem, so a reader sees the old bytes
                     or the new ones, never half of either. *)
                  let tmp = p.Hermes_wiki.path ^ ".backfill.tmp" in
                  let oc = open_out_bin tmp in
                  output_string oc raw';
                  close_out oc;
                  Sys.rename tmp p.Hermes_wiki.path;
                  Some (p.Hermes_wiki.slug, List.length sets))
          batch
      in
      List.iter (fun (s, k) -> Printf.printf "  applied %d field(s) to %s\n" k s) applied;
      (try
         if not (Sys.file_exists "state") then Unix.mkdir "state" 0o755;
         let oc =
           open_out_gen [ Open_append; Open_creat ] 0o644 "state/wiki-audit.otel.jsonl"
         in
         let t = Unix.gmtime (Unix.time ()) in
         let ts =
           Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (t.Unix.tm_year + 1900)
             (t.Unix.tm_mon + 1) t.Unix.tm_mday t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec
         in
         output_string oc
           (Wiki_otel.render
              (Wiki_otel.record ~ts ~severity:Wiki_otel.Info ~body:"backfill batch applied"
                 ~attrs:
                   [ ("actor", "backfiller");
                     ("pages", string_of_int (List.length applied)) ])
           ^ "\n");
         close_out oc
       with _ -> ());
      Printf.printf
        "[backfiller] APPLIED %d page(s). Now: re-run the battery, re-pin edited pages, and\n\
        \  re-pin the schema_debt gauge DOWNWARD with wiki_audit --pin (all deliberate).\n"
        (List.length applied)
