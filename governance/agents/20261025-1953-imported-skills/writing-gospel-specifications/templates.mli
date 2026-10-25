(** Verified Gospel templates — one worked example per construct.

    Coverage is the whole Gospel surface, taken from the installed grammar
    (lib/gospel/uast.mli: val_spec, type_spec, fun_spec, and the Sig_* ghost
    items), not from a sample of things that happened to come up. This entire
    file passes `gospel check` as one unit.

    Verify with:  gospel-lint templates.mli *)

(* ================================================================== *)
(* VAL SPECIFICATIONS — clauses: requires, checks, ensures, raises,    *)
(* modifies, consumes, diverges, pure, equivalent.                     *)
(* ================================================================== *)

(* Precondition + postcondition. Each `ensures` is a separate conjunct,
   which reads better than one big conjunction. *)
val clamp : int -> int
(*@ r = clamp x
    requires x >= -1000
    ensures r >= 0
    ensures r >= x *)

(* `checks` means the function itself raises Invalid_argument when the
   condition fails. `requires` means the caller must guarantee it and
   behaviour is otherwise undefined. Pick deliberately. *)
val head_checked : int list -> int
(*@ r = head_checked l
    checks l <> [] *)

val head_required : int list -> int
(*@ r = head_required l
    requires l <> [] *)

(* Exceptional postconditions; one `raises` per exception. *)
exception Negative
exception Overflow

val root : int -> int
(*@ r = root x
    raises Negative -> x < 0
    raises Overflow -> x > 1000000 *)

(* Mutation: `modifies` names what changes, `old` reads the pre-state.
   A unit-returning effect omits the result binding in the header. *)
type cell = { mutable value : int }

val bump : cell -> unit
(*@ bump s
    modifies s
    ensures s.value = old s.value + 1 *)

(* `consumes` marks an argument as spent. It requires a non-unit result:
   on a unit return gospel reports "The function ... returns unit". *)
type token

val redeem : token -> bool
(*@ r = redeem t
    consumes t *)

(* Non-termination is declared, not implied. *)
val serve : int -> int
(*@ r = serve x
    diverges *)

(* `pure` admits the function into the term language for later specs. *)
val canonical : string -> string
(*@ r = canonical text
    pure *)

(* Idempotence must be a TOP-LEVEL axiom: a function is not in scope
   inside its own specification. Quantify with `int` over OCaml int;
   `integer` is Gospel's unbounded type and will not unify. *)
(*@ axiom canonical_idempotent:
      forall text: string. canonical (canonical text) = canonical text *)

(* `equivalent` carries an informal English or code equivalence. *)
val doubled_value : int -> int
(*@ r = doubled_value x
    equivalent "2 * x" *)

(* ================================================================== *)
(* ARGUMENT FORMS                                                      *)
(* ================================================================== *)

(* Labelled and optional arguments bind BARE in the header (`~keep`,
   `?limit`), never `~keep:k`. A labelled function cannot be applied
   inside a term at all, so no axiom may mention `normalize`; state that
   obligation as a property test instead of dropping it. *)
val normalize : keep:bool -> string -> string
(*@ r = normalize ~keep text
    pure *)

val take : ?limit:int -> int list -> int list
(*@ r = take ?limit l *)

(* Tuple results bind each component. *)
val bounds : int list -> int * int
(*@ low, high = bounds l
    requires l <> []
    ensures low <= high *)

val find : int -> int option
(*@ r = find key
    ensures r = None -> key < 0 *)

(* ================================================================== *)
(* TYPE SPECIFICATIONS — ephemeral, model, invariant.                  *)
(* ================================================================== *)

(* `ephemeral` marks a type whose values are mutable/transient. *)
type buffer
(*@ ephemeral *)

(* A model exposes logical state for an abstract type. An invariant
   REQUIRES an abstract type: on a public record gospel reports
   "Invariant on public type". *)
type counter
(*@ mutable model count : integer *)
(*@ with c invariant c.count >= 0 *)

val fresh : unit -> counter
(*@ c = fresh ()
    ensures c.count = 0 *)

(* ================================================================== *)
(* LOGICAL DECLARATIONS — function, predicate, axiom, coercion.        *)
(* ================================================================== *)

(* A logical function exists only for specifications. *)
(*@ function twice (x: integer) : integer = 2 * x *)

(* Recursion needs a `variant` to prove termination. `variant` is a
   FUNCTION-spec clause: it is illegal in a val spec. *)
(*@ function rec countdown (x: integer) : integer =
      if x <= 0 then 0 else countdown (x - 1) *)
(*@ variant x *)

(* A predicate is a function returning a proposition. *)
(*@ predicate nonneg (x: integer) = x >= 0 *)

(*@ predicate rec even (x: integer) =
      if x = 0 then true else not (even (x - 1)) *)
(*@ variant x *)

(* A coercion lets gospel insert this conversion implicitly. *)
type meters
(*@ model size : integer *)

(*@ function meters_to_int (m: meters) : integer = m.size *)
(*@ coercion *)

(* ================================================================== *)
(* GHOST DECLARATIONS — specification-only signature items.            *)
(* ================================================================== *)

(*@ type index *)

(*@ val origin : int *)

(*@ open List *)

(* ================================================================== *)
(* TERM LANGUAGE — let/in, if/then/else, match/with/as, quantifiers,   *)
(* lambdas, and the boolean literals.                                  *)
(* ================================================================== *)

val describe : int option -> int
(*@ r = describe o
    ensures let fallback = 0 in r >= fallback
    ensures r = if r > 0 then r else 0
    ensures match o with (Some v) as w -> w = o | None -> true
    ensures forall y: int. y = y
    ensures exists y: int. y = r
    ensures (fun y -> y) r = r
    ensures not (r < 0) -> true *)
