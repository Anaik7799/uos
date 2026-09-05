(** Private pure process-declaration schema.  This module contains identities
    only; it never carries an executable, argv, cwd, environment, path, process
    handle, registry-current witness, or activation capability. *)

type _ process_slot =
  | Jujutsu_process : Jj_runtime_manifest.process_jujutsu process_slot
  | Candidate_process : Jj_runtime_manifest.process_candidate process_slot
  | Formal_process : Jj_runtime_manifest.process_formal process_slot

type request_kind =
  | Jujutsu_request of Jj_operation.t
  | Candidate_request of Jj_action_kind.candidate_step
  | Formal_request of Jj_action_kind.formal_tool

type declaration =
  | Declaration : {
      request : request_kind;
      request_id : string;
      slot : 'slot process_slot;
      manifest : 'slot Jj_runtime_manifest.declaration;
      digest : string;
    } -> declaration

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let frame value = string_of_int (String.length value) ^ ":" ^ value
let digest_fields fields = fields |> List.map frame |> String.concat "" |> sha256

let slot_id : type slot. slot process_slot -> string = function
  | Jujutsu_process -> "process.jujutsu"
  | Candidate_process -> "process.candidate"
  | Formal_process -> "process.formal"

let request_id = function
  | Jujutsu_request operation ->
      "request.jujutsu."
      ^ (Jj_operation.declaration operation).Jj_operation.key
  | Candidate_request step ->
      "request.candidate." ^ Jj_action_kind.candidate_step_key step
  | Formal_request tool ->
      "request.formal." ^ Jj_action_kind.formal_tool_key tool

let protocol_request = function
  | Jujutsu_request operation ->
      Jj_process_protocol.Jujutsu_operation operation
  | Candidate_request step ->
      Jj_process_protocol.Candidate_verification step
  | Formal_request tool -> Jj_process_protocol.Formal_oracle tool

let make request slot manifest =
  let identity = request_id request in
  Declaration
    { request; request_id = identity; slot; manifest;
      digest =
        digest_fields
          [ "jj-process-declaration-v1"; identity; slot_id slot;
            Jj_process_protocol.key (protocol_request request);
            Jj_runtime_manifest.declaration_key manifest;
            Jj_runtime_manifest.declaration_digest manifest ] }

let declarations =
  List.map
    (fun operation ->
      make (Jujutsu_request operation) Jujutsu_process
        Jj_runtime_manifest.process_jujutsu)
    Jj_operation.all
  @ List.map
      (fun step ->
        make (Candidate_request step) Candidate_process
          Jj_runtime_manifest.process_candidate)
      Jj_action_kind.candidate_steps
  @ List.map
      (fun tool ->
        make (Formal_request tool) Formal_process
          Jj_runtime_manifest.process_formal_unavailable)
      Jj_action_kind.formal_tools

let declaration_request_id (Declaration declaration) = declaration.request_id
let declaration_slot_id (Declaration declaration) = slot_id declaration.slot
let declaration_digest (Declaration declaration) = declaration.digest

let declaration_row declaration =
  (declaration_request_id declaration, declaration_slot_id declaration,
   declaration_digest declaration)

let manifest_slot_ids =
  [ slot_id Jujutsu_process; slot_id Candidate_process; slot_id Formal_process ]

let source_digest_of_rows ~slots rows =
  rows
  |> List.concat_map (fun (request, slot, declaration) ->
       [ request; slot; declaration ])
  |> fun fields ->
       digest_fields
         ([ "jj-process-schema-v1"; Jj_process_protocol.source_digest;
            Jj_operation.source_digest;
            Jj_action_kind.source_digest; Jj_runtime_manifest.source_digest;
            "request-count"; string_of_int (List.length rows);
            "slot-count"; string_of_int (List.length slots) ]
          @ slots @ fields)

let declaration_rows = List.map declaration_row declarations
let source_digest = source_digest_of_rows ~slots:manifest_slot_ids declaration_rows
