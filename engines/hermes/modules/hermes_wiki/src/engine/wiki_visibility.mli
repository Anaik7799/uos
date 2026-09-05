(* HW.1.4.1 — the visibility split. One `status` field could not express
   "published, but not indexed": a work-in-progress note was either
   invisible or fully promoted, so authors published things that were not
   ready or hid things that were useful by link.

   THREE STATES, MUTUALLY EXCLUSIVE AND TOTAL — that is the law, and
   totality is why this is a function of the document rather than a pair
   of independent booleans. Two booleans admit a fourth state nobody
   defined; a closed sum does not.

     Draft     NOT built at all
     Unlisted  built and reachable BY URL, absent from indexes and search
     Listed    built, indexed, searchable

   The frontmatter that decides it, in precedence order:
     `visibility: draft|unlisted|listed`  — explicit, wins
     `draft: true`                        — Docusaurus's spelling
     `unlisted: true`                     — Docusaurus's spelling
     otherwise `status: draft` -> Draft, and everything else -> Listed
   An UNRECOGNISED `visibility` value does not silently become Listed:
   it is reported, on the same ground the discourse vocabulary is closed.
   Publishing a page because its visibility was misspelled is precisely
   the failure this row exists to prevent. *)

type t = Draft | Unlisted | Listed

val of_page : Hermes_wiki.page -> t
val name : t -> string

(* The law, as three predicates a caller can use directly rather than
   re-deriving from the constructor and getting one of them wrong. *)
val in_build : t -> bool   (* Draft is excluded *)
val in_index : t -> bool   (* only Listed *)
val in_search : t -> bool  (* only Listed *)

(* Documents whose `visibility:` field was written but not recognised,
   one sorted line each. NOT silently Listed. *)
val malformed : Hermes_wiki.model -> string list

(* The corpus partitioned, each list sorted — the numbers a dashboard
   reports and a gauge ratchets. *)
val census : Hermes_wiki.model -> (t * string list) list
