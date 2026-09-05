open Ffmpeg_ontology

let compose_filters f1 f2 =
  match f1, f2 with
  | Null, f -> f
  | f, Null -> f
  | Scale (_w1, _h1), Scale (w2, h2) -> Scale (w2, h2) 
  | _, _ -> f2

let transmux node new_format new_sink =
  { node with output_format = new_format; sink = new_sink; video_codec = None }

let transcode node new_codec new_format new_sink =
  { node with output_format = new_format; sink = new_sink; video_codec = Some new_codec }
