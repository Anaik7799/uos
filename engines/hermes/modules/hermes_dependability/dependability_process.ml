type request = {
  declaration_digest : string;
  protocol_digest : string;
}

type unavailable =
  | Missing_registered_target_authority
  | Missing_registered_executable_authority
  | Bridge_admission_required

let prepare (_ : Dependability_process_protocol.declaration) =
  Error Missing_registered_target_authority
