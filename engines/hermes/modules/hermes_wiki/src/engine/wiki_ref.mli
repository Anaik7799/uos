(* HW.3.7.1 — typed cross-reference roles (mirror: zigvm note_ref.ml).
   A reference that declares WHAT KIND of thing it expects can be checked
   against that expectation: `kind(resolve_k(x)) = k` — a resolution of
   the wrong kind is a FAILURE, not a fallback.

   ONE grammar for the whole payload of a `[[...]]` reference, used by
   extraction and by BOTH renderers (the block_anchor_split discipline):

     [!] [doc:|term:] target[#fragment] [ |display | |@rel ]

   The role prefix set is CLOSED and lowercase — `[[re: subject]]` is a
   plain target containing a colon, not a role. `!` is HW.3.7.6's
   per-reference opt-out: mentioned, not asserted. *)

type kind = Doc | Term | Any

type t = {
  kind : kind;
  target : string;          (* trimmed; role stripped; fragment KEPT *)
  display : string option;  (* [[t|shown]] — grammar only; rendering of
                               display text is NOT part of HW.3.7.1 *)
  rel : string option;      (* [[t|@rel]] — the discourse dimension,
                               exactly as split_payload always returned *)
  suppress : bool;          (* [[!t]] — not an outlink, never warned *)
}

(* TOTAL: every payload parses; malformed role forms degrade to Any. *)
val parse : string -> t

(* Round-trips parse on canonical (already-trimmed) forms. *)
val to_wiki : t -> string

val kind_name : kind -> string

(* ------------------------------------------------------- resolution
   Pure over PASSED-IN spaces; the engine owns key normalization.
   docs: every (key, slug) registration — the full multimap, NOT the
   first-wins table, so ambiguity (HW.3.7.2) is observable.
   terms: (term, (glossary slug, anchor)) — empty until HW.3.7.4. *)

type candidate = { ckind : kind; cslug : string; canchor : string option }

type spaces = {
  docs : (string * string) list;
  terms : (string * (string * string)) list;
}

(* kind(resolve spaces k x) = k for k <> Any, deduped and sorted;
   Any is the union across kinds (a doc AND a term with one name are
   TWO candidates — ambiguity at the reference site, not a preference). *)
val resolve : spaces -> kind -> string -> candidate list
