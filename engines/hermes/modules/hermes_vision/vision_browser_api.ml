(* Fractal ontology of the browser video surface. See the .mli. *)

open Vision_ontology

type capability =
  | Media_element
  | Codec_support
  | Frame_callback
  | Playback_quality
  | Capture_stream
  | Media_recorder
  | Media_source
  | Web_codecs
  | Web_rtc

let capabilities =
  [ Media_element; Codec_support; Frame_callback; Playback_quality; Capture_stream;
    Media_recorder; Media_source; Web_codecs; Web_rtc ]

let name = function
  | Media_element -> "media_element"
  | Codec_support -> "codec_support"
  | Frame_callback -> "frame_callback"
  | Playback_quality -> "playback_quality"
  | Capture_stream -> "capture_stream"
  | Media_recorder -> "media_recorder"
  | Media_source -> "media_source"
  | Web_codecs -> "web_codecs"
  | Web_rtc -> "web_rtc"

let level = function
  | Media_element -> Fractal_diagnostic.L3_contract
  | Codec_support -> Fractal_diagnostic.L3_contract
  | Frame_callback -> Fractal_diagnostic.L5_trace
  | Playback_quality -> Fractal_diagnostic.L5_trace
  | Capture_stream -> Fractal_diagnostic.L6_receipt
  | Media_recorder -> Fractal_diagnostic.L6_receipt
  | Media_source -> Fractal_diagnostic.L4_fixture
  | Web_codecs -> Fractal_diagnostic.L5_trace
  | Web_rtc -> Fractal_diagnostic.L4_fixture

(* NONE of these is Implementation. A browser without a decoder says
   nothing about whether our pipeline is correct; recording it as
   Implementation would let a missing codec deny parity credit (R5).
   Evidence origin for the capture capabilities, because when those fail
   it is our EVIDENCE that is missing, not the system under test. *)
let origin = function
  | Capture_stream | Media_recorder | Frame_callback | Playback_quality ->
      Fractal_diagnostic.Evidence
  | Media_element | Codec_support | Media_source | Web_codecs | Web_rtc ->
      Fractal_diagnostic.Environment

let law = function
  | Media_element -> "a <video> element exists and exposes its media interface"
  | Codec_support -> "the engine reports it can decode the codec we actually serve"
  | Frame_callback -> "a per-composited-frame callback fires and carries mediaTime"
  | Playback_quality -> "dropped and total frame counters are readable and advance"
  | Capture_stream -> "captureStream yields a live track carrying decoded video"
  | Media_recorder -> "MediaRecorder accepts that track and emits non-empty blobs"
  | Media_source -> "MediaSource accepts a SourceBuffer for our mime and codec"
  | Web_codecs -> "VideoDecoder is configurable for the codec and emits VideoFrames"
  | Web_rtc -> "an RTCPeerConnection can be constructed and negotiate a video track"

(* Each hazard is the state in which the symbol is present and the
   capability is useless — which is why none of the probes tests for the
   symbol alone. *)
let hazard = function
  | Media_element -> "the element exists on every engine and decodes nothing without a codec"
  | Codec_support -> "canPlayType returns the empty string for 'no', which is falsy but not absent"
  | Frame_callback -> "the function exists and is never called because no frame is ever composited"
  | Playback_quality -> "the counters read zero both when playback is perfect and when it never began"
  | Capture_stream -> "captureStream returns a stream whose video track list is empty"
  | Media_recorder -> "recording starts and every dataavailable blob has size zero"
  | Media_source -> "MediaSource exists but isTypeSupported is false for the codec we serve"
  | Web_codecs -> "VideoDecoder constructs and configure() rejects asynchronously"
  | Web_rtc -> "the peer connection constructs and never negotiates a media section"

let serves = function
  | Media_element | Codec_support | Media_source | Web_rtc -> Play
  | Frame_callback | Playback_quality -> Play
  | Capture_stream | Media_recorder | Web_codecs -> Observe

let required_for = function
  | Play -> [ Media_element; Codec_support ]
  (* Observe needs a way to SEE frames; without one, the stage is
     Unknown, never Absent — nothing was proved either way. *)
  | Observe -> [ Frame_callback; Capture_stream; Media_recorder ]
  | Source | Encode | Package | Serve -> []

(* The probes answer the LAW, not the symbol. Generated via Vision_js so
   no JavaScript is authored here. *)
let probe_expression c =
  let open Vision_js in
  let v = raw_ident "document.querySelector(\"video\")" in
  let present e = ternary e (bool_ true) (bool_ false) in
  let body =
    match c with
    | Media_element -> obj [ ("ok", present v) ]
    (* canPlayType returns "", "maybe" or "probably" — "" is falsy but
       the field is present, so a truthiness test on the symbol passes
       while the engine cannot decode *)
    | Codec_support ->
        obj [ ("webm", call v "canPlayType" [ str "video/webm; codecs=\"vp8\"" ]);
              ("mp4", call v "canPlayType" [ str "video/mp4; codecs=\"avc1.42E01E\"" ]) ]
    | Frame_callback -> obj [ ("ok", present (field v "requestVideoFrameCallback")) ]
    | Playback_quality ->
        obj [ ("dropped", field (call v "getVideoPlaybackQuality" []) "droppedVideoFrames");
              ("total", field (call v "getVideoPlaybackQuality" []) "totalVideoFrames") ]
    (* a stream with zero video tracks is the declared hazard, so count
       the tracks rather than test the method *)
    | Capture_stream ->
        obj [ ("tracks", field (call (call v "captureStream" []) "getVideoTracks" []) "length") ]
    | Media_recorder ->
        obj [ ("ok", raw_ident "(typeof MediaRecorder !== \"undefined\")");
              ("webm", raw_ident "(typeof MediaRecorder !== \"undefined\" && MediaRecorder.isTypeSupported(\"video/webm\"))") ]
    | Media_source ->
        obj [ ("ok", raw_ident "(typeof MediaSource !== \"undefined\")");
              ("vp8", raw_ident "(typeof MediaSource !== \"undefined\" && MediaSource.isTypeSupported(\"video/webm; codecs=\\\"vp8\\\"\"))") ]
    | Web_codecs -> obj [ ("ok", raw_ident "(typeof VideoDecoder !== \"undefined\")") ]
    | Web_rtc -> obj [ ("ok", raw_ident "(typeof RTCPeerConnection !== \"undefined\")") ]
  in
  Printf.sprintf "() => (%s)" (render body)

type engine = Chrome | Edge | Chromium_oss | Firefox | Safari

let engines = [ Chrome; Edge; Chromium_oss; Firefox; Safari ]

let engine_name = function
  | Chrome -> "chrome"
  | Edge -> "edge"
  | Chromium_oss -> "chromium-oss"
  | Firefox -> "firefox"
  | Safari -> "safari"

(* Vendor-documented support: an ORACLE claim, never a measurement. A
   disagreement between this and probe_expression is the finding. *)
let declared engine cap =
  match (engine, cap) with
  (* requestVideoFrameCallback is Chromium+Safari; Firefox has not
     shipped it, which is why the browser oracle must be Chromium *)
  | Firefox, Frame_callback -> false
  | Firefox, Web_codecs -> true
  | Safari, Web_codecs -> true
  | Safari, Media_recorder -> true
  | _, (Media_element | Codec_support | Playback_quality | Capture_stream | Media_source | Web_rtc)
    -> true
  | _, (Frame_callback | Media_recorder | Web_codecs) -> true

(* The split that matters: an open-source Chromium build frequently ships
   without H.264, and that failure presents exactly as the Play hazard —
   a player reporting readiness and painting nothing. *)
let codecs = function
  | Chrome -> [ "vp8"; "vp9"; "av1"; "opus"; "h264"; "aac" ]
  | Edge -> [ "vp8"; "vp9"; "av1"; "opus"; "h264"; "aac"; "hevc" ]
  | Chromium_oss -> [ "vp8"; "vp9"; "av1"; "opus" ]
  | Firefox -> [ "vp8"; "vp9"; "av1"; "opus"; "h264" ]
  | Safari -> [ "h264"; "aac"; "hevc"; "vp9"; "av1" ]

let universal_codecs () =
  match engines with
  | [] -> []
  | first :: rest ->
      List.filter (fun c -> List.for_all (fun e -> List.mem c (codecs e)) rest) (codecs first)

let render () =
  let b = Buffer.create 2048 in
  Buffer.add_string b "browser video surface\n";
  List.iter
    (fun c ->
      Buffer.add_string b
        (Printf.sprintf "  %-18s %-14s %-12s serves=%s\n    law:    %s\n    hazard: %s\n"
           (name c)
           (Fractal_diagnostic.level_name (level c))
           (Fractal_diagnostic.origin_name (origin c))
           (stage_name (serves c)) (law c) (hazard c)))
    capabilities;
  Buffer.add_string b
    (Printf.sprintf "  universal codecs: %s\n" (String.concat ", " (universal_codecs ())));
  Buffer.contents b
