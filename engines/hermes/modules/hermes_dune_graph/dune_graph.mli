(** The dune library graph, read from source and closed under reachability.

    This exists because a suite's PREDICTIVE blast radius (R30) is its reverse
    dependency cone, and 160 of 213 declared cones name something that cannot
    be a node in that graph — an executable (a graph LEAF, since nothing
    depends on one) or a bare directory that appears in no stanza at all. A
    hand-written cone cannot be wrong, because nothing checks it. This module
    is what makes it checkable.

    {1 Fail closed, or the fix reproduces the bug}

    A parser that silently skips what it does not understand SHRINKS every
    cone derived from it, which is the original defect one level up: a check
    that cannot see its subject reports success. So:

    - malformed s-expressions {b refuse} rather than yielding a partial census;
    - a [library] stanza without a readable [name] {b refuses};
    - an unrecognised stanza head is recorded in {!ignored_heads} rather than
      dropped, and a test pins that set — a new stanza kind therefore forces a
      deliberate decision instead of quietly reducing the graph.

    {1 The algebra}

    Let [L] be the set of library names and [->] the "depends on" relation.
    [L] is a DAG, so it is a thin category; the reverse cone of [x] is the
    up-set of [x] in [L^op]. {!cone_of_set} is the monotone map
    [P(L) -> P(L)] induced by that up-set, and it satisfies

    {v
      monotone      S subset T  =>  cone S subset cone T
      idempotent    cone (cone S) = cone S
      additive      cone (S union T) = cone S union cone T
    v}

    Additivity is the load-bearing one: it is what lets a battery roll-up
    compose cones by union without recomputing anything, and it is exactly the
    monoid homomorphism [(P(L), union) -> (P(L), union)]. All three are proven
    over the real graph in the test, with mutants. *)

type stanza_kind = Library | Executable | Other of string

type parse_error =
  | Unterminated_sexp of string          (** file *)
  | Unexpected_close of string
  | Library_without_name of string
  | Malformed_libraries of string * string  (** file, library name *)

val string_of_parse_error : parse_error -> string

type library = {
  lib_name : string;
  lib_file : string;                     (** the dune file that declares it *)
  depends_on : string list;              (** verbatim, including externals *)
}

(** Every [(library (name ...))] stanza under [root], or the first refusal.
    Externals (yojson, unix, …) stay in [depends_on]: dropping them here would
    be a silent judgement, and the graph filters them where it matters. *)
val libraries : root:string -> (library list, parse_error) result

(** Stanza heads seen and not interpreted. Pinned by the test so a new kind is
    a deliberate decision, never a silent shrink. *)
val ignored_heads : root:string -> (string list, parse_error) result

type t

val of_libraries : library list -> t
val nodes : t -> string list
val edges : t -> (string * string) list   (** (dependent, dependency), internal only *)

(** Direct dependents: every library naming [x] in its own [libraries] field. *)
val dependents : t -> string -> string list

(** The reverse dependency cone: everything that would be affected if [x] were
    wrong. Transitive, and {b excluding [x] itself} — a suite's own library is
    not part of its blast radius, and including it is how a cone of "1" gets
    reported for a library nothing depends on. Returns the empty set for an
    unknown name rather than raising, because [is_node] is the question to ask
    about membership. *)
val cone : t -> string -> string list

val cone_of_set : t -> string list -> string list
val is_node : t -> string -> bool

(** {1 Independent formal cross-check}

    A QF_LIA rank encoding, mirroring [Dependency_smt]: one integer per node,
    one strict inequality per edge. [sat] exhibits a topological order and so
    proves acyclicity; [unsat] proves a cycle. This is deliberately a SECOND
    path to the same fact — the traversal computes cones assuming
    well-foundedness, and this checks that assumption without reusing the
    traversal. *)
val smt2_acyclic : t -> string
