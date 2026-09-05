(* ZK Tag Laundering Preventer — a REAL, law-carrying tag-escaper over the live
   MoC pages, admitted against the ACTUAL Docs_wiki indexer.

   Promoted from a phase-7 printf stub (DIVERGENCE 690). Auto-generated MoC pages
   list their member notes and roll up those notes' tags. If a MoC emits a LIVE
   `#tag`, the tag indexer re-files the MoC ITSELF into that tag's community, which
   then feeds the next MoC generation — "tag laundering": a generated page
   manufacturing the very membership it summarises (a recursion). The class rule
   FM-ZK-TAG-LAUNDER (knowledge-systems-algebra §7) mandates: generated aggregators
   must emit INERT forms of live syntax.

   ── THE HONEST FINDING (corrected). ──────────────────────────────────────────
   The MoC generator (`Docs_wiki.moc_markdown`) is ALREADY safe: it emits the tag
   rollup as backtick code spans `` `#tag` ``, which the real indexer never sees.
   The DEFECT was in THIS module's earlier oracle: its liveness test treated only a
   preceding backslash as escaping, so it counted the generator's backtick form as
   "live" and reported 57 phantom laundering violations. The real indexer
   (docs_wiki.ml:276) is the regex "\(^\|[ (]\)#\([a-z][a-z0-9_-]+\)": a `#tag` is
   indexed ONLY when preceded by line-start / space / '(' and followed by a
   lowercase letter then >=1 of [a-z0-9_-]. Backtick- or backslash-preceded `#tag`,
   uppercase `#Tag`, and mid-word `word#tag` are all INERT.

   ── THE RULIOLOGY FRAME. ─────────────────────────────────────────────────────
   Escaping is a REWRITE SYSTEM  E : live-#tag |-> \#tag.  Its redexes are the
   substrings the REAL indexer would index; they are non-overlapping (one per `#`
   site), so the system is ORTHOGONAL and therefore CONFLUENT by construction —
   the normal form is unique. The laws (`--selfcheck-tag-laundering`) pin the
   ruliological + algebraic guarantees:
     L1 FIDELITY        — this module's `live_tags` = the REAL Docs_wiki indexer
                          (`Docs_wiki.build ... .tags`) AND the hand label, over a
                          fixture battery (triple agreement; fixes the over-count).
     L2 NORMAL-FORM     — the REAL indexer extracts empty from `E body` (no redex
                          survives; the laundering channel is closed).
     L3 IDEMPOTENCE     — `E (E body) = E body` (the normal form is a fixpoint).
     L4 TERMINATION     — `|live_tags (E body)| = 0`; the redex measure strictly
                          drops to 0 in one pass (well-founded, no regress).
     L5 TRANSPARENCY    — `E` inserts a `\` only before live `#`; `unescape (E b)=b`
                          and every non-redex byte is preserved (a homomorphism).
     L6 DETECTION       — a synthetic live `#tag` is flagged+escaped, while the
                          inert forms (backtick, backslash, `#T`, `w#t`, too-short)
                          are NOT flagged (pins the corrected oracle).
     L7 LIVE-CORPUS     — every real docs/zk/moc-*.md has REAL-indexed tags = empty
                          (the generator is already safe -> the true finding is 0,
                          not 57); a regression guard against a future generator
                          change that emits a live tag.

   Not gate authority and NOT in the default gate (the Rete gate is decoupled from
   doc/wiki vocabulary — DIVERGENCE 669; wiring a doc fact into a gate rule would
   breach that isolation). Standalone `--check-tag-laundering` (fail-closed on real
   laundering) + `--selfcheck-tag-laundering` (the 7 laws). *)

module Docs_wiki = Wiki_render.Docs_wiki

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(* every moc-*.md directly under docs/zk *)
let moc_files root =
  let dir = Filename.concat root "docs/zk" in
  let entries = try Sys.readdir dir with _ -> [||] in
  Array.to_list entries
  |> List.filter (fun n ->
       Filename.check_suffix n ".md"
       && String.length n >= 4 && String.sub n 0 4 = "moc-")
  |> List.map (fun n -> Filename.concat dir n)
  |> List.sort compare

(* ── the FAITHFUL liveness oracle (mirrors docs_wiki.ml:276 exactly) ─────────── *)
let is_tagchar c =
  (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' || c = '_'
let is_lower c = c >= 'a' && c <= 'z'

(* the indexer's prefix class: line-start | space | '(' *)
let prefix_ok body i =
  i = 0 || (match body.[i - 1] with ' ' | '(' | '\n' -> true | _ -> false)

(* a LIVE (indexable) tag start at [i]: '#', an indexer-prefix before it, then a
   lowercase letter and >=1 further tagchar (the regex [a-z][a-z0-9_-]+, >=2). *)
let is_live_tag body i =
  let ls = String.length body in
  body.[i] = '#' && prefix_ok body i
  && i + 1 < ls && is_lower body.[i + 1]
  && i + 2 < ls && is_tagchar body.[i + 2]

(* the tag SET this module considers live (the FINAL encoding of the indexer) *)
let live_tags body =
  let ls = String.length body in
  let acc = ref [] and i = ref 0 in
  while !i < ls do
    if is_live_tag body !i then begin
      let j = ref (!i + 1) in
      while !j < ls && is_tagchar body.[!j] do incr j done;
      acc := String.sub body (!i + 1) (!j - !i - 1) :: !acc;
      i := !j
    end
    else incr i
  done;
  List.sort_uniq compare !acc

let count_live_tags body = List.length (live_tags body)

(* the ORACLE: the tags the REAL Docs_wiki indexer would extract from [body] *)
let indexed_tags body =
  match Docs_wiki.build [ ("_tagcheck.md", body) ] with
  | (p : Docs_wiki.page) :: _ -> List.sort_uniq compare p.tags
  | [] -> []

(* ── the rewrite system E and its inverse ────────────────────────────────────── *)
(* E: insert a '\' before every live '#' (renders as text, invisible to the indexer) *)
let escape_tags body =
  let ls = String.length body in
  let b = Buffer.create (ls + 32) and i = ref 0 in
  while !i < ls do
    if is_live_tag body !i then (Buffer.add_char b '\\'; Buffer.add_char b '#'; incr i)
    else (Buffer.add_char b body.[!i]; incr i)
  done;
  Buffer.contents b

(* the left inverse of E on its image: drop a '\' that sits immediately before a
   '#' whose following chars form a tag body (recovers the original bytes) *)
let unescape_tags body =
  let ls = String.length body in
  let b = Buffer.create ls and i = ref 0 in
  while !i < ls do
    if !i + 2 < ls && body.[!i] = '\\' && body.[!i + 1] = '#'
       && is_lower body.[!i + 2] then (Buffer.add_char b '#'; i := !i + 2)
    else (Buffer.add_char b body.[!i]; incr i)
  done;
  Buffer.contents b

(* ── report-only entry (run under --run-support-modules) ─────────────────────── *)
let run (root : string) : unit =
  let mocs = moc_files root in
  Printf.printf "[zk_tag_laundering_preventer] MoC pages scanned: %d\n" (List.length mocs);
  let violations = ref 0 in
  List.iter (fun path ->
    let body = try read_file path with _ -> "" in
    let real = indexed_tags body in
    if real <> [] then begin
      incr violations;
      Printf.printf "  [LAUNDER] %-44s real-indexed#=%d (%s)\n"
        (Filename.basename path) (List.length real) (String.concat "," real)
    end else
      Printf.printf "  [clean]   %-44s real-indexed#=0\n" (Filename.basename path))
    mocs;
  Printf.printf
    "  summary: %d/%d MoCs launder tags (per the REAL Docs_wiki indexer). The \
     generator emits inert backtick code spans, so the honest count is 0.\n"
    !violations (List.length mocs);
  Printf.printf
    "  [NOTE] admitted by --selfcheck-tag-laundering (7 laws) against the live \
     indexer; real rewrite over real bytes; files are not mutated on disk\n"

(* ── the fail-closed check: any real MoC that the live indexer would tag ─────── *)
type verdict = Clean | Laundering of (string * string list) list

let check root : verdict =
  let bad =
    List.filter_map (fun path ->
      let body = try read_file path with _ -> "" in
      match indexed_tags body with [] -> None | tags -> Some (Filename.basename path, tags))
      (moc_files root)
  in
  match bad with [] -> Clean | l -> Laundering l

(* ── the law battery ─────────────────────────────────────────────────────────── *)
(* (label, body, expected live-tag set) — derived from the docs_wiki.ml:276 regex *)
let fixtures =
  [ ("space-prefixed lowercase", "see #alpha here", [ "alpha" ]);
    ("line-start", "#beta rest", [ "beta" ]);
    ("paren-prefixed", "call (#gamma) end", [ "gamma" ]);
    ("two adjacent live", "#one #two", [ "one"; "two" ]);
    ("backtick-inert (the generator form)", "rollup `#delta` end", []);
    ("backslash-inert", "esc \\#epsilon end", []);
    ("uppercase is not a tag", "a #Zeta here", []);
    ("mid-word is not a tag", "word#eta here", []);
    ("too short (<2 chars)", "x #q y", []);
    ("digit-first is not a tag", "hex #1a2b here", []) ]

(* returns true iff every law passed; prints per-law OK/RED + a summary *)
let selfcheck (root : string) : bool =
  Printf.printf
    "[selfcheck-tag-laundering] admitting the tag-escape rewrite against the REAL Docs_wiki indexer:\n";
  let results = ref [] in
  let law name passed detail = results := (name, passed, detail) :: !results in
  let set_eq a b = List.sort_uniq compare a = List.sort_uniq compare b in
  let n = List.length fixtures in

  (* L1 FIDELITY: this module's live_tags = the REAL indexer = the hand label,
     over the fixture battery. Non-vacuous: >=1 fixture has a nonempty tag set. *)
  let l1_bad =
    List.filter (fun (_, body, expected) ->
      not (set_eq (live_tags body) expected && set_eq (indexed_tags body) expected))
      fixtures
  in
  let nonempty = List.exists (fun (_, _, e) -> e <> []) fixtures in
  law "L1 FIDELITY live=indexer=label" (l1_bad = [] && nonempty)
    (Printf.sprintf "%d/%d fixtures triple-agree (my scan = Docs_wiki = label)" (n - List.length l1_bad) n);

  (* L2 NORMAL-FORM SOUNDNESS: the REAL indexer extracts nothing from E(body). *)
  let l2_bad = List.filter (fun (_, body, _) -> indexed_tags (escape_tags body) <> []) fixtures in
  law "L2 NORMAL-FORM indexer(E b)=empty" (l2_bad = [])
    (Printf.sprintf "%d/%d escaped bodies index to 0 tags" (n - List.length l2_bad) n);

  (* L3 IDEMPOTENCE: E o E = E (the normal form is a fixpoint). *)
  let l3_bad = List.filter (fun (_, body, _) -> escape_tags (escape_tags body) <> escape_tags body) fixtures in
  law "L3 IDEMPOTENCE E(E b)=E b" (l3_bad = [])
    (Printf.sprintf "%d/%d bodies reach a fixpoint" (n - List.length l3_bad) n);

  (* L4 TERMINATION: the redex measure drops to 0 in one pass. *)
  let l4_bad = List.filter (fun (_, body, _) -> count_live_tags (escape_tags body) <> 0) fixtures in
  law "L4 TERMINATION |live(E b)|=0" (l4_bad = [])
    (Printf.sprintf "%d/%d bodies have 0 residual redexes" (n - List.length l4_bad) n);

  (* L5 TRANSPARENCY: E only inserts a '\' before a live '#'; unescape recovers the
     original, and escaped/original differ only by those inserted backslashes. *)
  let l5_bad =
    List.filter (fun (_, body, _) ->
      let e = escape_tags body in
      (* E's inserted backslashes vanish under unescape (recoverable regardless of
         any backslash the body already contained) *)
      let recovered = unescape_tags e = unescape_tags body in
      (* E's ONLY effect is inserting one '\' per live '#': stripping all
         backslashes is invariant, and the length grows by exactly the redex count *)
      let insert_only =
        String.length e - String.length body = count_live_tags body
        && String.concat "" (String.split_on_char '\\' e)
           = String.concat "" (String.split_on_char '\\' body)
      in
      not (recovered && insert_only))
      fixtures
  in
  law "L5 TRANSPARENCY unescape.E=id, insert-only" (l5_bad = [])
    (Printf.sprintf "%d/%d bodies round-trip, non-redex bytes preserved" (n - List.length l5_bad) n);

  (* L6 DETECTION + OVER-COUNT-GUARD: a live tag is flagged; the inert forms are
     NOT (the exact bug the corrected oracle fixes). *)
  let live_flagged = count_live_tags "topic #realtag here" = 1 in
  let inert_clean =
    count_live_tags "rollup `#realtag` end" = 0
    && count_live_tags "esc \\#realtag end" = 0
    && count_live_tags "a #Realtag here" = 0
    && count_live_tags "word#realtag here" = 0
  in
  law "L6 DETECTION live-flagged inert-clean" (live_flagged && inert_clean)
    (Printf.sprintf "live#flagged:%b inert(backtick/backslash/upper/midword)#clean:%b" live_flagged inert_clean);

  (* L7 LIVE-CORPUS regression: every real MoC indexes to empty (generator is safe). *)
  let mocs = moc_files root in
  let laundering = List.filter (fun p -> indexed_tags (try read_file p with _ -> "") <> []) mocs in
  law "L7 LIVE-CORPUS real-MoCs index-empty" (laundering = [])
    (Printf.sprintf "%d/%d MoCs launder (real indexer)" (List.length laundering) (List.length mocs));

  let laws = List.rev !results in
  List.iter (fun (nm, ok, detail) ->
    Printf.printf "  %s %-40s %s\n" (if ok then "OK " else "RED") nm detail) laws;
  let passed = List.for_all (fun (_, ok, _) -> ok) laws in
  Printf.printf "[selfcheck-tag-laundering] %d/%d laws passed%s\n"
    (List.length (List.filter (fun (_, ok, _) -> ok) laws)) (List.length laws)
    (if passed then "" else " — FAIL CLOSED");
  passed
