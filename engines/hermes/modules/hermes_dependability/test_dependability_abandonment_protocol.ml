open Dependability_abandonment_protocol

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let get = function Ok value -> value | Error refusal -> failwith (refusal_code refusal)
let is_error = function Error _ -> true | Ok _ -> false
let id value = get (Identity.make value)

let context suffix =
  get
    (make_context ~manifest:(id ("manifest-" ^ suffix))
       ~dispatch:(id ("dispatch-" ^ suffix))
       ~session:(id ("session-" ^ suffix))
       ~attempt:(id ("attempt-" ^ suffix))
       ~transition:(id ("transition-" ^ suffix)))

let denominator labels =
  let identities = List.map id labels in
  get (make_denominator ~expected:identities ~observed:identities)

let global_bundle context =
  let purpose = Global_no_effect in
  let singleton role = denominator [ "global-" ^ role ] in
  ( get (prepare_claim ~purpose ~context ~denominator:(singleton "claim")),
    get
      (prepare_target_entry ~context ~denominator:(singleton "target")
         ~fact:No_source_changing_target_entry),
    get
      (prepare_effect ~context ~denominator:(singleton "effect")
         ~fact:No_effect_applied),
    get
      (prepare_event ~context ~denominator:(singleton "event")
         ~fact:No_effect_event),
    get
      (prepare_frontier ~context ~denominator:(singleton "frontier")
         ~fact:No_mutation_attempted),
    get
      (prepare_session ~purpose ~context ~denominator:(singleton "session")
         ~state:Quiescent),
    get
      (prepare_before_after ~context ~denominator:(singleton "before-after")
         ~fact:Exact_operation_tree_source_equal_and_resources_released) )

let fenced_bundle context =
  let purpose = Fenced_unentered_tail in
  let coverage role = denominator [ "prefix-" ^ role; "tail-" ^ role ] in
  ( get (prepare_claim ~purpose ~context ~denominator:(coverage "claim")),
    get
      (prepare_target_entry ~context ~denominator:(coverage "target")
         ~fact:Terminal_entered_target_prefix_and_tail_unentered),
    get
      (prepare_effect ~context ~denominator:(coverage "effect")
         ~fact:Terminal_entered_effect_prefix_and_tail_unentered),
    get
      (prepare_event ~context ~denominator:(coverage "event")
         ~fact:Terminal_entered_event_prefix_and_tail_unentered),
    get
      (prepare_frontier ~context ~denominator:(coverage "frontier")
         ~fact:Terminal_mutation_frontier_and_tail_unentered),
    get
      (prepare_session ~purpose ~context ~denominator:(coverage "session")
         ~state:Fenced_dead),
    get
      (prepare_before_after ~context ~denominator:(coverage "before-after")
         ~fact:Pending_transition_and_writer_fence_retained) )

let prepare_bundle (claim, target_entry, effect_attestation, event, frontier, session,
    before_after) =
  prepare_join ~claim ~target_entry ~effect_attestation ~event ~frontier ~session
    ~before_after

let () =
  check "A1 identities are bounded canonical lower-ASCII tokens"
    (Result.is_ok (Identity.make "dispatch-01")
     && List.for_all is_error
          [ Identity.make ""; Identity.make "UPPER"; Identity.make "../escape";
            Identity.make (String.make 129 'a') ]);
  check "A2 a denominator requires a nonempty exact ordered observation"
    (let a = id "node-a" and b = id "node-b" in
     Result.is_ok (make_denominator ~expected:[ a; b ] ~observed:[ a; b ])
     && is_error (make_denominator ~expected:[] ~observed:[])
     && is_error (make_denominator ~expected:[ a; b ] ~observed:[ a ])
     && is_error (make_denominator ~expected:[ a; b ] ~observed:[ b; a ]));
  check "A3 duplicate expected or observed nodes are refused"
    (let a = id "node-a" in
     is_error (make_denominator ~expected:[ a; a ] ~observed:[ a ])
     && is_error (make_denominator ~expected:[ a ] ~observed:[ a; a ]));
  let global = global_bundle (context "global") in
  let fenced = fenced_bundle (context "fenced") in
  check "A4 all seven exact global-no-effect roles prepare one structural join"
    (Result.is_ok (prepare_bundle global));
  check "A5 all seven exact fenced-tail roles prepare one structural join"
    (Result.is_ok (prepare_bundle fenced));
  check "A6 a stale or cross-context role attestation refuses the join"
    (let claim, target_entry, effect_attestation, _, frontier, session, before_after = global in
     let foreign_event =
       get
         (prepare_event ~context:(context "foreign")
            ~denominator:(denominator [ "global-event" ])
            ~fact:No_effect_event)
     in
     is_error
       (prepare_join ~claim ~target_entry ~effect_attestation
          ~event:foreign_event ~frontier
          ~session ~before_after));
  check "A7 global and fenced preparations remain purpose-distinct"
    (let global = get (prepare_bundle global) in
     let fenced = get (prepare_bundle fenced) in
     prepared_evidence_digest global <> prepared_evidence_digest fenced);
  check "A8 preparation is deterministic and binds every role"
    (let one = get (prepare_bundle (global_bundle (context "repeat"))) in
     let two = get (prepare_bundle (global_bundle (context "repeat"))) in
     let _, target_entry, effect_attestation, event, frontier, session,
         before_after = global_bundle (context "repeat") in
     let changed_claim =
       get
         (prepare_claim ~purpose:Global_no_effect ~context:(context "repeat")
            ~denominator:(denominator [ "global-claim-changed" ]))
     in
     let changed =
       get
         (prepare_join ~claim:changed_claim ~target_entry ~effect_attestation
            ~event
            ~frontier ~session ~before_after)
     in
     prepared_evidence_digest one = prepared_evidence_digest two
     && prepared_evidence_digest one <> prepared_evidence_digest changed);
  check "A9 prepared evidence is explicitly noncurrent and nonauthorizing"
    (prepared_evidence_status (get (prepare_bundle global))
     = `Prepared_nonauthorizing);
  check "A10 refusals carry stable closed codes"
    (let a = id "node-a" and b = id "node-b" in
     match make_denominator ~expected:[ a ] ~observed:[ b ] with
     | Error refusal -> refusal_code refusal = "incomplete-denominator"
     | Ok _ -> false);
  check "A11 source identity is a deterministic SHA-256 shape"
    (String.length source_digest = 64);
  let self =
    Suite_telemetry.observe ~suite:"test_dependability_abandonment_protocol"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_abandonment_protocol ]);
  exit (Suite_telemetry.exit_code self)
