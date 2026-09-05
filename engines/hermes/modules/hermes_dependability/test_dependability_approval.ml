open Dependability_approval

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.eprintf "FAILED: %s\n" name
  end

let unavailable code = function
  | Error diagnostic ->
      diagnostic_code diagnostic = code
      && diagnostic_origin diagnostic = Evidence
      && diagnostic_coordinate diagnostic = "L2.Task6.Approval"
  | Ok () -> false

let jj_get label = function Ok value -> value | Error _ -> failwith label

let crypto_get label = function Ok value -> value | Error _ -> failwith label

let frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let hex_value = function
  | '0' .. '9' as value -> Char.code value - Char.code '0'
  | 'a' .. 'f' as value -> 10 + Char.code value - Char.code 'a'
  | _ -> failwith "non-hexadecimal fixture"

let octets hex =
  String.init (String.length hex / 2) (fun index ->
      Char.chr
        ((hex_value hex.[index * 2] lsl 4)
         lor hex_value hex.[(index * 2) + 1]))

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let approval_digest label =
  Jj_approval.Digest.make (sha256 label) |> jj_get "approval digest"

let clock () =
  Dependability_clock.observe ~max_pair_span_ns:1_000_000_000L
    ~lifetime_ns:30_000_000_000L
  |> function Ok receipt -> receipt | Error _ -> failwith "clock unavailable"

let canonical_ticket key_identity context =
  frame
    [ "approval-signed-ticket-v1"; key_identity;
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
      frame
        (List.map Jj_approval.Capability.to_string
           context.capability_references) ]

let () =
  check "P1 production approval authority remains typed unavailable"
    (production_posture = `Implemented_unavailable);

  check "P2 nonce/session key identity and signed-ticket schema prerequisites are current"
    (Result.is_ok (prerequisite_status Authority_nonce_store_protocol)
     && Result.is_ok (prerequisite_status Authority_role_session_fence)
     && Result.is_ok (prerequisite_status Operator_public_key_identity)
     && Result.is_ok (prerequisite_status Canonical_campaign_ticket_schema));

  check "P3 remaining unconstructible approval prerequisites fail closed"
    (List.for_all
       (fun (prerequisite, code) ->
          unavailable code (prerequisite_status prerequisite))
       [ (Campaign_open_current_carrier,
          "campaign-open-current-carrier-unavailable");
         (Dispatch_decision_current_carrier,
          "dispatch-decision-current-carrier-unavailable");
         (Dispatch_abandonment_current_carrier,
          "dispatch-abandonment-current-carrier-unavailable") ]);

  let approval =
    Jj_id.Approval.make "approval-neutral-binding"
    |> jj_get "approval identity"
  in
  let request =
    Jj_id.Request.make "approval-neutral-request"
    |> jj_get "approval request"
  in
  let occurrence =
    Jj_campaign_action.release_request ~request_id:request
    |> Jj_campaign_action.standalone_phase_declarations
    |> List.hd
  in
  check "P4 typed approval and occurrence identities project into the neutral lower protocol"
    (Result.is_ok (bind_authority_approval_identity approval)
     && Result.is_ok (bind_authority_occurrence occurrence));

  let repository =
    Jj_id.Repository.make "approval-repository" |> jj_get "repository"
  in
  let workspace =
    Jj_id.Workspace.make "approval-workspace" |> jj_get "workspace"
  in
  let head = Jj_id.Operation.make "approval-head" |> jj_get "head" in
  let receipt = Jj_id.Receipt.make "approval-receipt" |> jj_get "receipt" in
  let payload =
    Jj_campaign_action.approval_payload ~approval_reference:approval ~occurrence
      ~phase_context:(Jj_campaign_action.Approval_release receipt)
      ~constraints:
        [ Jj_campaign_action.Authorized_phase; Exact_head; Bounded_resources ]
      ~expected_identities:
        [ Jj_campaign_action.Expected_repository repository;
          Expected_workspace workspace; Expected_operation head ]
    |> jj_get "approval payload"
  in
  let context =
    { Jj_approval.payload; plan = approval_digest "approval-plan";
      design = approval_digest "approval-design"; head; repository; workspace;
      phase = "release";
      branch = Jj_approval.Branch.make "approval-branch" |> jj_get "branch";
      actor = Jj_approval.Actor.make "approval-operator" |> jj_get "actor";
      host = Jj_approval.Host.make "approval-host" |> jj_get "host";
      expires_at_epoch = 2_000_000_000L;
      journal_position =
        Jj_approval.Journal_position.make 1L |> jj_get "journal position";
      occurrence_nonce = Jj_campaign_action.occurrence_nonce occurrence;
      capability_references =
        [ Jj_approval.Capability.make "approval-capability"
          |> jj_get "capability" ] }
  in
  let seed =
    octets "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  in
  let public =
    octets "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  in
  let operator_key =
    Dependability_approval_crypto.public_key_of_octets public
    |> crypto_get "operator key"
  in
  let key_identity =
    Dependability_approval_crypto.public_key_identity operator_key
  in
  let ticket = canonical_ticket key_identity context in
  let private_key =
    Mirage_crypto_ec.Ed25519.priv_of_octets seed |> crypto_get "test key"
  in
  let signature =
    Mirage_crypto_ec.Ed25519.sign ~key:private_key
      (frame [ Dependability_approval_crypto.domain_separator; ticket ])
    |> Dependability_approval_crypto.signature_of_octets
    |> crypto_get "signature"
  in
  let now = clock () in
  let verified_ticket =
    verify_signed_ticket ~operator_key ~signature ~now ~expected:context
      ~presented:context
  in
  check "P5 canonical context witness and opaque Ed25519 verification compose one digest-only ticket"
    (match verified_ticket with
     | Error _ -> false
     | Ok ticket ->
         String.length (signed_ticket_digest ticket) = 64
         && String.length (signed_ticket_public_key_identity ticket) = 64
         && String.length (signed_ticket_context_witness_digest ticket) = 64);

  check "P6 source authority kills every named approval-foundation mutant"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation ->
             source_digest <> For_test.source_digest_with_mutation mutation)
          [ For_test.Invent_nonce_store;
            Drop_role_session_fence;
            Accept_raw_signature;
            Accept_partial_ticket;
            Consume_without_campaign_open;
            Consume_unselected_nonce;
            Reopen_terminal_nonce;
            Forge_decision_current;
            Forge_abandonment_current ]);

  let self =
    Suite_telemetry.observe ~suite:"test_dependability_approval"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_dependability_approval ]);
  exit (Suite_telemetry.exit_code self)
