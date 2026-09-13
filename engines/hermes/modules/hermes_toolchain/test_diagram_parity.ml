(* Laws for dual-source diagram checking.

   The first laws are the MEASURED falsifiers: documents that the old
   `journal_linter` substring sweep reported as
   "dual diagram source parity verified" while containing no ASCII
   diagram at all. They are kept verbatim so the defect cannot return
   quietly. *)

let passed = ref 0
let failed = ref 0

let law name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
    incr failed;
    print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

open Diagram_parity

let v = Diagram_parity.check

let mermaid = "```mermaid\nflowchart TD\n  A[\"a\"] --> B[\"b\"]\n```"

let empty_cell_table = mermaid ^ "\n\n| Col | Note |\n|---|---|\n| x |  |\n"
let right_aligned_table = mermaid ^ "\n\n| Metric | Value |\n|---:|---:|\n|   1 |   2 |\n"

let mermaid_of edges =
  "```mermaid\nflowchart TD\n"
  ^ String.concat "\n"
      (List.map (fun (x, y) -> "  " ^ x ^ "[\"" ^ x ^ "\"] --> " ^ y ^ "[\"" ^ y ^ "\"]") edges)
  ^ "\n```\n"

let ascii_of edges =
  "```text\n"
  ^ String.concat "\n"
      (List.map (fun (x, y) -> "[" ^ x ^ "] --> [" ^ y ^ "]") edges)
  ^ "\n```\n"

let doc m a = mermaid_of m ^ "\n" ^ ascii_of a

let has needle d =
  let n = String.length needle and h = String.length d in
  let rec go i = i + n <= h && (String.sub d i n = needle || go (i + 1)) in
  go 0

let box =
  mermaid
  ^ "\n\n```text\n+--------+      +--------+\n|  alpha | ---> |  beta  |\n\
     +--------+      +--------+\n```\n"

let () =
  (* --- the measured regressions ------------------------------------- *)
  (* The tables here are UNFENCED, so they are not ASCII-block candidates at
     all and the verdict is Missing_ascii. The load-bearing property is not
     which constructor fires but that the document does not PASS: the old
     check reported "parity verified" for both of these. Asserting the
     constructor instead would be this suite committing the same error as the
     code it replaces -- pinning an incidental observable. L4 covers the
     fenced-table case, where Table_mistaken_for_diagram is the right verdict. *)
  law "L1 REGRESSION: a table with an empty cell does not satisfy the ASCII \
         requirement (the old check PASSED this exact document)" (fun () ->
      (not (is_passing (v empty_cell_table))) && is_failure (v empty_cell_table));
  law "L2 REGRESSION: a right-aligned table does not satisfy it either \
         (the old check PASSED this exact document too)" (fun () ->
      (not (is_passing (v right_aligned_table))) && is_failure (v right_aligned_table));
  law "L3 both measured falsifiers are failures, not merely non-passes"
    (fun () ->
       List.for_all
         (fun d -> (not (is_passing (v d))) && is_failure (v d))
         [ empty_cell_table; right_aligned_table ]);
  law "L4 a Markdown table inside a ```text fence is still a table -- \
         fencing it does not make it topology" (fun () ->
      v (mermaid ^ "\n\n```text\n| a |  |\n|---|---|\n| b |  |\n```\n")
      = Table_mistaken_for_diagram);

  (* --- absence ------------------------------------------------------ *)
  law "L5 mermaid with no ASCII block at all is Missing_ascii" (fun () ->
      v (mermaid ^ "\n\nprose only, no fenced ascii\n") = Missing_ascii);
  law "L6 no mermaid is not a finding -- a prose document owes no diagram"
    (fun () -> v "# title\n\nplain prose\n" = No_mermaid);
  law "L7 no mermaid is passing even with no ASCII present" (fun () ->
      is_passing (v "nothing here"));

  (* --- box art: co-present but UNVERIFIED --------------------------- *)
  law "L8 box art is neither pass nor failure: it is UNVERIFIED, because \
         2D line art has no mechanically extractable edge set" (fun () ->
      match v box with
      | Unverifiable_box_art _ ->
        (not (is_passing (v box))) && not (is_failure (v box))
      | _ -> false);
  law "L9 the box-art verdict reports how many mermaid edges went \
         unverified, so a reader can judge the exposure" (fun () ->
      match v box with
      | Unverifiable_box_art { mermaid_edges } -> mermaid_edges = 1
      | _ -> false);
  law "L10 unicode box-drawing glyphs are recognised as box art" (fun () ->
      match
        v (mermaid ^ "\n\n```text\n\xe2\x94\x8c\xe2\x94\x80\xe2\x94\x80\n\
                      \xe2\x94\x82 a\n```\n")
      with
      | Unverifiable_box_art _ -> true
      | _ -> false);

  (* --- arrow-list: real edge parity --------------------------------- *)
  law "L11 identical edge sets PASS and report the count compared"
    (fun () ->
       v (doc [ ("A", "B"); ("B", "C") ] [ ("A", "B"); ("B", "C") ])
       = Edges_match 2);
  law "L12 order does not matter -- an edge SET, not a sequence" (fun () ->
      v (doc [ ("A", "B"); ("B", "C") ] [ ("B", "C"); ("A", "B") ])
      = Edges_match 2);
  (* Edge names are reported in NORMALISED label space (lowercased,
     whitespace collapsed), because that is the space the comparison happens
     in. Reporting the raw form would name something the checker never
     compared. *)
  law "L13 an edge only in the mermaid is caught and named" (fun () ->
      match v (doc [ ("A", "B"); ("B", "C") ] [ ("A", "B") ]) with
      | Edges_differ { only_ascii = []; only_mermaid = [ "b --> c" ] } -> true
      | _ -> false);
  law "L14 an edge only in the ASCII is caught and named" (fun () ->
      match v (doc [ ("A", "B") ] [ ("A", "B"); ("B", "C") ]) with
      | Edges_differ { only_ascii = [ "b --> c" ]; only_mermaid = [] } -> true
      | _ -> false);
  law "L15 a REDIRECTED edge is caught -- same node count, different \
         topology, which co-presence could never see" (fun () ->
      match v (doc [ ("A", "B"); ("A", "C") ] [ ("A", "B"); ("B", "C") ]) with
      | Edges_differ _ -> true
      | _ -> false);
  law "L16 an edge-set difference is a failure" (fun () ->
      is_failure (v (doc [ ("A", "B") ] [ ("A", "C") ])));

  (* --- mermaid parsing details -------------------------------------- *)
  law "L17 node identity is the ID, not the label: this corpus writes \
         different WORDING in the two forms while the graph is the same"
    (fun () ->
       mermaid_edges "A[\"long prose here\"] --> B[\"other prose\"]"
       = [ ("A", "B") ]);
  law "L18 declarations, directives and subgraph lines carry no edge"
    (fun () ->
       mermaid_edges
         "graph LR\n  subgraph S[\"x\"]\n  A[\"a\"]\n  end\n  style A fill:#fff\n\
          \  classDef c fill:#000\n  %% comment"
       = []);
  law "L19 a labelled edge keeps its endpoints" (fun () ->
      mermaid_edges "A -->|because| B" = [ ("A", "B") ]);
  law "L20 the other arrow forms are recognised" (fun () ->
      List.for_all
        (fun l -> mermaid_edges l = [ ("A", "B") ])
        [ "A --> B"; "A ==> B"; "A -.-> B"; "A --- B" ]);
  law "L21 round and brace node shapes reduce to their id" (fun () ->
      List.for_all
        (fun l -> mermaid_edges l = [ ("A", "B") ])
        [ "A(a) --> B(b)"; "A{a} --> B{b}"; "A((a)) --> B((b))" ]);

  (* --- fence discipline --------------------------------------------- *)
  law "L22 a bare ``` fence is NOT an ASCII diagram candidate: it is code \
         in this corpus, and admitting it drifts back toward a sweep"
    (fun () -> v (mermaid ^ "\n\n```\n+---+\n| a |\n+---+\n```\n") = Missing_ascii);
  law "L23 an ```ascii fence is accepted alongside ```text" (fun () ->
      match v (mermaid ^ "\n\n```ascii\n+---+\n|a|\n+---+\n```\n") with
      | Unverifiable_box_art _ -> true
      | _ -> false);

  (* --- honesty of the verdict vocabulary ---------------------------- *)
  law "L24 only an actual edge comparison is passing" (fun () ->
      is_passing (Edges_match 1)
      && not (is_passing (Unverifiable_box_art { mermaid_edges = 3 }))
      && not (is_passing Table_mistaken_for_diagram)
      && not (is_passing Missing_ascii));
  law "L25 no verdict says PASS unless it verified something" (fun () ->
      (not (has "PASS" (describe (Unverifiable_box_art { mermaid_edges = 1 }))))
      && has "UNVERIFIED" (describe (Unverifiable_box_art { mermaid_edges = 1 }))
      && has "PASS" (describe (Edges_match 1)));
  law "L26 the box-art description names the mandate it cannot check"
    (fun () ->
       let d = describe (Unverifiable_box_art { mermaid_edges = 2 }) in
       has "INV-JRN-06" d && has "Nonpassing" d);
  law "L27 the module is report-only and says so" (fun () ->
      authority = "REPORT_ONLY");

  (* --- robustness --------------------------------------------------- *)
  law "L28 an empty document is No_mermaid, not a crash" (fun () ->
      v "" = No_mermaid);
  law "L29 an unterminated mermaid fence is still seen -- a truncated \
         document must not silently owe nothing" (fun () ->
      v "```mermaid\nA --> B\n" <> No_mermaid);
  (* --- regressions from the first real corpus run -------------------- *)
  law "L31 a `] -> [` arrow list is an arrow list too: the hand-authored \
         contract flows use one dash, and missing it reported a document \
         with a perfectly good ASCII diagram as having none" (fun () ->
      match
        v (mermaid_of [ ("A", "B") ]
           ^ "\n```text\n[A] -> [B]\n```\n")
      with
      | Edges_match 1 -> true
      | _ -> false);
  law "L32 a non-table `text` fence is a DIAGRAM, not an absence: claiming \
         'no ASCII diagram' of a document that has one is a false FAIL, the \
         mirror image of the defect being repaired" (fun () ->
      match v (mermaid ^ "\n```text\n  Gleam control -> C ABI -> Mojo\n```\n") with
      | Unverifiable_box_art _ | Edges_match _ | Edges_differ _ -> true
      | _ -> false);
  law "L33 the measured real-corpus case: a text fence whose arrows are `->` \
         and which carries no box glyph is never Missing_ascii" (fun () ->
      v (mermaid ^ "\n```text\n[Models] -> [Record] -> [Validation]\n```\n")
      <> Missing_ascii);

  law "L30 multiple mermaid blocks contribute all their edges" (fun () ->
      match
        v (mermaid_of [ ("A", "B") ] ^ mermaid_of [ ("C", "D") ]
           ^ ascii_of [ ("A", "B"); ("C", "D") ])
      with
      | Edges_match 2 -> true
      | _ -> false)

let () =
  Printf.printf "diagram_parity: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_diagram_parity" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.toolchain_core ]);
  exit (Suite_telemetry.exit_code self)
