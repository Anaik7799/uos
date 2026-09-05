open Ffmpeg_ontology

type ffmpeg_intent =
  | Transmux_Stream of { source: string; sink: string }
  | Transcode_Stream of { source: string; codec: codec; sink: string }
  | Simulate_Stream of { sink: string }
  | Stop_Stream of { id: string }

let compile_intent = function
  | Transmux_Stream { source; sink } ->
      Printf.sprintf "ffmpeg -i %s -c copy -f mpegts %s" source sink
  | Transcode_Stream { source; codec; sink } ->
      let c_str = match codec with | H264 -> "libx264" | H265 -> "libx265" | VP8 -> "libvpx" | _ -> "copy" in
      Printf.sprintf "ffmpeg -i %s -c:v %s -preset ultrafast -f mpegts %s" source c_str sink
  | Simulate_Stream { sink } ->
      Printf.sprintf "ffmpeg -re -f lavfi -i testsrc=size=1280x720:rate=30 -c:v libx264 -preset ultrafast -f mpegts %s" sink
  | Stop_Stream { id } ->
      Printf.sprintf "pkill -f 'ffmpeg.*%s'" id
