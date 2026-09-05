let root ~snapshot_digest : Evidence_store.fractal_node =
  { snapshot_digest; id = "hermes"; level = 0; parent_id = None;
    semantic_key = "hermes"; label = "Hermes product"; required = true;
    status_policy = "all-children" }

let families ~snapshot_digest =
  List.map
    (fun (feature : Feature_catalog.feature) ->
      { Evidence_store.snapshot_digest; id = "hermes." ^ feature.id; level = 1;
        parent_id = Some "hermes"; semantic_key = feature.id; label = feature.label;
        required = true; status_policy = "all-children" })
    Feature_catalog.all

let capabilities ~snapshot_digest =
  List.map
    (fun (capability : Capability_catalog.capability) ->
      { Evidence_store.snapshot_digest; id = Capability_catalog.node_id capability; level = 2;
        parent_id = Some (Capability_catalog.parent_node_id capability);
        semantic_key = Capability_catalog.semantic_key capability; label = capability.label;
        required = true; status_policy = "all-children" })
    Capability_catalog.all

(* Parents precede children so the deferred foreign key resolves within one
   transaction regardless of insertion order. *)
let nodes ~snapshot_digest =
  (root ~snapshot_digest :: families ~snapshot_digest) @ capabilities ~snapshot_digest
