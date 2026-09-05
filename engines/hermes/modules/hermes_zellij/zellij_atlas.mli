(** Atomic functional atlas for the Zellij integration and documentation oracle.
*)

type lifecycle =
  | Documented_only
  | Declared
  | Implemented
  | Tested
  | Live_verified
  | Unavailable_observed

type credit =
  | No_credit
  | Discovery_credit
  | Structural_credit
  | Functional_credit

type operation =
  | Install
  | Preflight
  | Observe_version
  | Render_kdl
  | Validate_kdl
  | Backup
  | Project
  | Install_command
  | List_sessions
  | Ensure
  | Attach
  | Observe
  | Verify
  | Status
  | Detect_drift
  | Tmux_non_interference
  | Removal_plan
  | Docs_audit

type row

val rows : row list
val documentation_pages : row list
val validate : unit -> string list
val validate_rows : row list -> string list
val digest : string
val id : row -> string
val ontology_id : row -> string
val session : row -> Zellij_intent.session option
val operation : row -> operation option
val lifecycle : row -> lifecycle
val credit : row -> credit
val documentation_url : row -> string option
val description : row -> string
val residuals : row -> string list
val with_credit : row -> credit -> row

val has_session_operation :
  session:Zellij_intent.session -> operation:operation -> bool

val lifecycle_name : lifecycle -> string
val credit_name : credit -> string
val operation_name : operation -> string
