(* The normative registry of FPP model names and instance base windows.

   Five owners declare FPP models, and until now each carried its own
   model name and base literals: Hermes at 0x700, HermesWikiZk at 0x1800,
   HermesOps at 0x2000, HermesCompletion at 0x3000-0x3600, HermesOperations
   at 0x4000. Their disjointness was recorded in prose — each file's header
   comment names the windows it believes the others hold — and enforced
   nowhere.

   -------------------------------------------------------------------
   WHY THIS MODULE EXISTS, AND WHY IT IS A LEAF

   Task 5's formal relation must assert cross-model window disjointness
   over raw facts. It lives in hermes_ops_dashboard; two of the five
   models live in aggregate hermes_ops, which already depends on the
   dashboard. Importing them would close the cycle

     hermes_ops_dashboard -> hermes_ops -> hermes_ops_dashboard

   and copying their bases into the formula would create a second, stale
   authority — the very failure the formula is meant to detect. So the
   allocation moves DOWN, into a leaf every projection and the formula
   can both reach. This is a MOVED source of authority, not a copied
   projection: once the projections look their bases up here, there is
   exactly one place a window is stated.

   -------------------------------------------------------------------
   NO HOST VERDICT

   [rows] returns raw NORMATIVE facts and nothing else. Missing allocations and
   missing components are reported as [allocation_present = false] and
   [component_present = false] rather than as an error, and a mismatched
   name is reported as a declared/observed PAIR rather than a Boolean.

   Fixed owners contribute only their registered allocations. Operations
   contributes every projected instance under an explicit sequential policy:
   the first base is [window_base Operations] and each successor begins at the
   previous half-open end. Legacy actual instances outside a fixed owner's
   registry are returned by [unregistered_actual_rows], never silently promoted
   into the normative theorem. This is load-bearing: Harness and Wiki currently
   reuse actual bases 0x1000 and 0x1100, while their normative allocations are
   the registered harness_config and auditLoop windows.

   That is deliberate. Model-name equality, allocation presence, base
   equality, positive span, overflow safety (base <= max_int - span) and
   half-open pairwise disjointness are all obligations of the QF_LIA
   formula, discharged by the solver. A [valid : bool] here would be a
   host-precomputed truth handed to Z3 to agree with — exactly what
   independent review rejected in Task 5's first relational cut. *)

type owner = Harness | Wiki | Ops_monitor | Completion | Operations

val owners : owner list
val owner_name : owner -> string

(* The model name each owner is required to declare. *)
val declared_model_name : owner -> string

(* Every declared (instance, component, base) allocation, in a stable
   order. Spans are not stored: a span is a property of the component the
   instance is of, read from [Fpp_model.id_span] at projection time, so
   storing it here would create the second authority this module exists
   to remove. *)
type allocation = {
  alloc_owner : owner;
  instance_id : string;
  component_id : string;
  base_id : int;
}

val allocations : allocation list
val allocations_of : owner -> allocation list

(* The base each owner's projection allocates from — the first base in
   its window, and the value a projection must use instead of a literal. *)
val window_base : owner -> int

(* The registered base for one instance, for a projection to look up
   instead of stating a literal.

   Raises [Invalid_argument] naming the owner and instance when the pair
   is unregistered. That is deliberate and it is not a partial function
   by accident: a projection asks only for instances it declares, so a
   miss means the registry and the projection have diverged — the single
   fault this module exists to make impossible. Failing loudly at module
   initialisation is the honest response; an [option] here would push
   every call site into inventing a fallback, and a fallback is a
   literal, which is what we are removing. *)
val base_of_instance : owner -> string -> int

type row = {
  owner : owner;
  sequential : bool;
  declared_model_name : string;
  observed_model_name : string;
  instance_id : string;
  observed_instance_id : string;
  component_id : string;
  observed_component_id : string;
  allocation_present : bool;   (* the normative allocation is observed *)
  declared_base_id : int;      (* fixed base; sequential first base; then [-1] *)
  observed_base_id : int;      (* [-1] when the instance is absent *)
  component_present : bool;
  span : int;                  (* [Fpp_model.id_span], [0] when absent *)
}

(* Raw normative rows for one owner against the exact model it supplied.
   Fixed owners yield exactly their registered allocation denominator;
   Operations yields its sequential projected denominator. Total: an absent
   fixed allocation or component yields a row with the corresponding
   [_present] flag false rather than being dropped, because a dropped row is a
   fact the formula can no longer refute. *)
val rows : owner -> Fpp_model.model -> row list
(*@ ensures List.length result >= 0 *)

(* Actual instances not admitted by a fixed owner's normative registry. They
   retain their observed identity/base/span and carry [allocation_present =
   false], [declared_base_id = -1]. Operations returns [] because every one of
   its projected instances is governed by the sequential policy. These rows
   are diagnostic facts, not theorem members. *)
val unregistered_actual_rows : owner -> Fpp_model.model -> row list
(*@ ensures List.length result >= 0 *)

(* SHA-256 over the ordered, length-framed raw allocation and owner-policy
   fields. Two registries agree only if every owner, policy, instance,
   component and base agrees in order — length framing so that ("ab","c")
   and ("a","bc") cannot digest alike. *)
val allocation_digest : unit -> string
