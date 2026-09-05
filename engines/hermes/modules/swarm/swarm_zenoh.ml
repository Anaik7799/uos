(** Zenoh Network Mesh for Swarm Topologist & Sensorium *)

type zenoh_topic =
  | Telemetry_Stream
  | CRDT_State_Vector
  | BFT_Heartbeat
  | Actuator_Command

let topic_to_string = function
  | Telemetry_Stream -> "swarm/sensorium/telemetry"
  | CRDT_State_Vector -> "swarm/topologist/crdt"
  | BFT_Heartbeat -> "swarm/sentinel/bft"
  | Actuator_Command -> "swarm/conductor/actuate"

(** Publishes a deterministic CRDT state vector over the Zenoh mesh *)
let publish_state_vector (digest : string) =
  let topic = topic_to_string CRDT_State_Vector in
  Printf.printf "[ZENOH PUB] %s -> %s\n" topic digest;
  (* In a real deployment, this binds to the Rust/C Zenoh FFI *)
  true

(** Publishes general telemetry data to control and monitor the pipeline *)
let publish_telemetry (payload : string) =
  let topic = topic_to_string Telemetry_Stream in
  Printf.printf "[ZENOH TELEMETRY PUB] %s -> %s\n" topic payload;
  true

(** Subscribes to 20kHz physical sensor streams without blocking the OODA loop *)
let subscribe_telemetry (callback : string -> unit) =
  let topic = topic_to_string Telemetry_Stream in
  Printf.printf "[ZENOH SUB] %s listening at 20kHz\n" topic;
  (* Dummy trigger for simulation *)
  callback "SENSOR_DATA_FRAME_001"
