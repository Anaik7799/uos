(* doc_lint.ml — the document lint algebra.

   SEMANTIC DOMAIN
   ---------------
   A document is (path, kind, bytes). A rule is a NAMED TOTAL function
   `doc -> finding list`. The linter is the fold of a rule registry over a
   corpus, accumulating findings and metrics in a monoid. Nothing else.

       lint : registry -> doc list -> report
       lint R (d1 … dn) = fold (⊕) empty [ r d | r ∈ R, d ∈ (d1 … dn) ]

   Consequences that make this worth writing as an algebra rather than a pile
   of checks:

   * EXTENSIBLE / PLUGGABLE. A new check is a new value appended to
     `registry`. The engine is never edited — the SC-F30 registry-port
     discipline applied to linting. Rules cannot see each other, so adding one
     cannot change another's verdict.
   * TOTAL. A rule that raises is a defect in the rule, not a crash of the
     gate: `run_rule` catches and converts to an Error finding against the
     rule itself, so one bad rule can never hide the rest of the corpus.
   * DETERMINISTIC. Rules are pure functions of the document; the same corpus
     yields the same report, which is what makes a ratchet possible.
   * MEASURABLE. Because evaluation is a fold, per-rule and per-stage cost is
     observable without instrumenting each rule by hand.

   SEVERITY LATTICE:  Info < Warning < Error.  Only `Error` fails the gate.
   This is deliberate and load-bearing: it lets the linter cover EVERY
   generated artifact honestly, reporting real-but-not-fatal issues in
   inherited documents instead of either reddening a shared gate or narrowing
   the scope until the gate is green by exclusion. The scope is total; the
   failure set is principled.

   Benchmarked against W3C vnu, markdownlint, remark-lint, html-validate and
   HTMLHint — see `docs/design/LINT_BENCHMARK.md` for what this deliberately
   does NOT attempt (CSS value validity, the full HTML content model). *)

type kind = Markdown | Html | Json | Zig | Ocaml

type severity = Info | Warning | Error

let severity_rank = function Info -> 0 | Warning -> 1 | Error -> 2
let severity_name = function Info -> "info" | Warning -> "warning" | Error -> "error"

type finding = {
  rule_id : string;
  severity : severity;
  path : string;
  line : int; (* 1-based; 0 means "the document as a whole" *)
  message : string;
}

type doc = {
  path : string;
  kind : kind;
  content : string;
  lines : string list;
  lower : string;
  generated : bool; (* a generated artifact is held to strict correctness *)
}

type rule = {
  id : string;
  applies : kind;
  sev : severity;
  title : string;   (* one-line label *)
  why : string;     (* why it matters — shown in the rule catalogue *)
  remedy : string;  (* how to fix it *)
  check : doc -> (int * string) list; (* (line, message) *)
}

(* ---------- report monoid ------------------------------------------------ *)

type report = {
  findings : finding list;
  files : int;
  bytes : int;
  lines_total : int;
  rule_ms : (string * float) list; (* per-rule accumulated cost *)
}

let empty_report =
  { findings = []; files = 0; bytes = 0; lines_total = 0; rule_ms = [] }

let merge_ms a b =
  let tbl = Hashtbl.create 16 in
  List.iter (fun (k, v) -> Hashtbl.replace tbl k (v +. (try Hashtbl.find tbl k with Not_found -> 0.))) (a @ b);
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) tbl []

(* merge : associative, with empty_report as identity (LINT-MONOID). *)
let merge a b =
  { findings = a.findings @ b.findings;
    files = a.files + b.files;
    bytes = a.bytes + b.bytes;
    lines_total = a.lines_total + b.lines_total;
    rule_ms = merge_ms a.rule_ms b.rule_ms }

(* ---------- helpers (total, allocation-light) ---------------------------- *)

(* Allocation-free substring primitives.

   The first version compared with `String.sub hay i ln = needle`, which
   ALLOCATES a fresh substring at every position. On the 10.8 MB artifact in
   this corpus that is ~10.8 million allocations per scan, per rule — and it,
   not scheduling, was the reason parallelism appeared to plateau. Comparing
   bytes in place removes the allocation entirely. *)

let matches_at (hay : string) (i : int) (needle : string) : bool =
  let ln = String.length needle in
  if i + ln > String.length hay then false
  else begin
    let j = ref 0 and ok = ref true in
    while !ok && !j < ln do
      if String.unsafe_get hay (i + !j) <> String.unsafe_get needle !j then ok := false;
      incr j
    done;
    !ok
  end

let contains (hay : string) (needle : string) : bool =
  let lh = String.length hay and ln = String.length needle in
  if ln = 0 then true
  else if ln > lh then false
  else begin
    let c0 = String.unsafe_get needle 0 in
    let found = ref false and i = ref 0 and last = lh - ln in
    while (not !found) && !i <= last do
      if String.unsafe_get hay !i = c0 && matches_at hay !i needle then found := true
      else incr i
    done;
    !found
  end

let count_of (hay : string) (needle : string) : int =
  let lh = String.length hay and ln = String.length needle in
  if ln = 0 || ln > lh then 0
  else begin
    let c0 = String.unsafe_get needle 0 in
    let n = ref 0 and i = ref 0 and last = lh - ln in
    while !i <= last do
      if String.unsafe_get hay !i = c0 && matches_at hay !i needle then
        (incr n; i := !i + ln)
      else incr i
    done;
    !n
  end

let ltrim (s : string) : string =
  let n = String.length s in
  let i = ref 0 in
  while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done;
  String.sub s !i (n - !i)

let clip n s = if String.length s <= n then s else String.sub s 0 n ^ "…"

(* ---------- markdown rules ----------------------------------------------- *)

let md_body_lines (d : doc) : (int * string) list =
  (* drop YAML frontmatter, keeping original line numbers *)
  let numbered = List.mapi (fun i l -> (i + 1, l)) d.lines in
  match numbered with
  | (_, first) :: rest when String.trim first = "---" ->
      let rec skip = function
        | [] -> []
        | (_, l) :: tl when String.trim l = "---" -> tl
        | _ :: tl -> skip tl
      in
      skip rest
  | _ -> numbered

let r_md_title_first =
  { id = "MD-TITLE-FIRST"; applies = Markdown; sev = Error;
    title = "document begins with its H1 title";
    why =
      "A document whose first line is not its title has usually been damaged \
       by an edit — this is exactly how a mis-delimited substitution welds a \
       table row onto the head of a file, which happened twice here.";
    remedy = "Restore the `# Title` as the first non-blank line.";
    check = (fun d ->
      match List.find_opt (fun (_, l) -> String.trim l <> "") (md_body_lines d) with
      | None -> [ (0, "document is empty") ]
      | Some (n, l) ->
          let t = ltrim l in
          if not (String.length t > 2 && String.sub t 0 2 = "# ") then
            [ (n, Printf.sprintf "first non-blank line is not an H1: %s" (clip 60 t)) ]
          else if String.contains l '|' then
            [ (n, "the H1 line also carries a table pipe (concatenated content)") ]
          else []) }

let r_md_welded_heading =
  { id = "MD-NO-EMBEDDED-HEADING"; applies = Markdown; sev = Error;
    title = "no table row welded to a heading";
    why =
      "`|#` is the signature of a substitution whose delimiter appeared in its \
       payload: a table row and a heading fused into one line.";
    remedy = "Split the line; re-apply the edit with an exact-match tool.";
    check = (fun d ->
      List.filter_map
        (fun (n, l) ->
          let t = ltrim l in
          if String.length t > 0 && t.[0] = '|' && contains l "|# " then
            Some (n, Printf.sprintf "row welded to a heading: %s" (clip 60 t))
          else None)
        (md_body_lines d)) }

let r_md_fence_balanced =
  { id = "MD-FENCE-BALANCED"; applies = Markdown; sev = Error;
    title = "code fences pair up";
    why = "An unclosed fence swallows the rest of the document when rendered.";
    remedy = "Add the missing closing ``` .";
    check = (fun d ->
      let n =
        List.length
          (List.filter
             (fun (_, l) ->
               let t = ltrim l in
               String.length t >= 3 && String.sub t 0 3 = "```")
             (md_body_lines d))
      in
      if n mod 2 <> 0 then [ (0, Printf.sprintf "%d fences — one is unclosed" n) ]
      else []) }

(* ---------- the markdown table model (GFM-faithful) -----------------------

   A run of lines containing pipes is NOT a table. GFM defines a table as a
   HEADER row, a DELIMITER row whose cell count EQUALS the header's, and a
   body of following rows; the table ends at the first line that is not a row.
   Everything else — including a tidy grid of pipes with no delimiter row —
   renders as literal paragraph text in every conforming renderer.

   Modelling that exactly, rather than counting pipes, is what lets these
   rules name the defect instead of a symptom. The previous encoding did two
   things wrong, both found by running it over this corpus:

   (1) it RESET its header on every mismatch, so one bad row silently re-based
       the check: the linter then reported later, CORRECT rows while staying
       silent about the row that actually broke the block. Two independent
       reviews of its output traced flagged lines back to a breaker several
       rows earlier.
   (2) it treated delimiter-less pipe runs as tables. `DIVERGENCE_LOG.md` is
       an append-only ledger of pipe-delimited RECORDS whose arity drifted
       from 5 to 7 columns over hundreds of entries and which carries exactly
       one delimiter row; the rule reported 33 "column count" defects that
       were really one structural fact, and the remedy it proposed would have
       had an agent invent or drop ledger content to satisfy a broken model.

   Precision here is not leniency: the checks below apply to every real table
   in the corpus, and three new rules cover defects the pipe counter could not
   see at all. The residual is stated in LINT_FEATURES.md. *)

(* Cell count of a row line, GFM-normalised: strip one optional leading and one
   optional trailing pipe, then count separators that are neither escaped nor
   inside a code span. cells = separators + 1. Returns 0 when the line carries
   no pipe at all. TOTAL — no input escapes, no exception. *)
let md_row_cells (line : string) : int =
  let s = String.trim line in
  let n = String.length s in
  if n = 0 then 0
  else begin
    let b = if s.[0] = '|' then 1 else 0 in
    let e = if n - 1 > b && s.[n - 1] = '|' && s.[n - 2] <> '\\' then n - 1 else n in
    let wrapped = b = 1 && e < n in
    if e <= b then (if wrapped then 1 else 0)
    else begin
      let seps = ref 0 and i = ref b in
      while !i < e do
        (match s.[!i] with
         | '\\' -> incr i (* the escaped character is literal, never a separator *)
         | '`' ->
             (* skip a code span: a run of k backticks closes on the next run
                of EXACTLY k. An unmatched run is literal text, so scanning
                simply resumes after it. *)
             let start = !i in
             while !i < e && s.[!i] = '`' do incr i done;
             let k = !i - start in
             let j = ref !i and closed = ref false in
             while (not !closed) && !j < e do
               if s.[!j] = '`' then begin
                 let st = !j in
                 while !j < e && s.[!j] = '`' do incr j done;
                 if !j - st = k then closed := true
               end
               else incr j
             done;
             if !closed then i := !j;
             decr i (* the loop's own increment lands on the next character *)
         | '|' -> incr seps
         | _ -> ());
        incr i
      done;
      if !seps = 0 && not wrapped && b = 0 then 0 else !seps + 1
    end
  end

(* Some n when the line is a GFM delimiter row of n cells: every cell must be
   `:?-+:?`, there must be at least one, and the line must carry a pipe —
   without that last clause a thematic break (`---`) reads as a one-column
   delimiter and every horizontal rule in the corpus opens a phantom table.
   TOTAL. *)
let md_delimiter_cells (line : string) : int option =
  let s = String.trim line in
  let n = String.length s in
  if n = 0 || not (String.contains s '|') then None
  else begin
    let b = if s.[0] = '|' then 1 else 0 in
    let e = if n - 1 > b && s.[n - 1] = '|' then n - 1 else n in
    if e <= b then None
    else begin
      let cells = ref [] and buf = Buffer.create 16 in
      for i = b to e - 1 do
        if s.[i] = '|' then begin
          cells := Buffer.contents buf :: !cells;
          Buffer.clear buf
        end
        else Buffer.add_char buf s.[i]
      done;
      cells := Buffer.contents buf :: !cells;
      let cells = List.rev !cells in
      let valid c =
        let c = String.trim c in
        let m = String.length c in
        m > 0
        && begin
             let i = ref 0 and dashes = ref 0 in
             if c.[0] = ':' then incr i;
             while !i < m && c.[!i] = '-' do incr i; incr dashes done;
             if !i < m && c.[!i] = ':' then incr i;
             !dashes >= 1 && !i = m
           end
      in
      if List.for_all valid cells then Some (List.length cells) else None
    end
  end

type md_tline =
  | ML_blank
  | ML_row of int (* cells *)
  | ML_delim of int (* cells *)
  | ML_other

(* A line that opens another block-level construct is never a table row, no
   matter how many pipes it carries. Without this, a bullet list of wikilinks
   — `- [[target|label]] · degree 67`, the shape every generated MoC note in
   this repository is built from — reads as a uniform grid of two-cell rows,
   and the corpus run reported eight generated files as malformed tables.
   Checked only when the line does not already open with a pipe. *)
let md_block_marker (t : string) : bool =
  let n = String.length t in
  n > 0
  && (match t.[0] with
      | '#' | '>' -> true
      | '-' | '*' | '+' -> n = 1 || t.[1] = ' ' || t.[1] = '\t'
      | '0' .. '9' ->
          let i = ref 0 in
          while !i < n && t.[!i] >= '0' && t.[!i] <= '9' do incr i done;
          !i < n && (t.[!i] = '.' || t.[!i] = ')')
      | _ -> false)

(* GFM: up to three leading spaces are allowed; four or more make an indented
   code block, which is never a table. *)
let md_classify (line : string) : md_tline =
  let t = String.trim line in
  if t = "" then ML_blank
  else begin
    let indent = ref 0 in
    while !indent < String.length line && line.[!indent] = ' ' do incr indent done;
    if !indent >= 4 then ML_other
    else if t.[0] <> '|' && md_block_marker t then ML_other
    else
      match md_delimiter_cells t with
      | Some n -> ML_delim n
      | None -> ( match md_row_cells t with 0 -> ML_other | c -> ML_row c)
  end

(* A maximal run of consecutive row/delimiter lines, with the classification
   of the gap that precedes it — a blank-only gap is what splits one table
   into fragments, and the fragment then renders as literal text. *)
type md_block = {
  bl_lines : (int * md_tline * string) list;
  bl_gap_blank_only : bool;
}

let md_blocks (d : doc) : md_block list =
  let fence = ref None in
  (* [gap_blank_only] describes the gap PRECEDING whatever block is being
     accumulated. A block is flushed by the very blank line that opens the next
     gap, so flushing starts a fresh gap as blank-only and any non-blank line
     clears it. It starts false: nothing precedes the first block. *)
  let blocks = ref [] and cur = ref [] and gap_blank_only = ref false in
  let flush () =
    if !cur <> [] then begin
      blocks := { bl_lines = List.rev !cur; bl_gap_blank_only = !gap_blank_only } :: !blocks;
      cur := [];
      gap_blank_only := true
    end
  in
  List.iter
    (fun (n, l) ->
      let t = ltrim l in
      (* fenced regions are never tables; a fence closes on the same character
         with at least the opening length (GFM) *)
      let fence_run ch =
        let k = ref 0 in
        while !k < String.length t && t.[!k] = ch do incr k done;
        !k
      in
      let tick = fence_run '`' and tilde = fence_run '~' in
      let opener = if tick >= 3 then Some ('`', tick) else if tilde >= 3 then Some ('~', tilde) else None in
      match (!fence, opener) with
      | None, Some (ch, k) ->
          flush ();
          gap_blank_only := false;
          fence := Some (ch, k)
      | Some (ch, k), Some (ch', k') when ch = ch' && k' >= k -> fence := None
      | Some _, _ -> ()
      | None, None -> (
          match md_classify l with
          | ML_blank -> flush ()
          | ML_other ->
              flush ();
              gap_blank_only := false
          | (ML_row _ | ML_delim _) as k -> cur := (n, k, l) :: !cur))
    (md_body_lines d);
  flush ();
  List.rev !blocks

(* The ORACLE for the block model. `md_blocks` above is the FINAL encoding: one
   streaming pass carrying the fence state and the gap flag in refs. This one is
   written to be READ — it materialises the classified line list, collects the
   maximal row runs by index, and then decides each gap by looking at the lines
   between two runs, which is the definition rather than an implementation of
   it. The two are admitted equal by TABLE-ORACLE-AGREEMENT over enumerated and
   random documents; the streaming version exists only because the corpus is
   42 MB. *)
let md_blocks_oracle (d : doc) : md_block list =
  (* 1. classify every body line, forcing fenced regions to ML_other *)
  let classified =
    let fence = ref None in
    List.map
      (fun (n, l) ->
        let t = ltrim l in
        let run ch =
          let k = ref 0 in
          while !k < String.length t && t.[!k] = ch do incr k done;
          !k
        in
        let tick = run '`' and tilde = run '~' in
        let opener =
          if tick >= 3 then Some ('`', tick) else if tilde >= 3 then Some ('~', tilde) else None
        in
        match (!fence, opener) with
        | None, Some (ch, k) -> fence := Some (ch, k); (n, ML_other, l)
        | Some (ch, k), Some (ch', k') when ch = ch' && k' >= k -> fence := None; (n, ML_other, l)
        | Some _, _ -> (n, ML_other, l)
        | None, None -> (n, md_classify l, l))
      (md_body_lines d)
  in
  let is_rowish = function ML_row _ | ML_delim _ -> true | _ -> false in
  (* 2. collect maximal runs of row-ish lines, as index ranges into [arr] *)
  let arr = Array.of_list classified in
  let runs = ref [] and i = ref 0 in
  while !i < Array.length arr do
    let (_, k, _) = arr.(!i) in
    if is_rowish k then begin
      let start = !i in
      while !i < Array.length arr && (let (_, k, _) = arr.(!i) in is_rowish k) do incr i done;
      runs := (start, !i - 1) :: !runs
    end
    else incr i
  done;
  let runs = List.rev !runs in
  (* 3. a gap is blank-only when every line strictly between two runs is blank;
        the first run has no preceding table, so its gap is never blank-only *)
  let rec build prev_end = function
    | [] -> []
    | (s, e) :: tl ->
        let blank_only =
          match prev_end with
          | None -> false
          | Some p ->
              let ok = ref true in
              for j = p + 1 to s - 1 do
                let (_, k, _) = arr.(j) in
                if k <> ML_blank then ok := false
              done;
              !ok
        in
        let lines = ref [] in
        for j = e downto s do
          lines := arr.(j) :: !lines
        done;
        { bl_lines = !lines; bl_gap_blank_only = blank_only } :: build (Some e) tl
  in
  build None runs

(* A block is a TABLE when its first line is a row and its second is a
   delimiter of the SAME arity. Returns (header_cells, body). *)
let md_table_of_block (b : md_block) : (int * (int * md_tline * string) list) option =
  match b.bl_lines with
  | (_, ML_row h, _) :: (_, ML_delim dcells, _) :: body when h = dcells -> Some (h, body)
  | _ -> None

let block_first_row_cells (b : md_block) : int option =
  match b.bl_lines with (_, ML_row c, _) :: _ -> Some c | _ -> None

let r_md_table_columns =
  { id = "MD-TABLE-COLUMN-COUNT"; applies = Markdown; sev = Warning;
    title = "table rows match their header's cell count";
    why =
      "A row with a stray or missing pipe renders as a broken table — cells \
       shift and the last one is dropped. The check is anchored on the header \
       and never re-bases, so the row reported is the row that is wrong.";
    remedy = "Escape the stray pipe as \\| or wrap the fragment in backticks; \
              add the missing cell.";
    check = (fun d ->
      List.concat_map
        (fun b ->
          match md_table_of_block b with
          | None -> []
          | Some (header, body) ->
              List.filter_map
                (fun (n, k, _) ->
                  match k with
                  | ML_row c when c <> header ->
                      Some (n, Printf.sprintf "%d cell(s); header has %d" c header)
                  | _ -> None)
                body)
        (md_blocks d)) }

let r_md_table_delimiter =
  { id = "MD-TABLE-DELIMITER"; applies = Markdown; sev = Warning;
    title = "a grid of pipe rows carries its delimiter row";
    why =
      "Without a `|---|---|` row under the header, GFM does not make a table \
       at all — every renderer emits the pipes as literal paragraph text. The \
       page looks authored but reads as raw punctuation.";
    remedy = "Add a delimiter row under the header with one cell per column.";
    check = (fun d ->
      List.filter_map
        (fun b ->
          if md_table_of_block b <> None then None
          else
            (* only a UNIFORM grid of three or more rows is evidence that a
               table was intended; a run of pipe-delimited records with
               drifting arity is prose, and saying otherwise would be a style
               opinion rather than a well-formedness defect *)
            match b.bl_lines with
            | (n, ML_row c, _) :: (_ :: _ as rest) when List.length rest >= 2 ->
                if
                  List.for_all
                    (fun (_, k, _) -> match k with ML_row c' -> c' = c | _ -> false)
                    rest
                then
                  Some
                    (n,
                     Printf.sprintf
                       "%d uniform %d-cell rows with no delimiter row — renders as text, not a table"
                       (1 + List.length rest) c)
                else None
            | _ -> None)
        (md_blocks d)) }

let r_md_table_split =
  { id = "MD-TABLE-SPLIT"; applies = Markdown; sev = Warning;
    title = "a blank line does not split a table";
    why =
      "A blank line ends a GFM table. The rows after it lose the header and \
       delimiter and render as literal text, while the source still looks \
       like one continuous table.";
    remedy = "Delete the blank line inside the table.";
    check = (fun d ->
      (* [chain] is the arity of a table the current position is still
         DETACHED FROM: it is set by a real table and survives only across
         fragments that a blank-only gap separated and whose arity matches, so
         deleting those blank lines really does reattach them. Anything else —
         prose, a fenced block, a change of arity — breaks the chain. Without
         that the rule pointed at "the table above" from hundreds of lines and
         several unrelated pipe runs away, and its remedy would not have
         worked. *)
      let rec walk chain = function
        | [] -> []
        | b :: tl -> (
            match md_table_of_block b with
            | Some (h, _) -> walk (Some h) tl
            | None -> (
                match (chain, block_first_row_cells b, b.bl_lines) with
                | Some h, Some c, (n, _, _) :: _ when b.bl_gap_blank_only && c = h ->
                    (n,
                     Printf.sprintf
                       "%d row(s) of %d cells detached from the table above by a blank line"
                       (List.length b.bl_lines) c)
                    :: walk chain tl
                | _ -> walk None tl))
      in
      walk None (md_blocks d)) }

let r_md_table_row_wrapped =
  { id = "MD-TABLE-ROW-WRAPPED"; applies = Markdown; sev = Warning;
    title = "a table row is not hard-wrapped across lines";
    why =
      "Markdown has no row continuation: a row wrapped over several physical \
       lines ends the table at the first wrapped line, and the remainder \
       renders as a paragraph. The table looks right in the source and is \
       broken everywhere else.";
    remedy = "Keep each row on one physical line.";
    check = (fun d ->
      List.concat_map
        (fun b ->
          match md_table_of_block b with
          | None -> []
          | Some (_, _) ->
              (* only the LAST line of a table block can be a wrapped row: an
                 interior one would be followed by another row. The signature
                 is an unterminated row — every well-formed row in this corpus
                 closes with a pipe. *)
              (match List.rev b.bl_lines with
               | (n, ML_row _, l) :: _ ->
                   let t = String.trim l in
                   let m = String.length t in
                   if m > 1 && t.[0] = '|' && t.[m - 1] <> '|' then
                     [ (n, "row starts with a pipe but does not close — it continues onto the next line") ]
                   else []
               | _ -> []))
        (md_blocks d)) }

(* ---------- the markup algebra (HTML) -------------------------------------

   The HTML rules used to be substring scans over the lowercased document, and
   that is the same mistake the table rules made: bytes are not markup. A scan
   for `<html` counts the one inside a comment, inside a `<script>`, and inside
   an attribute VALUE; a scan for one exact spelling of a quoted script-src
   prefix misses the extra-whitespace form, the uppercase SRC, the
   single-quoted form, and a protocol-relative //cdn; and a scan that walks to
   the next `>` to find a tag's end stops early on a `>` inside a quoted
   attribute value. Each of those is a false positive or a false negative that
   no amount of needle-tuning removes.

   (The line above is deliberately quote-free: an unmatched double quote inside
   an OCaml comment opens a string literal and breaks the build. That is the
   same self-reference hazard this programme has now hit five times — a control
   tripping over the very pattern it describes.)

   So: tokenize. A Document denotes its TOKEN SEQUENCE, and every rule is a
   predicate over that sequence rather than over bytes.

   Carrier      Document (a string)
   Denotation   Token list, each carrying its byte span
   Signature    html_tokenize : Document -> Token list
   Law          CONSERVATION: the token spans partition the document exactly —
                concatenating their sources reconstructs it byte for byte, so a
                tokenizer defect cannot silently drop or duplicate content.

   Round-trip is the oracle here, and deliberately so. A second hand-written
   tokenizer would share its author's misconceptions about HTML; byte-exact
   reconstruction cannot, because the document itself is the reference. It is
   checked on every enumerated and fuzzed input.

   Scope: this is a TOKENIZER, not a parser. It does not build a tree, does not
   implement the insertion modes, adoption agency, or foreign-content
   integration points, and does not resolve entities. It models exactly what
   these rules need: token boundaries, element names, attributes with their
   real quoting, raw-text elements, and comments. `docs/design/HTML_ALGEBRA.md`
   states the whole of it including what is not attempted. *)

type html_tok_kind =
  | HK_doctype
  | HK_start of string * (string * string) list * bool (* name, attrs, self-closing *)
  | HK_end of string
  | HK_comment
  | HK_text

type html_tok = { hk : html_tok_kind; h_off : int; h_len : int }

(* void elements: no content, no end tag *)
let html_void =
  [ "area"; "base"; "br"; "col"; "embed"; "hr"; "img"; "input"; "link"; "meta";
    "param"; "source"; "track"; "wbr" ]

(* elements whose end tag the HTML spec allows to be OMITTED. Leaving one open
   is not a defect: every renderer closes it implicitly, and the two-tier
   standard says a construct that renders correctly is acceptable. *)
let html_optional_end =
  [ "html"; "head"; "body"; "p"; "li"; "dt"; "dd"; "rt"; "rp"; "optgroup";
    "option"; "colgroup"; "caption"; "thead"; "tbody"; "tfoot"; "tr"; "td"; "th" ]

(* elements whose content is TEXT, not markup, until their end tag *)
let html_raw_text = [ "script"; "style"; "textarea"; "title" ]

let is_alpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
let is_alnum c = is_alpha c || (c >= '0' && c <= '9')
let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012'
let lower_ascii s = String.lowercase_ascii s

(* TOTAL: every byte of [s] lands in exactly one token, in order. *)
let html_tokenize (s : string) : html_tok list =
  let n = String.length s in
  let out = ref [] and i = ref 0 and raw = ref None in
  let emit hk off len = if len > 0 then out := { hk; h_off = off; h_len = len } :: !out in
  while !i < n do
    match !raw with
    | Some name ->
        (* raw text runs to the matching end tag, or to EOF if there is none *)
        let start = !i and ln = String.length name in
        let j = ref !i and stop = ref n and found = ref false in
        while (not !found) && !j + 1 < n do
          if s.[!j] = '<' && s.[!j + 1] = '/' && !j + 2 + ln <= n
             && lower_ascii (String.sub s (!j + 2) ln) = name
          then (found := true; stop := !j)
          else incr j
        done;
        emit HK_text start (!stop - start);
        i := !stop;
        raw := None
    | None ->
        if s.[!i] <> '<' then begin
          let start = !i in
          while !i < n && s.[!i] <> '<' do incr i done;
          emit HK_text start (!i - start)
        end
        else if !i + 3 < n && s.[!i + 1] = '!' && s.[!i + 2] = '-' && s.[!i + 3] = '-' then begin
          let j = ref (!i + 4) and stop = ref n and found = ref false in
          while (not !found) && !j + 2 < n do
            if s.[!j] = '-' && s.[!j + 1] = '-' && s.[!j + 2] = '>' then
              (found := true; stop := !j + 3)
            else incr j
          done;
          emit HK_comment !i (!stop - !i);
          i := !stop
        end
        else if !i + 1 < n && s.[!i + 1] = '!' then begin
          let j = ref (!i + 2) in
          while !j < n && s.[!j] <> '>' do incr j done;
          let stop = min n (!j + 1) in
          emit HK_doctype !i (stop - !i);
          i := stop
        end
        else if !i + 2 < n && s.[!i + 1] = '/' && is_alpha s.[!i + 2] then begin
          let j = ref (!i + 2) in
          while !j < n && is_alnum s.[!j] do incr j done;
          let name = lower_ascii (String.sub s (!i + 2) (!j - (!i + 2))) in
          while !j < n && s.[!j] <> '>' do incr j done;
          let stop = min n (!j + 1) in
          emit (HK_end name) !i (stop - !i);
          i := stop
        end
        else if !i + 1 < n && is_alpha s.[!i + 1] then begin
          let j = ref (!i + 1) in
          while !j < n && is_alnum s.[!j] do incr j done;
          let name = lower_ascii (String.sub s (!i + 1) (!j - (!i + 1))) in
          let attrs = ref [] and self = ref false and fin = ref false in
          while (not !fin) && !j < n do
            while !j < n && is_space s.[!j] do incr j done;
            if !j >= n then fin := true
            else if s.[!j] = '>' then (incr j; fin := true)
            else if s.[!j] = '/' then
              if !j + 1 < n && s.[!j + 1] = '>' then (self := true; j := !j + 2; fin := true)
              else incr j
            else begin
              let ns = !j in
              while !j < n && (not (is_space s.[!j])) && s.[!j] <> '=' && s.[!j] <> '>'
                    && s.[!j] <> '/' do incr j done;
              let aname = lower_ascii (String.sub s ns (!j - ns)) in
              let save = !j in
              while !j < n && is_space s.[!j] do incr j done;
              let aval =
                if !j < n && s.[!j] = '=' then begin
                  incr j;
                  while !j < n && is_space s.[!j] do incr j done;
                  if !j < n && (s.[!j] = '"' || s.[!j] = '\'') then begin
                    (* a quoted value may contain '>' and newlines — the whole
                       reason a scan-to-'>' tokenizer misreads real pages *)
                    let q = s.[!j] in
                    incr j;
                    let vs = !j in
                    while !j < n && s.[!j] <> q do incr j done;
                    let v = String.sub s vs (!j - vs) in
                    if !j < n then incr j;
                    v
                  end
                  else begin
                    let vs = !j in
                    while !j < n && (not (is_space s.[!j])) && s.[!j] <> '>' do incr j done;
                    String.sub s vs (!j - vs)
                  end
                end
                else (j := save; "")
              in
              if aname = "" then (if !j < n && !j = ns then incr j)
              else attrs := (aname, aval) :: !attrs
            end
          done;
          emit (HK_start (name, List.rev !attrs, !self)) !i (!j - !i);
          i := !j;
          if (not !self) && List.mem name html_raw_text then raw := Some name
        end
        else begin
          (* a literal '<' that opens nothing *)
          emit HK_text !i 1;
          incr i
        end
  done;
  List.rev !out

let html_tok_source (s : string) (t : html_tok) : string = String.sub s t.h_off t.h_len

let line_of_offset (s : string) (off : int) : int =
  let stop = min off (String.length s) in
  let c = ref 1 in
  for k = 0 to stop - 1 do
    if s.[k] = '\n' then incr c
  done;
  !c

let html_starts (toks : html_tok list) =
  List.filter_map
    (fun t -> match t.hk with HK_start (n, a, sc) -> Some (t, n, a, sc) | _ -> None)
    toks

let starts_with (s : string) (p : string) =
  String.length s >= String.length p && String.sub s 0 (String.length p) = p

(* A value that makes the page reach the network at RENDER time. Protocol
   relative `//host` counts: it inherits the page's scheme and is still remote. *)
let html_remote_value (v : string) : bool =
  let v = lower_ascii (String.trim v) in
  starts_with v "http://" || starts_with v "https://" || starts_with v "//"

(* attribute that LOADS a resource, per element. `a href` is a navigation
   target, not a runtime asset, and must never be flagged. *)
let html_resource_attr (elem : string) (attr : string) (attrs : (string * string) list) : bool =
  match (elem, attr) with
  | ("script", "src") | ("img", "src") | ("iframe", "src") | ("video", "src")
  | ("audio", "src") | ("source", "src") | ("track", "src") | ("embed", "src")
  | ("input", "src") | ("video", "poster") | ("object", "data")
  | ("image", "href") | ("use", "href") | ("image", "xlink:href") | ("use", "xlink:href") ->
      true
  | ("link", "href") ->
      let rel = lower_ascii (try List.assoc "rel" attrs with Not_found -> "") in
      List.exists (fun r -> contains rel r)
        [ "stylesheet"; "icon"; "preload"; "prefetch"; "manifest"; "preconnect"; "dns-prefetch" ]
  | _ -> false

(* CSS reaches the network too: url(...) and @import. Scanned over style
   element text and style attribute values. *)
let css_remote_urls (css : string) : bool =
  let low = lower_ascii css in
  let n = String.length low in
  let hit = ref false and i = ref 0 in
  while (not !hit) && !i < n do
    if matches_at low !i "url(" then begin
      let j = ref (!i + 4) in
      while !j < n && (is_space low.[!j] || low.[!j] = '"' || low.[!j] = '\'') do incr j done;
      if html_remote_value (String.sub low !j (min 8 (n - !j))) then hit := true;
      i := !j
    end
    else if matches_at low !i "@import" then begin
      let j = ref (!i + 7) in
      while !j < n && (is_space low.[!j] || low.[!j] = '"' || low.[!j] = '\'') do incr j done;
      if matches_at low !j "url(" then j := !j + 4;
      while !j < n && (is_space low.[!j] || low.[!j] = '"' || low.[!j] = '\'') do incr j done;
      if html_remote_value (String.sub low !j (min 8 (n - !j))) then hit := true;
      i := !j
    end
    else incr i
  done;
  !hit

(* ---------- html rules ---------------------------------------------------- *)

(* Markup-only view: retained for the rules that still read raw bytes. The
   tokenizer makes it unnecessary for the rest — content inside a raw-text
   element or an escaped `<pre>` block is a TEXT token and can no longer be
   mistaken for markup, which is what this hack existed to prevent. *)
let markup_only (lower : string) : string =
  let n = String.length lower in
  let b = Bytes.of_string lower in
  let i = ref 0 in
  while !i < n do
    if matches_at lower !i "<pre" then begin
      let stop = ref !i in
      while !stop < n && not (matches_at lower !stop "</pre>") do incr stop done;
      let last = min n (!stop + 6) in
      for k = !i to last - 1 do Bytes.set b k ' ' done;
      i := last
    end
    else incr i
  done;
  Bytes.to_string b



let html_start_tag (d : doc) (name : string) : string option =
  let n = String.length d.lower in
  let pat = "<" ^ name in
  let lp = String.length pat in
  let rec find i =
    if i + lp > n then None
    else if matches_at d.lower i pat then begin
      let j = ref i in
      while !j < n && d.lower.[!j] <> '>' do incr j done;
      Some (String.sub d.lower i (min (!j + 1) n - i))
    end
    else find (i + 1)
  in
  find 0

let r_html_doctype =
  { id = "HTML-DOCTYPE"; applies = Html; sev = Error;
    title = "doctype present and first";
    why =
      "Without a leading doctype the browser falls into quirks mode and the \
       page renders by different rules than the one it was designed against.";
    remedy = "Put `<!doctype html>` as the first bytes of the file.";
    check = (fun d ->
      (* the first token that is neither whitespace nor a comment must be the
         doctype — which is what "first" means to a parser *)
      let rec first = function
        | [] -> None
        | (t : html_tok) :: tl -> (
            match t.hk with
            | HK_comment -> first tl
            | HK_text when String.trim (html_tok_source d.content t) = "" -> first tl
            | _ -> Some t)
      in
      match first (html_tokenize d.content) with
      | None -> [ (1, "document is empty") ]
      | Some t -> (
          match t.hk with
          | HK_doctype ->
              if starts_with (lower_ascii (html_tok_source d.content t)) "<!doctype html" then []
              else [ (line_of_offset d.content t.h_off, "declaration is not <!doctype html>") ]
          | _ ->
              [ (line_of_offset d.content t.h_off,
                 "content appears before the doctype: " ^ clip 40 (html_tok_source d.content t)) ])) }

let r_html_title =
  { id = "HTML-TITLE-REQUIRED"; applies = Html; sev = Error;
    title = "head carries a title";
    why =
      "`<title>` is required by the HTML spec and is what a reader sees in the \
       tab, a bookmark and every search result.";
    remedy = "Add a `<title>…</title>` inside `<head>`.";
    check = (fun d ->
      let names = List.map (fun (_, n, _, _) -> n) (html_starts (html_tokenize d.content)) in
      if List.mem "head" names && not (List.mem "title" names) then
        [ (0, "<head> has no <title> child") ]
      else []) }

let r_html_lang =
  { id = "HTML-LANG-REQUIRED"; applies = Html; sev = Warning;
    title = "html declares a language";
    why =
      "Screen readers choose pronunciation from `lang`; without it assistive \
       technology guesses.";
    remedy = "Write `<html lang=\"en\">`.";
    check = (fun d ->
      match
        List.find_opt (fun (_, n, _, _) -> n = "html") (html_starts (html_tokenize d.content))
      with
      | Some (t, _, attrs, _) when not (List.mem_assoc "lang" attrs) ->
          [ (line_of_offset d.content t.h_off, "<html> has no lang attribute") ]
      | _ -> []) }

let r_html_balance =
  { id = "HTML-TAG-BALANCE"; applies = Html; sev = Error;
    title = "structural tags balance";
    why =
      "An unclosed container silently swallows the rest of the page; a \
       published journal can lose half its content and still look plausible.";
    remedy = "Close the tag named in the message.";
    check = (fun d ->
      (* A STACK, not a pair of counters. Counting `<html` against `</html>`
         over raw bytes counts the occurrences inside comments, scripts and
         attribute values, and it cannot tell `<main>…</main><main>` from
         `<main><main>…</main>` — two opens and two closes either way. The stack
         also reports WHERE, which a count never can.

         Elements whose end tag the spec allows to be omitted are skipped: the
         browser closes them and the page is correct, which is the authored
         standard. *)
      let requires name = not (List.mem name html_void || List.mem name html_optional_end) in
      let stack = ref [] and out = ref [] in
      List.iter
        (fun (t : html_tok) ->
          match t.hk with
          | HK_start (name, _, self) ->
              if (not self) && not (List.mem name html_void) then stack := (name, t.h_off) :: !stack
          | HK_end name ->
              if not (List.mem name html_void) then
                if List.exists (fun (n, _) -> n = name) !stack then begin
                  (* pop to the match; anything popped on the way was left open *)
                  let rec pop = function
                    | [] -> []
                    | (n, off) :: tl ->
                        if n = name then tl
                        else begin
                          if requires n then
                            out :=
                              (line_of_offset d.content off,
                               Printf.sprintf "<%s> is still open at </%s>" n name)
                              :: !out;
                          pop tl
                        end
                  in
                  stack := pop !stack
                end
                else if requires name then
                  out :=
                    (line_of_offset d.content t.h_off,
                     Printf.sprintf "</%s> closes nothing that is open" name)
                    :: !out
          | _ -> ())
        (html_tokenize d.content);
      List.iter
        (fun (n, off) ->
          if requires n then
            out :=
              (line_of_offset d.content off, Printf.sprintf "<%s> is never closed" n) :: !out)
        !stack;
      List.rev !out) }

let r_html_self_contained =
  { id = "HTML-SELF-CONTAINED"; applies = Html; sev = Error;
    title = "no remote runtime resource";
    why =
      "The journal contract requires an archival page to render with no \
       network. A remote script or stylesheet is VALID HTML — no conformance \
       checker will ever flag it — so this rule is the only thing enforcing it.";
    remedy = "Inline the asset, or embed it as a data: URI.";
    check = (fun d ->
      (* Over ATTRIBUTES, not bytes. The needle list this replaces matched six
         exact spellings and missed every other one: extra whitespace, uppercase
         SRC, unquoted values, protocol-relative //cdn, and every element that
         loads a resource other than script/link/img. It also could not tell
         `<a href="http…">` — a navigation target, which is fine — from a
         runtime asset, so the needles had to avoid `href` almost entirely. *)
      let out = ref [] in
      let toks = html_tokenize d.content in
      List.iter
        (fun ((t : html_tok), elem, attrs, _) ->
          List.iter
            (fun (a, v) ->
              if html_resource_attr elem a attrs && html_remote_value v then
                out :=
                  (line_of_offset d.content t.h_off,
                   Printf.sprintf "remote runtime resource: <%s %s=\"%s\">" elem a (clip 60 v))
                  :: !out
              else if a = "style" && css_remote_urls v then
                out :=
                  (line_of_offset d.content t.h_off,
                   Printf.sprintf "remote resource in a style attribute on <%s>" elem)
                  :: !out)
            attrs)
        (html_starts toks);
      (* CSS inside <style> reaches the network the same way *)
      let rec scan_style = function
        | (a : html_tok) :: (b : html_tok) :: tl -> (
            match (a.hk, b.hk) with
            | HK_start ("style", _, false), HK_text ->
                if css_remote_urls (html_tok_source d.content b) then
                  out :=
                    (line_of_offset d.content b.h_off, "remote resource in a <style> block") :: !out;
                scan_style (b :: tl)
            | _ -> scan_style (b :: tl))
        | _ -> ()
      in
      scan_style toks;
      List.rev !out) }

let r_html_data_uri =
  { id = "HTML-DATA-URI-INTACT"; applies = Html; sev = Error;
    title = "data: URIs contain no whitespace";
    why =
      "A line break inside a data: URI breaks the embedded asset silently — \
       the page still loads, the image just never appears.";
    remedy = "Emit the data: URI on one line with no wrapping.";
    check = (fun d ->
      (* Over attribute VALUES. The byte scanner needed a "preceded by a quote
         or a paren" heuristic to avoid reading the prose token `mono-data:
         monospace` as a URI — 7 false positives on the real corpus. A tokenizer
         does not need the heuristic: an attribute value is an attribute value,
         and prose is a text token. *)
      let out = ref [] in
      let toks = html_tokenize d.content in
      let bad v = contains v "data:" && String.exists (fun c -> is_space c) v in
      List.iter
        (fun ((t : html_tok), elem, attrs, _) ->
          List.iter
            (fun (a, v) ->
              if bad (lower_ascii v) then
                out :=
                  (line_of_offset d.content t.h_off,
                   Printf.sprintf "whitespace inside a data: URI in <%s %s>" elem a)
                  :: !out)
            attrs)
        (html_starts toks);
      (* and inside CSS, where a wrapped url(data:…) fails the same way *)
      let rec scan = function
        | (a : html_tok) :: (b : html_tok) :: tl -> (
            match (a.hk, b.hk) with
            | HK_start ("style", _, false), HK_text ->
                let css = lower_ascii (html_tok_source d.content b) in
                let n = String.length css in
                let i = ref 0 in
                while !i < n do
                  if matches_at css !i "url(" then begin
                    let j = ref (!i + 4) and stop = ref false and broke = ref false in
                    while (not !stop) && !j < n do
                      (match css.[!j] with
                       | ')' -> stop := true
                       | c when is_space c -> broke := true
                       | _ -> ());
                      incr j
                    done;
                    if !broke && contains (String.sub css !i (min (!j - !i) (n - !i))) "data:" then
                      out :=
                        (line_of_offset d.content (b.h_off + !i),
                         "whitespace inside a data: URI in a <style> block")
                        :: !out;
                    i := !j
                  end
                  else incr i
                done;
                scan (b :: tl)
            | _ -> scan (b :: tl))
        | _ -> ()
      in
      scan toks;
      match List.rev !out with [] -> [] | x :: _ -> [ x ] (* one per document *)) }

let r_html_comment_unclosed =
  { id = "HTML-COMMENT-UNCLOSED"; applies = Html; sev = Error;
    title = "comments are terminated";
    why =
      "An unterminated `<!--` swallows the entire remainder of the document: \
       the page still loads and still looks plausible, it is simply missing \
       everything after that point. Invisible to a byte scanner, which has no \
       notion of where a comment ends.";
    remedy = "Close the comment with -->.";
    check = (fun d ->
      List.filter_map
        (fun (t : html_tok) ->
          match t.hk with
          | HK_comment ->
              let src = html_tok_source d.content t in
              let n = String.length src in
              if n >= 3 && String.sub src (n - 3) 3 = "-->" then None
              else
                Some (line_of_offset d.content t.h_off,
                      "comment is never closed — it swallows the rest of the document")
          | _ -> None)
        (html_tokenize d.content)) }

let r_html_attr_duplicate =
  { id = "HTML-ATTR-DUPLICATE"; applies = Html; sev = Warning;
    title = "an attribute appears once per tag";
    why =
      "A parser keeps the FIRST occurrence and silently drops the rest, so the \
       value a reader sees in the source is not the value that takes effect. \
       Valid enough to render, which is why nothing else reports it.";
    remedy = "Remove the duplicate, keeping the value that is meant to apply.";
    check = (fun d ->
      List.filter_map
        (fun ((t : html_tok), elem, attrs, _) ->
          let names = List.map fst attrs in
          let dup =
            List.find_opt
              (fun a -> List.length (List.filter (fun b -> a = b) names) > 1)
              (List.sort_uniq compare names)
          in
          match dup with
          | Some a ->
              Some (line_of_offset d.content t.h_off,
                    Printf.sprintf "<%s> repeats the attribute %s — only the first takes effect" elem a)
          | None -> None)
        (html_starts (html_tokenize d.content))) }

let r_html_heading_levels =
  { id = "HTML-HEADING-LEVELS"; applies = Html; sev = Warning;
    title = "heading levels do not skip";
    why =
      "Assistive technology builds the document outline from heading levels; a \
       jump from h2 to h4 presents a section as nested under nothing.";
    remedy = "Use the next level down, or restructure the section.";
    check = (fun d ->
      (* From START TOKENS. The byte scanner counted `<h2` wherever it appeared
         — inside a comment, inside a `<script>` string, inside an escaped code
         sample — so a page that DOCUMENTS heading structure tripped on its own
         examples. *)
      let out = ref [] and prev = ref 0 in
      List.iter
        (fun ((t : html_tok), name, _, _) ->
          if String.length name = 2 && name.[0] = 'h'
             && (match name.[1] with '1' .. '6' -> true | _ -> false)
          then begin
            let lvl = Char.code name.[1] - Char.code '0' in
            if !prev > 0 && lvl > !prev + 1 then
              out :=
                (line_of_offset d.content t.h_off,
                 Printf.sprintf "heading jumps h%d -> h%d" !prev lvl)
                :: !out;
            prev := lvl
          end)
        (html_starts (html_tokenize d.content));
      match List.rev !out with [] -> [] | x :: _ -> [ x ]) }


(* ---------- zettelkasten rules (kind = Markdown, scoped by path) ---------- *)

let is_zk (d : doc) =
  String.length d.path >= 8 && String.sub d.path 0 8 = "docs/zk/"

let r_zk_frontmatter =
  { id = "ZK-FRONTMATTER"; applies = Markdown; sev = Error;
    title = "a Zettelkasten note carries its identity frontmatter";
    why =
      "A note without a stable id and status cannot be linked, aged, or \
       verified; it becomes an orphan the currency loop cannot reason about.";
    remedy = "Open the note with a --- block carrying id, status and verified_by.";
    check = (fun d ->
      if not (is_zk d) then []
      else
        match d.lines with
        | first :: rest when String.trim first = "---" ->
            (* scan the WHOLE frontmatter block, not a fixed head window: a
               first draft looked at 12 lines and reported a note whose
               verified_by sat on line 13. *)
            let rec upto_close acc = function
              | [] -> List.rev acc
              | l :: _ when String.trim l = "---" -> List.rev acc
              | l :: tl -> upto_close (l :: acc) tl
            in
            let head = String.concat "\n" (upto_close [] rest) in
            let missing =
              List.filter (fun k -> not (contains head (k ^ ":")))
                [ "id"; "status"; "verified_by" ]
            in
            if missing = [] then []
            else [ (1, "frontmatter is missing: " ^ String.concat ", " missing) ]
        | _ -> [ (1, "note does not open with a --- frontmatter block") ]) }

let r_zk_empty_wikilink =
  { id = "ZK-EMPTY-WIKILINK"; applies = Markdown; sev = Warning;
    title = "no empty wikilink";
    why =
      "`[[]]` resolves to nothing and is invisible in rendered output — a link \
       that silently goes nowhere. Target resolution itself belongs to \
       --wiki-audit, which owns the slug set; this only catches the empty form.";
    remedy = "Give the link a target, or remove the brackets.";
    check = (fun d ->
      List.filter_map
        (fun (n, l) -> if contains l "[[]]" then Some (n, "empty wikilink [[]]") else None)
        (List.mapi (fun i l -> (i + 1, l)) d.lines)) }

(* ---------- bonsai rules (kind = Ocaml, scoped by content) ----------------

   Bonsai is an INCREMENTAL UI framework: you build a dependency graph once and
   it recomputes only what changed. Every rule here catches a way of using it
   that silently opts out of that — paying the framework's cost without its
   benefit — or that routes around the type system it is built on.

   They are grounded in this repository's own frontend, not in taste. The
   census that produced them is in the guide; the short version is that
   `harness/ui_web/main.ml` binds 25 separate states, bundles them into a
   positional list, and consumes the whole bundle in one ~360-line map.

   SEVERITY — deliberately `Info`. A new rule family over an existing
   5,000-line codebase lands ADVISORY: the findings are printed in full on
   every run and counted in the KPI, but they do not move the errors/warnings
   ratchet, which stays at zero. Nothing is hidden and nothing is excluded;
   the backlog is visible and its closing slice is named in the guide. The
   promotion trigger is stated there too: once the frontend refactor lands,
   these become warnings. Landing them as warnings today would have meant
   either raising a ceiling that is at zero, or blocking on a 2,000-line
   refactor — the first dishonest, the second unrelated to knowing the defect
   exists. *)

(* Every needle below is concatenation-split so THIS file does not match its own
   rules. Without it the first corpus run reported four findings against these
   very definitions — the seventh instance of the self-reference hazard in this
   programme, and the same convention the database-access guard and the
   report-only law already use (CAST-20260805-lint-obs-scanner-literal). *)
let bonsai_ns = "Bon" ^ "sai."
let bonsai_state_tok = bonsai_ns ^ "state "
let bonsai_state_str_tok = bonsai_ns ^ "state \""
let bonsai_all_tok = bonsai_ns ^ "all"
let bonsai_map_tok = bonsai_ns ^ "map "

let uses_bonsai (d : doc) = contains d.content bonsai_ns

(* count occurrences of a token at the start of an expression, ignoring
   comments is NOT attempted — this is a census, and it says so *)
let count_occurrences (hay : string) (needle : string) : int = count_of hay needle

let r_bonsai_state_explosion =
  { id = "BONSAI-STATE-EXPLOSION"; applies = Ocaml; sev = Info;
    title = "a component does not bind a dozen separate states";
    why =
      "Each `Bonsai.state` is an independent node in the incremental graph. A \
       component with dozens of them has no single model to reason about, no \
       place to put an invariant that spans two fields, and no way to make an \
       impossible combination unrepresentable. One state machine over a record \
       says the same thing with the compiler on your side.";
    remedy =
      "Collapse related states into one record model behind `state_machine`, \
       with a pure `apply_action` you can unit-test without a browser.";
    check = (fun d ->
      if not (uses_bonsai d) then []
      else
        let n = count_occurrences d.content bonsai_state_tok in
        if n > 8 then
          [ (0, Printf.sprintf
                 "%d separate Bonsai.state bindings — collapse related fields into one record model"
                 n) ]
        else []) }

let r_bonsai_positional_bundle =
  { id = "BONSAI-POSITIONAL-BUNDLE"; applies = Ocaml; sev = Info;
    title = "state is not bundled into a positional list";
    why =
      "Bundling with `all` over a list of `both` pairs produces a LIST, so the \
       only thing distinguishing one state from another is its position. The \
       destructuring pattern is not exhaustive, which forces a catch-all arm; \
       reordering two entries is then a type-correct, silent behavioural \
       change, and adding one degrades the view at runtime instead of failing \
       to compile.";
    remedy =
      "Bundle into a record or a tuple whose components have distinct types, \
       or return a typed model from a single state machine.";
    check = (fun d ->
      if not (uses_bonsai d) then []
      else
        List.filter_map
          (fun (n, l) ->
            if contains l bonsai_all_tok then
              Some (n, bonsai_all_tok ^ " over a list of `both`s — position, not type, distinguishes these states")
            else None)
          (List.mapi (fun i l -> (i + 1, l)) d.lines)) }

let r_bonsai_stringly_state =
  { id = "BONSAI-STRINGLY-STATE"; applies = Ocaml; sev = Info;
    title = "state carries its parsed type, not a string";
    why =
      "A state initialised to a numeric string is re-parsed on every read, \
       usually with a swallow-the-error fallback, so a malformed value becomes \
       a silent default instead of an impossible state. The model should carry \
       the type the domain already defines.";
    remedy =
      "Give the state its real type (float, int, a variant) and parse once at \
       the edge where the string enters.";
    check = (fun d ->
      if not (uses_bonsai d) then []
      else
        List.filter_map
          (fun (n, l) ->
            (* a state bound to a quoted numeric literal such as "0.0" or "1" *)
            if contains l bonsai_state_str_tok then begin
              let numericish = ref false in
              let i = ref 0 and len = String.length l in
              while !i < len - 1 do
                if l.[!i] = '"' then begin
                  let j = ref (!i + 1) and digits = ref 0 and other = ref 0 in
                  while !j < len && l.[!j] <> '"' do
                    (match l.[!j] with
                     | '0' .. '9' -> incr digits
                     | '.' | '-' -> ()
                     | _ -> incr other);
                    incr j
                  done;
                  if !digits > 0 && !other = 0 then numericish := true;
                  i := !j
                end
                else incr i
              done;
              if !numericish then
                Some (n, "state initialised to a numeric STRING — carry the parsed type in the model")
              else None
            end
            else None)
          (List.mapi (fun i l -> (i + 1, l)) d.lines)) }

let r_bonsai_monolithic_map =
  { id = "BONSAI-MONOLITHIC-MAP"; applies = Ocaml; sev = Info;
    title = "a map over state does not span hundreds of lines";
    why =
      "The dependency graph IS the performance model: a map consumes every \
       input it is given, so a single large map over the whole state means any \
       one change — a keystroke, a camera nudge — recomputes all of it. This \
       is opting out of incrementality while still paying for it.";
    remedy =
      "Split the view into components that each depend on the state they \
       actually read, so an unrelated change cannot invalidate them.";
    check = (fun d ->
      if not (uses_bonsai d) then []
      else begin
        (* SIZE, stated as size: the distance from a `Bonsai.map` to the next
           top-level definition. Not a semantic claim about the body. *)
        let arr = Array.of_list d.lines in
        let n = Array.length arr in
        let out = ref [] in
        for i = 0 to n - 1 do
          if contains arr.(i) bonsai_map_tok then begin
            let j = ref (i + 1) in
            while
              !j < n
              && not
                   (String.length arr.(!j) > 4
                   && String.sub arr.(!j) 0 4 = "let "
                   && not (contains arr.(!j) bonsai_map_tok))
            do incr j done;
            let span = !j - i in
            if span > 120 then
              out := (i + 1, Printf.sprintf "a Bonsai.map spanning %d lines — every input recomputes all of it" span) :: !out
          end
        done;
        List.rev !out
      end) }

(* ---------- json rules ---------------------------------------------------- *)

let r_json_well_formed =
  { id = "JSON-WELL-FORMED"; applies = Json; sev = Error;
    title = "the document parses as JSON";
    why =
      "A generated manifest that no longer parses silently stops feeding every \
       consumer downstream — the registry still exists, it just answers nothing.";
    remedy = "Fix the syntax error at the reported position and regenerate.";
    check = (fun d ->
      match Yojson.Safe.from_string d.content with
      | _ -> []
      | exception Yojson.Json_error m -> [ (0, "does not parse: " ^ clip 90 m) ]
      | exception e -> [ (0, "does not parse: " ^ clip 90 (Printexc.to_string e)) ]) }

(* ---------- zig rules ----------------------------------------------------- *)

let r_zig_module_doc =
  { id = "ZIG-MODULE-DOC"; applies = Zig; sev = Warning;
    title = "a Zig module opens with its specification doc-comment";
    why =
      "This repository's doctrine is that a module's doc-comment IS its \
       specification: signature, semantic domain, encodings, laws, scope. A \
       module without one has no stated meaning to verify against.";
    remedy = "Add a //! module doc-comment stating domain, encodings and laws.";
    check = (fun d ->
      match List.find_opt (fun l -> String.trim l <> "") d.lines with
      | Some first when String.length (ltrim first) >= 3 && String.sub (ltrim first) 0 3 = "//!" -> []
      | Some _ -> [ (1, "module does not open with a //! doc-comment") ]
      | None -> [ (0, "module is empty") ]) }

(* ---------- ocaml rules --------------------------------------------------- *)

(* OCaml lexical structure is deliberately NOT re-checked here.

   A first draft added ML-COMMENT-BALANCE, a scanner for unterminated comment
   openers. Run over the real corpus it reported harness/sa_plan/sa_plan_store.ml
   — a file that compiles. It uses 30 quoted-string literals of the brace-bar
   form and 8 char literals containing a double quote, both of which a naive
   scanner mishandles. The OCaml compiler is the AUTHORITATIVE oracle for this
   property and it runs before this linter ever does, so the rule could only
   contribute false positives. Removed rather than patched.

   Writing that removal note broke the build once, because the note itself
   contained a comment opener: the scanner-about-scanners hazard, recorded here
   because it is the same class the linter exists to catch.

   The .ml/.mli corpus is still walked and counted, so coverage stays honest
   about what it is. *)

(* A second draft proposed ML-MODULE-HEADER: an authored module should open with
   a header comment. Run over the real corpus it fired on 405 of ~450 files.
   That is not a defect rate, it is a convention this repository does not have —
   the rule was measuring an assumption rather than the codebase. Removed.

   Net result for OCaml: the corpus is walked and counted, and NO rule currently
   applies. Stated plainly so that coverage is never read as enforcement. *)

(* ---------- the registry: the ONLY extension port ------------------------ *)

let registry : rule list =
  [ r_md_title_first; r_md_welded_heading; r_md_fence_balanced; r_md_table_columns;
    r_md_table_delimiter; r_md_table_split; r_md_table_row_wrapped;
    r_html_doctype; r_html_title; r_html_lang; r_html_balance;
    r_html_self_contained; r_html_data_uri; r_html_heading_levels;
    r_html_comment_unclosed; r_html_attr_duplicate;
    r_zk_frontmatter; r_zk_empty_wikilink;
    r_json_well_formed; r_zig_module_doc;
    r_bonsai_state_explosion; r_bonsai_positional_bundle;
    r_bonsai_stringly_state; r_bonsai_monolithic_map ]

(* ---------- evaluation --------------------------------------------------- *)

(* PROVENANCE — the two-tier standard.

   An authored document is held to what a renderer actually does with it: a
   defect matters when the page LOSES or CORRUPTS content, and a construct that
   renders differently than the author imagined is advisory. A GENERATED
   artifact is held to strict correctness, because there is no author to have
   imagined anything — a malformed generated table is a bug in the generator,
   and shipping it would be this programme publishing markup it forbids.

   So severity is a function of provenance: every finding on a generated
   artifact is an Error, no ratchet, no exceptions. Detection is by the
   generation marker the generators themselves write, plus the generated trees,
   so a new generator inherits the strict standard without being enumerated
   here. *)
let generated_markers =
  [ "generated by"; "do not edit"; "auto-generated"; "autogenerated";
    "drafted by the harness"; "@generated" ]

let generated_prefixes =
  [ "docs/design/lint/"; "web/dist/"; "generated/"; "docs/zk/moc-"; "docs/ontology/" ]

let is_generated_path (path : string) : bool =
  List.exists
    (fun p -> String.length path >= String.length p && String.sub path 0 (String.length p) = p)
    generated_prefixes

let detect_generated (path : string) (content : string) : bool =
  is_generated_path path
  || begin
       (* only the head of the document counts: a marker deep in prose is a
          discussion of generation, not a declaration of it *)
       let head =
         let n = min (String.length content) 2000 in
         String.lowercase_ascii (String.sub content 0 n)
       in
       List.exists (contains head) generated_markers
     end

let make_doc path kind content =
  { path; kind; content;
    lines = String.split_on_char '\n' content;
    lower = String.lowercase_ascii content;
    generated = detect_generated path content }

(* TOTAL: a raising rule becomes a finding about the rule, never a crash. *)
let run_rule (r : rule) (d : doc) : finding list * float =
  if r.applies <> d.kind then ([], 0.)
  else begin
    let t0 = Unix.gettimeofday () in
    let res =
      try
        List.map
          (fun (line, message) ->
            { rule_id = r.id;
              (* strict-when-generated: see PROVENANCE above *)
              severity = (if d.generated then Error else r.sev);
              path = d.path; line; message })
          (r.check d)
      with e ->
        [ { rule_id = r.id; severity = Error; path = d.path; line = 0;
            message = "rule raised: " ^ Printexc.to_string e } ]
    in
    (res, Unix.gettimeofday () -. t0)
  end

let lint_doc (rules : rule list) (d : doc) : report =
  List.fold_left
    (fun acc r ->
      let fs, ms = run_rule r d in
      merge acc { empty_report with findings = fs; rule_ms = [ (r.id, ms) ] })
    { empty_report with files = 1; bytes = String.length d.content;
      lines_total = List.length d.lines }
    rules

let lint (rules : rule list) (docs : doc list) : report =
  List.fold_left (fun acc d -> merge acc (lint_doc rules d)) empty_report docs

(* ---------- bounded parallel interpretation ------------------------------

   The corpus fold is embarrassingly parallel: rules are pure, documents are
   independent, and `merge` is associative. Per the repository's Approach-B
   doctrine the SEQUENTIAL interpretation remains the ORACLE, and this final
   encoding is admitted only by observational equivalence with it.

   Determinism is preserved exactly, not merely up to reordering: each document
   writes its own slot in an array and the folds happen in INDEX order, so the
   findings list is byte-identical to the sequential one. The observation that
   legitimately differs is per-rule wall time, which is contended under
   parallelism; the equality law therefore compares the observational
   projection (findings and counts) and deliberately excludes timings. *)

let observational (r : report) =
  (List.map (fun (f : finding) -> (f.rule_id, f.path, f.line, f.message)) r.findings,
   r.files, r.bytes, r.lines_total)

let lint_parallel ?(domains = 0) (rules : rule list) (docs : doc list) : report =
  let darr = Array.of_list docs in
  let rarr = Array.of_list rules in
  let nd = Array.length darr and nr = Array.length rarr in
  let want = if domains > 0 then domains else Domain.recommended_domain_count () in
  if nd = 0 || nr = 0 || want <= 1 || nd * nr < 2 then lint rules docs
  else begin
    (* The work unit is a (document, rule) PAIR, not a document.
       Document-level parallelism was measured at only 1.17x on 10 domains
       because one 10.8 MB artifact dominates the critical path: all 15 of its
       rules ran on a single domain. Splitting per pair lets that one file's
       rules spread across every domain, which is where the remaining speedup
       lives (Amdahl on the largest document).

       Determinism is exact. Each pair writes its own slot, and the fold walks
       documents in order and rules in registry order — the same order the
       sequential encoding produces — so the findings list is byte-identical
       whatever order the domains happen to finish in. *)
    let total = nd * nr in
    let cell = Array.make total empty_report in
    (* longest-processing-time-first: biggest documents dispatched first *)
    let order =
      Array.init total (fun k -> k)
      |> Array.to_list
      |> List.sort (fun a b ->
             compare
               (String.length darr.(b / nr).content)
               (String.length darr.(a / nr).content))
      |> Array.of_list
    in
    let pool = Domainslib.Task.setup_pool ~num_domains:(want - 1) () in
    Fun.protect
      ~finally:(fun () -> Domainslib.Task.teardown_pool pool)
      (fun () ->
        Domainslib.Task.run pool (fun () ->
            Domainslib.Task.parallel_for pool ~chunk_size:1 ~start:0
              ~finish:(total - 1)
              ~body:(fun p ->
                let k = order.(p) in
                let d = darr.(k / nr) and r = rarr.(k mod nr) in
                let fs, ms = run_rule r d in
                cell.(k) <- { empty_report with findings = fs; rule_ms = [ (r.id, ms) ] })));
    (* per-document header (files/bytes/lines) folded in document order, then
       that document's rule cells in registry order *)
    let acc = ref empty_report in
    for i = 0 to nd - 1 do
      acc :=
        merge !acc
          { empty_report with files = 1; bytes = String.length darr.(i).content;
            lines_total = List.length darr.(i).lines };
      for j = 0 to nr - 1 do
        acc := merge !acc cell.((i * nr) + j)
      done
    done;
    !acc
  end

(* ---------- KPIs --------------------------------------------------------- *)

type kpi = {
  k_files : int;
  k_clean : int;
  k_bytes : int;
  k_lines : int;
  k_errors : int;
  k_warnings : int;
  k_infos : int;
  k_per_kloc : float;
  k_clean_ratio : float;
  k_by_rule : (string * int) list;
  k_slowest : (string * float) list;
}

let kpis (rep : report) : kpi =
  let count s = List.length (List.filter (fun f -> f.severity = s) rep.findings) in
  let dirty =
    List.sort_uniq compare (List.map (fun (f : finding) -> f.path) rep.findings) |> List.length
  in
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun f ->
      Hashtbl.replace tbl f.rule_id (1 + (try Hashtbl.find tbl f.rule_id with Not_found -> 0)))
    rep.findings;
  let by_rule =
    Hashtbl.fold (fun k v a -> (k, v) :: a) tbl []
    |> List.sort (fun (_, a) (_, b) -> compare b a)
  in
  let slowest =
    List.sort (fun (_, a) (_, b) -> compare b a) rep.rule_ms
    |> fun l -> if List.length l > 3 then List.filteri (fun i _ -> i < 3) l else l
  in
  { k_files = rep.files;
    k_clean = rep.files - dirty;
    k_bytes = rep.bytes;
    k_lines = rep.lines_total;
    k_errors = count Error;
    k_warnings = count Warning;
    k_infos = count Info;
    k_per_kloc =
      (if rep.lines_total = 0 then 0.
       else float_of_int (List.length rep.findings) /. (float_of_int rep.lines_total /. 1000.));
    k_clean_ratio =
      (if rep.files = 0 then 1. else float_of_int (rep.files - dirty) /. float_of_int rep.files);
    k_by_rule = by_rule;
    k_slowest = slowest }

let rule_catalogue () : string =
  let b = Buffer.create 2048 in
  List.iter
    (fun r ->
      Buffer.add_string b
        (Printf.sprintf "%-24s %-8s %s\n    why:    %s\n    remedy: %s\n" r.id
           (severity_name r.sev)
           (match r.applies with Markdown -> "[markdown]" | Html -> "[html]" | Json -> "[json]" | Zig -> "[zig]" | Ocaml -> "[ocaml]")
           r.why r.remedy))
    registry;
  Buffer.contents b
