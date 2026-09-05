(** Authority-preserving Task 6 analysis engines.

    Ruliad and Stan are permanently report-only. Their private receipts bind
    one validated current gate context, canonical input and budget identities,
    deterministic replay, and an explicit completeness boundary. Z3 remains a
    load-bearing gate and is unavailable until a supervised solver receipt is
    admitted. None of these receipts grants parity credit. *)

type engine = Ruliad | Stan_model | Z3

val gate : engine -> Run_safety.gate
val authority : engine -> Run_safety.authority
(** Ruliad and Stan are permanently [Analysis_only]; only Z3 is a
    load-bearing dispatch gate. *)

val unavailable_receipt :
  Run_safety.gate_context -> engine:engine -> reason:string ->
  (Run_safety.receipt, Run_safety.gate_error) result
(** Absent analysis engines can produce only context-bound
    [Unavailable_observed] receipts; no external/live result is synthesized. *)

val canonical_digest : string -> bool
(** True exactly for a lowercase canonical SHA-256 hexadecimal digest. *)
(*@ result = canonical_digest digest
    pure *)

module Ruliad : sig
  type state = {
    stable_id : string;
    evidence_digest : string;
  }

  type transition = {
    stable_id : string;
    from_state_id : string;
    to_state_id : string;
    move_digest : string;
  }

  type system

  val make_system :
    initial_state_id:string -> states:state list -> transitions:transition list ->
    (system, string list) result
  (** Validates all identifiers, lowercase SHA-256 identities, uniqueness and
      transition references, then derives one canonical system digest. *)

  type bounds = {
    max_states : int;
    max_edges : int;
    max_depth : int;
    max_paths : int64;
  }

  type graph = private {
    states : state list;
    transitions : transition list;
    terminal_state_ids : string list;
    state_count : int;
    edge_count : int;
    path_count : int64;
    max_depth : int;
    confluent : bool;
    graph_digest : string;
  }

  type unavailable_reason =
    | State_cap
    | Edge_cap
    | Depth_cap
    | Path_cap
    | Cyclic_relation

  type outcome =
    | Completed of graph
    | Unavailable of unavailable_reason * graph

  type receipt = private {
    authority : Run_safety.authority;
    context_digest : string;
    current_head_digest : string;
    current_at_ns : int64;
    system_digest : string;
    bounds_digest : string;
    outcome : outcome;
    outcome_digest : string;
    receipt_digest : string;
  }

  val analyze :
    Run_safety.gate_context -> bounds:bounds -> system ->
    (receipt, Run_safety.gate_error) result
  (*@ ensures match result with
      | Ok receipt -> receipt.authority = Run_safety.Analysis_only /\
                      canonical_digest receipt.receipt_digest = true
      | Error _ -> true *)

  val validate_receipt :
    context:Run_safety.gate_context -> receipt ->
    (unit, Run_safety.gate_error) result

  (** Recomputes the declared system under the exact bounds.  Only a complete
      within-bounds result with [Analysis_only] authority is accepted. *)
  val validate_exact :
    context:Run_safety.gate_context -> system:system -> bounds:bounds ->
    receipt -> (unit, Run_safety.gate_error) result
end

type ruliad_receipt = Ruliad.receipt

module Stan_model : sig
  type verdict = Passed | Failed

  type observation = private {
    scenario_id : string;
    family_id : string;
    sequence : int64;
    verdict : verdict;
    evidence_digest : string;
    observation_digest : string;
  }

  val make_observation :
    scenario_id:string -> family_id:string -> sequence:int64 ->
    verdict:verdict -> evidence_digest:string ->
    (observation, string list) result

  type input

  val make_input :
    prior_alpha:float -> prior_beta:float -> all_families:string list ->
    observations:observation list -> (input, string list) result
  (** Priors must be finite and positive. Historical observations are allowed,
      but each scenario must have one unique latest sequence and every evidence
      digest may identify only one observation. *)

  type model_kind = Beta_binomial_analytic_moment_band_v1

  type family_summary = private {
    family_id : string;
    scenario_count : int;
    passing_count : int;
    posterior_alpha : float;
    posterior_beta : float;
    mean : float;
    variance : float;
    moment_band_low : float;
    moment_band_high : float;
    latest_observation_digests : string list;
    summary_digest : string;
  }

  type receipt = private {
    model : model_kind;
    authority : Run_safety.authority;
    context_digest : string;
    current_head_digest : string;
    current_at_ns : int64;
    input_digest : string;
    model_digest : string;
    summaries : family_summary list;
    unmeasured_families : string list;
    coverage_complete : bool;
    result_digest : string;
    receipt_digest : string;
  }

  val analyze :
    Run_safety.gate_context -> input ->
    (receipt, Run_safety.gate_error) result
  (*@ ensures match result with
      | Ok receipt -> receipt.authority = Run_safety.Analysis_only /\
                      canonical_digest receipt.receipt_digest = true
      | Error _ -> true *)

  val validate_receipt :
    context:Run_safety.gate_context -> receipt ->
    (unit, Run_safety.gate_error) result

  (** Recomputes the exact population and observations and requires complete
      family coverage.  Analysis evidence remains report-only. *)
  val validate_exact :
    context:Run_safety.gate_context -> input:input -> receipt ->
    (unit, Run_safety.gate_error) result
end

type stan_receipt = Stan_model.receipt

module Z3 : sig
  (** Closed load-bearing solver evidence.  [Run_formal.result] is reused so
      the formal authority, both solver backends, and the admission predicate
      cannot disagree through an adapter-only result type. *)

  type backend = Linked_smtml_z3 | Injected_z3_cli

  type process_status =
    | Exited of int
    | Signalled of int
    | Timed_out
    | Spawn_failed
    | Supervision_failed

  type campaign_envelope = private {
    maximum_total_elapsed_ms : int;
    maximum_teardown_ms : int;
    maximum_receipt_materialization_ms : int;
    linked_max_allocated_bytes : int64;
    linked_max_heap_words : int;
    linked_worker_executable : string;
    linked_worker_executable_digest : string;
    linked_virtual_memory_bytes : int64;
    linked_cpu_seconds : int;
    linked_maximum_query_bytes : int;
    linked_maximum_output_bytes : int;
    maximum_worker_rss_bytes : int64;
    envelope_digest : string;
  }

  val make_campaign_envelope :
    maximum_total_elapsed_ms:int -> linked_max_allocated_bytes:int64 ->
    linked_max_heap_words:int -> linked_virtual_memory_bytes:int64 ->
    linked_cpu_seconds:int -> linked_maximum_query_bytes:int ->
    linked_maximum_output_bytes:int -> maximum_worker_rss_bytes:int64 ->
    (campaign_envelope, string list) result
  (** Declares campaign, bounded process teardown, and linked-memory evidence
      limits.  [maximum_teardown_ms] is derived from the maximum single worker
      timeout admitted by both the campaign and obligation authority, followed
      by its TERM and KILL grace phases.  The separate receipt-materialization
      allowance derives from the exact obligation count and total authoritative
      SMT bytes.  Both wall-clock bounds are part of the envelope digest.
      This envelope does not itself claim hard isolation; until an isolated
      linked worker exists, a campaign remains non-admitting even when
      post-hoc measurements fit. *)

  type cli_configuration = private {
    executable : string;
    executable_digest : string;
    timeout_ms : int;
    version_probe_timeout_ms : int;
    termination_grace_ms : int;
    maximum_output_bytes : int;
    configuration_digest : string;
  }

  val make_cli_configuration :
    executable:string -> timeout_ms:int -> termination_grace_ms:int ->
    maximum_output_bytes:int -> (cli_configuration, string list) result
  (** The executable must be an absolute readable regular file.  Its canonical
      content digest and every bounded supervision setting are derived into the
      private configuration identity.  Version discovery uses an independent
      bounded executable-startup allowance; solver queries retain [timeout_ms]. *)

  type diagnostic = private {
    code : string;
    detail : string;
    detail_digest : string;
    coordinate : Ops_capability.coordinate;
    rca_origin : Ops_capability.rca_origin;
    hazard_id : string;
    diagnostic_digest : string;
  }

  type process_receipt = private {
    argv_digest : string;
    timeout_ms : int;
    elapsed_ns : int64;
    status : process_status;
    child_created : bool;
    term_sent : bool;
    kill_sent : bool;
    reaped : bool;
    stdout : string;
    stderr : string;
    stdout_bytes : int;
    stderr_bytes : int;
    stdout_digest : string;
    stderr_digest : string;
    receipt_digest : string;
  }

  val supervision_admissible :
    status:process_status -> child_created:bool -> term_sent:bool ->
    kill_sent:bool -> reaped:bool -> bool
  (** Only a normally exited-zero, created and reaped child is admissible.
      Timeout, signal, spawn, supervision failure, or missing reap is never
      solver credit. *)

  type linked_invocation = private {
    solver_calls_before : int;
    solver_calls_after : int;
    solver_call_delta : int;
    assertion_count : int;
    invocation_digest : string;
  }

  type backend_receipt = private {
    backend : backend;
    obligation_stable_id : string;
    requirement_id : string;
    kind : Run_formal.kind;
    expected : Run_formal.result;
    observed : Run_formal.result;
    query_digest : string;
    query_bytes : int;
    executed_query_digest : string;
    readback_query_digest : string;
    readback_query_bytes : int;
    query_object_identity_stable : bool;
    query_object_identity_digest : string;
    obligation_timeout_ms : int;
    solver_timeout_ms : int;
    solver_id : string;
    solver_version_constraint : string;
    solver_version : string;
    linked_library_version : string option;
    executable_path : string option;
    executable_digest : string option;
    process : process_receipt option;
    linked_invocation : linked_invocation option;
    linked_request_digest : string option;
    linked_limits_digest : string option;
    linked_handshake_digest : string option;
    linked_result_digest : string option;
    diagnostics : diagnostic list;
    receipt_digest : string;
  }

  val query_execution_admissible :
    authoritative_digest:string -> executed_digest:string ->
    readback_digest:string -> authoritative_bytes:int -> readback_bytes:int ->
    object_identity_stable:bool -> bool
  (** Pure fail-closed identity law shared by linked and CLI materialization. *)

  type admission = Admitted | Blocked

  type row_policy =
    | Preflight_fail_fast
    | Campaign_deadline_partial
    | Full_denominator

  type memory_evidence = private {
    envelope_digest : string;
    allocated_before_bytes : int64;
    allocated_after_bytes : int64;
    heap_before_words : int;
    heap_after_words : int;
    within_envelope : bool;
    hard_isolated : bool;
    peak_rss_bytes : int64;
    virtual_memory_limit_bytes : int64;
    cpu_limit_seconds : int;
    worker_executable_digest : string;
    limits_digest : string;
    evidence_digest : string;
  }

  type receipt = private {
    authority : Run_safety.authority;
    context_digest : string;
    current_head_digest : string;
    current_at_ns : int64;
    specification_digest : string;
    obligation_set_digest : string;
    cli_configuration_digest : string;
    campaign_envelope_digest : string;
    campaign_elapsed_ns : int64;
    campaign_deadline_exhausted : bool;
    cli_version_process : process_receipt;
    in_process : backend_receipt list;
    cli : backend_receipt list;
    controls_complete : bool;
    laws_complete : bool;
    cross_backend_agreement : bool;
    admission : admission;
    row_policy : row_policy;
    memory_evidence : memory_evidence;
    diagnostics : diagnostic list;
    result_digest : string;
    receipt_digest : string;
  }

  val verify :
    Run_safety.gate_context -> campaign:campaign_envelope -> cli_configuration ->
    (receipt, Run_safety.gate_error) result
  (** Executes the exact immutable [Run_formal.obligations] through both the
      linked smtml/Z3 path and the injected argv-only CLI path.  It never
      regenerates or substitutes a query.  [Admitted] additionally requires
      the linked worker's applied hard process isolation and measured RSS
      evidence within the declared memory envelope. *)
  (*@ ensures match result with
      | Ok receipt -> receipt.authority = Run_safety.Load_bearing_dispatch_gate /\
                      canonical_digest receipt.receipt_digest = true /\
                      (receipt.admission = Admitted ->
                         receipt.memory_evidence.hard_isolated = true /\
                         receipt.memory_evidence.within_envelope = true) /\
                      (receipt.row_policy = Preflight_fail_fast ->
                         receipt.in_process = [] /\ receipt.cli = []) /\
                      (receipt.row_policy = Campaign_deadline_partial ->
                         List.length receipt.in_process =
                           List.length Run_formal.obligations /\
                         List.length receipt.cli =
                           List.length Run_formal.obligations /\
                         receipt.campaign_deadline_exhausted = true /\
                         receipt.admission = Blocked) /\
                      (receipt.row_policy = Full_denominator ->
                         List.length receipt.in_process =
                           List.length Run_formal.obligations /\
                         List.length receipt.cli =
                           List.length Run_formal.obligations)
      | Error _ -> true *)

  val validate_receipt :
    context:Run_safety.gate_context -> campaign:campaign_envelope ->
    cli_configuration -> receipt ->
    (unit, Run_safety.gate_error) result
  (** Recomputes every canonical campaign and row identity and rejects stale,
      incomplete, non-reaped, mismatched, or fabricated credit.  Deadline
      materialization retains the exact authoritative obligation identity on
      each backend; every unstarted deadline row is typed [Unavailable] with no
      process evidence and can only validate as blocked partial evidence. *)

  module For_test : sig
    type receipt_mutation =
      | Positive_wrong_assertion_count
      | Substituted_linked_request_digest
      | Substituted_linked_handshake_digest
      | Substituted_linked_result_digest

    val mutate_receipt : receipt_mutation -> receipt -> receipt
    (** Corrupts one linked-evidence field of an existing private receipt while
        coherently resealing its derived receipt digests.  It cannot construct
        solver evidence or grant production authority. *)
  end
end

type z3_receipt = Z3.receipt
