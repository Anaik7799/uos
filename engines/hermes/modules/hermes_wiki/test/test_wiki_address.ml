(* THE ADDRESSING FAMILY — five rows, one envelope:

     N*  nominal      a name reaches its thing; the inventory agrees with
                      the resolver in BOTH directions
     X*  exhaustion   depth bounds, wide fan-out, a large corpus
     S*  stuck        undefined name, unreadable path, wrong domain,
                      empty target
     A*  anomaly      cycles, collisions, malformed markers, and the
                      grammar written INSIDE a fence or backticks

   The headline laws, one per row:

     HW.3.9.1  a cross-domain collision is UNREPRESENTABLE — a qualified
               address never falls back to another domain
     HW.3.8.1  the inventory AGREES with the resolver: every entry
               resolves to the slug it names (checked against the
               engine's own rendered href) and every resolvable key is
               published
     HW.3.10.1 one definition; an undefined name is LOUD and is never
               rendered as its own literal marker
     HW.3.10.2 the include denotes the file; acyclic and depth-bounded,
               and the bound is REPORTED
     HW.3.2.3  the author's id overrides the derived slug and survives a
               retitle; two headings claiming one id is a COLLISION,
               reported and never silently resolved *)

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

(* ------------------------------------------------------------- accessors *)

let ekey e = e.Wiki_address.ekey
let edomain e = e.Wiki_address.edomain
let ekind e = e.Wiki_address.ekind
let eslug e = e.Wiki_address.eslug
let txt r = r.Wiki_address.text
let used r = r.Wiki_address.used
let conflicts r = r.Wiki_address.conflicts
let missing r = r.Wiki_address.missing
let cycles r = r.Wiki_address.cycles
let truncated r = r.Wiki_address.truncated
let anomalies r = r.Wiki_address.anomalies
let quiet r = missing r = [] && cycles r = [] && truncated r = [] && anomalies r = []

(* --------------------------------------------------------------- corpus *)

let corpus =
  [ ( "docs/hermes/zk/20260810-parity.md",
      "---\naliases: [Parity Note]\n---\n# Parity Ledger\n\nThe ledger body.\n" );
    ("docs/hermes/journal/2026-08-10-run.md", "# Run Log\n\nThe run body.\n");
    ( "docs/hermes/wiki/glossary.md",
      "---\ntopics: [glossary]\n---\n# Glossary\n\n## Parity\n\nByte equality.\n" );
    ("docs/hermes/specs/2026-08-10-gate.md", "# The Gate Spec\n\nSpec body.\n") ]

let model = Hermes_wiki.build corpus
let inventory = Wiki_address.entries_of_model model

(* The SOUNDNESS oracle: the engine itself. A probe page writes the entry's
   key as a reference; the engine renders an href; the entry's published
   location must be exactly that href, made root-relative. Nothing here
   asks this module whether it is right. *)
let engine_agrees e =
  let payload =
    match ekind e with
    | Wiki_ref.Term -> "[[term:" ^ ekey e ^ "]]"
    | Wiki_ref.Doc | Wiki_ref.Any -> "[[" ^ ekey e ^ "]]"
  in
  let m =
    Hermes_wiki.build (("docs/hermes/wiki/probe.md", "# Probe\n\nsee " ^ payload ^ ".\n") :: corpus)
  in
  let loc = Wiki_address.location e in
  let href = String.sub loc 1 (String.length loc - 1) in
  match Hermes_wiki.page m "probe" with
  | None -> false
  | Some p ->
      contains p.Hermes_wiki.html ("href=\"" ^ href ^ "\"")
      && not (contains p.Hermes_wiki.html "class=\"missing\"")

(* --------------------------------------------------------------- nominal *)

let () =
  check "N1 the domain axis COMPOSES with Wiki_ref's grammar, in either order" (fun () ->
      let a = Wiki_address.parse "zk:doc:parity-ledger" in
      let b = Wiki_address.parse "doc:zk:parity-ledger" in
      a = b
      && a.Wiki_address.domain = Some Wiki_address.Zk
      && a.Wiki_address.reference.Wiki_ref.kind = Wiki_ref.Doc
      && a.Wiki_address.reference.Wiki_ref.target = "parity-ledger");
  check "N2 an UNKNOWN qualifier is target text — a real title keeps its colon" (fun () ->
      let a = Wiki_address.parse "re: subject" in
      a.Wiki_address.domain = None && a.Wiki_address.reference.Wiki_ref.target = "re: subject");
  check "N3 display, rel and the ! opt-out survive the domain peel" (fun () ->
      let a = Wiki_address.parse "!zk:the-note|@supports" in
      a.Wiki_address.domain = Some Wiki_address.Zk
      && a.Wiki_address.reference.Wiki_ref.suppress
      && a.Wiki_address.reference.Wiki_ref.rel = Some "supports"
      && a.Wiki_address.reference.Wiki_ref.target = "the-note"
      && (Wiki_address.parse "journal:x|shown").Wiki_address.reference.Wiki_ref.display
         = Some "shown");
  check "N4 to_wiki ROUND-TRIPS parse on canonical forms (Wiki_ref's own [[...]] shape)"
    (fun () ->
      List.for_all
        (fun s -> Wiki_address.to_wiki (Wiki_address.parse s) = "[[" ^ s ^ "]]")
        [ "zk:x"; "doc:zk:x"; "term:spec:y"; "!journal:z"; "wiki:a|shown"; "plain"; "doc:plain" ]);
  check "N5 the domain set is CLOSED and its names round-trip" (fun () ->
      List.length Wiki_address.domains = 4
      && List.for_all
           (fun d -> Wiki_address.domain_of_name (Wiki_address.domain_name d) = Some d)
           Wiki_address.domains
      && Wiki_address.domain_of_name "Doc" = None
      && Wiki_address.domain_of_name "re" = None);
  check "N6 a document's domain is its stratum (R16); anything else is an ordinary page"
    (fun () ->
      Wiki_address.domain_of_path "docs/hermes/zk/a.md" = Wiki_address.Zk
      && Wiki_address.domain_of_path "docs/hermes/journal/a.md" = Wiki_address.Journal
      && Wiki_address.domain_of_path "docs/hermes/specs/a.md" = Wiki_address.Spec
      && Wiki_address.domain_of_path "docs/hermes/wiki/a.md" = Wiki_address.Wiki
      && Wiki_address.domain_of_path "docs/hermes/elsewhere/a.md" = Wiki_address.Wiki);
  check "N7 INVENTORY SOUND: every entry resolves to the slug it names (engine oracle)"
    (fun () -> inventory <> [] && List.for_all engine_agrees inventory);
  check "N8 INVENTORY COMPLETE: every key the resolver reaches is published" (fun () ->
      List.for_all
        (fun p ->
          List.for_all
            (fun k ->
              k = ""
              || List.exists (fun e -> ekey e = k && ekind e = Wiki_ref.Doc) inventory)
            (Hermes_wiki.resolver_keys p @ Hermes_wiki.alias_keys p))
        model.Hermes_wiki.pages);
  check "N9 the inventory is a FUNCTION: at most one entry per (kind, key)" (fun () ->
      let ks = List.map (fun e -> (ekind e, ekey e)) inventory in
      List.length (List.sort_uniq compare ks) = List.length ks);
  check "N10 every location is ROOT-RELATIVE — a site path, never a URL or a file path"
    (fun () ->
      List.for_all
        (fun e ->
          let l = Wiki_address.location e in
          String.length l > 1 && l.[0] = '/'
          && (not (contains l "://"))
          && (not (contains l ".."))
          && contains l ".html")
        inventory);
  check "N11 a TERM entry publishes its anchor — a term IS a location" (fun () ->
      match List.find_opt (fun e -> ekind e = Wiki_ref.Term) inventory with
      | Some e ->
          ekey e = "parity" && eslug e = "glossary"
          && Wiki_address.location e = "/glossary.html#parity"
      | None -> false);
  check "N12 the DIGEST pins the bytes: order-invariant, and it moves when an address does"
    (fun () ->
      let d = Wiki_address.inventory_digest inventory in
      d = Wiki_address.inventory_digest (List.rev inventory)
      && d <> Wiki_address.inventory_digest (List.tl inventory)
      && String.length d = 32);
  check "N20 the TIER law: an ARCHIVED page never wins a key from a living one" (fun () ->
      (* the archived page is FIRST in corpus order, so only the tier can
         decide this: an archive is a record, not a contestant *)
      let c =
        [ ( "docs/hermes/zk/old-record.md",
            "---\nmaturity: archived\n---\n# Shared Title\n\narchived body\n" );
          ("docs/hermes/zk/living-note.md", "# Shared Title\n\nliving body\n") ]
      in
      let es = Wiki_address.entries_of_model (Hermes_wiki.build c) in
      let probe =
        Hermes_wiki.build (("docs/hermes/wiki/probe.md", "# Probe\n\n[[shared-title]]\n") :: c)
      in
      match List.find_opt (fun e -> ekey e = "shared-title") es with
      | None -> false
      | Some e ->
          eslug e = "living-note"
          && List.exists (fun x -> ekey x = "old-record" && eslug x = "old-record") es
          && (match Hermes_wiki.page probe "probe" with
             | Some p -> contains p.Hermes_wiki.html ("href=\"" ^ eslug e ^ ".html\"")
             | None -> false));
  check "N13 SUBSTITUTION: defined once, expanded at build, the definition consumed" (fun () ->
      let r = Wiki_address.substitute "<!-- subst: proj = Hermes -->\n\n{{proj}} ships.\n" in
      txt r = "\nHermes ships.\n" && used r = [ "proj" ] && conflicts r = [] && quiet r);
  check "N14 a substitution NESTS: a replacement may use another definition" (fun () ->
      let r =
        Wiki_address.substitute
          "<!-- subst: a = A{{b}} -->\n<!-- subst: b = B -->\n\n{{a}}\n"
      in
      contains (txt r) "AB" && used r = [ "a"; "b" ] && quiet r);
  check "N15 INCLUDE: the expansion is the FILE'S BYTES, un-annotated" (fun () ->
      let files = [ ("shared/preamble.md", "# Preamble\n\nShared bytes.\n") ] in
      let r =
        Wiki_address.splice
          ~read:(fun p -> List.assoc_opt p files)
          ~self:"host.md" "before\n<!-- include: shared/preamble.md -->\nafter\n"
      in
      contains (txt r) "# Preamble"
      && contains (txt r) "Shared bytes."
      && contains (txt r) "before" && contains (txt r) "after"
      && used r = [ "shared/preamble.md" ]
      && quiet r);
  check "N16 an include NESTS, and a DIAMOND is not a cycle" (fun () ->
      let files = [ ("a.md", "A\n<!-- include: leaf.md -->"); ("leaf.md", "LEAF") ] in
      let r =
        Wiki_address.splice
          ~read:(fun p -> List.assoc_opt p files)
          ~self:"h.md" "<!-- include: a.md -->\n<!-- include: leaf.md -->\n"
      in
      used r = [ "a.md"; "leaf.md" ] && cycles r = []
      && (let n = ref 0 and t = txt r in
          String.iteri
            (fun i _ -> if i + 4 <= String.length t && String.sub t i 4 = "LEAF" then incr n)
            t;
          !n = 2));
  check "N17 CUSTOM ID: the author's id OVERRIDES the derived slug, marker stripped" (fun () ->
      match Wiki_address.headings_of "## Configuring the gate {#gate-config}\n" with
      | [ h ] ->
          h.Wiki_address.hanchor = "gate-config"
          && h.Wiki_address.htext = "Configuring the gate"
          && h.Wiki_address.hcustom && h.Wiki_address.hlevel = 2
      | _ -> false);
  check "N18 ANCHOR o RETITLE = ANCHOR: rewording the heading moves nothing" (fun () ->
      Wiki_address.anchors_of "## Configuring the gate {#gate-config}\n"
      = Wiki_address.anchors_of "## Something else entirely {#gate-config}\n"
      && Wiki_address.anchors_of "## Configuring the gate {#gate-config}\n" = [ "gate-config" ]
      (* and WITHOUT the declaration the anchor does move — the feature is
         load-bearing, not decorative *)
      && Wiki_address.anchors_of "## Configuring the gate\n"
         <> Wiki_address.anchors_of "## Something else entirely\n");
  check "N19 AGREEMENT: with no declared id, the headings ARE the engine's headings" (fun () ->
      let body = "# Top\n\n## Setup\n\ntext\n\n## Setup\n\n#### Deep One\n\n## Setup\n" in
      let m = Hermes_wiki.build [ ("docs/hermes/wiki/agree.md", body) ] in
      match Hermes_wiki.page m "agree" with
      | None -> false
      | Some p ->
          p.Hermes_wiki.headings
          = List.map
              (fun h ->
                (h.Wiki_address.hlevel, h.Wiki_address.htext, h.Wiki_address.hanchor))
              (Wiki_address.headings_of body))

(* ------------------------------------------------------------ exhaustion *)

let () =
  check "X1 the SUBSTITUTION depth bound stops expansion and REPORTS it" (fun () ->
      let src =
        "<!-- subst: a = A{{b}} -->\n<!-- subst: b = B{{c}} -->\n<!-- subst: c = C -->\n\n{{a}}\n"
      in
      let shallow = Wiki_address.substitute ~depth:1 src in
      let deep = Wiki_address.substitute ~depth:4 src in
      truncated shallow <> []
      && contains (List.hd (truncated shallow)) "bound REPORTED"
      && contains (txt shallow) "substitution depth 1 reached"
      && contains (txt deep) "ABC"
      && truncated deep = []);
  check "X2 the INCLUDE depth bound stops expansion and REPORTS it" (fun () ->
      let files =
        [ ("d1.md", "1\n<!-- include: d2.md -->"); ("d2.md", "2\n<!-- include: d3.md -->");
          ("d3.md", "3\n<!-- include: d4.md -->"); ("d4.md", "4 leaf") ]
      in
      let run depth =
        Wiki_address.splice ~depth
          ~read:(fun p -> List.assoc_opt p files)
          ~self:"h.md" "<!-- include: d1.md -->"
      in
      let shallow = run 2 and deep = run 5 in
      truncated shallow <> []
      && contains (List.hd (truncated shallow)) "bound REPORTED"
      && contains (txt shallow) "include depth 2 reached"
      && contains (txt deep) "4 leaf"
      && List.length (used deep) > List.length (used shallow));
  check "X3 wide fan-out on one line: 50 uses, one definition, no diagnostics" (fun () ->
      let line = String.concat " " (List.init 50 (fun _ -> "{{p}}")) in
      let r = Wiki_address.substitute ("<!-- subst: p = X -->\n" ^ line ^ "\n") in
      used r = [ "p" ] && quiet r
      && (let n = ref 0 and t = txt r in
          String.iter (fun c -> if c = 'X' then incr n) t;
          !n = 50));
  check "X4 a large corpus keeps the inventory sorted, functional and pinned" (fun () ->
      let big =
        List.init 40 (fun i ->
            (Printf.sprintf "docs/hermes/zk/n%02d.md" i, Printf.sprintf "# Note %02d\n\nbody\n" i))
      in
      let es = Wiki_address.entries_of_model (Hermes_wiki.build big) in
      let text = Wiki_address.inventory es in
      let lines = List.filter (fun l -> l <> "") (String.split_on_char '\n' text) in
      let body = List.tl lines in
      body = List.sort compare body
      && List.length es >= 40
      && Wiki_address.inventory_digest es
         = Wiki_address.inventory_digest (List.sort_uniq compare (List.rev es)))

(* ----------------------------------------------------------------- stuck *)

let () =
  check "S1 an UNDEFINED substitution is LOUD, and never its own literal marker" (fun () ->
      let r = Wiki_address.substitute "the {{ghost}} here\n" in
      contains (txt r) "**[undefined substitution: ghost]**"
      && (not (contains (txt r) "{{ghost}}"))
      && List.length (missing r) = 1
      && contains (List.hd (missing r)) "substitution undefined"
      && used r = []);
  check "S2 an UNREADABLE include path is LOUD in the text AND reported" (fun () ->
      let r =
        Wiki_address.splice ~read:(fun _ -> None) ~self:"h.md" "<!-- include: gone.md -->\n"
      in
      contains (txt r) "**[include unresolved: gone.md]**"
      && List.length (missing r) = 1
      && used r = []);
  check "S3 a reader that resolves NOTHING fails closed — never a quietly empty include"
    (fun () ->
      let r = Wiki_address.splice ~read:(fun _ -> None) ~self:"h.md" "a\n<!-- include: x -->\nb\n" in
      contains (txt r) "a" && contains (txt r) "b" && missing r <> []);
  check "S4 THE DOMAIN LAW: a qualified address NEVER falls back to another domain" (fun () ->
      let r q = Wiki_address.resolve inventory (Wiki_address.parse q) in
      (* the ledger is a zk note; asking the journal for it finds nothing *)
      r "journal:parity-ledger" = []
      && r "spec:parity-ledger" = []
      && List.length (r "zk:parity-ledger") = 1
      && List.for_all (fun e -> edomain e = Wiki_address.Zk) (r "zk:parity-ledger")
      (* ...and unqualified, it still resolves: the union over domains *)
      && r "parity-ledger" = r "zk:parity-ledger");
  check "S5 the KIND law survives the domain axis: kind(resolve_k(x)) = k" (fun () ->
      let r q = Wiki_address.resolve inventory (Wiki_address.parse q) in
      List.length (r "term:parity") = 1
      && List.for_all (fun e -> ekind e = Wiki_ref.Term) (r "term:parity")
      && r "doc:parity" = []
      && List.for_all (fun e -> ekind e = Wiki_ref.Doc) (r "doc:glossary"));
  check "S6 an EMPTY or absent target resolves to nothing, and does not raise" (fun () ->
      Wiki_address.resolve inventory (Wiki_address.parse "") = []
      && Wiki_address.resolve inventory (Wiki_address.parse "zk:") = []
      && Wiki_address.resolve inventory (Wiki_address.parse "never-written") = []);
  check "S7 an EMPTY body is total everywhere" (fun () ->
      let r = Wiki_address.substitute "" in
      txt r = "" && quiet r
      && Wiki_address.headings_of "" = []
      && Wiki_address.entries_of_model (Hermes_wiki.build []) = [])

(* --------------------------------------------------------------- anomaly *)

let () =
  check "A1 a SUBSTITUTION CYCLE terminates, is broken where it closes, and is named"
    (fun () ->
      let r =
        Wiki_address.substitute "<!-- subst: a = x{{b}} -->\n<!-- subst: b = y{{a}} -->\n\n{{a}}\n"
      in
      cycles r <> []
      && contains (List.hd (cycles r)) "already on the path"
      && contains (txt r) "**[substitution cycle: a]**"
      && contains (txt r) "xy");
  check "A2 an INCLUDE CYCLE terminates and is named; a self-include is one at depth zero"
    (fun () ->
      let files =
        [ ("a.md", "A\n<!-- include: b.md -->"); ("b.md", "B\n<!-- include: a.md -->") ]
      in
      let read p = List.assoc_opt p files in
      let mutual = Wiki_address.splice ~read ~self:"h.md" "<!-- include: a.md -->" in
      let self = Wiki_address.splice ~read ~self:"a.md" "<!-- include: a.md -->" in
      cycles mutual <> []
      && contains (List.hd (cycles mutual)) "already on the path"
      && contains (txt mutual) "**[include cycle: a.md]**"
      && cycles self <> []
      && contains (txt self) "**[include cycle: a.md]**"
      && used self = []);
  check "A3 a marker inside a CODE FENCE is an EXAMPLE, not a use (25 phantom embeds once)"
    (fun () ->
      let r =
        Wiki_address.substitute
          "<!-- subst: a = X -->\n```\n{{a}}\n<!-- subst: b = Y -->\n```\n{{b}}\n"
      in
      (* the fenced use is untouched, the fenced definition never registered *)
      contains (txt r) "{{a}}"
      && contains (txt r) "<!-- subst: b = Y -->"
      && used r = []
      && List.length (missing r) = 1
      && contains (List.hd (missing r)) "{{b}}"
      && Wiki_address.definitions "```\n<!-- subst: b = Y -->\n```\n" = []);
  check "A4 a marker in INLINE BACKTICKS is an EXAMPLE — no expansion, and no phantom diagnostic"
    (fun () ->
      let s = Wiki_address.substitute "<!-- subst: a = X -->\nthe `{{a}}` form expands\n" in
      let i =
        Wiki_address.splice
          ~read:(fun _ -> Some "SPLICED")
          ~self:"h.md" "write `<!-- include: a.md -->` to include a document\n"
      in
      contains (txt s) "`{{a}}`" && used s = [] && quiet s
      && (not (contains (txt i) "SPLICED"))
      && used i = [] && quiet i);
  check "A5 an id marker inside a CODE FENCE is not a heading at all" (fun () ->
      Wiki_address.headings_of "```\n## Fenced {#id}\n```\n" = []
      && Wiki_address.id_anomalies "```\n## Bad {#}\n```\n" = []);
  check "A6 TWO HEADINGS CLAIMING ONE ID is a COLLISION: both keep it, and it is reported"
    (fun () ->
      let body = "## One {#dup}\n\n## Two {#dup}\n" in
      Wiki_address.anchors_of body = [ "dup"; "dup" ]
      && List.length (Wiki_address.id_collisions body) = 1
      && contains (List.hd (Wiki_address.id_collisions body)) "REPORTED not resolved");
  check "A7 a declared id colliding with an already-DERIVED anchor is reported too" (fun () ->
      let body = "## Setup\n\n## Elsewhere {#setup}\n" in
      Wiki_address.anchors_of body = [ "setup"; "setup" ]
      && Wiki_address.id_collisions body <> []);
  check "A8 a derived anchor after a declared one still de-duplicates (derived names may move)"
    (fun () ->
      Wiki_address.anchors_of "## Elsewhere {#setup}\n\n## Setup\n" = [ "setup"; "setup-1" ]);
  check "A9 a MALFORMED id marker is preserved VERBATIM and named" (fun () ->
      let bad = "## Bad {#}\n" and spaced = "## Bad {#a b}\n" in
      (match Wiki_address.headings_of bad with
      | [ h ] -> h.Wiki_address.htext = "Bad {#}" && not h.Wiki_address.hcustom
      | _ -> false)
      && List.length (Wiki_address.id_anomalies bad) = 1
      && List.length (Wiki_address.id_anomalies spaced) = 1
      && Wiki_address.id_collisions bad = []);
  check "A10 a MISPLACED id marker is preserved VERBATIM and named" (fun () ->
      let mid = "## Mid {#x} tail\n" in
      (match Wiki_address.headings_of mid with
      | [ h ] -> h.Wiki_address.htext = "Mid {#x} tail" && not h.Wiki_address.hcustom
      | _ -> false)
      && List.length (Wiki_address.id_anomalies mid) = 1
      && contains (List.hd (Wiki_address.id_anomalies mid)) "verbatim");
  check "A11 TWO DEFINITIONS of one name: first wins, and the corpus says so" (fun () ->
      let r = Wiki_address.substitute "<!-- subst: a = ONE -->\n<!-- subst: a = TWO -->\n\n{{a}}\n" in
      contains (txt r) "ONE"
      && (not (contains (txt r) "TWO"))
      && List.length (conflicts r) = 1
      && contains (List.hd (conflicts r)) "REPORTED not resolved"
      && Wiki_address.definitions "<!-- subst: a = ONE -->\n<!-- subst: a = TWO -->\n"
         = [ ("a", "ONE") ]);
  check "A12 a MALFORMED substitution marker is preserved VERBATIM and named" (fun () ->
      let use = Wiki_address.substitute "a {{ }} b\n" in
      let def = Wiki_address.substitute "<!-- subst: novalue -->\n{{novalue}}\n" in
      contains (txt use) "{{ }}"
      && List.length (anomalies use) = 1
      && missing use = []
      && contains (txt def) "<!-- subst: novalue -->"
      && List.length (anomalies def) = 1
      && missing def <> []);
  check "A13 a MISPLACED line directive is preserved VERBATIM and named, never spliced"
    (fun () ->
      let r =
        Wiki_address.splice
          ~read:(fun _ -> Some "SPLICED")
          ~self:"h.md" "prose <!-- include: a.md --> more prose\n"
      in
      txt r = "prose <!-- include: a.md --> more prose\n"
      && List.length (anomalies r) = 1
      && used r = []);
  check "A14 an UNTERMINATED marker is ordinary prose: untouched, unnamed, never raised"
    (fun () ->
      let r = Wiki_address.substitute "<!-- subst: a = X -->\nbraces {{a and <!-- a comment\n" in
      contains (txt r) "{{a and" && quiet r && used r = []);
  check "A15 another directive of the family is NOT ours — `<!-- index: t -->` is untouched"
    (fun () ->
      let s = Wiki_address.substitute "<!-- index: parity -->\ntext\n" in
      let i = Wiki_address.splice ~read:(fun _ -> Some "X") ~self:"h" "<!-- index: parity -->\n" in
      txt s = "<!-- index: parity -->\ntext\n" && quiet s
      && txt i = "<!-- index: parity -->\n" && quiet i);
  check "A16 TOTAL over pathological input — nothing raises, nothing is lost" (fun () ->
      let junk =
        [ ""; "{"; "{{"; "{{}}"; "{{ }}"; "}}"; "#"; "# "; "#####"; "## {#"; "## {#}";
          "<!--"; "-->"; "<!-- subst: -->"; "<!-- include: -->"; "`"; "```"; String.make 2000 '{';
          String.make 2000 '#' ]
      in
      List.for_all
        (fun s ->
          let _ = Wiki_address.substitute s in
          let _ = Wiki_address.splice ~read:(fun _ -> None) ~self:"h" s in
          let _ = Wiki_address.headings_of s in
          let _ = Wiki_address.id_collisions s in
          let _ = Wiki_address.id_anomalies s in
          let _ = Wiki_address.resolve inventory (Wiki_address.parse s) in
          let _ = Wiki_address.to_wiki (Wiki_address.parse s) in
          true)
        junk);
  check "A17 ANCHOR LOCALITY: a page's anchors are a function of that page ALONE" (fun () ->
      (* mirrors the HW.3.2.2 probe: the same body, alone and among
         pages carrying the very same headings and ids *)
      let body = "# P\n\n## Setup {#gate}\n\n## Setup\n" in
      let alone = Hermes_wiki.build [ ("docs/hermes/zk/p.md", body) ] in
      let among =
        Hermes_wiki.build
          [ ("docs/hermes/zk/before.md", body); ("docs/hermes/zk/p.md", body);
            ("docs/hermes/zk/after.md", body) ]
      in
      Wiki_address.anchors_of body = [ "p"; "gate"; "setup" ]
      && Hermes_wiki.anchors alone "p" = Hermes_wiki.anchors among "p"
      && List.for_all
           (fun m ->
             match Hermes_wiki.page m "p" with
             | Some p -> Wiki_address.anchors_of p.Hermes_wiki.raw = Wiki_address.anchors_of body
             | None -> false)
           [ alone; among ])

(* ------------------------------------------------------------------ end *)

let () =
  Printf.printf "wiki_address: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_address" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_address ]);
  exit (Wiki_suite_telemetry.exit_code self)
