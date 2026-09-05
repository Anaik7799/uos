type level = L0 | L1 | L2 | L3 | L4 | L5 | L6 | LX

type coordinate = { level : level; node : string }

type owner =
  | Portfolio_owner
  | Repository_workspace_owner
  | Policy_coordinator_owner
  | Intent_operation_owner
  | Effect_attempt_owner
  | Readback_evidence_owner
  | Durable_receipt_owner
  | Telemetry_owner

type lifecycle = Declared_unavailable | Implemented_unavailable

type invariant =
  | Canonical_identity
  | Identity_separation
  | Monotone_policy
  | Approval_and_lease_required
  | Apply_once
  | Deterministic_replay
  | Bounded_output
  | Exact_readback
  | Recovery_anchor_retained
  | Source_only_closure
  | Redacted_observation
  | Surface_equivalence
  | Bridge_before_effect
  | Remote_publication_requires_cas

type input =
  | Portfolio_declaration
  | Repository_workspace_identity
  | Policy_and_coordination_state
  | Operation_intent
  | Prepared_effect_attempt
  | Bounded_readback
  | Durable_receipt_input
  | Receipt_observation

type output =
  | Portfolio_scope
  | Repository_workspace_scope
  | Admitted_policy_decision
  | Typed_operation_declaration
  | Effect_attempt_identity
  | Readback_evidence
  | Durable_receipt
  | Non_authorizing_telemetry

type hazard =
  | Authority_drift
  | Identity_aliasing
  | Approval_bypass
  | Lease_bypass
  | Duplicate_apply
  | Unbounded_output
  | Readback_mismatch
  | Recovery_anchor_loss
  | Secret_disclosure
  | Bridge_bypass
  | Unproved_remote_publication
  | False_credit

type kind =
  | Portfolio
  | Repository_workspace
  | Policy_coordinator
  | Intent_operation
  | Effect_attempt
  | Readback_evidence_node
  | Durable_receipt_node
  | Telemetry

type identity = { schema_id : string; authority_digest : string }

type node = {
  kind : kind;
  coordinate : coordinate;
  owner : owner;
  identity : identity;
  invariants : invariant list;
  inputs : input list;
  outputs : output list;
  hazards : hazard list;
  lifecycle : lifecycle;
}

let schema_id = "hermes.jj-fractal-ontology.v1"

let level_key = function
  | L0 -> "L0" | L1 -> "L1" | L2 -> "L2" | L3 -> "L3"
  | L4 -> "L4" | L5 -> "L5" | L6 -> "L6" | LX -> "LX"

let kind_key = function
  | Portfolio -> "portfolio"
  | Repository_workspace -> "repository-workspace"
  | Policy_coordinator -> "policy-coordinator"
  | Intent_operation -> "intent-operation"
  | Effect_attempt -> "effect-attempt"
  | Readback_evidence_node -> "readback-evidence"
  | Durable_receipt_node -> "durable-receipt"
  | Telemetry -> "telemetry"

let owner_key = function
  | Portfolio_owner -> "portfolio-owner"
  | Repository_workspace_owner -> "repository-workspace-owner"
  | Policy_coordinator_owner -> "policy-coordinator-owner"
  | Intent_operation_owner -> "intent-operation-owner"
  | Effect_attempt_owner -> "effect-attempt-owner"
  | Readback_evidence_owner -> "readback-evidence-owner"
  | Durable_receipt_owner -> "durable-receipt-owner"
  | Telemetry_owner -> "telemetry-owner"

let lifecycle_key = function
  | Declared_unavailable -> "declared-unavailable"
  | Implemented_unavailable -> "implemented-unavailable"

let invariant_key = function
  | Canonical_identity -> "canonical-identity"
  | Identity_separation -> "identity-separation"
  | Monotone_policy -> "monotone-policy"
  | Approval_and_lease_required -> "approval-and-lease-required"
  | Apply_once -> "apply-once"
  | Deterministic_replay -> "deterministic-replay"
  | Bounded_output -> "bounded-output"
  | Exact_readback -> "exact-readback"
  | Recovery_anchor_retained -> "recovery-anchor-retained"
  | Source_only_closure -> "source-only-closure"
  | Redacted_observation -> "redacted-observation"
  | Surface_equivalence -> "surface-equivalence"
  | Bridge_before_effect -> "bridge-before-effect"
  | Remote_publication_requires_cas -> "remote-publication-requires-cas"

let input_key = function
  | Portfolio_declaration -> "portfolio-declaration"
  | Repository_workspace_identity -> "repository-workspace-identity"
  | Policy_and_coordination_state -> "policy-and-coordination-state"
  | Operation_intent -> "operation-intent"
  | Prepared_effect_attempt -> "prepared-effect-attempt"
  | Bounded_readback -> "bounded-readback"
  | Durable_receipt_input -> "durable-receipt-input"
  | Receipt_observation -> "receipt-observation"

let output_key = function
  | Portfolio_scope -> "portfolio-scope"
  | Repository_workspace_scope -> "repository-workspace-scope"
  | Admitted_policy_decision -> "admitted-policy-decision"
  | Typed_operation_declaration -> "typed-operation-declaration"
  | Effect_attempt_identity -> "effect-attempt-identity"
  | Readback_evidence -> "readback-evidence"
  | Durable_receipt -> "durable-receipt"
  | Non_authorizing_telemetry -> "non-authorizing-telemetry"

let hazard_key = function
  | Authority_drift -> "HZ-JJ-AUTHORITY-DRIFT"
  | Identity_aliasing -> "HZ-JJ-IDENTITY-ALIASING"
  | Approval_bypass -> "HZ-JJ-APPROVAL-BYPASS"
  | Lease_bypass -> "HZ-JJ-LEASE-BYPASS"
  | Duplicate_apply -> "HZ-JJ-DUPLICATE-APPLY"
  | Unbounded_output -> "HZ-JJ-UNBOUNDED-OUTPUT"
  | Readback_mismatch -> "HZ-JJ-READBACK-MISMATCH"
  | Recovery_anchor_loss -> "HZ-JJ-RECOVERY-ANCHOR-LOSS"
  | Secret_disclosure -> "HZ-JJ-SECRET-DISCLOSURE"
  | Bridge_bypass -> "HZ-JJ-BRIDGE-BYPASS"
  | Unproved_remote_publication -> "HZ-JJ-UNPROVED-REMOTE-PUBLICATION"
  | False_credit -> "HZ-JJ-FALSE-CREDIT"

let sha256 fields =
  fields |> Jj_id.length_frame |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let identity kind authorities =
  { schema_id = schema_id ^ "/" ^ kind_key kind;
    authority_digest = sha256 (kind_key kind :: authorities) }

let make kind level owner authorities invariants inputs outputs hazards =
  { kind; coordinate = { level; node = "jj." ^ kind_key kind }; owner;
    identity = identity kind authorities; invariants; inputs; outputs; hazards;
    lifecycle = Implemented_unavailable }

let operation_authorities =
  [ Jj_operation.source_digest; Jj_action_kind.source_digest ]

let all =
  [ make Portfolio L0 Portfolio_owner
      [ Jj_operation.source_digest; Jj_action_kind.source_digest;
        Jj_recovery_schema.source_digest; Jj_partition.source_digest;
        Jj_source_manifest.schema_id; Jj_secret_scan.source_digest;
        Jj_receipt_core.source_digest ]
      [ Canonical_identity; Identity_separation; Source_only_closure ]
      [ Portfolio_declaration ] [ Portfolio_scope ]
      [ Authority_drift; False_credit ];
    make Repository_workspace L1 Repository_workspace_owner
      [ Jj_source_manifest.schema_id; Jj_partition.source_digest ]
      [ Canonical_identity; Identity_separation; Source_only_closure ]
      [ Repository_workspace_identity ] [ Repository_workspace_scope ]
      [ Identity_aliasing; Secret_disclosure ];
    make Policy_coordinator L2 Policy_coordinator_owner
      [ Jj_action_kind.source_digest; Jj_recovery_schema.source_digest ]
      [ Monotone_policy; Approval_and_lease_required ]
      [ Policy_and_coordination_state ] [ Admitted_policy_decision ]
      [ Approval_bypass; Lease_bypass ];
    make Intent_operation L3 Intent_operation_owner operation_authorities
      [ Canonical_identity; Surface_equivalence; Bridge_before_effect ]
      [ Operation_intent ] [ Typed_operation_declaration ]
      [ Authority_drift; Bridge_bypass ];
    make Effect_attempt L4 Effect_attempt_owner
      [ Jj_action_kind.source_digest; Jj_operation.source_digest ]
      [ Apply_once; Bounded_output; Bridge_before_effect;
        Remote_publication_requires_cas ]
      [ Prepared_effect_attempt ] [ Effect_attempt_identity ]
      [ Duplicate_apply; Unbounded_output; Bridge_bypass;
        Unproved_remote_publication ];
    make Readback_evidence_node L5 Readback_evidence_owner
      [ Jj_operation.source_digest; Jj_secret_scan.source_digest;
        Jj_receipt_core.source_digest ]
      [ Deterministic_replay; Exact_readback; Redacted_observation ]
      [ Bounded_readback ] [ Readback_evidence ]
      [ Readback_mismatch; Secret_disclosure; False_credit ];
    make Durable_receipt_node L6 Durable_receipt_owner
      [ Jj_receipt_core.source_digest; Jj_recovery_schema.source_digest ]
      [ Apply_once; Recovery_anchor_retained; Redacted_observation ]
      [ Durable_receipt_input ] [ Durable_receipt ]
      [ Duplicate_apply; Recovery_anchor_loss; Secret_disclosure ];
    make Telemetry LX Telemetry_owner
      [ Jj_receipt_core.source_digest; Jj_secret_scan.source_digest ]
      [ Bounded_output; Redacted_observation ]
      [ Receipt_observation ] [ Non_authorizing_telemetry ]
      [ Secret_disclosure; False_credit ] ]

let find kind = List.find (fun node -> node.kind = kind) all

let canonical_node_with_lifecycle lifecycle node =
  Jj_id.length_frame
    ([ kind_key node.kind; level_key node.coordinate.level; node.coordinate.node;
       owner_key node.owner; node.identity.schema_id;
       node.identity.authority_digest; lifecycle ]
     @ List.map invariant_key node.invariants
     @ List.map input_key node.inputs
     @ List.map output_key node.outputs
     @ List.map hazard_key node.hazards)

let canonical_node node =
  canonical_node_with_lifecycle (lifecycle_key node.lifecycle) node

let digest_nodes nodes extra =
  sha256 (schema_id :: extra @ List.map canonical_node nodes)

let source_digest = digest_nodes all []

module For_test = struct
  type mutation = Drop_node | Change_identity | Drop_invariant | Claim_available

  let source_digest_with_mutation = function
    | Drop_node -> digest_nodes (List.tl all) []
    | Change_identity ->
        let first = List.hd all in
        let changed =
          { first with identity = { first.identity with authority_digest =
              sha256 [ "mutated-authority" ] } } in
        digest_nodes (changed :: List.tl all) []
    | Drop_invariant ->
        let first = List.hd all in
        let changed = { first with invariants = List.tl first.invariants } in
        digest_nodes (changed :: List.tl all) []
    | Claim_available ->
        let first = List.hd all in
        sha256
          (schema_id :: canonical_node_with_lifecycle "available" first
           :: List.map canonical_node (List.tl all))
end
