type authority = Load_bearing_dispatch_gate | Analysis_only

type gate = Stpa_fmea | Rete_ul | Raven_matrix | Ruliad | Stan_model | Z3
  | Assurance

type receipt_outcome = Satisfied | Rejected of string list
  | Unavailable_observed of string

type error_code = Invalid_context | Context_mismatch | Invalid_receipt
  | Invalid_model | Duplicate_receipt

type gate_error = { code : error_code; message : string;
  context_digest : string option; coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin; hazard_id : string }

type current_head_source = Test_only | Store_source of Run_event_store.t

type current_head_receipt = { run_id : string; provenance : Run_model.provenance;
  head_sequence : int64; head_event_digest : string; observed_at_ns : int64;
  current_at_ns : int64; expires_at_ns : int64;
  observed_monotonic_ns : int64; expires_monotonic_ns : int64;
  authority_digest : string; receipt_digest : string;
  source : current_head_source }

type gate_context = { run_id : string; request_id : string; activity_id : string;
  provenance : Run_model.provenance; coordinate : Ops_capability.coordinate;
  plane : Ops_capability.plane; current_head_digest : string;
  current_at_ns : int64; context_digest : string;
  current_head : current_head_receipt }

type receipt = { gate : gate; authority : authority; outcome : receipt_outcome;
  context_digest : string; coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin; hazard_ids : string list;
  evidence_digest : string; receipt_digest : string }

type uca_kind = Not_provided | Provided_unsafe | Wrong_timing
  | Applied_too_long
type risk = { severity : int; occurrence : int; detectability : int }
type loss = { stable_id : string; edge_id : string; description : string }
type hazard = { stable_id : string; edge_id : string; description : string;
  loss_ids : string list }
type causal_scenario = { stable_id : string; edge_id : string;
  hazard_ids : string list; description : string }
type unsafe_control_action = { stable_id : string; edge_id : string;
  kind : uca_kind; hazard_ids : string list; causal_scenario_ids : string list;
  constraint_ids : string list }
type safety_constraint = { stable_id : string; edge_id : string;
  uca_ids : string list; statement : string; control : string; owner : string;
  verifier_id : string }
type control_evidence = { failure_mode_id : string; control_ids : string list;
  verifier_id : string; original_risk_digest : string;
  residual_risk_digest : string; model_authority_digest : string;
  context_digest : string; current_head_digest : string;
  observed_at_ns : int64; evidence_digest : string }
type residual_acceptance = { failure_mode_id : string; requirement_id : string;
  owner : string; rationale : string; context_digest : string;
  current_head_digest : string; authority_digest : string;
  original_risk_digest : string; residual_risk_digest : string;
  model_authority_digest : string; accepted_at_ns : int64;
  expires_at_ns : int64; acceptance_digest : string }
type failure_mode = { stable_id : string; edge_id : string;
  requirement_id : string; hazard_ids : string list; failure_effect : string;
  cause : string; control_ids : string list; owner : string;
  initial_risk : risk; residual_risk : risk; verifier_id : string;
  control_evidence : control_evidence option;
  acceptance : residual_acceptance option }
type path_analysis = { edge_id : string; loss_ids : string list;
  hazard_ids : string list; uca_ids : string list;
  causal_scenario_ids : string list; constraint_ids : string list;
  failure_mode_ids : string list }
type model = { topology_digest : string; evaluated_at_ns : int64;
  residual_rpn_threshold : int; losses : loss list; hazards : hazard list;
  causal_scenarios : causal_scenario list;
  unsafe_control_actions : unsafe_control_action list;
  constraints : safety_constraint list; failure_modes : failure_mode list;
  paths : path_analysis list }
type decision = Admit | Block of string list
type assurance_evaluation = { admitted : bool; reasons : string list;
  receipt : receipt }

let ( let* ) value f =
  match value with Ok result -> f result | Error _ as error -> error

let nonempty value = String.trim value <> ""

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let is_hex = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let valid_digest value =
  String.length value = 64 && String.for_all is_hex value

let coordinate_json (coordinate : Ops_capability.coordinate) =
  `Assoc
    [ ("level", `String (Ops_capability.string_of_level coordinate.level));
      ("phase", `String (Ops_capability.string_of_phase coordinate.phase)) ]

let provenance_json (provenance : Run_model.provenance) =
  `Assoc
    [ ("authorityDigest", `String provenance.authority_digest);
      ("configurationDigest", `String provenance.configuration_digest);
      ("executableDigest", `String provenance.executable_digest);
      ("sourceClean", `Bool provenance.source_clean);
      ("sourceRevision", `String provenance.source_revision) ]

let plane_string = Ops_capability.string_of_plane

let context_json ~run_id ~request_id ~activity_id ~provenance ~coordinate
    ~plane ~current_head_digest ~current_at_ns =
  `Assoc
    [ ("activityId", `String activity_id);
      ("coordinate", coordinate_json coordinate);
      ("currentAtNs", `Intlit (Int64.to_string current_at_ns));
      ("currentHeadDigest", `String current_head_digest);
      ("plane", `String (plane_string plane));
      ("provenance", provenance_json provenance);
      ("requestId", `String request_id);
      ("runId", `String run_id) ]

let make_error ?context_digest ~code ~message ~coordinate ~rca_origin
    ~hazard_id () =
  { code; message; context_digest; coordinate; rca_origin; hazard_id }

let context_error coordinate message =
  Error
    (make_error ~code:Invalid_context ~message ~coordinate
       ~rca_origin:Ops_capability.Control ~hazard_id:"HZ-GATE-CONTEXT-01" ())

let coordinate_equal (left : Ops_capability.coordinate)
    (right : Ops_capability.coordinate) =
  left.level = right.level && left.phase = right.phase

let current_head_authority_digest =
  sha256 "hermes-task5-store-current-head-authority-v2"

let current_head_json ~run_id ~provenance ~head_sequence ~head_event_digest
    ~observed_at_ns ~current_at_ns ~expires_at_ns ~observed_monotonic_ns
    ~expires_monotonic_ns ~authority_digest =
  `Assoc
    [ ("authorityDigest", `String authority_digest);
      ("currentAtNs", `Intlit (Int64.to_string current_at_ns));
      ("expiresAtNs", `Intlit (Int64.to_string expires_at_ns));
      ("headEventDigest", `String head_event_digest);
      ("headSequence", `Intlit (Int64.to_string head_sequence));
      ("observedAtNs", `Intlit (Int64.to_string observed_at_ns));
      ("observedMonotonicNs", `Intlit (Int64.to_string observed_monotonic_ns));
      ("provenance", provenance_json provenance);
      ("runId", `String run_id);
      ("expiresMonotonicNs", `Intlit (Int64.to_string expires_monotonic_ns)) ]

let current_head_digest ~run_id ~provenance ~head_sequence ~head_event_digest
    ~observed_at_ns ~current_at_ns ~expires_at_ns ~observed_monotonic_ns
    ~expires_monotonic_ns ~authority_digest =
  current_head_json ~run_id ~provenance ~head_sequence ~head_event_digest
    ~observed_at_ns ~current_at_ns ~expires_at_ns ~observed_monotonic_ns
    ~expires_monotonic_ns ~authority_digest
  |> Run_model.canonical_string
  |> Result.map sha256

let head_coordinate : Ops_capability.coordinate =
  { level = Ops_capability.L0; phase = Ops_capability.Observe }

let make_current_head_receipt ~run_id ~(provenance : Run_model.provenance)
    ~head_sequence ~head_event_digest ~observed_at_ns ~current_at_ns
    ~expires_at_ns ~observed_monotonic_ns ~expires_monotonic_ns ~source =
  let invalid message = context_error head_coordinate message in
  match Run_model.validate_head ~run_id ~provenance with
  | Error message -> invalid message
  | Ok () when not provenance.source_clean ->
      invalid "source head must be clean for current-head admission"
  | Ok ()
    when not
      (valid_digest provenance.configuration_digest
       && valid_digest provenance.authority_digest
       && valid_digest provenance.executable_digest
       && valid_digest head_event_digest) ->
      invalid "current-head provenance digests must be canonical lowercase SHA-256"
  | Ok () when String.lowercase_ascii provenance.source_revision
               <> provenance.source_revision ->
      invalid "source revision must use canonical lowercase text"
  | Ok ()
    when Int64.compare head_sequence 0L < 0 ->
      invalid "current-head sequence must be nonnegative"
  | Ok ()
    when Int64.compare observed_at_ns 0L < 0
         || Int64.compare observed_at_ns current_at_ns > 0
         || Int64.compare current_at_ns expires_at_ns >= 0
         || Int64.compare observed_monotonic_ns 0L < 0
         || Int64.compare observed_monotonic_ns expires_monotonic_ns >= 0 ->
      invalid "current-head lifetime must satisfy 0 <= observed <= current < expires"
  | Ok () ->
      begin match
        current_head_digest ~run_id ~provenance ~head_sequence
          ~head_event_digest ~observed_at_ns ~current_at_ns ~expires_at_ns
          ~observed_monotonic_ns ~expires_monotonic_ns
          ~authority_digest:current_head_authority_digest
      with
      | Error message -> invalid message
      | Ok receipt_digest ->
          Ok
            { run_id; provenance; head_sequence; head_event_digest;
              observed_at_ns; current_at_ns; expires_at_ns;
              observed_monotonic_ns; expires_monotonic_ns;
              authority_digest = current_head_authority_digest; receipt_digest;
              source }
      end

let make_current_head_receipt_for_test ~run_id
    ~(provenance : Run_model.provenance) ~observed_at_ns
    ~current_at_ns ~expires_at_ns =
  make_current_head_receipt ~run_id ~provenance ~head_sequence:0L
    ~head_event_digest:(sha256 ("test-current-head:" ^ run_id))
    ~observed_at_ns ~current_at_ns ~expires_at_ns
    ~observed_monotonic_ns:observed_at_ns
    ~expires_monotonic_ns:expires_at_ns ~source:Test_only

let validate_current_head_structure coordinate (receipt : current_head_receipt) =
  if not
      (String.equal receipt.authority_digest current_head_authority_digest
       && valid_digest receipt.receipt_digest
       && valid_digest receipt.authority_digest
       && Int64.compare receipt.head_sequence 0L >= 0
       && valid_digest receipt.head_event_digest
       && receipt.provenance.source_clean
       && valid_digest receipt.provenance.configuration_digest
       && valid_digest receipt.provenance.authority_digest
       && valid_digest receipt.provenance.executable_digest
       && String.lowercase_ascii receipt.provenance.source_revision
          = receipt.provenance.source_revision
       && Int64.compare receipt.observed_at_ns 0L >= 0
       && Int64.compare receipt.observed_at_ns receipt.current_at_ns <= 0
       && Int64.compare receipt.current_at_ns receipt.expires_at_ns < 0
       && Int64.compare receipt.observed_monotonic_ns 0L >= 0
       && Int64.compare receipt.observed_monotonic_ns
            receipt.expires_monotonic_ns < 0)
  then context_error coordinate "current-head identity receipt is invalid or stale"
  else
    match
      current_head_digest ~run_id:receipt.run_id ~provenance:receipt.provenance
        ~head_sequence:receipt.head_sequence
        ~head_event_digest:receipt.head_event_digest
        ~observed_at_ns:receipt.observed_at_ns
        ~current_at_ns:receipt.current_at_ns ~expires_at_ns:receipt.expires_at_ns
        ~observed_monotonic_ns:receipt.observed_monotonic_ns
        ~expires_monotonic_ns:receipt.expires_monotonic_ns
        ~authority_digest:receipt.authority_digest
    with
    | Ok digest when String.equal digest receipt.receipt_digest -> Ok ()
    | Ok _ | Error _ -> context_error coordinate "current-head receipt digest differs"

let wall_now_ns () =
  try
    let seconds = Unix.gettimeofday () in
    if Float.is_finite seconds && Float.compare seconds 0.0 >= 0
       && Float.compare seconds
            (Int64.to_float Int64.max_int /. 1_000_000_000.) <= 0
    then Ok (Int64.of_float (seconds *. 1_000_000_000.))
    else Error "production wall clock is outside signed nanosecond range"
  with exn -> Error ("production wall clock failed: " ^ Printexc.to_string exn)

let validate_stream ~run_id events =
  let rec loop expected_sequence previous_digest provenance = function
    | [] ->
        begin match provenance with
        | None -> Error "the authoritative run stream is empty"
        | Some value -> Ok value
        end
    | (event : Run_model.event) :: rest ->
        if not (String.equal event.run_id run_id) then
          Error "the authoritative stream contains a foreign run id"
        else if not (Int64.equal event.sequence expected_sequence) then
          Error "the authoritative stream sequence is not contiguous"
        else if event.previous_digest <> previous_digest then
          Error "the authoritative stream digest chain is not contiguous"
        else if not (valid_digest event.digest)
                || not (String.equal event.digest (Run_model.digest event)) then
          Error "the authoritative stream contains a noncanonical event digest"
        else
          begin match provenance with
          | Some value when not (Run_model.equal_provenance value event.provenance) ->
              Error "the authoritative stream contains mixed provenance"
          | None | Some _ ->
              loop (Int64.succ expected_sequence) (Some event.digest)
                (Some event.provenance) rest
          end
  in
  loop Run_snapshot.first_sequence None None events

let observe_current_head ~store ~run_id ~lifetime_ns =
  let invalid message = context_error head_coordinate message in
  if not (nonempty run_id) then invalid "run_id must be nonempty"
  else if Int64.compare lifetime_ns 0L <= 0 then
    invalid "current-head lifetime must be positive"
  else
    match Run_event_store.events store ~run_id with
    | Error message -> invalid ("current-head store read failed: " ^ message)
    | Ok [] -> invalid "the authoritative run stream is empty"
    | Ok events ->
        begin match validate_stream ~run_id events, Run_snapshot.fold events with
        | Error message, _ | _, Error message -> invalid message
        | Ok provenance, Ok snapshot ->
            let dispatch_active =
              Run_snapshot.phase_state snapshot Run_model.Dispatch
              = Run_snapshot.Phase_active
            in
            let suite_active =
              Run_snapshot.phase_state snapshot Run_model.Suite_execution
              = Run_snapshot.Phase_active
            in
            if not (dispatch_active || suite_active) then
              invalid "current-head authority requires active Dispatch or Suite_execution"
            else
              let head = List.hd (List.rev events) in
              begin match wall_now_ns () with
              | Error message -> invalid message
              | Ok current_at_ns ->
                  let monotonic_at_ns =
                    try Ok (Mtime_clock.elapsed_ns ())
                    with exn ->
                      Error
                        ("production monotonic clock failed: "
                         ^ Printexc.to_string exn)
                  in
                  begin match monotonic_at_ns with
                  | Error message -> invalid message
                  | Ok monotonic_at_ns
                    when List.exists
                           (fun (event : Run_model.event) ->
                             Int64.compare event.occurred_at_ns current_at_ns > 0
                             || Int64.compare event.monotonic_at_ns monotonic_at_ns > 0)
                           events ->
                      invalid "the authoritative stream contains a future event"
                  | Ok monotonic_at_ns
                    when Int64.compare current_at_ns
                           (Int64.sub Int64.max_int lifetime_ns) > 0
                         || Int64.compare monotonic_at_ns
                              (Int64.sub Int64.max_int lifetime_ns) > 0 ->
                      invalid "current-head lifetime overflows signed nanoseconds"
                  | Ok monotonic_at_ns ->
                      make_current_head_receipt ~run_id ~provenance
                        ~head_sequence:head.sequence
                        ~head_event_digest:head.digest
                        ~observed_at_ns:current_at_ns ~current_at_ns
                        ~expires_at_ns:(Int64.add current_at_ns lifetime_ns)
                        ~observed_monotonic_ns:monotonic_at_ns
                        ~expires_monotonic_ns:
                          (Int64.add monotonic_at_ns lifetime_ns)
                        ~source:(Store_source store)
                  end
              end
        end

let validate_current_head_at ~wall_now_ns ~monotonic_now_ns coordinate
    (receipt : current_head_receipt) =
  let invalid message = context_error coordinate message in
  match validate_current_head_structure coordinate receipt with
  | Error _ as error -> error
  | Ok ()
    when Int64.compare wall_now_ns receipt.current_at_ns < 0
         || Int64.compare monotonic_now_ns receipt.observed_monotonic_ns < 0 ->
      invalid "current-head validation clock precedes its observation"
  | Ok ()
    when Int64.compare wall_now_ns receipt.expires_at_ns >= 0
         || Int64.compare monotonic_now_ns receipt.expires_monotonic_ns >= 0 ->
      invalid "current-head identity receipt is expired"
  | Ok () ->
      begin match receipt.source with
      | Test_only -> Ok ()
      | Store_source store ->
          begin match Run_event_store.events store ~run_id:receipt.run_id with
          | Error message -> invalid ("current-head store reread failed: " ^ message)
          | Ok events ->
              begin match validate_stream ~run_id:receipt.run_id events,
                          Run_snapshot.fold events, List.rev events with
              | Error message, _, _ | _, Error message, _ -> invalid message
              | _, _, [] -> invalid "the authoritative run stream is empty"
              | Ok provenance, Ok snapshot, head :: _ ->
                  let active =
                    Run_snapshot.phase_state snapshot Run_model.Dispatch
                      = Run_snapshot.Phase_active
                    || Run_snapshot.phase_state snapshot Run_model.Suite_execution
                         = Run_snapshot.Phase_active
                  in
                  if not active then
                    invalid "current-head authority is no longer in an active execution phase"
                  else if not (Run_model.equal_provenance provenance receipt.provenance)
                          || not (Int64.equal head.sequence receipt.head_sequence)
                          || not (String.equal head.digest receipt.head_event_digest)
                  then invalid "current-head store advanced or identity changed"
                  else if
                    List.exists
                      (fun (event : Run_model.event) ->
                        Int64.compare event.occurred_at_ns wall_now_ns > 0
                        || Int64.compare event.monotonic_at_ns monotonic_now_ns > 0)
                      events
                  then invalid "the authoritative stream contains a future event"
                  else Ok ()
              end
          end
      end

let validate_current_head coordinate receipt =
  match receipt.source with
  | Test_only -> validate_current_head_structure coordinate receipt
  | Store_source _ ->
      begin match wall_now_ns () with
      | Error message -> context_error coordinate message
      | Ok wall_now_ns ->
          begin
            try
              validate_current_head_at ~wall_now_ns
                ~monotonic_now_ns:(Mtime_clock.elapsed_ns ()) coordinate receipt
            with exn ->
              context_error coordinate
                ("production monotonic clock failed: " ^ Printexc.to_string exn)
          end
      end

let make_gate_context ~(current_head : current_head_receipt) ~request_id
    ~activity_id ~coordinate ~plane =
  let run_id = current_head.run_id in
  let provenance = current_head.provenance in
  match validate_current_head coordinate current_head with
  | Error _ as error -> error
  | Ok () when not (nonempty request_id) ->
      context_error coordinate "request_id must be nonempty"
  | Ok () when not (nonempty activity_id) ->
      context_error coordinate "activity_id must be nonempty"
  | Ok () ->
      begin match
        List.find_opt
          (fun (item : Ops_capability.declaration) ->
            String.equal item.id activity_id)
          Ops_capability.all
      with
      | None -> context_error coordinate ("unknown activity_id: " ^ activity_id)
      | Some item when item.kind <> Ops_capability.Activity ->
          context_error coordinate ("declaration is not an activity: " ^ activity_id)
      | Some item when item.plane <> plane ->
          context_error coordinate ("activity plane mismatch: " ^ activity_id)
      | Some item
        when not (List.exists (coordinate_equal coordinate) item.path) ->
          context_error coordinate
            ("coordinate is not in the authored activity path: " ^ activity_id)
      | Some _ ->
          let json =
            context_json ~run_id ~request_id ~activity_id ~provenance ~coordinate
              ~plane ~current_head_digest:current_head.receipt_digest
              ~current_at_ns:current_head.current_at_ns
          in
          begin match Run_model.canonical_string json with
          | Error message -> context_error coordinate message
          | Ok canonical ->
              Ok
                { run_id; request_id; activity_id; provenance; coordinate; plane;
                  current_head_digest = current_head.receipt_digest;
                  current_at_ns = current_head.current_at_ns;
                  context_digest = sha256 canonical; current_head }
          end
      end

let revalidate_gate_context_current_head_at ~wall_now_ns ~monotonic_now_ns
    ~store (context : gate_context) =
  let retained = context.current_head in
  let invalid message = context_error context.coordinate message in
  if not
      (String.equal context.run_id retained.run_id
       && Run_model.equal_provenance context.provenance retained.provenance
       && String.equal context.current_head_digest retained.receipt_digest
       && Int64.equal context.current_at_ns retained.current_at_ns)
  then invalid "gate context and retained current-head identity differ"
  else
    match retained.source with
    | Test_only ->
        invalid "a Test_only current head is not production store authority"
    | Store_source observed_store when observed_store != store ->
        invalid "current head belongs to a different event-store identity"
    | Store_source _ ->
        validate_current_head_at ~wall_now_ns ~monotonic_now_ns
          context.coordinate retained

let revalidate_gate_context_current_head ~store (context : gate_context) =
  match wall_now_ns () with
  | Error message -> context_error context.coordinate message
  | Ok wall_now_ns ->
      begin
        try
          revalidate_gate_context_current_head_at ~wall_now_ns
            ~monotonic_now_ns:(Mtime_clock.elapsed_ns ()) ~store context
        with exn ->
          context_error context.coordinate
            ("production monotonic clock failed: " ^ Printexc.to_string exn)
      end

let same_current_head_source left right =
  match left, right with
  | Test_only, Test_only -> true
  | Store_source left, Store_source right -> left == right
  | Test_only, Store_source _ | Store_source _, Test_only -> false

let same_current_head (left : current_head_receipt)
    (right : current_head_receipt) =
  String.equal left.run_id right.run_id
  && Run_model.equal_provenance left.provenance right.provenance
  && Int64.equal left.head_sequence right.head_sequence
  && String.equal left.head_event_digest right.head_event_digest
  && Int64.equal left.observed_at_ns right.observed_at_ns
  && Int64.equal left.current_at_ns right.current_at_ns
  && Int64.equal left.expires_at_ns right.expires_at_ns
  && Int64.equal left.observed_monotonic_ns right.observed_monotonic_ns
  && Int64.equal left.expires_monotonic_ns right.expires_monotonic_ns
  && String.equal left.authority_digest right.authority_digest
  && String.equal left.receipt_digest right.receipt_digest
  && same_current_head_source left.source right.source

let same_context (left : gate_context) (right : gate_context) =
  String.equal left.run_id right.run_id
  && String.equal left.request_id right.request_id
  && String.equal left.activity_id right.activity_id
  && Run_model.equal_provenance left.provenance right.provenance
  && coordinate_equal left.coordinate right.coordinate
  && left.plane = right.plane
  && String.equal left.current_head_digest right.current_head_digest
  && Int64.equal left.current_at_ns right.current_at_ns
  && String.equal left.context_digest right.context_digest
  && same_current_head left.current_head right.current_head

let authority_of_gate = function
  | Ruliad | Stan_model -> Analysis_only
  | Stpa_fmea | Rete_ul | Raven_matrix | Z3 | Assurance ->
      Load_bearing_dispatch_gate

let string_of_gate = function
  | Stpa_fmea -> "stpa-fmea" | Rete_ul -> "rete-ul"
  | Raven_matrix -> "raven-matrix" | Ruliad -> "ruliad"
  | Stan_model -> "stan-model" | Z3 -> "z3" | Assurance -> "assurance"

let string_of_authority = function
  | Load_bearing_dispatch_gate -> "load-bearing-dispatch-gate"
  | Analysis_only -> "analysis-only"

let rca_string = Ops_capability.string_of_rca_origin

let normalized_nonempty_set label values =
  if values = [] then Error (label ^ " must be nonempty")
  else if List.exists (fun value -> not (nonempty value)) values then
    Error (label ^ " contains an empty value")
  else Ok (List.sort_uniq String.compare values)

let normalize_outcome = function
  | Satisfied -> Ok Satisfied
  | Rejected reasons ->
      let* reasons = normalized_nonempty_set "rejection reasons" reasons in
      Ok (Rejected reasons)
  | Unavailable_observed reason when nonempty reason ->
      Ok (Unavailable_observed reason)
  | Unavailable_observed _ -> Error "unavailable reason must be nonempty"

let outcome_json = function
  | Satisfied -> `Assoc [ ("kind", `String "satisfied") ]
  | Rejected reasons ->
      `Assoc
        [ ("kind", `String "rejected");
          ("reasons", `List (List.map (fun item -> `String item) reasons)) ]
  | Unavailable_observed reason ->
      `Assoc
        [ ("kind", `String "unavailable-observed");
          ("reason", `String reason) ]

let receipt_json ~gate ~authority ~outcome ~context_digest ~coordinate
    ~rca_origin ~hazard_ids ~evidence_digest =
  `Assoc
    [ ("authority", `String (string_of_authority authority));
      ("contextDigest", `String context_digest);
      ("coordinate", coordinate_json coordinate);
      ("evidenceDigest", `String evidence_digest);
      ("gate", `String (string_of_gate gate));
      ("hazardIds", `List (List.map (fun item -> `String item) hazard_ids));
      ("outcome", outcome_json outcome);
      ("rcaOrigin", `String (rca_string rca_origin)) ]

let receipt_error (context : gate_context) code message =
  Error
    (make_error ~context_digest:context.context_digest ~code ~message
       ~coordinate:context.coordinate ~rca_origin:Ops_capability.Control
       ~hazard_id:"HZ-GATE-RECEIPT-01" ())

let mint_receipt ?evidence_digest (context : gate_context) ~gate ~outcome
    ~rca_origin ~hazard_ids =
  match normalized_nonempty_set "hazard_ids" hazard_ids with
  | Error message -> receipt_error context Invalid_receipt message
  | Ok hazard_ids ->
      begin match normalize_outcome outcome with
      | Error message -> receipt_error context Invalid_receipt message
      | Ok outcome ->
          let authority = authority_of_gate gate in
          let evidence_digest =
            Option.value evidence_digest ~default:context.context_digest
          in
          if not (valid_digest evidence_digest) then
            receipt_error context Invalid_receipt
              "evidence_digest must be a 64-character hexadecimal SHA-256 digest"
          else
            let json =
              receipt_json ~gate ~authority ~outcome
                ~context_digest:context.context_digest
                ~coordinate:context.coordinate ~rca_origin ~hazard_ids
                ~evidence_digest
            in
            begin match Run_model.canonical_string json with
            | Error message -> receipt_error context Invalid_receipt message
            | Ok canonical ->
              Ok
                { gate; authority; outcome;
                  context_digest = context.context_digest;
                  coordinate = context.coordinate; rca_origin; hazard_ids;
                  evidence_digest; receipt_digest = sha256 canonical }
            end
      end

let unavailable_receipt context ~gate ~reason ~hazard_id =
  mint_receipt context ~gate ~outcome:(Unavailable_observed reason)
    ~rca_origin:Ops_capability.Evidence ~hazard_ids:[ hazard_id ]

let rete_unavailable_receipt context ~reason =
  unavailable_receipt context ~gate:Rete_ul ~reason
    ~hazard_id:"HZ-INTELLIGENCE-RETE-UNAVAILABLE-01"

let raven_unavailable_receipt context ~reason =
  unavailable_receipt context ~gate:Raven_matrix ~reason
    ~hazard_id:"HZ-INTELLIGENCE-RAVEN-UNAVAILABLE-01"

let ruliad_unavailable_receipt context ~reason =
  unavailable_receipt context ~gate:Ruliad ~reason
    ~hazard_id:"HZ-ANALYSIS-RULIAD-UNAVAILABLE-01"

let stan_unavailable_receipt context ~reason =
  unavailable_receipt context ~gate:Stan_model ~reason
    ~hazard_id:"HZ-ANALYSIS-STAN-UNAVAILABLE-01"

let z3_unavailable_receipt context ~reason =
  unavailable_receipt context ~gate:Z3 ~reason
    ~hazard_id:"HZ-ANALYSIS-Z3-UNAVAILABLE-01"

let validate_receipt ~(context : gate_context) (receipt : receipt) =
  if not
      (String.equal receipt.context_digest context.context_digest
       && coordinate_equal receipt.coordinate context.coordinate)
  then receipt_error context Context_mismatch "receipt context differs"
  else if receipt.authority <> authority_of_gate receipt.gate then
    receipt_error context Invalid_receipt "receipt authority differs from gate"
  else if not (valid_digest receipt.evidence_digest) then
    receipt_error context Invalid_receipt "receipt evidence digest is invalid"
  else
    match normalized_nonempty_set "hazard_ids" receipt.hazard_ids with
    | Error message -> receipt_error context Invalid_receipt message
    | Ok hazard_ids ->
        begin match normalize_outcome receipt.outcome with
        | Error message -> receipt_error context Invalid_receipt message
        | Ok outcome ->
            let json =
              receipt_json ~gate:receipt.gate ~authority:receipt.authority
                ~outcome ~context_digest:receipt.context_digest
                ~coordinate:receipt.coordinate ~rca_origin:receipt.rca_origin
                ~hazard_ids ~evidence_digest:receipt.evidence_digest
            in
            begin match Run_model.canonical_string json with
            | Error message -> receipt_error context Invalid_receipt message
            | Ok canonical when String.equal (sha256 canonical) receipt.receipt_digest ->
                Ok ()
            | Ok _ ->
                receipt_error context Invalid_receipt "receipt digest differs"
            end
        end

let make_gate_error (context : gate_context) ~code ~message ~rca_origin
    ~hazard_id =
  make_error ~context_digest:context.context_digest ~code ~message
    ~coordinate:context.coordinate ~rca_origin ~hazard_id ()

let effectful_edges =
  List.filter
    (fun (edge : Run_topology.edge) ->
      match edge.kind with
      | Run_topology.Projection -> false
      | Run_topology.Admission | Run_topology.Execution
      | Run_topology.Evidence_flow | Run_topology.State_flow -> true)
    Run_topology.authority.edges

let effectful_edge_ids =
  List.map (fun (edge : Run_topology.edge) -> edge.stable_id) effectful_edges

let edge_suffix edge_id =
  String.map
    (function '.' | '_' -> '-' | character -> character)
    edge_id

let loss_id edge_id = "LOSS-OPS-" ^ edge_suffix edge_id
let hazard_id edge_id = "HZ-OPS-" ^ edge_suffix edge_id
let scenario_id edge_id = "CS-OPS-" ^ edge_suffix edge_id
let uca_id edge_id = "UCA-OPS-" ^ edge_suffix edge_id
let constraint_id edge_id = "SC-OPS-" ^ edge_suffix edge_id
let failure_mode_id edge_id = "FM-OPS-" ^ edge_suffix edge_id

let edge_kind_text (edge : Run_topology.edge) =
  match edge.kind with
  | Run_topology.Admission -> "admission"
  | Run_topology.Execution -> "execution"
  | Run_topology.Evidence_flow -> "evidence"
  | Run_topology.State_flow -> "state"
  | Run_topology.Projection -> "projection"

let requirement_and_verifier (edge : Run_topology.edge) =
  match edge.kind with
  | Run_topology.Admission | Run_topology.Execution ->
      ("REQ-OPS-EXECUTION-BRIDGE", "verify.operations.execution-bridge")
  | Run_topology.Evidence_flow | Run_topology.State_flow ->
      ("REQ-OPS-FPP-VALID", "verify.operations.fpp")
  | Run_topology.Projection ->
      ("REQ-OPS-UI-ISOLATION", "verify.operations.ui-isolation")

let generic_loss (edge : Run_topology.edge) =
  { stable_id = loss_id edge.stable_id; edge_id = edge.stable_id;
    description =
      Printf.sprintf "Loss of controlled %s transfer on %s"
        (edge_kind_text edge) edge.stable_id }

let generic_hazard (edge : Run_topology.edge) =
  { stable_id = hazard_id edge.stable_id; edge_id = edge.stable_id;
    description =
      Printf.sprintf "Unsafe or missing %s transfer on %s"
        (edge_kind_text edge) edge.stable_id;
    loss_ids = [ loss_id edge.stable_id ] }

let generic_scenario (edge : Run_topology.edge) =
  { stable_id = scenario_id edge.stable_id; edge_id = edge.stable_id;
    hazard_ids = [ hazard_id edge.stable_id ];
    description =
      Printf.sprintf
        "The source emits work or state without the destination proving the controlled %s handoff"
        (edge_kind_text edge) }

let generic_uca (edge : Run_topology.edge) =
  { stable_id = uca_id edge.stable_id; edge_id = edge.stable_id;
    kind = Not_provided; hazard_ids = [ hazard_id edge.stable_id ];
    causal_scenario_ids = [ scenario_id edge.stable_id ];
    constraint_ids = [ constraint_id edge.stable_id ] }

let generic_constraint (edge : Run_topology.edge) =
  let _, verifier_id = requirement_and_verifier edge in
  { stable_id = constraint_id edge.stable_id; edge_id = edge.stable_id;
    uca_ids = [ uca_id edge.stable_id ];
    statement =
      Printf.sprintf "%s must complete only through its declared typed ports"
        edge.stable_id;
    control =
      Printf.sprintf "Validate %s and its endpoint ports against Run_topology.authority"
        edge.stable_id;
    owner = edge.from_component ^ "->" ^ edge.to_component;
    verifier_id }

let generic_failure_mode (edge : Run_topology.edge) =
  let requirement_id, verifier_id = requirement_and_verifier edge in
  { stable_id = failure_mode_id edge.stable_id; edge_id = edge.stable_id;
    requirement_id; hazard_ids = [ hazard_id edge.stable_id ];
    failure_effect = "The declared destination cannot establish a complete controlled handoff";
    cause = "The source omits, mistimes, or bypasses the declared typed edge";
    control_ids = [ constraint_id edge.stable_id ];
    owner = edge.from_component ^ "->" ^ edge.to_component;
    initial_risk = { severity = 1; occurrence = 1; detectability = 1 };
    residual_risk = { severity = 1; occurrence = 1; detectability = 1 };
    verifier_id; control_evidence = None; acceptance = None }

let generic_path (edge : Run_topology.edge) =
  { edge_id = edge.stable_id; loss_ids = [ loss_id edge.stable_id ];
    hazard_ids = [ hazard_id edge.stable_id ];
    uca_ids = [ uca_id edge.stable_id ];
    causal_scenario_ids = [ scenario_id edge.stable_id ];
    constraint_ids = [ constraint_id edge.stable_id ];
    failure_mode_ids = [ failure_mode_id edge.stable_id ] }

let sqlite_edge_id = "edge.evidence.worker-store"
let sqlite_loss_id = "LOSS-SQL-EVIDENCE-01"
let sqlite_scenario_id = "CS-SQL-FIN-01"
let sqlite_uca_id = "UCA-SQL-FIN-01"
let sqlite_constraint_id = "SC-SQL-FIN-01"
let sqlite_failure_mode_id = "FM-SQL-FIN-01"

let add_sqlite_path (path : path_analysis) =
  if not (String.equal path.edge_id sqlite_edge_id) then path
  else
    { path with
      loss_ids = sqlite_loss_id :: path.loss_ids;
      hazard_ids = "HZ-SQL-FIN-01" :: path.hazard_ids;
      uca_ids = sqlite_uca_id :: path.uca_ids;
      causal_scenario_ids = sqlite_scenario_id :: path.causal_scenario_ids;
      constraint_ids = sqlite_constraint_id :: path.constraint_ids;
      failure_mode_ids = sqlite_failure_mode_id :: path.failure_mode_ids }

let model =
  { topology_digest = Run_topology.source_digest;
    evaluated_at_ns = 1_000L;
    residual_rpn_threshold = 100;
    losses =
      { stable_id = sqlite_loss_id; edge_id = sqlite_edge_id;
        description = "Loss of durable run evidence through native SQLite termination" }
      :: List.map generic_loss effectful_edges;
    hazards =
      { stable_id = "HZ-SQL-FIN-01"; edge_id = sqlite_edge_id;
        description =
          "A statement wrapper becomes collectible during explicit native finalization";
        loss_ids = [ sqlite_loss_id ] }
      :: List.map generic_hazard effectful_edges;
    causal_scenarios =
      { stable_id = sqlite_scenario_id; edge_id = sqlite_edge_id;
        hazard_ids = [ "HZ-SQL-FIN-01" ];
        description =
          "A parallel major collection reaches a live wrapper while sqlite3_finalize has released the OCaml runtime" }
      :: List.map generic_scenario effectful_edges;
    unsafe_control_actions =
      { stable_id = sqlite_uca_id; edge_id = sqlite_edge_id;
        kind = Provided_unsafe; hazard_ids = [ "HZ-SQL-FIN-01" ];
        causal_scenario_ids = [ sqlite_scenario_id ];
        constraint_ids = [ sqlite_constraint_id ] }
      :: List.map generic_uca effectful_edges;
    constraints =
      { stable_id = sqlite_constraint_id; edge_id = sqlite_edge_id;
        uca_ids = [ sqlite_uca_id ];
        statement =
          "Every explicit SQLite finalization keeps the OCaml statement reachable across the foreign call";
        control =
          "Run_event_store finalization observes Sqlite3.finalize and then Gc.keep_alive on the same statement";
        owner = "runEventStore"; verifier_id = "verify.operations.fpp" }
      :: List.map generic_constraint effectful_edges;
    failure_modes =
      { stable_id = sqlite_failure_mode_id; edge_id = sqlite_edge_id;
        requirement_id = "HZ-SQL-FIN-01";
        hazard_ids = [ "HZ-SQL-FIN-01" ];
        failure_effect = "Native process termination loses durable run evidence";
        cause = "A second finalizer enters sqlite3_finalize for the same wrapper";
        control_ids = [ sqlite_constraint_id ]; owner = "runEventStore";
        initial_risk = { severity = 10; occurrence = 4; detectability = 4 };
        residual_risk = { severity = 10; occurrence = 4; detectability = 4 };
        verifier_id = "verify.operations.fpp"; control_evidence = None;
        acceptance = None }
      :: List.map generic_failure_mode effectful_edges;
    paths = List.map (fun edge -> add_sqlite_path (generic_path edge)) effectful_edges }

let rank value = value >= 1 && value <= 10

let rpn risk =
  if rank risk.severity && rank risk.occurrence && rank risk.detectability then
    Ok (risk.severity * risk.occurrence * risk.detectability)
  else Error "FMEA severity, occurrence, and detectability must each be in 1..10"

let sorted_strings values = List.sort_uniq String.compare values
let string_list_json values =
  `List (List.map (fun value -> `String value) (sorted_strings values))

let risk_json (risk : risk) =
  `Assoc
    [ ("detectability", `Int risk.detectability);
      ("occurrence", `Int risk.occurrence);
      ("severity", `Int risk.severity) ]

let risk_digest (risk : risk) = risk_json risk |> Yojson.Safe.to_string |> sha256

let residual_policy_authority_digest =
  sha256 "hermes-task6-residual-policy-authority-v1"

let control_evidence_json (evidence : control_evidence) =
  `Assoc
    [ ("contextDigest", `String evidence.context_digest);
      ("controlIds", string_list_json evidence.control_ids);
      ("currentHeadDigest", `String evidence.current_head_digest);
      ("failureModeId", `String evidence.failure_mode_id);
      ("modelAuthorityDigest", `String evidence.model_authority_digest);
      ("observedAtNs", `Intlit (Int64.to_string evidence.observed_at_ns));
      ("originalRiskDigest", `String evidence.original_risk_digest);
      ("residualRiskDigest", `String evidence.residual_risk_digest);
      ("verifierId", `String evidence.verifier_id) ]

let control_evidence_digest_of (evidence : control_evidence) =
  control_evidence_json evidence |> Yojson.Safe.to_string |> sha256

let acceptance_json (acceptance : residual_acceptance) =
  `Assoc
    [ ("acceptedAtNs", `Intlit (Int64.to_string acceptance.accepted_at_ns));
      ("authorityDigest", `String acceptance.authority_digest);
      ("contextDigest", `String acceptance.context_digest);
      ("currentHeadDigest", `String acceptance.current_head_digest);
      ("expiresAtNs", `Intlit (Int64.to_string acceptance.expires_at_ns));
      ("failureModeId", `String acceptance.failure_mode_id);
      ("modelAuthorityDigest", `String acceptance.model_authority_digest);
      ("owner", `String acceptance.owner);
      ("originalRiskDigest", `String acceptance.original_risk_digest);
      ("rationale", `String acceptance.rationale);
      ("residualRiskDigest", `String acceptance.residual_risk_digest);
      ("requirementId", `String acceptance.requirement_id) ]

let acceptance_digest_of (acceptance : residual_acceptance) =
  acceptance_json acceptance |> Yojson.Safe.to_string |> sha256

let uca_kind_string = function
  | Not_provided -> "not-provided"
  | Provided_unsafe -> "provided-unsafe"
  | Wrong_timing -> "wrong-timing"
  | Applied_too_long -> "applied-too-long"

let sort_by_id get values =
  List.sort (fun left right -> String.compare (get left) (get right)) values

let model_json (value : model) =
  `Assoc
    [ ("causalScenarios",
       `List
         (value.causal_scenarios
          |> sort_by_id (fun (item : causal_scenario) -> item.stable_id)
          |> List.map (fun (item : causal_scenario) ->
                 `Assoc
                   [ ("description", `String item.description);
                     ("edgeId", `String item.edge_id);
                     ("hazardIds", string_list_json item.hazard_ids);
                     ("stableId", `String item.stable_id) ])));
      ("constraints",
       `List
         (value.constraints
          |> sort_by_id (fun (item : safety_constraint) -> item.stable_id)
          |> List.map (fun (item : safety_constraint) ->
                 `Assoc
                   [ ("control", `String item.control);
                     ("edgeId", `String item.edge_id);
                     ("owner", `String item.owner);
                     ("stableId", `String item.stable_id);
                     ("statement", `String item.statement);
                     ("ucaIds", string_list_json item.uca_ids);
                     ("verifierId", `String item.verifier_id) ])));
      ("evaluatedAtNs", `Intlit (Int64.to_string value.evaluated_at_ns));
      ("failureModes",
       `List
         (value.failure_modes
          |> sort_by_id (fun (item : failure_mode) -> item.stable_id)
          |> List.map (fun (item : failure_mode) ->
                 `Assoc
                   [ ("acceptance",
                      match item.acceptance with
                      | None -> `Null
                      | Some acceptance ->
                          `Assoc
                            [ ("digest", `String acceptance.acceptance_digest);
                              ("value", acceptance_json acceptance) ]);
                     ("cause", `String item.cause);
                     ("controlEvidence",
                      match item.control_evidence with
                      | None -> `Null
                      | Some evidence ->
                          `Assoc
                            [ ("digest", `String evidence.evidence_digest);
                              ("value", control_evidence_json evidence) ]);
                     ("controlIds", string_list_json item.control_ids);
                     ("edgeId", `String item.edge_id);
                     ("failureEffect", `String item.failure_effect);
                     ("hazardIds", string_list_json item.hazard_ids);
                     ("initialRisk", risk_json item.initial_risk);
                     ("owner", `String item.owner);
                     ("requirementId", `String item.requirement_id);
                     ("residualRisk", risk_json item.residual_risk);
                     ("stableId", `String item.stable_id);
                     ("verifierId", `String item.verifier_id) ])));
      ("hazards",
       `List
         (value.hazards
          |> sort_by_id (fun (item : hazard) -> item.stable_id)
          |> List.map (fun (item : hazard) ->
                 `Assoc
                   [ ("description", `String item.description);
                     ("edgeId", `String item.edge_id);
                     ("lossIds", string_list_json item.loss_ids);
                     ("stableId", `String item.stable_id) ])));
      ("losses",
       `List
         (value.losses
          |> sort_by_id (fun (item : loss) -> item.stable_id)
          |> List.map (fun (item : loss) ->
                 `Assoc
                   [ ("description", `String item.description);
                     ("edgeId", `String item.edge_id);
                     ("stableId", `String item.stable_id) ])));
      ("paths",
       `List
         (value.paths
          |> sort_by_id (fun (item : path_analysis) -> item.edge_id)
          |> List.map (fun (item : path_analysis) ->
                 `Assoc
                   [ ("causalScenarioIds", string_list_json item.causal_scenario_ids);
                     ("constraintIds", string_list_json item.constraint_ids);
                     ("edgeId", `String item.edge_id);
                     ("failureModeIds", string_list_json item.failure_mode_ids);
                     ("hazardIds", string_list_json item.hazard_ids);
                     ("lossIds", string_list_json item.loss_ids);
                     ("ucaIds", string_list_json item.uca_ids) ])));
      ("residualRpnThreshold", `Int value.residual_rpn_threshold);
      ("topologyDigest", `String value.topology_digest);
      ("unsafeControlActions",
       `List
         (value.unsafe_control_actions
          |> sort_by_id (fun (item : unsafe_control_action) -> item.stable_id)
          |> List.map (fun (item : unsafe_control_action) ->
                 `Assoc
                   [ ("causalScenarioIds", string_list_json item.causal_scenario_ids);
                     ("constraintIds", string_list_json item.constraint_ids);
                     ("edgeId", `String item.edge_id);
                     ("hazardIds", string_list_json item.hazard_ids);
                     ("kind", `String (uca_kind_string item.kind));
                     ("stableId", `String item.stable_id) ]))) ]

let model_digest value = model_json value |> Yojson.Safe.to_string |> sha256

let model_authority_digest value =
  let authority_model =
    { value with evaluated_at_ns = 0L;
      failure_modes =
        List.map
          (fun (item : failure_mode) ->
            { item with residual_risk = item.initial_risk;
              control_evidence = None; acceptance = None })
          value.failure_modes }
  in
  model_json authority_model |> Yojson.Safe.to_string |> sha256

let validate_control_structure (value : model) =
  let gaps = ref [] in
  let add message = gaps := message :: !gaps in
  let check_registry label get_id values =
    if values = [] then add (label ^ " registry is empty");
    let ids = List.map get_id values in
    if List.exists (fun id -> not (nonempty id)) ids then
      add (label ^ " contains an empty stable id");
    if List.length ids <> List.length (sorted_strings ids) then
      add (label ^ " stable ids are not unique")
  in
  let check_refs owner label references available =
    if references = [] then add (owner ^ " has no " ^ label);
    if List.length references <> List.length (sorted_strings references) then
      add (owner ^ " has duplicate " ^ label);
    List.iter
      (fun id ->
        if not (List.mem id available) then
          add (owner ^ " references unknown " ^ label ^ ": " ^ id))
      references
  in
  let check_local_refs owner edge_id label references values get_id get_edge =
    List.iter
      (fun reference ->
        match List.find_opt (fun item -> String.equal (get_id item) reference) values with
        | None -> ()
        | Some item when String.equal (get_edge item) edge_id -> ()
        | Some _ ->
            add
              (Printf.sprintf "%s references cross-edge %s: %s"
                 owner label reference))
      references
  in
  if not (String.equal value.topology_digest Run_topology.source_digest) then
    add "safety topology digest differs from Run_topology authority";
  if Int64.compare value.evaluated_at_ns 0L < 0 then
    add "safety evaluated_at_ns must be nonnegative";
  if value.residual_rpn_threshold < 1 || value.residual_rpn_threshold > 1_000 then
    add "residual RPN threshold must be in 1..1000";
  check_registry "loss" (fun (item : loss) -> item.stable_id) value.losses;
  check_registry "hazard" (fun (item : hazard) -> item.stable_id) value.hazards;
  check_registry "causal scenario"
    (fun (item : causal_scenario) -> item.stable_id) value.causal_scenarios;
  check_registry "unsafe control action"
    (fun (item : unsafe_control_action) -> item.stable_id)
    value.unsafe_control_actions;
  check_registry "constraint"
    (fun (item : safety_constraint) -> item.stable_id) value.constraints;
  check_registry "failure mode"
    (fun (item : failure_mode) -> item.stable_id) value.failure_modes;
  check_registry "path" (fun (item : path_analysis) -> item.edge_id) value.paths;
  let loss_ids = List.map (fun (item : loss) -> item.stable_id) value.losses in
  let hazard_ids = List.map (fun (item : hazard) -> item.stable_id) value.hazards in
  let scenario_ids =
    List.map (fun (item : causal_scenario) -> item.stable_id)
      value.causal_scenarios
  in
  let uca_ids =
    List.map (fun (item : unsafe_control_action) -> item.stable_id)
      value.unsafe_control_actions
  in
  let constraint_ids =
    List.map (fun (item : safety_constraint) -> item.stable_id) value.constraints
  in
  let failure_ids =
    List.map (fun (item : failure_mode) -> item.stable_id) value.failure_modes
  in
  let verifier_ids =
    List.map (fun (item : Run_topology.verifier) -> item.stable_id)
      Run_topology.authority.verifiers
  in
  let requirement_ids =
    List.map (fun (item : Run_topology.requirement) -> item.stable_id)
      Run_topology.authority.requirements
  in
  let path_edge_ids = List.map (fun (item : path_analysis) -> item.edge_id) value.paths in
  if List.sort String.compare path_edge_ids
     <> List.sort String.compare effectful_edge_ids
  then add "safety path denominator differs from effectful topology edges";
  List.iter
    (fun (item : loss) ->
      if not (List.mem item.edge_id effectful_edge_ids) then
        add (item.stable_id ^ " names a non-effectful edge");
      if not (nonempty item.description) then
        add (item.stable_id ^ " has an empty loss description"))
    value.losses;
  List.iter
    (fun (item : hazard) ->
      if not (List.mem item.edge_id effectful_edge_ids) then
        add (item.stable_id ^ " names a non-effectful edge");
      if not (nonempty item.description) then
        add (item.stable_id ^ " has an empty hazard description");
      check_refs item.stable_id "loss" item.loss_ids loss_ids;
      check_local_refs item.stable_id item.edge_id "loss" item.loss_ids
        value.losses (fun (linked : loss) -> linked.stable_id)
        (fun (linked : loss) -> linked.edge_id))
    value.hazards;
  List.iter
    (fun (item : causal_scenario) ->
      if not (List.mem item.edge_id effectful_edge_ids) then
        add (item.stable_id ^ " names a non-effectful edge");
      if not (nonempty item.description) then
        add (item.stable_id ^ " has an empty causal scenario");
      check_refs item.stable_id "hazard" item.hazard_ids hazard_ids;
      check_local_refs item.stable_id item.edge_id "hazard" item.hazard_ids
        value.hazards (fun (linked : hazard) -> linked.stable_id)
        (fun (linked : hazard) -> linked.edge_id))
    value.causal_scenarios;
  List.iter
    (fun (item : unsafe_control_action) ->
      if not (List.mem item.edge_id effectful_edge_ids) then
        add (item.stable_id ^ " names a non-effectful edge");
      check_refs item.stable_id "hazard" item.hazard_ids hazard_ids;
      check_refs item.stable_id "causal scenario" item.causal_scenario_ids
        scenario_ids;
      check_refs item.stable_id "constraint" item.constraint_ids constraint_ids;
      check_local_refs item.stable_id item.edge_id "hazard" item.hazard_ids
        value.hazards (fun (linked : hazard) -> linked.stable_id)
        (fun (linked : hazard) -> linked.edge_id);
      check_local_refs item.stable_id item.edge_id "causal scenario"
        item.causal_scenario_ids value.causal_scenarios
        (fun (linked : causal_scenario) -> linked.stable_id)
        (fun (linked : causal_scenario) -> linked.edge_id);
      check_local_refs item.stable_id item.edge_id "constraint"
        item.constraint_ids value.constraints
        (fun (linked : safety_constraint) -> linked.stable_id)
        (fun (linked : safety_constraint) -> linked.edge_id))
    value.unsafe_control_actions;
  List.iter
    (fun (item : safety_constraint) ->
      if not (List.mem item.edge_id effectful_edge_ids) then
        add (item.stable_id ^ " names a non-effectful edge");
      check_refs item.stable_id "UCA" item.uca_ids uca_ids;
      check_local_refs item.stable_id item.edge_id "UCA" item.uca_ids
        value.unsafe_control_actions
        (fun (linked : unsafe_control_action) -> linked.stable_id)
        (fun (linked : unsafe_control_action) -> linked.edge_id);
      if not (nonempty item.statement && nonempty item.control
              && nonempty item.owner)
      then add (item.stable_id ^ " lacks statement, control, or owner");
      if not (List.mem item.verifier_id verifier_ids) then
        add (item.stable_id ^ " names an unknown verifier"))
    value.constraints;
  List.iter
    (fun (item : failure_mode) ->
      if not (List.mem item.edge_id effectful_edge_ids) then
        add (item.stable_id ^ " names a non-effectful edge");
      check_refs item.stable_id "hazard" item.hazard_ids hazard_ids;
      check_refs item.stable_id "control" item.control_ids constraint_ids;
      check_local_refs item.stable_id item.edge_id "hazard" item.hazard_ids
        value.hazards (fun (linked : hazard) -> linked.stable_id)
        (fun (linked : hazard) -> linked.edge_id);
      check_local_refs item.stable_id item.edge_id "control" item.control_ids
        value.constraints
        (fun (linked : safety_constraint) -> linked.stable_id)
        (fun (linked : safety_constraint) -> linked.edge_id);
      if not (nonempty item.failure_effect && nonempty item.cause
              && nonempty item.owner)
      then add (item.stable_id ^ " lacks effect, cause, or owner");
      if not (List.mem item.verifier_id verifier_ids) then
        add (item.stable_id ^ " names an unknown verifier");
      if not (List.mem item.requirement_id requirement_ids) then
        add (item.stable_id ^ " names an unknown requirement");
      if Result.is_error (rpn item.initial_risk)
         || Result.is_error (rpn item.residual_risk)
      then add (item.stable_id ^ " has an invalid FMEA risk rank");
      let original_risk_digest = risk_digest item.initial_risk in
      let residual_risk_digest = risk_digest item.residual_risk in
      let authority_digest = model_authority_digest value in
      begin match item.control_evidence with
      | None when not (String.equal original_risk_digest residual_risk_digest) ->
          add (item.stable_id ^ " lowers residual risk without typed control evidence")
      | None -> ()
      | Some evidence ->
          if not
              (String.equal evidence.failure_mode_id item.stable_id
               && evidence.control_ids = sorted_strings item.control_ids
               && String.equal evidence.verifier_id item.verifier_id
               && String.equal evidence.original_risk_digest original_risk_digest
               && String.equal evidence.residual_risk_digest residual_risk_digest
               && String.equal evidence.model_authority_digest authority_digest
               && valid_digest evidence.context_digest
               && valid_digest evidence.current_head_digest
               && valid_digest evidence.evidence_digest
               && Int64.compare evidence.observed_at_ns 0L >= 0
               && String.equal evidence.evidence_digest
                    (control_evidence_digest_of evidence))
          then add (item.stable_id ^ " control evidence binding is invalid")
      end;
      match item.acceptance with
      | None -> ()
      | Some acceptance ->
          if not
              (String.equal acceptance.failure_mode_id item.stable_id
               && String.equal acceptance.requirement_id item.requirement_id)
          then add (item.stable_id ^ " acceptance scope differs");
          if not (nonempty acceptance.owner && nonempty acceptance.rationale) then
            add (item.stable_id ^ " acceptance lacks owner or rationale");
          if not
              (valid_digest acceptance.context_digest
               && valid_digest acceptance.current_head_digest
               && valid_digest acceptance.authority_digest
               && String.equal acceptance.authority_digest
                    residual_policy_authority_digest
               && String.equal acceptance.original_risk_digest original_risk_digest
               && String.equal acceptance.residual_risk_digest residual_risk_digest
               && String.equal acceptance.model_authority_digest authority_digest
               && String.equal acceptance.acceptance_digest
                    (acceptance_digest_of acceptance))
          then add (item.stable_id ^ " acceptance digest or binding is invalid");
          if Int64.compare acceptance.accepted_at_ns 0L < 0
             || Int64.compare acceptance.expires_at_ns
                  acceptance.accepted_at_ns <= 0
          then add (item.stable_id ^ " acceptance lifetime is invalid"))
    value.failure_modes;
  List.iter
    (fun (item : path_analysis) ->
      check_refs item.edge_id "loss" item.loss_ids loss_ids;
      check_refs item.edge_id "hazard" item.hazard_ids hazard_ids;
      check_refs item.edge_id "UCA" item.uca_ids uca_ids;
      check_refs item.edge_id "causal scenario" item.causal_scenario_ids
        scenario_ids;
      check_refs item.edge_id "constraint" item.constraint_ids constraint_ids;
      check_refs item.edge_id "failure mode" item.failure_mode_ids failure_ids;
      check_local_refs item.edge_id item.edge_id "loss" item.loss_ids
        value.losses (fun (linked : loss) -> linked.stable_id)
        (fun (linked : loss) -> linked.edge_id);
      check_local_refs item.edge_id item.edge_id "hazard" item.hazard_ids
        value.hazards (fun (linked : hazard) -> linked.stable_id)
        (fun (linked : hazard) -> linked.edge_id);
      check_local_refs item.edge_id item.edge_id "UCA" item.uca_ids
        value.unsafe_control_actions
        (fun (linked : unsafe_control_action) -> linked.stable_id)
        (fun (linked : unsafe_control_action) -> linked.edge_id);
      check_local_refs item.edge_id item.edge_id "causal scenario"
        item.causal_scenario_ids value.causal_scenarios
        (fun (linked : causal_scenario) -> linked.stable_id)
        (fun (linked : causal_scenario) -> linked.edge_id);
      check_local_refs item.edge_id item.edge_id "constraint"
        item.constraint_ids value.constraints
        (fun (linked : safety_constraint) -> linked.stable_id)
        (fun (linked : safety_constraint) -> linked.edge_id);
      check_local_refs item.edge_id item.edge_id "failure mode"
        item.failure_mode_ids value.failure_modes
        (fun (linked : failure_mode) -> linked.stable_id)
        (fun (linked : failure_mode) -> linked.edge_id))
    value.paths;
  let covered selector = List.concat_map selector value.paths |> sorted_strings in
  let total label declared observed =
    if sorted_strings declared <> observed then
      add (label ^ " registry is not exactly covered by safety paths")
  in
  total "loss" loss_ids
    (covered (fun (item : path_analysis) -> item.loss_ids));
  total "hazard" hazard_ids
    (covered (fun (item : path_analysis) -> item.hazard_ids));
  total "UCA" uca_ids
    (covered (fun (item : path_analysis) -> item.uca_ids));
  total "causal scenario" scenario_ids
    (covered (fun (item : path_analysis) -> item.causal_scenario_ids));
  total "constraint" constraint_ids
    (covered (fun (item : path_analysis) -> item.constraint_ids));
  total "failure mode" failure_ids
    (covered (fun (item : path_analysis) -> item.failure_mode_ids));
  List.iter
    (fun required ->
      if not (List.mem required hazard_ids || List.mem required uca_ids
              || List.mem required scenario_ids || List.mem required constraint_ids
              || List.mem required failure_ids)
      then add ("required SQLite safety element is missing: " ^ required))
    [ "HZ-SQL-FIN-01"; sqlite_uca_id; sqlite_scenario_id;
      sqlite_constraint_id; sqlite_failure_mode_id ];
  List.rev !gaps

let invalid_model context message =
  Error
    (make_gate_error context ~code:Invalid_model ~message
       ~rca_origin:Ops_capability.Control ~hazard_id:"HZ-SAFETY-MODEL-01")

let make_control_evidence_at_for_test context (value : model) ~failure_mode_id
    ~residual_risk ~observed_at_ns =
  match
    List.find_opt
      (fun (item : failure_mode) -> String.equal item.stable_id failure_mode_id)
      value.failure_modes
  with
  | None -> invalid_model context ("unknown failure_mode_id: " ^ failure_mode_id)
  | Some item ->
      begin match rpn item.initial_risk, rpn residual_risk with
      | Ok initial, Ok residual when residual <= initial ->
          let provisional =
            { failure_mode_id; control_ids = sorted_strings item.control_ids;
              verifier_id = item.verifier_id;
              original_risk_digest = risk_digest item.initial_risk;
              residual_risk_digest = risk_digest residual_risk;
              model_authority_digest = model_authority_digest value;
              context_digest = context.context_digest;
              current_head_digest = context.current_head_digest;
              observed_at_ns; evidence_digest = "" }
          in
          Ok
            { provisional with
              evidence_digest = control_evidence_digest_of provisional }
      | Ok _, Ok _ ->
          invalid_model context "control evidence cannot increase residual risk"
      | Error message, _ | _, Error message -> invalid_model context message
      end

let make_control_evidence_for_test context value ~failure_mode_id
    ~residual_risk =
  make_control_evidence_at_for_test context value ~failure_mode_id
    ~residual_risk ~observed_at_ns:context.current_at_ns

let make_residual_acceptance_for_test context (value : model) ~failure_mode_id
    ~owner ~rationale ~expires_at_ns =
  let invalid message =
    invalid_model context message
  in
  match
    List.find_opt
      (fun (item : failure_mode) -> String.equal item.stable_id failure_mode_id)
      value.failure_modes
  with
  | None -> invalid ("unknown failure_mode_id: " ^ failure_mode_id)
  | Some _ when not (nonempty owner && nonempty rationale) ->
      invalid "acceptance owner and rationale must be nonempty"
  | Some _
    when Int64.compare expires_at_ns context.current_at_ns <= 0 ->
      invalid "acceptance lifetime must be positive and increasing"
  | Some item ->
      let provisional =
        { failure_mode_id; requirement_id = item.requirement_id; owner; rationale;
          context_digest = context.context_digest;
          current_head_digest = context.current_head_digest;
          authority_digest = residual_policy_authority_digest;
          original_risk_digest = risk_digest item.initial_risk;
          residual_risk_digest = risk_digest item.residual_risk;
          model_authority_digest = model_authority_digest value;
          accepted_at_ns = context.current_at_ns; expires_at_ns;
          acceptance_digest = "" }
      in
      Ok
        { provisional with
          acceptance_digest = acceptance_digest_of provisional }

let current_acceptance (context : gate_context) (value : model)
    (item : failure_mode) =
  match item.acceptance with
  | None -> false
  | Some acceptance ->
      String.equal acceptance.failure_mode_id item.stable_id
      && String.equal acceptance.requirement_id item.requirement_id
      && String.equal acceptance.context_digest context.context_digest
      && String.equal acceptance.current_head_digest context.current_head_digest
      && String.equal acceptance.authority_digest residual_policy_authority_digest
      && String.equal acceptance.original_risk_digest (risk_digest item.initial_risk)
      && String.equal acceptance.residual_risk_digest (risk_digest item.residual_risk)
      && String.equal acceptance.model_authority_digest
           (model_authority_digest value)
      && String.equal acceptance.acceptance_digest
           (acceptance_digest_of acceptance)
      && Int64.compare acceptance.accepted_at_ns context.current_at_ns <= 0
      && Int64.compare context.current_at_ns acceptance.expires_at_ns < 0

let current_control_evidence (context : gate_context) (item : failure_mode) =
  match item.control_evidence with
  | None -> String.equal (risk_digest item.initial_risk) (risk_digest item.residual_risk)
  | Some evidence ->
      String.equal evidence.context_digest context.context_digest
      && String.equal evidence.current_head_digest context.current_head_digest
      && Int64.equal evidence.observed_at_ns context.current_at_ns

let evaluate context (value : model) =
  match validate_control_structure value with
  | _ :: _ as gaps ->
      Error
        (make_gate_error context ~code:Invalid_model
           ~message:(String.concat "; " gaps)
           ~rca_origin:Ops_capability.Control ~hazard_id:"HZ-SAFETY-MODEL-01")
  | [] ->
      let stale_controls =
        value.failure_modes
        |> List.filter (fun item -> not (current_control_evidence context item))
        |> List.map (fun item ->
               item.stable_id
               ^ ": control evidence is foreign, stale, or absent for risk lowering")
      in
      if stale_controls <> [] then
        invalid_model context (String.concat "; " stale_controls)
      else
      let reasons =
        List.filter_map
          (fun (item : failure_mode) ->
            match rpn item.residual_risk with
            | Error message -> Some (item.stable_id ^ ": " ^ message)
            | Ok residual
              when residual >= value.residual_rpn_threshold
                   && not (current_acceptance context value item) ->
                Some
                  (Printf.sprintf
                     "%s: residual RPN %d requires current scoped acceptance"
                     item.stable_id residual)
            | Ok _ -> None)
          value.failure_modes
      in
      let decision, outcome =
        match reasons with
        | [] -> (Admit, Satisfied)
        | _ -> (Block reasons, Rejected reasons)
      in
      let hazard_ids =
        List.map (fun (item : hazard) -> item.stable_id) value.hazards
      in
      let evidence_digest = model_digest value in
      let* receipt =
        mint_receipt ~evidence_digest context ~gate:Stpa_fmea ~outcome
          ~rca_origin:Ops_capability.Control ~hazard_ids
      in
      Ok (decision, receipt)

module Assurance_evaluator = struct
  let required_gates =
    [ Stpa_fmea; Rete_ul; Raven_matrix; Ruliad; Stan_model; Z3 ]

  let all_input_gates = Assurance :: required_gates

  let error context code message =
    make_gate_error context ~code ~message ~rca_origin:Ops_capability.Control
      ~hazard_id:"HZ-ASSURANCE-FOUNDATION-01"

  let duplicate_gates receipts =
    List.filter
      (fun gate ->
        List.length
          (List.filter (fun (item : receipt) -> item.gate = gate) receipts)
        > 1)
      all_input_gates

  let validation_errors context receipts =
    let receipt_errors =
      List.filter_map
        (fun item ->
          match validate_receipt ~context item with
          | Ok () -> None
          | Error issue -> Some issue)
        receipts
    in
    let duplicate_errors =
      duplicate_gates receipts
      |> List.map (fun gate ->
             error context Duplicate_receipt
               ("duplicate gate receipt: " ^ string_of_gate gate))
    in
    let circular_errors =
      receipts
      |> List.filter (fun (item : receipt) -> item.gate = Assurance)
      |> List.map (fun _ ->
             error context Invalid_receipt
               "an assurance receipt cannot be its own input")
    in
    receipt_errors @ duplicate_errors @ circular_errors

  let required_reason receipts gate =
    match List.find_opt (fun (item : receipt) -> item.gate = gate) receipts with
    | None -> Some ("missing required gate: " ^ string_of_gate gate)
    | Some { outcome = Satisfied; _ } -> None
    | Some { outcome = Rejected reasons; _ } ->
        Some
          (Printf.sprintf "required gate rejected: %s: %s"
             (string_of_gate gate) (String.concat "," reasons))
    | Some { outcome = Unavailable_observed reason; _ } ->
        Some
          (Printf.sprintf "required gate unavailable: %s: %s"
             (string_of_gate gate) reason)

  let bundle_digest receipts =
    receipts
    |> List.sort (fun (left : receipt) (right : receipt) ->
           String.compare (string_of_gate left.gate) (string_of_gate right.gate))
    |> List.map (fun (item : receipt) ->
           `Assoc
             [ ("gate", `String (string_of_gate item.gate));
               ("receiptDigest", `String item.receipt_digest) ])
    |> fun rows -> `Assoc [ ("receipts", `List rows) ]
    |> Run_model.canonical_string
    |> Result.map sha256

  let evaluate context receipts =
    match validation_errors context receipts with
    | _ :: _ as errors -> Error errors
    | [] ->
        let reasons = List.filter_map (required_reason receipts) required_gates in
        let outcome = match reasons with [] -> Satisfied | _ -> Rejected reasons in
        begin match bundle_digest receipts with
        | Error message -> Error [ error context Invalid_receipt message ]
        | Ok evidence_digest ->
            begin match
              mint_receipt ~evidence_digest context ~gate:Assurance ~outcome
                ~rca_origin:Ops_capability.Control
                ~hazard_ids:[ "HZ-ASSURANCE-FOUNDATION-01" ]
            with
            | Error issue -> Error [ issue ]
            | Ok receipt -> Ok { admitted = reasons = []; reasons; receipt }
            end
        end
end

module For_test = struct
  type retained_head_mutation =
    | Receipt_digest
    | Provenance
    | Store_identity of Run_event_store.t

  let current_head_receipt = make_current_head_receipt_for_test
  let validate_current_head_at ~wall_now_ns ~monotonic_now_ns receipt =
    validate_current_head_at ~wall_now_ns ~monotonic_now_ns head_coordinate receipt
  let mutate_current_head_event_digest receipt =
    { receipt with head_event_digest = sha256 (receipt.head_event_digest ^ ":mutant") }

  let revalidate_gate_context_current_head_at =
    revalidate_gate_context_current_head_at

  let mutate_retained_current_head mutation (context : gate_context) =
    let current_head =
      match mutation with
      | Receipt_digest ->
          { context.current_head with
            receipt_digest = sha256 (context.current_head.receipt_digest ^ ":mutant") }
      | Provenance ->
          let retained = context.current_head in
          let provenance =
            { retained.provenance with
              source_revision = retained.provenance.source_revision ^ "-mutant" }
          in
          let receipt_digest =
            match
              current_head_digest ~run_id:retained.run_id ~provenance
                ~head_sequence:retained.head_sequence
                ~head_event_digest:retained.head_event_digest
                ~observed_at_ns:retained.observed_at_ns
                ~current_at_ns:retained.current_at_ns
                ~expires_at_ns:retained.expires_at_ns
                ~observed_monotonic_ns:retained.observed_monotonic_ns
                ~expires_monotonic_ns:retained.expires_monotonic_ns
                ~authority_digest:retained.authority_digest
            with
            | Ok digest -> digest
            | Error _ -> retained.receipt_digest
          in
          { retained with provenance; receipt_digest }
      | Store_identity store ->
          { context.current_head with source = Store_source store }
    in
    { context with current_head }

  let control_evidence = make_control_evidence_for_test
  let control_evidence_at = make_control_evidence_at_for_test
  let residual_acceptance = make_residual_acceptance_for_test
end
