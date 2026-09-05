(* HW.10.1.4 — the dependency sheaf: a render sees only its cover.
   Deep-structures pass S27 (unified-deep-structures.md §3, §14), implemented.

   THE SITE. Objects are documents; the covering family of [d] is the set
   [deps d] of slugs whose observables [render d] may consult — today,
   the canonical targets of the wikilinks in d's RAW body (raw, not the
   model's curated outlinks: an allow_example_links page strips its edges
   from the graph, but its render still consults the resolver, and the
   cover must match what render OBSERVES, not what the graph records).

   THE LAW, AND WHY IT IS A TYPE. [Env.view] is abstract, [Env.restrict]
   is its only producer, and there is deliberately no
   [widen : view -> Env.t]. So

     section (Env.restrict e (deps d)) d = section (Env.restrict e all) d

   holds for every consumer of THIS interface: a render that reads outside
   its cover cannot be written against it. Enabling one requires adding a
   widening function here, which is a reviewable interface change.

   ADAPTATIONS from the proposal, stated per the honesty rule:
   - slugs are strings (the phantom-typed Id module is future work);
   - Observable is consulted for EXISTENCE only, because today's renderer
     reads nothing else from a link target; title and anchors ride along
     for the features that will need them (transclusion, typed refs);
   - the perturbation domain for tightness (L27.5) is existence flips —
     remove-or-add — matching that observable. Addressing-level changes
     (retitles that re-key the resolver) are environment changes, outside
     a single view's law.

   ADMISSIBILITY. No IO anywhere: [Env.of_model] consumes an already-built
   model. Sections are bytes, so P1 is untouched and the digest keeps its
   meaning. *)

module Cover : sig
  type t

  val empty : t
  val of_list : string list -> t
  val union : t -> t -> t
  val inter : t -> t -> t
  val mem : t -> string -> bool

  (* Sorted and deduplicated: a cover has ONE serialisation (L27.6). *)
  val elements : t -> string list
  val equal : t -> t -> bool
end

module Observable : sig
  (* Everything one document may learn about another. Deliberately small:
     a cover only means something if the observable does; adding a field
     widens every cover and must be priced. *)
  type t = {
    exists : bool;
    title : string;
    anchors : string list;
  }
end

module Env : sig
  type t
  type view (* ABSTRACT — restrict is the only producer; no widening *)

  val of_model : Hermes_wiki.model -> t
  val restrict : t -> Cover.t -> view
  val narrow : view -> Cover.t -> view
  (* cover_of (narrow v c) = inter (cover_of v) c  — L27.2 *)
  val observe : view -> string -> Observable.t option
  val cover_of : view -> Cover.t
end

module Section : sig
  type t

  val empty : t
  val append : t -> t -> t (* bytes (append a b) = bytes a ^ bytes b *)
  val bytes : t -> string
end

(* The cover of a document: the canonical slugs its render may consult. *)
val deps : Hermes_wiki.model -> Hermes_wiki.page -> Cover.t

(* The local section — the ONLY renderer in this module; [render] is its
   bytes. Pure: a function of the view and the document alone. *)
val section : Env.view -> Hermes_wiki.page -> Section.t
val render : Env.view -> Hermes_wiki.page -> string

(* The global family: every document against its own cover. *)
val build : Env.t -> Hermes_wiki.model -> (string * Section.t) list

(* Descent: the glued family, in slug order — one serialisation, so the
   result is independent of family order and of how work was partitioned
   (L27.3), which is what makes worker count irrelevant. *)
val glue : (string * Section.t) list -> Section.t

(* Incremental: recompute exactly [changed] and its dependents; reuse the
   rest. L27.4: byte-identical to a cold [build]. *)
val rebuild :
  previous:(string * Section.t) list ->
  Env.t ->
  changed:Cover.t ->
  Hermes_wiki.model ->
  (string * Section.t) list

(* The transpose of [deps]: who must be rebuilt when [slug] changes.
   Derived, never stored — ontology I3. *)
val dependents : Hermes_wiki.model -> string -> string list

(* L27.5 as an executable check: cover elements whose existence-flip does
   NOT change the section. Always [] for [deps]-derived covers; a non-empty
   result means the cover over-approximates and incremental work is wasted.
   [widen_with] exists for the meta-falsification leg: prove the check can
   fail by handing it a deliberately widened cover. *)
val dead_cover_elements :
  ?widen_with:string list -> Hermes_wiki.model -> Hermes_wiki.page -> string list
