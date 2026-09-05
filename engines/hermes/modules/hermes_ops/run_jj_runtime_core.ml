type diagnostic_code =
  | Process_schema_denominator_mismatch
  | Profile_subset_mismatch
  | Live_process_source_unfrozen
  | Process_registry_current_unavailable
  | Recovery_only_current_unavailable
  | Release_terminal_cleanup_denominator_unavailable

type diagnostic = {
  code : diagnostic_code;
  message : string;
  coordinate : string;
  origin : [ `Specification | `Evidence | `Control ];
}

let diagnostic code message origin =
  { code; message; coordinate = "L3/Orient/run-jj-runtime-core"; origin }

let diagnostic_code diagnostic = diagnostic.code
let diagnostic_message diagnostic = diagnostic.message
let diagnostic_coordinate diagnostic = diagnostic.coordinate
let diagnostic_origin diagnostic = diagnostic.origin

let string_of_diagnostic_code = function
  | Process_schema_denominator_mismatch ->
      "process-schema-denominator-mismatch"
  | Profile_subset_mismatch -> "profile-subset-mismatch"
  | Live_process_source_unfrozen -> "live-process-source-unfrozen"
  | Process_registry_current_unavailable ->
      "process-registry-current-unavailable"
  | Recovery_only_current_unavailable ->
      "recovery-only-current-unavailable"
  | Release_terminal_cleanup_denominator_unavailable ->
      "release-terminal-cleanup-denominator-unavailable"

type live_prerequisite =
  | Frozen_process_source_authority
  | Process_registry_current_carrier
  | Recovery_only_current_receipt
  | Release_terminal_cleanup_denominator

let live_prerequisite_status = function
  | Frozen_process_source_authority ->
      Error
        (diagnostic Live_process_source_unfrozen
           "the exact Jujutsu process source contract is not frozen"
           `Specification)
  | Process_registry_current_carrier ->
      Error
        (diagnostic Process_registry_current_unavailable
           "the process registry exposes no Current carrier" `Evidence)
  | Recovery_only_current_receipt ->
      Error
        (diagnostic Recovery_only_current_unavailable
           "Recovery_only requires a typed current Jj receipt carrier"
           `Evidence)
  | Release_terminal_cleanup_denominator ->
      Error
        (diagnostic Release_terminal_cleanup_denominator_unavailable
           "Release terminal-cleanup constructors are not frozen" `Specification)

let live_preparation_posture = `Implemented_unavailable

type production_profile
type candidate_profile
type formal_profile
type recovery_only_profile
type release_profile

type _ profile =
  | Production : production_profile profile
  | Candidate : candidate_profile profile
  | Formal : formal_profile profile
  | Recovery_only : recovery_only_profile profile
  | Release : release_profile profile

type packed_profile = Profile : 'profile profile -> packed_profile
let profiles =
  [ Profile Production; Profile Candidate; Profile Formal;
    Profile Recovery_only; Profile Release ]

let profile_id : type p. p profile -> string = function
  | Production -> "production"
  | Candidate -> "candidate"
  | Formal -> "formal"
  | Recovery_only -> "recovery-only"
  | Release -> "release"

type 'profile validated_subset = {
  subset_profile : 'profile profile;
  subset_count_value : int;
  subset_digest_value : string;
}

let subset_profile_id subset = profile_id subset.subset_profile
let subset_count subset = subset.subset_count_value
let subset_digest subset = subset.subset_digest_value

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let digest_ids profile ids =
  Jj_id.length_frame ("runtime-profile-subset-v1" :: profile :: ids) |> sha256

let expected_jujutsu_ids =
  List.map
    (fun operation ->
      Jj_process_schema.request_id
        (Jj_process_schema.Jujutsu_request operation))
    Jj_operation.all

let expected_candidate_ids =
  List.map
    (fun step ->
      Jj_process_schema.request_id
        (Jj_process_schema.Candidate_request step))
    Jj_action_kind.candidate_steps

let expected_formal_ids =
  List.map
    (fun tool ->
      Jj_process_schema.request_id (Jj_process_schema.Formal_request tool))
    Jj_action_kind.formal_tools

let sorted = List.sort String.compare

let ids_for_slot slot =
  Jj_process_schema.declaration_rows
  |> List.filter_map (fun (request, observed_slot, _) ->
       if String.equal slot observed_slot then Some request else None)

let unique values =
  List.length values = List.length (List.sort_uniq String.compare values)

let process_schema_is_exact () =
  let ids =
    List.map Jj_process_schema.declaration_request_id
      Jj_process_schema.declarations
  in
  List.length ids = 44
  && unique ids
  && Jj_process_schema.manifest_slot_ids
     = [ "process.jujutsu"; "process.candidate"; "process.formal" ]
  && sorted (ids_for_slot "process.jujutsu") = sorted expected_jujutsu_ids
  && sorted (ids_for_slot "process.candidate") = sorted expected_candidate_ids
  && sorted (ids_for_slot "process.formal") = sorted expected_formal_ids

let validate_fixed_subset :
    type p.
    p profile -> profile_name:string -> slot:string -> expected:string list ->
    (p validated_subset, diagnostic) result =
 fun profile ~profile_name ~slot ~expected ->
  if not (process_schema_is_exact ()) then
    Error
      (diagnostic Process_schema_denominator_mismatch
         "the private process schema is not the exact 34 + 5 + 5 denominator"
         `Control)
  else
    let observed = ids_for_slot slot in
    if sorted observed <> sorted expected || not (unique observed) then
      Error
        (diagnostic Profile_subset_mismatch
           ("the " ^ profile_name ^ " request subset is not exact") `Control)
    else
      Ok
        { subset_profile = profile;
          subset_count_value = List.length observed;
          subset_digest_value = digest_ids profile_name observed }

let validate_subset : type p. p profile -> (p validated_subset, diagnostic) result =
 fun profile ->
  match profile with
  | Recovery_only ->
      Error
        (diagnostic Recovery_only_current_unavailable
           "Recovery_only requires a typed current Jj receipt carrier"
           `Evidence)
  | Release ->
      Error
        (diagnostic Release_terminal_cleanup_denominator_unavailable
           "Release terminal-cleanup constructors are not frozen" `Specification)
  | Production ->
      validate_fixed_subset Production ~profile_name:"production"
        ~slot:"process.jujutsu" ~expected:expected_jujutsu_ids
  | Candidate ->
      validate_fixed_subset Candidate ~profile_name:"candidate"
        ~slot:"process.candidate" ~expected:expected_candidate_ids
  | Formal ->
      validate_fixed_subset Formal ~profile_name:"formal"
        ~slot:"process.formal" ~expected:expected_formal_ids

let runtime_core_declaration = Jj_runtime_manifest.runtime_core

let source_fields =
  [ ("schema-version", "run-jj-runtime-core-v1");
    ("request-denominator", "jujutsu:34,candidate:5,formal:5");
    ("manifest-process-slots",
     String.concat "," Jj_process_schema.manifest_slot_ids);
    ("runtime-core-declaration",
     Jj_runtime_manifest.declaration_key runtime_core_declaration ^ ":"
     ^ Jj_runtime_manifest.declaration_digest runtime_core_declaration);
    ("profiles", "production,candidate,formal,recovery-only,release");
    ("live-preparation", "implemented-unavailable:unfrozen-source");
    ("process-registry-current", "unavailable");
    ("recovery-only-current", "unavailable:typed-jj-receipt-required");
    ("release-terminal-cleanup", "unavailable:constructor-denominator-unfrozen");
    ("escape-fields", "none:argv,executable,cwd,environment,path");
    ("current-constructor", "absent");
    ("activation-constructor", "absent") ]

let source_digest_of process_schema_digest fields =
  let framed_fields =
    List.concat_map (fun (name, value) -> [ name; value ]) fields
  in
  digest_ids "run-jj-runtime-core-source-v1"
    (Jj_operation.source_digest :: Jj_action_kind.source_digest
     :: Jj_runtime_manifest.source_digest :: process_schema_digest
     :: framed_fields)

let source_digest =
  source_digest_of Jj_process_schema.source_digest source_fields

module For_test = struct
  let process_request_ids =
    List.map Jj_process_schema.declaration_request_id
      Jj_process_schema.declarations

  let process_request_slots =
    List.map
      (fun declaration ->
        (Jj_process_schema.declaration_request_id declaration,
         Jj_process_schema.declaration_slot_id declaration))
      Jj_process_schema.declarations

  let manifest_process_slot_ids = Jj_process_schema.manifest_slot_ids
  let process_schema_digest = Jj_process_schema.source_digest

  type source_mutation =
    | Drop_jujutsu_request
    | Drop_candidate_request
    | Drop_formal_request
    | Duplicate_request
    | Swap_process_slot
    | Drop_manifest_process_slot
    | Add_argv_field
    | Add_executable_field
    | Add_cwd_field
    | Add_environment_field
    | Add_path_field
    | Permit_live_preparation
    | Invent_process_registry_current
    | Guess_release_terminal_cleanup
    | Add_current_constructor
    | Add_activation_constructor

  let replace_field name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let has_prefix prefix value =
    let prefix_length = String.length prefix in
    String.length value >= prefix_length
    && String.sub value 0 prefix_length = prefix

  let rec drop_first predicate = function
    | [] -> []
    | row :: rows when predicate row -> rows
    | row :: rows -> row :: drop_first predicate rows

  let drop_request prefix =
    drop_first
      (fun (request, _, _) -> has_prefix prefix request)
      Jj_process_schema.declaration_rows

  let duplicate_request =
    match Jj_process_schema.declaration_rows with
    | [] -> [ ("request.duplicate", "process.jujutsu", "duplicate") ]
    | row :: _ -> row :: Jj_process_schema.declaration_rows

  let swap_process_slot =
    let rec swap = function
      | [] -> []
      | (request, slot, declaration) :: rows
        when String.equal slot "process.jujutsu" ->
          (request, "process.candidate", declaration) :: rows
      | row :: rows -> row :: swap rows
    in
    swap Jj_process_schema.declaration_rows

  let mutated_schema_digest rows slots =
    Jj_process_schema.source_digest_of_rows ~slots rows

  let source_digest_with_mutation mutation =
    let rows = Jj_process_schema.declaration_rows in
    let slots = Jj_process_schema.manifest_slot_ids in
    let schema_digest, fields =
      match mutation with
      | Drop_jujutsu_request ->
          (mutated_schema_digest (drop_request "request.jujutsu.") slots,
           source_fields)
      | Drop_candidate_request ->
          (mutated_schema_digest (drop_request "request.candidate.") slots,
           source_fields)
      | Drop_formal_request ->
          (mutated_schema_digest (drop_request "request.formal.") slots,
           source_fields)
      | Duplicate_request ->
          (mutated_schema_digest duplicate_request slots, source_fields)
      | Swap_process_slot ->
          (mutated_schema_digest swap_process_slot slots, source_fields)
      | Drop_manifest_process_slot ->
          (mutated_schema_digest rows
             (List.filter
                (fun slot -> not (String.equal slot "process.formal"))
                slots),
           source_fields)
      | Add_argv_field ->
          (Jj_process_schema.source_digest,
           replace_field "escape-fields" "argv" source_fields)
      | Add_executable_field ->
          (Jj_process_schema.source_digest,
           replace_field "escape-fields" "executable" source_fields)
      | Add_cwd_field ->
          (Jj_process_schema.source_digest,
           replace_field "escape-fields" "cwd" source_fields)
      | Add_environment_field ->
          (Jj_process_schema.source_digest,
           replace_field "escape-fields" "environment" source_fields)
      | Add_path_field ->
          (Jj_process_schema.source_digest,
           replace_field "escape-fields" "path" source_fields)
      | Permit_live_preparation ->
          (Jj_process_schema.source_digest,
           replace_field "live-preparation" "permitted" source_fields)
      | Invent_process_registry_current ->
          (Jj_process_schema.source_digest,
           replace_field "process-registry-current" "invented" source_fields)
      | Guess_release_terminal_cleanup ->
          (Jj_process_schema.source_digest,
           replace_field "release-terminal-cleanup" "guessed" source_fields)
      | Add_current_constructor ->
          (Jj_process_schema.source_digest,
           replace_field "current-constructor" "present" source_fields)
      | Add_activation_constructor ->
          (Jj_process_schema.source_digest,
           replace_field "activation-constructor" "present" source_fields)
    in
    source_digest_of schema_digest fields
end
