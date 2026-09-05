(** Opaque FPP fragment derived from the complete Jujutsu operation registry.
    It is a projection only: runtime ownership and address allocation belong
    to the future atomic execution cone. *)

type port_role = Command_input | Command_response | Event_output | Telemetry_output
type port
val port_role : port -> port_role
val port_id : port -> string
val port_type : port -> string

type command_guard =
  | Exact_identity
  | Policy_permit
  | Approval_valid
  | Writer_lease_valid
  | Resources_bounded
  | Bridge_admitted
  | Remote_cas_proved

type command
val command_id : command -> string
val command_guards : command -> command_guard list

type state =
  | Prepared
  | Admitted
  | Running
  | Readback_pending
  | Succeeded
  | Refused
  | Failed
  | Unavailable

type event
val event_id : event -> string
type channel
val channel_id : channel -> string
type metric
val metric_id : metric -> string

type activation = Declared_unavailable | Implemented_unavailable | Current
type operation_fragment
val operation : operation_fragment -> Jj_operation.t
val command : operation_fragment -> command
val ports : operation_fragment -> port list
val states : operation_fragment -> state list
val events : operation_fragment -> event list
val channels : operation_fragment -> channel list
val metrics : operation_fragment -> metric list
val activation : operation_fragment -> activation

type allocation = Inherited_runtime_owner
type fragment
val fragment : fragment
val operations : fragment -> operation_fragment list
val allocation : fragment -> allocation
val identities : fragment -> string list
val digest : fragment -> string
val source_digest : string

module For_test : sig
  val digest_with_operation_key : Jj_operation.t -> string -> string
end

