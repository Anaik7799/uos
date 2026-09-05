(* L1 Declarative Intent: Comprehensive Vision Pipeline Envelope *)

type webrtc_signaling_strategy =
  | Native_Datarhei
  | ICE_Relay of string list
  | Strict_Local

type telemetry_hook =
  | Capture_Jitter
  | Capture_Buffer
  | Capture_Decoded_Frames
  | Emit_All_To_Console

type player_engine =
  | OvenPlayer of { version : string; debug : bool; fallback : bool }
  | Custom of string

type vision_source = {
  label : string;
  endpoint : string;
  stream_type : [ `WebRTC | `HLS | `DASH ];
}

type zenoh_routing_mode =
  | Peer_to_Peer
  | Routed_via_Broker of string
  | Multicast_Scout

type zenoh_topology = {
  sensor_pub_key : string;
  inference_sub_pub_key : string;
  telemetry_pub_key : string;
  webrtc_signaling_key : string;
  routing_mode : zenoh_routing_mode;
}

type pipeline_envelope = {
  host : string;
  source : vision_source;
  engine : player_engine;
  signaling : webrtc_signaling_strategy;
  telemetry : telemetry_hook list;
  zenoh : zenoh_topology;
  max_retry : int;
  connection_timeout_ms : int;
}

let default_hardened_envelope = {
  host = "vm-1.tail55d152.ts.net";
  source = {
    label = "Datarhei WebRTC";
    endpoint = "ws://localhost:3333/app/stream";
    stream_type = `WebRTC;
  };
  engine = OvenPlayer { version = "0.10.36"; debug = true; fallback = true };
  signaling = Native_Datarhei;
  telemetry = [ Emit_All_To_Console; Capture_Jitter; Capture_Buffer ];
  zenoh = {
    sensor_pub_key = "vision/nuc-1/raw";
    inference_sub_pub_key = "vision/vm-1/inference";
    telemetry_pub_key = "vision/kpi/vm-1";
    webrtc_signaling_key = "vision/signaling/datarhei";
    routing_mode = Peer_to_Peer;
  };
  max_retry = 4;
  connection_timeout_ms = 10000;
}

let synthesize_html_config (env : pipeline_envelope) : string =
  let debug_flag = match env.engine with
    | OvenPlayer { debug = true; _ } -> "true"
    | _ -> "false"
  in
  Printf.sprintf {|
    const playerConfig = {
      sources: [{ label: "%s", type: "webrtc", file: "%s" }],
      autoFallback: true,
      debug: %s,
      webrtcConfig: {
        timeoutMaxRetry: %d,
        connectionTimeout: %d
      }
    };
  |}
    env.source.label
    env.source.endpoint
    debug_flag
    env.max_retry
    env.connection_timeout_ms
