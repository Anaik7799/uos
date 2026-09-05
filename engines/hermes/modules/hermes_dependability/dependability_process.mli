(** Fail-closed process-owner boundary.

    Callers may supply only the closed declarative process protocol.  No raw
    executable, argv, environment, working-directory, output path, receipt,
    or effect entrypoint is public.  Preparation remains unavailable until a
    registered target/executable authority and the governed Swarm bridge are
    implemented. *)

type request

type unavailable =
  | Missing_registered_target_authority
  | Missing_registered_executable_authority
  | Bridge_admission_required

val prepare :
  Dependability_process_protocol.declaration -> (request, unavailable) result
