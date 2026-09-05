# Swarm Vision Satellite: Video Processing Implementation Plan

## Goal Description
The objective is to architect and deploy a **Vision Satellite** (one of the $M$ external nodes in our 15+N+M topology) to process real-time video streams from the Logitech StreamCam currently attached to `nuc-1` (`/dev/video0`). 

To maintain the mathematical safety proofs of the Swarm, heavy Computer Vision (CV) inference must run *outside* the OCaml 5 core. The video processing must be bridged via the Eclipse Zenoh data mesh, allowing the core Swarm to treat the vision inferences as standard asynchronous telemetry.

## User Review Required
> [!IMPORTANT]
> **Video Encoding**: Streaming raw 1080p frames over Zenoh consumes massive bandwidth. We propose using H.264 hardware encoding on `nuc-1` (via GStreamer) and decoding on the Vision Satellite, rather than passing raw MJPEG frames. Please approve this encoding step.

> [!CAUTION]
> **GPU Allocation**: Which Tailscale node will run the Vision Satellite? If `dev-1` has an NVIDIA GPU, we should run the Satellite there, while `nuc-1` simply acts as a Zenoh publisher.

## Open Questions
1. **Model Architecture**: Do we want to run object detection (e.g., YOLOv8), semantic segmentation, or simple motion tracking on this stream?
2. **Satellite Language**: Python is the standard for ML ecosystems (PyTorch/OpenCV). Is Python approved for the $M$ satellite, provided it strictly communicates via Zenoh pub/sub?

---

## Proposed Changes

### Component 1: `nuc-1` Edge Publisher (Rust/Python)
We will deploy a lightweight Zenoh publisher directly on `nuc-1` whose sole job is to capture `/dev/video0` and push it to the mesh.

#### [NEW] `projects/satellites/vision/edge_capture.py`
```python
# Pseudo-code for nuc-1 capture node
import cv2
import zenoh

session = zenoh.open()
pub = session.declare_publisher("swarm/telemetry/vision/nuc-1/raw")

cap = cv2.VideoCapture('/dev/video0')
while True:
    ret, frame = cap.read()
    if ret:
        # Compress to JPEG or H264 before publishing
        _, buffer = cv2.imencode('.jpg', frame)
        pub.put(buffer.tobytes())
```

---

### Component 2: The Vision Satellite Processor
This node runs on a high-compute machine (e.g., `dev-1`), subscribes to the video feed, runs the ML model, and publishes lightweight bounding-box metadata back to the mesh.

#### [NEW] `projects/satellites/vision/satellite_inference.py`
```python
# Pseudo-code for the Vision Satellite
import zenoh
import json
from ultralytics import YOLO # Example model

model = YOLO("yolov8n.pt")
session = zenoh.open()
inference_pub = session.declare_publisher("swarm/telemetry/vision/nuc-1/inference")

def listener_callback(sample):
    # Decode image from sample.payload
    frame = decode_image(sample.payload)
    results = model(frame)
    
    # Extract bounding boxes
    boxes = format_to_json(results)
    
    # Publish inference data back to the core Swarm
    inference_pub.put(json.dumps(boxes))

sub = session.declare_subscriber("swarm/telemetry/vision/nuc-1/raw", listener_callback)
```

---

### Component 3: Core Swarm Ingestion (OCaml)
The OCaml safety kernel never touches the raw video. The `Sensorium` agent simply subscribes to the JSON bounding boxes and routes them to the `Topologist` to update the CRDT state.

#### [MODIFY] `modules/swarm/swarm_agents.ml`
```ocaml
(* Inside the Sensorium Agent module *)
let ingest_vision_inference (payload : string) =
  let json = Yojson.Safe.from_string payload in
  let bounding_boxes = parse_boxes json in
  (* Forward to Byzantine Critic for anomaly detection before CRDT merge *)
  send_to_critic bounding_boxes
```

---

## Verification Plan

### Automated Tests
1.  **Zenoh Mesh Routing Test**: `dune exec modules/swarm/test_zenoh_routing.exe` to ensure the core Swarm can receive and parse the mock JSON bounding boxes.
2.  **Safety Kernel Isolation**: Verify that the OCaml core memory footprint does not increase when the Vision Satellite processes heavy video feeds.

### Manual Verification
1.  Run the publisher on `nuc-1`.
2.  Run the Vision Satellite on `dev-1`.
3.  Observe the Global Homeostasis Dashboard to verify the Swarm's `Sensorium` is receiving coordinate data in real-time.
