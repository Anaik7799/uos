(** The live [actual] for the declarative-intent layer: per-fractal-node verdicts
    rolled up from the evidence store's latest parity results.

    Pure over the [(contract_id, passed)] rows {!Evidence_store.parity_results}
    returns: each contract maps to its fractal node
    ([hermes.<family>.<capability>], the first two dotted components), each
    scenario's latest verdict is [Verified] (passed) or [Divergent] (failed), and
    a node's verdict is the {!Parity_algebra.roll_up} of its scenarios -- so one
    failing scenario makes the node [Divergent], and a node with no evidence at
    all is [Unmapped], never a silent pass. *)

val node_of_contract : string -> string
(** ["model_routing.provider_transports.request_shaping"] ->
    ["hermes.model_routing.provider_transports"];
    ["agent_loop.interrupt_control"] -> ["hermes.agent_loop.interrupt_control"]. *)

val per_node : (string * bool) list -> (string * Parity_algebra.verdict) list
(** Group the latest scenario results by node and roll each up
    ([~required:true]), sorted by node. *)

val actual_of : (string * Parity_algebra.verdict) list -> string -> Parity_algebra.verdict
(** The lookup to feed {!Blueprint.reconcile}: a node with no entry is
    [Unmapped]. *)

val family_verdicts :
  catalog:(string * string list) list ->
  nodes:(string * Parity_algebra.verdict) list ->
  (string * Parity_algebra.verdict) list
(** Family-level evidence: for each [(family, capability_nodes)] in the catalog,
    the family node [hermes.<family>] rolls up over ALL its capability nodes'
    verdicts, an uncovered capability counting as [Unmapped] -- so a family is
    [Verified] only when every one of its slices is (the vacuous-truth guard at
    family scale). Also emits the product root [hermes], rolled up over the
    family verdicts the same way. *)

val actual_with_families :
  catalog:(string * string list) list ->
  nodes:(string * Parity_algebra.verdict) list ->
  string ->
  Parity_algebra.verdict
(** The full-fractal lookup: capability nodes from [nodes], family nodes and the
    product root from {!family_verdicts}; anything else is [Unmapped]. *)

val live : Evidence_store.t -> snapshot_digest:string -> (string -> Parity_algebra.verdict, string) result
(** [actual_of (per_node rows)] over the store's latest parity results.
    Capability nodes only; compose with {!actual_with_families} for the full
    fractal. *)
