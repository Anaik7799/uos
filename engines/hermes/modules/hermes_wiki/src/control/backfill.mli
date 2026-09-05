(* Schema backfill (serves HW.1.3.16) — the converge loop's PURE core:
   given what a page already declares and what the evidence supports,
   propose values for the missing PKM fields, or worklist the field for a
   human. NEVER invents: every proposal carries its evidence, and a field
   the evidence cannot derive is Ask, not a guess (R16 for `created`: the
   date comes from git history, supplied by the caller — the IO shell
   reads it, this module never does). *)

type evidence =
  | From_type of string        (* ktype mapped from the discourse type *)
  | From_status of string      (* maturity mapped from status *)
  | From_git of string         (* created: the first-add date *)
  | From_tags of string list   (* topics: the page's own #tags *)
  | From_group of string       (* domain candidate: the page's group *)

type proposal =
  | Set of { field : string; value : string; evidence : evidence }
  | Ask of { field : string; why : string }

type page_facts = {
  slug : string;
  group : string;               (* top directory under the corpus root *)
  authored : string list;       (* frontmatter keys the DOCUMENT actually
                                   carries. A model default is not
                                   evidence: [meta_of] supplies
                                   status="published" and type="note" for
                                   documents that never said so, and
                                   citing those as From_status/From_type
                                   would manufacture provenance. The
                                   guard lives HERE, in the pure core,
                                   because a contract a type enforces
                                   beats one a comment states. *)
  ntype : string;               (* discourse type ('' if absent) *)
  status : string;              (* '' if absent *)
  tags : string list;
  first_add : string option;    (* git first-add date, caller-supplied *)
  missing : string list;        (* the five-field subset actually missing *)
}

(* One proposal or Ask PER MISSING FIELD, in field order — total, pure,
   deterministic. Fields never proposed twice; fields not missing never
   appear. *)
val propose : page_facts -> proposal list

val render : slug:string -> proposal -> string
