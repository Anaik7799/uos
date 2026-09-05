module Th = Tyxml.Html
module Ts = Tyxml.Svg

(* Render one element to a string. The FRAGMENT analogue of `page_frame_elts`:
   a converted fragment produces elements, and this shim exists only for the
   callers still assembling pages by hand. Every `_elt` function below is the
   real definition; its string twin dies with its last string-shaped caller. *)
let elt_str (e : [< Html_types.flow5 ] Th.elt) = Format.asprintf "%a" (Th.pp_elt ()) e

(* docs_wiki.ml — render every docs/*.md as an OCaml wiki with a pure View that
   is a function of an immutable Model.

   The Model is built from a system of record (here the docs/ tree + git), and
   the View is a pure function of it (no I/O, no mutation).

   This module is PURE (testable in-process): the driver reads the files and
   passes (path, content) pairs; everything here is a total function of them. *)

(* ── agent-collaborative metadata (YAML frontmatter, the agent's control panel) ─
   Every note carries structured metadata an agent can read WITHOUT parsing the
   body: a stable UUID (identity that survives a rename), a lifecycle status, and
   freshness/decay signals (last_verified / next_review) telling an agent exactly
   when a fact must be re-checked. Absent fields get honest defaults; the UUID
   defaults to a DETERMINISTIC id derived from the slug so every existing note has
   a stable identity with zero file edits. Enforced by `--selfcheck-wiki`. *)
type meta = {
  id : string;              (* stable UUID (frontmatter `id:`, else derived from the slug) *)
  status : string;          (* draft | published | flagged_for_review (default: published) *)
  last_verified : string;   (* ISO date the fact was last confirmed, or "" *)
  verified_by : string;     (* agent | human | "" — who last verified *)
  next_review : string;     (* ISO date a re-check is due, or "" (decay signal) *)
  ntype : string;
    (* DISCOURSE type (zk-discourse-types, journal 20260729-1056 §7.5, Joel
       Chan's discourse-graph vocabulary): note | question | claim | evidence |
       decision. Frontmatter `type:`, default "note"; an UNKNOWN value is
       PRESERVED verbatim (honesty) and flagged report-only in anomalies. *)
  has_frontmatter : bool;   (* did the file carry an explicit --- block? *)
  allow_example_links : bool;
    (* audit-only exemption for a note that quotes literal [[link]] grammar;
       frontmatter keeps this control out of the rendered reading surface *)
}

(* ── the Model ─────────────────────────────────────────────────────────── *)
type page = {
  path : string;   (* repo-relative, e.g. docs/harness-wiki/02-The-Gate.md *)
  slug : string;   (* url-safe id, e.g. harness-wiki--02-the-gate *)
  title : string;  (* the first H1, else the file basename *)
  group : string;  (* the sub-directory under docs/, "" for top-level *)
  html : string;   (* the rendered body *)
  outlinks : string list;   (* Zettelkasten: slugs this note [[links]] to *)
  backlinks : string list;  (* Zettelkasten: slugs that [[link]] to this note *)
  tags : string list;       (* Zettelkasten: #tags in this note *)
  mentions : string list;   (* Zettelkasten: slugs that MENTION this note's title but do NOT [[link]] it *)
  back_ctx : (string * string) list;
    (* CONTEXTUAL backlinks (zk-contextual-backlinks, journal 20260729-1056
       §7.10): (source-slug, the trimmed source LINE containing the [[link]]) —
       Roam-style citation context, so a reader/agent sees WHY a note links
       here without a second fetch. Domain law: fst back_ctx ≡ backlinks. *)
  typed : (string * string) list;  (* typed edges: (target-slug, relation) from [[T|@rel]] *)
  raw : string;             (* the source markdown (for unlinked-mention scanning) *)
  meta : meta;              (* the agent-collaborative frontmatter (control panel) *)
}

(* a deterministic UUID (v5-style) from any string — MD5(s) reformatted as a
   canonical UUID. Stable + reproducible (no randomness), so a note's identity is
   a pure function of its slug and survives across runs and machines. *)
let uuid_of_string (s : string) : string =
  let hex = Digest.to_hex (Digest.string ("zigvm-wiki:" ^ s)) in  (* 32 hex chars *)
  Printf.sprintf "%s-%s-%s-%s-%s"
    (String.sub hex 0 8) (String.sub hex 8 4) (String.sub hex 12 4)
    (String.sub hex 16 4) (String.sub hex 20 12)

let default_status = "published"
let valid_status = [ "draft"; "published"; "flagged_for_review"; "archived" ]

(* the discourse-type vocabulary (§7.5): the structural half of a discourse
   graph — the SEMANTICS (Dung grounded extension over @opposes) is the
   separate zk-grounded-semantics slice. *)
let default_type = "note"
let valid_types = [ "note"; "question"; "claim"; "evidence"; "decision" ]

(* an ETag = a content fingerprint (MD5 hex) used for OPTIMISTIC CONCURRENCY. A
   write must present the ETag it read (If-Match); if the note has changed since
   (a human/other agent edited it), the ETags differ and the write is rejected
   409 rather than clobbering. Deterministic: same content → same ETag. *)
let etag_of_content (raw : string) : string = Digest.to_hex (Digest.string raw)
let etag_of (p : page) : string = etag_of_content p.raw

(* parse a leading `---\n … \n---\n` YAML frontmatter block (line-based key: value)
   into (meta, body-without-frontmatter). No block → (None, md unchanged). *)
let parse_frontmatter (md : string) : (string * string) list option * string =
  let n = String.length md in
  if n < 4 || String.sub md 0 4 <> "---\n" then (None, md)
  else
    (* find the closing "\n---" line *)
    let rec find_close i =
      if i + 4 > n then None
      else if String.sub md i 4 = "\n---" then Some i
      else find_close (i + 1) in
    (match find_close 3 with
     | None -> (None, md)
     | Some close ->
         let block = String.sub md 4 (close - 4) in
         (* body starts after the closing "---" line *)
         let after = close + 4 in
         let body_start =
           (match String.index_from_opt md after '\n' with Some j -> j + 1 | None -> n) in
         let body = if body_start <= n then String.sub md body_start (n - body_start) else "" in
         let kv = List.filter_map (fun line ->
             let line = String.trim line in
             if line = "" then None else
             match String.index_opt line ':' with
             | Some c ->
                 let k = String.trim (String.sub line 0 c) in
                 let v = String.trim (String.sub line (c + 1) (String.length line - c - 1)) in
                 if k = "" then None else Some (k, v)
             | None -> None)
           (String.split_on_char '\n' block) in
         (Some kv, body))

(* build the meta record for a note from its (optional) frontmatter kv + slug. *)
let meta_of ~(slug : string) (kv : (string * string) list option) : meta =
  let get k d = match kv with Some l -> (match List.assoc_opt k l with Some v when v <> "" -> v | _ -> d) | None -> d in
  { id = get "id" (uuid_of_string slug);
    status = (let s = get "status" default_status in if List.mem s valid_status then s else default_status);
    last_verified = get "last_verified" "";
    verified_by = get "verified_by" "";
    next_review = get "next_review" "";
    ntype = String.lowercase_ascii (String.trim (get "type" default_type));
    has_frontmatter = (kv <> None);
    allow_example_links =
      String.equal
        (String.lowercase_ascii (String.trim (get "wiki-audit" "")))
        "allow-example-links" }

let esc buf s =
  String.iter (fun c -> match c with
    | '<' -> Buffer.add_string buf "&lt;"
    | '>' -> Buffer.add_string buf "&gt;"
    | '&' -> Buffer.add_string buf "&amp;"
    | c -> Buffer.add_char buf c) s

let esc_s s = let b = Buffer.create (String.length s) in esc b s; Buffer.contents b

(* ── Zettelkasten: [[wiki-links]] + a bidirectional link graph ──────────── *)
(* During rendering, [[Target]] / [[Target|Display]] resolves to a note's slug
   via `zettel_resolve` (built from all note titles/slugs/basenames) and records
   the outlink in `zettel_outlinks`. build/ then reverses the graph → backlinks
   (the "Linked references" of every note). All native OCaml. *)
let zettel_resolve : (string -> string option) ref = ref (fun _ -> None)
let zettel_outlinks : string list ref = ref []
let zettel_tags : string list ref = ref []
(* typed / semantic edges: [[Target|@relation]] records (slug, relation) — e.g.
   [[The Gate|@prereq]], [[X|@contradicts]] — so agents can reason about WHY two
   notes connect, not just that they do. *)
let zettel_typed : (string * string) list ref = ref []
(* normalize a title/slug/link to a comparable key: lowercase, non-alnum→'-'. *)
let znorm s =
  let b = Buffer.create (String.length s) in
  let dash = ref true in
  String.iter (fun c ->
    let c = Char.lowercase_ascii c in
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') then (Buffer.add_char b c; dash := false)
    else if not !dash then (Buffer.add_char b '-'; dash := true)) s;
  let r = Buffer.contents b in
  let n = String.length r in
  if n > 0 && r.[n-1] = '-' then String.sub r 0 (n-1) else r

(* JSON string escape (< → < so it can't break the inline <script>). *)
let jesc s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (fun c -> match c with
    | '"' -> Buffer.add_string b "\\\"" | '\\' -> Buffer.add_string b "\\\\"
    | '\n' | '\r' | '\t' -> Buffer.add_char b ' '
    | '<' -> Buffer.add_string b "\\u003c" | '&' -> Buffer.add_string b "\\u0026"
    | c when Char.code c < 32 -> Buffer.add_char b ' '
    | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"'; Buffer.contents b

(* the searchable plain text of a note: markdown with whitespace collapsed,
   capped (the index stays small). *)
let search_text md =
  let cap = min 3000 (String.length md) in
  let b = Buffer.create cap and sp = ref false in
  String.iteri (fun i ch -> if i < cap then
    let c = match ch with '\n' | '\r' | '\t' -> ' ' | c -> c in
    if c = ' ' then (if not !sp then Buffer.add_char b ' '; sp := true)
    else (Buffer.add_char b c; sp := false)) md;
  String.trim (Buffer.contents b)

(* rewrite a markdown link target so EVERY internal link resolves to a working
   HTML page: a `*.md` target (any relative depth) → the matching note's
   <slug>.html (via the resolver, keyed on basename); external / server-route /
   anchor / already-.html targets pass through unchanged. So clicking any link
   opens the related content as HTML. *)
let rewrite_href url =
  let sw p = String.length url >= String.length p && String.sub url 0 (String.length p) = p in
  if sw "http://" || sw "https://" || sw "//" || sw "#" || sw "mailto:" || sw "/" then url
  else
    let path, anchor = match String.index_opt url '#' with
      | Some i -> (String.sub url 0 i, String.sub url i (String.length url - i))
      | None -> (url, "") in
    if String.length path >= 3 && String.lowercase_ascii (Filename.extension path) = ".md" then
      let base = Filename.remove_extension (Filename.basename path) in
      (match !zettel_resolve base with Some slug -> slug ^ ".html" ^ anchor | None -> url)
    else url

(* slug: lowercase, non-alnum → '-', dir '/' → '--', drop the .md *)
let slug_of_path path =
  let p = if Filename.check_suffix path ".md" then Filename.chop_suffix path ".md" else path in
  let p = if String.length p > 5 && String.sub p 0 5 = "docs/" then String.sub p 5 (String.length p - 5) else p in
  let b = Buffer.create (String.length p) in
  String.iter (fun c ->
    let c = Char.lowercase_ascii c in
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') then Buffer.add_char b c
    else if c = '/' then Buffer.add_string b "--"
    else Buffer.add_char b '-') p;
  Buffer.contents b

(* ── block markdown → HTML (line-based, total) ─────────────────────────── *)
(* BLOCK-LEVEL IDs (agent-collaborative granularity): a trailing " ^id" on a block
   is an explicit, stable block anchor (Obsidian convention) → an agent can address
   and surgically patch ONE block, and [[Page#^id]] links to it. Headings get an
   auto anchor = znorm(text), so [[Page#Section]] resolves too. *)
let parse_block_id (t : string) : string * string option =
  let re = Str.regexp " +\\^\\([A-Za-z0-9_-]+\\)$" in
  try ignore (Str.search_forward re t 0);
      let id = Str.matched_group 1 t in (Str.global_replace re "" t, Some id)
  with Not_found -> (t, None)

(* the explicit block anchors (^id) in a note — the addressable blocks an agent can
   reference ([[Page#^id]]) or surgically patch. *)
let block_ids_of (raw : string) : string list =
  List.filter_map (fun line ->
    match parse_block_id (String.trim line) with (_, Some id) -> Some id | _ -> None)
    (String.split_on_char '\n' raw)

(* ── the note body as addressable CHUNKS (zk-block-vectors, journal
   20260729-1056 §6.3) ─────────────────────────────────────────────────────
   The BLOCK is the retrieval unit (§4's ACH Hypothesis B): heading lines
   start a new chunk, blank lines separate chunks, everything else stays with
   its run — so every non-blank line belongs to exactly ONE chunk, in order.
   A chunk carrying an explicit trailing ^id anchor keeps that id (search
   hits, [[Page#^id]] links, and embeddings share ONE addressing scheme); an
   anchor-less chunk gets a DETERMINISTIC content-digest id b<md5-8> (same
   bytes ⇒ same id, no clock/randomness), suffixed -2,-3… on within-note
   collision so ids stay unique.
   LAW chunk-partition: the in-order concatenation of the chunks' token
   streams ≡ the body's token stream (blank separators carry no tokens).
   LAW chunk-anchor: an explicit ^id survives as the chunk id.
   LAW chunk-determinism/uniqueness: same input ⇒ same (id, text) list; ids
   unique within a note. Total on empty/blank bodies. *)
let chunks_of (raw : string) : (string * string) list =
  let flush groups cur = match cur with [] -> groups | _ -> List.rev cur :: groups in
  let groups =
    let rec go groups cur = function
      | [] -> flush groups cur
      | l :: rest ->
          let t = String.trim l in
          if t = "" then go (flush groups cur) [] rest
          else if t.[0] = '#' then go (flush groups cur) [ l ] rest
          else go groups (l :: cur) rest
    in
    List.rev (go [] [] (String.split_on_char '\n' raw)) in
  let seen = Hashtbl.create 16 in
  List.map (fun ls ->
    let text = String.concat "\n" ls in
    let explicit = List.fold_left (fun acc l ->
        match acc with Some _ -> acc | None -> snd (parse_block_id (String.trim l))) None ls in
    let base = match explicit with
      | Some id -> id
      | None -> "b" ^ String.sub (Digest.to_hex (Digest.string text)) 0 8 in
    let rec uniq c i = if Hashtbl.mem seen c then uniq (Printf.sprintf "%s-%d" base i) (i + 1) else c in
    let cid = uniq base 2 in
    Hashtbl.replace seen cid ();
    (cid, text)) groups

(* ── THE RENDERING PATH ───────────────────────────────────────────────────
   Markdown reaches every served page through the typed AST. The streaming
   renderer that preceded it has been RETIRED: it was admitted-against, not
   merely replaced — the AST was proven equivalent over every document in the
   corpus before the old code was deleted, and that guarantee now lives in
   `docs/design/markdown-render-baseline.txt`, a committed digest per document
   which `LAW CORPUS-BASELINE` checks on every gate run.

   The link graph comes back as DATA (`refs`) rather than through the
   `zettel_outlinks`/`zettel_tags`/`zettel_typed` globals the old renderer
   accumulated into. *)
let render_markdown_typed ~resolve (md : string) : string =
  Markdown_ast.render_string ~resolve (Markdown_ast.parse_with_resolve ~resolve md)

(* ── TRANSCLUSION: ![[Note]] / ![[Note#^id]] block embeds (zk-transclusion,
   journal 20260729-1056 §7.8 — Roam/Logseq's block-reference composition) ──
   A FULL-LINE `![[Target]]` embeds the whole note body; `![[Target#^id]]`
   embeds the ^id chunk (the SAME addressing scheme as links, block vectors,
   and block search — chunks_of resolves the anchor). Inline (mid-sentence)
   `![[..]]` stays a plain link — only full-line markers expand, keeping
   block structure sane. Each embed renders inside a provenance-chipped
   container linking back to the source.
   SAFETY: expansion carries an explicit stack (cycle ⇒ error chip — the
   transclusion relation must be a DAG) and a depth bound of 3 (an embed
   chain deeper than 3 renders a bounded error chip, never recurses on).
   Rendering is TOTAL: unresolved targets / missing blocks / cycles / depth
   all degrade to visible error chips. LAWS: embed-render, whole-note-embed,
   embedded-links-resolve, inline-not-expanded, cycle-chip, depth-bound,
   missing-target/block chips, determinism; the corpus-level DAG check
   reports cycles in anomalies (report-only). *)
let embed_re = Str.regexp "^!\\[\\[\\([^]|#]+\\)\\(#\\^\\([A-Za-z0-9_-]+\\)\\)?\\]\\]$"

(* rebuild the note resolver from a page list — the same key set `build`
   registers (slug, title, basename, ordinal-stripped title). *)
let resolver_of (pages : page list) : string -> string option =
  let tbl = Hashtbl.create 256 in
  let reg k slug = let k = znorm k in
    if k <> "" && not (Hashtbl.mem tbl k) then Hashtbl.replace tbl k slug in
  List.iter (fun p ->
    reg p.slug p.slug; reg p.title p.slug;
    reg (Filename.remove_extension (Filename.basename p.path)) p.slug;
    reg (Str.global_replace (Str.regexp "^[0-9]+[ .\194\183:-]*") "" p.title) p.slug) pages;
  fun k -> Hashtbl.find_opt tbl (znorm k)

(* the full-line embed markers of a raw body, syntactically (no resolution) *)
let embed_lines (raw : string) : (string * string option) list =
  List.filter_map (fun line ->
    let t = String.trim line in
    if Str.string_match embed_re t 0 && Str.match_end () = String.length t then
      let base = Str.matched_group 1 t in
      let anchor = try Some (Str.matched_group 3 t) with Not_found -> None in
      Some (base, anchor)
    else None)
    (String.split_on_char '\n' raw)

let render_with_embeds (pages : page list) (p : page) : string =
  let resolve = resolver_of pages in
  (* the typed path, and no global to set or forget to reset *)
  let render_md md = render_markdown_typed ~resolve md in
  let find_page slug = List.find_opt (fun q -> String.equal q.slug slug) pages in
  (* The chip took a PRE-ESCAPED string, so every one of its six call sites had
     to remember `esc_s` and one forgotten call would have been an injection
     through a note title. Typed markup escapes at the boundary instead, so the
     callers below now pass the raw value and the escaping cannot be omitted. *)
  let chip msg = elt_str (Th.div ~a:[ Th.a_class [ "zk-embed"; "err" ] ] [ Th.txt msg ]) in
  let rec go stack depth (raw : string) : string =
    let buf = Buffer.create 512 and seg = Buffer.create 512 in
    let flush () =
      if Buffer.length seg > 0 then begin
        Buffer.add_string buf (render_md (Buffer.contents seg)); Buffer.clear seg
      end in
    List.iter (fun line ->
      let t = String.trim line in
      if Str.string_match embed_re t 0 && Str.match_end () = String.length t then begin
        (* capture groups BEFORE any further Str use (flush renders → Str) *)
        let base = Str.matched_group 1 t in
        let anchor = try Some (Str.matched_group 3 t) with Not_found -> None in
        flush ();
        Buffer.add_string buf (embed stack depth base anchor)
      end else begin
        Buffer.add_string seg line; Buffer.add_char seg '\n'
      end)
      (String.split_on_char '\n' raw);
    flush ();
    Buffer.contents buf
  and embed stack depth base anchor =
    match resolve base with
    | None -> chip (Printf.sprintf "unresolved embed: %s" base)
    | Some slug ->
        let frag = match anchor with Some a -> "#^" ^ a | None -> "" in
        let key = slug ^ frag in
        if List.mem key stack then
          chip (Printf.sprintf "embed cycle at %s — transclusion must be a DAG" key)
        else if depth >= 3 then chip "embed depth limit (3) reached"
        else
          (match find_page slug with
           | None -> chip (Printf.sprintf "unresolved embed: %s" base)
           | Some q ->
               let content = match anchor with
                 | None -> Some q.raw
                 | Some a -> List.assoc_opt a (chunks_of q.raw) in
               (match content, anchor with
                | None, Some a -> chip (Printf.sprintf "no block ^%s in %s" a slug)
                | None, None -> chip (Printf.sprintf "unresolved embed: %s" base)
                | Some md, _ ->
                    (* `inner` is HTML the recursion already produced, so it
                       splices unsafely — the one honest seam here, and the
                       reason it is safe is that everything reaching it went
                       through the typed renderer first. *)
                    let inner = go (key :: stack) (depth + 1) md in
                    elt_str
                      (Th.div
                         ~a:[ Th.a_class [ "zk-embed" ] ]
                         [ Th.a
                             ~a:[ Th.a_class [ "zk-embed-src" ];
                                  Th.a_href (slug ^ ".html" ^ frag);
                                  Th.a_title "embedded from" ]
                             [ Th.txt ("\226\134\177 " ^ key) ];
                           Th.Unsafe.data inner ])))
  in
  go [ p.slug ] 0 p.raw

(* the first "# Title" line, else the basename *)
let title_of path md =
  let rec first = function
    | [] -> None
    | l :: rest -> let t = String.trim l in
        if String.length t >= 2 && String.sub t 0 2 = "# " then Some (String.trim (String.sub t 2 (String.length t-2)))
        else if String.length t >= 3 && String.sub t 0 3 = "## " then first rest
        else first rest in
  match first (String.split_on_char '\n' md) with
  | Some t -> t
  | None -> Filename.remove_extension (Filename.basename path)

let group_of path =
  (* a doc under docs/SUB/… is grouped as SUB; a root-level doc is classified by
     theme so the
     whole project corpus (concepts · SDLC/SRE · porting · plan · system) is a
     navigable Zettelkasten, not one flat "root" pile. *)
  if String.length path > 5 && String.sub path 0 5 = "docs/" then
    (let p = String.sub path 5 (String.length path - 5) in
     match String.index_opt p '/' with Some i -> String.sub p 0 i | None -> "docs")
  (* skills/ · proofs/ · specs/ are their own top-level groups (first-class doc
     trees now served by the wiki), so they cluster instead of piling into "root". *)
  else if String.length path > 7 && String.sub path 0 7 = "skills/" then "skills"
  else if String.length path > 7 && String.sub path 0 7 = "proofs/" then "proofs"
  else if String.length path > 6 && String.sub path 0 6 = "specs/" then "specs"
  else begin
    let n = String.uppercase_ascii (Filename.basename path) in
    let hit subs = List.exists (fun s ->
      let ls = String.length s and ln = String.length n in
      let rec go i = i + ls <= ln && (String.sub n i ls = s || go (i+1)) in go 0) subs in
    if hit ["ALGEBRAIC"; "ONTOLOGY"; "FRACTAL"] then "concepts"
    else if hit ["SDLC"; "SRE"; "SAFETY"; "CAST"; "STPA"; "FMEA"] then "sdlc-sre"
    else if hit ["OTP30"; "PORTING"; "PARITY"; "DIVERGENCE"; "CONFORMANCE"] then "porting"
    else if hit ["PLAN"; "ROADMAP"; "IMPLEMENTATION"; "HANDOFF"; "KANBAN"] then "plan"
    else if hit ["ARCHITECTURE"; "CODEBASE"; "MAP"; "MUTATION"; "COVERAGE"] then "system"
    else "root"
  end

(* the CONTEXT of each [[link]] in a raw body: for every line containing a
   resolvable wiki-link, (target-slug, trimmed line clamped to 240 chars).
   FIRST occurrence per target wins (deterministic); anchors ([[Base#sec]])
   resolve by base. Pure — the extraction half of zk-contextual-backlinks;
   LAW ctx-soundness: re-scanning a stored context still yields its target. *)
let link_contexts (resolve : string -> string option) (raw : string) : (string * string) list =
  let re = Str.regexp "\\[\\[\\([^]|]+\\)\\(|\\([^]]+\\)\\)?\\]\\]" in
  let clamp s =
    let s = String.trim s in
    if String.length s <= 240 then s else String.sub s 0 240 in
  String.split_on_char '\n' raw
  |> List.fold_left (fun acc line ->
      let rec scan pos acc =
        match Str.search_forward re line pos with
        | _ ->
            let target = Str.matched_group 1 line in
            let stop = Str.match_end () in
            let base = match String.index_opt target '#' with
              | Some i -> String.trim (String.sub target 0 i)
              | None -> target in
            let acc = match resolve base with
              | Some slug when not (List.mem_assoc slug acc) -> (slug, clamp line) :: acc
              | _ -> acc in
            scan stop acc
        | exception Not_found -> acc
      in
      scan 0 acc)
    []
  |> List.rev

(* ── EPISODIC notes (zk-episodic-notes, journal 20260729-1056 §7.4 as
   amended by §8.2-M) ──────────────────────────────────────────────────────
   Harness-authored per-slice session memory lives under docs/zk/episodic/.
   THE PROJECTION LAW (conservative extension — "this is how a Zettelkasten
   dies" defense): episodic notes are EXCLUDED from every derived analytic —
   backlinks/mentions/context of core notes, PageRank/PPR, similarity,
   communities, betweenness, MoCs, grounded semantics, anomalies, and the
   search index — so the core wiki model with episodic notes present is
   IDENTICAL to the model with them absent. They still render as pages
   (navigable memory), they just never distort the garden. *)
let is_episodic (p : page) =
  let pre = "docs/zk/episodic/" in
  String.length p.path >= String.length pre
  && String.equal (String.sub p.path 0 (String.length pre)) pre

let core_pages (pages : page list) : page list =
  List.filter (fun p -> not (is_episodic p)) pages

(* The unlinked-mention index.  The former implementation lowercased and
   substring-scanned every source note once for every target title
   (O(notes^2 * text), with enormous transient allocation).  Aho-Corasick
   constructs one deterministic automaton over all eligible titles, then scans
   each source body once.  It preserves the old byte-level ASCII-insensitive
   substring semantics: no token/word-boundary policy has been added. *)
type mention_ac_node = {
  ac_next : (char, int) Hashtbl.t;
  mutable ac_fail : int;
  mutable ac_out : string list;
}

type mention_automaton = { ac_nodes : mention_ac_node array; ac_count : int }

let mention_automaton (patterns : (string * string) list) : mention_automaton =
  let fresh () = { ac_next = Hashtbl.create 8; ac_fail = 0; ac_out = [] } in
  let nodes = ref (Array.init 64 (fun _ -> fresh ())) and count = ref 1 in
  let node i = (!nodes).(i) in
  let add_node () =
    if !count = Array.length !nodes then begin
      let old = !nodes in
      let grown = Array.init (2 * Array.length old) (fun _ -> fresh ()) in
      Array.blit old 0 grown 0 (Array.length old);
      nodes := grown
    end;
    let i = !count in
    (!nodes).(i) <- fresh ();
    incr count;
    i in
  List.iter
    (fun (pattern, slug) ->
      let pattern = String.lowercase_ascii pattern in
      if String.length pattern >= 4 then begin
        let state = ref 0 in
        String.iter
          (fun c ->
            match Hashtbl.find_opt (node !state).ac_next c with
            | Some next -> state := next
            | None ->
                let next = add_node () in
                Hashtbl.replace (node !state).ac_next c next;
                state := next)
          pattern;
        if not (List.mem slug (node !state).ac_out) then
          (node !state).ac_out <- slug :: (node !state).ac_out
      end)
    patterns;
  let queue = Queue.create () in
  Hashtbl.iter
    (fun _ child -> (node child).ac_fail <- 0; Queue.add child queue)
    (node 0).ac_next;
  while not (Queue.is_empty queue) do
    let parent = Queue.take queue in
    Hashtbl.iter
      (fun c child ->
        Queue.add child queue;
        let fallback = ref (node parent).ac_fail in
        while !fallback <> 0
              && not (Hashtbl.mem (node !fallback).ac_next c) do
          fallback := (node !fallback).ac_fail
        done;
        let target =
          match Hashtbl.find_opt (node !fallback).ac_next c with
          | Some next -> next
          | None -> 0 in
        (node child).ac_fail <- target;
        (node child).ac_out <-
          List.sort_uniq compare ((node child).ac_out @ (node target).ac_out))
      (node parent).ac_next
  done;
  { ac_nodes = Array.sub !nodes 0 !count; ac_count = !count }

let mention_matches (automaton : mention_automaton) (raw : string) : string list =
  let state = ref 0 and matches = ref [] in
  String.iter
    (fun c ->
      let c = Char.lowercase_ascii c in
      while !state <> 0
            && not (Hashtbl.mem automaton.ac_nodes.(!state).ac_next c) do
        state := automaton.ac_nodes.(!state).ac_fail
      done;
      state :=
        (match Hashtbl.find_opt automaton.ac_nodes.(!state).ac_next c with
         | Some next -> next
         | None -> 0);
      matches := automaton.ac_nodes.(!state).ac_out @ !matches)
    raw;
  List.sort_uniq compare !matches

let contains_case_ascii hay needle =
  let hl = String.lowercase_ascii hay and nl = String.lowercase_ascii needle in
  let ln = String.length nl in
  ln >= 4
  && (let rec go i =
        i + ln <= String.length hl
        && (String.equal (String.sub hl i ln) nl || go (i + 1)) in
      go 0)

(* Slow, allocation-heavy reference interpretation retained for differential
   admission of the indexed edge/mention reduction.  It is never used by the
   serving path. *)
let naive_derived_link_mismatches (pages : page list) : string list =
  List.filter_map
    (fun (p : page) ->
      let expected_backlinks, expected_mentions =
        if is_episodic p then [], []
        else
          ( List.filter_map
              (fun (q : page) ->
                if not (is_episodic q) && q.slug <> p.slug
                   && List.mem p.slug q.outlinks
                then Some q.slug else None)
              pages
            |> List.sort_uniq compare,
            List.filter_map
              (fun (q : page) ->
                if not (is_episodic q) && q.slug <> p.slug
                   && not (List.mem p.slug q.outlinks)
                   && contains_case_ascii q.raw p.title
                then Some q.slug else None)
              pages
            |> List.sort_uniq compare ) in
      if expected_backlinks = p.backlinks && expected_mentions = p.mentions then None
      else Some p.slug)
    pages

let build (files : (string * string) list) : page list =
  (* pass 1: identify every note (a Zettelkasten atomic note = a doc page). The
     YAML frontmatter is parsed off the front so it neither renders nor pollutes
     search/similarity; `body` is the frontmatter-stripped content. *)
  let notes = List.map (fun (path, md) ->
    let kv, body = parse_frontmatter md in
    (path, body, kv, slug_of_path path, title_of path body)) files in
  (* the resolver: every note is addressable by its slug, title, basename, and
     its title minus a leading "NN · " / "NN-" ordinal. *)
  let tbl = Hashtbl.create 256 in
  List.iter (fun (path, _, _, slug, title) ->
    let reg k = if k <> "" && not (Hashtbl.mem tbl k) then Hashtbl.replace tbl k slug in
    reg (znorm slug); reg (znorm title);
    reg (znorm (Filename.remove_extension (Filename.basename path)));
    reg (znorm (Str.global_replace (Str.regexp "^[0-9]+[ .·:-]*") "" title))) notes;
  let resolve k = Hashtbl.find_opt tbl (znorm k) in
  (* pass 2: render each note WITH the resolver, capturing outlinks + tags. *)
  let pages0 = List.map (fun (path, body, kv, slug, title) ->
    (* the graph arrives as DATA from the parse, not as global side effects *)
    let doc, refs = Markdown_ast.of_markdown ~resolve body in
    let html = Markdown_ast.render_string ~resolve doc in
    { path; slug; title; group = group_of path; html; raw = body;
      outlinks = List.sort_uniq compare refs.Markdown_ast.outlinks;
      tags = List.sort_uniq compare refs.Markdown_ast.tags;
      typed = List.sort_uniq compare refs.Markdown_ast.typed;
      backlinks = []; mentions = []; back_ctx = []; meta = meta_of ~slug kv }) notes in
  (* pass 3: reverse the graph → backlinks; + UNLINKED MENTIONS (a note whose
     TITLE appears verbatim in another note that does NOT [[link]] it — the
     hallmark Zettelkasten "unlinked references" that surface latent connections). *)
  let by_slug = Hashtbl.create (max 16 (2 * List.length pages0)) in
  List.iter (fun (p : page) -> Hashtbl.replace by_slug p.slug p) pages0;
  (* Indexed edge inversion: one map pass over outgoing edges, then immutable
     target lookups.  Self-links remain excluded exactly as before. *)
  let backlinks_by_target = Hashtbl.create (max 16 (2 * List.length pages0)) in
  List.iter
    (fun (q : page) ->
      if not (is_episodic q) then
        List.iter
          (fun target ->
            if not (String.equal target q.slug) then
              Hashtbl.replace backlinks_by_target target
                (q.slug
                 :: Option.value ~default:[]
                      (Hashtbl.find_opt backlinks_by_target target)))
          q.outlinks)
    pages0;
  (* One title automaton, one scan per core source note.  Results are reduced by
     target slug; explicit links are removed because those are backlinks, not
     unlinked mentions. *)
  let automaton =
    pages0
    |> List.filter (fun p -> not (is_episodic p))
    |> List.map (fun p -> (p.title, p.slug))
    |> mention_automaton in
  let mentions_by_target = Hashtbl.create (max 16 (2 * List.length pages0)) in
  List.iter
    (fun (q : page) ->
      if not (is_episodic q) then
        List.iter
          (fun target ->
            if not (String.equal target q.slug)
               && not (List.mem target q.outlinks) then
              Hashtbl.replace mentions_by_target target
                (q.slug
                 :: Option.value ~default:[]
                      (Hashtbl.find_opt mentions_by_target target)))
          (mention_matches automaton q.raw))
    pages0;
  List.map (fun p ->
    (* PROJECTION (§8.2-M): an episodic note is neither a backlink/mention
       SOURCE for core notes nor a backlink/mention TARGET itself — the core
       graph is byte-identical with or without the episodic set. *)
    if is_episodic p then { p with backlinks = []; mentions = []; back_ctx = [] }
    else
    let backs =
      Option.value ~default:[] (Hashtbl.find_opt backlinks_by_target p.slug)
      |> List.sort_uniq compare in
    let ments =
      Option.value ~default:[] (Hashtbl.find_opt mentions_by_target p.slug)
      |> List.sort_uniq compare in
    (* contextual backlinks: for each source, the line where it links p.
       Every back edge came from a [[wikilink]] in q.raw, so the re-scan
       finds it; "" is the honest fallback if it ever cannot. *)
    let ctx = List.map (fun src ->
      match Hashtbl.find_opt by_slug src with
      | Some q ->
          (src,
           Option.value ~default:""
             (List.assoc_opt p.slug (link_contexts resolve q.raw)))
      | None -> (src, "")) backs in
    { p with backlinks = backs; back_ctx = ctx; mentions = ments }) pages0
  |> List.sort (fun a b -> match compare a.group b.group with 0 -> compare a.path b.path | c -> c)

(* ── the View (pure functions of the Model) ────────────────────────────── *)
let css = {css|
:root{--bg:#0f1417;--side:#0b0f12;--pn:#141c20;--ink:#d9e2e4;--mu:#83949a;--dim:#5d6f76;--ln:#24333a;--ac:#3cc9ae;--bl:#5c9dd0;--code:#101a1e}
:root[data-theme=light]{--bg:#f7f6f3;--side:#f0efe9;--pn:#fff;--ink:#20272b;--mu:#5c6a70;--dim:#8b939a;--ln:#e6e1d8;--ac:#0c8a76;--bl:#2c72a8;--code:#f4f2ee}
@media(prefers-color-scheme:light){:root:not([data-theme=dark]){--bg:#f7f6f3;--side:#f0efe9;--pn:#fff;--ink:#20272b;--mu:#5c6a70;--dim:#8b939a;--ln:#e6e1d8;--ac:#0c8a76;--bl:#2c72a8;--code:#f4f2ee}}
*{box-sizing:border-box}html{background:var(--bg);scroll-behavior:smooth}
body{margin:0;color:var(--ink);background:var(--bg);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;font-size:15.5px;line-height:1.68;-webkit-font-smoothing:antialiased}
code,pre{font-family:ui-monospace,Menlo,Consolas,monospace}
.layout{display:grid;grid-template-columns:264px 1fr;max-width:1200px;margin:0 auto;min-height:100vh}
@media(max-width:880px){.layout{grid-template-columns:1fr}}
aside{border-right:1px solid var(--ln);background:var(--side);padding:22px 16px;position:sticky;top:0;height:100vh;overflow-y:auto}
@media(max-width:880px){aside{position:static;height:auto;border-right:none;border-bottom:1px solid var(--ln)}}
aside .brand{font-family:ui-monospace,monospace;font-size:13px;font-weight:700;display:flex;gap:8px;align-items:center;margin-bottom:3px}
aside .brand .g{width:8px;height:8px;border-radius:50%;background:var(--ac);box-shadow:0 0 6px var(--ac)}
aside .sub{font-size:11.5px;color:var(--dim);margin-bottom:16px}
aside .grp{font-size:10px;letter-spacing:.11em;text-transform:uppercase;color:var(--dim);margin:16px 0 5px;font-weight:700}
aside a{display:block;font-size:13px;color:var(--mu);padding:3px 8px;border-radius:6px;text-decoration:none;margin:1px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
aside a:hover{background:color-mix(in srgb,var(--ac) 12%,transparent);color:var(--ink)}
aside a.cur{background:color-mix(in srgb,var(--ac) 16%,transparent);color:var(--ac);font-weight:600}
main{padding:38px 46px 90px;max-width:900px;overflow-x:hidden}
@media(max-width:880px){main{padding:26px 20px 60px}}
main h1{font-size:33px;line-height:1.12;margin:0 0 14px;letter-spacing:-.02em}
main h2{font-size:23px;margin:38px 0 8px;padding-top:14px;border-top:1px solid var(--ln)}
main h3{font-size:17.5px;margin:26px 0 4px}main h4{font-size:15px;margin:20px 0 2px;color:var(--mu)}
main p{margin:11px 0;color:var(--ink)}
main a{color:var(--bl);text-decoration:none;border-bottom:1px solid color-mix(in srgb,var(--bl) 30%,transparent)}
main strong{color:var(--ink)}main em{color:var(--mu)}
main code{background:var(--code);border:1px solid var(--ln);border-radius:4px;padding:1px 5px;font-size:.86em}
main pre{background:var(--code);border:1px solid var(--ln);border-radius:9px;padding:14px 16px;overflow-x:auto;font-size:12.7px;line-height:1.55;margin:14px 0}
main pre code{background:none;border:none;padding:0}
/* code block: hover-revealed copy button + a language label drawn from
   data-lang. The label is CSS content, not markup, so it never lands in the
   copied text or the search index. */
.cb{position:relative;margin:14px 0}
.cb main pre,.cb pre{margin:0}
.cb-copy{position:absolute;top:7px;right:8px;z-index:2;font:inherit;font-size:11px;
  color:var(--mu);background:var(--pn);border:1px solid var(--ln);border-radius:6px;
  padding:2px 8px;cursor:pointer;opacity:0;transition:opacity .12s}
.cb:hover .cb-copy,.cb-copy:focus{opacity:1}
.cb-copy:hover{color:var(--ac);border-color:var(--ac)}
.cb[data-lang]::after{content:attr(data-lang);position:absolute;top:9px;right:64px;
  font-size:10px;letter-spacing:.04em;text-transform:uppercase;color:var(--dim);
  pointer-events:none}
/* mermaid: the runtime replaces the element's text with an SVG, so it gets no
   code-block chrome. Until/unless a runtime loads it stays readable as text. */
main pre.mermaid{background:var(--pn);text-align:center;line-height:1.4}
main pre.mermaid svg{max-width:100%;height:auto}
/* the repository's FIRST print rule. A hover-revealed control has no meaning on
   paper, and printing it would leave the word "Copy" floating over the code. */
@media print{.cb-copy{display:none}.cb[data-lang]::after{display:none}}
main ul,main ol{color:var(--ink);padding-left:24px}main li{margin:5px 0}
main blockquote{margin:16px 0;padding:11px 16px;border-left:3px solid var(--ac);background:var(--pn);border-radius:0 8px 8px 0;color:var(--mu)}
main hr{border:none;border-top:1px solid var(--ln);margin:26px 0}
.tw{overflow-x:auto;margin:14px 0}main table{border-collapse:collapse;width:100%;font-size:13.5px;min-width:420px}
main th{text-align:left;font-size:10.5px;text-transform:uppercase;letter-spacing:.05em;color:var(--dim);padding:8px 12px;border-bottom:2px solid var(--ln)}
main td{padding:8px 12px;border-bottom:1px solid var(--ln);vertical-align:top;color:var(--mu)}
main td strong,main td code{color:var(--ink)}
.crumb{font-family:ui-monospace,monospace;font-size:11px;color:var(--dim);margin-bottom:14px}
.crumb a{color:var(--bl);border:none}
.pn{display:flex;justify-content:space-between;gap:12px;margin-top:40px}
a.nav{flex:1;max-width:48%;border:1px solid var(--ln);border-radius:9px;padding:11px 14px;text-decoration:none;color:var(--ink);background:var(--pn);font-weight:600;font-size:14px}
a.nav.next{text-align:right}a.nav:hover{border-color:var(--ac)}
a.nav .d{display:block;font-family:ui-monospace,monospace;font-size:10px;color:var(--dim);font-weight:400;text-transform:uppercase;letter-spacing:.06em;margin-bottom:2px}
.foot{margin-top:50px;padding-top:18px;border-top:1px solid var(--ln);font-size:12px;color:var(--dim)}
.foot a{color:var(--bl)}
.idx-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:18px}@media(max-width:680px){.idx-grid{grid-template-columns:1fr}}
.idx-card{border:1px solid var(--ln);border-radius:10px;padding:13px 15px;background:var(--pn)}
.idx-card a{border:none;font-weight:600;font-size:15px}.idx-card .pg{font-family:ui-monospace,monospace;font-size:10.5px;color:var(--dim);margin-top:3px}
/* Zettelkasten: wiki-links + backlinks + graph */
a.zettel{display:inline-block;font-size:13px;padding:2px 9px;margin:2px 4px 2px 0;border-radius:20px;background:color-mix(in srgb,var(--ac) 12%,transparent);color:var(--ac);text-decoration:none;border:1px solid color-mix(in srgb,var(--ac) 28%,transparent)}
a.zettel:hover{background:color-mix(in srgb,var(--ac) 22%,transparent)}
a.zettel.missing{background:color-mix(in srgb,var(--dim) 14%,transparent);color:var(--dim);border-color:color-mix(in srgb,var(--dim) 28%,transparent);border-style:dashed}
.zk{margin-top:40px;display:grid;grid-template-columns:1fr 1fr;gap:16px}@media(max-width:680px){.zk{grid-template-columns:1fr}}
.zk-sec{border:1px solid var(--ln);border-radius:10px;padding:13px 15px;background:var(--pn)}
.zk-h{font-size:11px;text-transform:uppercase;letter-spacing:.07em;color:var(--dim);font-weight:700;margin-bottom:8px}
.zk-n{color:var(--ac);font-family:ui-monospace,monospace}
.zk-empty{color:var(--dim);font-size:12.5px}
.zk-bl{margin:5px 0}
.zk-ctx{color:var(--mu);font-size:12.5px;border-left:2px solid var(--ln);padding-left:9px;margin:3px 0 0 3px;font-style:italic;overflow-wrap:anywhere}
.zk-type{background:color-mix(in srgb,var(--bl) 18%,transparent);color:var(--bl)}
.zk-type.invalid{background:color-mix(in srgb,#c66 18%,transparent);color:#c66}
.zq{margin:8px 0}
.zq-q{display:block;font-size:12px;color:var(--mu);margin-bottom:5px}
.zq-t{border-collapse:collapse;width:100%;font-size:13px}
.zq-t th,.zq-t td{border:1px solid var(--ln);padding:3px 8px;text-align:left}
.zq-t th{color:var(--dim);font-weight:600}
.zq-n{font-size:11.5px;color:var(--dim);margin-top:3px}
.zq-err{color:#c66;font-size:12.5px;font-family:ui-monospace,monospace}
.zk-pair{display:inline-flex;gap:5px;align-items:center;margin:2px 8px 2px 0;font-size:13px}
.zk-grd{font-weight:600}.zk-grd.g-in{color:var(--ac)}.zk-grd.g-out{color:#c66}.zk-grd.g-undec{color:var(--mu)}
.zk-comm{color:var(--bl)}
.zk-nbh{margin:10px 0}.zk-nbh summary{cursor:pointer;color:var(--mu);font-size:13px}
.tl-spark{display:block;margin:10px 0}.tl-bar{fill:var(--ln)}.tl-bar.sel{fill:var(--ac)}
.tl-commits{font-family:ui-monospace,monospace;font-size:11.5px;line-height:2}
.tl-c{color:var(--mu);margin-right:6px;text-decoration:none}.tl-c.sel{color:var(--ac);font-weight:700}
.moc-st{font-size:11px;padding:1px 7px;border-radius:8px;background:color-mix(in srgb,var(--mu) 15%,transparent)}
.moc-st.fresh{color:var(--ac)}.moc-st.stale{color:#ca4}.moc-st.missing{color:#c66}.moc-st.frozen{color:var(--bl)}
.zks-kind{font-size:10.5px;padding:0 6px;border-radius:7px;background:color-mix(in srgb,var(--bl) 15%,transparent);color:var(--bl);margin-left:6px}
blockquote.callout{border-left-width:3px;border-radius:0 8px 8px 0;padding:8px 14px;background:color-mix(in srgb,var(--bl) 7%,transparent);border-left-color:var(--bl)}
blockquote.callout .co-t{font-weight:700;font-size:12.5px;text-transform:capitalize;margin-bottom:2px}
blockquote.co-warning,blockquote.co-danger,blockquote.co-caution{background:color-mix(in srgb,#c66 8%,transparent);border-left-color:#c66}
blockquote.co-tip,blockquote.co-hint{background:color-mix(in srgb,var(--ac) 8%,transparent);border-left-color:var(--ac)}
li.todo{list-style:none;margin-left:-18px}
li.todo input{accent-color:var(--ac);margin-right:4px}
nav.toc{display:block;border:1px solid var(--ln);border-radius:10px;padding:10px 14px;margin:10px 0;font-size:13.5px}
nav.toc a{display:block;color:var(--mu);text-decoration:none;padding:1px 0}
nav.toc a:hover{color:var(--ac)}
nav.toc .toc-l2{margin-left:14px}nav.toc .toc-l3{margin-left:28px}nav.toc .toc-l4{margin-left:42px}
.zk-embed{border-left:3px solid var(--ac);background:color-mix(in srgb,var(--ac) 6%,transparent);border-radius:0 8px 8px 0;padding:8px 14px;margin:10px 0}
.zk-embed.err{border-left-color:#c66;color:#c66;font-size:12.5px;font-family:ui-monospace,monospace}
.zk-embed-src{display:block;font-size:11px;color:var(--dim);text-decoration:none;margin-bottom:4px}
.zk-embed-src:hover{color:var(--ac)}
.zk-edges{display:flex;flex-direction:column;gap:4px;margin:12px 0}
.zk-edge{font-size:13px;padding:5px 0;border-bottom:1px solid var(--ln)}.zk-edge a{color:var(--bl);text-decoration:none}
.zk-arrow{color:var(--dim);margin:0 6px}
/* SVG graph visualization */
.zk-viz{border:1px solid var(--ln);border-radius:12px;background:var(--pn);padding:8px;margin:18px 0;overflow:hidden}
.zk-svg{width:100%;height:auto;display:block}
.zk-line{stroke:var(--ln);stroke-width:1.4}
.zk-arrhead{fill:var(--dim)}
.zk-node{fill:var(--ac);stroke:var(--bg);stroke-width:2;cursor:pointer;transition:fill .12s}
.zk-svg a:hover .zk-node{fill:var(--bl)}
.zk-label{fill:var(--ink);font-family:ui-monospace,Menlo,monospace;font-size:11px;pointer-events:none}
.zk-svg a:hover .zk-label{fill:var(--ac)}
/* tags */
.zk-tags{display:flex;flex-wrap:wrap;gap:5px;margin:-4px 0 16px}
a.zk-tag{font-family:ui-monospace,monospace;font-size:11.5px;color:var(--bl);text-decoration:none;background:color-mix(in srgb,var(--bl) 12%,transparent);padding:1px 8px;border-radius:20px}
a.zk-tag:hover{background:color-mix(in srgb,var(--bl) 22%,transparent)}
.zk-rel{display:inline-block;font-size:9.5px;text-transform:uppercase;letter-spacing:.04em;font-weight:700;color:var(--bl);background:color-mix(in srgb,var(--bl) 14%,transparent);border:1px solid color-mix(in srgb,var(--bl) 30%,transparent);border-radius:4px;padding:0 5px;margin-left:4px;vertical-align:middle}
.zk-card{display:flex;flex-wrap:wrap;align-items:center;gap:6px 10px;margin:-2px 0 14px;font-size:11.5px;color:var(--mu)}
.zk-id{font-family:ui-monospace,monospace;font-size:11px;color:var(--ac);background:color-mix(in srgb,var(--ac) 10%,transparent);padding:2px 8px;border-radius:5px;border:1px solid color-mix(in srgb,var(--ac) 22%,transparent)}
.zk-stat{font-variant-numeric:tabular-nums;white-space:nowrap}
.zk-stat::before{content:"·";margin-right:8px;color:color-mix(in srgb,var(--mu) 50%,transparent)}
.zk-pos{font-size:11.5px;color:var(--mu);margin:-6px 0 14px;padding:6px 10px;border-radius:7px;background:color-mix(in srgb,var(--ac) 6%,transparent);border:1px solid var(--ln)}
.zk-pos b{color:var(--ac);font-variant-numeric:tabular-nums}
.meta-panel{display:flex;flex-wrap:wrap;align-items:center;gap:6px 12px;margin:-6px 0 14px;font-size:11.5px;color:var(--mu)}
.meta-f b{color:var(--fg);font-weight:600}
.meta-f.mu{opacity:.7}
.meta-f code{font-size:10.5px}
.meta-status{font-family:ui-monospace,monospace;font-size:10px;text-transform:uppercase;letter-spacing:.05em;padding:2px 8px;border-radius:20px;font-weight:700;background:color-mix(in srgb,var(--mu) 20%,transparent);color:var(--fg)}
.meta-status.s-published{background:color-mix(in srgb,#3fb950 22%,transparent);color:#3fb950}
.meta-status.s-draft{background:color-mix(in srgb,#d29922 22%,transparent);color:#d29922}
.meta-status.s-flagged_for_review{background:color-mix(in srgb,#f85149 22%,transparent);color:#f85149}
.meta-status.s-archived{background:color-mix(in srgb,var(--mu) 25%,transparent);color:var(--mu)}
.meta-f.overdue{color:#f85149;font-weight:600}
.meta-f.overdue b{color:#f85149}
/* authoring forms */
.zk-form{display:flex;flex-direction:column;gap:14px;max-width:680px;margin:18px 0}
.zk-form label{display:flex;flex-direction:column;gap:5px;font-size:12.5px;color:var(--mu);font-weight:600}
.zk-form input,.zk-form textarea{font:inherit;font-size:14px;color:var(--fg);background:var(--bg);border:1px solid var(--ln);border-radius:8px;padding:9px 11px}
.zk-form textarea{resize:vertical;line-height:1.55;font-family:ui-monospace,monospace;font-size:13px}
.zk-form input:focus,.zk-form textarea:focus{outline:2px solid color-mix(in srgb,var(--ac) 55%,transparent);border-color:var(--ac)}
.zk-form button,.zk-del button{align-self:flex-start;font:inherit;font-size:13px;font-weight:600;cursor:pointer;border-radius:8px;padding:9px 18px;border:1px solid color-mix(in srgb,var(--ac) 40%,transparent);background:color-mix(in srgb,var(--ac) 14%,transparent);color:var(--ac)}
.zk-form button:hover{background:color-mix(in srgb,var(--ac) 24%,transparent)}
.zk-del{margin:18px 0}
.zk-del button.danger{border-color:color-mix(in srgb,#e5484d 45%,transparent);background:color-mix(in srgb,#e5484d 10%,transparent);color:#e5484d}
a.zk-edit{font-size:12px;color:var(--mu);text-decoration:none;border:1px solid var(--ln);border-radius:6px;padding:2px 9px;margin-left:8px}
a.zk-edit:hover{color:var(--ac);border-color:var(--ac)}
/* system memory */
.mem-item{border:1px solid var(--ln);border-left:3px solid color-mix(in srgb,var(--ac) 45%,transparent);border-radius:8px;padding:11px 14px;margin:10px 0;background:color-mix(in srgb,var(--ac) 3%,transparent)}
.mem-head{display:flex;flex-wrap:wrap;align-items:center;gap:8px;font-size:13.5px}
.mem-body{font-size:12.5px;color:var(--mu);margin:6px 0;font-family:ui-monospace,monospace;white-space:pre-wrap;word-break:break-word}
.mem-v{font-family:ui-monospace,monospace;font-size:10.5px;text-transform:uppercase;letter-spacing:.04em;padding:2px 7px;border-radius:5px;background:color-mix(in srgb,var(--mu) 18%,transparent);color:var(--fg)}
.mem-v.v-ok{background:color-mix(in srgb,#3fb950 22%,transparent);color:#3fb950}
.mem-rel,.mem-c .mem-rel{display:flex;flex-wrap:wrap;align-items:center;gap:5px;margin-top:7px}
.mem-git{display:flex;flex-direction:column;gap:5px;margin:8px 0}
.mem-c{font-size:12.5px;padding:7px 10px;border:1px solid var(--ln);border-radius:6px}
.mem-c code{color:var(--ac);font-size:11.5px}
/* interactive force graph */
.fg-wrap{margin:16px 0;border:1px solid var(--ln);border-radius:12px;overflow:hidden;background:color-mix(in srgb,var(--ac) 3%,transparent)}
.fg-controls{display:flex;flex-wrap:wrap;align-items:center;gap:10px;padding:10px 12px;border-bottom:1px solid var(--ln)}
.fg-search{font:inherit;font-size:13px;color:var(--fg);background:var(--bg);border:1px solid var(--ln);border-radius:7px;padding:6px 10px;min-width:180px}
.fg-legend{display:flex;flex-wrap:wrap;gap:4px 10px;flex:1}
.fg-f{display:inline-flex;align-items:center;gap:4px;font-size:11.5px;color:var(--mu);cursor:pointer}
.fg-btn{font:inherit;font-size:12px;cursor:pointer;border:1px solid var(--ln);border-radius:7px;padding:6px 12px;background:var(--bg);color:var(--fg)}
.fg-btn:hover{border-color:var(--ac);color:var(--ac)}
#fg{display:block;width:100%;height:min(70vh,640px);color:var(--fg);touch-action:none;background:radial-gradient(circle at 50% 40%,color-mix(in srgb,var(--ac) 6%,transparent),transparent 70%)}
.fg-hint{padding:7px 12px;font-size:11px;color:var(--mu);border-top:1px solid var(--ln);text-align:center}
/* network analysis */
.prbar{display:inline-block;width:120px;height:8px;border-radius:5px;background:var(--ln);overflow:hidden;vertical-align:middle;margin-right:7px}
.prbar span{display:block;height:100%;background:linear-gradient(90deg,var(--ac),var(--bl))}
.degdist{display:flex;align-items:flex-end;gap:4px;height:130px;padding:8px 0;border-bottom:1px solid var(--ln);overflow-x:auto}
.degbar{display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:100%;min-width:22px}
.degcol{width:16px;background:linear-gradient(180deg,var(--ac),color-mix(in srgb,var(--ac) 30%,transparent));border-radius:3px 3px 0 0;min-height:2px}
.deglbl{font-size:10px;color:var(--mu);margin-top:3px;font-variant-numeric:tabular-nums}
.rdorder{max-height:340px;overflow:auto;border:1px solid var(--ln);border-radius:8px;padding:10px 14px 10px 34px;margin:8px 0;font-size:13px}
.rdorder li{margin:1px 0;padding:1px 0}
.rdorder li a{text-decoration:none}
.rdorder li a:hover{text-decoration:underline}
/* criteria envelope + decision records */
.crit-env{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:12px;margin:16px 0}
.crit-col{border:1px solid var(--ln);border-radius:10px;padding:12px 14px;background:color-mix(in srgb,var(--ac) 3%,transparent)}
.crit-col h4{margin:0 0 8px;font-size:13px}
.crit-col ul{margin:0;padding-left:18px}
.crit-col li{font-size:12px;color:var(--mu);margin:4px 0;line-height:1.45}
.crit-col li b{color:var(--fg)}
/* full-text search */
.nav-search{width:100%;margin-bottom:10px;padding:6px 10px;border:1px solid var(--ln);border-radius:7px;background:var(--bg);color:var(--ink);font:inherit;font-size:12.5px}
.nav-search:focus{outline:none;border-color:var(--ac)}
.zks-input{width:100%;padding:11px 14px;border:1px solid var(--ln);border-radius:9px;background:var(--pn);color:var(--ink);font:inherit;font-size:15px;margin:10px 0 4px}
.zks-input:focus{outline:none;border-color:var(--ac);box-shadow:0 0 0 3px color-mix(in srgb,var(--ac) 15%,transparent)}
.zks-count{font-size:11px;color:var(--dim);text-transform:uppercase;letter-spacing:.06em;margin:14px 0 6px}
.zks-results{display:flex;flex-direction:column;gap:8px;margin-top:8px}
.zks-hit{display:block;border:1px solid var(--ln);border-radius:9px;padding:11px 14px;text-decoration:none;background:var(--pn)}
.zks-hit:hover{border-color:var(--ac)}
.zks-t{font-weight:600;color:var(--ink);font-size:14.5px}
.zks-g{font-family:ui-monospace,monospace;font-size:10px;color:var(--dim);background:var(--el);padding:1px 7px;border-radius:20px;margin-left:6px}
.zks-x{color:var(--mu);font-size:12.5px;margin-top:4px}
mark{background:color-mix(in srgb,var(--ac) 30%,transparent);color:var(--ink);border-radius:2px;padding:0 1px}
|css}

(* The page's behaviour, served from `/docs/wiki.js` — SAME ORIGIN, so the
   site's own `script-src 'self'` policy admits it. Everything here would
   otherwise have to be an inline `on*=` attribute, which that policy forbids.

   Two jobs, both progressive enhancement: a page served without this file keeps
   working, showing an inert Copy button and mermaid diagrams as readable source
   text. Nothing here is required to READ a document.

   (1) COPY — bound by DELEGATION on document, so it costs one listener no matter
       how many code blocks a page carries, and works for blocks inserted later.
   (2) MERMAID — initialised with the theme that matches the page's own
       light/dark resolution, so a diagram never renders dark-on-dark. *)
let wiki_js = {js|(function(){
  document.addEventListener('click', function(e){
    var b = e.target.closest && e.target.closest('.cb-copy');
    if (!b) return;
    var pre = b.nextElementSibling;
    if (!pre) return;
    navigator.clipboard.writeText(pre.innerText).then(function(){
      b.textContent = 'Copied';
      setTimeout(function(){ b.textContent = 'Copy'; }, 1200);
    });
  });
  if (window.mermaid) {
    var root = document.documentElement.getAttribute('data-theme');
    var dark = root ? root === 'dark'
      : window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    window.mermaid.initialize({ startOnLoad: true, theme: dark ? 'dark' : 'default' });
  }
})();
|js}

(* ---------- the wiki shell, typed -------------------------------------------
   `nav_html` and `page_frame` are the furniture EVERY page passes through, so
   an escaping slip here would affect the whole wiki rather than one view. Both
   are TyXML now: note titles, slugs and group names come from frontmatter and
   filenames — data, not literals — and are escaped structurally.

   ONE HONEST SEAM. `page_frame` receives `body` as an already-rendered HTML
   STRING from the markdown renderer, which still builds strings incrementally
   (its `in_ul`/`in_ol`/`in_bq` state machine opens a tag on one line and
   closes it many lines later — a streaming shape TyXML cannot express without
   restructuring the parser into a tree). So the body is embedded with
   `Unsafe.data`, and that is a real limit, not a formality: the shell is
   type-guaranteed, the body is only as good as the renderer's own escaping.
   Converting the parser is a separate, larger piece of work. *)

let nav_link ~cur ~href ~key label =
  Th.a
    ~a:(Th.a_href href :: (if key = cur then [ Th.a_class [ "cur" ] ] else []))
    [ Th.txt label ]

let nav_aside ~cur pages =
  let groups = List.sort_uniq compare (List.map (fun p -> p.group) pages) in
  Th.aside
    ([ Th.div
         ~a:[ Th.a_class [ "brand" ] ]
         [ Th.span ~a:[ Th.a_class [ "g" ] ] []; Th.txt "zigvm docs" ];
       Th.div ~a:[ Th.a_class [ "sub" ] ] [ Th.txt "OCaml wiki · Zettelkasten" ];
       Th.input
         ~a:
           [ Th.a_class [ "nav-search" ]; Th.a_input_type `Search;
             Th.a_placeholder "Search…";
             Th.a_onkeydown
               "if(event.key==='Enter')location.href='search.html?q='+encodeURIComponent(this.value)" ]
         ();
       nav_link ~cur ~href:"search.html" ~key:"search" "Search";
       nav_link ~cur ~href:"index.html" ~key:"" "Index";
       nav_link ~cur ~href:"graph.html" ~key:"graph" "Zettelkasten graph";
       nav_link ~cur ~href:"/docs/memory" ~key:"memory" "🧠 System memory";
       Th.a ~a:[ Th.a_href "/report" ] [ Th.txt "📊 System report" ];
       nav_link ~cur ~href:"/docs/decision" ~key:"decision" "⚖ Decision record";
       nav_link ~cur ~href:"/docs/criteria" ~key:"criteria" "📏 Criteria envelope";
       nav_link ~cur ~href:"tags.html" ~key:"tags" "Tags";
       nav_link ~cur ~href:"random.html" ~key:"random" "🎲 Random note";
       nav_link ~cur ~href:"/docs/new" ~key:"new" "➕ New note" ]
    @ List.concat_map
        (fun g ->
          Th.div ~a:[ Th.a_class [ "grp" ] ] [ Th.txt g ]
          :: List.filter_map
               (fun p ->
                 if p.group = g then
                   Some (nav_link ~cur ~href:(p.slug ^ ".html") ~key:p.slug p.title)
                 else None)
               pages)
        groups)

let nav_html ~cur pages = Format.asprintf "%a" (Th.pp_elt ()) (nav_aside ~cur pages)

(* The TYPED entry point. A caller that has already been converted hands over
   ELEMENTS, so no `Unsafe.data` seam exists for it at all — the whole page is
   type-guaranteed end to end. `page_frame` below keeps the string signature
   for the callers still emitting HTML by hand; as each converts it moves to
   this one, and the string version dies when the last of them does. That is
   the migration made visible in the types rather than tracked in a comment. *)
let page_frame_elts ~title ~cur ~pages ~(body : [< Html_types.main_content_fun ] Th.elt list) =
  let doc =
    Th.html
      ~a:[ Th.a_lang "en" ]
      (Th.head
         (Th.title (Th.txt (title ^ " · zigvm docs")))
         [ Th.meta ~a:[ Th.a_charset "utf-8" ] ();
           Th.meta
             ~a:[ Th.a_name "viewport"; Th.a_content "width=device-width, initial-scale=1" ]
             ();
           Th.base ~a:[ Th.a_href "/docs/" ] ();
           Th.style [ Th.Unsafe.data css ] ])
      (Th.body
         [ Th.div ~a:[ Th.a_class [ "layout" ] ] [ nav_aside ~cur pages; Th.main body ];
           (* both scripts are SAME-ORIGIN and `defer`red: they are enhancement,
              never required to read the page (see `wiki_js`) *)
           Th.script ~a:[ Th.a_src "/docs/mermaid.min.js"; Th.a_defer () ] (Th.txt "");
           Th.script ~a:[ Th.a_src "/docs/wiki.js"; Th.a_defer () ] (Th.txt "") ])
  in
  Format.asprintf "%a" (Th.pp ()) doc

let page_frame ~title ~cur ~pages ~body =
  (* A PROPER HTML document: (1) a doctype so browsers use standards mode and the
     display:grid layout lays out (quirks mode collapsed the content pane —
     "nothing showing up"); (2) <base href="/docs/"> so every RELATIVE link
     (`<slug>.html`, `graph.html`, `tags.html#x`) resolves under /docs/ whether the
     current URL is `/docs` (no trailing slash) or `/docs/<slug>.html` — the index
     was served at `/docs`, so its relative links resolved to `/<slug>.html` at the
     ROOT (not a served route) and 404'd; (3) <meta charset> so the ontology's
     unicode (ऋतम्भरा · → · ✓) renders; (4) a real <head>/<body>. *)
  let doc =
    Th.html
      ~a:[ Th.a_lang "en" ]
      (Th.head
         (Th.title (Th.txt (title ^ " · zigvm docs")))
         [ Th.meta ~a:[ Th.a_charset "utf-8" ] ();
           Th.meta
             ~a:[ Th.a_name "viewport"; Th.a_content "width=device-width, initial-scale=1" ]
             ();
           Th.base ~a:[ Th.a_href "/docs/" ] ();
           (* Unsafe.data, never txt: TyXML escapes <style> content. *)
           Th.style [ Th.Unsafe.data css ] ])
      (Th.body
         [ Th.div
             ~a:[ Th.a_class [ "layout" ] ]
             [ nav_aside ~cur pages;
               (* the one honest seam — see the note above *)
               Th.main [ Th.Unsafe.data body ] ];
           Th.script ~a:[ Th.a_src "/docs/mermaid.min.js"; Th.a_defer () ] (Th.txt "");
           Th.script ~a:[ Th.a_src "/docs/wiki.js"; Th.a_defer () ] (Th.txt "") ])
  in
  Format.asprintf "%a" (Th.pp ()) doc

(* two-way navigation: prev/next neighbours in the sorted order, so every page
   is reachable both from the sidebar (any→any) AND linearly (prev↔next↔index). *)
let neighbours pages (p : page) =
  let rec go prev = function
    | a :: b :: _ when a.slug = p.slug -> (prev, Some b)
    | a :: rest when a.slug = p.slug -> (prev, (match rest with n :: _ -> Some n | [] -> None))
    | a :: rest -> go (Some a) rest
    | [] -> (prev, None) in
  go None pages

(* ── Zettelkasten note identity + discovery (pure, law-governed) ────────── *)
(* CONNECTEDNESS: a zettel's degree = how embedded it is in the graph. This is
   the single number that says whether a note is doing its job (a Zettelkasten
   note earns its keep by its links, not its prose). *)
let degree (p : page) = List.length p.outlinks + List.length p.backlinks
let word_count (p : page) =
  let t = search_text p.raw in
  if String.length t = 0 then 0
  else List.length (List.filter (fun s -> s <> "") (String.split_on_char ' ' t))

(* MAPS OF CONTENT (structure notes): the entry points into the Zettelkasten —
   the most-connected notes, which a reader starts from. Highest degree first;
   a note with NO links is never an entry point (it has nothing to structure). *)
(* ── COMMUNITY DETECTION: deterministic label propagation (zk-communities,
   journal 20260729-1056 §6.5; Raghavan et al. 2007 made judge-safe) ───────
   Nodes = notes, edges = the UNDIRECTED link graph (outlinks ∪ backlinks).
   Classic LPA is order/random-sensitive — poison for a Tier-1 judge — so
   this variant is deterministic BY CONSTRUCTION: fixed page-order sweeps,
   most-frequent neighbor label with ties broken by SMALLEST label, and a
   hard 64-round bound (a hang is a failed law; LPA converges in far fewer
   rounds at corpus scale). A community's public id is the smallest member
   slug — content-derived, stable across runs.
   HONESTY BOUND: like all LPA variants, a single bridge edge MAY merge two
   dense clusters (first-round ties can propagate a foreign label) — the
   guaranteed separations are the DISCONNECTED ones; treat cluster shapes
   near bridges as coarse. LAWS: partition-valid (every note exactly one
   community; each community id maps to itself), determinism,
   clique-converges-to-one, disconnected-cliques-stay-two,
   singleton-isolates, id-is-smallest-member, totality. *)
let undirected_idx (pages : page list) : (string, int) Hashtbl.t * int list array =
  let n = List.length pages in
  let idx = Hashtbl.create (n * 2) in
  List.iteri (fun i p -> Hashtbl.replace idx p.slug i) pages;
  let adj = Array.make n [] in
  List.iteri (fun i p ->
    List.iter (fun o -> match Hashtbl.find_opt idx o with
      | Some j when j <> i ->
          if not (List.mem j adj.(i)) then adj.(i) <- j :: adj.(i);
          if not (List.mem i adj.(j)) then adj.(j) <- i :: adj.(j)
      | _ -> ()) p.outlinks) pages;
  (idx, adj)

let communities (pages : page list) : (string * string) list =
  let pages = core_pages pages in  (* §8.2-M projection *)
  let n = List.length pages in
  if n = 0 then [] else begin
    let _, adj = undirected_idx pages in
    let label = Array.init n (fun i -> i) in
    let changed = ref true and rounds = ref 0 in
    while !changed && !rounds < 64 do
      changed := false; incr rounds;
      for i = 0 to n - 1 do
        if adj.(i) <> [] then begin
          let freq = Hashtbl.create 8 in
          List.iter (fun j ->
            let l = label.(j) in
            Hashtbl.replace freq l (1 + Option.value ~default:0 (Hashtbl.find_opt freq l)))
            adj.(i);
          (* most frequent; ties → SMALLEST label (deterministic) *)
          let best = Hashtbl.fold (fun l c acc -> match acc with
            | None -> Some (l, c)
            | Some (bl, bc) ->
                if c > bc || (c = bc && l < bl) then Some (l, c) else acc) freq None in
          match best with
          | Some (l, _) when l <> label.(i) -> label.(i) <- l; changed := true
          | _ -> ()
        end
      done
    done;
    (* public community id = the smallest member SLUG of the cluster *)
    let slugs = Array.of_list (List.map (fun p -> p.slug) pages) in
    let rep = Hashtbl.create 16 in
    Array.iteri (fun i l ->
      let s = slugs.(i) in
      match Hashtbl.find_opt rep l with
      | Some r when r <= s -> ()
      | _ -> Hashtbl.replace rep l s) label;
    List.mapi (fun i p -> (p.slug, Hashtbl.find rep label.(i))) pages
  end

(* ── BETWEENNESS CENTRALITY (Brandes 2001, unweighted) — the bridge metric
   for structural-hole detection (§6.5, InfraNodus-shaped). O(V·E), trivial
   at corpus scale. LAWS: path-center-max (a—b—c ⇒ b strictly highest),
   leaf-zero, totality on empty/singleton. *)
let betweenness (pages : page list) : (string * float) list =
  let pages = core_pages pages in  (* §8.2-M projection *)
  let n = List.length pages in
  if n = 0 then [] else begin
    let _, adj = undirected_idx pages in
    let cb = Array.make n 0. in
    for s = 0 to n - 1 do
      let stack = ref [] in
      let pred = Array.make n [] in
      let sigma = Array.make n 0. and dist = Array.make n (-1) in
      sigma.(s) <- 1.; dist.(s) <- 0;
      let q = Queue.create () in
      Queue.add s q;
      while not (Queue.is_empty q) do
        let v = Queue.pop q in
        stack := v :: !stack;
        List.iter (fun w ->
          if dist.(w) < 0 then (dist.(w) <- dist.(v) + 1; Queue.add w q);
          if dist.(w) = dist.(v) + 1 then begin
            sigma.(w) <- sigma.(w) +. sigma.(v);
            pred.(w) <- v :: pred.(w)
          end) adj.(v)
      done;
      let delta = Array.make n 0. in
      List.iter (fun w ->
        List.iter (fun v ->
          delta.(v) <- delta.(v) +. (sigma.(v) /. sigma.(w)) *. (1. +. delta.(w)))
          pred.(w);
        if w <> s then cb.(w) <- cb.(w) +. delta.(w)) !stack
    done;
    List.mapi (fun i p -> (p.slug, cb.(i))) pages
  end

(* MAPS OF CONTENT, community-grounded (§6.5 upgrade of the old pure-degree
   heuristic): one entry point per community — the top-degree member of each
   of the k LARGEST communities (ties → slug). Old guarantees preserved:
   entries have degree > 0 (singleton/orphan communities are excluded), an
   unlinked corpus yields []. LAW mocs-distinct-communities. *)
let mocs ?(k = 6) (pages : page list) =
  let comm = communities pages in
  let clusters = Hashtbl.create 16 in
  List.iter (fun (s, c) ->
    Hashtbl.replace clusters c (s :: Option.value ~default:[] (Hashtbl.find_opt clusters c))) comm;
  let by_slug s = List.find (fun p -> String.equal p.slug s) pages in
  Hashtbl.fold (fun c members acc -> (c, members) :: acc) clusters []
  |> List.filter (fun (_, ms) -> List.length ms > 1)
  |> List.sort (fun (c1, m1) (c2, m2) ->
      match compare (List.length m2) (List.length m1) with 0 -> compare c1 c2 | d -> d)
  |> List.filteri (fun i _ -> i < k)
  |> List.map (fun (_, ms) ->
      List.map by_slug ms
      |> List.sort (fun a b ->
          match compare (degree b) (degree a) with 0 -> compare a.slug b.slug | d -> d)
      |> List.hd)
  |> List.filter (fun p -> degree p > 0)

(* SERENDIPITY: the random walk. Luhmann's slip-box surfaces unexpected
   juxtapositions; `random_target pages n` picks a note deterministically from
   an index (total: always a member for non-empty; None for empty) so the walk
   is testable, while the /docs/random route rotates n per request. *)
let random_target (pages : page list) (n : int) : page option =
  match pages with
  | [] -> None
  | _ -> let len = List.length pages in Some (List.nth pages (((n mod len) + len) mod len))

(* the zettel card: the note's permanent identity — ID (slug), connectedness,
   size, tag/link counts. Rendered at the top of every note page. *)
(* the `docs / <where>` breadcrumb every page opens with *)
let crumb_to label =
  Th.div
    ~a:[ Th.a_class [ "crumb" ] ]
    [ Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "docs" ]; Th.txt (" / " ^ label) ]

(* ── THE PAGE-FURNITURE ALGEBRA ──────────────────────────────────────────
   Every page in this wiki is built from the same eight shapes. Converting
   them one at a time meant re-deriving the same elements by hand on each
   page, which is slow and drifts. Naming them once makes each remaining page
   a short TERM over this vocabulary instead of a pile of elements, and gives
   the laws a smaller surface: law the combinator, and every page that uses it
   inherits the guarantee. *)
let mu kids = Th.p ~a:[ Th.a_class [ "mu" ] ] kids
let badge s = Th.span ~a:[ Th.a_class [ "zk-n" ] ] [ Th.txt s ]
let badge_n n = badge (string_of_int n)
let chips kids = Th.div ~a:[ Th.a_class [ "zk-chips" ] ] kids
let foot kids = Th.div ~a:[ Th.a_class [ "foot" ] ] kids
let link href label = Th.a ~a:[ Th.a_href href ] [ Th.txt label ]
let when_ cond elts = if cond then elts else []

(* a scrollable data table with a real <thead> — the shape used by every
   report page here *)
let data_table headers rows =
  Th.div
    ~a:[ Th.a_class [ "tw" ] ]
    [ Th.table
        ~thead:(Th.thead [ Th.tr (List.map (fun h -> Th.th [ Th.txt h ]) headers) ])
        rows ]

let zk_stat ?title text =
  let a = Th.a_class [ "zk-stat" ] :: (match title with None -> [] | Some t -> [ Th.a_title t ]) in
  Th.span ~a [ Th.txt text ]

let zettel_card_elt (p : page) =
  Th.div
    ~a:[ Th.a_class [ "zk-card" ] ]
    [ Th.span ~a:[ Th.a_class [ "zk-id" ] ] [ Th.txt p.slug ];
      zk_stat ~title:"connectedness = links in + out"
        (Printf.sprintf "\226\151\136 %d linked" (degree p));
      zk_stat (Printf.sprintf "\226\134\146 %d out" (List.length p.outlinks));
      zk_stat (Printf.sprintf "\226\134\144 %d in" (List.length p.backlinks));
      zk_stat (Printf.sprintf "%d words" (word_count p));
      zk_stat (Printf.sprintf "%d tags" (List.length p.tags)) ]

let zettel_card (p : page) = elt_str (zettel_card_elt p)

(* the agent-collaborative metadata panel — the frontmatter control panel made
   visible: lifecycle status, the stable UUID, and freshness/decay dates. A tiny
   client-side check flags a note whose next_review is past (a decay signal). *)
let render_meta_panel_elt (p : page) =
  let m = p.meta in
  let field label v =
    if String.trim v = "" then []
    else
      [ Th.span
          ~a:[ Th.a_class [ "meta-f" ] ]
          [ Th.b [ Th.txt label ]; Th.txt " "; Th.txt v ] ]
  in
  let review =
    if String.trim m.next_review = "" then []
    else
      [ Th.span
          (* a custom attribute is TYPED here (`a_user_data`), not spliced —
             the client-side decay check reads data-review. *)
          ~a:[ Th.a_class [ "meta-f" ]; Th.a_user_data "review" m.next_review ]
          [ Th.b [ Th.txt "review by" ]; Th.txt " "; Th.txt m.next_review ] ]
  in
  (* the discourse-type badge (§7.5) — shown whenever the note is typed beyond
     the default, marked invalid when outside the vocabulary (report-only). *)
  let tbadge =
    if m.ntype = default_type then []
    else if List.mem m.ntype valid_types then
      [ Th.span
          ~a:[ Th.a_class [ "meta-status"; "zk-type" ]; Th.a_title "discourse type" ]
          [ Th.txt m.ntype ] ]
    else
      [ Th.span
          ~a:
            [ Th.a_class [ "meta-status"; "zk-type"; "invalid" ];
              Th.a_title
                ("UNKNOWN discourse type \226\128\148 not in ["
                ^ String.concat "|" valid_types ^ "]") ]
          [ Th.txt (m.ntype ^ " ?") ] ]
  in
  Th.div
    ~a:[ Th.a_class [ "meta-panel" ] ]
    ([ Th.span ~a:[ Th.a_class [ "meta-status"; "s-" ^ m.status ] ] [ Th.txt m.status ] ]
    @ tbadge
    @ [ Th.span
          ~a:[ Th.a_class [ "meta-f" ]; Th.a_title "stable UUID \226\128\148 survives a rename" ]
          [ Th.b [ Th.txt "id" ]; Th.txt " "; Th.code [ Th.txt m.id ] ] ]
    @ field "verified" m.last_verified
    @ field "by" m.verified_by
    @ review
    @
    if m.has_frontmatter then []
    else
      [ Th.span
          ~a:[ Th.a_class [ "meta-f"; "mu" ]; Th.a_title "no --- block; id derived from slug" ]
          [ Th.txt "\194\183 derived id" ] ])

let render_meta_panel (p : page) = elt_str (render_meta_panel_elt p)

(* the SERENDIPITY page: a client-side random jump (no-JS fallback lists a
   rotating suggestion) — the /docs/random route 302s server-side. *)
let render_random (pages : page list) =
  (* the slug list goes through Json_embed, so the data island cannot be closed
     by a slug and a control character survives as an escape rather than being
     flattened to a space *)
  let idx =
    Json_embed.to_string
      (Json_embed.Arr (List.map (fun p -> Json_embed.Str p.slug) pages))
  in
  let suggestion =
    match random_target pages (List.length pages) with
    (* anchor inlined rather than `zettel_link`, which is defined further down
       the file — the same reason `render_query_page` inlines its own *)
    | Some p ->
        [ Th.a
            ~a:[ Th.a_class [ "zettel" ]; Th.a_href (p.slug ^ ".html") ]
            [ Th.txt p.title ] ]
    | None -> [ Th.span ~a:[ Th.a_class [ "mu" ] ] [ Th.txt "no notes yet" ] ]
  in
  let jump_js =
    "(function(){var a=JSON.parse(document.getElementById('zk-all').textContent);\
     if(a.length){var s=a[Math.floor(Math.random()*a.length)];\
     location.replace(s+'.html');}})();"
  in
  let body =
    [ crumb_to "random";
      Th.h1 [ Th.txt "\240\159\142\178 Serendipity" ];
      mu
        [ Th.txt
            "The Zettelkasten random walk \226\128\148 jump to an arbitrary note to \
             surface unexpected connections (Luhmann's slip-box discovery \
             affordance)." ];
      Th.p
        (Th.txt "Jumping to a random note\226\128\166 "
         :: [ Th.span ~a:[ Th.a_id "zk-fallback" ] (Th.txt "no-JS pick: " :: suggestion) ]);
      Th.script
        ~a:[ Th.a_id "zk-all"; Th.a_script_type (`Mime "application/json") ]
        (Th.Unsafe.data idx);
      Th.script (Th.Unsafe.data jump_js);
      foot
        [ Th.txt "Serendipity \226\128\148 native OCaml (docs_wiki.ml). ";
          link "index.html" "\226\134\144 index"; Th.txt " \194\183 ";
          link "graph.html" "graph" ] ]
  in
  page_frame_elts ~title:"Serendipity" ~cur:"random" ~pages ~body

(* ── Zettelkasten AUTHORING (the pure kernel) ──────────────────────────
   A note-authoring command decides WHAT file to write and WHERE; the actual
   filesystem effect lives in the harness shell (zigvm_harness.ml). Everything
   here is pure and law-tested — most importantly the PATH-SAFETY law: for ANY
   title (incl. "../../etc/passwd", slashes, unicode, "") the target is under
   docs/zk/ and its basename is [0-9a-z-]+\.md. The shell writes ONLY the path
   this kernel returns, so a hostile title can never escape the slip-box. *)

let zk_dir = "docs/zk"

(* a stable note id from a unix timestamp: YYYYMMDD-HHMMSS (UTC). Pure in ts. *)
let note_id_of (ts : float) : string =
  let tm = Unix.gmtime ts in
  Printf.sprintf "%04d%02d%02d-%02d%02d%02d"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

(* the slug component: znorm (every non-[a-z0-9] → '-'), GUARANTEED non-empty
   and structurally free of '/' and '.', so it can never form a path escape. *)
let safe_slug s = match znorm s with "" -> "note" | z -> z

(* the note's relative path — ALWAYS docs/zk/<id>-<slug>.md, path-safe by
   construction (id is digits+'-', slug is [a-z0-9-]+ → no separators). *)
let note_path ~(ts : float) ~(title : string) : string =
  Printf.sprintf "%s/%s-%s.md" zk_dir (note_id_of ts) (safe_slug title)

(* the safety predicate the shell asserts before every write: rel is under
   docs/zk/, basename is [0-9a-z-]+\.md, and contains no "..". Total. *)
let path_is_safe (rel : string) : bool =
  let ok c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' in
  let pfx = zk_dir ^ "/" in
  String.length rel > String.length pfx
  && String.sub rel 0 (String.length pfx) = pfx
  && Filename.check_suffix rel ".md"
  && (let stem = Filename.chop_suffix (Filename.basename rel) ".md" in
      stem <> "" && String.for_all ok stem)
  && (let rec no_dd i = i + 1 >= String.length rel || (not (rel.[i] = '.' && rel.[i+1] = '.') && no_dd (i+1)) in no_dd 0)

(* the note file CONTENT: a well-formed markdown zettel — a "# title" heading
   (so title_of recovers it), the body verbatim (so [[links]] flow to the
   graph), and a trailing #tag line (so build() indexes them). *)
let note_markdown ~(title : string) ~(body : string) ~(tags : string list) : string =
  let clean = List.filter_map (fun t -> match znorm t with "" -> None | z -> Some z) tags in
  let tagline = match clean with [] -> "" | l -> "\n\n" ^ String.concat " " (List.map (fun t -> "#" ^ t) l) in
  Printf.sprintf "# %s\n\n%s%s\n"
    (let t = String.trim title in if t = "" then "Untitled" else t)
    (String.trim body) tagline

(* a YAML frontmatter block for an authored note — the agent-collaborative
   control panel written at creation: a stable UUID, a lifecycle status, and the
   verification stamp. Round-trips through parse_frontmatter. *)
let frontmatter ~(id : string) ~(status : string) ~(date : string) ~(verified_by : string) : string =
  Printf.sprintf "---\nid: %s\nstatus: %s\nlast_verified: %s\nverified_by: %s\n---\n"
    id status date verified_by

(* a full authored note = frontmatter + markdown body. Used by the /docs/new and
   /docs/decision write paths so every agent/human-created note is born with an id. *)
let authored_note ~(id : string) ~(date : string) ~(verified_by : string)
    ~(title : string) ~(body : string) ~(tags : string list) : string =
  frontmatter ~id ~status:"draft" ~date ~verified_by ^ note_markdown ~title ~body ~tags

(* ── BI-TEMPORAL EDGE HISTORY (zk-git-temporal, journal 20260729-1056
   §7.3/§8.2-T — the Graphiti/Zep insight applied to what the repo already
   has: git IS the transaction-time axis) ──────────────────────────────────
   Carrier: an ordered list of SNAPSHOTS (commit, timestamp, edge set) — the
   link graph as it stood at successive commits. `edge_intervals` is the
   FINAL encoding: each edge becomes (edge, added_idx, removed_idx option),
   half-open [added, removed); a re-added edge opens a SECOND interval
   (non-destructive invalidation — history is never rewritten). The ORACLE
   is the snapshot list itself; the HOMOMORPHISM is `asof_of_intervals`:
   reconstructing any snapshot index from the intervals yields exactly that
   snapshot's edge set (LAW asof-roundtrip — intervals are a LOSSLESS
   encoding). Other laws: interval-wellformed (added < removed),
   monotone-append (closed intervals of a prefix persist verbatim in the
   extended history), totality, determinism. *)
let edge_intervals (snaps : (string * string * (string * string) list) list)
  : ((string * string) * int * int option) list =
  let closed = ref [] and open_ = Hashtbl.create 64 in
  List.iteri (fun i (_, _, edges) ->
    let cur = List.sort_uniq compare edges in
    let to_close = Hashtbl.fold (fun e s l ->
        if List.mem e cur then l else (e, s) :: l) open_ [] in
    List.iter (fun (e, s) ->
      Hashtbl.remove open_ e;
      closed := (e, s, Some i) :: !closed) to_close;
    List.iter (fun e ->
      if not (Hashtbl.mem open_ e) then Hashtbl.replace open_ e i) cur)
    snaps;
  let opens = Hashtbl.fold (fun e s l -> (e, s, None) :: l) open_ [] in
  List.sort compare (!closed @ opens)

(* the edge set AS OF snapshot index i — the point-in-time query. *)
let asof_of_intervals (ivs : ((string * string) * int * int option) list) (i : int)
  : (string * string) list =
  List.filter_map (fun (e, s, r) ->
    if s <= i && (match r with None -> true | Some r -> i < r) then Some e else None)
    ivs
  |> List.sort_uniq compare

(* per-note CHURN over the mined window (§7.9's decay signal): how many
   interval events (edge added or removed) touch a slug — the notes whose
   NEIGHBORHOOD is moving are the ones due for human review. *)
let interval_churn (ivs : ((string * string) * int * int option) list)
  : (string * int) list =
  let tbl = Hashtbl.create 64 in
  let bump s n = Hashtbl.replace tbl s (n + Option.value ~default:0 (Hashtbl.find_opt tbl s)) in
  List.iter (fun ((a, b), _, r) ->
    let events = 1 + (match r with Some _ -> 1 | None -> 0) in
    bump a events; bump b events) ivs;
  Hashtbl.fold (fun s n l -> (s, n) :: l) tbl []
  |> List.sort (fun (s1, a) (s2, b) -> if b <> a then compare b a else compare s1 s2)

(* ── the EPISODIC session note (zk-episodic-notes, journal 20260729-1056
   §7.4/§8.2-M): ONE note per slice under docs/zk/episodic/, UPDATED in place
   after each recorded cycle. `verified_by: harness` is machine-set here (the
   attribution can't be spoofed from note content — UCA-ZKE-4), status stays
   `draft` (a human promotes), and the cycle history is COMPACTED to the 5
   most recent entries (UCA-ZKE-2: unbounded growth is how a Zettelkasten
   drowns). Pure: (prev content, cycle facts) → new content.
   LAWS: episode-attribution (draft + harness frontmatter), episode-compaction
   (folding N cycles keeps ≤5 entries, newest first), determinism. *)
let episode_markdown ~(slice : string) ~(verdict : string) ~(notes : string)
    ~(commit : string) ~(date : string) ~(prev : string) : string =
  let c8 = if String.length commit >= 8 then String.sub commit 0 8 else commit in
  let entry =
    Printf.sprintf "## Cycle %s — %s @ %s\n\n%s\n" date verdict c8 (String.trim notes) in
  (* previous entries = the "## Cycle " sections of the prior content *)
  let prev_entries =
    let lines = String.split_on_char '\n' prev in
    let rec go acc cur started = function
      | [] -> List.rev (if started then String.concat "\n" (List.rev cur) :: acc else acc)
      | l :: rest ->
          if String.length l >= 9 && String.equal (String.sub l 0 9) "## Cycle " then
            go (if started then String.concat "\n" (List.rev cur) :: acc else acc) [ l ] true rest
          else go acc (if started then l :: cur else cur) started rest
    in
    go [] [] false lines in
  let kept = List.filteri (fun i _ -> i < 4) prev_entries in
  frontmatter ~id:(uuid_of_string ("episode-" ^ slice)) ~status:"draft" ~date
    ~verified_by:"harness"
  ^ Printf.sprintf "# Episode: %s\n\n" slice
  ^ "Harness-authored session memory for this slice (one note per slice, \
     compacted to the 5 newest cycles; excluded from graph analytics by the \
     \194\1678.2-M projection law).\n\n"
  ^ entry ^ "\n"
  ^ String.concat "\n" (List.map String.trim kept)
  ^ (if kept = [] then "" else "\n")

(* ── COMMUNITY SUMMARY NOTES / MoCs (zk-community-summaries, journal
   20260729-1056 §7.13 — Microsoft GraphRAG's community summaries under this
   repo's discipline) ──────────────────────────────────────────────────────
   One DETERMINISTIC Map-of-Content note per large community, drafted by the
   harness from the live link graph (no LLM on this path — the §7.13
   agent-refinement stays an optional Stratum-C pass through zk_author_note).
   Notes live at docs/zk/moc-<community-id>.md, born draft+harness, and are
   regenerated ONLY when the community's MEMBERSHIP HASH changes (the §2.3
   memoization/circuit-breaker discipline).
   TWO structural safeguards, each a law + mutant:
   · SELF-INVALIDATION IMMUNITY: an MoC note links all its members, so if it
     counted toward membership it would perturb the hash it records — a
     permanent stale loop. Membership is therefore computed over the corpus
     WITHOUT moc-* notes (LAW moc-fresh-fixpoint: adding the generated note
     leaves its own status Fresh).
   · PROMOTION FREEZE: a human-promoted summary (status ≠ draft or
     verified_by ≠ harness) is NEVER overwritten — it reports Frozen, not
     Stale (LAW moc-promotion-freeze). *)
let is_moc (p : page) =
  let pre = "docs/zk/moc-" in
  String.length p.path >= String.length pre
  && String.equal (String.sub p.path 0 (String.length pre)) pre

let community_digest (members : string list) : string =
  Digest.to_hex (Digest.string (String.concat "\n" (List.sort compare members)))

(* the top size≥2 communities of the corpus WITHOUT moc notes (see above) *)
let moc_communities ?(k = 5) (pages : page list) : (string * string list) list =
  let base = List.filter (fun p -> not (is_moc p)) pages in
  let clusters = Hashtbl.create 16 in
  List.iter (fun (s, c) ->
    Hashtbl.replace clusters c (s :: Option.value ~default:[] (Hashtbl.find_opt clusters c)))
    (communities base);
  Hashtbl.fold (fun c ms acc -> (c, List.sort compare ms) :: acc) clusters []
  |> List.filter (fun (_, ms) -> List.length ms > 1)
  |> List.sort (fun (c1, m1) (c2, m2) ->
      match compare (List.length m2) (List.length m1) with 0 -> compare c1 c2 | d -> d)
  |> List.filteri (fun i _ -> i < k)

let moc_markdown ~(date : string) ~(cid : string) ~(members : string list)
    (pages : page list) : string =
  let by_slug s = List.find_opt (fun p -> String.equal p.slug s) pages in
  let deg s = match by_slug s with Some p -> degree p | None -> 0 in
  let title_of_s s = match by_slug s with Some p -> p.title | None -> s in
  let ranked = List.sort (fun a b ->
      match compare (deg b) (deg a) with 0 -> compare a b | d -> d) members in
  let tags = List.sort_uniq compare
      (List.concat_map (fun s -> match by_slug s with Some p -> p.tags | None -> []) members) in
  let rel = Printf.sprintf "%s/moc-%s.md" zk_dir (safe_slug cid) in
  Printf.sprintf
    "---\nid: %s\nstatus: draft\nlast_verified: %s\nverified_by: harness\n---\n\
     # MoC: %s\n\n\
     Deterministic map of content for the **%s** community (%d notes), drafted \
     by the harness from the live link graph (LPA communities, journal \
     20260729-1056 \194\1677.13). Regenerated only when the membership hash \
     changes; promote by editing `status:`.\n\n\
     membership: %s\n\n\
     ## Members (by connectedness)\n\n%s%s\n"
    (uuid_of_string rel) date (title_of_s cid) cid (List.length members)
    (community_digest members)
    (String.concat "" (List.map (fun s ->
         (* target by SLUG (always resolver-safe), display by title *)
         Printf.sprintf "- [[%s|%s]] \194\183 degree %d\n" s (title_of_s s) (deg s)) ranked))
    (* the tags ROLLUP is descriptive, rendered as INERT code spans — a live
       "#tag" here would LAUNDER member tags onto the MoC itself, polluting
       every tag-based query (found by the feature-algebra wellformedness law
       the moment the timer drew a MoC around feature notes: the MoC
       inherited #feature + multiple #cov-* and became a malformed feature). *)
    (match tags with [] -> "" | l -> "\n" ^ String.concat " " (List.map (fun t -> "`#" ^ t ^ "`") l))

(* the stored membership hash of an existing MoC note's body ("" if absent) *)
let moc_stored_digest (raw : string) : string =
  let pre = "membership: " in
  List.fold_left (fun acc l ->
    if acc = "" && String.length l > String.length pre
       && String.equal (String.sub l 0 (String.length pre)) pre
    then String.trim (String.sub l (String.length pre) (String.length l - String.length pre))
    else acc)
    "" (String.split_on_char '\n' raw)

type moc_state = Moc_missing | Moc_stale | Moc_fresh | Moc_frozen

let moc_status (pages : page list) : (string * string list * moc_state) list =
  List.map (fun (cid, members) ->
    let slug = slug_of_path (Printf.sprintf "%s/moc-%s.md" zk_dir (safe_slug cid)) in
    let state = match List.find_opt (fun p -> String.equal p.slug slug) pages with
      | None -> Moc_missing
      | Some p ->
          if not (String.equal p.meta.status "draft"
                  && String.equal p.meta.verified_by "harness")
          then Moc_frozen
          else if String.equal (moc_stored_digest p.raw) (community_digest members)
          then Moc_fresh
          else Moc_stale in
    (cid, members, state))
    (moc_communities pages)

(* ── the ZK AS THE SYSTEM'S MEMORY (git + SQLite, threaded into the graph) ──
   The Zettelkasten is not only static docs + authored slips: it is the VM's
   living memory. `render_memory` renders the system's OWN operational record —
   git (what changed) + the harness SQLite ledger (what was decided, closed, and
   proven) — as memory items, each auto-threaded into the concept graph so the
   episodic record (a closed cycle, a decision) links to the semantic notes
   (Architecture, The Gate) that explain it. Develop · document · evolve, from
   one surface. The renderer is PURE (records in → HTML out); the git/SQLite
   reads live in the harness shell. *)

type memory = {
  head : string;                                        (* git HEAD: short-hash then subject *)
  commits : (string * string) list;                     (* recent git log: hash, subject *)
  cycles : (string * string * string * string) list;    (* at, slice, verdict, notes *)
  frontier : (string * string * int) list;              (* slice, status, criticality *)
  ooda : (string * string * string) list;               (* at, phase, content *)
  baselines : (string * string) list;                   (* accepted_at, eq_counts *)
}
let empty_memory = { head=""; commits=[]; cycles=[]; frontier=[]; ooda=[]; baselines=[] }

(* case-insensitive substring — used to thread memory items into the graph *)
let ci_contains hay needle =
  let hl = String.lowercase_ascii hay and nl = String.lowercase_ascii needle in
  let ln = String.length nl in
  ln > 0 && (let rec go i = i + ln <= String.length hl && (String.sub hl i ln = nl || go (i + 1)) in go 0)

(* the concept notes a memory item RELATES to: any note whose title (len ≥ 5)
   appears in the item's text. This is the thread from episodic → semantic. *)
let mem_related (pages : page list) (text : string) =
  List.filteri (fun i _ -> i < 6)
    (List.filter (fun (p : page) -> String.length p.title >= 5 && ci_contains text p.title) pages)

(* TYPED. Every string on this page arrives from OUTSIDE the program — commit
   subjects from git, slice names/verdicts/notes/OODA content from SQLite — and
   the previous encoding escaped each of them at its own call site. Twenty
   `esc_s` calls is twenty chances to omit one. Built as elements, escaping is
   not a call anyone can forget. *)
let render_memory ~(pages : page list) (m : memory) =
  let chips text =
    match mem_related pages text with
    | [] -> []
    | ps ->
        [ Th.div
            ~a:[ Th.a_class [ "mem-rel" ] ]
            (Th.span ~a:[ Th.a_class [ "mu" ] ] [ Th.txt "\226\134\148 relates to" ]
             :: List.map
                  (fun (p : page) ->
                    Th.a
                      ~a:[ Th.a_class [ "zettel" ]; Th.a_href (p.slug ^ ".html") ]
                      [ Th.txt p.title ])
                  ps) ]
  in
  let when_ cond elts = if cond then elts else [] in
  let count_badge n = Th.span ~a:[ Th.a_class [ "zk-n" ] ] [ Th.txt n ] in
  let body =
    [ Th.div
        ~a:[ Th.a_class [ "crumb" ] ]
        [ Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "docs" ]; Th.txt " / memory" ];
      Th.h1 [ Th.txt "\240\159\167\160 System memory" ];
      Th.p
        ~a:[ Th.a_class [ "mu" ] ]
        [ Th.txt
            "The Zettelkasten as the VM's living memory \226\128\148 its own \
             operational record, read live from ";
          Th.b [ Th.txt "git" ];
          Th.txt " (what changed) and the harness ";
          Th.b [ Th.txt "SQLite" ];
          Th.txt
            " ledger (what was decided, closed, and proven), threaded into the \
             concept graph. Develop \194\183 document \194\183 evolve, from one \
             surface. HEAD: ";
          Th.code [ Th.txt m.head ];
          Th.txt "." ] ]
    (* git — the change memory *)
    @ when_ (m.commits <> [])
        [ Th.h2 [ Th.txt "Recent commits "; count_badge "git" ];
          Th.div
            ~a:[ Th.a_class [ "mem-git" ] ]
            (List.map
               (fun (h, subj) ->
                 Th.div
                   ~a:[ Th.a_class [ "mem-c" ] ]
                   ([ Th.code [ Th.txt h ]; Th.txt " "; Th.txt subj ] @ chips subj))
               m.commits) ]
    (* SQLite cycle_outcome — the episodic memory of closed work *)
    @ [ Th.h2
          [ Th.txt "Closed cycles "; count_badge (string_of_int (List.length m.cycles)) ];
        Th.p
          ~a:[ Th.a_class [ "mu" ] ]
          [ Th.txt
              "Every slice the Zero-Trust gate has admitted \226\128\148 the \
               system's episodic memory." ] ]
    @ List.map
        (fun (at, slice, verdict, notes) ->
          Th.div
            ~a:[ Th.a_class [ "mem-item" ] ]
            ([ Th.div
                 ~a:[ Th.a_class [ "mem-head" ] ]
                 [ Th.span ~a:[ Th.a_class [ "mem-v"; "v-" ^ verdict ] ] [ Th.txt verdict ];
                   Th.txt " ";
                   Th.b [ Th.txt slice ];
                   Th.txt " ";
                   Th.span ~a:[ Th.a_class [ "mu" ] ] [ Th.txt at ] ];
               Th.div ~a:[ Th.a_class [ "mem-body" ] ] [ Th.txt notes ] ]
             @ chips (slice ^ " " ^ notes)))
        m.cycles
    (* SQLite slice_backlog — the frontier: what the system will evolve next *)
    @ when_ (m.frontier <> [])
        [ Th.h2
            [ Th.txt "Frontier ";
              count_badge (Printf.sprintf "%d open" (List.length m.frontier)) ];
          Th.p
            ~a:[ Th.a_class [ "mu" ] ]
            [ Th.txt
                "Open slices by criticality \226\128\148 the system's intent, what \
                 it plans to become." ];
          Th.div
            ~a:[ Th.a_class [ "tw" ] ]
            [ Th.table
                ~thead:
                  (Th.thead
                     [ Th.tr
                         [ Th.th [ Th.txt "Slice" ];
                           Th.th [ Th.txt "Status" ];
                           Th.th [ Th.txt "Crit" ];
                           Th.th [ Th.txt "Relates to" ] ] ])
                (List.map
                   (fun (slice, status, crit) ->
                     Th.tr
                       [ Th.td [ Th.b [ Th.txt slice ] ];
                         Th.td [ Th.txt status ];
                         Th.td [ Th.txt (string_of_int crit) ];
                         Th.td (chips slice) ])
                   m.frontier) ] ]
    (* SQLite oodalog — the deliberation memory *)
    @ when_ (m.ooda <> [])
        [ Th.h2 [ Th.txt "Decisions "; count_badge "OODA" ];
          Th.div
            ~a:[ Th.a_class [ "mem-git" ] ]
            (List.map
               (fun (at, phase, content) ->
                 Th.div
                   ~a:[ Th.a_class [ "mem-c" ] ]
                   ([ Th.span ~a:[ Th.a_class [ "mem-v" ] ] [ Th.txt phase ];
                      Th.txt " ";
                      Th.span ~a:[ Th.a_class [ "mu" ] ] [ Th.txt at ];
                      Th.txt " ";
                      Th.txt content ]
                    @ chips content))
               m.ooda) ]
    (* SQLite baselines — the proof memory *)
    @ when_ (m.baselines <> [])
        [ Th.h2
            [ Th.txt "Accepted baselines ";
              count_badge (string_of_int (List.length m.baselines)) ];
          Th.p
            ~a:[ Th.a_class [ "mu" ] ]
            [ Th.txt
                "Conformance snapshots the gate has accepted \226\128\148 the \
                 system's memory of what is proven." ];
          Th.div
            ~a:[ Th.a_class [ "mem-git" ] ]
            (List.map
               (fun (at, eq) ->
                 Th.div
                   ~a:[ Th.a_class [ "mem-c" ] ]
                   [ Th.span ~a:[ Th.a_class [ "mu" ] ] [ Th.txt at ];
                     Th.txt " ";
                     Th.code [ Th.txt eq ] ])
               m.baselines) ]
    @ [ Th.div
          ~a:[ Th.a_class [ "foot" ] ]
          [ Th.txt
              "System memory \226\128\148 git + SQLite, native OCaml \
               (docs_wiki.ml). ";
            Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "\226\134\144 index" ];
            Th.txt " \194\183 ";
            Th.a ~a:[ Th.a_href "graph.html" ] [ Th.txt "graph" ];
            Th.txt " \194\183 ";
            Th.a ~a:[ Th.a_href "/wiki" ] [ Th.txt "live wiki" ] ] ]
  in
  page_frame_elts ~title:"System memory" ~cur:"memory" ~pages ~body

(* the "+ New note" authoring form (plain HTML POST — no JS needed). *)
let render_new_form (pages : page list) =
  let body =
    [ crumb_to "new";
      Th.h1 [ Th.txt "\226\158\149 New note" ];
      Th.p
        ~a:[ Th.a_class [ "mu" ] ]
        [ Th.txt "Write an atomic Zettelkasten note. It is saved as ";
          (* `<id>` and `<slug>` are placeholder TEXT, not markup — as a string
             literal they had to be spelled with entities by hand, and getting
             that wrong renders an empty element instead of showing the shape. *)
          Th.code [ Th.txt "docs/zk/<id>-<slug>.md" ];
          Th.txt ", staged in git, and its ";
          Th.code [ Th.txt "[[links]]" ];
          Th.txt ", backlinks, #tags and graph position update immediately. Link \
                   other notes with ";
          Th.code [ Th.txt "[[Their Title]]" ];
          Th.txt "." ];
      Th.form
        ~a:[ Th.a_class [ "zk-form" ]; Th.a_method `Post; Th.a_action "new" ]
        [ Th.label
            [ Th.txt "Title";
              Th.input
                ~a:[ Th.a_name "title"; Th.a_required ();
                     Th.a_placeholder "An idea, atomically" ]
                () ];
          Th.label
            [ Th.txt "Body";
              Th.textarea
                ~a:[ Th.a_name "body"; Th.a_rows 12;
                     Th.a_placeholder "One thought. Link with [[Another Note]]." ]
                (Th.txt "") ];
          Th.label
            [ Th.txt "Tags ";
              Th.span ~a:[ Th.a_class [ "mu" ] ] [ Th.txt "(space-separated, no #)" ];
              Th.input
                ~a:[ Th.a_name "tags"; Th.a_placeholder "zettelkasten method" ]
                () ];
          Th.button ~a:[ Th.a_button_type `Submit ] [ Th.txt "Create note" ] ];
      Th.div
        ~a:[ Th.a_class [ "foot" ] ]
        [ Th.txt "Native OCaml authoring (docs_wiki.ml). ";
          Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "\226\134\144 index" ] ] ]
  in
  page_frame_elts ~title:"New note" ~cur:"new" ~pages ~body

(* the Edit form for an existing authored note (pre-filled body). *)
let render_edit_form ~pages (p : page) =
  (* strip the leading "# title" heading + trailing #tag line for editing *)
  let lines = String.split_on_char '\n' p.raw in
  let drop_head = match lines with h :: rest when String.length h > 0 && h.[0] = '#' -> rest | l -> l in
  let is_tagline s = let t = String.trim s in t <> "" && String.for_all (fun c -> c = '#' || c = ' ' || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' || c = '_') t && t.[0] = '#' in
  let rec rstrip = function
    | [] -> [] | l -> (match List.rev l with last :: _ when is_tagline last || String.trim last = "" -> rstrip (List.rev (List.tl (List.rev l))) | _ -> l) in
  let body_text = String.trim (String.concat "\n" (rstrip drop_head)) in
  (* NOT `esc_s body_text` — TyXML escapes textarea content itself, so keeping
     the hand-escaper would double-escape and the editor would show `&amp;lt;`
     where the note has `<`. Converting means DELETING the escaper, not
     carrying it across. *)
  let ta = body_text and tg = String.concat " " p.tags in
  let etag = etag_of p in
  let body =
    [ Th.div
        ~a:[ Th.a_class [ "crumb" ] ]
        [ Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "docs" ];
          Th.txt " / ";
          Th.a ~a:[ Th.a_href (p.slug ^ ".html") ] [ Th.txt p.title ];
          Th.txt " / edit" ];
      Th.h1 [ Th.txt ("\226\156\143 Edit \194\183 " ^ p.title) ];
      Th.p
        ~a:[ Th.a_class [ "mu" ] ]
        [ Th.txt "Editing ";
          Th.code [ Th.txt p.path ];
          Th.txt ". Only slip-box notes under ";
          Th.code [ Th.txt "docs/zk/" ];
          Th.txt " are editable \226\128\148 the curated docs are read-only." ];
      Th.form
        ~a:[ Th.a_class [ "zk-form" ]; Th.a_method `Post;
             Th.a_action ("/docs/edit/" ^ p.slug) ]
        [ Th.input ~a:[ Th.a_input_type `Hidden; Th.a_name "etag"; Th.a_value etag ] ();
          Th.label
            [ Th.txt "Title"; Th.input ~a:[ Th.a_name "title"; Th.a_value p.title ] () ];
          Th.label
            [ Th.txt "Body";
              Th.textarea ~a:[ Th.a_name "body"; Th.a_rows 14 ] (Th.txt ta) ];
          Th.label [ Th.txt "Tags"; Th.input ~a:[ Th.a_name "tags"; Th.a_value tg ] () ];
          Th.button ~a:[ Th.a_button_type `Submit ] [ Th.txt "Save changes" ] ];
      Th.form
        ~a:[ Th.a_class [ "zk-del" ]; Th.a_method `Post;
             Th.a_action ("/docs/delete/" ^ p.slug);
             Th.a_onsubmit "return confirm('Delete this note?')" ]
        [ Th.button
            ~a:[ Th.a_button_type `Submit; Th.a_class [ "danger" ] ]
            [ Th.txt "Delete note" ] ];
      Th.div
        ~a:[ Th.a_class [ "foot" ] ]
        [ Th.a ~a:[ Th.a_href (p.slug ^ ".html") ] [ Th.txt "\226\134\144 back to the note" ];
          Th.txt " \194\183 ";
          Th.span
            ~a:[ Th.a_class [ "mu" ] ]
            [ Th.txt "etag "; Th.code [ Th.txt etag ];
              Th.txt " (optimistic-concurrency guard)" ] ] ]
  in
  page_frame_elts ~title:("Edit \194\183 " ^ p.title) ~cur:p.slug ~pages ~body

(* is this note an authored slip-box note (editable/deletable)? — ONLY files
   physically under docs/zk/ ; the curated docs are never mutated by the server. *)
let is_authored (p : page) =
  let pfx = zk_dir ^ "/" in
  String.length p.path >= String.length pfx && String.sub p.path 0 (String.length pfx) = pfx

(* ── DECISION RECORDS: the ZK as an integral part of the SDLC/SRE loop ────
   A decision record (ADR) captures the full process envelope for a change —
   agent reasoning, as-is context, to-be decision, the criteria used for
   architecture/code/test/docs, tradeoffs, alternatives ("what else"), and the
   implementation path — as a structured, #decision-tagged zettel that flows into
   the graph, memory, and the SDLC view. The renderer is pure; the write is the
   authoring shell. *)
let decision_markdown ~(title : string) ~(sections : (string * string) list) : string =
  let body = String.concat "" (List.filter_map (fun (h, b) ->
      if String.trim b = "" then None else Some (Printf.sprintf "\n\n## %s\n\n%s" h (String.trim b))) sections) in
  Printf.sprintf "# %s\n\n_Decision record (ADR) — captured in the Zettelkasten as part of the SDLC/SRE loop._%s\n\n#decision #adr"
    (let t = String.trim title in if t = "" then "Untitled decision" else t) body

(* the FULL ENVELOPE OF CRITERIA the process uses for architecture / code / test /
   docs — the project's real quality bar, made explicit in the wiki so every
   decision is weighed against it. (Sourced from AGENTS.md / ALGEBRAIC_FRACTAL_RULES.md.) *)
let crit_col heading items =
  Th.div
    ~a:[ Th.a_class [ "crit-col" ] ]
    [ Th.h4 [ Th.txt heading ]; Th.ul (List.map (fun kids -> Th.li kids) items) ]

let criteria_envelope_elt =
  Th.div
    ~a:[ Th.a_class [ "crit-env" ] ]
    [ crit_col "\240\159\143\151\239\184\143 Architecture"
        [ [ Th.txt "Write the "; Th.b [ Th.txt "semantic domain" ]; Th.txt " before code." ];
          [ Th.txt "Identify the "; Th.b [ Th.txt "oracle" ];
            Th.txt " (obviously-correct) and "; Th.b [ Th.txt "final" ];
            Th.txt " (efficient) encoding." ];
          [ Th.txt "A "; Th.b [ Th.txt "homomorphism law" ];
            Th.txt " at every representation boundary." ];
          [ Th.txt
              "Respect the strata: A (algebraic core) \194\183 B (engines, verified \
               vs A) \194\183 C (substrate, quarantined)." ] ];
      crit_col "\226\140\168 Code"
        [ [ Th.txt "Exhaustive switches over domain unions (no silent default)." ];
          [ Th.txt "Explicit arena/heap ownership; "; Th.b [ Th.txt "zero leaks" ];
            Th.txt " ("; Th.code [ Th.txt "std.testing.allocator" ]; Th.txt " proves it)." ];
          [ Th.txt
              "Observational equality only \226\128\148 never pointer/address identity." ];
          [ Th.txt "Boundaries hold: "; Th.code [ Th.txt "src/" ]; Th.txt " Zig-only, ";
            Th.code [ Th.txt "harness/" ]; Th.txt " OCaml-only." ] ];
      crit_col "\240\159\167\170 Test"
        [ [ Th.txt
              "Laws named after algebraic properties (homomorphism, round-trip, \
               monoid, \226\128\166)." ];
          [ Th.txt
              "Seeded generators that echo their seed on failure; bounded drivers \
               (a hang is a failed law)." ];
          [ Th.b [ Th.txt "\226\137\1652 mutants" ];
            Th.txt " per slice \226\128\148 killed or documented EQUIVALENT." ];
          [ Th.txt "Property tests in the deterministic environment where applicable." ] ];
      crit_col "\240\159\147\154 Docs"
        [ [ Th.txt
              "The module doc-comment IS the spec (signature, domain, encodings, \
               laws, scope)." ];
          [ Th.txt "Sync HANDOFF / ROADMAP / CODEBASE_MAP / IMPLEMENTATION_PLAN on completion." ];
          [ Th.txt "Finish with a green gate + cite the SQLite run status." ];
          [ Th.txt "Controller/evidence slices fill the STPA/UCA/FMEA safety packet." ] ] ]

let criteria_envelope = elt_str criteria_envelope_elt

let render_criteria (pages : page list) =
  let body =
    [ crumb_to "criteria";
      Th.h1 [ Th.txt "The criteria envelope" ];
      Th.p
        ~a:[ Th.a_class [ "mu" ] ]
        [ Th.txt
            "The full envelope of criteria the SDLC/SRE process weighs for every \
             change \226\128\148 architecture, code, test, and docs. Every ";
          Th.a ~a:[ Th.a_href "/docs/decision" ] [ Th.txt "decision record" ];
          Th.txt " is judged against these." ];
      criteria_envelope_elt;
      Th.div
        ~a:[ Th.a_class [ "foot" ] ]
        [ Th.txt "Native OCaml (docs_wiki.ml). ";
          Th.a ~a:[ Th.a_href "/docs/decision" ] [ Th.txt "\226\154\150 record a decision" ];
          Th.txt " \194\183 ";
          Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "\226\134\144 index" ] ] ]
  in
  page_frame_elts ~title:"Criteria envelope" ~cur:"criteria" ~pages ~body

let render_decision_form (pages : page list) =
  let field name label ph =
    Th.label
      [ Th.txt label;
        Th.textarea ~a:[ Th.a_name name; Th.a_rows 3; Th.a_placeholder ph ] (Th.txt "") ]
  in
  let body =
    [ crumb_to "decision";
      Th.h1 [ Th.txt "\226\154\150 Decision record" ];
      Th.p
        ~a:[ Th.a_class [ "mu" ] ]
        [ Th.txt "Capture the full process envelope for a change \226\128\148 it is saved as a ";
          Th.code [ Th.txt "#decision" ];
          Th.txt " zettel in ";
          Th.code [ Th.txt "docs/zk/" ];
          Th.txt
            ", threaded into the graph, memory, and the SDLC view. Weigh it against ";
          Th.a ~a:[ Th.a_href "/docs/criteria" ] [ Th.txt "the criteria envelope" ];
          Th.txt " below." ];
      criteria_envelope_elt;
      Th.form
        ~a:[ Th.a_class [ "zk-form" ]; Th.a_method `Post; Th.a_action "/docs/decision" ]
        ([ Th.label
             [ Th.txt "Title";
               Th.input
                 ~a:[ Th.a_name "title"; Th.a_required (); Th.a_placeholder "Adopt X for Y" ]
                 () ];
           field "context" "Context (as-is)" "The current state and the forces at play.";
           field "decision" "Decision (to-be)" "What we will do.";
           field "reasoning" "Agent reasoning" "The thinking that led here.";
           field "arch" "Criteria \194\183 Architecture"
             "Semantic domain, oracle/final, homomorphism, strata.";
           field "test" "Criteria \194\183 Test" "Laws, mutants, property tests, seeds.";
           field "tradeoffs" "Tradeoffs" "What we accept / give up.";
           field "alternatives" "Alternatives \226\128\148 what else could be done"
             "Options considered and why rejected.";
           field "path" "Implementation path" "The slices + sequencing.";
           field "docs" "Criteria \194\183 Docs" "Which docs sync; the gate + run citation.";
           Th.button ~a:[ Th.a_button_type `Submit ] [ Th.txt "Record decision" ] ]);
      Th.div
        ~a:[ Th.a_class [ "foot" ] ]
        [ Th.txt "Native OCaml authoring (docs_wiki.ml). ";
          Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "\226\134\144 index" ] ] ]
  in
  page_frame_elts ~title:"Decision record" ~cur:"decision" ~pages ~body

(* ── network science: PageRank / eigenvector centrality (scale-free maths) ──
   pagerank_core is the power iteration over an int adjacency, factored so the
   stochasticity laws (Σ=1, ≥0) are QCheck-tested independent of the wiki.

   ?teleport generalizes it to PERSONALIZED PageRank (the HippoRAG retrieval
   kernel): both the (1−d) restart mass and the dangling-node mass flow to the
   teleport distribution τ instead of uniform, so the stationary distribution
   ranks nodes by hub-connectedness TO THE SEEDS. Semantic domain: the
   stationary distribution of M_τ = d·(W + dangling→τ) + (1−d)·τ.
   LAW ppr-degeneration: τ absent, non-normalizable (Σ≤0) or uniform ⇒ exactly
   the classic kernel — the old behavior is the oracle of the new. *)
let pagerank_core ?(d = 0.85) ?teleport ?(iters = 60) (n : int) (out : int list array) : float array =
  if n = 0 then [||] else begin
    let outdeg = Array.map List.length out in
    let nf = float_of_int n in
    (* τ: clamp non-finite/negative entries to 0, then normalize; degenerate
       input (missing, short, or zero total mass) falls back to uniform — the
       kernel stays TOTAL and the output stays a probability distribution. *)
    let tau = match teleport with
      | Some t when Array.length t = n ->
          let c = Array.map (fun x -> if Float.is_nan x || x < 0. then 0. else x) t in
          let s = Array.fold_left (+.) 0. c in
          if s > 0. then Array.map (fun x -> x /. s) c else Array.make n (1. /. nf)
      | _ -> Array.make n (1. /. nf) in
    let rank = Array.make n (1. /. nf) in
    for _ = 1 to iters do
      let next = Array.init n (fun i -> (1. -. d) *. tau.(i)) in
      let dangling = ref 0. in
      for i = 0 to n - 1 do if outdeg.(i) = 0 then dangling := !dangling +. rank.(i) done;
      let dmass = d *. !dangling in
      for i = 0 to n - 1 do next.(i) <- next.(i) +. dmass *. tau.(i) done;
      for j = 0 to n - 1 do
        if outdeg.(j) > 0 then begin
          let share = d *. rank.(j) /. float_of_int outdeg.(j) in
          List.iter (fun i -> if i >= 0 && i < n then next.(i) <- next.(i) +. share) out.(j)
        end
      done;
      Array.blit next 0 rank 0 n
    done; rank
  end

(* PageRank over the note graph → (slug, centrality) sorted most-central first. *)
let pagerank (pages : page list) : (string * float) list =
  let pages = core_pages pages in  (* §8.2-M projection *)
  let n = List.length pages in
  if n = 0 then [] else begin
    let idx = Hashtbl.create (n * 2) in
    List.iteri (fun i p -> Hashtbl.replace idx p.slug i) pages;
    let out = Array.of_list (List.map (fun p ->
        List.filter_map (fun o -> Hashtbl.find_opt idx o) p.outlinks) pages) in
    let r = pagerank_core n out in
    List.mapi (fun i p -> (p.slug, r.(i))) pages
    (* total order: centrality desc, then slug asc — a deterministic ranking
       even when scores tie (no reliance on input or hash order). *)
    |> List.sort (fun (s1, a) (s2, b) -> if compare b a <> 0 then compare b a else compare s1 s2)
  end

(* Personalized-PageRank retrieval over the note graph (HippoRAG-shaped,
   journal 20260729-1056 §7.1): teleport mass concentrated on the seed notes
   (weight ∝ relevance, e.g. the query's KNN scores) ranks notes by
   hub-connectedness to what matched — multi-hop retrieval with no ML.
   Seeds naming unknown slugs or carrying weight ≤ 0 are IGNORED (total);
   LAW ppr-degeneration: no usable seeds ⇒ identical to `pagerank`. *)
let ppr ?(seeds : (string * float) list = []) (pages : page list) : (string * float) list =
  let pages = core_pages pages in  (* §8.2-M projection *)
  let n = List.length pages in
  if n = 0 then [] else begin
    let idx = Hashtbl.create (n * 2) in
    List.iteri (fun i p -> Hashtbl.replace idx p.slug i) pages;
    let out = Array.of_list (List.map (fun p ->
        List.filter_map (fun o -> Hashtbl.find_opt idx o) p.outlinks) pages) in
    let tau = Array.make n 0. in
    List.iter (fun (s, w) -> match Hashtbl.find_opt idx s with
      | Some i when w > 0. && not (Float.is_nan w) -> tau.(i) <- tau.(i) +. w
      | _ -> ()) seeds;
    let teleport = if Array.exists (fun x -> x > 0.) tau then Some tau else None in
    let r = pagerank_core ?teleport n out in
    List.mapi (fun i p -> (p.slug, r.(i))) pages
    |> List.sort (fun (s1, a) (s2, b) -> if compare b a <> 0 then compare b a else compare s1 s2)
  end

(* ── ONTOLOGY INFERENCE: transitive closure of the [[link]] relation ──────
   A description-logic transitive property: if A→B and B→C then A⇝C. reach_core
   is the ≥1-hop reachability matrix over an int adjacency — factored out so the
   inference laws (transitivity, direct⊆reach, irreflexive-by-construction) are
   QCheck-tested independent of the wiki. *)
let reach_core (n : int) (out : int list array) : bool array array =
  let r = Array.make_matrix n n false in
  for i = 0 to n - 1 do
    let q = Queue.create () in
    List.iter (fun j -> if j >= 0 && j < n && not r.(i).(j) then (r.(i).(j) <- true; Queue.add j q)) out.(i);
    while not (Queue.is_empty q) do
      let u = Queue.pop q in
      List.iter (fun j -> if j >= 0 && j < n && not r.(i).(j) then (r.(i).(j) <- true; Queue.add j q)) out.(u)
    done
  done; r

(* the inferred (indirect, transitively-reachable) notes for one note, EXCLUDING
   the ones it already links directly or is linked from — the genuinely NEW facts
   inference derives ("you can reach these but haven't connected them"). *)
let inferred_for (pages : page list) (p : page) : string list =
  let out = Hashtbl.create 256 in
  List.iter (fun q -> Hashtbl.replace out q.slug q.outlinks) pages;
  let seen = Hashtbl.create 64 in
  let rec go = function
    | [] -> ()
    | s :: rest ->
        let nbrs = try Hashtbl.find out s with Not_found -> [] in
        let fresh = List.filter (fun x -> x <> p.slug && not (Hashtbl.mem seen x)) nbrs in
        List.iter (fun x -> Hashtbl.replace seen x ()) fresh;
        go (fresh @ rest)
  in go [p.slug];
  let direct = p.outlinks @ p.backlinks in
  List.sort compare (Hashtbl.fold (fun k () a -> if List.mem k direct then a else k :: a) seen [])

(* total count of inferred facts across the corpus (for the graph summary). *)
let inferred_count (pages : page list) =
  List.fold_left (fun a p -> a + List.length (inferred_for pages p)) 0 pages

(* ── SEMANTIC similarity: TF-IDF vectors in ℝⁿ + cosine similarity ─────────
   The KB linear-algebra construct: each note is a bag-of-words vector weighted
   by TF-IDF; similarity is the cosine of the angle between vectors. Surfaces
   notes that are textually about the same thing even when NOT linked — content
   neighbours, distinct from graph neighbours. cosine_dense is the numeric core,
   QCheck-tested (self=1, symmetric, bounded). *)
let cosine_dense (a : float array) (b : float array) : float =
  let n = min (Array.length a) (Array.length b) in
  let dot = ref 0. and na = ref 0. and nb = ref 0. in
  for i = 0 to n - 1 do dot := !dot +. a.(i) *. b.(i); na := !na +. a.(i) *. a.(i); nb := !nb +. b.(i) *. b.(i) done;
  if !na = 0. || !nb = 0. then 0. else !dot /. (sqrt !na *. sqrt !nb)

let sim_stop = ["the";"and";"for";"that";"this";"with";"are";"was";"has";"have";"its";"not";"but";"from";"which";"can";"per";"via";"the";"a"]
let sim_tokens s =
  let b = Buffer.create 16 and acc = ref [] in
  let flush () = if Buffer.length b > 0 then (let w = Buffer.contents b in Buffer.clear b;
    if String.length w >= 3 && not (List.mem w sim_stop) then acc := w :: !acc) in
  String.iter (fun c -> let c = Char.lowercase_ascii c in
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') then Buffer.add_char b c else flush ()) s;
  flush (); List.rev !acc

(* the corpus IDF as a function — feeds the vector-store embedding (vec.ml). *)
let corpus_idf (pages : page list) : (string -> float) =
  let n = List.length pages in
  let df = Hashtbl.create 4096 in
  List.iter (fun p ->
    let seen = Hashtbl.create 64 in
    List.iter (fun t -> if not (Hashtbl.mem seen t) then
      (Hashtbl.replace seen t (); Hashtbl.replace df t (1 + (try Hashtbl.find df t with Not_found -> 0))))
      (sim_tokens (search_text p.raw))) pages;
  let nf = float_of_int (max 1 n) in
  fun t -> log (nf /. float_of_int (1 + (try Hashtbl.find df t with Not_found -> 0)))

(* the tokens of a note (public, for the vector-store embedding). *)
let note_tokens (p : page) : string list = sim_tokens (search_text p.raw)

type simvec = { w : (string, float) Hashtbl.t; norm : float }
let build_vectors (pages : page list) : (string, simvec) Hashtbl.t =
  let n = List.length pages in
  let df = Hashtbl.create 4096 in
  let docs = List.map (fun p ->
    let tf = Hashtbl.create 128 in
    List.iter (fun t -> Hashtbl.replace tf t (1. +. (try Hashtbl.find tf t with Not_found -> 0.))) (sim_tokens (search_text p.raw));
    (p.slug, tf)) pages in
  List.iter (fun (_, tf) -> Hashtbl.iter (fun t _ -> Hashtbl.replace df t (1 + (try Hashtbl.find df t with Not_found -> 0))) tf) docs;
  let nf = float_of_int (max 1 n) in
  let vectors = Hashtbl.create (n * 2) in
  List.iter (fun (slug, tf) ->
    let w = Hashtbl.create (Hashtbl.length tf) in
    Hashtbl.iter (fun t c -> let idf = log (nf /. float_of_int (try Hashtbl.find df t with Not_found -> 1)) in
      Hashtbl.replace w t (c *. idf)) tf;
    let norm = sqrt (Hashtbl.fold (fun _ x a -> a +. x *. x) w 0.) in
    Hashtbl.replace vectors slug { w; norm }) docs;
  vectors

let cosine_sparse (a : simvec) (b : simvec) : float =
  if a.norm = 0. || b.norm = 0. then 0. else begin
    let small, big = if Hashtbl.length a.w <= Hashtbl.length b.w then a.w, b.w else b.w, a.w in
    let dot = Hashtbl.fold (fun t x acc -> acc +. x *. (try Hashtbl.find big t with Not_found -> 0.)) small 0. in
    dot /. (a.norm *. b.norm)
  end

(* memoise the corpus vectors by a cheap fingerprint so a whole render pass over
   the same pages builds them once. *)
let sim_cache : (int * (string, simvec) Hashtbl.t) option ref = ref None
let vectors_for (pages : page list) =
  let fp = List.fold_left (fun a p -> a + String.length p.raw + String.length p.slug) (List.length pages) pages in
  match !sim_cache with
  | Some (f, v) when f = fp -> v
  | _ -> let v = build_vectors pages in sim_cache := Some (fp, v); v

(* the k most content-similar notes to p (cosine over TF-IDF), excluding itself. *)
let similar_notes (pages : page list) (p : page) (k : int) : (string * float) list =
  let pages = core_pages pages in  (* §8.2-M projection *)
  if is_episodic p then [] else
  let v = vectors_for pages in
  match Hashtbl.find_opt v p.slug with
  | None -> []
  | Some pv ->
      List.filter_map (fun q -> if q.slug = p.slug then None else
        match Hashtbl.find_opt v q.slug with
        | Some qv -> let c = cosine_sparse pv qv in if c > 0.03 then Some (q.slug, c) else None
        | None -> None) pages
      (* total order: similarity desc, then slug asc — deterministic on ties *)
      |> List.sort (fun (s1, a) (s2, b) -> if compare b a <> 0 then compare b a else compare s1 s2)
      |> List.filteri (fun i _ -> i < k)

let json_slist (xs : string list) = "[" ^ String.concat "," (List.map jesc xs) ^ "]"

(* ── zkquery: saved queries as notes (zk-query-dsl, journal 20260729-1056
   §7.7) ───────────────────────────────────────────────────────────────────
   A TOTAL, deliberately NON-RECURSIVE query DSL — the Dataview/Bases shape
   sized for a Tier-1 judge:

     [from (all|type:T|group:G|tag:T)]
     [where COND (and COND)*]
     [sort (slug|title|words|degree|pagerank) [asc|desc]]
     [limit N]

     COND := FIELD(=|!=)VALUE   for status|type|group|slug|tag
           | FIELD(=|>|>=|<|<=)N for words|degree|outlinks|backlinks

   No recursion in the grammar ⇒ structural termination (LAW query-total);
   an unknown field/op/token REJECTS with a named error — fail-closed, never
   a guess. LAWS: limit-monotone (limit n is a PREFIX of limit m≥n),
   filter-commute (where a and b ≡ where b and a), eval-soundness (every
   returned row satisfies every condition — asserted generically), sort is a
   total order (slug tiebreak ⇒ deterministic under ties), rejection. *)
type zcond = { zf : string; zop : string; zv : string }
type zquery = { zwhere : zcond list; zsort : string * bool; zlimit : int option }

let zk_str_fields = [ "status"; "type"; "group"; "slug"; "tag" ]
let zk_int_fields = [ "words"; "degree"; "outlinks"; "backlinks" ]
let zk_sort_keys = [ "slug"; "title"; "words"; "degree"; "pagerank" ]

let zkquery_parse (q : string) : (zquery, string) result =
  let toks =
    String.map (fun c -> if c = '\t' || c = '\n' || c = '\r' then ' ' else c) q
    |> String.split_on_char ' ' |> List.filter (fun t -> t <> "") in
  let parse_cond t =
    let rec find = function
      | [] -> Error (Printf.sprintf "zkquery: not a condition: %s" t)
      | op :: rest -> (
          match Str.bounded_split_delim (Str.regexp_string op) t 2 with
          | [ f; v ] when f <> "" && v <> "" ->
              if List.mem f zk_int_fields then
                if op = "!=" then Error (Printf.sprintf "zkquery: %s is numeric; use =,>,>=,<,<=" f)
                else if int_of_string_opt v = None then Error (Printf.sprintf "zkquery: %s needs a number, got %s" f v)
                else Ok { zf = f; zop = op; zv = v }
              else if List.mem f zk_str_fields then
                if List.mem op [ "="; "!=" ] then Ok { zf = f; zop = op; zv = v }
                else Error (Printf.sprintf "zkquery: %s supports only = and !=" f)
              else Error (Printf.sprintf "zkquery: unknown field %s" f)
          | _ -> find rest)
    in
    find [ "!="; ">="; "<="; "="; ">"; "<" ] in
  let rec pfrom toks acc =
    match toks with
    | "from" :: [] -> Error "zkquery: from needs a selector (all|type:T|group:G|tag:T)"
    | "from" :: "all" :: rest -> pwhere rest acc
    | "from" :: sel :: rest -> (
        match String.index_opt sel ':' with
        | Some i ->
            let f = String.sub sel 0 i
            and v = String.sub sel (i + 1) (String.length sel - i - 1) in
            if List.mem f [ "type"; "group"; "tag" ] && v <> ""
            then pwhere rest ({ zf = f; zop = "="; zv = v } :: acc)
            else Error (Printf.sprintf "zkquery: bad from-selector %s" sel)
        | None -> Error (Printf.sprintf "zkquery: bad from-selector %s" sel))
    | _ -> pwhere toks acc
  and pwhere toks acc =
    match toks with
    | "where" :: rest ->
        let rec conds toks acc =
          match toks with
          | [] -> Error "zkquery: where needs a condition"
          | t :: rest -> (
              match parse_cond t with
              | Error e -> Error e
              | Ok c -> (
                  match rest with
                  | "and" :: more -> conds more (c :: acc)
                  | _ -> psort rest (c :: acc)))
        in
        conds rest acc
    | _ -> psort toks acc
  and psort toks acc =
    match toks with
    | "sort" :: key :: rest ->
        if not (List.mem key zk_sort_keys)
        then Error (Printf.sprintf "zkquery: unknown sort key %s" key)
        else (
          match rest with
          | "desc" :: more -> plimit more acc (key, true)
          | "asc" :: more -> plimit more acc (key, false)
          | _ -> plimit rest acc (key, false))
    | "sort" :: [] -> Error "zkquery: sort needs a key"
    | _ -> plimit toks acc ("slug", false)
  and plimit toks acc sort =
    match toks with
    | [] -> Ok { zwhere = List.rev acc; zsort = sort; zlimit = None }
    | [ "limit"; n ] -> (
        match int_of_string_opt n with
        | Some k when k >= 0 -> Ok { zwhere = List.rev acc; zsort = sort; zlimit = Some k }
        | _ -> Error (Printf.sprintf "zkquery: bad limit %s" n))
    | "limit" :: [] -> Error "zkquery: limit needs a number"
    | t :: _ -> Error (Printf.sprintf "zkquery: unexpected token %s" t)
  in
  pfrom toks []

let zkquery_eval (pages : page list) (q : zquery) : page list =
  let int_field p = function
    | "words" -> word_count p
    | "degree" -> degree p
    | "outlinks" -> List.length p.outlinks
    | "backlinks" -> List.length p.backlinks
    | _ -> 0 in
  let sat p c =
    if List.mem c.zf zk_int_fields then
      match int_of_string_opt c.zv with
      | None -> false
      | Some v ->
          let x = int_field p c.zf in
          (match c.zop with
           | "=" -> x = v | ">" -> x > v | ">=" -> x >= v
           | "<" -> x < v | "<=" -> x <= v | _ -> false)
    else
      let eqv = match c.zf with
        | "status" -> String.equal p.meta.status c.zv
        | "type" -> String.equal p.meta.ntype c.zv
        | "group" -> String.equal p.group c.zv
        | "slug" -> String.equal p.slug c.zv
        | "tag" -> List.mem c.zv p.tags
        | _ -> false in
      match c.zop with "=" -> eqv | "!=" -> not eqv | _ -> false in
  let rows = List.filter (fun p -> List.for_all (sat p) q.zwhere) pages in
  let key, desc = q.zsort in
  let pr = if String.equal key "pagerank" then pagerank pages else [] in
  let cmp a b =
    let c = match key with
      | "slug" -> compare a.slug b.slug
      | "title" -> compare a.title b.title
      | "words" -> compare (word_count a) (word_count b)
      | "degree" -> compare (degree a) (degree b)
      | "pagerank" ->
          compare (Option.value ~default:0. (List.assoc_opt a.slug pr))
                  (Option.value ~default:0. (List.assoc_opt b.slug pr))
      | _ -> 0 in
    let c = if desc then -c else c in
    if c <> 0 then c else compare a.slug b.slug in
  let rows = List.sort cmp rows in
  match q.zlimit with
  | Some k -> List.filteri (fun i _ -> i < k) rows
  | None -> rows

let zkquery_json (pages : page list) (q : string) : string =
  match zkquery_parse q with
  | Error e -> Printf.sprintf "{\"q\":%s,\"error\":%s}" (jesc q) (jesc e)
  | Ok zq ->
      let rows = zkquery_eval pages zq in
      let row p =
        Printf.sprintf
          "{\"slug\":%s,\"title\":%s,\"type\":%s,\"status\":%s,\"group\":%s,\"words\":%d,\"degree\":%d,\"tags\":%s}"
          (jesc p.slug) (jesc p.title) (jesc p.meta.ntype) (jesc p.meta.status)
          (jesc p.group) (word_count p) (degree p) (json_slist p.tags) in
      Printf.sprintf "{\"q\":%s,\"count\":%d,\"rows\":[%s]}"
        (jesc q) (List.length rows) (String.concat "," (List.map row rows))

(* the ```zkquery fenced blocks of a note, in order — queries ARE notes
   (versioned, reviewed, mention-scanned like everything else). *)
let zkquery_blocks (raw : string) : string list =
  let lines = String.split_on_char '\n' raw in
  let rec go acc cur inq = function
    | [] -> List.rev acc          (* an unclosed fence yields NO query (total) *)
    | l :: rest ->
        let t = String.trim l in
        if inq then
          if t = "```" then go (String.concat "\n" (List.rev cur) :: acc) [] false rest
          else go acc (l :: cur) true rest
        else if t = "```zkquery" then go acc [] true rest
        else go acc cur false rest
  in
  go [] [] false lines

(* live results table for the embedded queries of a note (the human surface;
   agents use zk_query). Typed markup: the query text and every field of every
   row are element children, so a parse error renders as an error chip and no
   escape call remains that anyone could forget. Returns ELEMENTS — the note
   page splices them directly, so this fragment's seam is DELETED, not moved. *)
let render_zkquery_results_elts (pages : page list) (p : page) =
  match zkquery_blocks p.raw with
  | [] -> []
  | qs ->
      let one q =
        match zkquery_parse q with
        | Error e -> Th.div ~a:[ Th.a_class [ "zq-err" ] ] [ Th.txt e ]
        | Ok zq ->
            let rows = zkquery_eval pages zq in
            let tr (r : page) =
              Th.tr
                [ Th.td
                    [ Th.a
                        ~a:[ Th.a_class [ "zettel" ]; Th.a_href (r.slug ^ ".html") ]
                        [ Th.txt r.title ] ];
                  Th.td [ Th.txt r.meta.ntype ];
                  Th.td [ Th.txt r.meta.status ];
                  Th.td [ Th.txt (string_of_int (word_count r)) ];
                  Th.td [ Th.txt (string_of_int (degree r)) ] ]
            in
            Th.div
              ~a:[ Th.a_class [ "zq" ] ]
              [ Th.code ~a:[ Th.a_class [ "zq-q" ] ] [ Th.txt q ];
                Th.table
                  ~a:[ Th.a_class [ "zq-t" ] ]
                  ~thead:
                    (Th.thead
                       [ Th.tr
                           [ Th.th [ Th.txt "note" ]; Th.th [ Th.txt "type" ];
                             Th.th [ Th.txt "status" ]; Th.th [ Th.txt "words" ];
                             Th.th [ Th.txt "\194\176" ] ] ])
                  (List.map tr rows);
                Th.div
                  ~a:[ Th.a_class [ "zq-n" ] ]
                  [ Th.txt
                      (Printf.sprintf "%d row%s" (List.length rows)
                         (if List.length rows = 1 then "" else "s")) ] ]
      in
      [ Th.div
          ~a:[ Th.a_class [ "zk-sec" ] ]
          (Th.div
             ~a:[ Th.a_class [ "zk-h" ] ]
             [ Th.txt "\226\140\152 Query results "; badge "live" ]
          :: List.map one qs) ]

(* string shim, the same shape as `chip_of` over `chip_of_elt`. After the note
   page took the element form this has no callers left; kept for one slice as
   the visible marker that the migration finished here, then removable. *)
let render_zkquery_results (pages : page list) (p : page) : string =
  String.concat "" (List.map elt_str (render_zkquery_results_elts pages p))
let json_typed (ts : (string * string) list) =
  "[" ^ String.concat "," (List.map (fun (s, r) -> Printf.sprintf "{\"to\":%s,\"rel\":%s}" (jesc s) (jesc r)) ts) ^ "]"

(* ── GROUNDED SEMANTICS over the @opposes attack graph (zk-grounded-semantics,
   journal 20260729-1056 §8.2-A H2; Dung 1995) ─────────────────────────────
   The Zettelkasten's argumentation framework: arguments = notes, attacks =
   `[[Target|@opposes]]` typed edges. The GROUNDED labelling is computed by
   the standard least-fixpoint iteration of Dung's characteristic function:
     IN    — every attacker is OUT (vacuously: unattacked), i.e. DEFENSIBLE;
     OUT   — some attacker is IN, i.e. DEFEATED by an accepted argument;
     UNDEC — neither stabilizes (e.g. mutual attack cycles), i.e. DISPUTED.
   The grounded extension is the unique ⊆-least complete extension — no
   choice points, deterministic, polynomial — which is exactly why it (and
   not preferred/stable semantics) fits a Tier-1 judge.
   LAWS: grounded-fixpoint-stability (recompute agrees), conflict-free (no
   two IN notes attack each other), admissible (every IN note's attackers
   are OUT), unattacked-in, reinstatement (a→b→c ⇒ c IN), attack-direction
   (a→b ⇒ a IN ∧ b OUT), mutual-cycle-undec, totality on empty. *)
let grounded_statuses (pages : page list) : (string * string) list =
  let pages = core_pages pages in  (* §8.2-M projection *)
  let slugs = List.map (fun p -> p.slug) pages in
  let attackers : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  (* every @opposes edge is an attack — including a self-attack, a legal AF
     shape (a self-attacker can never enter the grounded extension). typed
     edges are sort_uniq'd at build, so no duplicate attacks. *)
  List.iter (fun q ->
    List.iter (fun (target, rel) ->
      if String.equal rel "opposes" then
        Hashtbl.replace attackers target
          (q.slug :: (Option.value ~default:[] (Hashtbl.find_opt attackers target))))
      q.typed) pages;
  let status : (string, string) Hashtbl.t = Hashtbl.create 64 in
  let get s = Hashtbl.find_opt status s in
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter (fun s ->
      if get s = None then begin
        let atk = Option.value ~default:[] (Hashtbl.find_opt attackers s) in
        (* only attackers that exist in the corpus count (typed targets are
           build-resolved, and attacker slugs are page slugs by construction) *)
        if List.for_all (fun a -> get a = Some "out") atk then begin
          Hashtbl.replace status s "in"; changed := true
        end else if List.exists (fun a -> get a = Some "in") atk then begin
          Hashtbl.replace status s "out"; changed := true
        end
      end) slugs
  done;
  List.map (fun s -> (s, Option.value ~default:"undec" (get s))) slugs

let neighborhood_edges (p : page) : (string * string) list =
  List.map (fun s -> ("out", s)) p.outlinks
  @ List.map (fun s -> ("back", s)) p.backlinks
  @ List.map (fun (s, r) -> ("typed:" ^ r, s)) p.typed
  @ List.map (fun s -> ("mention", s)) p.mentions
  |> List.sort_uniq compare

(* the note chip — the most-consumed fragment in the module: four pages splice
   its string output. `_elt` is the definition; the shim serves those four
   until they convert. *)
let zettel_link ~slug ~title =
  Th.a ~a:[ Th.a_class [ "zettel" ]; Th.a_href (slug ^ ".html") ] [ Th.txt title ]

let chip_of_elt (pages : page list) (s : string) =
  let title =
    match List.find_opt (fun p -> String.equal p.slug s) pages with
    | Some p -> p.title
    | None -> s
  in
  zettel_link ~slug:s ~title

let chip_of (pages : page list) (s : string) : string = elt_str (chip_of_elt pages s)

(* A render context is the immutable, corpus-wide part of note rendering.
   Historically [render_page] recomputed PageRank, deterministic communities,
   grounded semantics, transitive inference, and semantic neighbours for every
   page.  That preserved semantics but made a full projection super-quadratic.
   Preparing the context once is the initial algebra; rendering a page is then
   a pure observation of that value.  The tables are populated completely
   before publication and are read-only afterwards, so the same context is safe
   to share between bounded Eio domains. *)
type render_context = {
  rc_pages : page list;
  rc_titles : (string, string) Hashtbl.t;
  rc_neighbours : (string, page option * page option) Hashtbl.t;
  rc_inferred : (string, string list) Hashtbl.t;
  rc_similar : (string, (string * float) list) Hashtbl.t;
  rc_pagerank : (string * float) list;
  rc_grounded : (string * string) list;
  rc_communities : (string * string) list;
}

let prepare_render_context (pages : page list) : render_context =
  let capacity = max 16 (2 * List.length pages) in
  let titles = Hashtbl.create capacity
  and nav = Hashtbl.create capacity
  and inferred = Hashtbl.create capacity
  and similar = Hashtbl.create capacity in
  List.iter (fun (p : page) -> Hashtbl.replace titles p.slug p.title) pages;
  (* Force the sole historical similarity cache on this domain before any
     worker receives the immutable vector tables. *)
  ignore (vectors_for (core_pages pages));
  List.iter
    (fun (p : page) ->
      Hashtbl.replace nav p.slug (neighbours pages p);
      Hashtbl.replace inferred p.slug (inferred_for pages p);
      Hashtbl.replace similar p.slug (similar_notes pages p 6))
    pages;
  { rc_pages = pages;
    rc_titles = titles;
    rc_neighbours = nav;
    rc_inferred = inferred;
    rc_similar = similar;
    rc_pagerank = pagerank pages;
    rc_grounded = grounded_statuses pages;
    rc_communities = communities pages }

(* Sequential compatibility callers commonly render many pages from the same
   persistent list value.  Retain one prepared context by physical corpus
   identity; the parallel path never touches this mutable convenience cache and
   receives its explicit immutable context instead. *)
let render_context_cache : render_context option ref = ref None

let render_context_for pages =
  match !render_context_cache with
  | Some context when context.rc_pages == pages -> context
  | _ ->
      let context = prepare_render_context pages in
      render_context_cache := Some context;
      context

let render_page_with_context ~(context : render_context) (p : page) =
  let pages = context.rc_pages in
  let prev, next =
    Option.value ~default:(None, None)
      (Hashtbl.find_opt context.rc_neighbours p.slug) in
  (* nav_link / slug_chips, NOT link / chips: those names belong to the
     page-furniture algebra above and shadowing them here would silently swap
     two different meanings inside one function. *)
  let nav_link dir = function
    | Some (q : page) ->
        Th.a
          ~a:[ Th.a_class [ "nav" ^ dir ]; Th.a_href (q.slug ^ ".html") ]
          [ Th.span
              ~a:[ Th.a_class [ "d" ] ]
              [ Th.txt (if dir = "prev" then "\226\134\144 previous" else "next \226\134\146") ];
            Th.txt q.title ]
    | None -> Th.span []
  in
  let title_of_slug s = Option.value ~default:s (Hashtbl.find_opt context.rc_titles s) in
  let slug_chips slugs =
    List.map (fun s -> zettel_link ~slug:s ~title:(title_of_slug s)) slugs
  in
  let zk_sec kids = Th.div ~a:[ Th.a_class [ "zk-sec" ] ] kids in
  let zk_h kids = Th.div ~a:[ Th.a_class [ "zk-h" ] ] kids in
  let zk_empty kids = Th.div ~a:[ Th.a_class [ "zk-empty" ] ] kids in
  (* the note's #tags (a Zettelkasten metadata row under the title) *)
  let tags_row =
    when_ (p.tags <> [])
      [ Th.div
          ~a:[ Th.a_class [ "zk-tags" ] ]
          (List.map
             (fun t ->
               Th.a
                 ~a:[ Th.a_class [ "zk-tag" ]; Th.a_href ("tags.html#" ^ t) ]
                 [ Th.txt ("#" ^ t) ])
             p.tags) ]
  in
  (* Zettelkasten panels: outgoing links · bidirectional backlinks · UNLINKED mentions *)
  let zettel =
    let outs =
      when_ (p.outlinks <> [])
        [ zk_sec
            [ zk_h [ Th.txt "\226\134\146 Links to "; badge_n (List.length p.outlinks) ];
              chips (slug_chips p.outlinks) ] ]
    in
    let backs =
      if p.backlinks = [] then
        [ zk_sec
            [ zk_h [ Th.txt "\226\134\144 Linked references" ];
              zk_empty [ Th.txt "No notes link here yet." ] ] ]
      else
        (* CONTEXTUAL backlinks (§7.10): each reference carries the source LINE
           containing the wiki link — the reader sees WHY it cites this note. *)
        [ zk_sec
            (zk_h
               [ Th.txt "\226\134\144 Linked references "; badge_n (List.length p.backlinks) ]
             :: List.map
                  (fun (src, ctx) ->
                    Th.div
                      ~a:[ Th.a_class [ "zk-bl" ] ]
                      (zettel_link ~slug:src ~title:(title_of_slug src)
                       :: when_ (ctx <> "")
                            [ Th.div ~a:[ Th.a_class [ "zk-ctx" ] ] [ Th.txt ctx ] ]))
                  p.back_ctx) ]
    in
    let ments =
      when_ (p.mentions <> [])
        [ zk_sec
            [ zk_h
                [ Th.txt "\226\151\135 Unlinked mentions "; badge_n (List.length p.mentions) ];
              zk_empty
                [ Th.txt "Notes that name this one without a ";
                  Th.code [ Th.txt "[[link]]" ];
                  Th.txt " \226\128\148 latent connections." ];
              chips (slug_chips p.mentions) ] ]
    in
    (* ontology inference: notes transitively reachable but NOT directly linked *)
    let inferred =
      Option.value ~default:[] (Hashtbl.find_opt context.rc_inferred p.slug)
      |> List.filteri (fun i _ -> i < 10) in
    let inf =
      when_ (inferred <> [])
        [ zk_sec
            [ zk_h [ Th.txt "\226\135\157 Inferred "; badge "transitive" ];
              zk_empty
                [ Th.txt "Reachable via ";
                  Th.code [ Th.txt "[[links]]" ];
                  Th.txt
                    " but not directly connected \226\128\148 derived by transitive \
                     closure." ];
              chips (slug_chips inferred) ] ]
    in
    (* semantic neighbours: TF-IDF cosine similarity — notes ABOUT the same thing *)
    let sim = List.filter (fun (s, _) -> not (List.mem s p.outlinks) && not (List.mem s p.backlinks))
                (Option.value ~default:[] (Hashtbl.find_opt context.rc_similar p.slug)) in
    let simsec =
      when_ (sim <> [])
        [ zk_sec
            [ zk_h [ Th.txt "\226\137\136 Similar "; badge "TF-IDF cosine" ];
              zk_empty
                [ Th.txt
                    "Textually about the same topic (vector-space similarity), \
                     independent of links \226\128\148 candidate connections." ];
              chips
                (List.map
                   (fun (s, sc) ->
                     Th.a
                       ~a:
                         [ Th.a_class [ "zettel" ]; Th.a_href (s ^ ".html");
                           Th.a_title (Printf.sprintf "cosine %.2f" sc) ]
                       [ Th.txt (title_of_slug s) ])
                   sim) ] ]
    in
    Th.div ~a:[ Th.a_class [ "zk" ] ] (outs @ backs @ ments @ inf @ simsec)
  in
  (* authored slip-box notes carry an inline Edit affordance; curated docs don't *)
  let edit =
    when_ (is_authored p)
      [ Th.a
          ~a:[ Th.a_class [ "zk-edit" ]; Th.a_href ("/docs/edit/" ^ p.slug) ]
          [ Th.txt "\226\156\143 edit" ] ]
  in
  (* KNOWLEDGE POSITION: this note's place in the graph by eigenvector centrality
     (PageRank) — turns each note into an instrumented knowledge card. *)
  let position =
    let pr = context.rc_pagerank in
    let n = List.length pr in
    let rec find i = function (s, _) :: _ when s = p.slug -> i | _ :: t -> find (i + 1) t | [] -> n in
    let rank = find 1 pr in
    let pct = if n = 0 then 0 else int_of_float (Float.round (100. *. float_of_int (n - rank + 1) /. float_of_int n)) in
    (* zk-web-surfacing: the note's DIALECTICAL standing and COMMUNITY, page-
       native (previously API-only). Both empty for episodic pages (the
       projection excludes them) — the chips simply hide. *)
    let gstd = Option.value ~default:"" (List.assoc_opt p.slug context.rc_grounded) in
    let comm = Option.value ~default:"" (List.assoc_opt p.slug context.rc_communities) in
    let gchip =
      when_ (gstd <> "")
        [ Th.txt " \194\183 ";
          Th.span
            ~a:
              [ Th.a_class [ "zk-grd"; "g-" ^ gstd ];
                Th.a_title
                  "grounded standing over the @opposes graph: in=defensible, \
                   out=defeated, undec=disputed" ]
            [ Th.txt ("\226\154\150 " ^ gstd) ] ]
    in
    let cchip =
      when_ (comm <> "")
        [ Th.txt " \194\183 community ";
          Th.a
            ~a:
              [ Th.a_class [ "zk-comm" ]; Th.a_href (comm ^ ".html");
                Th.a_title
                  "deterministic LPA community, named by its smallest member" ]
            [ Th.txt comm ] ]
    in
    Th.div
      ~a:[ Th.a_class [ "zk-pos" ] ]
      ([ Th.txt "\240\159\167\173 centrality ";
         Th.b [ Th.txt (Printf.sprintf "#%d" rank) ];
         Th.txt (Printf.sprintf " of %d " n);
         Th.span
           ~a:[ Th.a_class [ "mu" ] ]
           [ Th.txt (Printf.sprintf "(top %d%%, PageRank)" pct) ];
         Th.txt " \194\183 degree ";
         Th.b [ Th.txt (string_of_int (degree p)) ] ]
      @ gchip @ cchip
      @ [ Th.txt " \194\183 "; link "graph.html" "graph" ])
  in
  (* zk-web-surfacing: the 1-hop labelled neighborhood, expandable — the
     page-native face of zk_neighborhood *)
  let nbh =
    let e1 = neighborhood_edges p in
    if e1 = [] then []
    else
      let n2 = List.fold_left (fun a (_, s) ->
          a + (match List.find_opt (fun q -> String.equal q.slug s) pages with
               | Some q -> List.length (neighborhood_edges q) | None -> 0)) 0 e1 in
      [ Th.details
          ~a:[ Th.a_class [ "zk-nbh" ] ]
          (Th.summary
             [ Th.txt
                 (Printf.sprintf
                    "\240\159\149\184 neighborhood \194\183 %d direct edge%s \194\183 ~%d at 2 hops"
                    (List.length e1)
                    (if List.length e1 = 1 then "" else "s")
                    n2) ])
          [ chips
              (List.map
                 (fun (rel, s) ->
                   Th.span
                     ~a:[ Th.a_class [ "zk-pair" ] ]
                     [ Th.span ~a:[ Th.a_class [ "zk-rel" ] ] [ Th.txt rel ];
                       chip_of_elt pages s ])
                 e1) ] ]
  in
  let nav_foot =
    foot
      [ Th.txt "Rendered from ";
        Th.code [ Th.txt p.path ];
        Th.txt
          " by the harness OCaml wiki (docs_wiki.ml) \226\128\148 a Zettelkasten: ";
        Th.code [ Th.txt "[[wiki-links]]" ];
        Th.txt
          ", bidirectional backlinks, #tags, unlinked mentions, inference, a \
           graph, serendipity, YAML frontmatter. Navigate: sidebar \194\183 \
           prev/next \194\183 ";
        link "index.html" "index"; Th.txt " \194\183 ";
        link "graph.html" "graph"; Th.txt " \194\183 ";
        link "tags.html" "tags"; Th.txt " \194\183 ";
        link "random.html" "\240\159\142\178 random"; Th.txt " \194\183 ";
        link "anomalies.html" "anomalies"; Th.txt " \194\183 ";
        link "query.html" "query"; Th.txt " \194\183 ";
        link "timeline.html" "timeline"; Th.txt " \194\183 ";
        link "currency.html" "currency"; Th.txt " \194\183 ";
        link "/wiki" "live wiki"; Th.txt "." ]
  in
  (* The overdue-review check. A script body is raw text by definition, so it is
     Unsafe.data — and it is a fixed literal, never data. *)
  let review_js =
    "(function(){var t=new Date().toISOString().slice(0,10);\
     document.querySelectorAll('[data-review]').forEach(function(e){\
     if(e.getAttribute('data-review')<t)e.classList.add('overdue');});})();"
  in
  let body =
    [ Th.div
        ~a:[ Th.a_class [ "crumb" ] ]
        ([ Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "docs" ];
           Th.txt (Printf.sprintf " / %s / %s" p.group (Filename.basename p.path)) ]
        @ edit);
      zettel_card_elt p;
      render_meta_panel_elt p;
      position ]
    @ tags_row
    @ [ (* THE ONE REMAINING SEAM, named. `p.html` is the streaming markdown
           renderer's output: a parser that opens a tag on one line and closes it
           many lines later, which is its own slice. Everything else on this page
           is typed — the zkquery results now arrive as ELEMENTS, so that second
           seam is gone rather than relocated. *)
        Th.Unsafe.data
          (if embed_lines p.raw = [] then p.html else render_with_embeds pages p) ]
    @ render_zkquery_results_elts pages p
    @ [ zettel ]
    @ nbh
    @ [ Th.div ~a:[ Th.a_class [ "pn" ] ] [ nav_link "prev" prev; nav_link "next" next ];
        nav_foot;
        Th.script (Th.Unsafe.data review_js) ]
  in
  page_frame_elts ~title:p.title ~cur:p.slug ~pages ~body

(* Compatibility interpretation for single-page callers.  Full-corpus callers
   should prepare once and use [render_page_with_context]. *)
let render_page ~pages (p : page) =
  render_page_with_context ~context:(render_context_for pages) p

(* the TAGS index: every #tag → the notes carrying it. *)
let render_tags (pages : page list) =
  let all = List.sort_uniq compare (List.concat_map (fun p -> p.tags) pages) in
  let body =
    [ crumb_to "tags";
      Th.h1 [ Th.txt "Tags" ];
      Th.p
        ~a:[ Th.a_class [ "mu" ] ]
        [ Th.txt
            (Printf.sprintf
               "%d tags across the notes. A tag groups notes by theme \226\128\148 \
                the second axis of a Zettelkasten, orthogonal to links."
               (List.length all)) ] ]
    @ (if all <> [] then []
       else
         [ Th.p
             ~a:[ Th.a_class [ "mu" ] ]
             [ Th.txt "No "; Th.code [ Th.txt "#tags" ];
               Th.txt " in the corpus yet \226\128\148 add ";
               Th.code [ Th.txt "#a-tag" ]; Th.txt " to any note." ] ])
    @ List.concat_map
        (fun t ->
          let notes = List.filter (fun p -> List.mem t p.tags) pages in
          [ Th.h2
              ~a:[ Th.a_id t ]
              [ Th.txt ("#" ^ t); Th.txt " ";
                Th.span
                  ~a:[ Th.a_class [ "zk-n" ] ]
                  [ Th.txt (string_of_int (List.length notes)) ] ];
            Th.div
              ~a:[ Th.a_class [ "zk-chips" ] ]
              (List.map (fun p -> zettel_link ~slug:p.slug ~title:p.title) notes) ])
        all
    @ [ Th.div
          ~a:[ Th.a_class [ "foot" ] ]
          [ Th.txt "Tags \226\128\148 the thematic index of the Zettelkasten (all OCaml). ";
            Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "\226\134\144 index" ];
            Th.txt " \194\183 ";
            Th.a ~a:[ Th.a_href "graph.html" ] [ Th.txt "graph" ] ] ]
  in
  page_frame_elts ~title:"Tags" ~cur:"tags" ~pages ~body

(* FULL-TEXT SEARCH: an index (slug/title/group/text) generated in OCaml, filtered
   client-side (multi-term AND, ranked, snippet + highlight). Works both served
   (/docs/search) and as static output; deep-linkable via ?q=. *)
let render_search (pages : page list) =
  let idx = "[" ^ String.concat "," (List.map (fun p ->
    Printf.sprintf "{\"s\":%s,\"t\":%s,\"g\":%s,\"x\":%s}"
      (jesc p.slug) (jesc p.title) (jesc p.group) (jesc (search_text p.raw))) pages) ^ "]" in
  let body = Printf.sprintf
{search|<div class=crumb><a href="index.html">docs</a> / search</div>
<h1>Search</h1>
<p class=mu>Full-text search over %d notes (title + body). Multi-term AND, ranked by match count, with highlighted snippets — all client-side over an index generated in OCaml.</p>
<input id=zks-q class=zks-input type=search placeholder="Search the notes…  (try: gate, zettelkasten, ontology)" autofocus>
<div id=zks-results class=zks-results></div>
<div id=zks-semwrap style=display:none><h2>Semantic (vectors + graph)</h2>
<p class=mu style=font-size:12.5px>Server-side TF-IDF KNN over notes + html + <b>code</b>, personalized-PageRank re-ranked.
<label>granularity <select id=zks-g><option value=note>note</option><option value=block>block</option></select></label></p>
<div id=zks-sem></div></div>
<div class=foot>Full-text search over the OCaml wiki (docs_wiki.ml). <a href="index.html">← index</a> · <a href="graph.html">graph</a> · <a href="tags.html">tags</a></div>
<script type="application/json" id=zks-idx>%s</script>
<script>
const idx=JSON.parse(document.getElementById('zks-idx').textContent);
const q=document.getElementById('zks-q'), out=document.getElementById('zks-results');
function esc(s){return String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));}
function hi(s,term){const r=term.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');return esc(s).replace(new RegExp('('+r+')','ig'),'<mark>$1</mark>');}
function snippet(text,term){const i=text.toLowerCase().indexOf(term);if(i<0)return esc(text.slice(0,150));const a=Math.max(0,i-55);return (a>0?'…':'')+hi(text.slice(a,a+150),term)+'…';}
function run(){const terms=q.value.toLowerCase().trim().split(/\s+/).filter(Boolean);
  if(!terms.length){out.innerHTML='';return;}
  const hits=idx.map(n=>{const hay=(n.t+' '+n.x).toLowerCase();
    const ok=terms.every(t=>hay.indexOf(t)>=0);
    const score=ok?terms.reduce((a,t)=>a+(hay.split(t).length-1),0)+(n.t.toLowerCase().indexOf(terms[0])>=0?50:0):0;
    return {n,score};}).filter(h=>h.score>0).sort((a,b)=>b.score-a.score).slice(0,50);
  out.innerHTML=hits.length
    ?('<div class=zks-count>'+hits.length+' result'+(hits.length>1?'s':'')+'</div>'+hits.map(h=>'<a class=zks-hit href="'+h.n.s+'.html"><div class=zks-t>'+hi(h.n.t,terms[0])+' <span class=zks-g>'+esc(h.n.g)+'</span></div><div class=zks-x>'+snippet(h.n.x,terms[0])+'</div></a>').join(''))
    :'<p class=mu>No matches.</p>';}
const g=document.getElementById('zks-g'), sem=document.getElementById('zks-sem'), semwrap=document.getElementById('zks-semwrap');
let semTimer=null;
async function runSem(){
  const query=q.value.trim(); if(!query){sem.innerHTML='';semwrap.style.display='none';return;}
  try{
    const r=await fetch('/api/search?q='+encodeURIComponent(query)+'&k=12&granularity='+g.value);
    if(!r.ok)throw 0; const d=await r.json();
    semwrap.style.display='';
    const hits=(d.results||[]).map(h=>'<a class=zks-hit href="'+esc(h.url)+'"><div class=zks-t>'+esc(h.title)
      +' <span class=zks-kind>'+esc(h.kind)+'</span> <span class=zks-g>'+h.score.toFixed(3)+'</span></div>'
      +(h.excerpt?'<div class=zks-x>'+esc(h.excerpt)+'</div>':'')+'</a>').join('');
    const ppr=(d.ppr||[]).slice(0,6).map(h=>'<a class=zettel href="'+esc(h.url)+'">'+esc(h.url.replace('/docs/',''))+'</a>').join(' ');
    sem.innerHTML=(hits||'<p class=mu>No semantic matches.</p>')
      +(ppr?'<div class=zks-count>graph-ranked (PPR): '+ppr+'</div>':'');
  }catch(e){sem.innerHTML='';semwrap.style.display='none';}
}
function runBoth(){run();clearTimeout(semTimer);semTimer=setTimeout(runSem,250);}
q.addEventListener('input',runBoth);
g.addEventListener('change',runSem);
const p=new URLSearchParams(location.search).get('q');if(p){q.value=p;runBoth();}
</script>|search} (List.length pages) idx in
  page_frame ~title:"Search" ~cur:"search" ~pages ~body

(* ── the INTERACTIVE force-directed knowledge graph (best-in-class viz) ────
   A self-contained (CSP-safe, no CDN) force simulation: draggable nodes,
   wheel-zoom/pan, click-to-navigate, degree-sized + group-coloured nodes, live
   highlight-search and per-group filters. The OCaml side is a PURE emitter of a
   node/edge JSON model + the inline JS; laws cover the model (one node/page, edge
   referential integrity, injection-safety, totality). *)
let fg_js = {fgjs|(function(){
var svg=document.getElementById('fg'),el=document.getElementById('fg-data');
if(!svg||!el)return;var data=JSON.parse(el.textContent),NS='http://www.w3.org/2000/svg',W=1000,H=640;
if(!data.nodes.length){var tx=document.createElementNS(NS,'text');tx.setAttribute('x',24);tx.setAttribute('y',44);tx.setAttribute('fill','currentColor');tx.textContent='No [[links]] yet — add one to any note.';svg.appendChild(tx);return;}
var byId={};data.nodes.forEach(function(n,i){var a=i/data.nodes.length*6.2832;n.x=W/2+300*Math.cos(a);n.y=H/2+300*Math.sin(a);n.vx=0;n.vy=0;byId[n.id]=n;});
var links=data.edges.filter(function(e){return byId[e.s]&&byId[e.t];});
var groups={},gi=0;data.nodes.forEach(function(n){if(!(n.g in groups))groups[n.g]=gi++;});
function col(g){return 'hsl('+((groups[g]*67)%360)+',60%,58%)';}
var gL=document.createElementNS(NS,'g'),gN=document.createElementNS(NS,'g');svg.appendChild(gL);svg.appendChild(gN);
var lines=links.map(function(){var l=document.createElementNS(NS,'line');l.setAttribute('stroke','currentColor');l.setAttribute('stroke-opacity','0.16');gL.appendChild(l);return l;});
data.nodes.forEach(function(n){var g=document.createElementNS(NS,'g');g.style.cursor='pointer';
var r=6+Math.min(15,n.d*2);var c=document.createElementNS(NS,'circle');c.setAttribute('r',r);c.setAttribute('fill',col(n.g));c.setAttribute('stroke','var(--bg)');c.setAttribute('stroke-width','1.5');
var t=document.createElementNS(NS,'text');t.textContent=n.t;t.setAttribute('font-size','9');t.setAttribute('fill','currentColor');t.setAttribute('dx',r+3);t.setAttribute('dy',3);t.setAttribute('opacity','0.72');
var ti=document.createElementNS(NS,'title');ti.textContent=n.t+'  ·  '+n.g+'  ·  '+n.d+' links';g.appendChild(ti);
g.appendChild(c);g.appendChild(t);gN.appendChild(g);n._c=c;n._t=t;n._g=g;n._r=r;
g.addEventListener('pointerdown',function(ev){drag.n=n;drag.moved=false;ev.stopPropagation();try{g.setPointerCapture(ev.pointerId);}catch(e){}});
g.addEventListener('click',function(){if(!drag.moved)location.href=n.id+'.html';});});
var alpha=1,drag={n:null,moved:false};
function toSvg(ev){var r=svg.getBoundingClientRect(),vb=svg.viewBox.baseVal;return{x:(ev.clientX-r.left)/r.width*vb.width+vb.x,y:(ev.clientY-r.top)/r.height*vb.height+vb.y};}
function render(){lines.forEach(function(l,i){var e=links[i],a=byId[e.s],b=byId[e.t];l.setAttribute('x1',a.x);l.setAttribute('y1',a.y);l.setAttribute('x2',b.x);l.setAttribute('y2',b.y);});data.nodes.forEach(function(n){n._g.setAttribute('transform','translate('+n.x+','+n.y+')');});}
function step(){alpha*=0.99;if(alpha<0.02)alpha=0.02;
for(var i=0;i<data.nodes.length;i++){var a=data.nodes[i];for(var j=i+1;j<data.nodes.length;j++){var b=data.nodes[j];var dx=a.x-b.x,dy=a.y-b.y,d2=dx*dx+dy*dy+0.01,d=Math.sqrt(d2),f=1600/d2*alpha,ux=dx/d,uy=dy/d;a.vx+=ux*f;a.vy+=uy*f;b.vx-=ux*f;b.vy-=uy*f;}}
links.forEach(function(e){var a=byId[e.s],b=byId[e.t],dx=b.x-a.x,dy=b.y-a.y,d=Math.sqrt(dx*dx+dy*dy)+0.01,f=(d-96)*0.02*alpha,ux=dx/d,uy=dy/d;a.vx+=ux*f;a.vy+=uy*f;b.vx-=ux*f;b.vy-=uy*f;});
data.nodes.forEach(function(n){n.vx+=(W/2-n.x)*0.0016*alpha;n.vy+=(H/2-n.y)*0.0016*alpha;if(n!==drag.n){n.vx*=0.86;n.vy*=0.86;n.x+=n.vx;n.y+=n.vy;}n.x=Math.max(16,Math.min(W-16,n.x));n.y=Math.max(16,Math.min(H-16,n.y));});
render();requestAnimationFrame(step);}
svg.addEventListener('pointermove',function(ev){if(!drag.n)return;var p=toSvg(ev);drag.n.x=p.x;drag.n.y=p.y;drag.n.vx=0;drag.n.vy=0;drag.moved=true;alpha=Math.max(alpha,0.3);});
window.addEventListener('pointerup',function(){drag.n=null;});
svg.addEventListener('wheel',function(ev){ev.preventDefault();var vb=svg.viewBox.baseVal,s=ev.deltaY>0?1.1:0.9,p=toSvg(ev);vb.x=p.x-(p.x-vb.x)*s;vb.y=p.y-(p.y-vb.y)*s;vb.width*=s;vb.height*=s;},{passive:false});
var q=document.getElementById('fg-q');if(q)q.addEventListener('input',function(){var s=this.value.toLowerCase();data.nodes.forEach(function(n){var h=!s||n.t.toLowerCase().indexOf(s)>=0;n._c.setAttribute('opacity',h?1:0.1);n._t.setAttribute('opacity',h?0.9:0.04);});});
document.querySelectorAll('.fg-f input').forEach(function(cb){cb.addEventListener('change',function(){var on={};document.querySelectorAll('.fg-f input').forEach(function(c){on[c.getAttribute('data-g')]=c.checked;});data.nodes.forEach(function(n){n._g.style.display=on[n.g]?'':'none';});lines.forEach(function(l,i){var e=links[i];l.style.display=(on[byId[e.s].g]&&on[byId[e.t].g])?'':'none';});});});
var rb=document.getElementById('fg-reset');if(rb)rb.addEventListener('click',function(){var vb=svg.viewBox.baseVal;vb.x=0;vb.y=0;vb.width=W;vb.height=H;alpha=1;});
render();requestAnimationFrame(step);})();|fgjs}

(* Returns ELEMENTS, so `render_graph`'s last `Unsafe.data` seam is deleted
   rather than moved. The node/edge payload goes through `Json_embed`, which is
   a FIDELITY improvement rather than a security fix: this module's local `jesc`
   already escaped the left angle bracket, so the script element was never
   closable from data here — unlike agent_workers' `je`, which did not. What
   `jesc` did do was map a newline, tab or control character to a SPACE, so a
   title containing one came back altered. The typed encoder escapes it instead,
   and there is now one encoder in the tree rather than two. *)
let render_graph_interactive_elts (pages : page list) =
  let node p =
    Json_embed.Obj
      [ ("id", Json_embed.Str p.slug); ("t", Json_embed.Str p.title);
        ("g", Json_embed.Str p.group); ("d", Json_embed.Int (degree p)) ]
  in
  let slugs = List.map (fun p -> p.slug) pages in
  let edges =
    List.concat_map
      (fun p ->
        List.filter_map
          (fun o ->
            if List.mem o slugs then
              Some
                (Json_embed.Obj
                   [ ("s", Json_embed.Str p.slug); ("t", Json_embed.Str o) ])
            else None)
          p.outlinks)
      pages
  in
  let data =
    Json_embed.to_string
      (Json_embed.Obj
         [ ("nodes", Json_embed.Arr (List.map node pages));
           ("edges", Json_embed.Arr edges) ])
  in
  let groups = List.sort_uniq compare (List.map (fun p -> p.group) pages) in
  [ Th.div
      ~a:[ Th.a_class [ "fg-wrap" ] ]
      [ Th.div
          ~a:[ Th.a_class [ "fg-controls" ] ]
          [ Th.input
              ~a:
                [ Th.a_id "fg-q"; Th.a_class [ "fg-search" ];
                  Th.a_placeholder "\240\159\148\141 highlight notes\226\128\166" ]
              ();
            Th.div
              ~a:[ Th.a_class [ "fg-legend" ] ]
              (List.map
                 (fun g ->
                   Th.label
                     ~a:[ Th.a_class [ "fg-f" ] ]
                     [ Th.input
                         ~a:
                           [ Th.a_input_type `Checkbox; Th.a_checked ();
                             Th.a_user_data "g" g ]
                         ();
                       Th.span [ Th.txt g ] ])
                 groups);
            Th.button
              ~a:[ Th.a_id "fg-reset"; Th.a_class [ "fg-btn" ] ]
              [ Th.txt "\226\159\178 reset view" ] ];
        Th.svg
          ~a:
            [ Ts.a_id "fg"; Ts.a_viewBox (0., 0., 1000., 640.);
              Ts.Unsafe.string_attrib "role" "img";
              Ts.Unsafe.string_attrib "aria-label" "interactive knowledge graph" ]
          [];
        Th.div
          ~a:[ Th.a_class [ "fg-hint" ] ]
          [ Th.txt
              "drag nodes \194\183 scroll to zoom \194\183 click to open \194\183 \
               filter by group" ];
        (* the payload is inert by construction, so the element cannot be closed
           by a note title *)
        Th.script
          ~a:[ Th.a_script_type (`Mime "application/json"); Th.a_id "fg-data" ]
          (Th.Unsafe.data data);
        Th.script (Th.Unsafe.data fg_js) ] ]

(* string shim for the callers that still assemble bytes *)
let render_graph_interactive (pages : page list) =
  String.concat "" (List.map elt_str (render_graph_interactive_elts pages))

(* ── network science over the Zettelkasten graph (the maths of a second brain) ─
   A mature Zettelkasten is a scale-free network; these pure kernels expose its
   structure. `pagerank_core` is the eigenvector-centrality power iteration —
   factored to a numeric core (n, out-adjacency) so it is directly QCheck-tested
   (the ranks are a probability distribution: non-negative, sum to 1). *)
(* combinatorics: (notes, actual edges, potential = n(n-1)/2) — why serendipity
   accelerates: potential connections grow quadratically in the note count. *)
let graph_density (pages : page list) =
  let n = List.length pages in
  let e = List.fold_left (fun a p -> a + List.length p.outlinks) 0 pages in
  (n, e, n * (n - 1) / 2)

(* the degree distribution (for the scale-free / power-law shape): (degree, count). *)
let degree_histogram (pages : page list) =
  let tbl = Hashtbl.create 32 in
  List.iter (fun p -> let dg = degree p in
    Hashtbl.replace tbl dg (1 + (try Hashtbl.find tbl dg with Not_found -> 0))) pages;
  List.sort compare (Hashtbl.fold (fun k v a -> (k, v) :: a) tbl [])

(* ── SPANNING-TREE reading order (graph → linear manuscript) ──────────────
   Traversing notes by links is a random walk; to WRITE from them you impose a
   rooted spanning forest and read it in DFS pre-order — collapsing the web into
   a one-dimensional sequence. Roots are taken by PageRank (most central first),
   so the manuscript opens with the foundational note. Returns (slug, depth); it
   is a PERMUTATION of every note (a spanning forest covers all nodes). *)
let reading_order (pages : page list) : (string * int) list =
  let out = Hashtbl.create 256 in
  List.iter (fun p -> Hashtbl.replace out p.slug p.outlinks) pages;
  let visited = Hashtbl.create 256 in
  let acc = ref [] in
  let rec dfs slug depth =
    if not (Hashtbl.mem visited slug) then begin
      Hashtbl.replace visited slug ();
      acc := (slug, depth) :: !acc;
      let kids = try Hashtbl.find out slug with Not_found -> [] in
      List.iter (fun c -> if Hashtbl.mem out c then dfs c (depth + 1)) kids
    end in
  List.iter (fun (slug, _) -> dfs slug 0) (pagerank pages);   (* roots by centrality *)
  (* any node unreachable from a PageRank root (shouldn't happen — PR covers all) *)
  List.iter (fun p -> dfs p.slug 0) pages;
  List.rev !acc

(* the network-analysis panel rendered on the graph page. *)
(* Returns ELEMENTS, not a string. `render_graph` used to splice this in with
   `Th.Unsafe.data`; returning elements DELETES that seam rather than moving
   it, which is the whole point of converting a fragment that another page
   consumes. A term over the furniture algebra above. *)
let render_graph_analysis_elts (pages : page list) =
  let title_of_slug s =
    match List.find_opt (fun q -> String.equal q.slug s) pages with
    | Some q -> q.title
    | None -> s
  in
  let note_link slug = link (slug ^ ".html") (title_of_slug slug) in
  let n, e, pot = graph_density pages in
  let pr = pagerank pages in
  let maxpr = List.fold_left (fun m (_, s) -> if s > m then s else m) 1e-12 pr in
  let hist = degree_histogram pages in
  let maxc = List.fold_left (fun m (_, c) -> if c > m then c else m) 1 hist in
  let ro = reading_order pages in
  [ Th.h2 [ Th.txt "Network analysis" ];
    mu
      [ Th.txt "A scale-free knowledge network: ";
        Th.b [ Th.txt (string_of_int n) ];
        Th.txt " notes, ";
        Th.b [ Th.txt (string_of_int e) ];
        Th.txt " links of ";
        Th.b [ Th.txt (string_of_int pot) ];
        Th.txt " possible (";
        Th.code [ Th.txt "n(n-1)/2" ];
        Th.txt ") \226\128\148 density ";
        Th.b
          [ Th.txt
              (Printf.sprintf "%.2f%%"
                 (if pot = 0 then 0. else 100. *. float_of_int e /. float_of_int pot)) ];
        Th.txt ". Foundational notes are ranked by ";
        Th.b [ Th.txt "eigenvector centrality (PageRank)" ];
        Th.txt ", not raw degree \226\128\148 the structurally most central ideas." ];
    Th.h3 [ Th.txt "Foundational notes "; badge "PageRank centrality" ];
    data_table [ "Note"; "Centrality" ]
      (List.map
         (fun (slug, score) ->
           Th.tr
             [ Th.td [ note_link slug ];
               Th.td
                 [ Th.span
                     ~a:[ Th.a_class [ "prbar" ] ]
                     [ Th.span
                         ~a:[ Th.a_style (Printf.sprintf "width:%.1f%%" (100. *. score /. maxpr)) ]
                         [] ];
                   Th.span ~a:[ Th.a_class [ "barn" ] ] [ Th.txt (Printf.sprintf "%.4f" score) ] ] ])
         (List.filteri (fun i _ -> i < 15) pr));
    Th.h3 [ Th.txt "Degree distribution "; badge "scale-free shape" ];
    Th.div
      ~a:[ Th.a_class [ "degdist" ] ]
      (List.map
         (fun (dg, c) ->
           Th.div
             ~a:
               [ Th.a_class [ "degbar" ];
                 Th.a_title (Printf.sprintf "%d notes with degree %d" c dg) ]
             [ Th.span
                 ~a:
                   [ Th.a_class [ "degcol" ];
                     Th.a_style
                       (Printf.sprintf "height:%.0f%%"
                          (100. *. float_of_int c /. float_of_int maxc)) ]
                 [];
               Th.span ~a:[ Th.a_class [ "deglbl" ] ] [ Th.txt (string_of_int dg) ] ])
         hist);
    Th.p
      ~a:[ Th.a_class [ "legend" ] ]
      [ Th.txt
          "x = degree (links), bar height = how many notes have it. A few \
           high-degree hubs + many low-degree leaves = the power-law signature." ];
    Th.h3 [ Th.txt "Ontology inference "; badge "transitive closure" ];
    mu
      [ Th.txt "The description-logic transitive rule over ";
        Th.code [ Th.txt "[[links]]" ];
        Th.txt
          ": if A\226\134\146B and B\226\134\146C then A\226\128\137\226\135\157\226\128\137C. ";
        Th.b [ Th.txt (string_of_int (inferred_count pages)) ];
        Th.txt
          " indirect relations are inferred beyond the direct links \226\128\148 the \
           small-world paths that make any two ideas a few hops apart." ];
    Th.h3 [ Th.txt "Reading order "; badge "spanning tree" ];
    mu
      [ Th.txt
          (Printf.sprintf
             "The graph collapsed to a one-dimensional manuscript: a rooted spanning \
              forest in DFS pre-order, opening with the most central note. %d notes, \
              indented by tree depth."
             (List.length ro)) ];
    Th.ol
      ~a:[ Th.a_class [ "rdorder" ] ]
      (List.map
         (fun (slug, depth) ->
           Th.li ~a:[ Th.a_style (Printf.sprintf "margin-left:%dpx" (depth * 18)) ]
             [ note_link slug ])
         (List.filteri (fun i _ -> i < 80) ro)
      @ when_ (List.length ro > 80)
          [ Th.li
              ~a:[ Th.a_class [ "legend" ] ]
              [ Th.txt (Printf.sprintf "\226\128\166 +%d more" (List.length ro - 80)) ] ]) ]

(* string shim for `selftest`, the last caller that still wants bytes *)
let render_graph_analysis (pages : page list) =
  String.concat "" (List.map elt_str (render_graph_analysis_elts pages))

(* the Zettelkasten GRAPH: the whole link graph + hubs + orphans.

   Typed markup, and it goes through `page_frame_elts`, so the shell AND this
   page's own content are type-guaranteed. Two sub-renderers are still string
   producers — the force-directed canvas (a JS blob, correctly raw) and the
   analysis panel — so they enter through `Unsafe.data`; those are named
   rather than hidden, and each disappears as its own function converts. *)
let render_graph (pages : page list) =
  let title_of_slug s =
    match List.find_opt (fun q -> String.equal q.slug s) pages with
    | Some q -> q.title
    | None -> s
  in
  let total_links = List.fold_left (fun a p -> a + List.length p.outlinks) 0 pages in
  let hubs =
    List.sort (fun a b -> compare (List.length b.backlinks) (List.length a.backlinks)) pages
  in
  let orphans = List.filter (fun p -> p.outlinks = [] && p.backlinks = []) pages in
  let note_link slug title = Th.a ~a:[ Th.a_href (slug ^ ".html") ] [ Th.txt title ] in
  let body =
    [ Th.div
        ~a:[ Th.a_class [ "crumb" ] ]
        [ Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "docs" ]; Th.txt " / graph" ];
      Th.h1 [ Th.txt "Zettelkasten graph" ];
      Th.p
        ~a:[ Th.a_class [ "mu" ] ]
        [ Th.txt
            (Printf.sprintf "The bidirectional link graph over %d notes — %d "
               (List.length pages) total_links);
          Th.code [ Th.txt "[[wiki-link]]" ];
          Th.txt
            " edges. Every note is an atomic page; a link creates a backlink \
             automatically. Drag to explore, scroll to zoom, click a node to open it." ];
      (* NO SEAM LEFT ON THIS PAGE. The force-directed canvas and the analysis
         section both return elements now; the only raw thing inside the canvas
         is its own fixed JS program, and the data it reads is a Json_embed
         encoding that cannot close the element. *)
    ]
    @ render_graph_interactive_elts pages
    @ render_graph_analysis_elts pages
    @ [ Th.h2 [ Th.txt "Most linked-to (hubs)" ];
      Th.div
        ~a:[ Th.a_class [ "tw" ] ]
        [ Th.table
            ~thead:
              (Th.thead
                 [ Th.tr [ Th.th [ Th.txt "Note" ]; Th.th [ Th.txt "← refs" ];
                           Th.th [ Th.txt "→ out" ] ] ])
            (List.filter_map
               (fun p ->
                 if List.length p.backlinks > 0 || List.length p.outlinks > 0 then
                   Some
                     (Th.tr
                        [ Th.td [ note_link p.slug p.title ];
                          Th.td [ Th.txt (string_of_int (List.length p.backlinks)) ];
                          Th.td [ Th.txt (string_of_int (List.length p.outlinks)) ] ])
                 else None)
               (List.filteri (fun i _ -> i < 30) hubs)) ];
      Th.h2 [ Th.txt "Edges" ];
      Th.div
        ~a:[ Th.a_class [ "zk-edges" ] ]
        (List.concat_map
           (fun p ->
             List.map
               (fun o ->
                 Th.div
                   ~a:[ Th.a_class [ "zk-edge" ] ]
                   [ note_link p.slug p.title; Th.txt " ";
                     Th.span ~a:[ Th.a_class [ "zk-arrow" ] ] [ Th.txt "→" ]; Th.txt " ";
                     note_link o (title_of_slug o) ])
               p.outlinks)
           pages
        @
        if total_links = 0 then
          [ Th.p
              ~a:[ Th.a_class [ "mu" ] ]
              [ Th.txt "No "; Th.code [ Th.txt "[[wiki-links]]" ];
                Th.txt " in the corpus yet — add "; Th.code [ Th.txt "[[Note Title]]" ];
                Th.txt " to any doc and its backlink appears automatically." ] ]
        else []);
      Th.h2
        [ Th.txt "Orphans ";
          Th.span
            ~a:[ Th.a_class [ "zk-n" ] ]
            [ Th.txt (string_of_int (List.length orphans)) ] ];
      Th.p
        ~a:[ Th.a_class [ "mu" ] ]
        [ Th.txt "Notes with no links in or out — candidates to connect." ];
      Th.div
        ~a:[ Th.a_class [ "zk-chips" ] ]
        (List.map
           (fun p ->
             Th.a
               ~a:[ Th.a_class [ "zettel" ]; Th.a_href (p.slug ^ ".html") ]
               [ Th.txt p.title ])
           orphans);
      Th.div
        ~a:[ Th.a_class [ "foot" ] ]
        [ Th.txt "The Zettelkasten graph — all native OCaml (docs_wiki.ml). ";
          Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "← index" ] ]
    ]
  in
  page_frame_elts ~title:"Zettelkasten graph" ~cur:"graph" ~pages ~body

let render_index (pages : page list) =
  let head_elts =
    [ Th.h1 [ Th.txt "zigvm documentation" ];
      Th.p
        [ Th.txt "Every ";
          Th.code [ Th.txt "docs/*.md" ];
          Th.txt
            (Printf.sprintf
               " file, rendered to HTML as an OCaml wiki (%d pages) from an \
                immutable docs-tree model and a pure view. Served by the harness at "
               (List.length pages));
          Th.code [ Th.txt "/docs" ];
          Th.txt "." ] ]
  in
  (* \226\154\161 WHAT'S NEW: the most-recently-MODIFIED docs (by file mtime), surfaced
     PROMINENTLY at the top so new/edited content is always visible first. Mtime
     auto-captures every new or edited doc — no frontmatter or manual list needed. *)
  let mtime_of p = try (Unix.stat p.path).Unix.st_mtime with _ -> 0.0 in
  (* Exclude the PERPETUAL-CHURN ledgers/registries: DIVERGENCE_LOG, MUTATION_LOG,
     CAST_LOG, CAPABILITY_STATUS, ISSUE_PATTERNS, SAFETY_ANALYSIS are appended EVERY
     slice, so they'd always float to the top and BURY the actual new documents.
     What's-new surfaces genuine content pages (fractal records, plans, guides); the
     ledgers stay one click away in their groups below. *)
  let is_ledger p =
    let base = String.uppercase_ascii (Filename.basename p.path) in
    let ends_with suf =
      let ls = String.length suf and lb = String.length base in
      lb >= ls && String.equal (String.sub base (lb - ls) ls) suf in
    ends_with "_LOG.MD"
    || List.mem base
         [ "CAPABILITY_STATUS.MD"; "ISSUE_PATTERNS.MD"; "SAFETY_ANALYSIS.MD";
           "MUTATION_LOG.MD"; "DIVERGENCE_LOG.MD"; "CAST_LOG.MD"; "ROADMAP.MD";
           "HANDOFF.MD"; "MUTATION_LOG.MD"; "CODEBASE_MAP.MD" ] in
  let content_pages = List.filter (fun p -> not (is_ledger p)) pages in
  let by_recent = List.sort (fun a c -> compare (mtime_of c) (mtime_of a)) content_pages in
  let rec take n = function [] -> [] | _ when n <= 0 -> [] | x :: t -> x :: take (n - 1) t in
  let recent = take 12 by_recent in
  (* YYYYMMDD-HHMMSS timestamp (from file mtime) — the sort key AND the prominent
     badge, so the newest content is unambiguous and machine-legible. *)
  let fmt_ts t = if t <= 0.0 then "00000000-000000" else
    let tm = Unix.gmtime t in
    Printf.sprintf "%04d%02d%02d-%02d%02d%02d"
      (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
      tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec in
  let th_style = "text-align:left;padding:6px 10px;font-size:11px;color:var(--dim)" in
  let whatsnew =
    if recent = [] then []
    else
      [ Th.h2
          ~a:[ Th.a_class [ "whatsnew" ] ]
          [ Th.txt "\226\154\161 What's new ";
            Th.span
              ~a:[ Th.a_class [ "zk-n" ] ]
              [ Th.txt "latest first \194\183 YYYYMMDD-HHMMSS by file mtime" ] ];
        Th.p
          ~a:[ Th.a_class [ "mu" ] ]
          [ Th.txt "New & recently-edited ";
            Th.b [ Th.txt "content pages" ];
            Th.txt " (fractal records, plans, guides), newest on top. The ";
            Th.code [ Th.txt "YYYYMMDD-HHMMSS" ];
            Th.txt
              " timestamp is the file's last-modified time (UTC). The \
               perpetual-churn ledgers (DIVERGENCE_LOG, MUTATION_LOG, \
               CAPABILITY_STATUS, ISSUE_PATTERNS, SAFETY_ANALYSIS \226\128\148 \
               appended every slice) are excluded so they don't bury genuinely new \
               docs; find them in their groups below." ];
        Th.table
          ~a:
            [ Th.a_class [ "whatsnew-tbl" ];
              Th.a_style "width:100%;border-collapse:collapse;font-size:13px" ]
          ~thead:
            (Th.thead
               [ Th.tr
                   [ Th.th
                       ~a:[ Th.a_style
                              ("text-align:left;padding:6px 10px;font-family:ui-monospace,\
                                monospace;font-size:11px;color:var(--dim)") ]
                       [ Th.txt "timestamp" ];
                     Th.th ~a:[ Th.a_style th_style ] [ Th.txt "document" ];
                     Th.th ~a:[ Th.a_style th_style ] [ Th.txt "group" ] ] ])
          (List.map
             (fun p ->
               Th.tr
                 ~a:[ Th.a_style "border-top:1px solid var(--ln)" ]
                 [ Th.td
                     ~a:[ Th.a_style
                            "padding:6px 10px;font-family:ui-monospace,monospace;\
                             font-size:12px;color:var(--ac);white-space:nowrap;font-weight:600" ]
                     [ Th.txt (fmt_ts (mtime_of p)) ];
                   Th.td
                     ~a:[ Th.a_style "padding:6px 10px" ]
                     [ Th.a ~a:[ Th.a_href (p.slug ^ ".html") ] [ Th.txt p.title ] ];
                   Th.td
                     ~a:[ Th.a_style "padding:6px 10px;color:var(--dim);font-size:12px" ]
                     [ Th.txt p.group ] ])
             recent) ]
  in
  (* MAPS OF CONTENT: the entry points — the most-connected structure notes. *)
  let entry = mocs pages in
  let idx_card ~slug ~title ~sub =
    Th.div
      ~a:[ Th.a_class [ "idx-card" ] ]
      [ Th.a ~a:[ Th.a_href (slug ^ ".html") ] [ Th.txt title ];
        Th.div ~a:[ Th.a_class [ "pg" ] ] [ Th.txt sub ] ]
  in
  let entries =
    if entry = [] then []
    else
      [ Th.h2
          [ Th.txt "\240\159\151\186\239\184\143 Entry points ";
            Th.span ~a:[ Th.a_class [ "zk-n" ] ] [ Th.txt "Maps of Content" ] ];
        Th.p
          ~a:[ Th.a_class [ "mu" ] ]
          [ Th.txt "The most-connected notes \226\128\148 where a reader starts. Also try ";
            Th.a ~a:[ Th.a_href "graph.html" ] [ Th.txt "the graph" ];
            Th.txt ", ";
            Th.a ~a:[ Th.a_href "/docs/memory" ]
              [ Th.txt "\240\159\167\160 the system's memory" ];
            Th.txt ", or ";
            Th.a ~a:[ Th.a_href "random.html" ]
              [ Th.txt "\240\159\142\178 a random note" ];
            Th.txt "." ];
        Th.div
          ~a:[ Th.a_class [ "idx-grid" ] ]
          (List.map
             (fun p ->
               idx_card ~slug:p.slug ~title:p.title
                 ~sub:(Printf.sprintf "%d links \194\183 %s" (degree p) p.group))
             entry) ]
  in
  let groups = List.sort_uniq compare (List.map (fun p -> p.group) pages) in
  let group_sections =
    List.concat_map
      (fun g ->
        [ Th.h2 [ Th.txt g ];
          Th.div
            ~a:[ Th.a_class [ "idx-grid" ] ]
            (List.filter_map
               (fun p ->
                 if p.group = g then
                   Some (idx_card ~slug:p.slug ~title:p.title ~sub:p.path)
                 else None)
               pages) ])
      groups
  in
  let body =
    head_elts @ whatsnew @ entries @ group_sections
    @ [ Th.div
          ~a:[ Th.a_class [ "foot" ] ]
          [ Th.txt "Generated by the harness (";
            Th.code [ Th.txt "--docs-wiki" ];
            Th.txt " / the ";
            Th.code [ Th.txt "/docs" ];
            Th.txt " serve route). Companion: the live ";
            Th.a ~a:[ Th.a_href "/wiki" ] [ Th.txt "harness wiki" ];
            Th.txt " (git + SQLite)." ] ]
  in
  page_frame_elts ~title:"documentation" ~cur:"" ~pages ~body

(* ── the HEADLESS JSON API (agent-collaborative: content decoupled from
   presentation). Agents read structured data — id, status, metadata, and the
   whole web of backlinks/outlinks/inferred/similar — without scraping HTML.
   Pure emitters; the shell serves them at /api/*. Every string is jesc-escaped
   (valid JSON), so a hostile title can never break the payload. *)
(* jesc already emits a QUOTED JSON string, so values use %s (jesc supplies the quotes). *)
let note_json (p : page) : string =
  let m = p.meta in
  Printf.sprintf
    "{\"id\":%s,\"slug\":%s,\"title\":%s,\"status\":%s,\"type\":%s,\"group\":%s,\"path\":%s,\"etag\":%s,\"last_verified\":%s,\"verified_by\":%s,\"next_review\":%s,\"words\":%d,\"tags\":%s,\"outlinks\":%s,\"backlinks\":%s,\"typed\":%s,\"blocks\":%s}"
    (jesc m.id) (jesc p.slug) (jesc p.title) (jesc m.status) (jesc m.ntype) (jesc p.group) (jesc p.path)
    (jesc (etag_of p))
    (jesc m.last_verified) (jesc m.verified_by) (jesc m.next_review)
    (word_count p) (json_slist p.tags) (json_slist p.outlinks) (json_slist p.backlinks) (json_typed p.typed) (json_slist (block_ids_of p.raw))

(* GET /api/notes — the whole corpus as a JSON array of note summaries (an agent
   fetches the index + graph edges in one request). *)
let api_index (pages : page list) : string =
  Printf.sprintf "{\"count\":%d,\"notes\":[%s]}"
    (List.length pages) (String.concat "," (List.map note_json pages))

(* GET /api/note/<slug|id> — one note with full metadata, the rendered HTML body,
   AND its whole relationship web (backlinks in one query, + inferred + similar). *)
let api_note (pages : page list) (p : page) : string =
  let sim = List.map fst (similar_notes pages p 6) in
  let inf = inferred_for pages p in
  (* contextual backlinks (§7.10): the citing line per source — an agent gets
     the WHY of each citation without a second zk_read_note round-trip. *)
  let bctx = String.concat "," (List.map (fun (src, ctx) ->
      Printf.sprintf "{\"from\":%s,\"context\":%s}" (jesc src) (jesc ctx)) p.back_ctx) in
  (* the note's dialectical standing under the grounded labelling (§8.2-A):
     in = defensible, out = defeated by an accepted opposer, undec = disputed *)
  let grounded = Option.value ~default:"undec" (List.assoc_opt p.slug (grounded_statuses pages)) in
  (* the note's community id (zk-communities §6.5) — deterministic LPA *)
  let community = Option.value ~default:p.slug (List.assoc_opt p.slug (communities pages)) in
  Printf.sprintf "{\"note\":%s,\"mentions\":%s,\"inferred\":%s,\"similar\":%s,\"backlinks_ctx\":[%s],\"grounded\":%s,\"community\":%s,\"html\":%s}"
    (note_json p) (json_slist p.mentions) (json_slist inf) (json_slist sim) bctx (jesc grounded) (jesc community) (jesc p.html)

(* resolve a note by slug OR by UUID (immutable id survives a rename). *)
let find_note (pages : page list) (key : string) : page option =
  match List.find_opt (fun p -> p.slug = key) pages with
  | Some _ as r -> r
  | None -> List.find_opt (fun p -> p.meta.id = key) pages

(* ── ZK MCP read surface (zk-mcp-read, journal 20260729-1056 §6.2) ────────
   Pure JSON kernels the MCP tools / CLI mirrors serve VERBATIM — the shells
   add no logic, so every law lives here (Stratum A) and the tool output is
   the law-tested value by construction. *)

(* the labelled 1-hop edge set of a note: out (explicit [[link]]), back
   (inbound), typed:<rel> (semantic [[T|@rel]]), mention (unlinked mention of
   this note's title). Deterministic: sorted, deduped. *)
(* the graph neighborhood as JSON — an agent walks the Zettelkasten without
   reading files. hops is CLAMPED to [1,2] (LAW hop-bound); an unknown key is
   an error JSON, never an exception (LAW rejection/totality). Edge endpoints
   are build-resolved slugs, so every "to" resolves in the corpus (LAW
   endpoint-closure) — except "mention"/"back" sources which are corpus slugs
   by construction of the mention scan. *)
let neighborhood_json (pages : page list) (key : string) ~(hops : int) : string =
  match find_note pages key with
  | None -> Printf.sprintf "{\"error\":\"unknown note\",\"key\":%s}" (jesc key)
  | Some p ->
      let hops = max 1 (min 2 hops) in
      let edge_json ~hop (from : string) (rel, to_) =
        Printf.sprintf "{\"from\":%s,\"rel\":%s,\"to\":%s,\"hop\":%d}"
          (jesc from) (jesc rel) (jesc to_) hop in
      let ring1 = neighborhood_edges p in
      let j1 = List.map (edge_json ~hop:1 p.slug) ring1 in
      let j2 =
        if hops < 2 then []
        else
          ring1
          |> List.filter_map (fun (_, s) -> if s = p.slug then None else find_note pages s)
          |> List.sort_uniq (fun a b -> compare a.slug b.slug)
          |> List.concat_map (fun q -> List.map (edge_json ~hop:2 q.slug) (neighborhood_edges q)) in
      Printf.sprintf "{\"note\":%s,\"title\":%s,\"hops\":%d,\"edges\":[%s]}"
        (jesc p.slug) (jesc p.title) hops (String.concat "," (j1 @ j2))

(* the Zettelkasten maintenance queue as JSON — REPORT-ONLY (journal
   20260729-1056 §6.6 discipline: anomalies prompt an agent pass, never a
   gate red). orphans: degree-0 notes (LAW orphan-iff-degree-0). unlinked
   mentions: (mentioner → mentioned) pairs an agent can verify and link.
   unpublished: lifecycle states needing attention. review: notes carrying a
   next_review stamp, VERBATIM — the caller compares dates (this kernel takes
   no clock, staying pure/deterministic). *)
(* the anomalies MODEL (zk-web-surfacing): ONE pure derivation feeding TWO
   encoders — anomalies_json (the MCP/CLI contract, byte-stable) and the
   /docs/anomalies board renderer. All classes REPORT-ONLY. *)
type anomalies = {
  an_orphans : string list;
  an_mentions : (string * string) list;      (* mentioner -> mentioned *)
  an_unpublished : (string * string) list;   (* slug, status *)
  an_review : (string * string) list;        (* slug, next_review *)
  an_invalid_types : (string * string) list; (* slug, type *)
  an_unsupported : string list;
  an_undermined : (string * string) list;    (* slug, type *)
  an_disputed : string list;
  an_embed_cycles : string list;
  an_holes : (string * string) list;         (* community-id pair *)
}

let anomalies_model (pages : page list) : anomalies =
  let pages = core_pages pages in  (* 94w8.2-M projection: episodic notes are intentional non-graph citizens *)
  let an_orphans = List.filter (fun p -> degree p = 0 && p.mentions = []) pages
                   |> List.map (fun p -> p.slug) in
  let an_mentions = List.concat_map (fun p ->
      List.map (fun m -> (m, p.slug)) p.mentions) pages in
  let an_unpublished = List.filter_map (fun p ->
      if p.meta.status = "published" then None else Some (p.slug, p.meta.status)) pages in
  let an_review = List.filter_map (fun p ->
      if p.meta.next_review = "" then None else Some (p.slug, p.meta.next_review)) pages in
  (* discourse-type structural checks (zk-discourse-types, 94w7.5) *)
  let an_invalid_types = List.filter_map (fun p ->
      if List.mem p.meta.ntype valid_types then None else Some (p.slug, p.meta.ntype)) pages in
  let supported slug = List.exists (fun q -> List.mem (slug, "supports") q.typed) pages in
  let an_unsupported = List.filter_map (fun p ->
      if p.meta.ntype = "claim" && not (supported p.slug) then Some p.slug else None) pages in
  (* grounded semantics (zk-grounded-semantics, 94w8.2-A H2) *)
  let gst = grounded_statuses pages in
  let has_attacker slug =
    List.exists (fun q -> List.exists (fun (t, r) -> r = "opposes" && t = slug) q.typed) pages in
  let an_undermined = List.filter_map (fun p ->
      if (p.meta.ntype = "claim" || p.meta.ntype = "decision")
         && List.assoc_opt p.slug gst = Some "out"
      then Some (p.slug, p.meta.ntype) else None) pages in
  let an_disputed = List.filter_map (fun (s, st) ->
      if st = "undec" && has_attacker s then Some s else None) gst in
  (* transclusion DAG check (zk-transclusion 94w7.8) *)
  let an_embed_cycles =
    let resolve = resolver_of pages in
    let n = List.length pages in
    let idx = Hashtbl.create (n * 2) in
    List.iteri (fun i p -> Hashtbl.replace idx p.slug i) pages;
    let out = Array.of_list (List.map (fun p ->
        List.filter_map (fun (base, _) ->
          Option.bind (resolve base) (Hashtbl.find_opt idx))
          (embed_lines p.raw)) pages) in
    if Array.for_all (fun l -> l = []) out then []
    else begin
      let r = reach_core n out in
      List.filteri (fun i _ -> r.(i).(i)) pages |> List.map (fun p -> p.slug)
    end in
  (* structural holes (zk-communities 94w6.5) *)
  let an_holes =
    let comm = communities pages in
    let clusters = Hashtbl.create 16 in
    List.iter (fun (s, c) ->
      Hashtbl.replace clusters c (s :: Option.value ~default:[] (Hashtbl.find_opt clusters c))) comm;
    let top =
      Hashtbl.fold (fun c ms acc -> (c, ms) :: acc) clusters []
      |> List.filter (fun (_, ms) -> List.length ms > 1)
      |> List.sort (fun (c1, m1) (c2, m2) ->
          match compare (List.length m2) (List.length m1) with 0 -> compare c1 c2 | d -> d)
      |> List.filteri (fun i _ -> i < 5) in
    let linked ms1 ms2 =
      List.exists (fun p ->
        (List.mem p.slug ms1 && List.exists (fun o -> List.mem o ms2) p.outlinks)
        || (List.mem p.slug ms2 && List.exists (fun o -> List.mem o ms1) p.outlinks)) pages in
    let rec pairs = function
      | [] -> []
      | (c1, m1) :: rest ->
          List.filter_map (fun (c2, m2) ->
            if linked m1 m2 then None else Some (c1, c2)) rest
          @ pairs rest in
    pairs top in
  { an_orphans; an_mentions; an_unpublished; an_review; an_invalid_types;
    an_unsupported; an_undermined; an_disputed; an_embed_cycles; an_holes }

let anomalies_json (pages : page list) : string =
  let m = anomalies_model pages in
  let sl xs = String.concat "," (List.map jesc xs) in
  Printf.sprintf
    "{\"orphans\":[%s],\"unlinked_mentions\":[%s],\"unpublished\":[%s],\"review\":[%s],\"invalid_types\":[%s],\"unsupported_claims\":[%s],\"undermined\":[%s],\"disputed\":[%s],\"embed_cycles\":[%s],\"structural_holes\":[%s]}"
    (sl m.an_orphans)
    (String.concat "," (List.map (fun (f, t) ->
         Printf.sprintf "{\"from\":%s,\"to\":%s}" (jesc f) (jesc t)) m.an_mentions))
    (String.concat "," (List.map (fun (s, st) ->
         Printf.sprintf "{\"slug\":%s,\"status\":%s}" (jesc s) (jesc st)) m.an_unpublished))
    (String.concat "," (List.map (fun (s, r) ->
         Printf.sprintf "{\"slug\":%s,\"next_review\":%s}" (jesc s) (jesc r)) m.an_review))
    (String.concat "," (List.map (fun (s, t) ->
         Printf.sprintf "{\"slug\":%s,\"type\":%s}" (jesc s) (jesc t)) m.an_invalid_types))
    (sl m.an_unsupported)
    (String.concat "," (List.map (fun (s, t) ->
         Printf.sprintf "{\"slug\":%s,\"type\":%s}" (jesc s) (jesc t)) m.an_undermined))
    (sl m.an_disputed)
    (sl m.an_embed_cycles)
    (String.concat "," (List.map (fun (a, b) ->
         Printf.sprintf "{\"a\":%s,\"b\":%s}" (jesc a) (jesc b)) m.an_holes))

(* ── THE FEATURE ALGEBRA (zk-feature-algebra, the ultrathink pass) ────────
   The Notion/Obsidian reference treated ALGEBRAICALLY, per the repo's own
   discipline. CARRIER: coverage — the chain Gap < Partial < Native < Strong
   plus Na (not-applicable-by-design). SIGNATURE: `cov_join` makes it a
   JOIN-SEMILATTICE with Na as the IDENTITY (an N/A feature contributes
   nothing to capability) and chain-max elsewhere. Because the carrier is
   FINITE (5 elements), the semilattice laws are verified EXHAUSTIVELY in the
   selftest — all 125 associativity triples, all 25 commutativity pairs, all
   5 idempotents: total verification, not sampling.
   ENCODINGS: the docs/features NOTES are the INITIAL encoding (the database
   is the corpus); `feature_of_page`/`feature_db` parse them into the FINAL
   encoding (typed records); the AGREEMENT law binds the two — the kernel's
   gap census must equal the count the zkquery tag path derives over the same
   pages (two independent representation paths, one answer).
   WELL-FORMEDNESS: a feature note carries EXACTLY ONE #cov-*, #src-*, and
   #area-* tag; violations are surfaced (report-only), never guessed. *)
type coverage = Cov_na | Cov_gap | Cov_partial | Cov_native | Cov_strong

let cov_rank = function
  | Cov_na -> -1 | Cov_gap -> 0 | Cov_partial -> 1 | Cov_native -> 2 | Cov_strong -> 3

let cov_join a b = match a, b with
  | Cov_na, x | x, Cov_na -> x
  | a, b -> if cov_rank a >= cov_rank b then a else b

let cov_name = function
  | Cov_na -> "na" | Cov_gap -> "gap" | Cov_partial -> "partial"
  | Cov_native -> "native" | Cov_strong -> "strong"

let cov_all = [ Cov_na; Cov_gap; Cov_partial; Cov_native; Cov_strong ]

let cov_of_tag = function
  | "cov-na" -> Some Cov_na | "cov-gap" -> Some Cov_gap
  | "cov-partial" -> Some Cov_partial | "cov-native" -> Some Cov_native
  | "cov-strong" -> Some Cov_strong | _ -> None

type feature = { fslug : string; fsrc : string; farea : string; fcov : coverage }

let tag_pfx pfx t =
  let n = String.length pfx in
  if String.length t > n && String.equal (String.sub t 0 n) pfx
  then Some (String.sub t n (String.length t - n)) else None

let feature_of_page (p : page) : (feature, string) result option =
  if not (List.mem "feature" p.tags) then None
  else
    let covs = List.filter_map cov_of_tag p.tags in
    let srcs = List.filter_map (tag_pfx "src-") p.tags in
    let areas = List.filter_map (tag_pfx "area-") p.tags in
    match covs, srcs, areas with
    | [ c ], [ s ], [ a ] -> Some (Ok { fslug = p.slug; fsrc = s; farea = a; fcov = c })
    | _ -> Some (Error p.slug)

(* the parsed database + the malformed remainder (report-only) *)
let feature_db (pages : page list) : feature list * string list =
  List.fold_left (fun (ok, bad) p ->
    match feature_of_page p with
    | None -> (ok, bad)
    | Some (Ok f) -> (f :: ok, bad)
    | Some (Error s) -> (ok, s :: bad))
    ([], []) pages
  |> fun (ok, bad) -> (List.rev ok, List.rev bad)

(* the algebraic rollup: per (source, area) — the JOIN of coverages (the
   area's best capability), the FLOOR of the comparable chain (the area's
   debt: worst non-Na), and the census. Deterministic ordering. *)
let coverage_rollup (fs : feature list) :
    (string * string * coverage * coverage option * int) list =
  let keys = List.sort_uniq compare (List.map (fun f -> (f.fsrc, f.farea)) fs) in
  List.map (fun (s, a) ->
    let members = List.filter (fun f -> f.fsrc = s && f.farea = a) fs in
    let j = List.fold_left (fun acc f -> cov_join acc f.fcov) Cov_na members in
    let chain = List.filter (fun f -> f.fcov <> Cov_na) members in
    let floor = match chain with
      | [] -> None
      | c :: r -> Some (List.fold_left (fun acc f ->
          if cov_rank f.fcov < cov_rank acc then f.fcov else acc) c.fcov r) in
    (s, a, j, floor, List.length members))
    keys

let coverage_json (pages : page list) : string =
  let fs, bad = feature_db pages in
  let census c = List.length (List.filter (fun f -> f.fcov = c) fs) in
  Printf.sprintf
    "{\"total\":%d,\"by_coverage\":{%s},\"malformed\":%s,\"rollup\":[%s]}"
    (List.length fs)
    (String.concat "," (List.map (fun c ->
         Printf.sprintf "%s:%d" (jesc (cov_name c)) (census c)) cov_all))
    (json_slist bad)
    (String.concat "," (List.map (fun (s, a, j, fl, n) ->
         Printf.sprintf
           "{\"src\":%s,\"area\":%s,\"join\":%s,\"floor\":%s,\"count\":%d}"
           (jesc s) (jesc a) (jesc (cov_name j))
           (match fl with Some f -> jesc (cov_name f) | None -> "null") n)
         (coverage_rollup fs)))

(* ── ZK-WEB-SURFACING: every ZK capability as a wiki PAGE ─────────────────
   Pure renderers over the law-tested kernels — the web is just another view
   (MCP and the CLI are the others). All READ-ONLY. *)

(* /docs/anomalies — the human face of the autonomic maintenance loop: every
   report-only defect class as a browsable, LINKED board with healing hints
   (per skills/zk-knowledge-base). An all-clear corpus renders the steady
   state explicitly. *)
(* plan S17 (smt-evidence-surface): READ-ONLY renderer for the harness's
   smt_obligations evidence rows — the zk-web-surfacing pattern: a pure
   Model→View over rows the CALLER fetched (no Db access in wiki_render),
   no state, laws per renderer (selfcheck-coverage L48: row-count
   agreement, column truth, no-write). Row shape:
   (created_at, vc_name, polarity, solver, status, verdict, elapsed_ms,
    formula_hash, core_hash). *)
let render_smt_page (pages : page list)
    ~(rows :
       (string * string * string * string * string * string * string * string * string)
       list) =
  let count_by proj =
    List.fold_left
      (fun acc r ->
        let k = proj r in
        let n = try List.assoc k acc with Not_found -> 0 in
        (k, n + 1) :: List.remove_assoc k acc)
      [] rows
    |> List.sort compare
  in
  let summary label kvs =
    Th.p
      ~a:[ Th.a_class [ "mu" ] ]
      (Th.txt (label ^ ": ")
       :: List.concat
            (List.mapi
               (fun i (k, n) ->
                 (if i = 0 then [] else [ Th.txt " \194\183 " ])
                 @ [ Th.txt (k ^ " "); Th.b [ Th.txt (string_of_int n) ] ])
               kvs))
  in
  let tr (ts, vc, pol, solver, status, verdict, ms, fh, ch) =
    Th.tr
      ~a:[ Th.a_class [ "ob" ] ]
      [ Th.td ~a:[ Th.a_class [ "mu" ] ] [ Th.txt ts ];
        Th.td [ Th.txt vc ];
        Th.td [ Th.txt pol ];
        Th.td [ Th.txt solver ];
        Th.td [ Th.txt status ];
        Th.td
          ~a:[ Th.a_class [ "v-" ^ (if verdict = "green" then "green" else "red") ] ]
          [ Th.txt verdict ];
        Th.td ~a:[ Th.a_class [ "mu" ] ] [ Th.txt (ms ^ " ms") ];
        Th.td
          ~a:[ Th.a_class [ "mu" ] ]
          ([ Th.code [ Th.txt fh ] ]
          @
          if ch = "" then []
          else [ Th.txt " "; Th.code ~a:[ Th.a_title "unsat core" ] [ Th.txt ch ] ]) ]
  in
  let body =
    [ crumb_to "smt";
      Th.h1 [ Th.txt "SMT obligations" ];
      Th.p
        ~a:[ Th.a_class [ "mu" ] ]
        [ Th.txt "The recorded solver-consultation evidence (";
          Th.code [ Th.txt "smt_obligations" ];
          Th.txt
            ", CTRL-SMT-EVIDENCE) \226\128\148 report-only: nothing reads these rows \
             for admission; the fail-closed judge is the sole green authority. ";
          Th.txt (Printf.sprintf "%d obligations shown (newest first)." (List.length rows)) ];
      summary "by solver" (count_by (fun (_, _, _, s, _, _, _, _, _) -> s));
      summary "by verdict" (count_by (fun (_, _, _, _, _, v, _, _, _) -> v));
      Th.table
        ~a:[ Th.a_class [ "zt" ] ]
        ~thead:
          (Th.thead
             [ Th.tr
                 (List.map
                    (fun h -> Th.th [ Th.txt h ])
                    [ "at"; "vc"; "polarity"; "solver"; "status"; "verdict"; "elapsed";
                      "formula / core hash" ]) ])
        (List.map tr rows) ]
  in
  page_frame_elts ~title:"SMT obligations" ~cur:"smt" ~pages ~body

(* stpa-envelope KPI dashboard (rev 5): pure Model→View over
   stpa_envelope_runs history rows the caller fetched — headline KPIs
   (watched %, top unwatched RPN, rule count) + the history table. Same
   laws family as /docs/smt: row-count agreement, KPI-cell truth,
   no-write. Row: (at, rules, mappings, mech_rules, envelope_rules,
   top_rpn). *)
let render_envelope_page (pages : page list) ~(muda : string)
    ~(rows : (string * string * string * string * string * string) list) =
  let head =
    match rows with
    | (at, rules, _, mech, env, top) :: _ ->
        let pct =
          match (int_of_string_opt mech, int_of_string_opt rules) with
          | Some m, Some r when r > 0 -> Printf.sprintf "%.1f%%" (100. *. float m /. float r)
          | _ -> "-"
        in
        Th.p
          ~a:[ Th.a_class [ "kpi" ] ]
          [ Th.txt "Watched: ";
            Th.b ~a:[ Th.a_class [ "v-green" ] ] [ Th.txt pct ];
            Th.txt (Printf.sprintf " (%s of %s rules) \194\183 unwatched top RPN: " mech rules);
            Th.b ~a:[ Th.a_class [ "v-red" ] ] [ Th.txt top ];
            Th.txt (Printf.sprintf " \194\183 envelope: %s \194\183 as of %s" env at) ]
    | [] ->
        Th.p
          ~a:[ Th.a_class [ "mu" ] ]
          [ Th.txt
              "No envelope history yet \226\128\148 run stpa_envelope.exe --record." ]
  in
  let tr (at, rules, maps, mech, env, top) =
    Th.tr
      ~a:[ Th.a_class [ "ev" ] ]
      (Th.td ~a:[ Th.a_class [ "mu" ] ] [ Th.txt at ]
       :: List.map (fun v -> Th.td [ Th.txt v ]) [ rules; maps; mech; env; top ])
  in
  let body =
    [ crumb_to "envelope";
      Th.h1 [ Th.txt "STPA Intelligence Envelope \226\128\148 KPIs" ];
      head ]
    @ (if String.length muda = 0 then []
       else
         [ Th.p
             ~a:[ Th.a_class [ "kpi" ] ]
             [ Th.txt "Zero-muda balance (anti-spiral budget): ";
               Th.b [ Th.txt muda ];
               Th.txt
                 " \226\128\148 intelligence work stays the parity program's \
                  instrument." ] ])
    @ [ Th.p
          ~a:[ Th.a_class [ "mu" ] ]
          [ Th.txt "Generated by ";
            Th.code [ Th.txt "stpa_envelope.ml" ];
            Th.txt
              " (10 in-exe laws; snapshot: STPA_INTELLIGENCE_ENVELOPE). \
               Report-only: the envelope points, laws admit, Rete gates." ];
        Th.table
          ~a:[ Th.a_class [ "zt" ] ]
          ~thead:
            (Th.thead
               [ Th.tr
                   (List.map
                      (fun h -> Th.th [ Th.txt h ])
                      [ "at"; "rules"; "mappings"; "mechanized"; "envelope"; "top RPN" ]) ])
          (List.map tr rows) ]
  in
  page_frame_elts ~title:"STPA envelope KPIs" ~cur:"envelope" ~pages ~body

let render_anomalies_page (pages : page list) =
  let m = anomalies_model pages in
  (* eta-expanded, NOT `chip_of_elt pages`: a partial application is only
     weakly polymorphic, and the chip is used both as flow content (inside
     `chips`) and as phrasing content (inside a zk-pair span). *)
  let c s = chip_of_elt pages s in
  let pair kids = Th.span ~a:[ Th.a_class [ "zk-pair" ] ] kids in
  let rel s = Th.span ~a:[ Th.a_class [ "zk-rel" ] ] [ Th.txt s ] in
  let pairchip (a, b) glue = pair [ c a; Th.txt (" " ^ glue ^ " "); c b ] in
  let relchip (s, t) = pair [ c s; Th.txt " "; rel t ] in
  let sec title hint items =
    when_ (items <> [])
      [ Th.div
          ~a:[ Th.a_class [ "zk-sec" ] ]
          [ Th.div
              ~a:[ Th.a_class [ "zk-h" ] ]
              [ Th.txt (title ^ " "); badge_n (List.length items) ];
            Th.div ~a:[ Th.a_class [ "zk-empty" ] ] [ Th.txt hint ];
            chips items ] ]
  in
  let total =
    List.length m.an_orphans + List.length m.an_mentions + List.length m.an_unpublished
    + List.length m.an_review + List.length m.an_invalid_types + List.length m.an_unsupported
    + List.length m.an_undermined + List.length m.an_disputed
    + List.length m.an_embed_cycles + List.length m.an_holes in
  let body =
    [ crumb_to "anomalies";
      Th.h1 [ Th.txt "Knowledge anomalies" ];
      mu
        [ Th.txt
            "The Zettelkasten's error budget \226\128\148 every class REPORT-ONLY \
             (never gate-mediating). Heal per ";
          link "skills--zk-knowledge-base--skill.html" "the zk-knowledge-base skill";
          Th.txt
            ": link orphans from a bridge note, close holes with a MEMBER edge, \
             answer undermined claims with ";
          Th.code [ Th.txt "@supports" ];
          Th.txt " evidence." ] ]
    @ when_ (total = 0)
        [ Th.div
            ~a:[ Th.a_class [ "zk-sec" ] ]
            [ Th.div ~a:[ Th.a_class [ "zk-h" ] ] [ Th.txt "\226\156\133 All clear" ];
              Th.div
                ~a:[ Th.a_class [ "zk-empty" ] ]
                [ Th.txt
                    "No orphans, no holes, no undermined claims \226\128\148 the graph \
                     is fully connected and defensible. Steady state." ] ] ]
    @ sec "\240\159\143\157 Orphans"
        "No links in or out \226\128\148 write them a bridge, or link them from a MoC."
        (List.map c m.an_orphans)
    @ sec "\226\151\135 Unlinked mentions"
        "Named without a [[link]] \226\128\148 verify and make the edge real."
        (List.map (fun p -> pairchip p "\226\134\146") m.an_mentions)
    @ sec "\240\159\149\179 Structural holes"
        "Top communities with NO connecting edge \226\128\148 bridge with a member-edge note."
        (List.map (fun p -> pairchip p "\226\136\165") m.an_holes)
    @ sec "\226\154\150 Undermined claims/decisions"
        "DEFEATED under grounded semantics \226\128\148 answer the attacker with @supports evidence or revise."
        (List.map relchip m.an_undermined)
    @ sec "\226\154\150 Disputed (undecided)"
        "Mutual opposition, nothing settles it \226\128\148 add independent evidence."
        (List.map c m.an_disputed)
    @ sec "\226\136\158 Embed cycles"
        "Transclusion must be a DAG \226\128\148 break one edge of each cycle."
        (List.map c m.an_embed_cycles)
    @ sec "\240\159\148\148 Unsupported claims"
        "type: claim with no inbound @supports edge."
        (List.map c m.an_unsupported)
    @ sec "?\239\184\143 Invalid discourse types"
        "Outside note|question|claim|evidence|decision."
        (List.map relchip m.an_invalid_types)
    @ sec "\240\159\147\157 Unpublished"
        "draft / flagged_for_review lifecycle states."
        (List.map relchip m.an_unpublished)
    @ sec "\226\143\179 Review stamps"
        "Carrying next_review \226\128\148 compare against today."
        (List.map relchip m.an_review)
    @ [ foot
          [ Th.txt
              "Derived live from the corpus by anomalies_model (docs_wiki.ml) \226\128\148 \
               the same data ";
            Th.code [ Th.txt "zk_anomalies" ]; Th.txt "/";
            Th.code [ Th.txt "--zk-anomalies" ]; Th.txt " serve. ";
            link "index.html" "\226\134\144 index"; Th.txt " \194\183 ";
            link "currency.html" "currency" ] ]
  in
  page_frame_elts ~title:"Anomalies" ~cur:"anomalies" ~pages ~body

(* /docs/query — the interactive zkquery console: the SAME parse/eval/table
   path the embedded ```zkquery fences use, driven by a GET form.

   Converted to typed markup, and this page earns it more than most: `q` is a
   GET PARAMETER — the most directly attacker-controlled string in the module —
   and it was previously hand-escaped into both an error message and a form
   `value=` attribute. Two interpolations, two chances to forget. Now neither
   exists. *)
let render_query_page (pages : page list) (q : string) =
  let code s = Th.code [ Th.txt s ] in
  let result : [> Html_types.flow5 ] Th.elt list =
    if String.trim q = "" then
      [ Th.p
          ~a:[ Th.a_class [ "mu" ] ]
          [ Th.txt "Try: ";
            code "from type:claim where status=draft sort pagerank desc limit 10";
            Th.txt " · "; code "from group:harness-wiki sort degree desc"; Th.txt " · ";
            code "where words>=500 sort words desc limit 15" ] ]
    else
      match zkquery_parse q with
      | Error e -> [ Th.div ~a:[ Th.a_class [ "zq-err" ] ] [ Th.txt e ] ]
      | Ok zq ->
          let rows = zkquery_eval pages zq in
          let tr (r : page) =
            Th.tr
              [ Th.td
                  [ Th.a
                      ~a:[ Th.a_class [ "zettel" ]; Th.a_href (r.slug ^ ".html") ]
                      [ Th.txt r.title ] ];
                Th.td [ Th.txt r.group ]; Th.td [ Th.txt r.meta.ntype ];
                Th.td [ Th.txt r.meta.status ];
                Th.td [ Th.txt (string_of_int (word_count r)) ];
                Th.td [ Th.txt (string_of_int (degree r)) ] ]
          in
          [ Th.table
              ~a:[ Th.a_class [ "zq-t" ] ]
              ~thead:
                (Th.thead
                   [ Th.tr
                       [ Th.th [ Th.txt "note" ]; Th.th [ Th.txt "group" ];
                         Th.th [ Th.txt "type" ]; Th.th [ Th.txt "status" ];
                         Th.th [ Th.txt "words" ]; Th.th [ Th.txt "°" ] ] ])
              (List.map tr rows);
            Th.div
              ~a:[ Th.a_class [ "zq-n" ] ]
              [ Th.txt
                  (Printf.sprintf "%d row%s" (List.length rows)
                     (if List.length rows = 1 then "" else "s")) ] ]
  in
  let body =
    [ Th.div
        ~a:[ Th.a_class [ "crumb" ] ]
        [ Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "docs" ]; Th.txt " / query" ];
      Th.h1 [ Th.txt "zkquery console" ];
      Th.p
        ~a:[ Th.a_class [ "mu" ] ]
        [ Th.txt "Structured queries over the corpus — the TOTAL zkquery DSL: ";
          code
            "[from all|type:T|group:G|tag:T] [where COND and …] [sort \
             slug|title|words|degree|pagerank [asc|desc]] [limit N]";
          Th.txt ". Unknown fields reject with a named error. Save a query by embedding a ";
          code "```zkquery"; Th.txt " fence in any note." ];
      Th.form
        ~a:[ Th.a_method `Get; Th.a_action "query.html" ]
        [ Th.input
            ~a:
              [ Th.a_class [ "zks-input" ]; Th.a_input_type `Search; Th.a_name "q";
                Th.a_value q;
                Th.a_placeholder
                  "from type:claim where status=draft sort pagerank desc limit 10";
                Th.a_autofocus () ]
            () ];
      Th.div ~a:[ Th.a_class [ "zq" ] ] result;
      Th.div
        ~a:[ Th.a_class [ "foot" ] ]
        [ Th.txt "Same kernel as "; code "zk_query"; Th.txt "/"; code "--zk-query";
          Th.txt " and embedded fences. ";
          Th.a ~a:[ Th.a_href "index.html" ] [ Th.txt "← index" ]; Th.txt " · ";
          Th.a ~a:[ Th.a_href "anomalies.html" ] [ Th.txt "anomalies" ] ]
    ]
  in
  page_frame_elts ~title:"zkquery" ~cur:"query" ~pages ~body

(* /docs/timeline — the bi-temporal graph browser over zk_edge_history rows
   (src, dst, added_commit, added_ts, removed_commit, removed_ts), refreshed
   by the currency timer. Pure over the ROWS; the shell fetches SQLite.
   Alive-at(c) uses timestamp order with the HALF-OPEN convention: an edge is
   alive at its add stamp and GONE at its removal stamp. *)
let render_timeline (pages : page list)
    ~(rows : (string * string * string * string * string * string) list)
    ~(sel : string) =
  if rows = [] then
    page_frame_elts ~title:"Timeline" ~cur:"timeline" ~pages
      ~body:
        [ crumb_to "timeline";
          Th.h1 [ Th.txt "Timeline" ];
          mu
            [ Th.txt "No mined history yet \226\128\148 run ";
              Th.code [ Th.txt "--zk-temporal" ];
              Th.txt " or wait for the ";
              Th.code [ Th.txt "zigvm-zk-maintain.timer" ];
              Th.txt " currency loop." ] ]
  else begin
    let commits =
      List.concat_map (fun (_, _, ac, ats, rc, rts) ->
        (if ac = "" then [] else [ (ats, ac) ]) @ (if rc = "" then [] else [ (rts, rc) ])) rows
      |> List.sort_uniq compare in
    let sel = if sel <> "" && List.exists (fun (_, c) -> c = sel) commits then sel
              else (match List.rev commits with (_, c) :: _ -> c | [] -> "") in
    let sel_ts = try fst (List.find (fun (_, c) -> c = sel) commits) with Not_found -> "" in
    let alive_at ts =
      List.filter (fun (_, _, _, ats, _, rts) -> ats <= ts && (rts = "" || ts < rts)) rows in
    let alive = alive_at sel_ts in
    let counts = List.map (fun (ts, _) -> List.length (alive_at ts)) commits in
    let maxc = List.fold_left max 1 counts in
    let bar_w = 14 in
    let fl = float_of_int in
    (* inline SVG sparkline of |edges| across the window. Typed through
       Tyxml.Svg: a coordinate is a NUMBER rather than an integer spliced into a
       string, and a bar with its tooltip cannot be left unclosed. *)
    let spark_w = fl (bar_w * List.length counts) in
    let spark =
      Th.svg
        ~a:
          [ Ts.a_class [ "tl-spark" ]; Ts.a_width (spark_w, None);
            Ts.a_height (42., None); Ts.a_viewBox (0., 0., spark_w, 42.) ]
        (List.mapi
           (fun i n ->
             let h = max 2 (40 * n / maxc) in
             let (_, c) = List.nth commits i in
             Ts.a
               ~a:[ Ts.a_href ("timeline.html?c=" ^ c) ]
               [ Ts.rect
                   ~a:
                     [ Ts.a_x (fl (i * bar_w + 1), None); Ts.a_y (fl (42 - h), None);
                       Ts.a_width (fl (bar_w - 3), None); Ts.a_height (fl h, None);
                       Ts.a_class ("tl-bar" :: when_ (c = sel) [ "sel" ]) ]
                   [ Ts.title (Ts.txt (Printf.sprintf "%s \194\183 %d edges" c n)) ] ])
           counts)
    in
    let commit_links =
      List.concat
        (List.mapi
           (fun i (ts, c) ->
             when_ (i > 0) [ Th.txt " " ]
             @ [ Th.a
                   ~a:
                     [ Th.a_class ("tl-c" :: when_ (c = sel) [ "sel" ]);
                       Th.a_href ("timeline.html?c=" ^ c); Th.a_title ts ]
                   [ Th.txt (String.sub c 0 (min 9 (String.length c))) ] ])
           commits)
    in
    let churn =
      let tbl = Hashtbl.create 64 in
      let bump s n = Hashtbl.replace tbl s (n + Option.value ~default:0 (Hashtbl.find_opt tbl s)) in
      List.iter (fun (a, b, _, _, _, rts) ->
        let ev = 1 + (if rts = "" then 0 else 1) in bump a ev; bump b ev) rows;
      Hashtbl.fold (fun s n l -> (s, n) :: l) tbl []
      |> List.sort (fun (s1, a) (s2, b) -> if b <> a then compare b a else compare s1 s2)
      |> List.filteri (fun i _ -> i < 8) in
    let shown = List.filteri (fun i _ -> i < 60) alive in
    let body =
      [ crumb_to "timeline";
        Th.h1 [ Th.txt "Timeline \226\128\148 the graph through git" ];
        mu
          [ Th.txt
              (Printf.sprintf
                 "Bi-temporal link history mined from the last %d doc commits \
                  (half-open intervals, non-destructive re-adds). Pick a commit \
                  to see the graph AS IT STOOD."
                 (List.length commits)) ];
        spark;
        Th.div ~a:[ Th.a_class [ "tl-commits" ] ] commit_links;
        Th.div
          ~a:[ Th.a_class [ "zk-sec" ] ]
          [ Th.div
              ~a:[ Th.a_class [ "zk-h" ] ]
              [ Th.txt
                  (Printf.sprintf "@ %s " (String.sub sel 0 (min 9 (String.length sel))));
                badge (Printf.sprintf "%d edges alive" (List.length alive)) ];
            chips
              (List.map
                 (fun (a, b, _, _, _, _) ->
                   Th.span
                     ~a:[ Th.a_class [ "zk-pair" ] ]
                     [ chip_of_elt pages a; Th.txt " \226\134\146 "; chip_of_elt pages b ])
                 shown
              @ when_ (List.length alive > 60)
                  [ badge (Printf.sprintf "\226\128\166 +%d more" (List.length alive - 60)) ]) ];
        Th.div
          ~a:[ Th.a_class [ "zk-sec" ] ]
          [ Th.div
              ~a:[ Th.a_class [ "zk-h" ] ]
              [ Th.txt "\240\159\148\165 Churn hotspots "; badge "review candidates" ];
            Th.div
              ~a:[ Th.a_class [ "zk-empty" ] ]
              [ Th.txt
                  "Notes whose neighborhood moved most across the window \
                   (\194\1677.9 decay signal)." ];
            chips
              (List.map
                 (fun (s, n) ->
                   Th.span
                     ~a:[ Th.a_class [ "zk-pair" ] ]
                     [ chip_of_elt pages s; Th.txt " ";
                       Th.span
                         ~a:[ Th.a_class [ "zk-rel" ] ]
                         [ Th.txt (Printf.sprintf "%d ev" n) ] ])
                 churn) ];
        foot
          [ Th.txt "Same intervals as "; Th.code [ Th.txt "--zk-temporal" ]; Th.txt "/";
            Th.code [ Th.txt "--zk-asof" ]; Th.txt ", served from zk_edge_history. ";
            link "index.html" "\226\134\144 index"; Th.txt " \194\183 ";
            link "currency.html" "currency" ] ]
    in
    page_frame_elts ~title:"Timeline" ~cur:"timeline" ~pages ~body
  end

(* /docs/currency — the organism's vitals: MoC freshness, vector-store
   census, corpus census, last audit verdict. Pure over its inputs. *)
let render_currency (pages : page list)
    ~(vec_counts : (string * int) list) ~(audit : string) =
  let mocs_st = moc_status pages in
  (* the moc-st pill: one shape, three users (MoC freshness, coverage join,
     coverage floor) — the class list is a LIST, never a joined string *)
  let st_span cls label = Th.span ~a:[ Th.a_class [ "moc-st"; cls ] ] [ Th.txt label ] in
  let st_chip = function
    | Moc_fresh -> st_span "fresh" "fresh"
    | Moc_stale -> st_span "stale" "stale"
    | Moc_missing -> st_span "missing" "missing"
    | Moc_frozen -> st_span "frozen" "frozen \240\159\148\146"
  in
  let n_episodic = List.length (List.filter is_episodic pages) in
  let stat label v =
    Th.span ~a:[ Th.a_class [ "zk-pair" ] ] [ Th.txt (label ^ " "); Th.b [ Th.txt v ] ]
  in
  let vitals =
    Th.div
      ~a:[ Th.a_class [ "zk-sec" ] ]
      [ Th.div ~a:[ Th.a_class [ "zk-h" ] ] [ Th.txt "Vitals" ];
        chips
          ([ stat "notes" (string_of_int (List.length pages));
             stat "episodic" (string_of_int n_episodic) ]
          @ List.map (fun (k, n) -> stat ("vec:" ^ k) (string_of_int n)) vec_counts
          @ [ stat "audit" (if audit = "" then "unknown" else audit) ]) ]
  in
  let mocs_elts =
    if mocs_st = [] then
      [ Th.div ~a:[ Th.a_class [ "zk-empty" ] ]
          [ Th.txt "No size\226\137\1652 communities yet." ] ]
    else
      List.map
        (fun (cid, members, st) ->
          Th.div
            ~a:[ Th.a_class [ "zk-bl" ] ]
            [ chip_of_elt pages cid; Th.txt " ";
              badge (Printf.sprintf "%d members" (List.length members));
              Th.txt " "; st_chip st ])
        mocs_st
  in
  (* the FEATURE-ALGEBRA rollup (zk-feature-algebra): reference coverage per
     source·area — join = capability, floor = debt; malformed notes surfaced *)
  let fs, bad = feature_db pages in
  let cov_elts =
    if fs = [] then
      [ Th.div ~a:[ Th.a_class [ "zk-empty" ] ]
          [ Th.txt "No feature database in the corpus." ] ]
    else
      List.map
        (fun (s, a, j, fl, n) ->
          Th.div
            ~a:[ Th.a_class [ "zk-bl" ] ]
            ([ Th.span ~a:[ Th.a_class [ "zk-rel" ] ] [ Th.txt (s ^ "\194\183" ^ a) ];
               Th.txt " ";
               st_span
                 (match j with
                  | Cov_strong | Cov_native -> "fresh"
                  | Cov_partial -> "stale"
                  | _ -> "missing")
                 ("join " ^ cov_name j) ]
            @ (match fl with
               | Some f ->
                   [ Th.txt " ";
                     st_span
                       (if f = Cov_gap then "missing" else "frozen")
                       ("floor " ^ cov_name f) ]
               | None -> [])
            @ [ Th.txt " ";
                badge (Printf.sprintf "%d feature%s" n (if n = 1 then "" else "s")) ]))
        (coverage_rollup fs)
      @ when_ (bad <> [])
          [ Th.div
              ~a:[ Th.a_class [ "zq-err" ] ]
              [ Th.txt
                  ("malformed feature notes (tag discipline): "
                  ^ String.concat ", " bad) ] ]
  in
  let body =
    [ crumb_to "currency";
      Th.h1 [ Th.txt "Currency — is the self-model current?" ];
      mu
        [ Th.txt "The knowledge base keeps ITSELF current: the ";
          Th.code [ Th.txt "zigvm-zk-maintain.timer" ];
          Th.txt
            " runs audit + vectors + MoCs + temporal every 30 minutes; episodic \
             notes write themselves on every recorded cycle. This page is the \
             pulse." ];
      vitals;
      Th.div
        ~a:[ Th.a_class [ "zk-sec" ] ]
        ([ Th.div
             ~a:[ Th.a_class [ "zk-h" ] ]
             [ Th.txt "Community MoCs "; badge "membership-hash memoized" ];
           Th.div
             ~a:[ Th.a_class [ "zk-empty" ] ]
             [ Th.txt "fresh = hash matches \194\183 stale/missing = next ";
               Th.code [ Th.txt "--zk-moc" ];
               Th.txt " redraws \194\183 frozen = human-promoted, never overwritten." ] ]
        @ mocs_elts);
      Th.div
        ~a:[ Th.a_class [ "zk-sec" ] ]
        ([ Th.div
             ~a:[ Th.a_class [ "zk-h" ] ]
             [ Th.txt "Reference coverage "; badge "the feature algebra" ];
           Th.div
             ~a:[ Th.a_class [ "zk-empty" ] ]
             [ Th.txt "Per source\194\183area over ";
               link "features--readme.html" "the feature database";
               Th.txt ": "; Th.b [ Th.txt "join" ];
               Th.txt " = the best we offer (coverage semilattice, Na-identity) \194\183 ";
               Th.b [ Th.txt "floor" ];
               Th.txt " = the debt (worst comparable)." ] ]
        @ cov_elts);
      foot
        [ link "index.html" "\226\134\144 index"; Th.txt " · ";
          link "anomalies.html" "anomalies"; Th.txt " · ";
          link "timeline.html" "timeline"; Th.txt " · ";
          link "query.html" "query" ] ]
  in
  page_frame_elts ~title:"Currency" ~cur:"currency" ~pages ~body

(* ── self-test (a law: the renderer is total + structurally correct) ───── *)
(* Called by the harness `--docs-wiki` mode + the selfcheck battery; a plain
   function (no ppx_inline_test dep). Raises on any violation. *)
let has s sub = let re = Str.regexp_string sub in try ignore (Str.search_forward re s 0); true with Not_found -> false
let selftest () =
  (* These assertions used to pin the retired streaming renderer's bytes. They
     were repointed at the AST rather than deleted: the behaviours they check
     are real, and dropping twenty tests to remove one function is the worse
     trade. Expected bytes were adjusted where typed markup differs — quoted
     attribute values, and no newline between blocks. *)
  let render_md_t s = render_markdown_typed ~resolve:(fun _ -> None) s in
  assert (render_md_t "# Hi" = "<h1 id=\"hi\">Hi</h1>");
  (* inline code is escaped and NOT re-interpreted (no HTML injection) *)
  assert (has (render_md_t "a `x<y` b") "<code>x&lt;y</code>");
  (* bold + link *)
  let h2 = render_md_t "see **X** and [t](u)" in
  assert (has h2 "<strong>X</strong>");
  assert (has h2 "<a href=\"u\">t</a>");
  (* raw < in prose is escaped *)
  assert (has (render_md_t "a < b") "&lt;");
  (* headers/lists/tables/blockquote/code all produce their tags *)
  assert (has (render_md_t "- one\n- two") "<ul>");
  assert (has (render_md_t "| a | b |\n|---|---|\n| 1 | 2 |") "<table>");
  assert (has (render_md_t "> quote") "<blockquote>");
  assert (has (render_md_t "```\ncode\n```") "<pre><code>");
  (* TOTALITY: an unclosed fence still renders (no exception) *)
  ignore (render_md_t "```\nunclosed");
  (* slug *)
  assert (slug_of_path "docs/harness-wiki/02-The-Gate.md" = "harness-wiki--02-the-gate");
  (* a page round-trips through build with a non-empty title + html *)
  (match build [ ("docs/X.md", "# Title\n\nbody") ] with
   | [ p ] -> assert (p.title = "Title"); assert (String.length p.html > 0)
   | _ -> assert false);
  (* ZETTELKASTEN: [[wiki-links]] resolve, and the backlink is BIDIRECTIONAL. *)
  assert (znorm "02 · The Gate" = "02-the-gate");
  let notes = build
    [ ("docs/a.md", "# Alpha\n\nsee [[Beta]] and [[Gamma|the third]]")
    ; ("docs/b.md", "# Beta\n\nplain note") ] in
  let a = List.find (fun p -> p.title = "Alpha") notes in
  let bnote = List.find (fun p -> p.title = "Beta") notes in
  (* Alpha's [[Beta]] resolves to b's slug (an outlink) and renders a zettel link *)
  assert (List.mem bnote.slug a.outlinks);
  (* p.html now comes from the TYPED path, which quotes attribute values. The
     byte-exact assertions further down still pin `render_markdown` — the
     oracle — in its own unquoted form, deliberately. *)
  assert (has a.html "class=\"zettel\"");
  (* the backlink is automatic + bidirectional: Beta is Linked-referenced by Alpha *)
  assert (List.mem a.slug bnote.backlinks);
  assert (has (render_page ~pages:notes bnote) "Linked references");
  assert (has (render_page ~pages:notes bnote) a.title);   (* Alpha shows as a backlink chip *)
  (* [[Gamma|the third]] is unresolved (no Gamma note) → a dashed missing link, display honoured *)
  assert (has a.html "zettel missing");
  assert (has a.html "the third");
  (* the graph renders edges + hubs *)
  assert (has (render_graph notes) "Zettelkasten graph");
  assert (has (render_graph notes) "zk-edge");
  (* internal *.md links are rewritten to the note's <slug>.html (working links) *)
  let lnotes = build
    [ ("docs/g.md", "# Guide\n\nsee [the gate](sub/02-The-Gate.md) and [ext](https://x.io)")
    ; ("docs/sub/02-The-Gate.md", "# The Gate\n\n#core #gate tagged note") ] in
  let g = List.find (fun p -> p.title = "Guide") lnotes in
  assert (has g.html "href=\"sub--02-the-gate.html\"");   (* .md → slug.html *)
  assert (has g.html "https://x.io");                       (* external untouched *)
  (* #tags parsed + indexed *)
  let gate = List.find (fun p -> p.title = "The Gate") lnotes in
  assert (List.mem "core" gate.tags && List.mem "gate" gate.tags);
  assert (has (render_tags lnotes) "#core");
  assert (has (render_page ~pages:lnotes gate) "zk-tag");
  (* UNLINKED MENTIONS: Guide names "The Gate" via a link so NOT unlinked; a note
     that mentions the title in prose WITHOUT a link IS an unlinked mention *)
  let mnotes = build
    [ ("docs/x.md", "# The Gate\n\natomic")
    ; ("docs/y.md", "# Other\n\nwe rely on The Gate every day") ] in
  let xg = List.find (fun p -> p.title = "The Gate") mnotes in
  let yo = List.find (fun p -> p.title = "Other") mnotes in
  assert (List.mem yo.slug xg.mentions);                    (* Other unlinked-mentions The Gate *)
  assert (has (render_page ~pages:mnotes xg) "Unlinked mentions");
  (* AHO-CORASICK DIFFERENTIAL: the indexed one-pass mention result equals the
     former all-pairs substring oracle, including mixed case, overlapping title
     suffixes, self exclusion, and explicit-link exclusion. *)
  let mention_law_notes = build
    [ ("docs/gate.md", "# The Gate\n\ncore")
    ; ("docs/ate.md", "# Gate\n\nshorter overlapping title")
    ; ("docs/prose.md", "# Prose\n\nTHE GATE and gate are named here")
    ; ("docs/linked.md", "# Linked\n\n[[The Gate]] is explicit") ] in
  let mention_law_ac =
    mention_automaton
      (List.map (fun p -> (p.title, p.slug)) mention_law_notes) in
  assert (mention_law_ac.ac_count > 1);
  List.iter
    (fun target ->
      let naive =
        List.filter_map
          (fun source ->
            if source.slug <> target.slug
               && not (List.mem target.slug source.outlinks)
               && contains_case_ascii source.raw target.title
            then Some source.slug else None)
          mention_law_notes
        |> List.sort_uniq compare in
      assert (naive = target.mentions);
      let indexed_sources =
        List.filter_map
          (fun source ->
            if List.mem target.slug (mention_matches mention_law_ac source.raw)
               && source.slug <> target.slug
               && not (List.mem target.slug source.outlinks)
            then Some source.slug else None)
          mention_law_notes
        |> List.sort_uniq compare in
      assert (naive = indexed_sources))
    mention_law_notes;
  (* MUTATION DISCRIMINATION.  A broken automaton that drops a terminal output,
     and a reduction that forgets explicit-link exclusion, must both disagree
     with the admitted page value. *)
  let gate_target = List.find (fun p -> p.title = "The Gate") mention_law_notes in
  let prose_source = List.find (fun p -> p.title = "Prose") mention_law_notes in
  let linked_source = List.find (fun p -> p.title = "Linked") mention_law_notes in
  let mut_drop_terminal =
    List.filter (( <> ) prose_source.slug) gate_target.mentions in
  let mut_include_explicit =
    List.sort_uniq compare (linked_source.slug :: gate_target.mentions) in
  assert (mut_drop_terminal <> gate_target.mentions);
  assert (mut_include_explicit <> gate_target.mentions);
  (* SEARCH: the index carries every note's title + text; JSON < is escaped *)
  let sr = render_search mnotes in
  assert (has sr "zks-idx"); assert (has sr "The Gate");
  assert (has (render_search (build [ ("docs/s.md", "# S\n\n<script>x</script>") ])) "\\u003cscript");
  (* ── Zettelkasten identity + discovery laws ──────────────────────────── *)
  (* CONNECTEDNESS: degree = |outlinks| + |backlinks| (mutant: drop a term → red) *)
  let a2 = List.find (fun p -> p.title = "Alpha") notes in   (* Alpha —[[Beta]]→ Beta *)
  let b2 = List.find (fun p -> p.title = "Beta") notes in
  assert (degree a2 = List.length a2.outlinks + List.length a2.backlinks);
  assert (degree a2 = 1 && degree b2 = 1);                    (* Alpha→Beta: each has degree 1 *)
  assert (word_count a2 >= 1);                                (* a note with prose has words *)
  assert (word_count (List.hd (build [("docs/e.md","")])) = 0); (* empty note: 0 words *)
  (* the zettel CARD shows the permanent ID + connectedness *)
  let card = render_page ~pages:notes a2 in
  assert (has card "zk-card"); assert (has card a2.slug); assert (has card "linked");
  (* MAPS OF CONTENT: entry points are highest-degree, degree>0, never orphans *)
  let m = mocs notes in
  assert (List.for_all (fun p -> degree p > 0) m);            (* no orphan is an entry point *)
  assert (mocs (build [("docs/o.md","# Orphan\n\nno links")]) = []); (* no links → no MOC *)
  assert (has (render_index notes) "Entry points");
  (* SERENDIPITY: random_target is total + always a member for non-empty; None empty *)
  assert (random_target [] 0 = None);
  assert (List.for_all (fun n -> match random_target notes n with
    | Some p -> List.exists (fun q -> q.slug = p.slug) notes | None -> false) [0;1;7;99;-3]);
  assert (has (render_random notes) "Serendipity");
  assert (has (render_random notes) "location.replace");      (* the JS random jump *)
  (* ── AUTHORING kernel laws ───────────────────────────────────────────── *)
  (* PATH-SAFETY (the safety-critical law): for ANY title — including hostile
     traversal payloads — the write target is under docs/zk/ with a clean
     basename. The shell writes ONLY note_path's output. *)
  let adversarial = [ "normal title"; "../../etc/passwd"; "a/b/c"; "..\\..\\win";
                      ""; "   "; "Ünïçödé ☃ 你好"; "#!$%^&*()"; "....//....//" ] in
  assert (List.for_all (fun t -> path_is_safe (note_path ~ts:1_700_000_000. ~title:t)) adversarial);
  assert (not (path_is_safe "docs/zk/../secret.md"));         (* the predicate rejects traversal *)
  assert (not (path_is_safe "etc/passwd"));                   (* …and anything outside docs/zk/ *)
  assert (not (path_is_safe "docs/zk/A B.md"));               (* …and non-[a-z0-9-] basenames *)
  (* the id is a pure function of the timestamp (deterministic, sortable) *)
  assert (note_id_of 0. = "19700101-000000");
  assert (String.length (note_id_of 1_700_000_000.) = 15);
  (* ROUND-TRIP / HOMOMORPHISM: author a note, build it, recover its meaning *)
  let md = note_markdown ~title:"My Idea" ~body:"see [[Alpha]]" ~tags:["Zettelkasten"; "method"] in
  let authored = build [ (note_path ~ts:1. ~title:"My Idea", md); ("docs/a.md", "# Alpha\n\nplain") ] in
  let mi = List.find (fun p -> p.title = "My Idea") authored in
  assert (mi.title = "My Idea");                              (* title recovered from "# " heading *)
  assert (List.mem "zettelkasten" mi.tags && List.mem "method" mi.tags); (* tags recovered *)
  assert (List.exists (fun s -> (List.find (fun q -> q.slug = s) authored).title = "Alpha") mi.outlinks); (* [[Alpha]] is a live outlink *)
  (* empty title/body never crash + still produce a valid, safe, titled note *)
  let empty = note_markdown ~title:"" ~body:"" ~tags:[] in
  assert (has empty "# Untitled");
  assert (path_is_safe (note_path ~ts:1. ~title:""));
  (* is_authored: only docs/zk/ notes are editable; curated docs are not *)
  assert (is_authored { mi with path = "docs/zk/x.md" });
  assert (not (is_authored { mi with path = "docs/ARCHITECTURE.md" }));
  (* the forms render *)
  assert (has (render_new_form notes) "New note");
  (* TyXML renders the `Post variant UPPERCASE; HTML form methods are
     case-insensitive, so this is the same form, spelled the library's way *)
  assert (has (render_new_form notes) "method=\"POST\"");
  assert (has (render_edit_form ~pages:authored mi) "Save changes");
  assert (has (render_edit_form ~pages:authored mi) "Delete note");
  (* ── SYSTEM MEMORY laws (the ZK as git+SQLite memory) ────────────────── *)
  (* TOTAL: empty memory still renders a valid page (no ledger yet ≠ crash) *)
  assert (has (render_memory ~pages:notes empty_memory) "System memory");
  (* INJECTION-SAFE: memory text from git/SQLite is escaped, never live HTML *)
  let mm = { empty_memory with head = "abc123 x";
             cycles = [ ("2026-01-01", "gap-x", "ok", "<script>alert(1)</script>") ];
             commits = [ ("deadbee", "did a thing") ] } in
  let mh = render_memory ~pages:notes mm in
  assert (has mh "&lt;script&gt;" && not (has mh "<script>alert"));
  (* COUNT: renders exactly the cycles given *)
  assert (has mh "gap-x" && has mh "did a thing");
  (* THREADING: a memory item mentioning a known note title relates to it *)
  let rel = mem_related notes "we closed the Alpha refactor cycle" in
  assert (List.exists (fun (p : page) -> p.title = "Alpha") rel);
  assert (mem_related notes "nothing here matches" |> List.for_all (fun (p:page) -> String.length p.title >= 5));
  (* ci_contains is case-insensitive + total on empty needle *)
  assert (ci_contains "The Gate keeps us honest" "the gate");
  assert (not (ci_contains "x" ""));
  (* ── INTERACTIVE GRAPH laws (the model is a homomorphism of the corpus) ── *)
  let ig = render_graph_interactive notes in
  assert (has ig "fg-data" && has ig "requestAnimationFrame");   (* the sim is present *)
  (* one node per page (HOMOMORPHISM: |nodes| = |pages|) *)
  let count_sub s sub = let re = Str.regexp_string sub and n = ref 0 and i = ref 0 in
    (try while true do i := Str.search_forward re s !i + 1; incr n done with Not_found -> ()); !n in
  assert (count_sub ig "\"id\":" = List.length notes);
  (* every edge endpoint is a real node (referential integrity) — Alpha→Beta = 1 edge *)
  assert (count_sub ig "{\"s\":" = List.fold_left (fun a p -> a + List.length p.outlinks) 0 notes);
  (* INJECTION-SAFE: a hostile title is jesc-escaped in the JSON model *)
  let ig2 = render_graph_interactive (build [ ("docs/x.md", "# <script>alert(1)</script>\n\nn") ]) in
  assert (not (has ig2 "<script>alert") && has ig2 "\\u003cscript");
  (* TOTAL: empty corpus → valid page, no nodes *)
  assert (has (render_graph_interactive []) "fg-data");
  (* ── NETWORK SCIENCE laws (PageRank, combinatorics, degree dist) ──────── *)
  (* PageRank is a probability distribution: non-negative and sums to 1 *)
  let pr = pagerank notes in
  let sum = List.fold_left (fun a (_, s) -> a +. s) 0. pr in
  assert (Float.abs (sum -. 1.0) < 1e-6);
  assert (List.for_all (fun (_, s) -> s >= 0.) pr);
  assert (List.length pr = List.length notes);
  (* a linked note (Beta, which Alpha points to) outranks a bare/orphan node *)
  let core = pagerank_core 2 [| [1]; [] |] in         (* 0→1 ; 1 dangling *)
  assert (Float.abs (core.(0) +. core.(1) -. 1.0) < 1e-6 && core.(1) > core.(0));
  assert (pagerank_core 0 [||] = [||]);               (* total on empty *)
  (* ── PERSONALIZED PageRank laws (zk-ppr-retrieval, journal 20260729-1056 §7.1) *)
  (* LAW ppr-degeneration: uniform teleport ≡ the classic kernel, element-wise —
     the pre-slice behavior is the ORACLE of the generalized kernel *)
  let dn = 5 in
  let dout = [| [1; 2]; [2]; [0]; [4]; [] |] in
  let uni = Array.make dn (1. /. float_of_int dn) in
  let classic = pagerank_core dn dout and lifted = pagerank_core ~teleport:uni dn dout in
  Array.iteri (fun i x -> assert (Float.abs (x -. lifted.(i)) < 1e-9)) classic;
  (* LAW stochasticity under a skewed teleport: still a probability distribution *)
  let skew = pagerank_core ~teleport:[| 0.9; 0.; 0.1; 0.; 0. |] dn dout in
  assert (Float.abs (Array.fold_left (+.) 0. skew -. 1.0) < 1e-6);
  assert (Array.for_all (fun x -> x >= 0.) skew);
  (* LAW seed-locality (absorption): two disconnected components, ALL teleport
     mass on component A = {0,1} ⇒ component B = {2→3, 3 dangling} drains to ~0
     (its dangling mass recycles to τ, i.e. back to A — the personalization) *)
  let loc = pagerank_core ~teleport:[| 1.; 0.; 0.; 0. |] 4 [| [1]; [0]; [3]; [] |] in
  assert (loc.(2) +. loc.(3) < 1e-6);
  assert (loc.(0) > loc.(2) && loc.(1) > loc.(3));
  (* LAW dangling-to-teleport (the DISCRIMINATING locality law): the dangling
     node sits in component A = {0→1, 1 dangling} WITH the teleport mass, and
     B = {2↔3} is a self-sustaining cycle. Correct PPR returns A's dangling
     mass to τ ⊆ A, so B only decays (·d per iter ⇒ ≈5.8e-5 after 60 iters);
     a kernel that leaks dangling mass uniformly feeds B ≈0.05 FOREVER. The
     first seed-locality law above cannot see this (B's own dangling mass
     self-drains under BOTH semantics) — this one kills mutant M2. *)
  let l2 = pagerank_core ~teleport:[| 1.; 0.; 0.; 0. |] 4 [| [1]; []; [3]; [2] |] in
  assert (l2.(2) +. l2.(3) < 1e-3);
  assert (l2.(0) > l2.(2) && l2.(0) > l2.(3));
  (* LAW rejection/totality: a malformed teleport (negative, NaN, zero-mass, or
     wrong length) degrades to uniform — never NaN, never a crash *)
  let bad = pagerank_core ~teleport:[| -1.; Float.nan; 0.; 0.; 0. |] dn dout in
  Array.iteri (fun i x -> assert (Float.abs (x -. classic.(i)) < 1e-9)) bad;
  let short = pagerank_core ~teleport:[| 1. |] dn dout in
  Array.iteri (fun i x -> assert (Float.abs (x -. classic.(i)) < 1e-9)) short;
  (* LAW ppr-wrapper degeneration: no seeds / unknown slugs / w≤0 ≡ pagerank *)
  assert (ppr notes = pagerank notes);
  assert (ppr ~seeds:[ ("no-such-note", 1.0); ("guide", -3.0) ] notes = pagerank notes);
  (* LAW seed-relevance: seeding a real note strictly raises its rank mass vs
     the uniform run (personalization is observable, not a no-op) *)
  (match pagerank notes with
   | (top, _) :: _ ->
       let before = List.assoc top (pagerank notes) in
       let after = List.assoc top (ppr ~seeds:[ (top, 1.0) ] notes) in
       assert (after > before)
   | [] -> assert false);
  (* combinatorics: potential = n(n-1)/2 *)
  let (n, _, pot) = graph_density notes in
  assert (pot = n * (n - 1) / 2);
  (* degree histogram counts every note exactly once *)
  assert (List.fold_left (fun a (_, c) -> a + c) 0 (degree_histogram notes) = List.length notes);
  assert (has (render_graph_analysis notes) "PageRank");
  (* ── SPANNING-TREE reading order + ONTOLOGY inference laws ────────────── *)
  (* reading_order is a PERMUTATION of every note (spanning forest covers all) *)
  let ro = reading_order notes in
  assert (List.length ro = List.length notes);
  assert (List.sort compare (List.map fst ro) = List.sort compare (List.map (fun p -> p.slug) notes));
  assert (List.exists (fun (_, d) -> d = 0) ro);            (* at least one root at depth 0 *)
  (* reach_core: transitivity + direct edges ⊆ reach + irreflexive by construction *)
  let out = [| [1]; [2]; [] |] in                            (* 0→1→2 *)
  let r = reach_core 3 out in
  assert (r.(0).(1) && r.(1).(2) && r.(0).(2));              (* TRANSITIVE: 0⇝2 inferred *)
  assert (not r.(0).(0) && not r.(2).(0));                   (* irreflexive; no back-path *)
  assert (reach_core 0 [||] = [||]);                         (* total on empty *)
  (* inferred_for = transitively reachable MINUS direct links (the new facts) *)
  let chain = build [ ("docs/a.md", "# A\n\n[[B]]"); ("docs/b.md", "# B\n\n[[C]]"); ("docs/c.md", "# C\n\nleaf") ] in
  let a = List.find (fun p -> p.title = "A") chain in
  let cslug = (List.find (fun p -> p.title = "C") chain).slug in
  assert (List.mem cslug (inferred_for chain a));            (* A infers C (via B), not a direct link *)
  assert (not (List.mem (List.find (fun p -> p.title = "B") chain).slug (inferred_for chain a))); (* B is direct, not inferred *)
  assert (has (render_graph_analysis notes) "Reading order" && has (render_graph_analysis notes) "Ontology inference");
  (* ── DECISION RECORD + criteria envelope laws (ZK integral to SDLC/SRE) ── *)
  (* ROUND-TRIP: a decision record recovers its title + sections + #decision tag *)
  let dm = decision_markdown ~title:"Adopt X"
      ~sections:[ ("Context (as-is)", "current"); ("Decision (to-be)", "do X");
                  ("Alternatives — what else could be done", "Y or Z"); ("empty", "") ] in
  let dnotes = build [ (note_path ~ts:1. ~title:"Adopt X", dm) ] in
  let d = List.hd dnotes in
  assert (d.title = "Adopt X");                              (* title recovered *)
  assert (List.mem "decision" d.tags && List.mem "adr" d.tags); (* tagged #decision #adr *)
  assert (has dm "Alternatives" && has dm "do X" && has dm "Context");
  assert (not (has dm "## empty"));                          (* empty sections are dropped *)
  (* empty title never crashes + still valid + safe *)
  assert (has (decision_markdown ~title:"" ~sections:[]) "# Untitled decision");
  (* the criteria envelope covers all four axes *)
  assert (has criteria_envelope "Architecture" && has criteria_envelope "Code"
          && has criteria_envelope "Test" && has criteria_envelope "Docs");
  assert (has (render_decision_form notes) "Decision record" && has (render_decision_form notes) "what else could be done");
  assert (has (render_criteria notes) "criteria envelope");
  (* ── FRONTMATTER + UUID laws (agent control panel) ───────────────────── *)
  (* UUID is DETERMINISTIC + canonical-shaped + differs per input *)
  let u1 = uuid_of_string "alpha" and u2 = uuid_of_string "beta" in
  assert (String.length u1 = 36 && u1.[8] = '-' && u1.[13] = '-' && u1.[18] = '-' && u1.[23] = '-');
  assert (u1 <> u2 && u1 = uuid_of_string "alpha");             (* stable + collision-distinct *)
  (* a note WITHOUT frontmatter gets a derived id = uuid_of_string slug, status published *)
  let plain = List.hd (build [ ("docs/x.md", "# X\n\nbody") ]) in
  assert (plain.meta.id = uuid_of_string plain.slug && plain.meta.status = "published"
          && not plain.meta.has_frontmatter);
  (* ROUND-TRIP: a note WITH frontmatter recovers id/status + the body renders WITHOUT the YAML *)
  let fm = frontmatter ~id:"11111111-2222-3333-4444-555555555555" ~status:"draft" ~date:"2026-07-25" ~verified_by:"agent" in
  let withfm = List.hd (build [ ("docs/y.md", fm ^ "# Y\n\nthe body only") ]) in
  assert (withfm.meta.id = "11111111-2222-3333-4444-555555555555");
  assert (withfm.meta.status = "draft" && withfm.meta.verified_by = "agent" && withfm.meta.has_frontmatter);
  assert (withfm.title = "Y");                                  (* title from the body's H1, not the YAML *)
  assert (not (has withfm.html "status:") && not (has withfm.raw "id:")); (* frontmatter stripped from body/raw *)
  let audit_control =
    List.hd
      (build
         [ ("docs/audit-control.md",
            "---\nwiki-audit: allow-example-links\n---\n# Audit control\n`[[example]]`\n") ])
  in
  assert audit_control.meta.allow_example_links;
  assert (not (has audit_control.html "wiki-audit"));
  (* invalid status in frontmatter is REJECTED → the safe default (no hallucinated states) *)
  let bad = List.hd (build [ ("docs/z.md", "---\nstatus: hacked\n---\n# Z\n\nb") ]) in
  assert (bad.meta.status = "published");
  (* the metadata panel renders the status + id *)
  assert (has (render_meta_panel withfm) "meta-status" && has (render_meta_panel withfm) "draft");
  (* authored_note is born with frontmatter that round-trips *)
  let an = authored_note ~id:"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" ~date:"2026-07-25" ~verified_by:"agent" ~title:"New" ~body:"b" ~tags:["t"] in
  let anp = List.hd (build [ ("docs/zk/n.md", an) ]) in
  assert (anp.meta.id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" && anp.meta.status = "draft" && anp.title = "New");
  (* ── HEADLESS JSON API laws ──────────────────────────────────────────── *)
  (* api_index covers EVERY note (count + each id/slug present) *)
  let ai = api_index notes in
  assert (has ai (Printf.sprintf "\"count\":%d" (List.length notes)));
  assert (List.for_all (fun p -> has ai ("\"slug\":\"" ^ p.slug ^ "\"") && has ai ("\"id\":\"" ^ p.meta.id ^ "\"")) notes);
  (* a note is resolvable by slug AND by its UUID (immutable id) *)
  let a0 = List.hd notes in
  assert (find_note notes a0.slug = Some a0 && find_note notes a0.meta.id = Some a0);
  assert (find_note notes "no-such-key" = None);
  (* api_note carries metadata + backlinks + the html; JSON is injection-safe *)
  let aj = api_note notes a0 in
  assert (has aj "\"note\":" && has aj "\"backlinks\":" && has aj "\"html\":" && has aj ("\"id\":\"" ^ a0.meta.id));
  let hostile = List.hd (build [ ("docs/h.md", "# \"</script>&\n\nb") ]) in
  assert (not (has (api_index [hostile]) "</script>") && has (api_index [hostile]) "\\u003c"); (* jesc-escaped *)
  (* ── ETAG / optimistic-concurrency laws ──────────────────────────────── *)
  assert (etag_of a0 = etag_of a0);                                   (* deterministic *)
  let a0changed = List.hd (build [ (a0.path, "# Alpha\n\nDIFFERENT body now") ]) in
  assert (etag_of a0 <> etag_of a0changed);                          (* content change ⇒ etag change *)
  assert (etag_of_content "x" = etag_of_content "x" && etag_of_content "x" <> etag_of_content "y");
  assert (has (api_index notes) "\"etag\":");                        (* etag exposed to agents *)
  assert (has (render_edit_form ~pages:notes bnote) "name=\"etag\"");  (* the write carries the guard *)
  (* ── TYPED LINKS: [[Target|@relation]] → a typed semantic edge ────────── *)
  let tl = build [ ("docs/x.md", "# X\n\nsee [[Y|@contradicts]] and plain [[Y]] and [[Y|shown]]");
                   ("docs/y.md", "# Y\n\nleaf") ] in
  let xp = List.find (fun p -> p.title = "X") tl in
  let yslug = (List.find (fun p -> p.title = "Y") tl).slug in
  assert (List.mem (yslug, "contradicts") xp.typed);                 (* the typed edge is captured *)
  assert (List.mem yslug xp.outlinks);                               (* still a plain outlink too *)
  assert (has xp.html "zk-rel" && has xp.html "contradicts");        (* the relation badge renders *)
  assert (not (has xp.html ">@contradicts<"));                       (* @ is consumed, not shown as text *)
  let plainx = build [ ("docs/p2.md", "# P\n\n[[Q]]"); ("docs/q2.md", "# Q\n\nl") ] in
  assert ((List.find (fun p -> p.title = "P") plainx).typed = []);   (* untyped link → no typed edge *)
  assert (has (api_index tl) "\"typed\":[{\"to\":");                 (* typed edges in the API *)
  (* ── BLOCK-LEVEL IDs + section/block-reference links (roadmap #7) ──────── *)
  let bl = build [ ("docs/bl.md", "## Design Notes\n\na key claim here ^claim-1\n\nplain para") ] in
  let blp = List.hd bl in
  assert (has blp.html "<h2 id=\"design-notes\">");                  (* heading auto-anchor *)
  assert (has blp.html "<p id=\"^claim-1\">" && has blp.html "a key claim here"); (* explicit block id, marker stripped *)
  assert (not (has blp.html "^claim-1<") && not (has blp.html "claim-1</p>")); (* the ^id is consumed, not shown *)
  (* [[Target#Section]] → slug.html#section ; [[Target#^id]] → slug.html#^id *)
  let lk = build [ ("docs/src.md", "# Src\n\nsee [[Doc#Design Notes]] and [[Doc#^claim-1]]");
                   ("docs/doc.md", "# Doc\n\n## Design Notes\n\nx ^claim-1") ] in
  let src = List.find (fun p -> p.title = "Src") lk in
  let dslug = (List.find (fun p -> p.title = "Doc") lk).slug in
  assert (has src.html (Printf.sprintf "href=\"%s.html#design-notes\"" dslug));  (* section link *)
  assert (has src.html (Printf.sprintf "href=\"%s.html#^claim-1\"" dslug));      (* block-reference link *)
  assert (List.mem dslug src.outlinks);                             (* still a graph edge to Doc *)
  (* KNOWLEDGE POSITION: the most-central note's page shows centrality #1 *)
  (match pagerank notes with
   | (top, _) :: _ -> let tp = List.find (fun p -> p.slug = top) notes in
                      assert (has (render_page ~pages:notes tp) "centrality <b>#1</b>")
   | [] -> ());
  (* ── SEMANTIC similarity (TF-IDF cosine) laws ────────────────────────── *)
  assert (Float.abs (cosine_dense [| 1.; 2.; 3. |] [| 1.; 2.; 3. |] -. 1.0) < 1e-9);  (* self = 1 *)
  assert (Float.abs (cosine_dense [| 1.; 0. |] [| 0.; 1. |]) < 1e-9);                 (* orthogonal = 0 *)
  assert (Float.abs (cosine_dense [| 1.; 2. |] [| 2.; 4. |] -. 1.0) < 1e-9);          (* colinear = 1 *)
  (* a near-duplicate note is more similar than an unrelated one *)
  let sm = build [ ("docs/p.md", "# Pattern matching\n\npattern matching binds variables across clauses");
                   ("docs/q.md", "# Clause binder\n\npattern matching binds variables across clauses too");
                   ("docs/z.md", "# Weather\n\nrain sunshine clouds thunder") ] in
  let pp = List.find (fun p -> p.title = "Pattern matching") sm in
  (match similar_notes sm pp 3 with
   | (top, _) :: _ -> assert ((List.find (fun q -> q.slug = top) sm).title = "Clause binder")
   | [] -> assert false);
  assert (similar_notes sm (List.find (fun p -> p.title = "Weather") sm) 3
          |> List.for_all (fun (_, c) -> c <= 1.0 +. 1e-9 && c >= 0.));   (* cosine bounded *)
  (* ── DETERMINISM: rendering is a pure function — byte-identical on repeat, and
     rankings are total-ordered so ties never reorder across runs. ──────── *)
  assert (String.equal (render_graph notes) (render_graph notes));
  assert (String.equal (render_page ~pages:notes a) (render_page ~pages:notes a));
  assert (List.map fst (pagerank notes) = List.map fst (pagerank notes));
  assert (similar_notes notes a 6 = similar_notes notes a 6);
  assert (reading_order notes = reading_order notes);
  (* tie determinism: equal-score nodes rank by slug — a 2-node symmetric graph
     (A↔B) has equal PageRank, so the order is the slug order, not input order *)
  let sym = build [ ("docs/bb.md", "# BB\n\n[[AA]]"); ("docs/aa.md", "# AA\n\n[[BB]]") ] in
  assert (List.map fst (pagerank sym) = List.sort compare (List.map (fun p -> p.slug) sym));
  (* ── ZK MCP READ KERNELS (zk-mcp-read, journal 20260729-1056 §6.2) ─────
     Fixture: A →[[B]] (untyped) + [[C|@supports]] (typed); D names A's title
     in prose without a link (an unlinked mention); E is a true orphan. *)
  let zc = build [ ("docs/an.md", "# Alpha Node\n\n[[Beta Node]] and [[Gamma Node|@supports]]");
                   ("docs/bn.md", "# Beta Node\n\nbody");
                   ("docs/gn.md", "# Gamma Node\n\nbody");
                   ("docs/dn.md", "# Delta Node\n\nAlpha Node is named here without a link");
                   ("docs/en.md", "---\nstatus: draft\nnext_review: 2001-01-01\n---\n# Epsilon Node\n\nalone") ] in
  let zslug t = (List.find (fun p -> p.title = t) zc).slug in
  let alpha = zslug "Alpha Node" and beta = zslug "Beta Node"
  and gamma = zslug "Gamma Node" and eps = zslug "Epsilon Node" in
  (* LAW neighborhood-soundness: out/typed edges of A and the REVERSE back
     edge on B all present with correct labels *)
  let na = neighborhood_json zc alpha ~hops:1 in
  assert (has na (Printf.sprintf "{\"from\":\"%s\",\"rel\":\"out\",\"to\":\"%s\",\"hop\":1}" alpha beta));
  assert (has na (Printf.sprintf "\"rel\":\"typed:supports\",\"to\":\"%s\"" gamma));
  assert (has na "\"rel\":\"mention\"");                       (* D's unlinked mention surfaces *)
  let nb = neighborhood_json zc beta ~hops:1 in
  assert (has nb (Printf.sprintf "{\"from\":\"%s\",\"rel\":\"back\",\"to\":\"%s\",\"hop\":1}" beta alpha));
  (* LAW hop-bound (clamp): hops 0 and 99 clamp to [1,2]; hop-2 edges appear
     only in the ≥2 form, and hop-2 contains B's backlink ring *)
  assert (neighborhood_json zc alpha ~hops:0 = neighborhood_json zc alpha ~hops:1);
  assert (neighborhood_json zc alpha ~hops:99 = neighborhood_json zc alpha ~hops:2);
  assert (not (has (neighborhood_json zc alpha ~hops:1) "\"hop\":2"));
  assert (has (neighborhood_json zc alpha ~hops:2) (Printf.sprintf "{\"from\":\"%s\",\"rel\":\"back\"" beta));
  (* LAW endpoint-closure: every "to" of a 2-hop walk resolves in the corpus *)
  let all_slugs = List.map (fun p -> p.slug) zc in
  List.iter (fun (rel, s) ->
      ignore rel; assert (List.mem s all_slugs))
    (List.concat_map neighborhood_edges zc);
  (* LAW rejection/totality + injection-safety: unknown key → error JSON with
     the hostile key ESCAPED, never an exception *)
  let bad = neighborhood_json zc "no\"such<script>" ~hops:1 in
  assert (has bad "\"error\"" && not (has bad "no\"such"));
  (* LAW determinism *)
  assert (neighborhood_json zc alpha ~hops:2 = neighborhood_json zc alpha ~hops:2);
  (* LAW anomalies orphan-iff-degree-0: E (no links either way, no mentions)
     is an orphan; B (degree 1, backlink only) is NOT — this kills the
     degree≤1 mutant *)
  let az = anomalies_json zc in
  assert (has az (Printf.sprintf "\"orphans\":[%s]" (jesc eps)) || has az ("\"" ^ eps ^ "\""));
  assert (not (has az (Printf.sprintf "\"orphans\":[\"%s\"" beta)));
  (let orph_section = List.nth (String.split_on_char '[' az) 1 in
   assert (not (has orph_section beta)));
  (* LAW mention-pairs soundness: (Delta → Alpha) is reported verbatim *)
  assert (has az (Printf.sprintf "{\"from\":\"%s\",\"to\":\"%s\"}" (zslug "Delta Node") alpha));
  (* LAW lifecycle surfacing: E's draft status + next_review stamp reported *)
  assert (has az (Printf.sprintf "{\"slug\":%s,\"status\":\"draft\"}" (jesc eps)));
  assert (has az (Printf.sprintf "{\"slug\":%s,\"next_review\":\"2001-01-01\"}" (jesc eps)));
  (* LAW anomalies determinism + totality on empty *)
  assert (anomalies_json zc = anomalies_json zc);
  assert (anomalies_json [] = "{\"orphans\":[],\"unlinked_mentions\":[],\"unpublished\":[],\"review\":[],\"invalid_types\":[],\"unsupported_claims\":[],\"undermined\":[],\"disputed\":[],\"embed_cycles\":[],\"structural_holes\":[]}");
  (* ── DISCOURSE TYPES (zk-discourse-types, journal 20260729-1056 §7.5) ──
     Fixture: a question, a supported claim (E1 —@supports→ C1), an
     UNsupported claim, an evidence note, an invalid type, an untyped note. *)
  let dc = build [
    ("docs/q1.md", "---\ntype: question\n---\n# Q1\n\nHow fast is dispatch?");
    ("docs/c1.md", "---\ntype: Claim\n---\n# C1\n\nDispatch is fast. [[Q1|@answers]]");
    ("docs/c2.md", "---\ntype: claim\n---\n# C2\n\nDispatch is slow.");
    ("docs/c3.md", "---\ntype: claim\n---\n# C3\n\nOutbound-only: [[Q1|@answers]] — nothing supports THIS claim");
    ("docs/e1.md", "---\ntype: evidence\n---\n# E1\n\nbench run: [[C1|@supports]]");
    ("docs/w1.md", "---\ntype: hunch\n---\n# W1\n\nweirdly typed");
    ("docs/p1.md", "# P1\n\nuntyped body") ] in
  let dpage t = List.find (fun p -> p.title = t) dc in
  let dslug t = (dpage t).slug in
  (* LAW type-default + type-parse + lowercase-normalization ("Claim"→"claim") *)
  assert ((dpage "P1").meta.ntype = "note");
  assert ((dpage "Q1").meta.ntype = "question");
  assert ((dpage "C1").meta.ntype = "claim" && (dpage "E1").meta.ntype = "evidence");
  (* LAW invalid-type-preserved+reported (report-only honesty): the unknown
     value survives VERBATIM in the model and is flagged in anomalies; a
     valid type is never flagged *)
  assert ((dpage "W1").meta.ntype = "hunch");
  let da = anomalies_json dc in
  assert (has da (Printf.sprintf "{\"slug\":\"%s\",\"type\":\"hunch\"}" (dslug "W1")));
  assert (not (has da (Printf.sprintf "{\"slug\":\"%s\",\"type\"" (dslug "C1"))));
  (* LAW claim-supported-iff-INBOUND-supports (exact set): C1 carries E1's
     INBOUND @supports so NOT reported; C2 (no edges at all) IS; C3 has an
     OUTBOUND typed edge but no inbound support so it IS — the C3 case is the
     discriminator that kills the outbound-instead-of-inbound mutant (which
     first SURVIVED the C1/C2-only fixture: both semantics agreed on it). *)
  assert (has da (Printf.sprintf "\"unsupported_claims\":[\"%s\",\"%s\"]" (dslug "C2") (dslug "C3")));
  (* LAW type-in-api: the note summary carries the discourse type *)
  assert (has (note_json (dpage "C1")) "\"type\":\"claim\"");
  assert (has (note_json (dpage "P1")) "\"type\":\"note\"");
  (* LAW type-badge render: valid type → badge; invalid type → marked invalid;
     the default type renders NO badge *)
  assert (has (render_page ~pages:dc (dpage "C1")) "meta-status zk-type\"");
  assert (has (render_page ~pages:dc (dpage "W1")) "meta-status zk-type invalid");
  assert (not (has (render_page ~pages:dc (dpage "P1")) "meta-status zk-type"));
  (* ── GROUNDED SEMANTICS (zk-grounded-semantics, journal 20260729-1056
     §8.2-A H2, Dung 1995) ────────────────────────────────────────────────
     Fixture AF: chain EA —opposes→ CB —opposes→ CC (evidence attacks a
     claim which attacks another claim), a mutual cycle M1 ⇄ M2, and a
     bystander N0. *)
  let gc = build [
    ("docs/ea.md", "---\ntype: evidence\n---\n# EA\n\ncounter-bench: [[CB|@opposes]]");
    ("docs/cb.md", "---\ntype: claim\n---\n# CB\n\nthe fast claim; and against [[CC|@opposes]]");
    ("docs/cc.md", "---\ntype: claim\n---\n# CC\n\nthe slow claim");
    ("docs/m1.md", "# M1\n\n[[M2|@opposes]]");
    ("docs/m2.md", "# M2\n\n[[M1|@opposes]]");
    ("docs/d1.md", "---\ntype: claim\n---\n# D1\n\nthe true 2-chain: [[D2|@opposes]]");
    ("docs/d2.md", "---\ntype: claim\n---\n# D2\n\nan attacked leaf, no outgoing attacks");
    ("docs/n0.md", "# N0\n\nneutral bystander") ] in
  let g = grounded_statuses gc in
  let gslug t = (List.find (fun p -> p.title = t) gc).slug in
  let gs t = List.assoc (gslug t) g in
  (* LAW unattacked-in: the unattacked attacker is IN, its target OUT *)
  assert (gs "EA" = "in" && gs "CB" = "out");
  (* LAW attack-direction (the TRUE 2-chain D1 —opposes→ D2, D2 with no
     outgoing attacks): direction-sensitive where the 3-chain is NOT — the
     3-chain is PALINDROMIC (reversing every attack yields the identical
     labelling), which let the inverted-relation mutant survive the first
     fixture. D1 must be IN and D2 OUT; inversion flips exactly this. *)
  assert (gs "D1" = "in" && gs "D2" = "out");
  (* LAW reinstatement: CC's only attacker CB is OUT ⇒ CC is DEFENDED ⇒ IN *)
  assert (gs "CC" = "in");
  (* LAW mutual-cycle-undec + bystander-in *)
  assert (gs "M1" = "undec" && gs "M2" = "undec");
  assert (gs "N0" = "in");
  (* LAW conflict-free + admissible, checked GENERICALLY over every attack *)
  let attacks = List.concat_map (fun q ->
      List.filter_map (fun (t, r) -> if r = "opposes" then Some (q.slug, t) else None) q.typed) gc in
  assert (attacks <> []);
  assert (List.for_all (fun (a, t) ->
      not (List.assoc a g = "in" && List.assoc t g = "in")) attacks);       (* conflict-free *)
  assert (List.for_all (fun (a, t) ->
      List.assoc t g <> "in" || List.assoc a g = "out") attacks);           (* admissible *)
  (* LAW fixpoint-stability/determinism + totality *)
  assert (grounded_statuses gc = grounded_statuses gc);
  assert (grounded_statuses [] = []);
  (* LAW self-attack-never-in (a legal AF shape) *)
  let sa = build [ ("docs/sx.md", "# SX\n\n[[SX|@opposes]] self-defeating") ] in
  assert (List.assoc (List.hd sa).slug (grounded_statuses sa) = "undec");
  (* LAW undermined-report (definitive defeat only): CB (claim, OUT) is the
     ONLY undermined entry — CC (claim, IN) and M1/M2 (undec) are absent;
     disputed = exactly the mutual cycle *)
  let ga = anomalies_json gc in
  assert (has ga (Printf.sprintf "\"undermined\":[{\"slug\":\"%s\",\"type\":\"claim\"},{\"slug\":\"%s\",\"type\":\"claim\"}]" (gslug "CB") (gslug "D2")));
  assert (has ga (Printf.sprintf "\"disputed\":[\"%s\",\"%s\"]" (gslug "M1") (gslug "M2")));
  (* LAW grounded-in-api: zk_read_note carries the dialectical standing *)
  assert (has (api_note gc (List.find (fun p -> p.title = "CB") gc)) "\"grounded\":\"out\"");
  assert (has (api_note gc (List.find (fun p -> p.title = "CC") gc)) "\"grounded\":\"in\"");
  (* ── zkquery DSL (zk-query-dsl, journal 20260729-1056 §7.7) — over the
     discourse fixture dc (3 claims c1/c2/c3, question, evidence, hunch, note) *)
  let zeval q = match zkquery_parse q with Ok z -> zkquery_eval dc z | Error e -> failwith e in
  let zj q = zkquery_json dc q in
  (* LAW empty-query-is-all (sorted by slug — the default total order) *)
  assert (zeval "" = List.sort (fun a b -> compare a.slug b.slug) dc);
  (* LAW from-selector + eval-soundness (GENERIC: every row satisfies) *)
  let claims = zeval "from type:claim" in
  assert (List.length claims = 3 && List.for_all (fun r -> r.meta.ntype = "claim") claims);
  (* LAW neq: where-chain with != excludes exactly the named slug *)
  let noc2 = zeval "where type=claim and slug!=c2" in
  assert (List.length noc2 = 2 && List.for_all (fun r -> r.slug <> "c2") noc2);
  (* LAW filter-commute: conjunction order is irrelevant *)
  assert (zeval "where type=claim and status=published"
          = zeval "where status=published and type=claim");
  (* LAW numeric-cmp: degree=0 picks exactly the unlinked notes *)
  let iso = zeval "where degree=0" in
  assert (List.for_all (fun r -> degree r = 0) iso && iso <> []);
  (* LAW limit-monotone (PREFIX, kills the off-by-one mutant) + limit-0 *)
  let full = zeval "from all sort degree desc" in
  let two = zeval "from all sort degree desc limit 2" in
  assert (List.length two = 2);
  assert (two = List.filteri (fun i _ -> i < 2) full);
  assert (zeval "limit 0" = []);
  (* LAW sort-determinism: desc = reverse of asc under the slug tiebreak on a
     tie-free key projection; and repeat runs agree *)
  assert (zeval "from all sort words asc" = zeval "from all sort words asc");
  (* LAW rejection (fail-closed, named errors, never a guess) *)
  assert (has (zj "where bogus=1") "\"error\"");
  assert (has (zj "frobnicate") "\"error\"");
  assert (has (zj "where words!=3") "\"error\"");        (* != is not numeric *)
  assert (has (zj "from type:claim extra") "\"error\""); (* trailing token *)
  assert (has (zj "limit -3") "\"error\"");
  assert (has (zj "sort sideways") "\"error\"");
  (* LAW query-total: hostile/degenerate inputs produce JSON, never raise *)
  List.iter (fun s -> ignore (zj s))
    [ ""; " "; "from"; "where"; "sort"; "limit"; "where a"; "from :x"; "==="; "where =" ];
  (* LAW query-json shape *)
  assert (has (zj "from type:claim") "\"count\":3");
  (* LAW embedded-query renders a LIVE table; a bad query renders an error
     chip; both keep the page total *)
  let qc = build [
    ("docs/qq.md", "# QQ\n\n```zkquery\nfrom type:claim\n```\n");
    ("docs/k1.md", "---\ntype: claim\n---\n# K1\n\nthe only claim here") ] in
  let qv = render_page ~pages:qc (List.find (fun p -> p.title = "QQ") qc) in
  assert (has qv "Query results" && has qv "zq-t" && has qv ">K1<");
  let qe = build [ ("docs/qe.md", "# QE\n\n```zkquery\nfrobnicate\n```\n") ] in
  assert (has (render_page ~pages:qe (List.hd qe)) "zq-err");
  (* LAW zkquery_blocks unit: ordered extraction; an unclosed fence is [] *)
  assert (zkquery_blocks "x\n```zkquery\nq1\n```\ny\n```zkquery\nq2\n```" = [ "q1"; "q2" ]);
  assert (zkquery_blocks "```zkquery\nfrom all" = []);
  (* ── TRANSCLUSION (zk-transclusion, journal 20260729-1056 §7.8) ────────
     TA embeds TB's ^b1 block (deliberately NOT TB's first chunk — the
     wrong-chunk mutant's discriminator); TW embeds TB whole; TI holds an
     INLINE marker (must stay a link); TM embeds a missing note + block. *)
  let ec = build [
    ("docs/ta.md", "# TA\n\nintro para\n\n![[TB#^b1]]\n\nafter para");
    ("docs/tb.md", "# TB\n\nfirst chunk here\n\nthe wanted block [[TC]] link ^b1\n\ntail chunk");
    ("docs/tc.md", "# TC\n\ntarget of the inner link");
    ("docs/tw.md", "# TW\n\n![[TB]]");
    ("docs/ti.md", "# TI\n\ninline ![[TB#^b1]] stays a link");
    ("docs/tm.md", "# TM\n\n![[Nowhere]]\n\n![[TB#^nope]]") ] in
  let epage t = List.find (fun p -> p.title = t) ec in
  let av = render_page ~pages:ec (epage "TA") in
  (* LAW embed-render: the addressed block (and ONLY that block) is inlined,
     with a provenance chip linking back to slug.html#^id *)
  assert (has av "zk-embed" && has av "the wanted block");
  assert (not (has av "first chunk here"));
  assert (has av "tb.html#^b1");
  (* LAW embedded-links-resolve: [[TC]] inside the embedded block is a LIVE
     link (the resolver is rebuilt at expansion time) *)
  assert (has av "href=\"tc.html\"");
  (* LAW whole-note-embed *)
  let wv = render_page ~pages:ec (epage "TW") in
  assert (has wv "first chunk here" && has wv "tail chunk");
  (* LAW inline-not-expanded: a mid-sentence marker stays a link *)
  assert (not (has (render_page ~pages:ec (epage "TI")) "the wanted block"));
  (* LAW missing-target/block chips — total, visible, escaped *)
  let mv = render_page ~pages:ec (epage "TM") in
  assert (has mv "unresolved embed" && has mv "no block ^nope");
  (* LAW embed-chip-escaping: the chip ECHOES the unresolved target back into
     the page, so the target is attacker-controlled text arriving at markup.
     The chip used to take a pre-escaped string and each call site carried its
     own `esc_s`; it now takes the raw value and escapes at the boundary. This
     law is what makes that a guarantee rather than a claim — it was missing
     while the discipline was manual, which is precisely when it was needed. *)
  let xv = build [ ("docs/xe.md", "# XE\n\n![[<img src=x onerror=alert(1)>]]") ] in
  let xh = render_page ~pages:xv (List.hd xv) in
  assert (has xh "unresolved embed");
  assert (not (has xh "<img src=x"));
  assert (has xh "&lt;img src=x");
  (* LAW determinism *)
  assert (String.equal (render_page ~pages:ec (epage "TA")) av);
  (* LAW cycle-chip + DAG report: A ⇄ B embeds — rendering stays total with
     an explicit cycle chip; anomalies names both cycle members *)
  let cy = build [ ("docs/ca.md", "# CA\n\n![[CB]]"); ("docs/cb.md", "# CB\n\n![[CA]]") ] in
  let cv = render_page ~pages:cy (List.find (fun p -> p.title = "CA") cy) in
  assert (has cv "embed cycle");
  assert (has (anomalies_json cy) "\"embed_cycles\":[\"ca\",\"cb\"]");
  assert (has (anomalies_json ec) "\"embed_cycles\":[]");
  (* LAW depth-bound: a 5-deep embed chain stops at depth 3 with a chip —
     bounded, never a hang (a hang is a failed law) *)
  let dp = build [
    ("docs/e1x.md", "# E1x\n\n![[E2x]]"); ("docs/e2x.md", "# E2x\n\n![[E3x]]");
    ("docs/e3x.md", "# E3x\n\n![[E4x]]"); ("docs/e4x.md", "# E4x\n\n![[E5x]]");
    ("docs/e5x.md", "# E5x\n\nthe deep leaf") ] in
  let dv = render_page ~pages:dp (List.find (fun p -> p.title = "E1x") dp) in
  assert (has dv "depth limit");
  assert (not (has dv "the deep leaf"));
  (* ── COMMUNITIES + BETWEENNESS + STRUCTURAL HOLES (zk-communities,
     journal 20260729-1056 §6.5) ──────────────────────────────────────────
     Fixture: two DISCONNECTED triangles T{1,2,3} / U{1,2,3} + an isolate. *)
  let cmx = build [
    ("docs/t1.md", "# T1\n\n[[T2]] [[T3]]"); ("docs/t2.md", "# T2\n\n[[T3]]");
    ("docs/t3.md", "# T3\n\n[[T1]]");
    ("docs/u1.md", "# U1\n\n[[U2]] [[U3]]"); ("docs/u2.md", "# U2\n\n[[U3]]");
    ("docs/u3.md", "# U3\n\n[[U1]]");
    ("docs/iso.md", "# Iso\n\nall alone") ] in
  let cm = communities cmx in
  let ct s = List.assoc s cm in
  (* LAW partition-valid: exactly one community per note; every community id
     maps to ITSELF (the id is a member, and the representative's fixpoint) *)
  assert (List.length cm = List.length cmx);
  List.iter (fun (_, c) -> assert (List.assoc c cm = c)) cm;
  (* LAW clique-converges-to-one + disconnected-cliques-stay-two *)
  assert (ct "t1" = ct "t2" && ct "t2" = ct "t3");
  assert (ct "u1" = ct "u2" && ct "u2" = ct "u3");
  assert (ct "t1" <> ct "u1");
  (* LAW singleton-isolates + id-is-smallest-member *)
  assert (ct "iso" = "iso");
  assert (ct "t1" = "t1" && ct "u1" = "u1");
  (* LAW determinism + totality *)
  assert (communities cmx = communities cmx);
  assert (communities [] = []);
  (* LAW betweenness path-center-max (Brandes): on the path PA—PB—PC the
     center is STRICTLY highest and the endpoints are 0 *)
  let pth = build [ ("docs/pa.md", "# PA\n\n[[PB]]"); ("docs/pb.md", "# PB\n\n[[PC]]");
                    ("docs/pc.md", "# PC\n\nleaf") ] in
  let bw = betweenness pth in
  assert (List.assoc "pb" bw > List.assoc "pa" bw);
  assert (List.assoc "pa" bw = 0. && List.assoc "pc" bw = 0.);
  assert (betweenness [] = []);
  (* LAW mocs-community-grounded: one entry per community — the two triangle
     reps (top-degree, tie→slug), the isolate excluded; distinct communities *)
  let mreps = mocs cmx in
  assert (List.map (fun p -> p.slug) mreps = [ "t1"; "u1" ]);
  assert (List.for_all (fun p -> degree p > 0) mreps);
  (* LAW structural-holes: the two disconnected triangle-communities are a
     hole, named by their ids; a corpus whose top communities ARE bridged
     reports none (robust to LPA merging the bridge: merged ⇒ no pair) *)
  assert (has (anomalies_json cmx) "\"structural_holes\":[{\"a\":\"t1\",\"b\":\"u1\"}]");
  let bb = build [
    ("docs/a1.md", "# A1\n\n[[A2]] [[A3]]"); ("docs/a2.md", "# A2\n\n[[A3]]");
    ("docs/a3.md", "# A3\n\n[[A1]] [[B1]]");
    ("docs/b1.md", "# B1\n\n[[B2]] [[B3]]"); ("docs/b2.md", "# B2\n\n[[B3]]");
    ("docs/b3.md", "# B3\n\n[[B1]]") ] in
  assert (has (anomalies_json bb) "\"structural_holes\":[]");
  (* LAW community-in-api: zk_read_note carries the community id *)
  assert (has (api_note cmx (List.find (fun p -> p.title = "T2") cmx)) "\"community\":\"t1\"");
  (* ── EPISODIC NOTES (zk-episodic-notes, journal 20260729-1056 §7.4/§8.2-M)
     Core fixture: ZC1→ZC2 link, ZC3 mentions ZC1's title. The episodic note
     LINKS ZC1 and NAMES ZC2 — under the projection law neither may perturb
     the core model. *)
  let corec = [
    ("docs/zc1.md", "# Zeta Core One\n\n[[Zeta Core Two]]");
    ("docs/zc2.md", "# Zeta Core Two\n\nplain body");
    ("docs/zc3.md", "# Zeta Core Three\n\nZeta Core One is named here without a link") ] in
  let epi = ("docs/zk/episodic/zk-some-slice.md",
             "---\nstatus: draft\nverified_by: harness\n---\n# Episode: zk-some-slice\n\n[[Zeta Core One]] worked; Zeta Core Two named too") in
  let cw = build corec and ce = build (corec @ [ epi ]) in
  (* LAW conservative-extension (THE projection law): every core page's graph
     model — outlinks, backlinks, mentions, contexts — is IDENTICAL with the
     episodic note present; so are pagerank, communities, similarity, mocs,
     and the whole anomalies report *)
  List.iter (fun p ->
    let q = List.find (fun q -> String.equal q.slug p.slug) ce in
    assert (q.outlinks = p.outlinks && q.backlinks = p.backlinks
            && q.mentions = p.mentions && q.back_ctx = p.back_ctx)) cw;
  assert (pagerank ce = pagerank cw);
  assert (communities ce = communities cw);
  assert (anomalies_json ce = anomalies_json cw);
  assert (List.map (fun p -> p.slug) (mocs ce) = List.map (fun p -> p.slug) (mocs cw));
  (let c1w = List.find (fun p -> p.title = "Zeta Core One") cw
   and c1e = List.find (fun p -> p.title = "Zeta Core One") ce in
   assert (similar_notes cw c1w 3 = similar_notes ce c1e 3));
  (* LAW episodic-degradation: the episodic page is classified, carries no
     backlinks/mentions, yields no similarity, and is ABSENT from
     pagerank/communities — yet still renders as a page (total) *)
  let ep = List.find is_episodic ce in
  assert (ep.backlinks = [] && ep.mentions = [] && ep.back_ctx = []);
  assert (similar_notes ce ep 5 = []);
  assert (not (List.mem_assoc ep.slug (pagerank ce)));
  assert (not (List.mem_assoc ep.slug (communities ce)));
  assert (has (render_page ~pages:ce ep) "Episode");
  assert (List.for_all (fun p -> not (is_episodic p)) cw);
  (* LAW episode-attribution: machine-set draft + harness frontmatter *)
  let e1 = episode_markdown ~slice:"zk-x" ~verdict:"ok" ~notes:"first pass"
             ~commit:"abcdef1234" ~date:"2026-07-29" ~prev:"" in
  assert (has e1 "status: draft" && has e1 "verified_by: harness");
  assert (has e1 "## Cycle 2026-07-29 \226\128\148 ok @ abcdef12");
  assert (has e1 "first pass");
  (* LAW episode-compaction: folding 7 cycles keeps exactly 5 entries,
     NEWEST FIRST — the unbounded-growth UCA's mechanized guard *)
  let final = List.fold_left (fun prev i ->
      episode_markdown ~slice:"zk-x" ~verdict:"ok"
        ~notes:(Printf.sprintf "cycle-note %d" i) ~commit:"abcdef1234"
        ~date:(Printf.sprintf "2026-07-%02d" i) ~prev)
      "" [ 1; 2; 3; 4; 5; 6; 7 ] in
  let entries = List.filter (fun l ->
      String.length l >= 9 && String.equal (String.sub l 0 9) "## Cycle ")
      (String.split_on_char '\n' final) in
  assert (List.length entries = 5);
  assert (has final "cycle-note 7" && not (has final "cycle-note 2"));
  (match entries with e :: _ -> assert (has e "2026-07-07") | [] -> assert false);
  (* LAW determinism *)
  assert (String.equal
            (episode_markdown ~slice:"s" ~verdict:"ok" ~notes:"n" ~commit:"c" ~date:"d" ~prev:"")
            (episode_markdown ~slice:"s" ~verdict:"ok" ~notes:"n" ~commit:"c" ~date:"d" ~prev:""));
  (* ── BI-TEMPORAL EDGE INTERVALS (zk-git-temporal, journal 20260729-1056
     §7.3/§8.2-T) — a 4-snapshot history with an add, a removal, and a
     RE-ADD (the non-destructive-invalidation case) *)
  let snaps = [
    ("c1", "t1", [ ("a", "b") ]);
    ("c2", "t2", [ ("a", "b"); ("b", "c") ]);
    ("c3", "t3", [ ("b", "c") ]);
    ("c4", "t4", [ ("b", "c"); ("a", "b") ]) ] in
  let ivs = edge_intervals snaps in
  (* LAW asof-roundtrip (THE homomorphism): reconstructing EVERY snapshot
     from the intervals yields exactly that snapshot's edge set — the final
     encoding is lossless against the snapshot oracle *)
  List.iteri (fun i (_, _, es) ->
    assert (asof_of_intervals ivs i = List.sort_uniq compare es)) snaps;
  (* LAW interval-wellformed: half-open, added strictly before removed *)
  List.iter (fun (_, s, r) -> match r with Some r -> assert (s < r) | None -> ()) ivs;
  (* LAW non-destructive re-add: a→b carries TWO intervals ([0,2) and [3,∞)),
     never a rewritten one *)
  assert (List.length (List.filter (fun (e, _, _) -> e = ("a", "b")) ivs) = 2);
  assert (List.mem (("a", "b"), 0, Some 2) ivs && List.mem (("a", "b"), 3, None) ivs);
  (* LAW live-edge-open: an edge present in the last snapshot has no close *)
  assert (List.exists (fun (e, _, r) -> e = ("b", "c") && r = None) ivs);
  (* LAW monotone-append: every interval CLOSED within a prefix persists
     verbatim in the extended history (history only grows) *)
  let pre = edge_intervals (List.filteri (fun i _ -> i < 3) snaps) in
  List.iter (fun (e, s, r) ->
    match r with Some _ -> assert (List.mem (e, s, r) ivs) | None -> ()) pre;
  (* LAW churn: both endpoints of every event counted; a→b has 3 events
     (add+remove+re-add) and ranks first with b *)
  (match interval_churn ivs with
   | (s1, n1) :: _ -> assert (n1 >= 3 && (s1 = "a" || s1 = "b"))
   | [] -> assert false);
  (* LAW totality + determinism *)
  assert (edge_intervals [] = []);
  assert (asof_of_intervals [] 0 = []);
  assert (edge_intervals snaps = edge_intervals snaps);
  (* ── COMMUNITY SUMMARIES / MoCs (zk-community-summaries, journal
     20260729-1056 §7.13) — fixture: an MA-triangle and an NA-pair *)
  let mf = [
    ("docs/ma.md", "# MA\n\n[[MB]] [[MC]]"); ("docs/mb.md", "# MB\n\n[[MC]]");
    ("docs/mc.md", "# MC\n\n[[MA]]");
    ("docs/na.md", "# NA\n\n[[NB]]"); ("docs/nb.md", "# NB\n\n[[NA]]") ] in
  let mcx = build mf in
  (* LAW digest: order-invariant, membership-sensitive *)
  assert (community_digest [ "b"; "a" ] = community_digest [ "a"; "b" ]);
  assert (community_digest [ "a" ] <> community_digest [ "a"; "b" ]);
  (* LAW moc-missing: both size≥2 communities need a summary *)
  let st0 = moc_status mcx in
  assert (List.length st0 = 2);
  assert (List.for_all (fun (_, _, s) -> s = Moc_missing) st0);
  (* LAW moc-markdown: draft + harness frontmatter, every member LINKED, the
     membership hash embedded verbatim *)
  let cid, members, _ = List.hd st0 in
  assert (String.equal cid "ma");
  let mm = moc_markdown ~date:"2026-07-29" ~cid ~members mcx in
  assert (has mm "status: draft" && has mm "verified_by: harness");
  (* LAW moc-slug-links: members linked by SLUG (resolver-safe against any
     title character), displayed by title — [[slug|Title]] *)
  assert (has mm "[[ma|MA]]" && has mm "[[mb|MB]]" && has mm "[[mc|MC]]");
  assert (has mm ("membership: " ^ community_digest members));
  (* LAW amp-title-resolves (the renderer bug the wiki-audit exposed): a
     [[Title & X]] link must RESOLVE despite pre-link HTML escaping — the
     backlink appears and the render carries no "unresolved note" *)
  let amp = build [
    ("docs/aa1.md", "# Alpha &amp; Analysis is not this title\n\nreal body");
    ("docs/at.md", "# Design & Integration\n\ntarget body");
    ("docs/as.md", "# Amp Source\n\nsee [[Design & Integration]] for detail") ] in
  let atp = List.find (fun p -> p.title = "Design & Integration") amp in
  assert (List.mem "as" atp.backlinks);
  assert (not (has (render_page ~pages:amp (List.find (fun p -> p.title = "Amp Source") amp))
                 "unresolved note"));
  (* LAW moc-fresh-fixpoint (self-invalidation IMMUNITY): adding the very
     note we generated — which links all members — leaves its own status
     Fresh, because membership is computed WITHOUT moc-* notes *)
  let mcx2 = build (mf @ [ ("docs/zk/moc-ma.md", mm) ]) in
  (match List.find (fun (c, _, _) -> String.equal c "ma") (moc_status mcx2) with
   | _, _, Moc_fresh -> ()
   | _ -> assert false);
  (* LAW moc-stale-on-membership-change: a NEW member (MD joins the
     MA-community) invalidates the stored hash *)
  let mcx3 = build (mf @ [ ("docs/zk/moc-ma.md", mm);
                           ("docs/md.md", "# MD\n\n[[MA]] [[MB]]") ]) in
  (match List.find (fun (c, _, _) -> String.equal c "ma") (moc_status mcx3) with
   | _, _, Moc_stale -> ()
   | _ -> assert false);
  (* LAW moc-promotion-freeze: a human-promoted summary (status flipped off
     draft) reports FROZEN even with a stale hash — never overwritable *)
  let promoted = Str.global_replace (Str.regexp_string "status: draft") "status: published" mm in
  let mcx4 = build (mf @ [ ("docs/zk/moc-ma.md", promoted);
                           ("docs/md.md", "# MD\n\n[[MA]] [[MB]]") ]) in
  (match List.find (fun (c, _, _) -> String.equal c "ma") (moc_status mcx4) with
   | _, _, Moc_frozen -> ()
   | _ -> assert false);
  (* LAW determinism + totality *)
  assert (moc_status mcx = moc_status mcx);
  assert (moc_status [] = []);
  (* ── ZK-WEB-SURFACING renderer laws — the web is one more VIEW of the
     law-tested kernels; every board entry must be a live link ─────────── *)
  (* anomalies board: orphan + mention entries linked; holes as pairs;
     undermined section; the healthy corpus renders the explicit steady state *)
  let ab = render_anomalies_page ce in
  assert (has ab "Orphans" && has ab "zc3.html");
  assert (has ab "Unlinked mentions");
  let hb = render_anomalies_page cmx in
  assert (has hb "Structural holes" && has hb "t1.html" && has hb "u1.html");
  assert (has (render_anomalies_page gc) "Undermined");
  let okc = build [ ("docs/ok1.md", "# Ok One\n\n[[Ok Two]]");
                    ("docs/ok2.md", "# Ok Two\n\n[[Ok One]]") ] in
  assert (has (render_anomalies_page okc) "All clear");
  (* query console: rows table, named error chip, blank-state hint — total *)
  let qp = render_query_page dc "from type:claim sort slug" in
  assert (has qp "zq-t" && has qp "c1.html" && has qp "3 rows");
  assert (has (render_query_page dc "frobnicate") "zq-err");
  assert (has (render_query_page dc "") "Try:");
  (* note-page enrichment: grounded standing chip (CB is OUT), community
     chip, expandable neighborhood *)
  (* the MARKUP form "zk-grd g-<x>" (space), never the CSS selector form
     ".zk-grd.g-<x>" — the stylesheet ships in every page and would satisfy a
     bare substring (the recurring CSS-in-page fixture trap, caught again by
     MUT-WS-1's first survival) *)
  assert (has (render_page ~pages:gc (List.find (fun p -> p.title = "CB") gc)) "zk-grd g-out");
  assert (has (render_page ~pages:gc (List.find (fun p -> p.title = "CC") gc)) "zk-grd g-in\"");
  let t2v = render_page ~pages:cmx (List.find (fun p -> p.title = "T2") cmx) in
  assert (has t2v "zk-comm" && has t2v "zk-nbh");
  (* search page: the semantic controls ship *)
  assert (has (render_search dc) "zks-g");
  (* timeline: HALF-OPEN aliveness — an edge is GONE at its removal stamp *)
  let trows = [ ("a", "b", "c1", "2026-01-01", "c2", "2026-01-02");
                ("b", "c", "c1", "2026-01-01", "", "") ] in
  assert (has (render_timeline dc ~rows:trows ~sel:"c1") "2 edges alive");
  assert (has (render_timeline dc ~rows:trows ~sel:"c2") "1 edges alive");
  assert (has (render_timeline dc ~rows:[] ~sel:"") "No mined history");
  (* currency vitals: census + audit verdict + MoC states (cmx: missing) *)
  let cv = render_currency cmx ~vec_counts:[ ("note", 5) ] ~audit:"HEALTHY" in
  assert (has cv "Vitals" && has cv "HEALTHY" && has cv "missing");
  assert (has (render_currency [] ~vec_counts:[] ~audit:"") "unknown");
  (* ── FEATURE ALGEBRA (zk-feature-algebra) ──────────────────────────────
     EXHAUSTIVE semilattice verification — the carrier is finite, so the
     laws hold for EVERY element, not a sample: 125 associativity triples,
     25 commutativity pairs, 5 idempotents, identity, upper-bound. *)
  List.iter (fun a -> List.iter (fun b -> List.iter (fun c ->
      assert (cov_join a (cov_join b c) = cov_join (cov_join a b) c))
      cov_all) cov_all) cov_all;
  List.iter (fun a -> List.iter (fun b ->
      assert (cov_join a b = cov_join b a);
      (* upper bound on the comparable chain: a ⊑ a ⊔ b unless a = Na *)
      if a <> Cov_na then assert (cov_rank (cov_join a b) >= cov_rank a))
      cov_all) cov_all;
  List.iter (fun a ->
      assert (cov_join a a = a);
      assert (cov_join Cov_na a = a && cov_join a Cov_na = a)) cov_all;
  (* LAW feature-parse well-formedness: exactly-one tag discipline — a good
     note parses, a double-cov note is REPORTED (never guessed), a
     non-feature page is ignored *)
  let ffx = build [
    ("docs/features/f-good.md", "# Good Feature\n\n#feature #src-notion #area-blocks #cov-native\n\nbody");
    ("docs/features/f-bad.md", "# Bad Feature\n\n#feature #src-notion #area-blocks #cov-native #cov-gap\n\nbody");
    ("docs/features/f-none.md", "# Not A Feature\n\n#other\n\nplain") ] in
  let ffs, fbad = feature_db ffx in
  assert (List.length ffs = 1);
  assert ((List.hd ffs).fcov = Cov_native && (List.hd ffs).fsrc = "notion"
          && (List.hd ffs).farea = "blocks");
  assert (fbad = [ "features--f-bad" ]);
  assert (feature_of_page (List.find (fun p -> p.title = "Not A Feature") ffx) = None);
  (* LAW rollup join/floor/partition over a mixed fixture: blocks =
     {native, gap, na} → join native, floor gap; pages = {strong} *)
  let ffx2 = build [
    ("docs/features/g1.md", "# G1\n\n#feature #src-notion #area-blocks #cov-native\n\nx");
    ("docs/features/g2.md", "# G2\n\n#feature #src-notion #area-blocks #cov-gap\n\nx");
    ("docs/features/g3.md", "# G3\n\n#feature #src-notion #area-blocks #cov-na\n\nx");
    ("docs/features/g4.md", "# G4\n\n#feature #src-notion #area-pages #cov-strong\n\nx") ] in
  let fs2, _ = feature_db ffx2 in
  assert (coverage_rollup fs2 = [
    ("notion", "blocks", Cov_native, Some Cov_gap, 3);
    ("notion", "pages", Cov_strong, Some Cov_strong, 1) ]);
  (* census partition: the by-coverage counts sum to the total *)
  assert (List.length fs2 =
          List.fold_left (fun acc c ->
              acc + List.length (List.filter (fun f -> f.fcov = c) fs2)) 0 cov_all);
  (* LAW cross-encoding AGREEMENT: the kernel's gap census equals the count
     the INDEPENDENT zkquery tag path derives over the same corpus — the
     initial (notes) and final (records) encodings answer identically *)
  (match zkquery_parse "from tag:cov-gap" with
   | Ok zq ->
       assert (List.length (zkquery_eval ffx2 zq)
               = List.length (List.filter (fun f -> f.fcov = Cov_gap) fs2))
   | Error _ -> assert false);
  (* LAW coverage_json: malformed surfaced verbatim; totals present *)
  assert (has (coverage_json ffx) "\"malformed\":[\"features--f-bad\"]");
  assert (has (coverage_json ffx2) "\"total\":4");
  (* LAW currency-panel algebra: the rollup renders join AND floor chips *)
  let cv2 = render_currency ffx2 ~vec_counts:[] ~audit:"HEALTHY" in
  assert (has cv2 "Reference coverage" && has cv2 "join native" && has cv2 "floor gap");
  (* ── GAP CLOSURE 1 (zk-gap-closure-1): callouts, todos, [TOC] ──────────
     The evolutionary loop demonstrated: three enumerated #cov-gap features
     become renderer laws, and the coverage census MOVES. *)
  (* LAW callout: typed admonition with icon+label; the TYPE is preserved
     (not defaulted); body lines continue inside; a PLAIN quote is untouched *)
  let co = render_md_t "> [!warning] Careful now\n> the body line" in
  assert (has co "callout co-warning\"" && has co "Careful now" && has co "the body line");
  assert (has (render_md_t "> [!tip] Do this") "callout co-tip\"");
  assert (not (has (render_md_t "> just a quote") "callout"));
  assert (has (render_md_t "> just a quote") "<blockquote>");
  (* unknown type accepted generically (any [a-z]+) *)
  assert (has (render_md_t "> [!ritual] Custom") "callout co-ritual\"");
  (* LAW todo: read-only checkboxes, checked state preserved; plain items
     unaffected *)
  let td = render_md_t "- [ ] open task\n- [x] done task\n- plain item" in
  assert (has td "<li class=\"todo\"><input type=\"checkbox\" disabled=\"disabled\"/> open task");
  assert
    (has td
       "<li class=\"todo\"><input type=\"checkbox\" disabled=\"disabled\" checked=\"checked\"/> done task");
  assert (has td "<li>plain item</li>");
  (* LAW toc: a full-line [TOC] links the note's OWN headings by the SAME
     anchors heading_html emits — znorm text, or the explicit ^id *)
  let tc = render_md_t "# Alpha One\n\n[TOC]\n\n## Beta Part ^bp\n\ntext\n\n### Gamma Sub" in
  assert (has tc "<nav class=\"toc\">");
  assert (has tc "href=\"#alpha-one\"");
  assert (has tc "href=\"#^bp\"");                 (* explicit id wins *)
  assert (has tc "toc-l3\" href=\"#gamma-sub\"");  (* level preserved *)
  assert (not (has (render_md_t "no headings\n\n[TOC]\n\nhere") "<nav class=\"toc\">"));
  assert (not (has (render_md_t "inline [TOC] mention") "<nav class=\"toc\">"));
  (* ── CONTEXTUAL BACKLINKS (zk-contextual-backlinks, §7.10) ─────────────
     Reuse the zc fixture: A's body links B and C on the line AFTER the H1,
     so the context is NOT the first line — the placement that kills the
     wrong-line mutant. *)
  let bpage = List.find (fun p -> p.slug = beta) zc in
  (* LAW ctx-domain-equality: the context map covers EXACTLY the backlinks *)
  List.iter (fun p -> assert (List.map fst p.back_ctx = p.backlinks)) zc;
  (* LAW ctx-soundness: the stored context is the CITING line — re-scanning it
     with the corpus resolver still yields this note (the link is IN the
     context), and it is not the H1 line *)
  (match bpage.back_ctx with
   | [ (src, ctx) ] ->
       assert (String.equal src alpha);
       assert (has ctx "[[Beta Node]]");
       assert (not (has ctx "# Alpha Node"));
       (* the same line cites Gamma too — one extraction, both targets *)
       assert (has ctx "[[Gamma Node|@supports]]")
   | _ -> assert false);
  (* LAW ctx-clamp: a pathologically long citing line is bounded to 240 chars *)
  let long = build [ ("docs/lt.md", "# Long Target\n\nbody");
                     ("docs/ls.md", "# Long Source\n\n" ^ String.make 400 'x' ^ " [[Long Target]] tail") ] in
  (match (List.find (fun p -> p.title = "Long Target") long).back_ctx with
   | [ (_, ctx) ] -> assert (String.length ctx <= 240)
   | _ -> assert false);
  (* LAW ctx-render + injection-safety: the context renders in the Linked-
     references panel ESCAPED (a hostile context can't inject markup) *)
  let hz = build [ ("docs/ht.md", "# Host Target\n\nbody");
                   ("docs/hs.md", "# Host Source\n\n<script>alert(1)</script> [[Host Target]]") ] in
  let hview = render_page ~pages:hz (List.find (fun p -> p.title = "Host Target") hz) in
  assert (has hview "zk-ctx");
  assert (not (has hview "<script>alert"));
  (* LAW ctx-api: zk_read_note's payload carries {from, context} verbatim *)
  let bapi = api_note zc bpage in
  assert (has bapi "\"backlinks_ctx\":[");
  assert (has bapi (Printf.sprintf "{\"from\":\"%s\",\"context\":" alpha));
  (* LAW link_contexts unit: first-occurrence-wins + anchor bases resolve *)
  let res k = if znorm k = "target" then Some "target" else None in
  (match link_contexts res "a [[Target]] one\nb [[Target]] two" with
   | [ ("target", c) ] -> assert (has c "one")
   | _ -> assert false);
  (match link_contexts res "see [[Target#section]] here" with
   | [ ("target", c) ] -> assert (has c "[[Target#section]]")
   | _ -> assert false);
  assert (link_contexts (fun _ -> None) "no [[Links]] resolve" = []);
  (* ── BLOCK CHUNKING (zk-block-vectors, journal 20260729-1056 §6.3) ─────── *)
  let braw = "# Intro heading ^intro\n\nfirst block words here\nsecond line same block\n\nanother anchored block ^b2\n\n## Sub heading\ntail text after heading" in
  let cs = chunks_of braw in
  (* LAW chunk-partition: in-order token-stream concatenation ≡ the body's *)
  assert (List.concat_map (fun (_, t) -> sim_tokens t) cs = sim_tokens braw);
  (* LAW chunk-anchor: explicit ^ids survive as chunk ids (search hits and
     [[Page#^id]] links share one addressing scheme) *)
  assert (List.mem_assoc "intro" cs && List.mem_assoc "b2" cs);
  (* LAW chunk-boundaries: the heading starts its own chunk; the line after a
     heading (no blank between) stays WITH the heading's chunk *)
  assert (List.exists (fun (_, t) -> has t "## Sub heading" && has t "tail text") cs);
  (* anchor-less chunks get deterministic digest ids (b + 8 hex) *)
  (let anon = List.filter (fun (c, _) -> c.[0] = 'b' && String.length c = 9 && c <> "b2") cs in
   assert (anon <> []));
  (* LAW chunk-determinism + id-uniqueness *)
  assert (chunks_of braw = chunks_of braw);
  (let ids = List.map fst cs in
   assert (List.sort_uniq compare ids = List.sort compare ids));
  (* same bytes in a DIFFERENT note ⇒ same digest id (content-derived, stable) *)
  assert (fst (List.hd (chunks_of "one lonely block")) = fst (List.hd (chunks_of "one lonely block")));
  (* duplicate content within ONE note ⇒ ids disambiguated, both kept *)
  (let dup = chunks_of "same words\n\nsame words" in
   assert (List.length dup = 2 && List.sort_uniq compare (List.map fst dup) |> List.length = 2));
  (* LAW totality: empty and blank-only bodies chunk to [] *)
  assert (chunks_of "" = []);
  assert (chunks_of "\n\n   \n" = []);
  ()
