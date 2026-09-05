(* Fractal ontology for the vision pipeline. See vision_ontology.mli. *)

type stage = Source | Encode | Package | Serve | Play | Observe

let stages = [ Source; Encode; Package; Serve; Play; Observe ]

let stage_name = function
  | Source -> "Source"
  | Encode -> "Encode"
  | Package -> "Package"
  | Serve -> "Serve"
  | Play -> "Play"
  | Observe -> "Observe"

let stage_index s =
  let rec go i = function
    | [] -> i
    | x :: rest -> if x = s then i else go (i + 1) rest
  in
  go 0 stages

let level = function
  | Source -> Fractal_diagnostic.L1_family
  | Encode -> Fractal_diagnostic.L2_capability
  | Package -> Fractal_diagnostic.L3_contract
  | Serve -> Fractal_diagnostic.L4_fixture
  | Play -> Fractal_diagnostic.L5_trace
  | Observe -> Fractal_diagnostic.L6_receipt

(* NOT Implementation for the transport stages. An absent ffmpeg, a busy
   port or an unreachable browser proves nothing about whether the
   pipeline is correctly specified, and recording it as Implementation
   would let a missing binary deny parity credit (R5). Only Package —
   where this repository's own code decides the segment contract — can
   be an Implementation fault. *)
let origin = function
  | Source -> Fractal_diagnostic.Environment
  | Encode -> Fractal_diagnostic.Environment
  | Package -> Fractal_diagnostic.Implementation
  | Serve -> Fractal_diagnostic.Control
  | Play -> Fractal_diagnostic.Environment
  | Observe -> Fractal_diagnostic.Evidence

let law = function
  | Source -> "a frame is produced, and its ordinal advances"
  | Encode -> "frames become a decodable elementary stream of the declared codec"
  | Package -> "a playlist names segments that exist and are non-empty"
  | Serve -> "the playlist and every segment it names are fetchable over HTTP"
  | Play -> "a browser decodes the stream and presents advancing frames"
  | Observe -> "the presented frames carry the same ordinals the source burned in"

(* Each hazard is a way the stage reports success while delivering
   nothing — which is why each has a probe rather than a status flag. *)
let hazard = function
  | Source -> "the source runs but emits a frozen frame, so the ordinal never advances"
  | Encode -> "the encoder accepts input and writes a stream nothing can decode"
  | Package -> "a playlist is written naming segments that were already deleted"
  | Serve -> "the playlist is served while its segments 404, so playback stalls silently"
  | Play -> "the player element exists and reports readiness without ever painting a frame"
  | Observe -> "the capture is compared against itself, so any stream would pass"

let upstream = function
  | Source -> Source
  | Encode -> Source
  | Package -> Encode
  | Serve -> Package
  | Play -> Serve
  | Observe -> Play
