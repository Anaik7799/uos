(* Fractal ontology of in-process libav. See the .mli: this one is about
   memory and lifetime, because libav failures happen inside us. *)

type call =
  | Version_query
  | Open_input
  | Find_stream_info
  | Send_packet
  | Receive_frame
  | Frame_buffer_access
  | Unref_frame
  | Close_input

let calls =
  [ Version_query; Open_input; Find_stream_info; Send_packet; Receive_frame;
    Frame_buffer_access; Unref_frame; Close_input ]

let name = function
  | Version_query -> "version_query"
  | Open_input -> "open_input"
  | Find_stream_info -> "find_stream_info"
  | Send_packet -> "send_packet"
  | Receive_frame -> "receive_frame"
  | Frame_buffer_access -> "frame_buffer_access"
  | Unref_frame -> "unref_frame"
  | Close_input -> "close_input"

let level = function
  | Version_query -> Fractal_diagnostic.L0_product
  | Open_input | Close_input -> Fractal_diagnostic.L1_family
  | Find_stream_info -> Fractal_diagnostic.L2_capability
  | Send_packet | Receive_frame -> Fractal_diagnostic.L3_contract
  | Frame_buffer_access -> Fractal_diagnostic.L6_receipt
  | Unref_frame -> Fractal_diagnostic.L5_trace

(* The lifetime calls are OURS to get right — the binding decides when a
   view expires and whether an expired one can still be held, and getting
   that wrong is an Implementation fault that will present as a segfault
   somewhere else. A codec that is absent from the linked library is
   Environment (R5). *)
let origin = function
  | Frame_buffer_access | Unref_frame | Close_input -> Fractal_diagnostic.Implementation
  | Send_packet | Receive_frame -> Fractal_diagnostic.Implementation
  | Version_query | Open_input | Find_stream_info -> Fractal_diagnostic.Environment

let allocates = function
  | Open_input | Find_stream_info | Receive_frame -> true
  | Version_query | Send_packet | Frame_buffer_access | Unref_frame | Close_input -> false

(* Anything that can block on I/O or spend real CPU. Holding the runtime
   lock across one of these stops EVERY domain, so a slow network input
   freezes the harness including the probes that would report it. *)
let releases_runtime_lock = function
  | Open_input | Find_stream_info | Send_packet | Receive_frame -> true
  | Version_query | Frame_buffer_access | Unref_frame | Close_input -> false

(* The safety obligation of the whole binding. *)
let invalidates_aliases = function
  | Unref_frame | Close_input -> true
  | Version_query | Open_input | Find_stream_info | Send_packet | Receive_frame
  | Frame_buffer_access -> false

let law = function
  | Version_query -> "the version reported is the LINKED library's, not a binary on PATH"
  | Open_input -> "a context is allocated and the caller holds the obligation to close it"
  | Find_stream_info -> "stream parameters are populated before any decode is attempted"
  | Send_packet -> "a packet is accepted, or EAGAIN says the decoder must be drained first"
  | Receive_frame -> "a frame is produced, or EAGAIN says more input is required"
  | Frame_buffer_access -> "pixels are read only while the frame reference is still held"
  | Unref_frame -> "the reference is dropped and every view onto it becomes unusable"
  | Close_input -> "the context is freed exactly once and no view outlives it"

(* Every one is correct-looking code, no exception, and a fault that
   appears somewhere else. *)
let hazard = function
  | Version_query ->
      "the header version and the linked version differ, so struct layouts disagree and fields \
       are read at the wrong offsets"
  | Open_input ->
      "the context is allocated and never closed, leaking memory the OCaml GC cannot see, so \
       the process grows with no heap growth to explain it"
  | Find_stream_info ->
      "it is skipped, and decode proceeds against uninitialised parameters that happen to be \
       zero"
  | Send_packet ->
      "EAGAIN is treated as an error, aborting a decode that was working and only needed to be \
       drained"
  | Receive_frame ->
      "any negative return is treated as failure, so a normal EAGAIN ends the loop and the file \
       reports as undecodable"
  | Frame_buffer_access ->
      "a Bigarray built over the frame ALIASES memory libav owns; after unref it is a live OCaml \
       value pointing at freed memory, and the segfault lands somewhere unrelated"
  | Unref_frame ->
      "unref runs while a zero-copy view is still reachable from OCaml, which no type in the \
       binding prevents unless it was designed to"
  | Close_input ->
      "the context is closed twice, or closed while frames derived from it are still held"

type code = Ok_zero | Again | End_of_file | Real_error of int

(* AVERROR(EAGAIN) = -11 on Linux; AVERROR_EOF = -('E'|'O'<<8|'F'<<16|' '<<24)
   which is -541478725. Both are NEGATIVE and neither is a failure. *)
let averror_eagain = -11
let averror_eof = -541478725

let classify n =
  if n >= 0 then Ok_zero
  else if n = averror_eagain then Again
  else if n = averror_eof then End_of_file
  else Real_error n

let code_name = function
  | Ok_zero -> "OK" | Again -> "EAGAIN" | End_of_file -> "EOF"
  | Real_error n -> Printf.sprintf "ERROR(%d)" n

(* THE CLASSIC LIBAV BUG lives here: "negative means error" aborts a
   working decode at the first EAGAIN. *)
let is_failure = function Real_error _ -> true | Ok_zero | Again | End_of_file -> false

let wants_more_input = function Again -> true | _ -> false

type view = Live | Expired

let readable = function Live -> true | Expired -> false

let after call v =
  if invalidates_aliases call then Expired else v

let render () =
  let b = Buffer.create 2048 in
  Buffer.add_string b
    "libav ontology (in-process: a failure here takes the harness with it)\n";
  List.iter
    (fun c ->
      Buffer.add_string b
        (Printf.sprintf
           "  %-22s %-14s %-14s alloc=%b unlock=%b expires=%b\n    law:    %s\n    hazard: %s\n"
           (name c)
           (Fractal_diagnostic.level_name (level c))
           (Fractal_diagnostic.origin_name (origin c))
           (allocates c) (releases_runtime_lock c) (invalidates_aliases c)
           (law c) (hazard c)))
    calls;
  Buffer.add_string b
    (Printf.sprintf "  return codes: EAGAIN=%d EOF=%d — both negative, NEITHER a failure\n"
       averror_eagain averror_eof);
  Buffer.contents b
