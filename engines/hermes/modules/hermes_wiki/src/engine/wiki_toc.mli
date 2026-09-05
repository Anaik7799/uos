(* HW.6.8.1 — the DECLARED navigation tree. Ported from the imported
   wiki_sidebar_tree_generator (R14 mirror), with its premise inverted:
   the import DERIVED a sidebar from a filesystem walk, and this derives
   nothing. Navigation is AUTHORED, so the reading order stops being an
   accident of filing — that is the whole of the row's argument.

   PURE: a function of Hermes_wiki.model alone. No filesystem, no clock.
   Input order CANNOT matter: declaring pages are visited in SLUG order,
   and entries within a page in SOURCE order, because the authored
   sequence is the point of the feature.

   THE TREE LAW, TRUE BY CONSTRUCTION rather than by test:
     SINGLE ROOT  [t] carries one [root], so a second root is
                  unrepresentable. The root is SYNTHETIC (slug ""),
                  because no document in this corpus is the corpus.
     NODE ONCE    a slug is claimed BEFORE its own entries are read, so
                  "node created" and "slug newly claimed" are the same
                  event. A later claim cannot make a second node.
     ACYCLIC      the same step. Re-entering a slug already on the
                  descent path finds it claimed, so the EDGE is dropped
                  and recorded in [conflicts]; a -> b -> a terminates
                  with b under a. Recursion is bounded by the claimed
                  set, which only grows and is bounded by the page count,
                  so termination needs no fuel parameter.
   One line carries all three — the claim placed before the descent. The
   tests witness these properties; they do not establish them.

   GRAMMAR — a fence whose first info token is exactly "toctree"; the
   body is one target per line, blanks and "#" comments ignored:

     ```toctree maxdepth=2 caption=Guides hidden titlesonly numbered reversed
     playbooks-readme
     01-add-parity-slice
     ```

   Targets resolve through Hermes_wiki.resolver_keys then alias_keys —
   the SAME two-pass key space [build] uses, never a second resolver, so
   an alias can never shadow an identity key (HW.1.2.7). An unresolved
   target is a named [gap], never a quietly missing branch: the dual of
   HW.9.2.1's include law.

   CAPTION IS A WHITESPACE-FREE TOKEN, as literalinclude's markers are —
   a real limit, stated rather than hidden. `glob` is NOT implemented: a
   glob would put the filing accident back inside an authored tree, and
   removing that accident is the row's entire value. *)

type entry = {
  target : string;        (* as written, before resolution *)
  hidden : bool;          (* PLACED but not listed — placement still counts *)
  caption : string;       (* "" when absent *)
  maxdepth : int option;  (* a RENDERING depth; never changes the structure *)
  titlesonly : bool;      (* carried, never consulted here *)
  numbered : bool;        (* carried for HW.6.8.3; numbering is its business *)
}

type node = {
  slug : string;          (* "" only for the synthetic root *)
  title : string;
  hidden : bool;          (* the edge that PLACED this node was hidden *)
  numbered : bool;        (* that edge asked for numbering (HW.6.8.3) *)
  caption : string;
  children : node list;   (* already in final order — the TYPE carries it *)
}

type t

(* [None] unless the first info token is exactly "toctree". TOTAL: a
   malformed option is ignored, never raised. Body lines become targets
   in source order (blanks and "#" comments dropped, duplicates within
   one fence collapsed to the first); `reversed` is applied HERE, so the
   builder never sees the option. *)
val parse_fence : string -> string list -> entry list option

(* The entries a page declares, in source order — fence-aware, so a
   toctree named in prose is not a declaration. *)
val entries_of_page : Hermes_wiki.page -> entry list

(* The declared tree. A page no fence names is NOT attached: that absence
   is HW.6.8.2's evidence, and auto-attaching the leftovers would make
   the unreachable check vacuous. *)
val of_model : Hermes_wiki.model -> t

(* The single synthetic root. TOTAL: an empty model yields a childless
   root, never an exception. *)
val root : t -> node

(* Every placed slug, sorted. Deduplicated BY CONSTRUCTION, so
   |placed| = |walk| is a law rather than a filter. *)
val placed : t -> string list

(* Pages the tree does not place, sorted — HW.6.8.2's raw material. On
   its own this is a FACT; the disclosure that turns it into a verdict is
   that row's to add. *)
val unplaced : Hermes_wiki.model -> t -> string list

(* Depth-first PRE-ORDER, root excluded: (slug, depth, hidden), depth 1
   for a root child. The ONE traversal every consumer shares, so a
   numbering (HW.6.8.3) and a rendering cannot disagree about position. *)
val walk : t -> (string * int * bool) list

(* HW.6.8.2 — the VERDICT, where [unplaced] is only the fact: pages no
   declared tree places AND which did not disclose `orphan: true`.
   A hidden entry still PLACES, so it is never unreachable — that
   distinction is the row's whole subtlety. The disclosure is the escape
   hatch that leaves a mark: it is counted, never silent. *)
val unreachable : Hermes_wiki.model -> t -> string list

(* The disclosed entry points, sorted — an escape hatch nobody can audit
   is not disclosure. *)
val disclosed_orphans : Hermes_wiki.model -> string list

(* HW.6.8.3 — section numbers DERIVED from position, never authored:
   slug -> dotted label ("2", "2.1", "2.1.3"). Only subtrees a `numbered`
   entry introduces are labelled, and the label of a node is a function
   of its path in [walk], so a rendering and a numbering cannot disagree.
   Inserting a sibling renumbers everything BELOW the insertion point and
   nothing above it — the stability the row asks for, and the reason a
   hand-maintained number always rots. *)
val numbering : t -> (string * string) list

(* The declared path from the root to a slug, root excluded, slug last.
   [None] when unplaced. By "each node once" this path is UNIQUE. *)
val path_to : t -> string -> string list option

(* Declarations that could not become edges: an unresolved target, or a
   page naming itself. One sorted line each. LOUD, never silent. *)
val gaps : t -> string list

(* Edges dropped because the target was ALREADY placed — (declaring slug,
   target slug), sorted. Kept apart from [gaps] because the fixes differ:
   a gap wants a target, a conflict wants a decision about which parent
   owns the document. A declaration cycle appears here as its back edge. *)
val conflicts : t -> (string * string) list
