(* HW.5.1.* / HW.5.2.* — zkquery: notes as data.

   Mirrored from zigvm's `docs_wiki.ml` §2253-2485 (R14), extended with
   `group by` (HW.5.1.5), which is Missing in BOTH Notion and Obsidian and
   is the natural shape of the grammar.

     [from (all|type:T|group:G|tag:T)]
     [where COND (and COND)*]
     [group by (status|type|group)]
     [sort KEY [asc|desc]]
     [limit N]

     COND := FIELD(=|!=)VALUE     for status|type|group|slug|tag
           | FIELD(=|>|>=|<|<=)N  for words|degree|outlinks|backlinks

   The grammar is deliberately NON-RECURSIVE, so termination is structural.

   Laws (plan §8.0.5):
     total       every input yields Ok or a NAMED Error; the parser never
                 raises and never returns a silently empty result — an
                 empty result must mean "no matches", never "bad query".
     sound       every returned row satisfies every condition.
     commute     `where a and b` == `where b and a`.
     monotone    `limit n` is a PREFIX of `limit m` for m >= n.
     determinism sort is a total order via the slug tiebreak, so a result
                 is pinnable by the render baseline.
     partition   `group by` is disjoint and covering. *)

type cond = { field : string; op : string; value : string }

type query = {
  conds : cond list;
  group_by : string option;
  sort : string * bool;  (* key, descending? *)
  limit : int option;
}

val string_fields : string list
val int_fields : string list
val sort_keys : string list
val group_keys : string list

(* Total: never raises; a malformed query is a NAMED error. *)
val parse : string -> (query, string) result

(* Pure: depends only on (pages, query), so a rendering is pinnable. *)
val eval : Hermes_wiki.page list -> query -> Hermes_wiki.page list

(* [eval] then partition by [group_by]; a query without `group by` yields a
   single anonymous bucket, so callers need no special case. Buckets are
   ordered by key, deterministically. *)
val group : Hermes_wiki.page list -> query -> (string * Hermes_wiki.page list) list

(* The ```zkquery fences of a note, in order — HW.5.4.1: a query is a note,
   so the same query can be embedded anywhere and reviewed in a diff. *)
val fences : string -> string list
