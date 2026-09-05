(* note_ref.ml — a wiki link is a route over a different address space.

   THE CLAIM THIS MAKES GOOD. The fractal reading of this system says the same
   structure recurs at different scales. That is easy to assert and usually
   decorative. Here it is checkable: a `[[note]]` link is an ADDRESS, the note
   set is the ADDRESS SPACE, resolution is a PARTIAL FUNCTION, and the
   integrity property is the one already written for HTTP —

     LAW COVERAGE-SERVED   every route the server serves is named by the algebra
     LAW LINK-COVERAGE     every [[link]] resolves to a note that exists

   — the same law at two scales. One algebra, one law family, three surfaces
   (HTTP, wiki, ZK). If that were merely a nice way of talking, the second law
   would not be able to fail. It can.

   SEMANTIC DOMAIN.

     ⟦·⟧ : Ref → Slug          resolve : Corpus → Slug ⇀ Note

   ENCODINGS of link extraction, which is the part with real edge cases:

     ORACLE — split the text on the opening delimiter and take each fragment
       up to the closing one. Obviously correct and quadratic-ish.
     FINAL — one indexed pass. Fast, and where an unterminated `[[` at end of
       file, or a `]]` with no opener, silently swallows the remainder.

   SCOPE LIMIT. This resolves links against a corpus of note names. It does not
   render, does not follow transclusion, and takes no position on whether a
   note's CONTENT is correct. *)

(* ---------- the address ----------------------------------------------------
   Abstract, exactly as `Route_algebra.Id` is, and for the same reason: the
   only way to obtain one is a partial constructor, so a caller must confront
   a malformed link rather than discovering it when the page renders. *)

module Slug : sig
  type t

  val of_string : string -> t option
  val to_string : t -> string
  val equal : t -> t -> bool
end = struct
  type t = string

  (* A slug is trimmed and case-folded, because `[[Agent-Handover]]` and
     `[[agent-handover]]` address the same note and a resolver that disagrees
     produces a broken link that looks correct in the source. Rejected: empty,
     path separators, and the traversal segments. *)
  let of_string s =
    let s = String.trim s in
    let s = String.lowercase_ascii s in
    (* `_` and `-` are the same separator here: the corpus holds
       `ALGEBRAIC_DOC_REVIEW.md` and links to it as `algebraic-doc-review`, and a
       TITLE link like [[The Gate]] addresses the same note as the-gate. This
       is the repository's own znorm folding, not an invention.
       Normalising both sides is what makes those the same address rather
       than a broken link that looks correct. *)
    let s = String.map (fun c -> if c = '_' || c = ' ' then '-' else c) s in
    if s = "" || s = "." || s = ".." then None
    else if String.exists (fun c -> c = '/' || c = '\\' || Char.code c < 0x20) s then None
    else Some s

  let to_string s = s
  let equal a b = String.equal a b
end

type t = { slug : Slug.t; alias : string option }

let make ?alias slug = { slug; alias }
let slug_of (r : t) = r.slug
let display (r : t) = match r.alias with Some a -> a | None -> Slug.to_string r.slug

(* A reference's text form. Round-trips through the extractor, which is what
   the ROUND-TRIP law checks. *)
let to_wiki (r : t) : string =
  match r.alias with
  | None -> "[[" ^ Slug.to_string r.slug ^ "]]"
  | Some a -> "[[" ^ Slug.to_string r.slug ^ "|" ^ a ^ "]]"

(* ---------- extraction -----------------------------------------------------
   `[[name]]` and `[[name|alias]]`. Both encodings are TOTAL: an unterminated
   opener yields the references found so far, never an exception and never a
   silent truncation of the ones already seen. *)

let open_delim = "[" ^ "["
let close_delim = "]" ^ "]"

let split_alias (body : string) : string * string option =
  match String.index_opt body '|' with
  | None -> (body, None)
  | Some i ->
      let name = String.sub body 0 i in
      let alias = String.sub body (i + 1) (String.length body - i - 1) in
      (name, if String.trim alias = "" then None else Some alias)

(* ORACLE: split on the opener, then take each fragment up to the closer. *)
let extract_oracle (text : string) : t list =
  let parts =
    (* split on the two-character opener *)
    let rec go acc start i =
      if i + 2 > String.length text then List.rev (String.sub text start (String.length text - start) :: acc)
      else if String.sub text i 2 = open_delim then go (String.sub text start (i - start) :: acc) (i + 2) (i + 2)
      else go acc start (i + 1)
    in
    match go [] 0 0 with [] -> [] | _ :: rest -> rest (* drop the text before the first opener *)
  in
  List.filter_map
    (fun fragment ->
      let rec find i =
        if i + 2 > String.length fragment then None
        else if String.sub fragment i 2 = close_delim then Some i
        else find (i + 1)
      in
      match find 0 with
      | None -> None (* unterminated opener: not a reference *)
      | Some j ->
          let body = String.sub fragment 0 j in
          let name, alias = split_alias body in
          (match Slug.of_string name with Some s -> Some (make ?alias s) | None -> None))
    parts

(* FINAL: one indexed pass. *)
let extract (text : string) : t list =
  let n = String.length text in
  let out = ref [] in
  let i = ref 0 in
  while !i + 2 <= n do
    if String.sub text !i 2 = open_delim then begin
      (* Scan for the closer, but a NEW opener wins: `[[a[[b]]]]` addresses
         `b`, not `a[[b`. An opener inside a body means the outer one was not
         a link, and a one-pass scanner that ignores this silently produces an
         address nobody wrote. Caught by ORACLE-FINAL — the oracle splits on
         the opener, so it had last-opener-wins for free. *)
      let j = ref (!i + 2) in
      let restart = ref (-1) in
      while !restart < 0 && !j + 2 <= n && String.sub text !j 2 <> close_delim do
        if String.sub text !j 2 = open_delim then restart := !j else incr j
      done;
      if !restart >= 0 then i := !restart
      else if !j + 2 <= n then begin
        let body = String.sub text (!i + 2) (!j - !i - 2) in
        let name, alias = split_alias body in
        (match Slug.of_string name with Some s -> out := make ?alias s :: !out | None -> ());
        i := !j + 2
      end
      else i := n (* unterminated: stop, keeping what was found *)
    end
    else incr i
  done;
  List.rev !out

(* ---------- code is not prose ----------------------------------------------
   A first run over the real corpus reported `[[1,2,3]]`, `[[955]]` and
   `[[...]]` as broken links. They are not links at all — they are matrix
   literals and code samples inside fenced blocks. The extractor was over-
   matching, which is the lint programme's lesson arriving one scale down: a
   scanner over a structured format needs the format's STRUCTURE, and a
   markdown fence is structure.

   Masking replaces code regions with spaces, preserving every byte OFFSET, so
   a reference's position is still meaningful and both encodings see the same
   input — ORACLE-FINAL therefore still binds the pair.

   LIMIT, stated because the precision of a scanner is exactly what the last
   programme showed is worth stating: this handles fenced blocks (``` and ~~~)
   and single-backtick inline spans. It does not handle indented code blocks,
   which are rare here and would need the full block algebra to detect. A
   `[[link]]` inside a four-space-indented block would still be counted.

   It also pairs inline backticks WITHIN A LINE. A code span that crosses a
   line break is legal markdown and one in MUTATION_LOG.md does exactly that,
   leaving its example exposed. Pairing globally was tried and made things
   worse: an unmatched backtick anywhere then shifts every span after it, and
   the count went 8 -> 9 with two NEW false links. A BOUNDED one-line carry
   was then tried and fails the same way for the same reason — the carry
   consumed the OPENING backtick of a legitimate heading span one line later,
   exposing it (1 -> 2). One line of carry is enough to invert the pairing.
   Per-line pairing contains the damage to a single line, so it stays and the
   residual was removed at the SOURCE instead: the one example whose span
   crossed a line break was joined onto a single line, which is a formatting
   normalisation of a code fragment rather than a change of meaning. The
   limit below is therefore still REAL — a multi-line span would still leak —
   but the corpus no longer contains one, so the ratchet stands at zero. *)

let mask_code (text : string) : string =
  let lines = String.split_on_char '\n' text in
  let in_fence = ref false in
  let masked =
    List.map
      (fun line ->
        let trimmed = String.trim line in
        let is_fence =
          (String.length trimmed >= 3 && String.sub trimmed 0 3 = "```")
          || (String.length trimmed >= 3 && String.sub trimmed 0 3 = "~~~")
        in
        if is_fence then begin
          in_fence := not !in_fence;
          String.map (fun _ -> ' ') line
        end
        else if !in_fence then String.map (fun _ -> ' ') line
        else begin
          (* blank single-backtick spans, offsets preserved *)
          let b = Bytes.of_string line in
          let n = Bytes.length b in
          let i = ref 0 in
          while !i < n do
            if Bytes.get b !i = '`' then begin
              let j = ref (!i + 1) in
              while !j < n && Bytes.get b !j <> '`' do incr j done;
              if !j < n then begin
                for k = !i to !j do Bytes.set b k ' ' done;
                i := !j + 1
              end
              else i := n
            end
            else incr i
          done;
          Bytes.to_string b
        end)
      lines
  in
  String.concat "\n" masked

(** Extraction from a DOCUMENT rather than from raw text: code is excluded
    first. Both encodings compose with it identically. *)
let extract_document (text : string) : t list = extract (mask_code text)
let extract_document_oracle (text : string) : t list = extract_oracle (mask_code text)

(* ---------- resolution ----------------------------------------------------- *)

type corpus = { notes : Slug.t list }

let corpus_of_names (names : string list) : corpus =
  { notes = List.filter_map Slug.of_string names }

let resolves (c : corpus) (r : t) : bool = List.exists (Slug.equal r.slug) c.notes

let unresolved (c : corpus) (refs : t list) : t list =
  List.filter (fun r -> not (resolves c r)) refs
