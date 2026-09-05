(* HW.3.5.1 — note transclusion, across the full functional envelope:

     N*  nominal      an embed denotes its source, with provenance
     X*  exhaustion   depth bound, wide fan-out, a large body
     S*  stuck        unresolvable target, empty body, self-embed
     A*  anomaly      cycles, malformed syntax, embeds inside fences

   The headline law: THE EMBED DENOTES ITS SOURCE, so drift between an
   embed and the note it embeds is unrepresentable. Its dual matters as
   much: every failure is LOUD — a silent empty embed would make a
   missing definition look like a definition that says nothing. *)

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

let corpus =
  [ ("alpha", "Alpha body.");
    ("beta", "Beta body with ![[alpha]] inside.");
    ("loop_a", "A then ![[loop_b]]");
    ("loop_b", "B then ![[loop_a]]");
    ("deep1", "d1 ![[deep2]]");
    ("deep2", "d2 ![[deep3]]");
    ("deep3", "d3 ![[deep4]]");
    ("deep4", "d4 leaf");
    ("empty", "") ]

let lookup t = List.assoc_opt t corpus |> Option.map (fun b -> (t, b))
let run ?depth ~self raw = Wiki_transclude.expand ?depth ~lookup ~self raw

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 THE EMBED DENOTES ITS SOURCE: the target's bytes appear" (fun () ->
      let r = run ~self:"host" "before ![[alpha]] after" in
      contains r.Wiki_transclude.text "Alpha body."
      && contains r.Wiki_transclude.text "before"
      && contains r.Wiki_transclude.text "after");
  check "N2 every embed carries a PROVENANCE chip back to its source" (fun () ->
      let r = run ~self:"host" "![[alpha]]" in
      contains r.Wiki_transclude.text "embedded from [[alpha]]");
  check "N3 embeds NEST: an embedded note's own embeds expand" (fun () ->
      let r = run ~self:"host" "![[beta]]" in
      contains r.Wiki_transclude.text "Beta body"
      && contains r.Wiki_transclude.text "Alpha body."
      && r.Wiki_transclude.embedded = [ "alpha"; "beta" ]);
  check "N4 a document with no embed is returned UNCHANGED, byte for byte" (fun () ->
      let src = "plain text\n\n- a list\n" in
      let r = run ~self:"host" src in
      r.Wiki_transclude.text = src && r.Wiki_transclude.embedded = []);
  check "N5 a DIAMOND is not a cycle: two siblings may embed one target" (fun () ->
      let r = run ~self:"host" "![[alpha]] and again ![[alpha]]" in
      r.Wiki_transclude.cycles = []
      && (let n = ref 0 and t = r.Wiki_transclude.text in
          String.iteri (fun i _ -> if i + 11 <= String.length t
                                   && String.sub t i 11 = "Alpha body." then incr n) t;
          !n = 2))

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 the DEPTH BOUND stops expansion and REPORTS it (never silently)" (fun () ->
      let r = run ~depth:2 ~self:"host" "![[deep1]]" in
      r.Wiki_transclude.truncated <> []
      && contains (List.hd r.Wiki_transclude.truncated) "bound REPORTED"
      && contains r.Wiki_transclude.text "embed depth 2 reached");
  check "X2 a deeper bound reaches further — the bound is the only limit" (fun () ->
      let shallow = run ~depth:1 ~self:"host" "![[deep1]]" in
      let deeper = run ~depth:4 ~self:"host" "![[deep1]]" in
      List.length deeper.Wiki_transclude.embedded > List.length shallow.Wiki_transclude.embedded
      && contains deeper.Wiki_transclude.text "d4 leaf");
  check "X3 wide fan-out on one line is handled" (fun () ->
      let line = String.concat " " (List.init 50 (fun _ -> "![[alpha]]")) in
      let r = run ~self:"host" line in
      r.Wiki_transclude.embedded = [ "alpha" ] && r.Wiki_transclude.missing = [])

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 an UNRESOLVABLE target is loud in the text AND reported" (fun () ->
      let r = run ~self:"host" "![[ghost]]" in
      contains r.Wiki_transclude.text "embed unresolved: ghost"
      && List.length r.Wiki_transclude.missing = 1);
  check "S2 an EMPTY target embeds emptily but still reports provenance" (fun () ->
      let r = run ~self:"host" "![[empty]]" in
      contains r.Wiki_transclude.text "embedded from [[empty]]"
      && r.Wiki_transclude.missing = []);
  check "S3 a page embedding ITSELF is a cycle at depth zero" (fun () ->
      let r = run ~self:"alpha" "![[alpha]]" in
      r.Wiki_transclude.cycles <> [] && contains r.Wiki_transclude.text "embed cycle")

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 a CYCLE terminates, is broken where it closes, and is named" (fun () ->
      let r = run ~self:"host" "![[loop_a]]" in
      r.Wiki_transclude.cycles <> []
      && contains (List.hd r.Wiki_transclude.cycles) "already on the path"
      && contains r.Wiki_transclude.text "A then"
      && contains r.Wiki_transclude.text "B then");
  check "A2b an embed inside INLINE BACKTICKS is an example, not a use" (fun () ->
      (* the live corpus had 25 of these and zero real embeds *)
      let r = run ~self:"host" "the `![[alpha]]` form embeds a note" in
      (not (contains r.Wiki_transclude.text "Alpha body.")) && r.Wiki_transclude.embedded = []);
  check "A2 an embed inside a CODE FENCE is an example, not a use" (fun () ->
      let r = run ~self:"host" "```\n![[alpha]]\n```\n" in
      (not (contains r.Wiki_transclude.text "Alpha body."))
      && r.Wiki_transclude.embedded = []);
  check "A3 an UNTERMINATED embed is left as text, never raised" (fun () ->
      let r = run ~self:"host" "![[alpha" in
      r.Wiki_transclude.text = "![[alpha" && r.Wiki_transclude.missing = []);
  check "A4 an ORDINARY wikilink is untouched — only ![[ ]] embeds" (fun () ->
      let r = run ~self:"host" "see [[alpha]] please" in
      r.Wiki_transclude.text = "see [[alpha]] please" && r.Wiki_transclude.embedded = []);
  check "A5 TOTAL over pathological input" (fun () ->
      List.for_all
        (fun s -> match run ~self:"h" s with _ -> true)
        [ ""; "!"; "!["; "![["; "![[]]"; "![[ ]]"; "]]"; String.make 2000 '!' ]);
  check "A6 an empty target name resolves to nothing and says so" (fun () ->
      let r = run ~self:"host" "![[]]" in
      r.Wiki_transclude.missing <> [] || r.Wiki_transclude.text = "![[]]")


(* -------------------------------- HW.3.5.2 BLOCK transclusion, ^id *)

let with_blocks t =
  match t with
  | "claims" ->
      Some ("claims", "Intro line.\n\nThe parity claim holds. ^parity\n\n- a list item ^item\n\nTail.")
  | _ -> None

let runb ~self raw = Wiki_transclude.expand ~lookup:with_blocks ~self raw

let () =
  check "B1 a block embed quotes ONE block, not the page around it" (fun () ->
      let r = runb ~self:"host" "![[claims#^parity]]" in
      contains r.Wiki_transclude.text "The parity claim holds."
      && (not (contains r.Wiki_transclude.text "Intro line."))
      && not (contains r.Wiki_transclude.text "Tail."));
  check "B2 the ^id marker is STRIPPED from the quoted text (the chip may name it)"
    (fun () ->
      let r = runb ~self:"host" "![[claims#^parity]]" in
      (* the block itself must not carry its own address; the provenance
         chip legitimately does, which is why this checks the joined form *)
      contains r.Wiki_transclude.text "The parity claim holds.\n"
      && not (contains r.Wiki_transclude.text "holds. ^parity"));
  check "B3 provenance names the BLOCK, not merely the page" (fun () ->
      contains (runb ~self:"host" "![[claims#^parity]]").Wiki_transclude.text
        "embedded from [[claims#^parity]]");
  check "B4 a list item is addressable too" (fun () ->
      contains (runb ~self:"host" "![[claims#^item]]").Wiki_transclude.text "a list item");
  check "B5 a MISSING block NEVER widens to the whole page — it fails loudly"
    (fun () ->
      let r = runb ~self:"host" "![[claims#^ghost]]" in
      r.Wiki_transclude.missing <> []
      && contains (List.hd r.Wiki_transclude.missing) "page exists, block does not"
      && not (contains r.Wiki_transclude.text "Intro line."));
  check "B6 a page embed still embeds the WHOLE page (no regression)" (fun () ->
      contains (runb ~self:"host" "![[claims]]").Wiki_transclude.text "Intro line.");
  check "B7 Wiki_transclude.block is fence-aware: a ^id in a fence is an example"
    (fun () ->
      Wiki_transclude.block ~id:"x" "```\nfenced ^x\n```\n" = None
      && Wiki_transclude.block ~id:"x" "real ^x\n" = Some "real")

let () =
  Printf.printf "wiki_transclude: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_transclude" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_transclude ]);
  exit (Wiki_suite_telemetry.exit_code self)
