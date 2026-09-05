(** Pure, non-authorizing runtime declaration manifest with one phantom per slot. *)

type target_jj and target_external_resource and target_repository_source
type target_approval and target_writer_lease and target_transition
type target_mutation_frontier and target_network_scope and target_credential_lease
type target_filesystem_materialization and target_candidate_verification
type target_release and target_completion_receipt and target_formal
type process_jujutsu and process_candidate and process_formal
type runtime_core and runtime_operator and runtime_recovery_port_vault
type activation_production and activation_candidate and activation_release
type activation_formal
type store_authority and store_dispatch and store_recovery_vault
type store_effect_event and store_completion_receipt

type _ slot =
  | Target_jj : target_jj slot
  | Target_external_resource : target_external_resource slot
  | Target_repository_source : target_repository_source slot
  | Target_approval : target_approval slot
  | Target_writer_lease : target_writer_lease slot
  | Target_transition : target_transition slot
  | Target_mutation_frontier : target_mutation_frontier slot
  | Target_network_scope : target_network_scope slot
  | Target_credential_lease : target_credential_lease slot
  | Target_filesystem_materialization : target_filesystem_materialization slot
  | Target_candidate_verification : target_candidate_verification slot
  | Target_release : target_release slot
  | Target_completion_receipt : target_completion_receipt slot
  | Target_formal : target_formal slot
  | Process_jujutsu : process_jujutsu slot
  | Process_candidate : process_candidate slot
  | Process_formal : process_formal slot
  | Runtime_core : runtime_core slot
  | Runtime_operator : runtime_operator slot
  | Runtime_recovery_port_vault : runtime_recovery_port_vault slot
  | Activation_production : activation_production slot
  | Activation_candidate : activation_candidate slot
  | Activation_release : activation_release slot
  | Activation_formal : activation_formal slot
  | Store_authority : store_authority slot
  | Store_dispatch : store_dispatch slot
  | Store_recovery_vault : store_recovery_vault slot
  | Store_effect_event : store_effect_event slot
  | Store_completion_receipt : store_completion_receipt slot

type 'slot declaration
type production

val slot_key : 'slot slot -> string
val declaration_key : 'slot declaration -> string
val declaration_digest : 'slot declaration -> string

(** Slot-local declarations are pure schema identities, not runtime
    availability attestations or capabilities. There is deliberately no
    generic public declaration constructor. *)
val target_jj : target_jj declaration
val target_external_resource : target_external_resource declaration
val target_repository_source : target_repository_source declaration
val target_approval : target_approval declaration
val target_writer_lease : target_writer_lease declaration
val target_transition : target_transition declaration
val target_mutation_frontier : target_mutation_frontier declaration
val target_network_scope : target_network_scope declaration
val target_credential_lease : target_credential_lease declaration
val target_filesystem_materialization : target_filesystem_materialization declaration
val target_candidate_verification : target_candidate_verification declaration
val target_release : target_release declaration
val target_completion_receipt : target_completion_receipt declaration
val process_jujutsu : process_jujutsu declaration
val process_candidate : process_candidate declaration
val runtime_core : runtime_core declaration
val runtime_operator : runtime_operator declaration
val runtime_recovery_port_vault : runtime_recovery_port_vault declaration
val activation_production : activation_production declaration
val activation_candidate : activation_candidate declaration
val activation_release : activation_release declaration
val store_authority : store_authority declaration
val store_dispatch : store_dispatch declaration
val store_recovery_vault : store_recovery_vault declaration
val store_effect_event : store_effect_event declaration
val store_completion_receipt : store_completion_receipt declaration

val target_formal_available : target_formal declaration
val target_formal_unavailable : target_formal declaration
val process_formal_available : process_formal declaration
val process_formal_unavailable : process_formal declaration
val activation_formal_available : activation_formal declaration
val activation_formal_unavailable : activation_formal declaration

val production :
  target_jj:target_jj declaration ->
  target_external_resource:target_external_resource declaration ->
  target_repository_source:target_repository_source declaration ->
  target_approval:target_approval declaration ->
  target_writer_lease:target_writer_lease declaration ->
  target_transition:target_transition declaration ->
  target_mutation_frontier:target_mutation_frontier declaration ->
  target_network_scope:target_network_scope declaration ->
  target_credential_lease:target_credential_lease declaration ->
  target_filesystem_materialization:target_filesystem_materialization declaration ->
  target_candidate_verification:target_candidate_verification declaration ->
  target_release:target_release declaration ->
  target_completion_receipt:target_completion_receipt declaration ->
  target_formal:target_formal declaration ->
  process_jujutsu:process_jujutsu declaration ->
  process_candidate:process_candidate declaration ->
  process_formal:process_formal declaration ->
  runtime_core:runtime_core declaration ->
  runtime_operator:runtime_operator declaration ->
  runtime_recovery_port_vault:runtime_recovery_port_vault declaration ->
  activation_production:activation_production declaration ->
  activation_candidate:activation_candidate declaration ->
  activation_release:activation_release declaration ->
  activation_formal:activation_formal declaration ->
  store_authority:store_authority declaration ->
  store_dispatch:store_dispatch declaration ->
  store_recovery_vault:store_recovery_vault declaration ->
  store_effect_event:store_effect_event declaration ->
  store_completion_receipt:store_completion_receipt declaration ->
  (production, Jj_error.t) result

val production_digest : production -> string
val production_slot_keys : string list
val slot_count : int

(** Test support is a separate profile and cannot inhabit a production slot. *)
type test_activation_disposable
type test_fixture_materialization
type test_isolation
type 'slot test_declaration
type test_support
val test_activation_disposable : test_activation_disposable test_declaration
val test_fixture_materialization : test_fixture_materialization test_declaration
val test_isolation : test_isolation test_declaration
val test_support :
  activation_disposable:test_activation_disposable test_declaration ->
  fixture_materialization:test_fixture_materialization test_declaration ->
  isolation:test_isolation test_declaration ->
  test_support
val test_support_digest : test_support -> string
val test_support_slot_keys : string list
val test_slot_count : int
val source_digest : string
