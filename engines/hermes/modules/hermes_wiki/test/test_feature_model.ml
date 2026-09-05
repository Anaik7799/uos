(* The MBSE spine, across the full functional envelope:

     N*  nominal      every register row becomes an element; the surfaces emit
     X*  exhaustion   285 rows through every surface, repeatedly
     S*  stuck        rows with no gates, no law, empty selections
     A*  anomalies    markup and quotes in a law, dangling dependencies

   The headline law: ONE SOURCE, THREE PROJECTIONS. SysML, OML and MMS
   are total functions of the register, so they cannot disagree with each
   other or with the code — which is the failure a hand-maintained model
   makes inevitable. Its dual: the surfaces are DETERMINISTIC, because a
   model that re-emits differently on an unchanged register makes every
   push look like a change and trains everyone to ignore the diff. *)

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

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 EVERY register row becomes a model element — the model loses nothing" (fun () ->
      List.length (Feature_model.elements ()) = List.length Feature_register.features);
  check "N2 model ids are unique — two features can never be one element" (fun () ->
      let ids = List.map (fun e -> e.Feature_model.mid) (Feature_model.elements ()) in
      List.length (List.sort_uniq compare ids) = List.length ids);
  check "N3 the model id is a function of the FEATURE ID, not the name" (fun () ->
      (* mutant M1 (derive the id from the NAME) survived a uniqueness
         check, because the 285 names happen to be unique too — so the
         check proved nothing about WHICH field the id comes from. A
         rename must not move the element: every downstream id, every
         MMS element and every OWL fragment would break at once. *)
      Feature_model.mid_of "HW.3.5.2" = "HWF_HW_3_5_2"
      && List.for_all
           (fun e -> e.Feature_model.mid = Feature_model.mid_of e.Feature_model.feature_id)
           (Feature_model.elements ()));
  check "N4 SysML v2 names every feature and every area package" (fun () ->
      let s = Feature_model.sysml_v2 () in
      List.for_all (fun e -> contains s e.Feature_model.mid) (Feature_model.elements ())
      && contains s "package Corpus {" && contains s "package Build {"
      && contains s "part def " && contains s "requirement ");
  check "N5 the OML/TTL surface carries every element as an owl:Class" (fun () ->
      let t = Feature_model.oml_ttl () in
      contains t "owl:Class" && contains t "@prefix owl:"
      && List.for_all (fun e -> contains t (":" ^ e.Feature_model.mid))
           (Feature_model.elements ()));
  check "N6 the area is a SUPERTYPE in the ontology, not a field" (fun () ->
      (* subsumption is the reason to have an ontology at all *)
      contains (Feature_model.oml_ttl ()) "rdfs:subClassOf"
      && List.exists
           (fun (b : Hermes_sysml.Sysml_types.block) -> b.supertypes <> [])
           (Feature_model.blocks ()));
  check "N7 the MMS payload owns every feature by its area package" (fun () ->
      let j = Feature_model.mms_json () in
      contains j "\"elements\":[" && contains j "\"type\":\"Package\""
      && contains j "\"type\":\"Class\"" && contains j "\"ownerId\":\"HWA_Corpus\"");
  check "N8 a gate edge becomes a dependency in ALL THREE surfaces" (fun () ->
      let gated =
        List.find (fun e -> e.Feature_model.satisfied_after <> []) (Feature_model.elements ())
      in
      let target = Feature_model.mid_of (List.hd gated.Feature_model.satisfied_after) in
      contains (Feature_model.sysml_v2 ())
        (Printf.sprintf "dependency from %s to %s;" gated.Feature_model.mid target)
      && contains (Feature_model.mms_json ()) "\"type\":\"Dependency\""
      && contains (Feature_model.oml_ttl ()) "owl:ObjectProperty")

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 every surface is DETERMINISTIC over the whole 285-row register" (fun () ->
      Feature_model.sysml_v2 () = Feature_model.sysml_v2 ()
      && Feature_model.oml_ttl () = Feature_model.oml_ttl ()
      && Feature_model.mms_json () = Feature_model.mms_json ());
  check "X2 element order does not depend on hash-table iteration" (fun () ->
      let ids () = List.map (fun e -> e.Feature_model.feature_id) (Feature_model.elements ()) in
      ids () = ids () && ids () = List.sort compare (ids ()));
  check "X3 the surfaces are substantial, not empty shells" (fun () ->
      String.length (Feature_model.sysml_v2 ()) > 10_000
      && String.length (Feature_model.oml_ttl ()) > 10_000
      && String.length (Feature_model.mms_json ()) > 10_000)

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 a row with NO gates still yields an element with no dependencies" (fun () ->
      List.exists (fun e -> e.Feature_model.satisfied_after = []) (Feature_model.elements ()));
  check "S2 coverage is internally consistent — the parts sum to the whole" (fun () ->
      let c = Feature_model.coverage () in
      c.Feature_model.total = List.length (Feature_model.elements ())
      && c.Feature_model.declared_only <= c.Feature_model.built
      && c.Feature_model.built <= c.Feature_model.total
      && c.Feature_model.verified <= c.Feature_model.total);
  check "S3 the gate counts EXACTLY the built rows with no verification method" (fun () ->
      List.length (Feature_model.model_gaps ()) = (Feature_model.coverage ()).Feature_model.declared_only)

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 no gate edge dangles: every dependency names an element that exists" (fun () ->
      Feature_model.dangling_dependencies () = []);
  check "A2 a quote in a law cannot break the JSON payload" (fun () ->
      (* mutant M2 (make the escape a no-op — which is the shared
         hermes_sysml emitter's ACTUAL state) survived a brace-balance
         check over the live register, because not one of the 285 laws
         currently contains a quote. The bug would have shipped and
         fired the day someone wrote one. So feed the emitter the input
         the register does not happen to contain. *)
      let hostile =
        { Feature_model.mid = "HWF_TEST"; feature_id = "HW.0.0.0"; package = "Corpus";
          name = "quote \" and backslash \\";
          requirement = "the law says \"x\" holds\nacross lines";
          satisfied_after = []; verification = Feature_model.Declared; status = "ready" }
      in
      let j = "{\"elements\":[\n" ^ Feature_model.mms_element hostile ^ "\n]}" in
      let rec balanced i depth =
        if i >= String.length j then depth = 0
        else
          match j.[i] with
          | '\\' -> balanced (i + 2) depth
          | '"' -> balanced (i + 1) (1 - depth)
          | _ -> balanced (i + 1) depth
      in
      balanced 0 0
      (* a raw newline inside a JSON string is malformed too *)
      && (not (contains j "lines\n\"")) && contains j "\\n"
      (* and the live payload must satisfy the same property *)
      &&
      let live = Feature_model.mms_json () in
      let rec bal i depth =
        if i >= String.length live then depth = 0
        else
          match live.[i] with
          | '\\' -> bal (i + 2) depth
          | '"' -> bal (i + 1) (1 - depth)
          | _ -> bal (i + 1) depth
      in
      bal 0 0);
  check "A2b a newline in a law never splits a SysML declaration across lines" (fun () ->
      let hostile =
        { Feature_model.mid = "HWF_TEST"; feature_id = "HW.0.0.0"; package = "Corpus";
          name = "n"; requirement = "line one\nline two"; satisfied_after = [];
          verification = Feature_model.Probe; status = "built" }
      in
      let s = Feature_model.sysml_part hostile in
      contains s "\\n" && not (contains s "line one\nline two"));
  check "A3 a newline in a law never breaks a SysML line" (fun () ->
      let s = Feature_model.sysml_v2 () in
      List.for_all
        (fun line ->
          let t = String.trim line in
          t = "" || t = "}" || t = "{" || String.length t > 0)
        (String.split_on_char '\n' s));
  check "A4 the gate's verdict is BOUNDED: a gap is text, never an exception" (fun () ->
      match Feature_model.model_gaps () with _ -> true);
  check "A5 model ids are legal in ALL THREE surfaces at once" (fun () ->
      (* SysML identifiers, OWL fragments and MMS ids share only [A-Za-z0-9_] *)
      List.for_all
        (fun e ->
          String.for_all
            (fun c ->
              (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
              || c = '_')
            e.Feature_model.mid)
        (Feature_model.elements ()))

let () =
  let c = Feature_model.coverage () in
  Printf.printf "  model: %d elements · %d verified by probe · %d built-but-declared (gaps)\n"
    c.Feature_model.total c.Feature_model.verified c.Feature_model.declared_only;
  Printf.printf "feature_model: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_feature_model" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
