(* Generate the ASCII form of a mermaid diagram FROM the mermaid.

   SC-DIAGRAM-001 requires both forms to describe identical topology.
   Hand-writing a second form and then CHECKING it agree is the weaker
   arrangement: the check can only detect drift after an author introduces it.
   Deriving the ASCII from the mermaid makes the edge sets equal BY
   CONSTRUCTION -- the same argument wiki_transclude.mli makes for prose
   ("makes byte-equality FREE rather than something to test for").

   It reuses Diagram_parity's extractor rather than re-implementing one. A
   second parser would be free to drift from the checker it must satisfy,
   which is the defect class this whole module family exists to remove.

   A flowchart/graph block becomes an ARROW LIST, whose edge set the checker
   compares against the mermaid's.

   EXTENDED 2026-11-07. sequenceDiagram, stateDiagram-v2, mindmap, erDiagram
   and quadrantChart are different languages whose arrows are not graph edges,
   and the first version of this tool refused them -- which left 43 of the 44
   documents that SC-DIAGRAM-001 reports as having no ASCII source with no
   ASCII source. Refusing to act is not neutral when the mandate asks for two
   forms and only one exists.

   So those kinds now get a MECHANICAL TRANSCRIPTION: the block's own lines,
   with brackets softened to parentheses and every arrow glyph written `=>`.
   That is deliberate and it is not a trick. The transcription makes NO claim
   the checker cannot stand behind: it is classified as a picture, so the
   document's verdict becomes UNVERIFIED -- co-presence holds, topology is not
   mechanically compared -- which is exactly the honest verdict for two forms
   of a sequence or state diagram. Writing the arrows as `=>` is what keeps it
   from claiming to be an edge list it is not.

   NOTHING is written unless the result passes the checker. Every output is
   re-read with Diagram_parity.check before the file is touched, and a
   document whose generated form would FAIL is left alone and reported. A
   generator that can emit what its own gate rejects is not a repair. *)

let read path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let write path s =
  let oc = open_out_bin path in
  output_string oc s; close_out oc

let starts_with pre s =
  String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

let replace_all hay needle rep =
  let nl = String.length needle in
  let b = Buffer.create (String.length hay) in
  let i = ref 0 in
  let n = String.length hay in
  while !i < n do
    if nl > 0 && !i + nl <= n && String.sub hay !i nl = needle then begin
      Buffer.add_string b rep; i := !i + nl
    end
    else begin Buffer.add_char b hay.[!i]; incr i end
  done;
  Buffer.contents b

(* Longest first: `-->>` must not be read as `-->` leaving a stray `>`. *)
let arrow_glyphs =
  [ "<-->"; "<==>"; "-->>"; "--)"; "--x"; "->>"; "--->"; "-.->"; "-->"; "==>";
    "-->|"; "->"; "=>" ]

(* A transcription must not accidentally spell an ARROW LIST. The checker reads
   `] --> [` and `] -> [` as "this document carries an extractable edge set",
   and a transcription that spelled one would be compared, edge for edge,
   against a diagram whose arrows are not edges -- manufacturing a mismatch out
   of a rendering choice. Brackets become parentheses and arrows become `=>`,
   so neither marker can form. *)
let transcribe_line l =
  let l = replace_all l "[" "(" in
  let l = replace_all l "]" ")" in
  List.fold_left (fun acc g -> replace_all acc g "=>") l arrow_glyphs

(* Every generated block opens with this line, and a mermaid block already
   preceded by one is left alone. Without that the tool is NOT IDEMPOTENT: a
   second run inserts a second copy of every block, and a third a third. The
   marker lives INSIDE the fence rather than in an HTML comment so it survives
   any renderer and is visible to a reader deciding whether to hand-edit. It
   carries no arrow and no table row, so it changes no verdict. *)
let marker = "ASCII source generated from the mermaid block below"

let contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  nl = 0
  || (nl <= hl
      && (let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
          go 0))

(* Walk the document line by line, emitting a ```text arrow-list immediately
   BEFORE each generatable mermaid block. Everything else is copied verbatim:
   the tool must not reformat a document it was asked only to add to. *)
let process body =
  let lines = String.split_on_char '\n' body in
  let out = Buffer.create (String.length body * 2) in
  let generated = ref 0 and transcribed = ref 0 and refused = ref [] in
  let already = ref 0 in
  (* true when the most recent thing emitted, blank lines aside, was a fence
     this tool had written. *)
  let marked = ref false in
  let rec go = function
    | [] -> ()
    | l :: rest
      when String.trim l = "```text" || String.trim l = "```ascii" ->
      let rec take acc = function
        | [] -> (List.rev acc, [])
        | x :: more when starts_with "```" (String.trim x) -> (List.rev acc, x :: more)
        | x :: more -> take (x :: acc) more
      in
      let block_lines, tail = take [] rest in
      marked := contains (String.concat "\n" block_lines) marker;
      Buffer.add_string out (l ^ "\n");
      List.iter (fun x -> Buffer.add_string out (x ^ "\n")) block_lines;
      (match tail with
       | closing :: more -> Buffer.add_string out (closing ^ "\n"); go more
       | [] -> ())
    | l :: rest when String.trim l = "" ->
      Buffer.add_string out (l ^ "\n"); go rest
    | l :: rest when String.trim l = "```mermaid" && !marked ->
      (* Already carries a generated ASCII source: copy and count, do not
         insert a duplicate. *)
      let rec take acc = function
        | [] -> (List.rev acc, [])
        | x :: more when starts_with "```" (String.trim x) -> (List.rev acc, x :: more)
        | x :: more -> take (x :: acc) more
      in
      let block_lines, tail = take [] rest in
      incr already;
      marked := false;
      Buffer.add_string out (l ^ "\n");
      List.iter (fun x -> Buffer.add_string out (x ^ "\n")) block_lines;
      go tail
    | l :: rest when String.trim l = "```mermaid" ->
      (* collect the block *)
      let rec take acc = function
        | [] -> (List.rev acc, [])
        | x :: more when starts_with "```" (String.trim x) -> (List.rev acc, x :: more)
        | x :: more -> take (x :: acc) more
      in
      let block_lines, tail = take [] rest in
      let block = String.concat "\n" block_lines in
      let edges = Diagram_parity.mermaid_edges block in
      let labels = Diagram_parity.mermaid_labels block in
      (* A BRACKET inside a label cannot round-trip through `[label] -->
         [label]`: the reader scans for the next `]` and would cut the label
         short. Arrows inside a label CAN round-trip and are no longer
         refused -- the ASCII reader extracts bracket CONTENT and never splits
         a bracketed segment on an arrow, so a node labelled
         "Port Hunter 8088 -> 8089 -> 8090 -> 0" reads back intact. Refusing
         it cost 11 documents their ASCII source for a hazard that is not
         there; the label-stripping in Diagram_parity.mermaid_labels removes
         brackets anyway, so this guard is now a belt, not the trousers. *)
      let unsafe raw =
        List.exists
          (fun m ->
             let hl = String.length raw and ml = String.length m in
             let rec go i = i + ml <= hl && (String.sub raw i ml = m || go (i + 1)) in
             go 0)
          [ "["; "]" ]
      in
      let lbl id =
        match List.assoc_opt id labels with
        | Some raw when String.trim raw <> "" -> String.trim raw
        | _ -> id
      in
      let has_unsafe =
        List.exists (fun (a, b) -> unsafe (lbl a) || unsafe (lbl b)) edges
      in
      if edges <> [] && not has_unsafe then begin
        Buffer.add_string out "```text\n";
        Buffer.add_string out
          (marker ^ ", edge for edge (SC-DIAGRAM-001).\n\n");
        List.iter
          (fun (a, b) ->
             Buffer.add_string out
               ("[" ^ lbl a ^ "] --> [" ^ lbl b ^ "]\n"))
          edges;
        Buffer.add_string out "```\n\n";
        incr generated
      end
      else begin
        (* No extractable edge set: a non-flowchart language, a
           declaration-only graph, or a label that cannot round-trip.
           Transcribe instead of refusing. The transcription is a PICTURE by
           construction (see transcribe_line), so the document's verdict
           becomes UNVERIFIED rather than a claim of verified topology. *)
        let k = Diagram_parity.mermaid_kind block in
        let k = if k = "" then "(undeclared)" else k in
        Buffer.add_string out "```text\n";
        Buffer.add_string out (marker ^ ", as a transcription.\n");
        Buffer.add_string out
          ("Kind: " ^ k ^ ". Arrows are written => and brackets as parentheses, \
            because this is\n");
        Buffer.add_string out
          "the diagram as text and NOT an extractable edge list: \
           SC-DIAGRAM-001 topology\n";
        Buffer.add_string out "parity stays UNVERIFIED for this document.\n\n";
        List.iter
          (fun x -> Buffer.add_string out (transcribe_line x ^ "\n"))
          block_lines;
        Buffer.add_string out "```\n\n";
        incr transcribed;
        refused := k :: !refused
      end;
      (* copy the mermaid block back verbatim *)
      Buffer.add_string out (l ^ "\n");
      List.iter (fun x -> Buffer.add_string out (x ^ "\n")) block_lines;
      go tail
    | l :: rest -> Buffer.add_string out (l ^ "\n"); go rest
  in
  go lines;
  (* `go` appends a newline per line, so a file that did not end in one gains
     exactly one. Trim that back rather than silently changing the last byte. *)
  let s = Buffer.contents out in
  let s =
    if String.length body > 0
       && body.[String.length body - 1] <> '\n'
       && String.length s > 0
       && s.[String.length s - 1] = '\n'
    then String.sub s 0 (String.length s - 1)
    else s
  in
  (s, !generated, !transcribed, !already, List.sort_uniq String.compare !refused)

let () =
  let dry = Array.exists (fun a -> a = "--dry-run") Sys.argv in
  let files =
    Array.to_list Sys.argv |> List.tl |> List.filter (fun a -> a <> "--dry-run")
  in
  let total = ref 0 and touched = ref 0 and skipped = ref 0 in
  List.iter
    (fun f ->
       match read f with
       | exception _ -> Printf.printf "SKIP  %s (unreadable)\n" f
       | body ->
         let out, n, tr, already, kinds = process body in
         let blocks = n + tr in
         (* VERIFY BEFORE WRITING. The old all-or-nothing heuristic guessed at
            when generation would disagree with itself; this asks the gate.
            A document is written only if its generated form is NOT a failure
            under the very checker that reports it -- which also covers the
            case this tool cannot foresee, an ASCII arrow list the document
            already carried and that contradicts the mermaid. *)
         let verdict = Diagram_parity.check out in
         if blocks = 0 && already > 0 then begin
           incr skipped;
           Printf.printf
             "KEPT  %s  (%d block%s already carry a generated ASCII source)\n" f
             already (if already = 1 then "" else "s")
         end
         else if blocks = 0 then begin
           incr skipped;
           Printf.printf "SKIP  %s  (no mermaid block to work from)\n" f
         end
         else if Diagram_parity.is_failure verdict then begin
           incr skipped;
           Printf.printf "SKIP  %s  (generated form still fails: %s)\n" f
             (Diagram_parity.describe verdict)
         end
         else begin
           total := !total + blocks;
           incr touched;
           if not dry then write f out;
           Printf.printf "%s  %s  (+%d arrow-list, +%d transcription%s)  -> %s\n"
             (if dry then "WOULD" else "WROTE") f n tr
             (if kinds = [] then "" else " [" ^ String.concat "," kinds ^ "]")
             (Diagram_parity.describe verdict)
         end)
    files;
  Printf.printf "\n%s %d ascii block(s) into %d file(s); %d file(s) skipped\n"
    (if dry then "would generate" else "generated")
    !total !touched !skipped
