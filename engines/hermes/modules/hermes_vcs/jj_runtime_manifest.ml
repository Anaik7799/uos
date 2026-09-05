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

type formal_unavailable_reason =
  | Formal_target_not_landed
  | Formal_process_not_landed
  | Formal_activation_not_landed
type 'slot declaration = { key : string; posture : string; digest : string }
type production = { declarations : string list; manifest_digest : string }

let slot_key : type s. s slot -> string = function
  | Target_jj -> "target.jj" | Target_external_resource -> "target.external-resource"
  | Target_repository_source -> "target.repository-source"
  | Target_approval -> "target.approval" | Target_writer_lease -> "target.writer-lease"
  | Target_transition -> "target.transition"
  | Target_mutation_frontier -> "target.mutation-frontier"
  | Target_network_scope -> "target.network-scope"
  | Target_credential_lease -> "target.credential-lease"
  | Target_filesystem_materialization -> "target.filesystem-materialization"
  | Target_candidate_verification -> "target.candidate-verification"
  | Target_release -> "target.release"
  | Target_completion_receipt -> "target.completion-receipt"
  | Target_formal -> "target.formal" | Process_jujutsu -> "process.jujutsu"
  | Process_candidate -> "process.candidate" | Process_formal -> "process.formal"
  | Runtime_core -> "runtime.core" | Runtime_operator -> "runtime.operator"
  | Runtime_recovery_port_vault -> "runtime.recovery-transition-port-vault"
  | Activation_production -> "activation.production"
  | Activation_candidate -> "activation.candidate"
  | Activation_release -> "activation.release" | Activation_formal -> "activation.formal"
  | Store_authority -> "store.authority" | Store_dispatch -> "store.dispatch"
  | Store_recovery_vault -> "store.recovery-vault"
  | Store_effect_event -> "store.effect-event"
  | Store_completion_receipt -> "store.completion-receipt"

let make_declaration slot posture =
  let key = slot_key slot in
  let digest = Jj_id.length_frame [ key; posture ]
    |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex in
  { key; posture; digest }

let declaration_key (declaration : _ declaration) = declaration.key
let declaration_digest (declaration : _ declaration) = declaration.digest

let available slot = make_declaration slot "schema-declared"
let target_jj = available Target_jj
let target_external_resource = available Target_external_resource
let target_repository_source = available Target_repository_source
let target_approval = available Target_approval
let target_writer_lease = available Target_writer_lease
let target_transition = available Target_transition
let target_mutation_frontier = available Target_mutation_frontier
let target_network_scope = available Target_network_scope
let target_credential_lease = available Target_credential_lease
let target_filesystem_materialization = available Target_filesystem_materialization
let target_candidate_verification = available Target_candidate_verification
let target_release = available Target_release
let target_completion_receipt = available Target_completion_receipt
let process_jujutsu = available Process_jujutsu
let process_candidate = available Process_candidate
let runtime_core = available Runtime_core
let runtime_operator = available Runtime_operator
let runtime_recovery_port_vault = available Runtime_recovery_port_vault
let activation_production = available Activation_production
let activation_candidate = available Activation_candidate
let activation_release = available Activation_release
let store_authority = available Store_authority
let store_dispatch = available Store_dispatch
let store_recovery_vault = available Store_recovery_vault
let store_effect_event = available Store_effect_event
let store_completion_receipt = available Store_completion_receipt

let formal_reason_key = function
  | Formal_target_not_landed -> "target-not-landed"
  | Formal_process_not_landed -> "process-not-landed"
  | Formal_activation_not_landed -> "activation-not-landed"

let formal_available slot =
  make_declaration slot "formal-schema-declared"
let formal_unavailable slot reason =
  make_declaration slot ("formal-unavailable:" ^ formal_reason_key reason)

let target_formal_available = formal_available Target_formal
let target_formal_unavailable =
  formal_unavailable Target_formal Formal_target_not_landed
let process_formal_available = formal_available Process_formal
let process_formal_unavailable =
  formal_unavailable Process_formal Formal_process_not_landed
let activation_formal_available = formal_available Activation_formal
let activation_formal_unavailable =
  formal_unavailable Activation_formal Formal_activation_not_landed

type packed_slot = Pack : 'slot slot -> packed_slot

let production_slots =
  [ Pack Target_jj; Pack Target_external_resource;
    Pack Target_repository_source; Pack Target_approval;
    Pack Target_writer_lease; Pack Target_transition;
    Pack Target_mutation_frontier; Pack Target_network_scope;
    Pack Target_credential_lease; Pack Target_filesystem_materialization;
    Pack Target_candidate_verification; Pack Target_release;
    Pack Target_completion_receipt; Pack Target_formal;
    Pack Process_jujutsu; Pack Process_candidate; Pack Process_formal;
    Pack Runtime_core; Pack Runtime_operator; Pack Runtime_recovery_port_vault;
    Pack Activation_production; Pack Activation_candidate;
    Pack Activation_release; Pack Activation_formal; Pack Store_authority;
    Pack Store_dispatch; Pack Store_recovery_vault; Pack Store_effect_event;
    Pack Store_completion_receipt ]

let production_slot_keys =
  List.map (fun (Pack slot) -> slot_key slot) production_slots

let production ~target_jj ~target_external_resource ~target_repository_source
    ~target_approval ~target_writer_lease ~target_transition ~target_mutation_frontier
    ~target_network_scope ~target_credential_lease ~target_filesystem_materialization
    ~target_candidate_verification ~target_release ~target_completion_receipt
    ~target_formal ~process_jujutsu ~process_candidate ~process_formal ~runtime_core
    ~runtime_operator ~runtime_recovery_port_vault ~activation_production
    ~activation_candidate ~activation_release ~activation_formal ~store_authority
    ~store_dispatch ~store_recovery_vault ~store_effect_event ~store_completion_receipt =
  let declarations =
    [ target_jj.digest; target_external_resource.digest; target_repository_source.digest;
      target_approval.digest; target_writer_lease.digest; target_transition.digest;
      target_mutation_frontier.digest; target_network_scope.digest;
      target_credential_lease.digest; target_filesystem_materialization.digest;
      target_candidate_verification.digest; target_release.digest;
      target_completion_receipt.digest; target_formal.digest; process_jujutsu.digest;
      process_candidate.digest; process_formal.digest; runtime_core.digest;
      runtime_operator.digest; runtime_recovery_port_vault.digest;
      activation_production.digest; activation_candidate.digest;
      activation_release.digest; activation_formal.digest; store_authority.digest;
      store_dispatch.digest; store_recovery_vault.digest; store_effect_event.digest;
      store_completion_receipt.digest ] in
  let digest = Jj_id.length_frame
      ([ "profile:production" ] @ production_slot_keys @ declarations)
    |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex in
  Ok { declarations; manifest_digest = digest }

let production_digest production = production.manifest_digest

type test_activation_disposable
type test_fixture_materialization
type test_isolation
type 'slot test_declaration = { test_key : string; test_digest : string }
type test_support = { test_declarations : string list; test_manifest_digest : string }

let make_test_declaration test_key =
  let test_digest = Jj_id.length_frame [ "profile:test-support"; test_key ]
    |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex in
  { test_key; test_digest }

let test_activation_disposable =
  make_test_declaration "test.activation.disposable"
let test_fixture_materialization =
  make_test_declaration "test.fixture-materialization"
let test_isolation = make_test_declaration "test.isolation"
let test_support_slot_keys =
  [ "test.activation.disposable"; "test.fixture-materialization";
    "test.isolation" ]
let test_slot_count = List.length test_support_slot_keys

let test_support ~activation_disposable ~fixture_materialization ~isolation =
  let test_declarations =
    [ activation_disposable.test_digest; fixture_materialization.test_digest;
      isolation.test_digest ] in
  let test_manifest_digest =
    Jj_id.length_frame
      ([ "profile:test-support" ] @ test_support_slot_keys @ test_declarations)
    |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex in
  { test_declarations; test_manifest_digest }

let test_support_digest support = support.test_manifest_digest
let slot_count = List.length production_slot_keys
let source_digest =
  Jj_id.length_frame
    ([ "jj-runtime-manifest-v2"; string_of_int slot_count;
       string_of_int test_slot_count; "unique-phantom-per-slot";
       "slot-local-declarations"; "production-profile";
       "test-support-separate" ]
     @ production_slot_keys @ test_support_slot_keys
     @ [ formal_reason_key Formal_target_not_landed;
         formal_reason_key Formal_process_not_landed;
         formal_reason_key Formal_activation_not_landed ])
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
