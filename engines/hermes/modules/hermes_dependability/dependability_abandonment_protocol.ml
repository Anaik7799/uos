type refusal =
  | Empty_identity
  | Identity_too_long
  | Noncanonical_identity
  | Empty_denominator
  | Duplicate_expected_identity
  | Duplicate_observed_identity
  | Incomplete_denominator
  | Context_mismatch
  | Purpose_mismatch
  | Role_mismatch

let refusal_code = function
  | Empty_identity -> "empty-identity"
  | Identity_too_long -> "identity-too-long"
  | Noncanonical_identity -> "noncanonical-identity"
  | Empty_denominator -> "empty-denominator"
  | Duplicate_expected_identity -> "duplicate-expected-identity"
  | Duplicate_observed_identity -> "duplicate-observed-identity"
  | Incomplete_denominator -> "incomplete-denominator"
  | Context_mismatch -> "context-mismatch"
  | Purpose_mismatch -> "purpose-mismatch"
  | Role_mismatch -> "role-mismatch"

module Identity = struct
  type t = string

  let canonical_byte = function
    | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' -> true
    | _ -> false

  let make value =
    let length = String.length value in
    if length = 0 then Error Empty_identity
    else if length > 128 then Error Identity_too_long
    else if value.[0] = '-' || value.[0] = '.'
            || value.[length - 1] = '-' || value.[length - 1] = '.'
            || not (String.for_all canonical_byte value)
    then Error Noncanonical_identity
    else Ok value

  let to_string value = value
  let equal = String.equal
end

let length_frame fields =
  fields
  |> List.map (fun field -> Printf.sprintf "%d:%s" (String.length field) field)
  |> String.concat ""

let sha256 fields =
  fields |> length_frame |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

type context = {
  manifest : Identity.t;
  dispatch : Identity.t;
  session : Identity.t;
  attempt : Identity.t;
  transition : Identity.t;
  digest : string;
}

let make_context ~manifest ~dispatch ~session ~attempt ~transition =
  let digest =
    sha256
      [ "abandonment-context-v1"; Identity.to_string manifest;
        Identity.to_string dispatch; Identity.to_string session;
        Identity.to_string attempt; Identity.to_string transition ]
  in
  Ok { manifest; dispatch; session; attempt; transition; digest }

let context_equal left right =
  Identity.equal left.manifest right.manifest
  && Identity.equal left.dispatch right.dispatch
  && Identity.equal left.session right.session
  && Identity.equal left.attempt right.attempt
  && Identity.equal left.transition right.transition
  && String.equal left.digest right.digest

type denominator = {
  expected : Identity.t list;
  observed : Identity.t list;
  digest : string;
}

let has_duplicate identities =
  let rec loop seen = function
    | [] -> false
    | identity :: rest ->
        if List.exists (Identity.equal identity) seen then true
        else loop (identity :: seen) rest
  in
  loop [] identities

let ordered_equal left right =
  try List.for_all2 Identity.equal left right with Invalid_argument _ -> false

let make_denominator ~expected ~observed =
  if expected = [] then Error Empty_denominator
  else if has_duplicate expected then Error Duplicate_expected_identity
  else if has_duplicate observed then Error Duplicate_observed_identity
  else if not (ordered_equal expected observed) then Error Incomplete_denominator
  else
    let framed = List.map Identity.to_string expected in
    Ok
      { expected; observed;
        digest = sha256 ("abandonment-denominator-v1" :: framed) }

type global_no_effect = |
type fenced_unentered_tail = |

type _ purpose =
  | Global_no_effect : global_no_effect purpose
  | Fenced_unentered_tail : fenced_unentered_tail purpose

let purpose_key : type p. p purpose -> string = function
  | Global_no_effect -> "global-no-effect"
  | Fenced_unentered_tail -> "fenced-unentered-tail"

type claim = |
type target_entry = |
type effect_role = |
type event = |
type frontier = |
type session = |
type before_after = |

type _ role =
  | Claim : claim role
  | Target_entry : target_entry role
  | Effect : effect_role role
  | Event : event role
  | Frontier : frontier role
  | Session : session role
  | Before_after : before_after role

let role_key : type r. r role -> string = function
  | Claim -> "claim"
  | Target_entry -> "target-entry"
  | Effect -> "effect"
  | Event -> "event"
  | Frontier -> "frontier"
  | Session -> "session"
  | Before_after -> "before-after"

type session_state = Quiescent | Fenced_dead

let session_state_key = function
  | Quiescent -> "quiescent"
  | Fenced_dead -> "fenced-dead"

type _ target_fact =
  | No_source_changing_target_entry : global_no_effect target_fact
  | Terminal_entered_target_prefix_and_tail_unentered :
      fenced_unentered_tail target_fact

let target_fact_key : type p. p target_fact -> string = function
  | No_source_changing_target_entry -> "no-source-changing-target-entry"
  | Terminal_entered_target_prefix_and_tail_unentered ->
      "terminal-entered-target-prefix-and-tail-unentered"

type _ effect_fact =
  | No_effect_applied : global_no_effect effect_fact
  | Terminal_entered_effect_prefix_and_tail_unentered :
      fenced_unentered_tail effect_fact

let effect_fact_key : type p. p effect_fact -> string = function
  | No_effect_applied -> "no-effect-applied"
  | Terminal_entered_effect_prefix_and_tail_unentered ->
      "terminal-entered-effect-prefix-and-tail-unentered"

type _ event_fact =
  | No_effect_event : global_no_effect event_fact
  | Terminal_entered_event_prefix_and_tail_unentered :
      fenced_unentered_tail event_fact

let event_fact_key : type p. p event_fact -> string = function
  | No_effect_event -> "no-effect-event"
  | Terminal_entered_event_prefix_and_tail_unentered ->
      "terminal-entered-event-prefix-and-tail-unentered"

type _ frontier_fact =
  | No_mutation_attempted : global_no_effect frontier_fact
  | Terminal_mutation_frontier_and_tail_unentered :
      fenced_unentered_tail frontier_fact

let frontier_fact_key : type p. p frontier_fact -> string = function
  | No_mutation_attempted -> "no-mutation-attempted"
  | Terminal_mutation_frontier_and_tail_unentered ->
      "terminal-mutation-frontier-and-tail-unentered"

type _ before_after_fact =
  | Exact_operation_tree_source_equal_and_resources_released :
      global_no_effect before_after_fact
  | Pending_transition_and_writer_fence_retained :
      fenced_unentered_tail before_after_fact

let before_after_fact_key : type p. p before_after_fact -> string = function
  | Exact_operation_tree_source_equal_and_resources_released ->
      "exact-operation-tree-source-equal-and-resources-released"
  | Pending_transition_and_writer_fence_retained ->
      "pending-transition-and-writer-fence-retained"

type ('purpose, 'role) prepared_attestation = {
  purpose : 'purpose purpose;
  role : 'role role;
  context : context;
  denominator : denominator;
  fact_key : string;
  digest : string;
}

let make_attestation ~purpose ~role ~(context : context)
    ~(denominator : denominator) ~fact_key =
  let digest =
    sha256
      [ "abandonment-attestation-v1"; purpose_key purpose; role_key role;
        context.digest; denominator.digest; fact_key ]
  in
  Ok { purpose; role; context; denominator; fact_key; digest }

let prepare_claim ~purpose ~context ~denominator =
  make_attestation ~purpose ~role:Claim ~context ~denominator
    ~fact_key:"exact-dispatch-session-attempt-claim"

let prepare_target_entry :
    type p.
    context:context ->
    denominator:denominator ->
    fact:p target_fact ->
    ((p, target_entry) prepared_attestation, refusal) result =
  fun ~context ~denominator ~fact ->
  match fact with
  | No_source_changing_target_entry ->
      make_attestation ~purpose:Global_no_effect ~role:Target_entry ~context
        ~denominator ~fact_key:(target_fact_key fact)
  | Terminal_entered_target_prefix_and_tail_unentered ->
      make_attestation ~purpose:Fenced_unentered_tail ~role:Target_entry
        ~context ~denominator ~fact_key:(target_fact_key fact)

let prepare_effect :
    type p.
    context:context ->
    denominator:denominator ->
    fact:p effect_fact ->
    ((p, effect_role) prepared_attestation, refusal) result =
  fun ~context ~denominator ~fact ->
  match fact with
  | No_effect_applied ->
      make_attestation ~purpose:Global_no_effect ~role:Effect ~context
        ~denominator ~fact_key:(effect_fact_key fact)
  | Terminal_entered_effect_prefix_and_tail_unentered ->
      make_attestation ~purpose:Fenced_unentered_tail ~role:Effect ~context
        ~denominator ~fact_key:(effect_fact_key fact)

let prepare_event :
    type p.
    context:context ->
    denominator:denominator ->
    fact:p event_fact ->
    ((p, event) prepared_attestation, refusal) result =
  fun ~context ~denominator ~fact ->
  match fact with
  | No_effect_event ->
      make_attestation ~purpose:Global_no_effect ~role:Event ~context
        ~denominator ~fact_key:(event_fact_key fact)
  | Terminal_entered_event_prefix_and_tail_unentered ->
      make_attestation ~purpose:Fenced_unentered_tail ~role:Event ~context
        ~denominator ~fact_key:(event_fact_key fact)

let prepare_frontier :
    type p.
    context:context ->
    denominator:denominator ->
    fact:p frontier_fact ->
    ((p, frontier) prepared_attestation, refusal) result =
  fun ~context ~denominator ~fact ->
  match fact with
  | No_mutation_attempted ->
      make_attestation ~purpose:Global_no_effect ~role:Frontier ~context
        ~denominator ~fact_key:(frontier_fact_key fact)
  | Terminal_mutation_frontier_and_tail_unentered ->
      make_attestation ~purpose:Fenced_unentered_tail ~role:Frontier ~context
        ~denominator ~fact_key:(frontier_fact_key fact)

let prepare_session ~purpose ~context ~denominator ~state =
  make_attestation ~purpose ~role:Session ~context ~denominator
    ~fact_key:(session_state_key state)

let prepare_before_after :
    type p.
    context:context ->
    denominator:denominator ->
    fact:p before_after_fact ->
    ((p, before_after) prepared_attestation, refusal) result =
  fun ~context ~denominator ~fact ->
  match fact with
  | Exact_operation_tree_source_equal_and_resources_released ->
      make_attestation ~purpose:Global_no_effect ~role:Before_after ~context
        ~denominator ~fact_key:(before_after_fact_key fact)
  | Pending_transition_and_writer_fence_retained ->
      make_attestation ~purpose:Fenced_unentered_tail ~role:Before_after
        ~context ~denominator ~fact_key:(before_after_fact_key fact)

type packed_prepared =
  | Packed_prepared : ('purpose, 'role) prepared_attestation -> packed_prepared

type 'purpose prepared_abandonment_evidence = {
  prepared_purpose : 'purpose purpose;
  prepared_context : context;
  prepared_role_digests : string list;
  prepared_digest : string;
}

let expected_roles =
  [ "claim"; "target-entry"; "effect"; "event"; "frontier"; "session";
    "before-after" ]

let prepare_join ~claim ~target_entry ~effect_attestation ~event ~frontier ~session
    ~before_after =
  let packed =
    [ Packed_prepared claim; Packed_prepared target_entry;
      Packed_prepared effect_attestation; Packed_prepared event; Packed_prepared frontier;
      Packed_prepared session; Packed_prepared before_after ]
  in
  let contexts_match =
    List.for_all
      (fun (Packed_prepared item) -> context_equal claim.context item.context)
      packed
  in
  let purposes_match =
    List.for_all
      (fun (Packed_prepared item) ->
        String.equal (purpose_key claim.purpose) (purpose_key item.purpose))
      packed
  in
  let roles =
    List.map (fun (Packed_prepared item) -> role_key item.role) packed
  in
  if not contexts_match then Error Context_mismatch
  else if not purposes_match then Error Purpose_mismatch
  else if roles <> expected_roles then Error Role_mismatch
  else
    let role_digests =
      List.map (fun (Packed_prepared item) -> item.digest) packed
    in
    let digest =
      sha256
        ([ "abandonment-prepared-join-v1"; purpose_key claim.purpose;
           claim.context.digest ]
        @ role_digests)
    in
    Ok
      { prepared_purpose = claim.purpose;
        prepared_context = claim.context;
        prepared_role_digests = role_digests;
        prepared_digest = digest }

let prepared_evidence_digest evidence = evidence.prepared_digest
let prepared_evidence_status _ = `Prepared_nonauthorizing

type claim_producer_seal = { claim_producer : Identity.t }
type target_entry_producer_seal = { target_entry_producer : Identity.t }
type effect_producer_seal = { effect_producer : Identity.t }
type event_producer_seal = { event_producer : Identity.t }
type frontier_producer_seal = { frontier_producer : Identity.t }
type session_producer_seal = { session_producer : Identity.t }
type before_after_producer_seal = { before_after_producer : Identity.t }

type ('purpose, 'role) current_attestation = {
  prepared : ('purpose, 'role) prepared_attestation;
  producer_digest : string;
}

let seal producer_key prepared =
  { prepared;
    producer_digest =
      sha256
        [ "abandonment-producer-seal-v1"; producer_key; prepared.digest ] }

let seal_claim producer prepared =
  seal (Identity.to_string producer.claim_producer) prepared

let seal_target_entry producer prepared =
  seal (Identity.to_string producer.target_entry_producer) prepared

let seal_effect producer prepared =
  seal (Identity.to_string producer.effect_producer) prepared

let seal_event producer prepared =
  seal (Identity.to_string producer.event_producer) prepared

let seal_frontier producer prepared =
  seal (Identity.to_string producer.frontier_producer) prepared

let seal_session producer prepared =
  seal (Identity.to_string producer.session_producer) prepared

let seal_before_after producer prepared =
  seal (Identity.to_string producer.before_after_producer) prepared

type 'purpose abandonment_evidence_current = {
  current_purpose : 'purpose purpose;
  current_context : context;
  current_digest : string;
}

let compose ~claim ~target_entry ~effect_attestation ~event ~frontier ~session
    ~before_after =
  match
    prepare_join ~claim:claim.prepared ~target_entry:target_entry.prepared
      ~effect_attestation:effect_attestation.prepared ~event:event.prepared
      ~frontier:frontier.prepared
      ~session:session.prepared ~before_after:before_after.prepared
  with
  | Error _ as error -> error
  | Ok prepared ->
      let producer_digests =
        [ claim.producer_digest; target_entry.producer_digest;
          effect_attestation.producer_digest; event.producer_digest;
          frontier.producer_digest; session.producer_digest;
          before_after.producer_digest ]
      in
      Ok
        { current_purpose = prepared.prepared_purpose;
          current_context = prepared.prepared_context;
          current_digest =
            sha256
              ([ "abandonment-current-join-v1"; prepared.prepared_digest ]
              @ producer_digests) }

let abandonment_evidence_digest evidence = evidence.current_digest

let source_digest =
  sha256
    [ "dependability-abandonment-protocol-v1";
      "roles=claim,target-entry,effect,event,frontier,session,before-after";
      "purposes=global-no-effect,fenced-unentered-tail";
      "exact-ordered-nonempty-denominator";
      "distinct-unconstructible-producer-seals";
      "prepared-is-nonauthorizing";
      "purpose-indexed-seven-argument-compose" ]
