# Implementation Plan: Hermes FPP Vision Architecture (H.265 RTP Upgrade)

## Goal Description
The objective is to upgrade the Swarm's computer vision pipeline from bandwidth-heavy MJPEG to a highly compressed **H.265 (HEVC) over RTP** streaming protocol. This drastically reduces the network load across the Tailscale mesh while maintaining the pure OCaml requirement (via FFI/bindings) and adhering to the FPP and Swarm execution mandates.

## User Review Required
> [!IMPORTANT]
> **Browser Compatibility & WebRTC**: Browsers cannot play raw RTP streams natively via an `<img>` or `<video src="rtp://...">` tag. To view the H.265 RTP stream in the HTML UI, the Dream backend must negotiate a **WebRTC** connection or transmux the RTP packets into a fragmented MP4 (fMP4) stream for the Media Source Extensions (MSE) API.
> 
> Furthermore, H.265 decoding is restricted in Chrome/Firefox natively; we must either rely on hardware acceleration in Safari/Edge, or fallback to a WebAssembly H.265 decoder in the Bonsai frontend. Please confirm this browser limitation is acceptable.

---

## 1. Architectural Changes (H.265 RTP Data Path)

```text
=============================================================================================================
                                     FRACTAL ATLAS (TAILSCALE MESH)                                          
=============================================================================================================

                   [ L4_M_Satellite: nuc-1 ]                             [ L4_M_Satellite: vm-1 ]            
                 +---------------------------+                         +---------------------------+         
                 |  Sensorium (GStreamer FFI)|                         |    Torch_FFI Satellite    |         
                 +---------------------------+                         +---------------------------+         
                   ^           |           |                             ^           |           ^           
  [Physical]       |           |           |     <H.265 RTP Packets>     |           |           |           
  /dev/video0 -----+           |           |       via Zenoh/RTP         |           |           |           
                               |           +============================>+           |           |           
                               |                                                     |           |           
                               |       <Data Path: JSON Bounding Boxes>              |           |           
                               +================== [Zenoh: kpi] =====================+           |           
                                                                                                 |           
                                                                                                 |           
=================================================================================================|===========
                                      [ L6_Projection: Dream + Bonsai ]                          |           
=================================================================================================|===========
                                                                |                                            
                                                                v                                            
                                +-----------------------------------------------------------+                
                                | <video> Element (WebRTC / fMP4 MSE)                       |                
                                | Dream WebRTC Signaling -> H.265 Render                    |                
                                +-----------------------------------------------------------+                
```

---

## 2. Declarative Config Mandate (R23)
We update the Ops config to explicitly declare H.265 and RTP boundaries.

#### [MODIFY] `modules/hermes_ops/ops_config.ml`
```ocaml
let elements = [
  ...
  (* Upgraded H.265 FPP Configuration *)
  { layer = L4_M_Satellite; purpose = "Vision_Capture"; consumer = "nuc-1_Eio"; supply = "v4l2src ! x265enc ! rtph265pay" };
  { layer = L6_Projection; purpose = "Dashboard_Render"; consumer = "Bonsai_UI"; supply = "webrtc://camera" };
]
```

---

## 3. The Typed Declarative Intent & Ontology
The FPP Builder is updated to request an H.265 compression codec.

#### [MODIFY] `projects/satellites/vision/vision_tracking_intent.ml`
```ocaml
open Hermes_harness_fractal_ontology
open Hermes_wiki_fpp

let build_intent () =
  let open Fpp.Intent.Builder in
  
  let nuc_supply = Ops_config.get_supply ~purpose:"Vision_Capture" in
  let vm_supply = Ops_config.get_supply ~purpose:"Torch_FFI" in
  
  (* The Sensorium now mandates H.265 HEVC *)
  let nuc_sensor = Sensorium.create ~host:"nuc-1" ~device:nuc_supply ~codec:Codec.H265 ~target_fps:30 in
  let vm_processor = ExternalSatellite.create ~host:"vm-1" ~engine:Torch_FFI ~model:vm_supply in
  
  (* The UI now mandates a WebRTC sink instead of MJPEG *)
  let web_dashboard = Dashboard.create ~route:"/camera" ~renderer:Bonsai_TyXML ~stream_type:Stream.WebRTC in
  
  create_intent "Vision_Tracking_Mission"
  |> add_node nuc_sensor
  |> add_node vm_processor
  |> add_node web_dashboard
  |> connect ~src:nuc_sensor ~dst:vm_processor ~via:ZenohMesh
  |> connect ~src:vm_processor ~dst:web_dashboard ~via:ZenohMesh
  |> build
```

---

## 4. OCaml Integration (GStreamer FFI)
Because we must use pure OCaml, we cannot rely on external bash scripts executing `ffmpeg`. We will utilize OCaml bindings to GStreamer (`ocaml-gstreamer` via FFI) to create the RTP payload directly in memory.

#### [NEW] `projects/satellites/vision/h265_capture.ml`
```ocaml
open Gstreamer
open Zenoh_ocaml

let capture_and_rtp_publish ~zenoh_session =
  let pub = Zenoh.declare_publisher zenoh_session "/swarm/vision/nuc1/h265rtp" in
  
  (* GStreamer Pipeline defined via FFI *)
  let pipeline = Pipeline.create "h265_rtp_pipeline" in
  let v4l2src = Element.factory_make "v4l2src" "source" in
  let x265enc = Element.factory_make "x265enc" "encoder" in
  let rtppay = Element.factory_make "rtph265pay" "payloader" in
  let appsink = Element.factory_make "appsink" "sink" in
  
  (* Pull RTP packets from appsink and push to Zenoh *)
  Appsink.set_callbacks appsink ~new_sample:(fun sample ->
    let buffer = Sample.get_buffer sample in
    Zenoh.put pub (Buffer.to_bytes buffer);
    Flow.Ok
  );
  
  Pipeline.set_state pipeline State.Playing
```

---

## Verification Plan

### Automated Tests
1.  **Ops Config Validation**: `dune exec modules/hermes_ops/ops_main.exe -- verify` to ensure `Codec.H265` and `Stream.WebRTC` are legally mapped.
2.  **GStreamer FFI Build**: `dune build projects/satellites/vision/` to verify linking against `libgstreamer-1.0`.

### Manual Verification
1.  Launch `./run_vision_mission.exe`.
2.  Navigate to `/camera` on an H.265-capable browser (e.g., Safari or Edge).
3.  Ensure the Bonsai UI successfully establishes the WebRTC signaling with Dream and decodes the H.265 payload.
