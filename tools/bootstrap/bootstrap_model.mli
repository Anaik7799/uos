(** EV01 Bootstrap predicate over observations, not an admission authority.
    Denotation: exactly one successful observation of each required fact.
    Missing, duplicate or false facts never construct a verified value. *)
type fact =
  | Workspace_marker | Repository_metadata | No_workspace_git_metadata
  | No_repository_git_metadata | Internal_git_store | Root_observed
  | Git_root_observed | Revision_observed | Snapshot_stable
type verified
type refusal = Malformed_observations | Failed_facts of fact list
val facts : fact list
val name : fact -> string
val verify : (fact * bool) list -> (verified, refusal) result
val observed : verified -> fact list
