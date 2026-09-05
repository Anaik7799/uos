(* HW.9.1.3 / HW.9.4.1 / HW.9.2.2 / HW.9.2.3 — binding documentation to
   source, across the full functional envelope:

     N*  nominal      a table, a census, a diff, a cross-link that work
     X*  exhaustion   thousands of vals, a diff past the LCS bound, a
                      census over many sources
     S*  stuck        an unreadable source, an interface with no vals, an
                      identical pair, the reader that resolves nothing
     A*  anomaly      injection through a doc comment, an out-of-range
                      line, a diff applied to the wrong slice, a
                      name that is a prefix of another name

   The four headline laws:

     HW.9.1.3  the table is COMPLETE over the public interface — an
               undocumented val is a row, marked, never an omission.
     HW.9.4.1  the DENOMINATOR is the declared set. An unreadable source
               is disclosed and counted at 0%; a coverage percentage that
               rose because the denominator shrank is unrepresentable.
     HW.9.2.2  the ROUND TRIP: patch before (diff before after) = after.
               A diff that merely looks plausible is decoration.
     HW.9.2.3  every emitted cross-link RESOLVES. An unresolvable target
               is a named diagnostic, never a clamped line number. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

let close a b = abs_float (a -. b) < 1e-9

(* ------------------------------------------------------------ fixtures *)

let mli_full = "(* documents a. And more. *)\nval a : int -> int\n\n(* documents b *)\nval b : string\n"
let mli_half = "(* documents a. And more. *)\nval a : int -> int\nval b : string\n"
let mli_types_only = "type t = int\ntype u = string\n"
let mli_hostile = "(* danger <script>alert(1)</script> & \"quotes\" *)\nval x : int -> int\n"

let sources =
  [ ("full.mli", mli_full);
    ("half.mli", mli_half);
    ("none.mli", mli_types_only);
    ("m.mli", "(* doc *)\nval apply : int -> int\nval ghost : int\n");
    ("m.ml", "let apply_start x = x\nlet apply x = x\n");
    ("after.ml", "one\ntwo\nthree\n");
    ("before.ml", "one\nTWO\nthree\n");
    ("same.ml", "one\ntwo\n");
    ("hostile.ml", "let f = \"<b>&\"\n") ]

let read p = List.assoc_opt p sources

(* the same corpus with half.mli withheld — the ONLY difference *)
let read_partial p = if p = "half.mli" then None else read p

(* ------------------------------------------------------------- nominal *)

let () =
  check "N1 HW.9.1.3 the table is COMPLETE: one row per val, in source order" (fun () ->
      let rows = Wiki_source_ext.api_rows mli_full in
      List.length rows = List.length (Wiki_iface.items mli_full)
      && List.map (fun (r : Wiki_source_ext.api_row) -> r.Wiki_source_ext.name) rows = [ "a"; "b" ]
      && (List.hd rows).Wiki_source_ext.signature = "int -> int");
  check "N2 the summary is the FIRST SENTENCE of the attached comment" (fun () ->
      match Wiki_source_ext.api_rows mli_full with
      | r :: _ -> r.Wiki_source_ext.summary = "documents a." && r.Wiki_source_ext.documented
      | [] -> false);
  check "N3 HW.9.4.1 the census counts every declared source, sorted, none dropped" (fun () ->
      let c = Wiki_source_ext.census ~read [ "none.mli"; "full.mli"; "half.mli" ] in
      c.Wiki_source_ext.declared = 3
      && List.length c.Wiki_source_ext.entries = 3
      && List.map (fun (e : Wiki_source_ext.entry) -> e.Wiki_source_ext.path) c.Wiki_source_ext.entries
         = [ "full.mli"; "half.mli"; "none.mli" ]);
  check "N4 the census figures are the honest ones (2/2 and 1/2 over two sources)" (fun () ->
      let c = Wiki_source_ext.census ~read [ "full.mli"; "half.mli" ] in
      c.Wiki_source_ext.items_documented = 3
      && c.Wiki_source_ext.items_total = 4
      && (match Wiki_source_ext.module_percent c with Some p -> close p 75.0 | None -> false)
      && (match Wiki_source_ext.item_percent c with Some p -> close p 75.0 | None -> false)
      && Wiki_source_ext.undetermined c = []);
  check "N5 HW.9.2.2 the ROUND TRIP holds: patch before (diff before after) = after" (fun () ->
      let before = [ "one"; "TWO"; "three" ] and after = [ "one"; "two"; "three" ] in
      let d = Wiki_source_ext.diff_lines ~before ~after in
      Wiki_source_ext.patch ~before d = Ok after);
  check "N6 the diff directive is `literalinclude` + diff=, and it renders both sides" (fun () ->
      match Wiki_source_ext.diff_of_info ~read "literalinclude after.ml diff=before.ml" with
      | Some (Ok r) ->
          r.Wiki_source_ext.before = [ "one"; "TWO"; "three" ]
          && r.Wiki_source_ext.after = [ "one"; "two"; "three" ]
          && Wiki_source_ext.patch ~before:r.Wiki_source_ext.before r.Wiki_source_ext.edits
             = Ok r.Wiki_source_ext.after
          && contains (Wiki_source_ext.diff_html r.Wiki_source_ext.edits) "-TWO"
          && contains (Wiki_source_ext.diff_html r.Wiki_source_ext.edits) "+two"
      | _ -> false);
  check "N7 HW.9.2.3 every emitted cross-link RESOLVES in the injected source" (fun () ->
      let x = Wiki_source_ext.cross_links ~read ~iface:"m.mli" ~impl:(Some "m.ml") in
      x.Wiki_source_ext.links <> []
      && List.for_all
           (fun (l : Wiki_source_ext.xref) -> Wiki_source_ext.resolves ~read l.Wiki_source_ext.target)
           x.Wiki_source_ext.links);
  check "N8 the cross-link href addresses a real file and line" (fun () ->
      let x = Wiki_source_ext.cross_links ~read ~iface:"m.mli" ~impl:(Some "m.ml") in
      match x.Wiki_source_ext.links with
      | l :: _ -> l.Wiki_source_ext.name = "apply" && l.Wiki_source_ext.href = "m.ml#L2"
      | [] -> false);
  check "N9 the census DISCLOSES what it counted, in one line, beside the number" (fun () ->
      let c = Wiki_source_ext.census ~read:read_partial [ "full.mli"; "half.mli" ] in
      let s = Wiki_source_ext.summary_line c in
      contains s "2 declared" && contains s "1 UNREADABLE"
      && contains (Wiki_source_ext.census_html c) "2 declared"
      && List.length (Wiki_source_ext.disclosure c) = c.Wiki_source_ext.declared)

(* ---------------------------------------------------------- exhaustion *)

let () =
  check "X1 two thousand vals: every one is a row, none dropped, no raise" (fun () ->
      let body =
        String.concat ""
          (List.init 2000 (fun i -> Printf.sprintf "(* doc %d *)\nval v%d : int\n" i i))
      in
      let rows = Wiki_source_ext.api_rows body in
      List.length rows = 2000
      && List.for_all (fun (r : Wiki_source_ext.api_row) -> r.Wiki_source_ext.documented) rows);
  check "X2 past the LCS bound the diff DEGRADES IN QUALITY, never in correctness" (fun () ->
      let before = List.init 1001 (fun i -> "b" ^ string_of_int i) in
      let after = List.init 1001 (fun i -> "a" ^ string_of_int i) in
      1001 * 1001 > Wiki_source_ext.max_lcs_cells
      && Wiki_source_ext.patch ~before (Wiki_source_ext.diff_lines ~before ~after) = Ok after);
  check "X3 under the bound the diff still finds the common lines (it is a real LCS)" (fun () ->
      let before = List.init 200 string_of_int in
      let after = List.filteri (fun i _ -> i <> 100) before in
      let d = Wiki_source_ext.diff_lines ~before ~after in
      List.length (List.filter (function Wiki_source_ext.Keep _ -> true | _ -> false) d) = 199
      && Wiki_source_ext.patch ~before d = Ok after);
  check "X4 a census over many sources is deterministic and sorted" (fun () ->
      let ps = List.init 200 (fun i -> Printf.sprintf "p%03d.mli" i) in
      let c1 = Wiki_source_ext.census ~read:Wiki_source_ext.no_source ps in
      let c2 = Wiki_source_ext.census ~read:Wiki_source_ext.no_source (List.rev ps) in
      c1.Wiki_source_ext.entries = c2.Wiki_source_ext.entries
      && Wiki_source_ext.disclosure c1 = List.sort compare (Wiki_source_ext.disclosure c1)
      && c1.Wiki_source_ext.declared = 200)

(* --------------------------------------------------------------- stuck *)

let () =
  check "S1 an interface with no vals is a NAMED NOTICE, never an empty <table>" (fun () ->
      let h = Wiki_source_ext.api_table_html mli_types_only in
      Wiki_source_ext.api_rows mli_types_only = []
      && contains h "no values declared"
      && (not (contains h "<table"))
      && contains (Wiki_source_ext.api_table_html "") "no values declared");
  check
    "S2 HW.9.4.1 THE LAW: an unreadable source stays in the denominator, so coverage FALLS"
    (fun () ->
      let ps = [ "full.mli"; "half.mli" ] in
      let whole = Wiki_source_ext.census ~read ps in
      let broken = Wiki_source_ext.census ~read:read_partial ps in
      (* the denominator is IDENTICAL — only the readability changed *)
      whole.Wiki_source_ext.declared = broken.Wiki_source_ext.declared
      && List.length broken.Wiki_source_ext.entries = 2
      && broken.Wiki_source_ext.unreadable = 1
      &&
      match (Wiki_source_ext.module_percent whole, Wiki_source_ext.module_percent broken) with
      | Some w, Some b -> close w 75.0 && close b 50.0 && b < w
      | _ -> false);
  check "S3 the unreadable source is DISCLOSED with a reason, never silently dropped" (fun () ->
      let c = Wiki_source_ext.census ~read:read_partial [ "full.mli"; "half.mli" ] in
      List.exists (fun l -> contains l "half.mli" && contains l "could not be read")
        (Wiki_source_ext.disclosure c)
      && List.exists (fun r -> contains r "half.mli") (Wiki_source_ext.undetermined c)
      && contains (Wiki_source_ext.census_html c) "half.mli");
  check "S4 an item RATE with a missing input is not a smaller rate, it is UNDETERMINED" (fun () ->
      let c = Wiki_source_ext.census ~read:read_partial [ "full.mli"; "half.mli" ] in
      Wiki_source_ext.item_percent c = None
      && Wiki_source_ext.undetermined c <> []
      && contains (Wiki_source_ext.census_html c) "UNDETERMINED");
  check "S5 a source declaring no values is 0%, not 100% — 0/0 survives aggregation" (fun () ->
      let c = Wiki_source_ext.census ~read [ "none.mli" ] in
      c.Wiki_source_ext.no_values = 1
      && (match Wiki_source_ext.module_percent c with Some p -> close p 0.0 | None -> false)
      && Wiki_source_ext.item_percent c = None
      && List.exists (fun l -> contains l "0/0 is not 100%") (Wiki_source_ext.disclosure c));
  check "S6 identical slices are an EMPTY DIFF, which is a diagnostic, never a blank block"
    (fun () ->
      match Wiki_source_ext.diff_of_info ~read "literalinclude same.ml diff=same.ml" with
      | Some (Error e) -> contains e "diff is empty" && contains e "same.ml"
      | _ -> false);
  check "S7 the default reader resolves NOTHING and says so on every surface" (fun () ->
      let c = Wiki_source_ext.census ~read:Wiki_source_ext.no_source [ "full.mli" ] in
      c.Wiki_source_ext.unreadable = 1
      && Wiki_source_ext.item_percent c = None
      && (match Wiki_source_ext.module_percent c with Some p -> close p 0.0 | None -> false)
      && (let x =
            Wiki_source_ext.cross_links ~read:Wiki_source_ext.no_source ~iface:"m.mli" ~impl:None
          in
          x.Wiki_source_ext.links = []
          && List.exists (fun g -> contains g "cannot read interface") x.Wiki_source_ext.gaps)
      && (match
            Wiki_source_ext.diff_of_info ~read:Wiki_source_ext.no_source
              "literalinclude after.ml diff=before.ml"
          with
         | Some (Error e) -> contains e "cannot read"
         | _ -> false));
  check "S8 an undocumented val is a ROW, marked — a gap the table hides is a gap nobody fixes"
    (fun () ->
      let rows = Wiki_source_ext.api_rows mli_half in
      List.length rows = 2
      && (match List.rev rows with
         | b :: _ -> (not b.Wiki_source_ext.documented) && b.Wiki_source_ext.summary = ""
         | [] -> false)
      && contains (Wiki_source_ext.api_table_html mli_half) "undocumented");
  check "S9 a val with no definition in the implementation is a GAP, and no link" (fun () ->
      let x = Wiki_source_ext.cross_links ~read ~iface:"m.mli" ~impl:(Some "m.ml") in
      List.length x.Wiki_source_ext.links = 1
      && List.exists (fun g -> contains g "no definition of ghost") x.Wiki_source_ext.gaps
      && contains (Wiki_source_ext.xref_html x) "no definition of ghost");
  check "S10 an unreadable implementation is a gap per val, never a link into nothing" (fun () ->
      let x = Wiki_source_ext.cross_links ~read ~iface:"m.mli" ~impl:(Some "absent.ml") in
      x.Wiki_source_ext.links = []
      && List.length x.Wiki_source_ext.gaps = 2
      && List.for_all (fun g -> contains g "cannot read implementation") x.Wiki_source_ext.gaps)

(* ------------------------------------------------------------- anomaly *)

let () =
  check "A1 a doc comment cannot inject markup into the API table" (fun () ->
      let h = Wiki_source_ext.api_table_html mli_hostile in
      (not (contains h "<script>"))
      && contains h "&lt;script&gt;"
      && contains h "&amp;"
      && not (contains h "\"quotes\""));
  check "A2 a source line cannot inject markup into a rendered diff" (fun () ->
      let d = Wiki_source_ext.diff_lines ~before:[] ~after:[ "let f = \"<b>&\"" ] in
      let h = Wiki_source_ext.diff_html d in
      (not (contains h "<b>")) && contains h "&lt;b&gt;" && contains h "&amp;");
  check "A3 an OUT-OF-RANGE line is a named diagnostic, NEVER a clamped line number" (fun () ->
      match Wiki_source_ext.xref_of ~read ~name:"z" { Wiki_source_ext.file = "m.ml"; line = 99 } with
      | Error e -> contains e "outside" && contains e "m.ml" && contains e "99"
      | Ok _ -> false);
  check "A4 resolution is a real check: a missing file and a zero line both fail" (fun () ->
      (not (Wiki_source_ext.resolves ~read { Wiki_source_ext.file = "ghost.ml"; line = 1 }))
      && (not (Wiki_source_ext.resolves ~read { Wiki_source_ext.file = "m.ml"; line = 0 }))
      && (not (Wiki_source_ext.resolves ~read { Wiki_source_ext.file = "m.ml"; line = 3 }))
      && Wiki_source_ext.resolves ~read { Wiki_source_ext.file = "m.ml"; line = 2 });
  check "A5 a trailing newline TERMINATES the last line (the slice reading)" (fun () ->
      Wiki_source_ext.line_count "" = 0
      && Wiki_source_ext.line_count "a" = 1
      && Wiki_source_ext.line_count "a\nb\n" = 2
      && Wiki_source_ext.line_count "a\nb" = 2
      && Wiki_source_ext.line_count "\n" = 1);
  check "A6 `let apply` does not resolve to `let apply_start` — the match is TOKEN-BOUNDED"
    (fun () ->
      let x = Wiki_source_ext.cross_links ~read ~iface:"m.mli" ~impl:(Some "m.ml") in
      match x.Wiki_source_ext.links with
      | l :: _ -> l.Wiki_source_ext.target.Wiki_source_ext.line = 2
      | [] -> false);
  check "A7 a diff REFUSES to apply to a slice it does not derive from" (fun () ->
      let d = Wiki_source_ext.diff_lines ~before:[ "one"; "TWO" ] ~after:[ "one"; "two" ] in
      (* the CONTEXT lines are checked too, not only the deletions: a
         patch that trusts its Keeps reproduces the right answer from the
         wrong slice, which is derivation by coincidence *)
      (match Wiki_source_ext.patch ~before:[ "ONE"; "TWO" ] d with
      | Error e -> contains e "does not derive" && contains e "context"
      | Ok _ -> false)
      && (match Wiki_source_ext.patch ~before:[ "one"; "OTHER" ] d with
         | Error e -> contains e "does not derive"
         | Ok _ -> false)
      && (match Wiki_source_ext.patch ~before:[] d with
         | Error e -> contains e "does not derive"
         | Ok _ -> false)
      && match Wiki_source_ext.patch ~before:[ "one"; "TWO"; "extra" ] d with
         | Error e -> contains e "does not derive"
         | Ok _ -> false);
  check "A8 the DENOMINATOR does not move when readability does" (fun () ->
      let ps = [ "full.mli"; "half.mli"; "none.mli" ] in
      let a = Wiki_source_ext.census ~read ps in
      let b = Wiki_source_ext.census ~read:read_partial ps in
      let c = Wiki_source_ext.census ~read:Wiki_source_ext.no_source ps in
      a.Wiki_source_ext.declared = 3 && b.Wiki_source_ext.declared = 3
      && c.Wiki_source_ext.declared = 3
      && List.length a.Wiki_source_ext.entries = 3
      && List.length b.Wiki_source_ext.entries = 3
      && List.length c.Wiki_source_ext.entries = 3);
  check "A9 UNREADABLE is not NO_VALUES: the benign bucket cannot hide a missing file" (fun () ->
      let c = Wiki_source_ext.census ~read:read_partial [ "half.mli"; "none.mli" ] in
      c.Wiki_source_ext.unreadable = 1 && c.Wiki_source_ext.no_values = 1
      && List.exists
           (fun (e : Wiki_source_ext.entry) ->
             e.Wiki_source_ext.path = "half.mli"
             && match e.Wiki_source_ext.status with Wiki_source_ext.Unreadable _ -> true | _ -> false)
           c.Wiki_source_ext.entries
      && List.exists
           (fun (e : Wiki_source_ext.entry) ->
             e.Wiki_source_ext.path = "none.mli"
             && match e.Wiki_source_ext.status with Wiki_source_ext.No_values _ -> true | _ -> false)
           c.Wiki_source_ext.entries);
  check "A10 a census over NOTHING is not 0% and not 100% — it is no census" (fun () ->
      let c = Wiki_source_ext.census ~read [] in
      c.Wiki_source_ext.declared = 0
      && Wiki_source_ext.module_percent c = None
      && Wiki_source_ext.item_percent c = None);
  check "A11 a path declared twice is one source, not two votes" (fun () ->
      let c = Wiki_source_ext.census ~read [ "full.mli"; "full.mli"; "half.mli" ] in
      c.Wiki_source_ext.declared = 2 && c.Wiki_source_ext.items_total = 4);
  check "A12 `diff=` is an OPTION on literalinclude — the base directive ignores it" (fun () ->
      match Wiki_include.parse "literalinclude after.ml diff=before.ml lines=1-3" with
      | Some d ->
          d.Wiki_include.path = "after.ml"
          && d.Wiki_include.bad = []
          && d.Wiki_include.lines = Some (1, 3)
          && Wiki_source_ext.diff_selector "literalinclude after.ml diff=before.ml lines=1-3"
             = Some "before.ml"
      | None -> false);
  check "A13 the SAME selectors apply to both sides, so the slices are comparable" (fun () ->
      match
        Wiki_source_ext.diff_of_info ~read "literalinclude after.ml diff=before.ml lines=2-3"
      with
      | Some (Ok r) ->
          r.Wiki_source_ext.before = [ "TWO"; "three" ]
          && r.Wiki_source_ext.after = [ "two"; "three" ]
      | _ -> false);
  check "A14 a plain literalinclude, and a non-include, are NOT this directive" (fun () ->
      Wiki_source_ext.diff_of_info ~read "literalinclude after.ml" = None
      && Wiki_source_ext.diff_of_info ~read "ocaml" = None
      && Wiki_source_ext.diff_selector "ocaml emphasize=2" = None);
  check "A15 `literalinclude` with diff= and no path is a diagnostic, not silence" (fun () ->
      (* the base directive would take `diff=before.ml` as its own path *)
      match Wiki_source_ext.diff_of_info ~read "literalinclude diff=before.ml" with
      | Some (Error e) -> contains e "no path"
      | _ -> false);
  check "A16 an unmatched marker on either side surfaces NAMED, and says which side" (fun () ->
      (match
         Wiki_source_ext.diff_of_info ~read "literalinclude after.ml diff=before.ml start-after=NOPE"
       with
      | Some (Error e) -> contains e "before side" && contains e "never matched"
      | _ -> false)
      && match Wiki_source_ext.diff_of_info ~read "literalinclude after.ml diff=same.ml lines=1-3" with
         | Some (Error e) -> contains e "before side" && contains e "out of range"
         | _ -> false);
  check "A17 the ROUND TRIP is a property, not an example: 200 pseudo-random pairs" (fun () ->
      let seed = ref 12345 in
      let next () = seed := ((!seed * 1103515245) + 12345) land 0x3FFFFFFF; !seed in
      let gen () = List.init (next () mod 9) (fun _ -> string_of_int (next () mod 5)) in
      List.for_all
        (fun _ ->
          let before = gen () and after = gen () in
          Wiki_source_ext.patch ~before (Wiki_source_ext.diff_lines ~before ~after) = Ok after)
        (List.init 200 (fun i -> i)));
  check "A18 TOTAL over pathological interface text" (fun () ->
      List.for_all
        (fun s ->
          let _ = Wiki_source_ext.api_rows s in
          let _ = Wiki_source_ext.api_table_html s in
          let _ = Wiki_source_ext.census ~read:(fun _ -> Some s) [ "p.mli" ] in
          let _ = Wiki_source_ext.cross_links ~read:(fun _ -> Some s) ~iface:"p.mli" ~impl:None in
          true)
        [ ""; "(*"; "(* nested (* deep *)"; "val"; "val :"; "val a :"; "\r\nval a : int\r\n";
          "val a : int"; String.make 5000 '('; "(* \" *) val a : int\n" ]);
  check "A19 an empty diff on both sides is the empty script, and it round-trips" (fun () ->
      Wiki_source_ext.diff_lines ~before:[] ~after:[] = []
      && Wiki_source_ext.patch ~before:[] [] = Ok []);
  check "A20 the census entry for an unreadable source is 0%, WITH ITS REASON attached" (fun () ->
      let c = Wiki_source_ext.census ~read:read_partial [ "half.mli" ] in
      match c.Wiki_source_ext.entries with
      | [ e ] ->
          close e.Wiki_source_ext.percent 0.0
          && e.Wiki_source_ext.documented = 0
          && e.Wiki_source_ext.total = 0
          && (match e.Wiki_source_ext.status with
             | Wiki_source_ext.Unreadable r -> contains r "counted at 0%"
             | _ -> false)
      | _ -> false)

let () =
  Printf.printf "wiki_source_ext: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_source_ext" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_source_ext ]);
  exit (Wiki_suite_telemetry.exit_code self)
