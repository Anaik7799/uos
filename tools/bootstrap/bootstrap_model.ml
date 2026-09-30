type fact =
  | Workspace_marker | Repository_metadata | No_workspace_git_metadata
  | No_repository_git_metadata | Internal_git_store | Root_observed
  | Git_root_observed | Revision_observed | Snapshot_stable
type verified = Verified
type refusal = Malformed_observations | Failed_facts of fact list
let facts = [Workspace_marker; Repository_metadata; No_workspace_git_metadata;
  No_repository_git_metadata; Internal_git_store; Root_observed; Git_root_observed;
  Revision_observed; Snapshot_stable]
let name = function
  | Workspace_marker -> "workspace_marker"
  | Repository_metadata -> "repository_metadata"
  | No_workspace_git_metadata -> "no_workspace_git_metadata"
  | No_repository_git_metadata -> "no_repository_git_metadata"
  | Internal_git_store -> "internal_git_store"
  | Root_observed -> "root_observed"
  | Git_root_observed -> "git_root_observed"
  | Revision_observed -> "revision_observed"
  | Snapshot_stable -> "snapshot_stable"
let verify observations =
  let rec collect seen failed = function
    | [] ->
        if List.length seen <> List.length facts then Error Malformed_observations
        else if failed <> [] then Error (Failed_facts (List.rev failed))
        else Ok Verified
    | (fact, success) :: rest ->
        if List.mem fact seen then Error Malformed_observations
        else collect (fact :: seen) (if success then failed else fact :: failed) rest
  in collect [] [] observations
let observed Verified = facts
