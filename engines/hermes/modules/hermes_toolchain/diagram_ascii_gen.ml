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

   ONLY flowchart/graph blocks are generated. sequenceDiagram, stateDiagram
   and friends are different languages whose arrows are not edges; this tool
   refuses them and says so, leaving them for an author. *)

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

(* Walk the document line by line, emitting a ```text arrow-list immediately
   BEFORE each generatable mermaid block. Everything else is copied verbatim:
   the tool must not reformat a document it was asked only to add to. *)
let process body =
  let lines = String.split_on_char '\n' body in
  let out = Buffer.create (String.length body * 2) in
  let generated = ref 0 and refused = ref [] in
  let rec go = function
    | [] -> ()
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
      (* A label carrying arrow syntax or brackets cannot round-trip through
         `[label] --> [label]`: the reader cannot tell the label's arrows from
         the edge's. MEASURED -- a node labelled
         "Port Hunter 8088 -> 8089 -> 8090 -> 0" produced ASCII this tool's own
         checker then read as a different graph. Refuse the block and say so
         rather than emit output that cannot be read back. Emitting something
         unreadable is worse than emitting nothing: nothing stays FAILED and
         visible, garbage reports a mismatch against the very diagram it was
         derived from. *)
      let unsafe raw =
        List.exists
          (fun m ->
             let hl = String.length raw and ml = String.length m in
             let rec go i = i + ml <= hl && (String.sub raw i ml = m || go (i + 1)) in
             go 0)
          [ "-->"; "->"; "=>"; "["; "]" ]
      in
      let lbl id =
        match List.assoc_opt id labels with
        | Some raw when String.trim raw <> "" -> String.trim raw
        | _ -> id
      in
      let has_unsafe =
        List.exists (fun (a, b) -> unsafe (lbl a) || unsafe (lbl b)) edges
      in
      if edges <> [] && has_unsafe then begin
        refused := "label-contains-arrow-syntax" :: !refused
      end
      else if edges <> [] then begin
        Buffer.add_string out "```text\n";
        List.iter
          (fun (a, b) ->
             Buffer.add_string out
               ("[" ^ lbl a ^ "] --> [" ^ lbl b ^ "]\n"))
          edges;
        Buffer.add_string out "```\n\n";
        incr generated
      end
      else begin
        let k = Diagram_parity.mermaid_kind block in
        refused := (if k = "" then "(undeclared)" else k) :: !refused
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
  (s, !generated, List.sort_uniq String.compare !refused)

let () =
  let dry = Array.exists (fun a -> a = "--dry-run") Sys.argv in
  let files =
    Array.to_list Sys.argv |> List.tl |> List.filter (fun a -> a <> "--dry-run")
  in
  let total = ref 0 and touched = ref 0 and skipped = ref [] in
  List.iter
    (fun f ->
       match read f with
       | exception _ -> Printf.printf "SKIP  %s (unreadable)\n" f
       | body ->
         let out, n, refused = process body in
         (* ALL-OR-NOTHING per document. The checker compares the union of a
            document's ASCII edges against the union of its mermaid edges, so
            covering some blocks and not others manufactures a mismatch
            against the very diagrams the ASCII was derived from. Measured:
            partial generation left 3 documents reporting a difference. *)
         if n > 0 && refused <> [] then begin
           skipped := (f, refused) :: !skipped;
           Printf.printf
             "SKIP  %s  (partial: %d generatable, but refused %s --               all-or-nothing)\n" f n (String.concat "," refused)
         end
         else if n > 0 then begin
           total := !total + n;
           incr touched;
           if not dry then write f out;
           Printf.printf "%s  %s  (+%d ascii block%s)%s\n"
             (if dry then "WOULD" else "WROTE") f n
             (if n = 1 then "" else "s")
             (if refused = [] then ""
              else "  refused: " ^ String.concat "," refused)
         end
         else begin
           skipped := (f, refused) :: !skipped;
           Printf.printf "SKIP  %s  (no generatable block; kinds: %s)\n" f
             (String.concat "," refused)
         end)
    files;
  Printf.printf "\n%s %d ascii block(s) into %d file(s); %d file(s) skipped\n"
    (if dry then "would generate" else "generated")
    !total !touched (List.length !skipped)
