(* Dual-source diagram checking for SC-DIAGRAM-001 / INV-JRN-06.

   THE DEFECT THIS REPLACES, measured 2026-09-13 by execution.

   `tools/journal_linter.ml` decided "an ASCII diagram is present" with a
   substring sweep that included `"|  "` -- a pipe followed by two spaces.
   Markdown table syntax contains that byte sequence whenever a cell is
   empty or right-aligned. Two falsifiers, both PASSING under the old
   check with no ASCII diagram anywhere in the document:

     | Col | Note |     <- empty cell:      "|  |"
     |---|---|
     | x |  |

     | Metric | Value |  <- right aligned:    "|   1 |"
     |---:|---:|
     |   1 |   2 |

   and it printed `SC-DIAGRAM-001 dual diagram source parity verified`.
   Co-presence of a fence and a punctuation pattern, announcing topology
   parity by name. An observable coarser than the property, again.

   WHAT THE MANDATE ASKS FOR, AND WHY IT CANNOT ALL BE CHECKED.

   INV-JRN-06 requires both forms to describe "identical topology" --
   same nodes, edges, labels, groupings. Surveyed over the 59 documents
   in docs/ and contracts/ that carry a mermaid block:

     arrow-list ASCII (`[A] --> [B]`) only :  0
     box-art ASCII    (`+---+`, `|`, box)  : 58
     both forms present                    :  1

   Box art is a PICTURE. Mermaid is a GRAPH. Reading an edge set out of
   2D line art requires tracing glyphs across rows and columns, and a
   tracer that guesses wrong is a NEW false-verdict source, subtler than
   the one being removed. Worse, the two forms in this corpus are not
   two encodings of one graph at all -- they are parallel prose. From
   contracts/rules/20260908-0912-provenance-integrity-contract.md the
   ASCII reads "EV-01 ..... EV-93" beside "outside the quarantined
   evidence range", while the mermaid node is labelled
   "EV-01 .. EV-93<br/>outside quarantined range<br/>no positive
   admission claim asserted here". Same meaning; different bytes. Exact
   label parity would FAIL that document, and that document is correct.

   So this module DOES NOT CLAIM to verify identical topology. It
   verifies what is mechanically decidable and NAMES THE REST AS
   UNVERIFIED. `Unverifiable_box_art` is a first-class verdict, not a
   pass: per SC-PROVENANCE-001's vocabulary UNKNOWN is nonpassing, and a
   checker that cannot see a property must say so rather than report the
   proxy it can see. That is the whole lesson of the defect above,
   applied to its own repair.

   Tightening the mandate to match the corpus, or the corpus to match the
   mandate, is a SOVEREIGN DECISION over a ratified contract and is
   deliberately not taken here. This module reports; the operator rules. *)

type ascii_kind =
  | Arrow_list       (** `[A] --> [B]` lines: an edge set is extractable *)
  | Box_art          (** 2D line art: a picture, not a graph *)
  | Table_only       (** Markdown table rows and nothing else -- THE DEFECT *)
  | Absent           (** no candidate ASCII diagram block at all *)

type verdict =
  | No_mermaid
      (** nothing to check; not a finding *)
  | Missing_ascii
      (** mermaid present, no ASCII diagram. A real failure. *)
  | Table_mistaken_for_diagram
      (** mermaid present and the only ASCII-ish content is a Markdown
          table. The old check PASSED this; it is a failure. *)
  | Edges_match of int
      (** arrow-list ASCII and mermaid agree on the edge set; count *)
  | Edges_differ of { only_ascii : string list; only_mermaid : string list }
      (** arrow-list ASCII and mermaid disagree. A real failure. *)
  | Unverifiable_naming of { ascii_edges : int; mermaid_edges : int }
      (** both sides are arrow lists, but their node vocabularies do not
          overlap, so no alignment exists. NOT a topology mismatch --
          calling it one would be a false FAIL. NONPASSING. *)
  | Unverifiable_box_art of { mermaid_edges : int }
      (** ASCII is box art. Co-presence holds; topology is NOT verified
          and this verdict says exactly that. NONPASSING. *)

(* ------------------------------------------------------------------ *)
(* fenced-block extraction                                            *)
(* ------------------------------------------------------------------ *)

let lines s = String.split_on_char '\n' s

let starts_with pre s =
  String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

let contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 then true
  else if nl > hl then false
  else
    let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
    go 0

(* Blocks fenced with ```<tag>. Returns each block's body. The fence walk
   is line-based and tracks open/close state, so a ``` inside a block
   closes it -- the same discipline Wiki_transclude uses, and the reason
   a regex over the whole file is wrong here. *)
let fenced_blocks ~tag body =
  let want = "```" ^ tag in
  let rec go acc cur inside = function
    | [] -> List.rev (if inside then String.concat "\n" (List.rev cur) :: acc else acc)
    | l :: rest ->
      let t = String.trim l in
      if inside then
        if starts_with "```" t then go (String.concat "\n" (List.rev cur) :: acc) [] false rest
        else go acc (l :: cur) true rest
      else if t = want || starts_with (want ^ " ") t then go acc [] true rest
      else go acc cur false rest
  in
  go [] [] false (lines body)

let mermaid_blocks body = fenced_blocks ~tag:"mermaid" body

(* ASCII diagram candidates: `text` and `ascii` fences are the two the
   diagram mandate names. A bare ``` fence is NOT accepted -- it is
   overwhelmingly code in this corpus, and admitting it is how a
   substring sweep starts drifting back toward the old defect. *)
let ascii_blocks body =
  fenced_blocks ~tag:"text" body @ fenced_blocks ~tag:"ascii" body

(* ------------------------------------------------------------------ *)
(* classification                                                     *)
(* ------------------------------------------------------------------ *)

let is_table_row l =
  let t = String.trim l in
  String.length t > 1 && t.[0] = '|'

let box_glyphs =
  [ "+--"; "+=="; "---+"; "|"; "\xe2\x94\x8c"; "\xe2\x94\x9c"; "\xe2\x94\x82";
    "\xe2\x94\x80"; "\xe2\x94\x94"; "\xe2\x94\xac"; "\xe2\x94\xbc"; "-->"; "<--" ]

(* Both arrow spellings occur in this corpus: `] --> [` in the generated
   plan diagrams and `] -> [` in the hand-authored contract flows. Missing
   the second is what made the first corpus run report
   contracts/rules/20260907-0811-hive-decision-forecast-kpi-mandate.md as
   having NO ascii diagram when it has a perfectly good arrow list. *)
let arrow_list_markers = [ "] --> ["; "] -> [" ]

let has_arrow_list block =
  List.exists
    (fun l -> List.exists (fun m -> contains l m) arrow_list_markers)
    (lines block)

(* A block of nothing but table rows and blank lines is a TABLE, however
   many box glyphs its padding happens to contain. This single predicate
   is the concrete bug fix: it is what the old `"|  "` sweep lacked. *)
let is_table_only block =
  let ls = List.filter (fun l -> String.trim l <> "") (lines block) in
  ls <> [] && List.for_all is_table_row ls

let classify_ascii blocks =
  match List.filter (fun b -> String.trim b <> "") blocks with
  | [] -> Absent
  | bs ->
    if List.exists has_arrow_list bs then Arrow_list
    else
      let non_table = List.filter (fun b -> not (is_table_only b)) bs in
      if non_table = [] then Table_only
      else
        (* A non-empty `text`/`ascii` fence that is not a table IS an authored
           diagram. Whether its topology is extractable is a separate
           question, answered by Arrow_list above; everything else is a
           picture. Returning Absent here would assert "no ASCII diagram" of
           a document that has one, which is a false FAIL -- the mirror image
           of the defect being repaired, and no more acceptable. *)
        Box_art

(* ------------------------------------------------------------------ *)
(* edge extraction                                                    *)
(* ------------------------------------------------------------------ *)

(* Strip a mermaid node decoration: A["x"] / A[x] / A(x) / A{x} / A((x)).
   Identity is the NODE ID, not the label, because the labels in this
   corpus legitimately differ in wording between the two forms while the
   graph is the same. Comparing ids compares topology; comparing labels
   would compare prose. *)
let node_id tok =
  let tok = String.trim tok in
  let n = String.length tok in
  let rec cut i =
    if i >= n then tok
    else match tok.[i] with
      | '[' | '(' | '{' -> String.sub tok 0 i
      | _ -> cut (i + 1)
  in
  String.trim (cut 0)

(* `A -->|why| B`: the edge LABEL sits between the arrow and the target, so
   the arrow splitter never sees a plain arrow and the edge was dropped
   silently. Measured by law L19. Strip the label segment first, then split:
   losing an edge is exactly the failure this module exists to catch, and a
   parser that drops edges would under-report a genuine mismatch. *)
let strip_edge_label l =
  let n = String.length l in
  let rec find i =
    if i + 1 >= n then None
    else if l.[i] = '>' && l.[i + 1] = '|' then Some (i + 1)
    else find (i + 1)
  in
  match find 0 with
  | None -> l
  | Some bar ->
    let rec close j = if j >= n then None else if l.[j] = '|' then Some j else close (j + 1) in
    (match close (bar + 1) with
     | None -> l
     | Some j -> String.sub l 0 bar ^ " " ^ String.sub l (j + 1) (n - j - 1))

let split_on_arrow l =
  let l = strip_edge_label l in
  let arrows = [ " --> "; " ---> "; " ==> "; " -.-> "; " --- "; " -> " ] in
  let rec try_arrows = function
    | [] -> None
    | a :: rest ->
      let hl = String.length l and al = String.length a in
      let rec find i =
        if i + al > hl then None
        else if String.sub l i al = a then Some i
        else find (i + 1)
      in
      (match find 0 with
       | Some i -> Some (String.sub l 0 i, String.sub l (i + al) (hl - i - al))
       | None -> try_arrows rest)
  in
  try_arrows arrows

(* Mermaid edges. Declaration-only lines and `subgraph`/`end`/`style`/
   `classDef` directives carry no edge and are skipped rather than
   guessed at. A labelled edge `A -->|why| B` keeps its endpoints. *)
let mermaid_edges block =
  lines block
  |> List.filter_map (fun l ->
      let t = String.trim l in
      if t = "" || starts_with "%%" t || starts_with "style " t
         || starts_with "classDef " t || starts_with "subgraph " t
         || t = "end" || starts_with "graph " t || starts_with "flowchart " t
      then None
      else
        match split_on_arrow t with
        | None -> None
        | Some (a, b) ->
          let a = node_id a and b = node_id b in
          if a = "" || b = "" then None else Some (a, b))

(* Arrow-list ASCII edges: `[A label] --> [B label]`. Identity is the
   FIRST token inside the bracket, matching the generator's convention in
   tools/generate_sa_plan_execution.ml. *)
let bracket_id tok =
  let t = String.trim tok in
  let t =
    if String.length t > 0 && t.[0] = '[' then String.sub t 1 (String.length t - 1) else t
  in
  let t =
    match String.index_opt t ']' with
    | Some i -> String.sub t 0 i
    | None -> t
  in
  match String.split_on_char ' ' (String.trim t) with
  | first :: _ -> first
  | [] -> ""

(* Normalised label: the only vocabulary the two forms actually share.
   Mermaid writes terse ids with labels (`M["Models/actors"]`); the ASCII
   arrow lists write the label text directly (`[Models/actors]`). Comparing
   mermaid IDS against ASCII LABELS is a category error -- it reported
   contracts/rules/20260907-0811-hive-decision-forecast-kpi-mandate.md as a
   topology MISMATCH when the two diagrams agree exactly. Compare labels. *)
(* Remove the decorations mermaid labels carry that the ASCII form never
   does: quotes, `<br/>` soft breaks, and stray bracket punctuation. *)
let strip_decorations s =
  let replace_all hay needle rep =
    let nl = String.length needle in
    let b = Buffer.create (String.length hay) in
    let i = ref 0 in
    let n = String.length hay in
    while !i < n do
      if !i + nl <= n && String.sub hay !i nl = needle then begin
        Buffer.add_string b rep; i := !i + nl
      end
      else begin Buffer.add_char b hay.[!i]; incr i end
    done;
    Buffer.contents b
  in
  List.fold_left (fun acc (a, b) -> replace_all acc a b) s
    [ ("<br/>", " "); ("<br />", " "); ("<br>", " "); ("\"", "");
      ("(", ""); (")", ""); ("[", ""); ("]", "") ]

let norm_label s =
  let b = Buffer.create (String.length s) in
  let last_space = ref true in
  String.iter
    (fun c ->
       let c = Char.lowercase_ascii c in
       if c = ' ' || c = '\t' || c = '\n' then begin
         if not !last_space then Buffer.add_char b ' ';
         last_space := true
       end
       else begin Buffer.add_char b c; last_space := false end)
    s;
  String.trim (Buffer.contents b)

(* `[A] -> [B] -> [C]` is TWO edges. Splitting once and keeping the first
   arrow lost every edge past the first in a chain, which silently
   under-reported the ASCII side and manufactured differences. *)
let bracket_chain l =
  let n = String.length l in
  let rec go i acc =
    if i >= n then List.rev acc
    else if l.[i] = '[' then
      match String.index_from_opt l i ']' with
      | Some j -> go (j + 1) (String.sub l (i + 1) (j - i - 1) :: acc)
      | None -> List.rev acc
    else go (i + 1) acc
  in
  go 0 []

let rec pairs = function
  | a :: (b :: _ as rest) -> (a, b) :: pairs rest
  | _ -> []

let arrow_list_edges block =
  lines block
  |> List.concat_map (fun l ->
      let t = String.trim l in
      if not (List.exists (fun m -> contains t m) arrow_list_markers) then []
      else
        bracket_chain t
        |> List.map norm_label
        |> List.filter (fun s -> s <> "")
        |> pairs)

(* ------------------------------------------------------------------ *)
(* the verdict                                                        *)
(* ------------------------------------------------------------------ *)

(* Mermaid id -> label, harvested from any decorated mention of a node
   anywhere in the block (declaration or inline in an edge). *)
let mermaid_labels block =
  let acc = ref [] in
  List.iter
    (fun l ->
       let n = String.length l in
       let rec go i =
         if i >= n then ()
         else if l.[i] = '[' || l.[i] = '(' || l.[i] = '{' then begin
           let closing = match l.[i] with '[' -> ']' | '(' -> ')' | _ -> '}' in
           (match String.index_from_opt l i closing with
            | Some j ->
              (* the id is the token immediately before the bracket *)
              let rec back k =
                if k <= 0 then 0
                else
                  let c = l.[k - 1] in
                  if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                     || (c >= '0' && c <= '9') || c = '_' || c = '-'
                  then back (k - 1) else k
              in
              let st = back i in
              let id = String.trim (String.sub l st (i - st)) in
              let raw = String.sub l (i + 1) (j - i - 1) in
              (* strip quotes, nested brackets and <br/> line breaks *)
              let raw = strip_decorations raw in
              if id <> "" then acc := (id, norm_label raw) :: !acc;
              go (j + 1)
            | None -> ())
         end
         else go (i + 1)
       in
       go 0)
    (lines block);
  !acc

let show_edge (a, b) = a ^ " --> " ^ b
let uniq_sorted l = List.sort_uniq String.compare l

let check (body : string) : verdict =
  let mers = mermaid_blocks body in
  if mers = [] then No_mermaid
  else
    let m_edges = List.concat_map mermaid_edges mers in
    match classify_ascii (ascii_blocks body) with
    | Absent -> Missing_ascii
    | Table_only -> Table_mistaken_for_diagram
    | Box_art -> Unverifiable_box_art { mermaid_edges = List.length m_edges }
    | Arrow_list ->
      let a_edges = List.concat_map arrow_list_edges (ascii_blocks body) in
      (* Project the mermaid edges into LABEL space, which is the only
         vocabulary the two forms share. A node with no label keeps its id. *)
      let labels = List.concat_map mermaid_labels mers in
      let lbl id = match List.assoc_opt id labels with
        | Some l when l <> "" -> l
        | _ -> norm_label id
      in
      let m_lbl = List.map (fun (x, y) -> (lbl x, lbl y)) m_edges in
      let a = uniq_sorted (List.map show_edge a_edges) in
      let m = uniq_sorted (List.map show_edge m_lbl) in
      let nodes es = uniq_sorted (List.concat_map (fun (x, y) -> [ x; y ]) es) in
      let an = nodes a_edges and mn = nodes m_lbl in
      let shared = List.filter (fun x -> List.mem x mn) an in
      if a = m then Edges_match (List.length a)
      else if shared = [] && an <> [] && mn <> [] then
        (* Disjoint vocabularies: nothing to align. Reporting a mismatch
           here would blame the document for the checker's inability to
           correspond two naming schemes. *)
        Unverifiable_naming
          { ascii_edges = List.length a; mermaid_edges = List.length m }
      else
        Edges_differ
          { only_ascii = List.filter (fun e -> not (List.mem e m)) a;
            only_mermaid = List.filter (fun e -> not (List.mem e a)) m }

(* PASSING means the property was VERIFIED. Box art is co-present but
   unverified, so it is not passing -- and naming it separately is what
   lets a caller choose to report without failing a build, instead of
   being forced to choose between a lie and a breakage. *)
let is_passing = function Edges_match _ | No_mermaid -> true | _ -> false

let is_failure = function
  | Missing_ascii | Table_mistaken_for_diagram | Edges_differ _ -> true
  | _ -> false

let describe = function
  | No_mermaid -> "no mermaid diagram; nothing to compare"
  | Missing_ascii ->
    "FAIL: mermaid diagram with no ASCII diagram source (SC-DIAGRAM-001)"
  | Table_mistaken_for_diagram ->
    "FAIL: the only ASCII-fenced content is a Markdown table, which is not a \
     diagram. A table satisfied the previous check; it does not satisfy this one."
  | Edges_match n ->
    Printf.sprintf "PASS: ASCII and mermaid edge sets agree (%d edges compared)" n
  | Edges_differ { only_ascii; only_mermaid } ->
    Printf.sprintf
      "FAIL: edge sets differ. ASCII only: [%s]. Mermaid only: [%s]."
      (String.concat "; " only_ascii) (String.concat "; " only_mermaid)
  | Unverifiable_naming { ascii_edges; mermaid_edges } ->
    Printf.sprintf
      "UNVERIFIED: both forms are arrow lists (%d ASCII edges, %d mermaid) but \
       their node vocabularies do not overlap, so no alignment exists. This is \
       NOT a topology mismatch. Nonpassing."
      ascii_edges mermaid_edges
  | Unverifiable_box_art { mermaid_edges } ->
    Printf.sprintf
      "UNVERIFIED: ASCII source is box art, whose topology is not mechanically \
       comparable to the mermaid graph (%d mermaid edges). Co-presence holds; \
       identical topology per INV-JRN-06 is NOT verified. Nonpassing."
      mermaid_edges

let authority = "REPORT_ONLY"
