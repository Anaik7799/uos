(* quint_rt.ml — the runtime library the Quint→OCaml transpiler emits calls into.

   This is the hand-written "oracle" support code for the pure functional fragment
   of Quint (harness/quint_to_ocaml.ml is the generator). It implements Quint's
   builtin operators over OCaml value types:
     - int   -> OCaml int
     - bool  -> OCaml bool
     - str   -> OCaml string
     - Set   -> a canonical (sorted, duplicate-free) OCaml list, so structural
                equality of two sets is OCaml `=` on the canonical form
     - List  -> an OCaml list (order-preserving, duplicates kept)
     - Map   -> an association list keyed canonically

   Set operations re-canonicalise (sort_uniq) so results are deterministic and
   comparable — mirroring Quint's set semantics where {2,4} = {4,2}. *)

[@@@warning "-a"]

(* ---- sets (canonical sorted-unique lists) ---- *)
let set l = List.sort_uniq compare l
let set_contains s x = List.mem x s          (* contains(set, elem) *)
let set_in x s = List.mem x s                (* elem.in(set) *)
let union a b = List.sort_uniq compare (a @ b)
let intersect a b = List.sort_uniq compare (List.filter (fun x -> List.mem x b) a)
let exclude a b = List.sort_uniq compare (List.filter (fun x -> not (List.mem x b)) a)
let subseteq a b = List.for_all (fun x -> List.mem x b) a
let is_empty c = c = []
let flatten ss = List.sort_uniq compare (List.concat ss)
let set_map f s = List.sort_uniq compare (List.map f s)
let set_filter f s = List.sort_uniq compare (List.filter f s)
let exists f s = List.exists f s
let forall f s = List.for_all f s

(* powerset of a canonical set, itself canonical (a set of sets) *)
let powerset s =
  let subs =
    List.fold_left
      (fun acc x -> acc @ List.map (fun sub -> set (x :: sub)) acc)
      [ [] ] s
  in
  List.sort_uniq compare subs

(* ---- generic size (works on sets, lists, maps: all OCaml lists) ---- *)
let size c = List.length c

(* ---- lists ---- *)
let length l = List.length l
let nth l i = List.nth l i
let head l = List.hd l
let tail l = List.tl l
let append l x = l @ [ x ]
let concat a b = a @ b
let indices l = List.mapi (fun i _ -> i) l
let select f l = List.filter f l
let range lo hi = if hi <= lo then [] else List.init (hi - lo) (fun i -> lo + i)
let replace_at l i x = List.mapi (fun j y -> if j = i then x else y) l
let slice l i j =
  List.filteri (fun k _ -> k >= i && k < j) l

(* fold(coll, init, op) with op(acc, elem) — shared by set fold and list foldl *)
let fold coll init f = List.fold_left f init coll
let foldl coll init f = List.fold_left f init coll

(* ---- maps (canonical assoc lists, sorted by key, unique keys) ---- *)
let map_canon m =
  List.sort_uniq (fun (k1, _) (k2, _) -> compare k1 k2) m
let map_get m k = List.assoc k m
let map_keys m = List.sort_uniq compare (List.map fst m)
let map_put m k v = map_canon ((k, v) :: List.remove_assoc k m)
let map_by f s = map_canon (List.map (fun k -> (k, f k)) s)

(* ---- misc scalar ops ---- *)
let implies a b = (not a) || b
let rec ipow base exp = if exp <= 0 then 1 else base * ipow base (exp - 1)

(* ---- STATE-MACHINE fragment (Phase 2): the bounded trace-explorer =========
   The transpiler emits, for a supported state-machine spec, a [state] record, an
   [init : state], per-action transition functions ([state -> state option], the
   option encoding a guarded action), and a [step : state -> state list] (the
   nondeterministic choice, actionAny). These combinators are the executable
   semantics of the transition system + the bounded temporal-invariant checker,
   the OCaml oracle judged against `quint run`'s bounded checker (differential).

   HONEST SCOPE.  A bounded checker decides temporal properties only over BOUNDED
   runs — the same guarantee `quint run` gives (bounded, seeded simulation), NOT
   full LTL model-checking over infinite traces. [sm_always]/[sm_eventually] are
   evaluated over the FINITE reachable set explored to [max_steps] BFS frontier
   expansions (a fixpoint for a finite state space). "same verdict as Quint's
   bounded checker" is the equivalence claimed, not decidability of ω-properties. *)

(* [sm_any s fs]: apply every candidate transition to [s], keep the enabled ones
   (those returning [Some]). This is actionAny / nondeterministic choice: the set
   of successor states reachable in one step. *)
let sm_any s fs = List.filter_map (fun f -> f s) fs

(* [sm_oneof s choices act]: the SUCCESSOR SET produced by a `nondet x = oneOf(S)`
   binder wrapping a single (option-guarded) action body. For each candidate value
   [c] drawn from the finite choice set [choices] (evaluated on the pre-state [s]),
   run the action [act c s : state option] and keep the ENABLED successors. This is
   the bounded, exhaustive enumeration of Quint's nondeterministic value choice —
   sound because [choices] is finite (a `Set(..)` / a set-valued const or var).
   Enumerating a strict SUBSET of [choices] would drop reachable states (mutant). *)
let sm_oneof s choices act = List.filter_map (fun c -> act c s) choices

(* [sm_oneof_flat s choices act]: the flattening variant for a NESTED nondet whose
   inner body itself yields a successor LIST (e.g. `nondet a = oneOf(A); nondet b =
   oneOf(B); body`). The cartesian product of the choice sets. *)
let sm_oneof_flat s choices act = List.concat_map (fun c -> act c s) choices

(* [sm_reachable ~max_steps ~init ~step]: the canonical (sorted, duplicate-free)
   set of states reachable from [init] within [max_steps] frontier expansions,
   by breadth-first exploration of the [step] transition relation. Bounded ⇒ a
   hang is impossible (mirrors the Zig suite's bounded-driver discipline); for a
   finite state space it reaches the fixpoint well before [max_steps]. *)
let sm_reachable ~max_steps ~init ~step =
  let rec go depth frontier visited =
    if depth >= max_steps || frontier = [] then visited
    else
      let next =
        List.concat_map step frontier
        |> List.filter (fun s -> not (List.mem s visited))
        |> List.sort_uniq compare
      in
      go (depth + 1) next (List.sort_uniq compare (visited @ next))
  in
  go 0 [ init ] [ init ]

(* [sm_always inv reachable]: the safety verdict — [inv] holds in EVERY reachable
   state (bounded ∀). This is `always inv` over the bounded run. *)
let sm_always inv reachable = List.for_all inv reachable

(* [sm_eventually inv reachable]: [inv] holds in SOME reachable state (bounded ∃),
   i.e. `eventually inv`. Distinct from [sm_always]; conflating the two is a real
   verdict-flipping defect (see MUTATION_LOG quint-sm mutant B). *)
let sm_eventually inv reachable = List.exists inv reachable

(* The bounded verdict for `always inv`: `Holds when inv is invariant over the
   reachable set, `Violated otherwise — the shape `quint run` reports via its
   exit code (0 = holds, non-zero = invariant violated). *)
let sm_verdict inv reachable = if sm_always inv reachable then `Holds else `Violated
