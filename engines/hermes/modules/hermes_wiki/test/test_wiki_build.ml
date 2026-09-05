(* The build pipeline, across the full functional envelope:

     N*  nominal      the six rows' laws on ordinary corpora
     X*  exhaustion   a large corpus, a change set touching everything,
                      a deep chain, wide fan-out, ALL permutations
     S*  stuck        an empty corpus, no changes, a change to an absent
                      document, a LYING change set, a nonsense worker count
     A*  anomaly      cycles, self-dependency, duplicate slugs, a retitle
                      that re-keys the resolver, pathological bytes

   THE HEADLINE LAW: an incremental build equals a full build, byte for
   byte, and a parallel build equals a serial one, byte for byte. Both are
   PROVED here by differential rather than asserted — and every
   differential also asserts that work was actually skipped, because a
   cache that quietly rebuilds everything passes an equality test while
   proving nothing at all. *)

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

(* ------------------------------------------------------------------ *)
(* Corpora                                                             *)
(* ------------------------------------------------------------------ *)

let doc name body = ("docs/hermes/zk/" ^ name ^ ".md", body)
let path_of name = "docs/hermes/zk/" ^ name ^ ".md"

let edit name body corpus =
  List.map (fun (p, b) -> if p = path_of name then (p, body) else (p, b)) corpus

(* delta links a page that does not exist yet — on purpose: adding and
   removing epsilon is how the EXISTENCE leg of the fingerprint gets
   exercised, and a corpus with no dangling edge cannot exercise it. *)
let base =
  [ doc "alpha" "# Alpha\n\nSee [[beta]] and [[gamma]].\n";
    doc "beta" "# Beta\n\nSee [[gamma]].\n";
    doc "gamma" "# Gamma\n\nLeaf.\n";
    doc "delta" "# Delta\n\nSee [[epsilon]].\n" ]

let base_edited = edit "gamma" "# Gamma\n\nLeaf, revised.\n" base
let with_epsilon = base @ [ doc "epsilon" "# Epsilon\n\nNew.\n" ]

let slugs_of corpus =
  List.map
    (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug)
    (Hermes_wiki.build corpus).Hermes_wiki.pages

let out t = Wiki_build.outputs t
let prof t = t.Wiki_build.profile

let rec perms = function
  | [] -> [ [] ]
  | xs ->
      List.concat_map
        (fun x -> List.map (fun p -> x :: p) (perms (List.filter (fun y -> y <> x) xs)))
        xs

(* ------------------------------------------------------------------ *)
(* N — nominal                                                         *)
(* ------------------------------------------------------------------ *)

let () =
  check "N1 NO SECOND RENDERER: the build's digest is Dep_sheaf's glued build"
    (fun () ->
      let m = Hermes_wiki.build base in
      let env = Dep_sheaf.Env.of_model m in
      let glued = Dep_sheaf.Section.bytes (Dep_sheaf.glue (Dep_sheaf.build env m)) in
      let t = Wiki_build.full base in
      String.equal (Wiki_build.digest t) glued && String.length glued > 0);

  check "N2 THE LAW: an edited document rebuilt incrementally = a full rebuild,\
        \ and work was actually SKIPPED" (fun () ->
      let previous = Wiki_build.full base in
      let inc = Wiki_build.incremental ~previous ~changed:[ "gamma" ] base_edited in
      let cold = Wiki_build.full base_edited in
      Wiki_build.equal_outputs inc cold
      && String.equal (Wiki_build.digest inc) (Wiki_build.digest cold)
      (* the corpus really did move: a vacuous differential proves nothing *)
      && not (Wiki_build.equal_outputs cold previous)
      (* and the incremental build really did reuse *)
      && (prof inc).Wiki_build.rebuilt = 1
      && (prof inc).Wiki_build.skipped = 3);

  check "N3 ADDING a page: incremental = full, and the page that LINKED it\
        \ rebuilds although the caller never named it" (fun () ->
      let previous = Wiki_build.full base in
      let inc = Wiki_build.incremental ~previous ~changed:[ "epsilon" ] with_epsilon in
      let cold = Wiki_build.full with_epsilon in
      Wiki_build.equal_outputs inc cold
      && (prof inc).Wiki_build.units_total = 5
      (* epsilon (new) and delta (its dangling link now resolves) *)
      && (prof inc).Wiki_build.rebuilt = 2
      && (prof inc).Wiki_build.skipped = 3);

  check "N4 REMOVING a page: incremental = full, and its linker rebuilds" (fun () ->
      let previous = Wiki_build.full with_epsilon in
      let inc = Wiki_build.incremental ~previous ~changed:[ "epsilon" ] base in
      let cold = Wiki_build.full base in
      Wiki_build.equal_outputs inc cold
      && (prof inc).Wiki_build.units_total = 4
      && (prof inc).Wiki_build.rebuilt = 1
      && (prof inc).Wiki_build.skipped = 3);

  check "N5 HW.10.3.2 the profile counts WORK, exactly and without a clock"
    (fun () ->
      let t = Wiki_build.full base in
      let p = prof t in
      let raw_total =
        List.fold_left (fun a (_, b) -> a + String.length b) 0 base
      in
      let out_total = List.fold_left (fun a (_, b) -> a + String.length b) 0 (out t) in
      p.Wiki_build.units_total = 4
      && p.Wiki_build.rebuilt = 4
      && p.Wiki_build.skipped = 0
      && p.Wiki_build.rebuilt + p.Wiki_build.skipped = p.Wiki_build.units_total
      && p.Wiki_build.source_bytes = raw_total
      && p.Wiki_build.output_bytes = out_total
      (* deterministic: the same corpus profiles identically every time *)
      && prof (Wiki_build.full base) = p);

  check "N5b an incremental profile reads only what it REBUILT" (fun () ->
      let previous = Wiki_build.full base in
      let inc = Wiki_build.incremental ~previous ~changed:[] base_edited in
      let gamma_raw =
        List.assoc (path_of "gamma") base_edited |> String.length
      in
      (prof inc).Wiki_build.source_bytes = gamma_raw
      && (prof inc).Wiki_build.output_bytes = (prof previous).Wiki_build.output_bytes
         - String.length (List.assoc (path_of "gamma") (out previous))
         + String.length (List.assoc (path_of "gamma") (out inc)));

  check "N6 changed_of derives exactly the slugs whose render inputs moved"
    (fun () ->
      let previous = Wiki_build.full base in
      Wiki_build.changed_of ~previous base = []
      && Wiki_build.changed_of ~previous base_edited = [ "gamma" ]
      (* delta appears WITHOUT being edited: its dangling link resolved *)
      && Wiki_build.changed_of ~previous with_epsilon = [ "delta"; "epsilon" ]);

  check "N7 HW.6.9.1 parse o uri = id" (fun () ->
      List.for_all
        (fun s -> Wiki_build.parse (Wiki_build.uri s) = Some s)
        [ "alpha"; "a-b-c"; "under_score"; "0"; "zzz" ]);

  check "N8 the resolver mirror agrees with Dep_sheaf.deps (no second model)"
    (fun () ->
      let m = Hermes_wiki.build with_epsilon in
      let t = Wiki_build.full with_epsilon in
      List.for_all
        (fun (u : Wiki_build.unit_result) ->
          match
            List.find_opt
              (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.path = u.Wiki_build.path)
              m.Hermes_wiki.pages
          with
          | None -> false
          | Some p ->
              let mine =
                List.sort_uniq compare
                  (List.map (fun (_, c, _) -> c) u.Wiki_build.inputs)
              in
              mine = Dep_sheaf.Cover.elements (Dep_sheaf.deps m p))
        t.Wiki_build.units);

  check "N9 HW.10.2.3 a check finds EXACTLY what the build complains about"
    (fun () ->
      let broken =
        [ doc "bad"
            "---\ntype: nonsense\n---\n\n# Bad\n\nSee [[nowhere-at-all]].\n";
          doc "gamma" "# Gamma\n\nLeaf.\n" ]
      in
      let r = Wiki_build.check broken in
      let t = Wiki_build.full broken in
      (* non-vacuous: there IS something to find *)
      r.Wiki_build.complaints <> []
      && r.Wiki_build.complaints = t.Wiki_build.findings
      && List.exists (fun f -> contains f "defect:") r.Wiki_build.complaints
      && r.Wiki_build.checked = 2);

  check "N10 HW.10.3.1 deserialise o serialise = Some" (fun () ->
      let t = Wiki_build.full with_epsilon in
      Wiki_build.deserialise (Wiki_build.serialise t) = Some t);

  check "N11 HW.10.1.3 a parallel build equals a serial one, whole record"
    (fun () ->
      let t = Wiki_build.full base in
      Wiki_build.parallel ~workers:4 base = t
      && Wiki_build.parallel ~workers:1 base = t);

  check "N12 output_path serves an extensionless URL, injectively" (fun () ->
      Wiki_build.output_path "notes" = "notes/index.html"
      && Wiki_build.output_path "" = "index.html"
      && Wiki_build.output_path "index" = "index/index.html"
      && Wiki_build.output_path "index" <> Wiki_build.output_path "");

  (* ---------------------------------------------------------------- *)
  (* X — exhaustion                                                    *)
  (* ---------------------------------------------------------------- *)
  check "X1 a 120-document corpus: one edit rebuilds ONE unit and equals a full\
        \ rebuild" (fun () ->
      let big =
        List.init 120 (fun i ->
            doc
              (Printf.sprintf "big-%03d" i)
              (Printf.sprintf "# Big %d\n\nSee [[big-%03d]].\n" i ((i + 1) mod 120)))
      in
      let big' = edit "big-060" "# Big 60\n\nSee [[big-061]]. Revised.\n" big in
      let previous = Wiki_build.full big in
      let inc = Wiki_build.incremental ~previous ~changed:[ "big-060" ] big' in
      let cold = Wiki_build.full big' in
      Wiki_build.equal_outputs inc cold
      && (prof inc).Wiki_build.units_total = 120
      && (prof inc).Wiki_build.rebuilt = 1
      && (prof inc).Wiki_build.skipped = 119);

  check "X2 a change set naming EVERY document rebuilds everything and still\
        \ equals a full build" (fun () ->
      let previous = Wiki_build.full base in
      let inc = Wiki_build.incremental ~previous ~changed:(slugs_of base) base in
      Wiki_build.equal_outputs inc (Wiki_build.full base)
      && (prof inc).Wiki_build.rebuilt = 4
      && (prof inc).Wiki_build.skipped = 0);

  check "X3 a 40-deep chain: removing the tail rebuilds its predecessor only"
    (fun () ->
      let chain n =
        List.init n (fun i ->
            doc
              (Printf.sprintf "chain-%02d" i)
              (Printf.sprintf "# Chain %d\n\nSee [[chain-%02d]].\n" i (i + 1)))
      in
      let previous = Wiki_build.full (chain 40) in
      let inc = Wiki_build.incremental ~previous ~changed:[ "chain-39" ] (chain 39) in
      let cold = Wiki_build.full (chain 39) in
      Wiki_build.equal_outputs inc cold
      && (prof inc).Wiki_build.units_total = 39
      && (prof inc).Wiki_build.rebuilt = 1
      && (prof inc).Wiki_build.skipped = 38);

  check "X4 ORDER-INDEPENDENCE, exhaustively: 24 permutations x 5 worker counts\
        \ give ONE answer" (fun () ->
      let paths = List.map fst base in
      let reference = Wiki_build.full base in
      let by_order =
        List.for_all
          (fun order -> Wiki_build.in_order ~order base = reference)
          (perms paths)
      in
      let by_workers =
        List.for_all
          (fun w -> Wiki_build.parallel ~workers:w base = reference)
          [ 1; 2; 3; 4; 5; 17 ]
      in
      List.length (perms paths) = 24 && by_order && by_workers);

  check "X5 wide fan-out: one document linking 60 targets builds and round-trips"
    (fun () ->
      let body =
        "# Hub\n\n"
        ^ String.concat " " (List.init 60 (fun i -> Printf.sprintf "[[leaf-%02d]]" i))
        ^ "\n"
      in
      let corpus =
        doc "hub" body
        :: List.init 60 (fun i ->
               doc (Printf.sprintf "leaf-%02d" i) (Printf.sprintf "# Leaf %d\n\n.\n" i))
      in
      let t = Wiki_build.full corpus in
      let hub =
        List.find (fun (u : Wiki_build.unit_result) -> u.Wiki_build.slug = "hub")
          t.Wiki_build.units
      in
      List.length hub.Wiki_build.inputs = 60
      && Wiki_build.deserialise (Wiki_build.serialise t) = Some t
      && Wiki_build.equal_outputs (Wiki_build.parallel ~workers:8 corpus) t);

  (* ---------------------------------------------------------------- *)
  (* S — stuck                                                         *)
  (* ---------------------------------------------------------------- *)
  check "S1 an EMPTY corpus is a defined build, everywhere" (fun () ->
      let t = Wiki_build.full [] in
      let r = Wiki_build.check [] in
      t.Wiki_build.units = []
      && t.Wiki_build.findings = []
      && prof t
         = { Wiki_build.units_total = 0; rebuilt = 0; skipped = 0; source_bytes = 0;
             output_bytes = 0 }
      && Wiki_build.digest t = ""
      && Wiki_build.outputs t = []
      && r.Wiki_build.checked = 0
      && r.Wiki_build.complaints = []
      && r.Wiki_build.bytes_examined = 0
      && Wiki_build.changed_of ~previous:t [] = []
      && Wiki_build.incremental ~previous:t ~changed:[ "ghost" ] [] = t
      && Wiki_build.parallel ~workers:3 [] = t
      && Wiki_build.in_order ~order:[ "nope" ] [] = t
      && Wiki_build.deserialise (Wiki_build.serialise t) = Some t
      && Wiki_build.wasted_cover [] = 0);

  check "S2 NO changes: everything is skipped and the answer is unchanged"
    (fun () ->
      let previous = Wiki_build.full base in
      let inc = Wiki_build.incremental ~previous ~changed:[] base in
      Wiki_build.equal_outputs inc previous
      && (prof inc).Wiki_build.rebuilt = 0
      && (prof inc).Wiki_build.skipped = 4
      && (prof inc).Wiki_build.source_bytes = 0);

  check "S3 a change to a document that DOES NOT EXIST is defined and harmless"
    (fun () ->
      let previous = Wiki_build.full base in
      let inc =
        Wiki_build.incremental ~previous ~changed:[ "no-such-page"; ""; "alpha/../x" ]
          base
      in
      Wiki_build.equal_outputs inc (Wiki_build.full base)
      && (prof inc).Wiki_build.rebuilt = 0);

  check "S4 a LYING change set cannot make the build wrong: soundness never\
        \ depends on the caller" (fun () ->
      let previous = Wiki_build.full base in
      (* the caller says nothing changed; gamma really did *)
      let inc = Wiki_build.incremental ~previous ~changed:[] base_edited in
      let cold = Wiki_build.full base_edited in
      Wiki_build.equal_outputs inc cold
      && (prof inc).Wiki_build.rebuilt = 1
      && (prof inc).Wiki_build.skipped = 3);

  check "S4b a lying change set cannot hide an ADDED page either" (fun () ->
      let previous = Wiki_build.full base in
      let inc = Wiki_build.incremental ~previous ~changed:[] with_epsilon in
      Wiki_build.equal_outputs inc (Wiki_build.full with_epsilon)
      && (prof inc).Wiki_build.rebuilt = 2);

  check "S5 a nonsense worker count CLAMPS rather than raising" (fun () ->
      let t = Wiki_build.full base in
      Wiki_build.parallel ~workers:0 base = t
      && Wiki_build.parallel ~workers:(-7) base = t
      && List.length (Wiki_build.queues ~workers:0 base) = 1
      && List.length (Wiki_build.queues ~workers:3 base) = 3
      && List.sort compare (List.concat (Wiki_build.queues ~workers:3 base))
         = List.sort compare (List.map fst base));

  check "S6 parse REFUSES exactly what uri never produces" (fun () ->
      Wiki_build.parse "" = None
      && Wiki_build.parse "notes" = None
      && Wiki_build.parse "/a/b" = None
      && Wiki_build.parse "/notes/" = None
      && Wiki_build.parse "/a%" = None
      && Wiki_build.parse "/a%z9" = None
      && Wiki_build.parse "/../etc" = None);

  check "S7 deserialise REFUSES malformed input rather than guessing" (fun () ->
      Wiki_build.deserialise "" = None
      && Wiki_build.deserialise "hermes-build 2\nprofile 0 0 0 0 0\n" = None
      && Wiki_build.deserialise "hermes-build 1\n" = None
      && Wiki_build.deserialise "hermes-build 1\nprofile 0 0 0 0\n" = None
      && Wiki_build.deserialise "hermes-build 1\nprofile 0 0 0 0 0\nunit a\n" = None
      && Wiki_build.deserialise "hermes-build 1\nprofile 0 0 0 0 0\nfinding a\\q\n"
         = None
      && Wiki_build.deserialise
           "hermes-build 1\nprofile 0 0 0 0 0\nunit a a a a t c 2\n" = None);

  (* ---------------------------------------------------------------- *)
  (* A — anomalies                                                     *)
  (* ---------------------------------------------------------------- *)
  check "A1 a CYCLE is not a special case: units render against their own\
        \ covers, so there is no order to deadlock" (fun () ->
      let cyc =
        [ doc "ca" "# CA\n\nSee [[cb]].\n"; doc "cb" "# CB\n\nSee [[ca]].\n" ]
      in
      let cyc' = edit "ca" "# CA\n\nSee [[cb]]. Revised.\n" cyc in
      let previous = Wiki_build.full cyc in
      let inc = Wiki_build.incremental ~previous ~changed:[ "ca" ] cyc' in
      Wiki_build.equal_outputs inc (Wiki_build.full cyc')
      && (prof inc).Wiki_build.rebuilt = 1
      && Wiki_build.parallel ~workers:2 cyc = previous);

  check "A2 a document depending on ITSELF builds and stays incremental"
    (fun () ->
      let self = [ doc "sa" "# SA\n\nSee [[sa]].\n" ] in
      let self' = edit "sa" "# SA\n\nSee [[sa]]. More.\n" self in
      let previous = Wiki_build.full self in
      let inc = Wiki_build.incremental ~previous ~changed:[] self' in
      Wiki_build.equal_outputs inc (Wiki_build.full self')
      && (prof inc).Wiki_build.rebuilt = 1
      (* and a self-link is not permanently dirty: with nothing changed the
         unit is REUSED, profile aside (a profile that did not differ would
         mean nothing was skipped) *)
      && Wiki_build.equal_outputs (Wiki_build.incremental ~previous ~changed:[] self)
           previous
      && (prof (Wiki_build.incremental ~previous ~changed:[] self)).Wiki_build.rebuilt
         = 0);

  check "A3 DUPLICATE slugs: two paths, one slug — no unit borrows another's\
        \ bytes" (fun () ->
      let dup =
        [ ("docs/hermes/zk/dup.md", "# One\n\nFirst body.\n");
          ("docs/hermes/wiki/dup.md", "# Two\n\nSecond body, different.\n") ]
      in
      let dup' =
        List.map
          (fun (p, b) ->
            if p = "docs/hermes/wiki/dup.md" then (p, "# Two\n\nEdited body.\n")
            else (p, b))
          dup
      in
      let previous = Wiki_build.full dup in
      let bodies = List.map snd (out previous) in
      let inc = Wiki_build.incremental ~previous ~changed:[ "dup" ] dup' in
      List.length previous.Wiki_build.units = 2
      && (match bodies with [ a; b ] -> not (String.equal a b) | _ -> false)
      && Wiki_build.equal_outputs inc (Wiki_build.full dup'));

  check "A4 the export survives PATHOLOGICAL bytes, including its own grammar"
    (fun () ->
      let nasty =
        [ doc "nasty"
            "# Nasty\n\nA back\\slash, a  double space, a\ttab.\n\n```\nunit a b c\n\
             hermes-build 1\nfinding x\n```\n\nAnd [[gamma]].\n";
          doc "gamma" "# Gamma\n\nLeaf.\n" ]
      in
      let t = Wiki_build.full nasty in
      let s = Wiki_build.serialise t in
      Wiki_build.deserialise s = Some t
      (* the escaping really was needed: the raw bytes contain a newline *)
      && contains (List.assoc (path_of "nasty") nasty) "\n"
      (* and no record ever spans a line: header + profile + findings +
         units, plus the empty tail after the final newline *)
      && List.length (String.split_on_char '\n' s)
         = 2 + List.length t.Wiki_build.findings + List.length t.Wiki_build.units + 1);

  check "A5 a RETITLE re-keys the resolver: the linker's own bytes never\
        \ changed, yet it MUST rebuild" (fun () ->
      let before =
        [ doc "rb" "# Target\n\nBody.\n"; doc "rc" "# RC\n\nSee [[Target]].\n" ]
      in
      let after =
        [ doc "rb" "# Other\n\nBody.\n"; doc "rc" "# RC\n\nSee [[Target]].\n" ]
      in
      let previous = Wiki_build.full before in
      let cold = Wiki_build.full after in
      (* non-vacuous: rc really does render differently either side *)
      let rc t = List.assoc (path_of "rc") (out t) in
      let inc = Wiki_build.incremental ~previous ~changed:[ "rb" ] after in
      (not (String.equal (rc previous) (rc cold)))
      && Wiki_build.equal_outputs inc cold
      && Wiki_build.changed_of ~previous after = [ "rb"; "rc" ]);

  check "A6 HW.6.9.1 the awkward slugs round-trip: a dot, a .md, index, empty"
    (fun () ->
      Wiki_build.uri "notes.v2" = "/notes.v2"
      && Wiki_build.parse "/notes.v2" = Some "notes.v2"
      && Wiki_build.uri "readme.md" = "/readme.md"
      && Wiki_build.parse "/readme.md" = Some "readme.md"
      && Wiki_build.uri "index" = "/index"
      && Wiki_build.parse "/index" = Some "index"
      && Wiki_build.parse "/index" <> Some ""
      && Wiki_build.uri "" = "/"
      && Wiki_build.parse "/" = Some ""
      (* a slug is not licensed to become a second path segment *)
      && Wiki_build.uri "a/b" = "/a%2Fb"
      && Wiki_build.parse (Wiki_build.uri "a/b") = Some "a/b"
      && Wiki_build.parse (Wiki_build.uri "a b") = Some "a b"
      && Wiki_build.parse (Wiki_build.uri "100%") = Some "100%");

  check "A7 HW.10.2.3 the check produces NO artifact and reads what it checked"
    (fun () ->
      let r = Wiki_build.check base in
      let t = Wiki_build.full base in
      r.Wiki_build.checked = List.length t.Wiki_build.units
      && r.Wiki_build.complaints = t.Wiki_build.findings
      && r.Wiki_build.bytes_examined
         = List.fold_left (fun a (_, b) -> a + String.length b) 0 base
      (* a check on a corpus that builds cleanly is silent, not empty-handed *)
      && Wiki_build.check with_epsilon = Wiki_build.check with_epsilon);

  check "A8 the export is CANONICAL: corpus order is not observable" (fun () ->
      String.equal
        (Wiki_build.serialise (Wiki_build.full base))
        (Wiki_build.serialise (Wiki_build.full (List.rev base)))
      && String.equal
           (Wiki_build.serialise (Wiki_build.full base))
           (Wiki_build.serialise (Wiki_build.parallel ~workers:3 base))
      && Wiki_build.outputs (Wiki_build.full base)
         = Wiki_build.outputs (Wiki_build.full (List.rev base)));

  check "A9 the dead-cover gauge is reused, reads ZERO, and can be MOVED"
    (fun () ->
      Wiki_build.wasted_cover base = 0
      && Wiki_build.wasted_cover ~widen_with:[ "ghost-page" ] base > 0);

  check "A10 a corpus whose documents all link a MISSING page still builds,\
        \ incrementally and in parallel" (fun () ->
      let ghosts =
        List.init 6 (fun i ->
            doc (Printf.sprintf "g-%d" i) (Printf.sprintf "# G%d\n\nSee [[absent]].\n" i))
      in
      let previous = Wiki_build.full ghosts in
      let inc = Wiki_build.incremental ~previous ~changed:[ "absent" ] ghosts in
      Wiki_build.equal_outputs inc previous
      && (prof inc).Wiki_build.rebuilt = 0
      && Wiki_build.parallel ~workers:5 ghosts = previous)

let () =
  Printf.printf "wiki_build: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_build" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_build ]);
  exit (Wiki_suite_telemetry.exit_code self)
