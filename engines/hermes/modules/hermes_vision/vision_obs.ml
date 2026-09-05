(* Fractal ontology of OBS Studio. See the .mli: OBS is a compositor,
   so a frame it cannot produce is dropped rather than awaited. *)

type source_kind =
  | Media_file | Display_capture | Window_capture | Video_device | Browser_source | Image_source

type output_kind = Stream_rtmp | Record_file | Virtual_camera

type capability =
  | Scene_composite
  | Source of source_kind
  | Output of output_kind
  | Encoder_x264
  | Stats_counters
  | Websocket_control

let source_kinds =
  [ Media_file; Display_capture; Window_capture; Video_device; Browser_source; Image_source ]

let output_kinds = [ Stream_rtmp; Record_file; Virtual_camera ]

let capabilities =
  (Scene_composite :: List.map (fun s -> Source s) source_kinds)
  @ List.map (fun o -> Output o) output_kinds
  @ [ Encoder_x264; Stats_counters; Websocket_control ]

let source_name = function
  | Media_file -> "media_file" | Display_capture -> "display_capture"
  | Window_capture -> "window_capture" | Video_device -> "video_device"
  | Browser_source -> "browser_source" | Image_source -> "image_source"

let output_name = function
  | Stream_rtmp -> "stream_rtmp" | Record_file -> "record_file"
  | Virtual_camera -> "virtual_camera"

let name = function
  | Scene_composite -> "scene_composite"
  | Source s -> "source." ^ source_name s
  | Output o -> "output." ^ output_name o
  | Encoder_x264 -> "encoder_x264"
  | Stats_counters -> "stats_counters"
  | Websocket_control -> "websocket_control"

let level = function
  | Scene_composite -> Fractal_diagnostic.L2_capability
  | Source _ -> Fractal_diagnostic.L1_family
  | Output Record_file -> Fractal_diagnostic.L3_contract
  | Output _ -> Fractal_diagnostic.L4_fixture
  | Encoder_x264 -> Fractal_diagnostic.L2_capability
  | Stats_counters -> Fractal_diagnostic.L5_trace
  | Websocket_control -> Fractal_diagnostic.LX_control

(* Only the recorded file is a contract this repository can be wrong
   about. A GPU that cannot composite, an ingest that refuses, a camera
   that is absent — all Environment, and under R5 they block credit and
   never deny it. *)
let origin = function
  | Output Record_file -> Fractal_diagnostic.Implementation
  | Stats_counters -> Fractal_diagnostic.Evidence
  | Websocket_control -> Fractal_diagnostic.Control
  | Scene_composite | Source _ | Output _ | Encoder_x264 -> Fractal_diagnostic.Environment

(* OBS composites through OpenGL; so does anything embedding a browser. *)
let gl_required = function
  | Scene_composite | Source Display_capture | Source Window_capture | Source Browser_source ->
      true
  | Source _ | Output _ | Encoder_x264 | Stats_counters | Websocket_control -> false

let law = function
  | Scene_composite -> "the scene is drawn at the configured frame rate with every source visible"
  | Source Media_file -> "the file decodes and its pictures appear in the composite"
  | Source Display_capture -> "the screen's pixels reach the composite"
  | Source Window_capture -> "the named window's pixels reach the composite"
  | Source Video_device -> "the device opens and delivers frames at the negotiated format"
  | Source Browser_source -> "the embedded page renders and its pixels reach the composite"
  | Source Image_source -> "the still decodes and is drawn"
  | Output Stream_rtmp -> "encoded frames are accepted by the ingest and acknowledged"
  | Output Record_file -> "the file grows and its container is finalised on stop"
  | Output Virtual_camera -> "the loopback device exists and other programs can open it"
  | Encoder_x264 -> "frames are encoded within the frame budget, with none skipped"
  | Stats_counters -> "all three loss counters are readable"
  | Websocket_control -> "a command is authenticated, applied, and its effect is observable"

(* Every hazard is a composite that keeps running and ships something
   incomplete — the failure mode a transform cannot have. *)
let hazard = function
  | Scene_composite ->
      "the scene renders at a reduced rate and the output stays continuous, so loss is invisible \
       without the counters"
  | Source Media_file -> "the file ends and the source renders BLACK rather than stopping the scene"
  | Source Display_capture -> "capture succeeds on a blanked or locked screen and yields black frames"
  | Source Window_capture ->
      "the window is minimised or closed and the source renders BLACK while remaining 'active'"
  | Source Video_device -> "the device is held by another process and yields the last frame forever"
  | Source Browser_source -> "the page fails to load and renders transparent, compositing as nothing"
  | Source Image_source -> "a missing file renders as an empty layer without a diagnostic"
  | Output Stream_rtmp ->
      "the ingest drops the connection and OBS RECONNECTS silently, so the output looks live \
       through a gap"
  | Output Record_file ->
      "the process is killed rather than stopped, leaving an unfinalised container that most \
       players still open"
  | Output Virtual_camera -> "the loopback module is absent and the output silently does nothing"
  | Encoder_x264 ->
      "the encoder falls behind and frames are SKIPPED before encoding, which the output stream \
       cannot reveal"
  | Stats_counters -> "the counters read zero before a run starts and after one that never began"
  | Websocket_control -> "a command is accepted and acknowledged without being applied"

let serves = function
  | Source _ -> Vision_ontology.Source
  | Scene_composite | Encoder_x264 -> Vision_ontology.Encode
  | Output Record_file -> Vision_ontology.Package
  | Output _ -> Vision_ontology.Serve
  | Stats_counters -> Vision_ontology.Observe
  | Websocket_control -> Vision_ontology.Play

type loss = Render_lag | Encoding_lag | Network_drop

let losses = [ Render_lag; Encoding_lag; Network_drop ]

let loss_name = function
  | Render_lag -> "render_lag" | Encoding_lag -> "encoding_lag" | Network_drop -> "network_drop"

(* Three faults, three responses. None is Implementation: a frame OBS
   could not composite says nothing about whether our pipeline is
   correct. *)
let loss_origin = function
  | Render_lag -> Fractal_diagnostic.Environment
  | Encoding_lag -> Fractal_diagnostic.Control
  | Network_drop -> Fractal_diagnostic.Environment

let loss_meaning = function
  | Render_lag -> "the compositor could not draw the scene in time — the GPU is the constraint"
  | Encoding_lag ->
      "frames were SKIPPED before encoding because the encoder fell behind — the CPU budget is \
       the constraint"
  | Network_drop ->
      "frames were encoded and then discarded because the output could not ship them — the link \
       is the constraint"

type stats = { rendered : int; render_missed : int; encoded : int; skipped : int; dropped : int }

(* NOT `encoded`: an encoded frame may still be discarded by the network
   stage afterwards, so encoded overstates what actually arrived. *)
let delivered s = s.encoded - s.dropped

let losses_observed s =
  List.filter
    (fun (_, n) -> n > 0)
    [ (Render_lag, s.render_missed); (Encoding_lag, s.skipped); (Network_drop, s.dropped) ]

let intact s = losses_observed s = []

let render () =
  let b = Buffer.create 2048 in
  Buffer.add_string b "obs ontology (compositor: loss is silent and the output stays continuous)\n";
  List.iter
    (fun c ->
      Buffer.add_string b
        (Printf.sprintf "  %-26s %-14s %-12s gl=%b serves=%s\n    law:    %s\n    hazard: %s\n"
           (name c)
           (Fractal_diagnostic.level_name (level c))
           (Fractal_diagnostic.origin_name (origin c))
           (gl_required c)
           (Vision_ontology.stage_name (serves c))
           (law c) (hazard c)))
    capabilities;
  Buffer.add_string b "  loss counters:\n";
  List.iter
    (fun l ->
      Buffer.add_string b
        (Printf.sprintf "    %-14s %-12s %s\n" (loss_name l)
           (Fractal_diagnostic.origin_name (loss_origin l))
           (loss_meaning l)))
    losses;
  Buffer.contents b
