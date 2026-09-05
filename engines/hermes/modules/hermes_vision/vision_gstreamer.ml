(* Fractal ontology of GStreamer. See the .mli for why this is shaped
   around states rather than stages. *)

type state = Null | Ready | Paused | Playing

let states = [ Null; Ready; Paused; Playing ]

let state_name = function
  | Null -> "NULL" | Ready -> "READY" | Paused -> "PAUSED" | Playing -> "PLAYING"

let index s =
  let rec go i = function [] -> i | x :: r -> if x = s then i else go (i + 1) r in
  go 0 states

(* Adjacent only, in both directions. GStreamer refuses NULL -> PLAYING
   as one change; modelling it as legal would let a caller believe a
   pipeline reached PLAYING without ever prerolling. *)
let legal_transition a b = abs (index a - index b) = 1

type change = Success | Async | No_preroll | Failure of string

let change_name = function
  | Success -> "SUCCESS" | Async -> "ASYNC" | No_preroll -> "NO_PREROLL"
  | Failure _ -> "FAILURE"

(* ASYNC IS NOT SUCCESS. The change was accepted and has not happened;
   claiming the state now is how a pipeline is reported working while it
   produces nothing. NO_PREROLL is also not arrival: it says this live
   source will never preroll, so waiting for preroll hangs forever. *)
let reached = function Success -> true | Async | No_preroll | Failure _ -> false

type element =
  | Src_file | Src_test | Src_udp
  | Decode_bin | Convert | Encode_h264 | Encode_vp8
  | Sink_hls | Sink_udp | Sink_app

let elements =
  [ Src_file; Src_test; Src_udp; Decode_bin; Convert; Encode_h264; Encode_vp8;
    Sink_hls; Sink_udp; Sink_app ]

let element_name = function
  | Src_file -> "filesrc" | Src_test -> "videotestsrc" | Src_udp -> "udpsrc"
  | Decode_bin -> "decodebin" | Convert -> "videoconvert"
  | Encode_h264 -> "x264enc" | Encode_vp8 -> "vp8enc"
  | Sink_hls -> "hlssink2" | Sink_udp -> "udpsink" | Sink_app -> "appsink"

let level = function
  | Src_file | Src_test | Src_udp -> Fractal_diagnostic.L1_family
  | Decode_bin | Convert -> Fractal_diagnostic.L2_capability
  | Encode_h264 | Encode_vp8 -> Fractal_diagnostic.L2_capability
  | Sink_hls -> Fractal_diagnostic.L3_contract
  | Sink_udp -> Fractal_diagnostic.L4_fixture
  | Sink_app -> Fractal_diagnostic.L6_receipt

(* Only the sinks whose contract THIS repository defines may be
   Implementation. A missing plugin or an unreachable port is
   Environment: it proves nothing about whether our pipeline is
   correct, and under R5 may block credit but never deny it. *)
let origin = function
  | Sink_hls -> Fractal_diagnostic.Implementation
  | Sink_app -> Fractal_diagnostic.Evidence
  | Sink_udp -> Fractal_diagnostic.Control
  | Src_file | Src_test | Src_udp | Decode_bin | Convert | Encode_h264 | Encode_vp8 ->
      Fractal_diagnostic.Environment

let law = function
  | Src_file -> "the file opens and pushes buffers downstream"
  | Src_test -> "a synthetic pattern is generated at the negotiated caps"
  | Src_udp -> "datagrams arrive and become buffers with increasing timestamps"
  | Decode_bin -> "a decoder is selected AND its dynamic pad is linked downstream"
  | Convert -> "upstream caps are converted to something the encoder accepts"
  | Encode_h264 -> "raw frames become an h264 elementary stream"
  | Encode_vp8 -> "raw frames become a vp8 elementary stream"
  | Sink_hls -> "a playlist is written naming segments that exist and are non-empty"
  | Sink_udp -> "packets leave the host toward the declared destination"
  | Sink_app -> "buffers are handed to our code and are actually consumed"

(* Every one of these is a pipeline that RUNS and produces nothing. None
   raises an error, which is precisely why each needs a probe. *)
let hazard = function
  | Src_file -> "the file opens and the pipeline stays PAUSED forever, never prerolling"
  | Src_test -> "the pattern generates at caps nothing downstream can accept, and negotiation stalls"
  | Src_udp -> "the socket binds and no datagram ever arrives, which is indistinguishable from idle"
  | Decode_bin ->
      "the DYNAMIC pad is never linked, so no data flows and no error is ever posted — the \
       classic GStreamer silent hang"
  | Convert -> "conversion succeeds into caps the encoder then refuses, stalling negotiation"
  | Encode_h264 -> "the encoder buffers input and emits nothing while the bus stays silent"
  | Encode_vp8 -> "the encoder runs at a bitrate that produces frames nothing can decode"
  | Sink_hls -> "a playlist is written naming segments already deleted by the rolling window"
  | Sink_udp -> "packets are sent to a black hole; udp gives no delivery signal at all"
  | Sink_app -> "buffers arrive with no callback attached and are silently dropped"

let serves = function
  | Src_file | Src_test | Src_udp -> Vision_ontology.Source
  | Decode_bin | Convert -> Vision_ontology.Encode
  | Encode_h264 | Encode_vp8 -> Vision_ontology.Encode
  | Sink_hls -> Vision_ontology.Package
  | Sink_udp -> Vision_ontology.Serve
  | Sink_app -> Vision_ontology.Observe

type pipeline = { elements : element list; properties : (string * string) list }

let is_source = function Src_file | Src_test | Src_udp -> true | _ -> false
let is_sink = function Sink_hls | Sink_udp | Sink_app -> true | _ -> false
let is_encoder = function Encode_h264 | Encode_vp8 -> true | _ -> false
let produces_raw = function Src_test | Convert -> true | _ -> false

let description p =
  String.concat " ! " (List.map element_name p.elements)

(* An argument VECTOR, never a shell string: gst-launch syntax is full of
   characters a shell would eat, and a property value containing a space
   must not become two arguments. *)
let argv p =
  let props =
    List.map (fun (k, v) -> Printf.sprintf "%s=%s" k v) p.properties
  in
  let rec interleave = function
    | [] -> []
    | [ e ] -> [ element_name e ]
    | e :: rest -> element_name e :: "!" :: interleave rest
  in
  ("gst-launch-1.0" :: "-q" :: interleave p.elements) @ props

let well_formed p =
  match p.elements with
  | [] -> Error "an empty pipeline links nothing"
  | first :: _ when not (is_source first) -> Error "a pipeline must begin with a source"
  | _ ->
      let last = List.nth p.elements (List.length p.elements - 1) in
      if not (is_sink last) then Error "a pipeline must end with a sink"
      else
        (* an encoder needs raw video in front of it; without that the
           link fails at runtime as a hang, not as an error *)
        let rec check prev = function
          | [] -> Ok p
          | e :: rest ->
              if is_encoder e && not (match prev with Some x -> produces_raw x || x = Decode_bin | None -> false)
              then Error (element_name e ^ " has nothing producing raw video in front of it")
              else check (Some e) rest
        in
        check None p.elements

let test_to_hls ~dir =
  { elements = [ Src_test; Convert; Encode_h264; Sink_hls ];
    properties = [ ("location", Filename.concat dir "gst%05d.ts");
                   ("playlist-location", Filename.concat dir "gst.m3u8") ] }

let file_to_hls ~path ~dir =
  { elements = [ Src_file; Decode_bin; Convert; Encode_h264; Sink_hls ];
    properties = [ ("location", path);
                   ("playlist-location", Filename.concat dir "gst.m3u8") ] }

let render () =
  let b = Buffer.create 2048 in
  Buffer.add_string b "gstreamer ontology\n  states: ";
  Buffer.add_string b (String.concat " -> " (List.map state_name states));
  Buffer.add_string b "\n";
  List.iter
    (fun e ->
      Buffer.add_string b
        (Printf.sprintf "  %-14s %-14s %-12s serves=%s\n    law:    %s\n    hazard: %s\n"
           (element_name e)
           (Fractal_diagnostic.level_name (level e))
           (Fractal_diagnostic.origin_name (origin e))
           (Vision_ontology.stage_name (serves e))
           (law e) (hazard e)))
    elements;
  Buffer.contents b
