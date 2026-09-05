type rca_origin = Specification | Implementation | Environment | Evidence | Control

type diagnostic =
  | Invalid_clock
  | Approval_context_invalid
  | Approval_signature_invalid
  | Campaign_open_current_carrier_unavailable
  | Dispatch_decision_current_carrier_unavailable
  | Dispatch_abandonment_current_carrier_unavailable

let diagnostic_code = function
  | Invalid_clock -> "invalid-clock"
  | Approval_context_invalid -> "approval-context-invalid"
  | Approval_signature_invalid -> "approval-signature-invalid"
  | Campaign_open_current_carrier_unavailable ->
      "campaign-open-current-carrier-unavailable"
  | Dispatch_decision_current_carrier_unavailable ->
      "dispatch-decision-current-carrier-unavailable"
  | Dispatch_abandonment_current_carrier_unavailable ->
      "dispatch-abandonment-current-carrier-unavailable"

let diagnostic_coordinate _ = "L2.Task6.Approval"
let diagnostic_origin _ = Evidence

type prerequisite =
  | Authority_nonce_store_protocol
  | Authority_role_session_fence
  | Operator_public_key_identity
  | Canonical_campaign_ticket_schema
  | Campaign_open_current_carrier
  | Dispatch_decision_current_carrier
  | Dispatch_abandonment_current_carrier

let prerequisite_status = function
  | Authority_nonce_store_protocol | Authority_role_session_fence ->
      Ok ()
  | Operator_public_key_identity | Canonical_campaign_ticket_schema -> Ok ()
  | Campaign_open_current_carrier ->
      Error Campaign_open_current_carrier_unavailable
  | Dispatch_decision_current_carrier ->
      Error Dispatch_decision_current_carrier_unavailable
  | Dispatch_abandonment_current_carrier ->
      Error Dispatch_abandonment_current_carrier_unavailable

let production_posture = `Implemented_unavailable

type owner = |

let open_owner ~authority:_ ~nonce:_ ~dormancy:_ ~abandonment:_
    ~operator_key:_ ~observed_at:_ =
  Error Campaign_open_current_carrier_unavailable

type signed_ticket = {
  ticket_digest_value : string;
  ticket_public_key_identity : string;
  ticket_context_witness_digest : string;
}
type approved_plan_current = |
type 'family approved_conditional_plan_current = |

let verify_standalone_plan _ ~plan:_ _ =
  Error Campaign_open_current_carrier_unavailable
let verify_conditional_plan _ ~plan:_ _ =
  Error Campaign_open_current_carrier_unavailable

type nonce_state = Available | Consumed | Dormant_closed | Abandoned_closed
type occurrence_nonce = |
type occurrence_capability = |
type dormant_closed_receipt = |
type 'purpose abandoned_closed_receipt = |

let occurrence_nonce _ ~occurrence:_ =
  Error Campaign_open_current_carrier_unavailable
let nonce_state _ _ = Error Campaign_open_current_carrier_unavailable
let close_dormant_once _ _ _ =
  Error Dispatch_decision_current_carrier_unavailable
let close_abandoned_once _ _ _ =
  Error Dispatch_abandonment_current_carrier_unavailable

let sha256 values =
  values |> String.concat "\000"
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let canonical_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let canonical_ticket public_key_identity context =
  canonical_frame
    [ "approval-signed-ticket-v1"; public_key_identity;
      Jj_campaign_action.canonical_approval_unsigned_bytes context.Jj_approval.payload;
      Jj_approval.Digest.to_string context.plan;
      Jj_approval.Digest.to_string context.design;
      Jj_id.Operation.to_string context.head;
      Jj_id.Repository.to_string context.repository;
      Jj_id.Workspace.to_string context.workspace; context.phase;
      Jj_approval.Branch.to_string context.branch;
      Jj_approval.Actor.to_string context.actor;
      Jj_approval.Host.to_string context.host;
      Int64.to_string context.expires_at_epoch;
      Int64.to_string
        (Jj_approval.Journal_position.to_int64 context.journal_position);
      context.occurrence_nonce;
      canonical_frame
        (List.map Jj_approval.Capability.to_string
           context.capability_references) ]

let verify_signed_ticket ~operator_key ~signature ~now ~expected ~presented =
  match Dependability_clock.validate now with
  | Error _ -> Error Invalid_clock
  | Ok () ->
      let now_epoch = Int64.div (Dependability_clock.wall_ns now) 1_000_000_000L in
      begin match Jj_approval.validate ~now_epoch ~expected ~presented with
      | Error _ -> Error Approval_context_invalid
      | Ok witness ->
          let public_key_identity =
            Dependability_approval_crypto.public_key_identity operator_key
          in
          let canonical = canonical_ticket public_key_identity presented in
          begin match
            Dependability_approval_crypto.canonical_signed_bytes
              ~canonical_ticket_bytes:canonical
          with
          | Error _ -> Error Approval_signature_invalid
          | Ok signed ->
              begin match
                Dependability_approval_crypto.verify operator_key signature signed
              with
              | Error _ -> Error Approval_signature_invalid
              | Ok verified ->
                  let context_witness = Jj_approval.witness_digest witness in
                  let canonical_digest = sha256 [ "canonical-ticket"; canonical ] in
                  let verification_digest =
                    Dependability_approval_crypto.verified_digest verified
                  in
                  Ok
                    { ticket_digest_value =
                        sha256
                          [ "approval-signed-ticket-current-v1";
                            public_key_identity; context_witness;
                            canonical_digest; verification_digest ];
                      ticket_public_key_identity = public_key_identity;
                      ticket_context_witness_digest = context_witness }
              end
          end
      end

let signed_ticket_digest ticket = ticket.ticket_digest_value
let signed_ticket_public_key_identity ticket = ticket.ticket_public_key_identity
let signed_ticket_context_witness_digest ticket =
  ticket.ticket_context_witness_digest

let authority_digest domain value =
  match
    Dependability_authority_store.Digest.make
      (sha256 [ domain; value ])
  with
  | Ok digest -> digest
  | Error _ -> assert false

let bind_authority_approval_identity approval =
  let digest =
    authority_digest "approval-neutral-identity-v1"
      (Jj_id.Approval.to_string approval)
  in
  Ok (Dependability_authority_store.approval_identity digest)

let bind_authority_occurrence occurrence =
  let identity =
    authority_digest "approval-neutral-occurrence-v1"
      (Jj_campaign_action.occurrence_id occurrence)
  in
  let nonce =
    authority_digest "approval-neutral-nonce-v1"
      (Jj_campaign_action.occurrence_nonce occurrence)
  in
  Ok (Dependability_authority_store.approval_occurrence ~identity ~nonce)

let source_digest =
  sha256
    [ "dependability-approval-bounded-foundation-v1";
      "authority-store-owns-durable-nonce-state";
      "authority-role-session-fence-required";
      "typed-jj-identities-project-to-neutral-authority-digests";
      "configured-operator-key-identity-required";
      "canonical-complete-campaign-ticket-required";
      "canonical-context-witness-and-ed25519-verification-compose-ticket";
      "ticket-retains-only-key-context-canonical-and-verification-digests";
      "campaign-open-current-required-before-consume";
      "nonce-state:available-consumed-dormant-closed-abandoned-closed";
      "dispatch-decision-current-required-before-dormant-close";
      "dispatch-abandonment-current-required-before-abandoned-close";
      "no-raw-signature-secret-sql-path-or-action-capability";
      "no-owner-ticket-current-nonce-or-authority-forgery" ]

module For_test = struct
  type mutation =
    | Invent_nonce_store
    | Drop_role_session_fence
    | Accept_raw_signature
    | Accept_partial_ticket
    | Consume_without_campaign_open
    | Consume_unselected_nonce
    | Reopen_terminal_nonce
    | Forge_decision_current
    | Forge_abandonment_current

  let mutation_name = function
    | Invent_nonce_store -> "invent-nonce-store"
    | Drop_role_session_fence -> "drop-role-session-fence"
    | Accept_raw_signature -> "accept-raw-signature"
    | Accept_partial_ticket -> "accept-partial-ticket"
    | Consume_without_campaign_open -> "consume-without-campaign-open"
    | Consume_unselected_nonce -> "consume-unselected-nonce"
    | Reopen_terminal_nonce -> "reopen-terminal-nonce"
    | Forge_decision_current -> "forge-decision-current"
    | Forge_abandonment_current -> "forge-abandonment-current"

  let source_digest_with_mutation mutation =
    sha256
      [ "dependability-approval-bounded-foundation-v1";
        mutation_name mutation ]
end
