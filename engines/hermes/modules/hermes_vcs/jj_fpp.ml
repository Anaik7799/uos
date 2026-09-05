type port_role = Command_input | Command_response | Event_output | Telemetry_output
type port = { port_id : string; role : port_role; port_type : string }
let port_role port = port.role
let port_id port = port.port_id
let port_type port = port.port_type

type command_guard =
  | Exact_identity
  | Policy_permit
  | Approval_valid
  | Writer_lease_valid
  | Resources_bounded
  | Bridge_admitted
  | Remote_cas_proved

type command = { command_id : string; guards : command_guard list }
let command_id command = command.command_id
let command_guards command = command.guards

type state =
  | Prepared
  | Admitted
  | Running
  | Readback_pending
  | Succeeded
  | Refused
  | Failed
  | Unavailable

type event = { event_id : string; event_type : string }
let event_id event = event.event_id
type channel = { channel_id : string; channel_type : string; bound : int }
let channel_id channel = channel.channel_id
type metric = { metric_id : string; unit_name : string }
let metric_id metric = metric.metric_id

type activation = Declared_unavailable | Implemented_unavailable | Current

type operation_fragment = {
  operation : Jj_operation.t;
  operation_key : string;
  command : command;
  ports : port list;
  states : state list;
  events : event list;
  channels : channel list;
  metrics : metric list;
  activation : activation;
}

let operation row = row.operation
let command row = row.command
let ports row = row.ports
let states row = row.states
let events row = row.events
let channels row = row.channels
let metrics row = row.metrics
let activation row = row.activation

type allocation = Inherited_runtime_owner
type fragment = { rows : operation_fragment list; allocation : allocation }

let operation_prefix key suffix = "jj." ^ key ^ "." ^ suffix

let derive ?key_override operation =
  let declaration = Jj_operation.declaration operation in
  let key = Option.value key_override ~default:declaration.key in
  let prefix suffix = operation_prefix key suffix in
  let guards =
    [ Exact_identity; Policy_permit; Approval_valid; Writer_lease_valid;
      Resources_bounded; Bridge_admitted ]
    @
    match declaration.capability with
    | Jj_operation.Capability_remote_publish -> [ Remote_cas_proved ]
    | _ -> []
  in
  let port role suffix port_type =
    { port_id = prefix suffix; role; port_type }
  in
  let event suffix event_type =
    { event_id = prefix ("event." ^ suffix); event_type }
  in
  let channel suffix channel_type bound =
    { channel_id = prefix ("channel." ^ suffix); channel_type; bound }
  in
  let metric suffix unit_name =
    { metric_id = prefix ("metric." ^ suffix); unit_name }
  in
  { operation;
    operation_key = key;
    command = { command_id = prefix "command"; guards };
    ports =
      [ port Command_input "port.command" "JjCommand";
        port Command_response "port.response" "JjCommandResponse";
        port Event_output "port.event" "JjLifecycleEvent";
        port Telemetry_output "port.telemetry" "JjTelemetry" ];
    states =
      [ Prepared; Admitted; Running; Readback_pending; Succeeded; Refused;
        Failed; Unavailable ];
    events =
      [ event "prepared" "Prepared"; event "refused" "Refused";
        event "started" "Started"; event "applied" "Applied";
        event "readback" "Readback"; event "failed" "Failed" ];
    channels =
      [ channel "attempts" "U32" declaration.budget.max_attempts;
        channel "output-bytes" "U64" declaration.budget.max_output_bytes;
        channel "duration-ms" "U64" declaration.budget.timeout_ms;
        channel "terminal" "Bool" 1 ];
    metrics =
      [ metric "attempts" "count"; metric "output-bytes" "bytes";
        metric "duration-ms" "milliseconds"; metric "terminal" "boolean" ];
    activation =
      match declaration.activation with
      | Jj_operation.Unavailable_until_bridge -> Declared_unavailable
      | Jj_operation.Implemented_unavailable -> Implemented_unavailable }

let fragment =
  { rows = List.map derive Jj_operation.all;
    allocation = Inherited_runtime_owner }

let operations fragment = fragment.rows
let allocation fragment = fragment.allocation

let state_name = function
  | Prepared -> "prepared" | Admitted -> "admitted" | Running -> "running"
  | Readback_pending -> "readback-pending" | Succeeded -> "succeeded"
  | Refused -> "refused" | Failed -> "failed" | Unavailable -> "unavailable"

let guard_name = function
  | Exact_identity -> "exact-identity" | Policy_permit -> "policy-permit"
  | Approval_valid -> "approval-valid" | Writer_lease_valid -> "writer-lease-valid"
  | Resources_bounded -> "resources-bounded" | Bridge_admitted -> "bridge-admitted"
  | Remote_cas_proved -> "remote-cas-proved"

let activation_name = function
  | Declared_unavailable -> "declared-unavailable"
  | Implemented_unavailable -> "implemented-unavailable"
  | Current -> "current"

let role_name = function
  | Command_input -> "command-input" | Command_response -> "command-response"
  | Event_output -> "event-output" | Telemetry_output -> "telemetry-output"

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat ""

let identities fragment =
  fragment.rows
  |> List.concat_map (fun row ->
       [ row.command.command_id ]
       @ List.map (fun port -> port.port_id) row.ports
       @ List.map (fun event -> event.event_id) row.events
       @ List.map (fun channel -> channel.channel_id) row.channels
       @ List.map (fun metric -> metric.metric_id) row.metrics
       @ List.map
           (fun state -> operation_prefix row.operation_key ("state." ^ state_name state))
           row.states)

let digest fragment =
  fragment.rows
  |> List.map (fun row ->
       length_frame
         ([ row.operation_key; row.command.command_id;
            activation_name row.activation ]
          @ List.map guard_name row.command.guards
          @ List.concat_map
              (fun port -> [ port.port_id; role_name port.role; port.port_type ])
              row.ports
          @ List.map state_name row.states
          @ List.concat_map
              (fun event -> [ event.event_id; event.event_type ]) row.events
          @ List.concat_map
              (fun channel ->
                 [ channel.channel_id; channel.channel_type; string_of_int channel.bound ])
              row.channels
          @ List.concat_map
              (fun metric -> [ metric.metric_id; metric.unit_name ]) row.metrics))
  |> String.concat ""
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let source_digest = digest fragment

module For_test = struct
  let digest_with_operation_key operation replacement =
    { fragment with
      rows =
        List.map
          (fun row ->
             if row.operation = operation then derive ~key_override:replacement operation
             else row)
          fragment.rows }
    |> digest
end
