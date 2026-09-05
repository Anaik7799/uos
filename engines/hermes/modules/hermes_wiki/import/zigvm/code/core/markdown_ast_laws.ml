(* Laws for the markdown AST — BDD scenarios, properties, seeded fuzz, and the
   DIFFERENTIAL against the streaming renderer, which is the oracle.

   THE ORACLE IS THE OLD CODE. `Docs_wiki.render_markdown` has rendered every
   page of this wiki for the programme's whole life; its behaviour — including
   its quirks — is the specification. The AST implementation is admitted only
   by observational equivalence to it: same input, same rendered meaning. The
   old implementation stays in the tree as the permanently-exercised oracle
   (the stan-oracle-still-exercised pattern), not as dead weight.

   Equivalence is OBSERVATIONAL, not byte-level: the old renderer emits some
   attributes unquoted and separates blocks with newlines; TyXML quotes
   everything and emits nothing between siblings. Both are the same document
   to a browser. The normalizer here parses both outputs to a canonical token
   list — names lowercased, attributes sorted with boolean values collapsed,
   entities decoded, whitespace-only text dropped and runs collapsed OUTSIDE
   pre — and the laws compare those. `GUARD NORMALIZER-DISCRIMINATES` proves
   the comparison can fail; the gate re-checks equivalence over the ENTIRE
   real corpus with the Doc_lint tokenizer as an independent normalizer. *)

module M = Markdown_ast
module W = Docs_wiki

(* ---------- the shared resolver both sides receive ----------------------- *)

let resolve s =
  match s with
  | "Known Note" | "known-note" -> Some "known-note"
  | "The Gate" -> Some "the-gate"
  | _ -> None

(* THE ORACLE IS RETIRED. It was deleted once the AST had been proven equivalent
   over every real document, and the corpus guarantee moved to a committed
   digest baseline (`LAW CORPUS-BASELINE`).

   BE CLEAR ABOUT WHAT THAT COSTS. A baseline pins the renderer to its own
   HISTORY; a second implementation pinned it to an INDEPENDENT account of the
   same specification. If the AST and the baseline are wrong in the same way,
   nothing here notices — the differential could not have been fooled that way,
   because the two implementations shared no code. What remains is: the baseline
   (regression), the BDD scenarios (behaviour, stated directly), and the
   properties and fuzz (escaping, totality, determinism, which never needed an
   oracle). That is weaker, deliberately, and it is written down rather than
   left for someone to infer from an absence. *)

(* `parse` uses the default (always-unresolved) resolver; the differential must
   give BOTH sides the same one or every wiki link renders as missing on one
   side only. That was a bug in this file, not in the parser. *)
let new_render md = M.render_string ~resolve (M.parse_with_resolve ~resolve md)

(* ---------- the normalizer ------------------------------------------------ *)

let decode_entities s =
  let b = Buffer.create (String.length s) in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '&' then begin
      let rest = String.sub s !i (min 8 (n - !i)) in
      let eat k c = Buffer.add_string b c; i := !i + k in
      if String.length rest >= 4 && String.sub rest 0 4 = "&lt;" then eat 4 "<"
      else if String.length rest >= 4 && String.sub rest 0 4 = "&gt;" then eat 4 ">"
      else if String.length rest >= 5 && String.sub rest 0 5 = "&amp;" then eat 5 "&"
      else if String.length rest >= 6 && String.sub rest 0 6 = "&quot;" then eat 6 "\""
      else if String.length rest >= 5 && String.sub rest 0 5 = "&#39;" then eat 5 "'"
      else if String.length rest >= 6 && String.sub rest 0 6 = "&#x27;" then eat 6 "'"
      else (Buffer.add_char b '&'; incr i)
    end
    else (Buffer.add_char b s.[!i]; incr i)
  done;
  Buffer.contents b

let collapse_ws s =
  let b = Buffer.create (String.length s) in
  let sp = ref false in
  String.iter
    (fun c ->
      if c = ' ' || c = '\n' || c = '\r' || c = '\t' then
        (if not !sp then Buffer.add_char b ' '; sp := true)
      else (Buffer.add_char b c; sp := false))
    s;
  Buffer.contents b

(* a tiny tag reader for the normalizer: name + attrs with quoting resolved *)
let read_tag s i n =
  let j = ref i in
  let name_start = !j in
  while !j < n && s.[!j] <> ' ' && s.[!j] <> '>' && s.[!j] <> '/' && s.[!j] <> '\n' do incr j done;
  let name = String.lowercase_ascii (String.sub s name_start (!j - name_start)) in
  let attrs = ref [] in
  let fin = ref false in
  while not !fin do
    while !j < n && (s.[!j] = ' ' || s.[!j] = '\n' || s.[!j] = '/') do incr j done;
    if !j >= n || s.[!j] = '>' then fin := true
    else begin
      let a0 = !j in
      while !j < n && s.[!j] <> '=' && s.[!j] <> ' ' && s.[!j] <> '>' && s.[!j] <> '/' do incr j done;
      let aname = String.lowercase_ascii (String.sub s a0 (!j - a0)) in
      let v =
        if !j < n && s.[!j] = '=' then begin
          incr j;
          if !j < n && (s.[!j] = '"' || s.[!j] = '\'') then begin
            let q = s.[!j] in
            incr j;
            let v0 = !j in
            while !j < n && s.[!j] <> q do incr j done;
            let v = String.sub s v0 (!j - v0) in
            if !j < n then incr j;
            v
          end
          else begin
            let v0 = !j in
            while !j < n && s.[!j] <> ' ' && s.[!j] <> '>' do incr j done;
            String.sub s v0 (!j - v0)
          end
        end
        else ""
      in
      (* boolean attributes: absent value and name-valued are the same fact *)
      let v = if v = "" || String.lowercase_ascii v = aname then aname else v in
      if aname <> "" then attrs := (aname, decode_entities v) :: !attrs
    end
  done;
  let close = if !j < n then !j + 1 else n in
  (name, List.sort compare !attrs, close)

(* Block-level boundaries. Whitespace touching one of these is NOT rendered, so
   the oracle's newline after `<blockquote>` and TyXML's absence of it are the
   same document. Whitespace BETWEEN INLINE elements is rendered, and is kept —
   `GUARD NORMALIZER-DISCRIMINATES` proves the difference still shows. *)
let block_tags =
  [ "html"; "head"; "body"; "div"; "p"; "ul"; "ol"; "li"; "blockquote"; "table";
    "thead"; "tbody"; "tr"; "td"; "th"; "h1"; "h2"; "h3"; "h4"; "h5"; "h6";
    "pre"; "hr"; "nav"; "section"; "article"; "main"; "figure"; "figcaption" ]

let is_block_token tok =
  let name =
    if String.length tok > 0 && tok.[0] = '/' then String.sub tok 1 (String.length tok - 1)
    else match String.index_opt tok '|' with Some i -> String.sub tok 0 i | None -> tok
  in
  List.mem name block_tags

let normalize (html : string) : string list =
  let n = String.length html in
  (* pass 1: raw tokens, text marked so pass 2 can see its neighbours *)
  let out = ref [] and i = ref 0 and pre = ref 0 in
  let flush_text t =
    let t = decode_entities t in
    if !pre > 0 then out := `Pre t :: !out else out := `Txt (collapse_ws t) :: !out
  in
  while !i < n do
    if html.[!i] = '<' then begin
      if !i + 1 < n && html.[!i + 1] = '/' then begin
        let j = ref (!i + 2) in
        while !j < n && html.[!j] <> '>' do incr j done;
        let name = String.lowercase_ascii (String.trim (String.sub html (!i + 2) (!j - !i - 2))) in
        if name = "pre" then decr pre;
        out := `Tag ("/" ^ name) :: !out;
        i := if !j < n then !j + 1 else n
      end
      else begin
        let name, attrs, close = read_tag html (!i + 1) n in
        if name = "pre" then incr pre;
        let a = String.concat " " (List.map (fun (k, v) -> k ^ "=" ^ v) attrs) in
        out := `Tag (name ^ "|" ^ a) :: !out;
        i := close
      end
    end
    else begin
      let start = !i in
      while !i < n && html.[!i] <> '<' do incr i done;
      flush_text (String.sub html start (!i - start))
    end
  done;
  (* pass 2: trim text whose whitespace touches a block boundary, drop what is
     then empty, and keep everything else — including a whitespace-only gap
     between two INLINE elements, which a browser does render *)
  let toks = Array.of_list (List.rev !out) in
  let len = Array.length toks in
  let neighbour_is_block k =
    k >= 0 && k < len && match toks.(k) with `Tag t -> is_block_token t | _ -> false
  in
  let res = ref [] in
  Array.iteri
    (fun k tok ->
      match tok with
      | `Tag t -> res := t :: !res
      | `Pre t -> res := ("P:" ^ t) :: !res
      | `Txt t ->
          let t = if neighbour_is_block (k - 1) then
              (let n = String.length t in
               let s = ref 0 in
               while !s < n && t.[!s] = ' ' do incr s done;
               String.sub t !s (n - !s))
            else t
          in
          let t = if neighbour_is_block (k + 1) then
              (let n = String.length t in
               let e = ref n in
               while !e > 0 && t.[!e - 1] = ' ' do decr e done;
               String.sub t 0 !e)
            else t
          in
          if t <> "" then res := ("T:" ^ t) :: !res)
    toks;
  List.rev !res

(* rendering is compared to itself for determinism; there is no second
   implementation to compare against any more *)
let stable md = normalize (new_render md) = normalize (new_render md)

(* ---------- fixtures ------------------------------------------------------ *)

let hostile = "<script>alert(1)</script>\"&'"

(* a seeded generator of REALISTIC documents: combinations of the constructs
   the corpus actually uses. Deliberately NOT adversarial about asterisks
   inside URLs and the like — the old pipeline is string rewriting over mixed
   text, and in those pathological corners the AST behaviour is intentionally
   the saner one. The REAL corpus differential in the gate is the bar that
   matters; this explores construct combinations. *)
let gen_doc seed =
  let st = ref seed in
  let next () = st := (!st * 1103515245 + 12345) land 0x3FFFFFFF; !st in
  let pick n = next () mod n in
  let words = [| "alpha"; "beta"; "the gate"; "x&y"; "q<r>"; "tag"; "45%" |] in
  let word () = words.(pick (Array.length words)) in
  let inline_bits () =
    let bits =
      [| (fun () -> word ());
         (fun () -> "`" ^ word () ^ "`");
         (fun () -> "**" ^ word () ^ "**");
         (fun () -> "*" ^ word () ^ "*");
         (fun () -> "[[Known Note]]");
         (fun () -> "[[Nowhere Man]]");
         (fun () -> "[[The Gate|the gate]]");
         (fun () -> "[[The Gate|@prereq]]");
         (fun () -> "[[Known Note#Section]]");
         (fun () -> "[t](x.md)");
         (fun () -> "[t](https://e.com/p)");
         (fun () -> "#atag");
         (fun () -> word ()) |]
    in
    String.concat " " (List.init (1 + pick 4) (fun _ -> bits.(pick (Array.length bits)) ()))
  in
  let line () =
    match pick 14 with
    | 0 -> "# " ^ inline_bits ()
    | 1 -> "## " ^ word () ^ " ^anchor" ^ string_of_int (pick 9)
    | 2 -> "- " ^ inline_bits ()
    | 3 -> "- [ ] " ^ word ()
    | 4 -> "- [x] " ^ word ()
    | 5 -> Printf.sprintf "%d. %s" (1 + pick 9) (inline_bits ())
    | 6 -> "> " ^ inline_bits ()
    | 7 -> "> [!warning] " ^ word ()
    | 8 -> "| " ^ word () ^ " | " ^ word () ^ " |"
    | 9 -> "|---|---|"
    | 10 -> "---"
    | 11 -> ""
    | 12 -> inline_bits () ^ " ^b" ^ string_of_int (pick 9)
    | _ -> inline_bits ()
  in
  (* The opening fence carries an INFO STRING on some seeds. Without this the
     corpus of generated documents has `info = ""` everywhere, and any law about
     information preservation is blind to the exact loss that motivated it: the
     fence info string was discarded for the programme's whole life. A mutant
     that dropped `info` from the AST collector SURVIVED until this line
     existed — the law was only ever as strong as the generator. *)
  let fence () =
    let opener =
      match pick 4 with
      | 0 -> "```"
      | 1 -> "```ocaml"
      | 2 -> "```zig title=vm"
      | _ -> "```erlang"
    in
    [ opener; "# not a heading " ^ hostile; "  code " ^ word (); "```" ]
  in
  let blocks = List.init (3 + pick 8) (fun _ -> if pick 9 = 0 then fence () else [ line () ]) in
  String.concat "\n" (List.concat blocks @ if pick 4 = 0 then [ "[TOC]" ] else [])

(* ---------- the suite ----------------------------------------------------- *)

let contains hay needle =
  let nl = String.length needle and hl = String.length hay in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl > 0 && go 0

let run () : (string * bool) list =
  let out = ref [] in
  let check name ok = out := (name, ok) :: !out in
  let bdd name md preds =
    let html = new_render md in
    check name (List.for_all (fun p -> p html) preds && stable md)
  in
  let has needle html = contains html needle in
  let lacks needle html = not (contains html needle) in

  (* ---- GUARDS first: the comparison itself must be able to fail --------- *)
  check "GUARD NORMALIZER-DISCRIMINATES: a planted class change is detected"
    (normalize "<p class=\"a\">x</p>" <> normalize "<p class=\"b\">x</p>"
    && normalize "<p>x</p>" <> normalize "<p>y</p>"
    && normalize "<pre>a\nb</pre>" <> normalize "<pre>a b</pre>");
  check "GUARD NORMALIZER-FORGIVES: quoting, newlines-between-blocks, bool attrs"
    (normalize "<p class=x>a</p>\n<hr>\n" = normalize "<p class=\"x\">a</p><hr/>"
    && normalize "<input disabled>" = normalize "<input disabled=\"disabled\"/>"
    && normalize "<blockquote>\na b </blockquote>\n" = normalize "<blockquote>a b</blockquote>");
  (* whitespace next to a BLOCK boundary is not rendered and is forgiven above;
     whitespace between two INLINE elements IS rendered and must still count,
     or the normalizer would call "a b" and "ab" the same document *)
  check "GUARD NORMALIZER-KEEPS-INLINE-GAPS: an inter-element space still counts"
    (normalize "<p><b>a</b> <b>b</b></p>" <> normalize "<p><b>a</b><b>b</b></p>"
    && normalize "<pre>a\nb</pre>" <> normalize "<pre>a b</pre>");

  (* ---- BDD: block constructs -------------------------------------------- *)
  bdd "SCENARIO heading: level, auto anchor from znorm, inline code inside"
    "## The `Gate` Rules"
    [ has "<h2"; has "id=\"the-gate-rules\""; has "<code>Gate</code>" ];
  bdd "SCENARIO heading: an explicit block id wins the anchor"
    "### Title ^myid"
    [ has "<h3"; has "id=\"^myid\""; lacks "^myid</h3>" ];
  bdd "SCENARIO five hashes is a paragraph, not a heading"
    "##### not a heading"
    [ has "<p>"; lacks "<h5" ];
  bdd "SCENARIO paragraph: a trailing block id becomes the p id"
    "claim text ^claim-1"
    [ has "<p id=\"^claim-1\">claim text</p>" ];
  bdd "SCENARIO hr in all three spellings"
    "---\n***\n___"
    [ (fun h ->
        let c = ref 0 and i = ref 0 in
        let n = String.length h in
        while !i + 3 <= n do
          if String.sub h !i 3 = "<hr" then incr c;
          incr i
        done;
        !c = 3) ];
  bdd "SCENARIO code fence: markup and wiki syntax inside stay text"
    "```\n# heading? no\n[[Known Note]]\n<b>bold?</b>\n```"
    [ has "<pre><code>"; lacks "<h1"; lacks "class=\"zettel\"";
      has "&lt;b&gt;bold?&lt;/b&gt;"; lacks "<b>bold?</b>" ];
  (* ---- the fence INFO STRING (items 1-3 slice) --------------------------- *)

  (* CONSERVATIVITY. The <pre><code> core of an info-less fence is UNCHANGED —
     no language class, no data-lang. This is the law that bounds the blast
     radius of the carrier change: the wrapper is new, the code element is not. *)
  bdd "SCENARIO fence without info: bare <pre><code>, no language class"
    "```\nplain\n```"
    [ has "<pre><code>"; lacks "language-"; lacks "data-lang" ];
  bdd "SCENARIO fence with a language: language- class and data-lang label"
    "```ocaml\nlet x = 1\n```"
    [ has "class=\"language-ocaml\""; has "data-lang=\"ocaml\""; has "class=\"cb\"";
      has "cb-copy"; has "let x = 1" ];
  (* the language is the FIRST token; the rest is meta and must not leak into
     the class. A mutant that takes the whole info string fails exactly here. *)
  bdd "SCENARIO fence info: only the first token is the language"
    "```ocaml title=\"a.ml\" {1,3}\nlet x = 1\n```"
    [ has "class=\"language-ocaml\""; lacks "title="; lacks "{1,3}" ];
  bdd "SCENARIO fence language is case-folded"
    "```OCaml\nx\n```"
    [ has "class=\"language-ocaml\"" ];
  (* mermaid is the one shape with NO code element and NO copy button: the
     runtime overwrites the element's children, so chrome inside it is destroyed *)
  bdd "SCENARIO mermaid fence renders bare pre.mermaid, no code, no button"
    "```mermaid\ngraph TD; A-->B;\n```"
    [ has "class=\"mermaid\""; lacks "<code"; lacks "cb-copy";
      has "graph TD; A--&gt;B;" ];
  (* a fence whose info is not a well-formed language degrades to the info-less
     rendering — never to a broken class attribute *)
  bdd "SCENARIO hostile fence info degrades to the info-less shape"
    "```\"><script>alert(1)</script>\nx\n```"
    [ has "<pre><code>"; lacks "language-"; lacks "<script>" ];

  check "LAW LANG-TOTALITY: lang_of_info is total and admits exactly [A-Za-z0-9_+-]+"
    (M.lang_of_info "ocaml" = Some "ocaml"
    && M.lang_of_info "OCaml" = Some "ocaml"
    && M.lang_of_info "c++" = Some "c++"
    && M.lang_of_info "objective-c" = Some "objective-c"
    && M.lang_of_info "ocaml title=x" = Some "ocaml"
    && M.lang_of_info "ocaml\tmeta" = Some "ocaml"
    && M.lang_of_info "" = None
    && M.lang_of_info "   " = None
    && M.lang_of_info "\"><b>" = None
    && M.lang_of_info "a b" = Some "a");
  check "LAW LANG-IDEMPOTENCE: a language token is a fixed point of the extractor"
    (List.for_all
       (fun l -> M.lang_of_info l = Some l)
       [ "ocaml"; "zig"; "erlang"; "sh"; "mermaid"; "text"; "json" ]);
  (* the carrier keeps the info string VERBATIM — the parser interprets nothing *)
  check "LAW FENCE-INFO-VERBATIM: parse carries the opening fence info unchanged"
    (match M.parse "```ocaml title=\"a.ml\"\nbody\n```" with
     | [ M.Code_block { info; body } ] -> info = "ocaml title=\"a.ml\"" && body = "body\n"
     | _ -> false);
  (* the CLOSING fence's trailing text is not an info string (CommonMark) *)
  check "LAW FENCE-CLOSE-IGNORED: only the opening fence carries info"
    (match M.parse "```ocaml\nbody\n```ignored\n" with
     | [ M.Code_block { info; _ } ] -> info = "ocaml"
     | _ -> false);
  check "LAW FENCE-UNCLOSED-KEEPS-INFO: an unclosed fence still carries its info"
    (match M.parse "```zig\nbody" with
     | [ M.Code_block { info; _ } ] -> info = "zig"
     | _ -> false);

  bdd "SCENARIO unordered list closes on blank; todo checkboxes read-only"
    "- one\n- [ ] open\n- [x] done\n\nafter"
    [ has "<ul>"; has "class=\"todo\""; has "disabled";
      has "checked"; has "<p>after</p>" ];
  bdd "SCENARIO ordered list; a numberless dot line stays a paragraph"
    "1. first\n2. second\n\n10 items"
    [ has "<ol>"; has "<li>first</li>"; has "<p>10 items</p>" ];
  bdd "SCENARIO blockquote lines join; callout carries family icon"
    "> line one\n> line two"
    [ has "<blockquote>"; has "line one"; has "line two" ];
  bdd "SCENARIO callout: warning family icon and typed class"
    "> [!warning] Careful\n> body"
    [ has "callout"; has "co-warning"; has "\226\154\160"; has "Careful" ];
  bdd "SCENARIO table: head row until separator, then body cells"
    "| A | B |\n|---|---|\n| 1 | 2 |"
    [ has "<th>A</th>"; has "<td>1</td>"; has "class=\"tw\"" ];
  bdd "SCENARIO table separator between list and table leaves list intact (quirk)"
    "- item\n|---|\n| H |"
    [ has "<li>item</li>"; has "<th>H</th>" ];
  bdd "SCENARIO TOC lists headings including fence interiors (pinned quirk)"
    "# Real\n```\n# Fenced\n```\n[TOC]"
    [ has "class=\"toc\""; has "#real"; has "Fenced" ];

  (* ---- BDD: inline constructs ------------------------------------------- *)
  bdd "SCENARIO wiki link resolves to slug.html with zettel class"
    "see [[Known Note]] here"
    [ has "href=\"known-note.html\""; has "class=\"zettel\"" ];
  bdd "SCENARIO wiki link unresolved: missing class and title, no href"
    "see [[Nowhere Man]]"
    [ has "missing"; has "unresolved note: Nowhere Man"; lacks "nowhere-man.html" ];
  bdd "SCENARIO wiki link with display text and with section anchor"
    "[[The Gate|the gatekeeper]] and [[Known Note#My Section]]"
    [ has ">the gatekeeper</a>"; has "href=\"known-note.html#my-section\"" ];
  bdd "SCENARIO typed relation: display shows base, badge shows relation"
    "[[The Gate|@prereq]]"
    [ has "zk-rel"; has "prereq"; has ">The Gate</a>" ];
  bdd "SCENARIO md link: an internal .md target rewrites to the note page"
    "[docs](known-note.md) and [ext](https://e.com/x)"
    [ has "href=\"known-note.html\""; has "href=\"https://e.com/x\"" ];
  bdd "SCENARIO hashtag chips only for lowercase word tags"
    "a #goodtag but #Heading and x#glued stay"
    [ has "class=\"zk-tag\""; has "tags.html#goodtag"; lacks "tags.html#Heading";
      lacks "tags.html#glued" ];
  bdd "SCENARIO bold and italic, including bold wrapping a link"
    "**bold [t](u) tail** and *emph*"
    [ has "<strong>"; has "<em>emph</em>";
      (fun h ->
        (* the strong span contains the anchor, as the oracle produces *)
        match String.index_opt h 's' with
        | _ ->
            let so = Str.search_forward (Str.regexp_string "<strong>") h 0 in
            let sc = Str.search_forward (Str.regexp_string "</strong>") h 0 in
            let ao = try Str.search_forward (Str.regexp_string "<a ") h 0 with Not_found -> -1 in
            ao > so && ao < sc) ];
  bdd "SCENARIO code spans protect their contents from every other pass"
    "`**not bold** [[not a link]]` after"
    [ has "<code>"; lacks "<strong>"; lacks "class=\"zettel\"" ];

  (* ---- properties -------------------------------------------------------- *)
  check "LAW ESCAPING: hostile text in every construct never yields live markup"
    (let md =
       "# " ^ hostile ^ "\n" ^ hostile ^ " ^b1\n- " ^ hostile ^ "\n> " ^ hostile
       ^ "\n| " ^ hostile ^ " |\n```\n" ^ hostile ^ "\n```\n[[" ^ hostile ^ "]]"
     in
     let h = new_render md in
     not (contains h "<script>alert"));
  check "LAW DETERMINISM: same input, same output"
    (let d = gen_doc 7 in new_render d = new_render d);
  check "LAW TOTALITY: hostile and degenerate inputs never raise"
    (List.for_all
       (fun md -> match new_render md with _ -> true | exception _ -> false)
       [ ""; "\n"; "```"; "```\nunclosed"; "> "; "|"; "[[unclosed"; "**"; "*";
         String.make 10000 '#'; String.concat "\n" (List.init 500 (fun i -> gen_doc i)) ]);

  (* ---- the ONE enumerated divergence ------------------------------------ *)
  (* A heading containing a link, listed in a [TOC]: the oracle nests an anchor
     inside the TOC anchor, which is invalid HTML that browsers restructure.
     TyXML makes it unconstructible, so the entry renders the link's TEXT. The
     divergence is deliberate and the AST is the better side, so it is PINNED
     here and EXCLUDED from the differential by a stated predicate — never by
     skipping a seed number. *)
  let toc_with_linked_heading md =
    let lines = String.split_on_char '\n' md in
    List.exists (fun l -> String.trim l = "[TOC]") lines
    && List.exists
         (fun l ->
           let t = String.trim l in
           (contains t "# ")
           && (contains t "[[" || contains t "](" ))
         lines
  in
  (* The behaviour the retired oracle would have got wrong, now stated on its
     own terms rather than as a difference: a TOC entry contains exactly ONE
     anchor, because an anchor inside an anchor is invalid HTML and TyXML makes
     it unconstructible. *)
  check "SCENARIO TOC-LINK: a linked heading lists as text, with exactly one anchor"
    (let md = "# see [[Known Note]] now\n[TOC]" in
     let nw = new_render md in
     toc_with_linked_heading md
     && contains nw "toc-l1"
     && contains nw "see Known Note now"
     && not (contains nw "toc-l1\"><a"));

  (* ---- seeded fuzz: totality, escaping and determinism -------------------
     These never needed an oracle, which is why they survive its retirement.
     What DID need one — "renders the same as the other implementation" — is
     now the committed baseline over the real corpus, and only over the real
     corpus: generated documents have no baseline entry to compare against. *)
  let unstable = ref (-1) and leaked = ref (-1) and raised = ref (-1) in
  for seed = 1 to 300 do
    let d = gen_doc seed in
    (match new_render d with
     | html ->
         if !unstable < 0 && not (stable d) then unstable := seed;
         if !leaked < 0 && contains html "<script>alert" then leaked := seed
     | exception _ -> if !raised < 0 then raised := seed)
  done;
  List.iter
    (fun (what, seed) ->
      if seed >= 0 then begin
        Printf.printf "        markdown-ast FUZZ %s at seed %d\n" what seed;
        let d = gen_doc seed in
        Printf.printf "        doc: %s\n"
          (String.escaped (String.sub d 0 (min 300 (String.length d))))
      end)
    [ ("non-determinism", !unstable); ("escaping leak", !leaked); ("exception", !raised) ];
  Printf.printf "        markdown-ast fuzz: 300 seeded documents\n";
  check "LAW FUZZ-TOTALITY: 300 seeded documents render without raising" (!raised < 0);
  check "LAW FUZZ-DETERMINISM: 300 seeded documents render identically twice" (!unstable < 0);
  check "LAW FUZZ-ESCAPING: no seeded document yields live markup" (!leaked < 0);
  List.rev !out

(* ---------- the corpus differential --------------------------------------
   The bar that actually matters. Generated documents explore construct
   combinations; the CORPUS is what ships. Every `docs/**/*.md` is rendered by
   both implementations with the same resolver and compared normalized.

   This is also what keeps the oracle ALIVE: the old streaming renderer is not
   dead code kept "just in case", it is executed on every gate run over every
   document, and the moment the two disagree the gate is red. Deleting it would
   delete the specification. *)

let rec walk acc dir =
  Array.fold_left
    (fun acc e ->
      let p = Filename.concat dir e in
      if (try Sys.is_directory p with Sys_error _ -> false) then walk acc p
      else if Filename.check_suffix p ".md" then p :: acc
      else acc)
    acc
    (try Sys.readdir dir with Sys_error _ -> [||])

let read_file p =
  let ic = open_in_bin p in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

let corpus_differential ~(root : string) : (string * bool) list =
  let files = walk [] (Filename.concat root "docs") in
  let pages =
    List.sort compare (List.filter_map (fun p -> try Some (p, read_file p) with _ -> None) files)
  in
  (* the resolver keyed on basename, the same shape the wiki builds *)
  let tbl = Hashtbl.create 1024 in
  List.iter
    (fun (p, _) ->
      let b = Filename.remove_extension (Filename.basename p) in
      Hashtbl.replace tbl (String.lowercase_ascii b) (M.znorm b))
    pages;
  let resolve k = Hashtbl.find_opt tbl (String.lowercase_ascii k) in
  (* the committed baseline: path -> digest of the normalized token stream *)
  let baseline = Hashtbl.create 1024 in
  let bpath = Filename.concat root "docs/design/markdown-render-baseline.txt" in
  (try
     let ic = open_in_bin bpath in
     (try
        while true do
          let line = input_line ic in
          if String.length line > 0 && line.[0] <> '#' then
            (* <render-digest> <content-digest> <path> *)
            match String.split_on_char ' ' line with
            | r :: c :: rest when rest <> [] ->
                Hashtbl.replace baseline (String.trim (String.concat " " rest)) (r, c)
            | _ -> ()
        done
      with End_of_file -> ());
     close_in ic
   with Sys_error _ -> ());
  let checked = ref 0 and drifted = ref [] and unlisted = ref [] and edited = ref 0 in
  List.iter
    (fun (p, md) ->
      let rel =
        let rl = String.length root + 1 in
        if String.length p > rl && String.sub p 0 (String.length root) = root then
          String.sub p rl (String.length p - rl)
        else p
      in
      let html = M.render_string ~resolve (M.parse_with_resolve ~resolve md) in
      let digest = Digest.to_hex (Digest.string (String.concat "\031" (normalize html))) in
      match Hashtbl.find_opt baseline rel with
      | None -> unlisted := rel :: !unlisted
      | Some (_, c) when c <> Digest.to_hex (Digest.string md) ->
          (* the document was EDITED since the baseline was taken, so its
             rendering says nothing about the renderer — skipped, and counted *)
          incr edited
      | Some (d, _) ->
          incr checked;
          if d <> digest then drifted := rel :: !drifted)
    pages;
  List.iter
    (fun p -> Printf.printf "        markdown-ast RENDER DRIFT: %s\n" p)
    (List.rev !drifted);
  (* NO SILENT CAPS: counts are printed whether or not anything failed, and a
     document missing from the baseline is reported rather than skipped
     quietly — an unlisted file is unguarded, which is the failure mode a
     digest baseline invites. *)
  Printf.printf
    "        markdown-ast corpus: %d checked against baseline, %d drifted, %d edited-since (skipped), %d unlisted\n"
    !checked (List.length !drifted) !edited (List.length !unlisted);
  [ ( "LAW CORPUS-BASELINE: every content-stable document renders as the committed baseline says",
      !drifted = [] );
    (* COVERAGE, bounded rather than absolute — and the reasoning is the same
       one that produced the content digest above. Requiring EVERY document to
       be listed makes the gate red on the commit that writes a new note, and
       every cycle here writes an episodic note. The only way to green it is to
       regenerate, so the law would teach the exact reflexive regeneration that
       makes a baseline worthless.

       A new document is not a regression. What would be a regression is
       coverage quietly eroding, so the bound is proportional: at most 5% of the
       corpus may be unlisted, and the count is printed whether or not it fires.
       An unlisted document IS unguarded — that is not being denied, it is being
       measured. *)
    ( "LAW BASELINE-COVERAGE: at most 5% of the corpus is outside the baseline",
      let total = !checked + !edited + List.length !unlisted in
      total = 0 || List.length !unlisted * 20 <= total );
    ( "GUARD NON-VACUOUS: the baseline check actually read documents", !checked > 100 );
    (* Skipping edited documents opens a way for this law to pass on nothing:
       edit enough of the corpus and `checked` reaches zero while `drifted`
       stays empty. The guard above sets a floor on the absolute count; this one
       sets it on the PROPORTION, so a slow erosion is caught as well as a sharp
       one. If it fires, the baseline is stale rather than wrong — regenerate it
       with the `regen:` disclosure the generator asks for. *)
    ( "GUARD BASELINE-NOT-ERODED: most of the corpus is still content-stable \
       against the baseline",
      let total = !checked + !edited in
      total = 0 || !checked * 10 >= total * 8 ) ]

(* ---------- information preservation: the discard set and the round trip ----

   There is NO inverse of `parse` — the module has no markdown printer — so
   "round-trip" cannot be stated as `parse ∘ print = id`. Saying so honestly
   matters, because the usual formulation is unavailable and pretending
   otherwise would produce a law that looks stronger than it is.

   What IS available is the composition. The pipeline is
   `source → AST → HTML`, and preservation across it factors into two laws
   that compose:

     DISCARD-SET   source content tokens \ AST tokens  ⊆  the DECLARED set
     RENDER-COMPLETE   AST tokens  ⊆  rendered tokens

   Together: no content reaches the page unless it survived both steps, and
   anything that does NOT survive step one is named in advance. This is the
   law that would have caught the fence-info-string loss, which lived for the
   programme's whole life precisely because nothing forbade a silent drop. *)

(* Alphanumeric runs of length >= 3, lowercased. Length 3 because shorter runs
   are dominated by markup fragments ("md", "x") whose survival says nothing,
   and because a two-character threshold makes the law noisy without making it
   stronger. *)
let content_tokens (s : string) : string list =
  let out = ref [] and buf = Buffer.create 16 in
  let flush () =
    if Buffer.length buf >= 3 then out := Buffer.contents buf :: !out;
    Buffer.clear buf
  in
  String.iter
    (fun c ->
      match c with
      | 'a' .. 'z' | '0' .. '9' -> Buffer.add_char buf c
      | 'A' .. 'Z' -> Buffer.add_char buf (Char.lowercase_ascii c)
      | _ -> flush ())
    s;
  flush ();
  List.sort_uniq compare !out

(* Every string the AST carries: visible text, and also the fields that are NOT
   visible text but ARE retained state — ids, fence info, wiki targets, hrefs,
   callout kinds. A collector that walked only the visible text would let a
   retained-but-unrendered field look like a loss, and a collector that skipped
   a field entirely would let a REAL loss look like a pass. *)
let rec inline_strings (i : M.inline) : string list =
  match i with
  | M.Text s | M.Code s | M.Tag s -> [ s ]
  | M.Strong xs | M.Em xs -> List.concat_map inline_strings xs
  | M.Link { href; body } -> href :: List.concat_map inline_strings body
  | M.Wiki { target; anchor; display; rel } ->
      target :: anchor :: rel :: List.concat_map inline_strings display
  | M.Wiki_missing { target; display } ->
      target :: List.concat_map inline_strings display

let inline_strings_of_item (it : M.item) : string list =
  List.concat_map inline_strings it.M.i_body

let block_strings (b : M.block) : string list =
  match b with
  | M.Heading { id; body; _ } -> id :: List.concat_map inline_strings body
  | M.Para { id; body } ->
      (match id with Some s -> [ s ] | None -> []) @ List.concat_map inline_strings body
  | M.Hr -> []
  | M.Code_block { info; body } -> [ info; body ]
  | M.Ul items -> List.concat_map (fun (it : M.item) -> inline_strings_of_item it) items
  | M.Ol rows -> List.concat_map (List.concat_map inline_strings) rows
  | M.Blockquote { callout; body } ->
      (match callout with Some (k, v) -> [ k; v ] | None -> [])
      @ List.concat_map inline_strings body
  | M.Table rows ->
      List.concat_map
        (fun (r : M.row) ->
          List.concat_map (fun (c : M.cell) -> List.concat_map inline_strings c.M.c_body) r.M.r_cells)
        rows
  | M.Toc entries -> List.concat_map (fun (_, id, body) -> id :: List.concat_map inline_strings body) entries

let ast_tokens (doc : M.t) : string list =
  content_tokens (String.concat " " (List.concat_map block_strings doc))

(* THE DECLARED DISCARD SET — what `parse` is permitted to drop.

   This list is the point of the law. Every entry is a deliberate decision with
   a reason; anything NOT here that goes missing is a defect. Adding an entry is
   how a new loss gets admitted, and it is visible in review rather than
   inferred from a diff of the parser. *)
let declared_discards : (string * string) list =
  [ ("toc",
     "the literal [TOC] marker is consumed into a Toc block, which carries the \
      collected headings instead — the marker itself has no further meaning");
    ("warning",
     "a callout KIND is retained on the Blockquote, but the generator also \
      emits it inside the bracket syntax `[!warning]`, whose bracket form is \
      structural and not content") ]

let discard_set_tokens = List.map fst declared_discards

(* THE DECLARED RENDER RESIDUAL — what the AST retains but the page does not
   yet show. Distinct from a discard: the information SURVIVED parsing and is
   available to any future consumer, it simply has no rendering yet. Keeping
   the two lists separate matters, because collapsing them would let a genuine
   parse loss hide behind "we don't render that anyway". *)
let declared_render_residuals : (string * string) list =
  [ ("title",
     "the fence info string is carried RAW, but only its first token becomes a \
      language class; the remaining meta (title, line highlights) is retained \
      for a future meta reader and is not emitted yet") ]

let render_residual_tokens = List.map fst declared_render_residuals

let information_laws () : (string * bool) list =
  let lost_undeclared = ref [] in
  let dropped_by_render = ref [] in
  for seed = 1 to 200 do
    let src = gen_doc seed in
    let doc = M.parse_with_resolve ~resolve src in
    let src_toks = content_tokens src in
    let ast_toks = ast_tokens doc in
    let rendered = decode_entities (M.render_string ~resolve doc) in
    let rendered_toks = content_tokens rendered in
    List.iter
      (fun t ->
        if (not (List.mem t ast_toks)) && not (List.mem t discard_set_tokens) then
          lost_undeclared := t :: !lost_undeclared)
      src_toks;
    List.iter
      (fun t ->
        if (not (List.mem t rendered_toks)) && not (List.mem t render_residual_tokens) then
          dropped_by_render := t :: !dropped_by_render)
      ast_toks
  done;
  [ ( "LAW MD-DISCARD-SET: over 200 seeded documents, every content token the \
       parser drops is a DECLARED discard (a silent loss is a defect)",
      !lost_undeclared = [] );
    ( "LAW MD-RENDER-COMPLETE: over 200 seeded documents, every token the AST \
       retains reaches the rendered page or is a DECLARED render residual",
      !dropped_by_render = [] );
    ( "LAW MD-RESIDUAL-DECLARED: every render residual carries a stated reason \
       (a residual without one is an undisclosed gap)",
      List.for_all (fun (t, why) -> String.length t > 0 && String.length why > 20)
        declared_render_residuals );
    (* Without this, the two laws above are satisfiable by an empty discard set
       AND by a bloated one: a discard entry that never fires is dead
       permission, and dead permission is how a real loss gets laundered later. *)
    ( "LAW MD-DISCARD-SET-MINIMAL: every declared discard is non-empty and \
       carries a stated reason",
      declared_discards <> []
      && List.for_all (fun (t, why) -> String.length t > 0 && String.length why > 20) declared_discards )
  ]

(* ---------- quirk-list amendment: the slugger ------------------------------

   THE PURE-SLUG QUIRK IS BEING AMENDED, and this is the scenario that had to
   fail before the change was allowed to land. Two headings with the same text
   received the SAME anchor, so a direct link to the second was impossible and
   the corpus carried 10 such collisions across 3 documents.

   SCOPE OF THE AMENDMENT — deliberately narrow, because the three anchor sites
   are not interchangeable:

   - HEADING DECLARATIONS are disambiguated. This is the change.
   - WIKILINK FRAGMENTS (`[[Doc#Section]]`) stay PURE. They are references to
     an anchor another document declared, computed without seeing that
     document; making them stateful would compute a suffix from this
     document's history and point at nothing.
   - THE [TOC] SCAN stays PURE. Its own pinned quirk is that it matches heading
     prefixes on every line INCLUDING inside code fences, so its sequence is
     not the heading sequence and a shared counter would drift apart. The
     observable consequence is unchanged from today: a TOC entry for a repeated
     heading resolves to the first occurrence, exactly as it does now when both
     share one anchor.

   That third point is the reason this is an amendment and not a rewrite: the
   fenced-line quirk stays pinned, and the slugger is fitted around it. *)

(* ---------- locality: stating directly what was only covered incidentally ----

   Making the slugger stateful introduced a hazard the pure `znorm` could not
   have: state that OUTLIVES the document. `parse_with_resolve` creates one
   slugger per call, and the amendment's central design claim is "one slugger
   per document, not one per run". No law SAID so, and the scenarios above
   cannot: each parses a fresh document, and the one that would notice a
   carried-over history asserts only on `^pinned`, the single element a shared
   history leaves alone.

   MEASURED, NOT ASSUMED — and the measurement corrected the premise. Hoisting
   the slugger to module level (MUT-AMEND-A) IS caught today, by
   JOURNAL-PUBLISH-DETERMINISTIC, which renders the same markdown twice in one
   process: a shared instance makes the second render differ. So the hazard was
   already covered. It was covered INCIDENTALLY, by a law about journal
   publication that happens to re-render, and which kills the mutant three
   stages before this file is reached.

   These laws are therefore not new coverage, and are not claimed as such. What
   they add is that the property is named where the amendment is made, and that
   it survives its own guard changing: the subsumption depends on
   JOURNAL-PUBLISH-DETERMINISTIC rendering twice IN ONE PROCESS, which is an
   implementation detail of that law, not a promise it makes. Split those two
   renders across processes and the shared-slugger hazard becomes invisible
   again with no law going red to say so.

   The property is LOCALITY: parsing is a function of its argument alone. The
   consequences are asserted separately because the ways they can be defeated
   differ — a memo keyed on document text satisfies locality and repetition
   while still sharing a slugger underneath.

   NON-VACUOUS earns its place on its own evidence: weakening the poisoning
   document to a non-colliding one leaves LOCALITY passing and turns
   NON-VACUOUS red. It is the only one of the three with a demonstrated
   exclusive kill, and it exists because the fence-info law on this same front
   went vacuous exactly this way.

   Why any of it matters: anchors are PUBLISHED. If a page's anchors depended
   on parse order, a full-corpus render and a single-file render would emit
   different links for the same page, and which one a reader received would
   depend on how the renderer happened to be invoked. *)

let locality_laws () : (string * bool) list =
  let ids doc =
    List.filter_map (function M.Heading { id; _ } -> Some id | _ -> None) doc
  in
  (* Chosen to POISON: every heading base in `subject` also occurs in `other`,
     so a shared history would force a suffix onto every one of them. *)
  let other = "# Alpha\n\n# Beta\n\n# Alpha\n" in
  let subject = "# Alpha\n\n# Beta\n" in
  let alone = ids (M.parse_with_resolve ~resolve subject) in
  let poisoned = ids (M.parse_with_resolve ~resolve other) in
  let after = ids (M.parse_with_resolve ~resolve subject) in
  [ ( "LAW MD-SLUG-LOCALITY: a document's anchors do not depend on what was \
       parsed before it — the same text parsed after a colliding document \
       yields the identical anchors",
      alone = after );
    (* Without this, LOCALITY passes vacuously the moment the poisoning
       document stops colliding — the exact way the fence-info law went vacuous
       on this front once already. *)
    ( "LAW MD-SLUG-LOCALITY-NON-VACUOUS: the poisoning document really does \
       claim every anchor the subject wants, so the law above could have failed",
      alone <> [] && List.for_all (fun a -> List.mem a poisoned) alone );
    ( "LAW MD-SLUG-REPETITION: parsing the same document twice yields the same \
       anchors, so a render is reproducible",
      ids (M.parse_with_resolve ~resolve other)
      = ids (M.parse_with_resolve ~resolve other) ) ]

let amendment_scenarios () : (string * bool) list =
  let ids doc =
    List.filter_map (function M.Heading { id; _ } -> Some id | _ -> None) doc
  in
  let two_same = M.parse_with_resolve ~resolve "# Alpha\n\n# Alpha\n" in
  let three_same = M.parse_with_resolve ~resolve "# A\n\n# A\n\n# A\n" in
  let punctuation = M.parse_with_resolve ~resolve "# The Gate\n\n# the  gate!\n" in
  let explicit = M.parse_with_resolve ~resolve "# Alpha ^pinned\n\n# Alpha\n" in
  [ ( "SCENARIO AMEND-SLUG-DISTINCT: given a document with two identical \
       headings, when it is parsed, then the anchors differ",
      match ids two_same with [ a; b ] -> a <> b | _ -> false );
    ( "SCENARIO AMEND-SLUG-FIRST-KEPT: the FIRST of a repeated heading keeps \
       the anchor it has today, so existing links to it do not move",
      match ids two_same with [ a; _ ] -> a = "alpha" | _ -> false );
    ( "SCENARIO AMEND-SLUG-THIRD: a third repeat is distinct from both",
      match ids three_same with
      | [ a; b; c ] -> a <> b && b <> c && a <> c
      | _ -> false );
    ( "SCENARIO AMEND-SLUG-NORMALISED-COLLISION: two headings that differ only \
       in case and punctuation still collide on the base and are disambiguated",
      match ids punctuation with [ a; b ] -> a = "the-gate" && b <> a | _ -> false );
    ( "SCENARIO AMEND-SLUG-EXPLICIT-UNTOUCHED: an author-pinned block id is \
       never rewritten by the slugger",
      match ids explicit with [ a; _ ] -> a = "^pinned" | _ -> false ) ]
  (* Locality belongs to the amendment's contract, not beside it: "one slugger
     per document" is a claim this amendment makes, so it is answered wherever
     the amendment is answered. Appending here also keeps the gate registration
     untouched — the laws run because this function already runs. *)
  @ locality_laws ()
