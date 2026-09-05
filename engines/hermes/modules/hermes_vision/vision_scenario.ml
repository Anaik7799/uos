(* Synthetic security scenarios. See the .mli. *)

type point = { x : int; y : int }

type scenario =
  | Intrusion of { start_x : int; speed_px_per_frame : int; boundary_x : int }
  | Loitering of { enter_x : int; speed_px_per_frame : int; stop_x : int; dwell_frames : int }
  | Abandoned of { speed_px_per_frame : int; drop_x : int; leaver_exits_x : int }

let name = function
  | Intrusion _ -> "intrusion" | Loitering _ -> "loitering" | Abandoned _ -> "abandoned"

let rate = 15
let height = 360
let width = 640
let track_y = 160
let box = 40

type event = { label : string; at_frame : int; at : point }

(* Derived from the motion law: change the law and the expected answer
   moves with it, which is the only way the two cannot drift. *)
let ground_truth = function
  | Intrusion { start_x; speed_px_per_frame = v; boundary_x } ->
      let f = (boundary_x - start_x + v - 1) / v in
      [ { label = "boundary_crossed"; at_frame = f; at = { x = boundary_x; y = track_y } } ]
  | Loitering { enter_x; speed_px_per_frame = v; stop_x; dwell_frames } ->
      let arrive = (stop_x - enter_x + v - 1) / v in
      [ { label = "arrived"; at_frame = arrive; at = { x = stop_x; y = track_y } };
        (* presence is true from `arrive`; LOITERING only from here, and
           a detector that alerts at `arrive` has not measured dwell *)
        { label = "dwell_threshold_reached"; at_frame = arrive + dwell_frames;
          at = { x = stop_x; y = track_y } } ]
  | Abandoned { speed_px_per_frame = v; drop_x; leaver_exits_x } ->
      let drop = (drop_x + v - 1) / v in
      let exit_f = (leaver_exits_x + v - 1) / v in
      [ { label = "object_dropped"; at_frame = drop; at = { x = drop_x; y = track_y } };
        { label = "carrier_left"; at_frame = exit_f; at = { x = leaver_exits_x; y = track_y } };
        (* the alert depends on telling these two apart: a tracker that
           reassigns identity reports the wrong one as abandoned *)
        { label = "object_abandoned"; at_frame = exit_f;
          at = { x = drop_x; y = track_y } } ]

let base = Printf.sprintf "color=black:s=%dx%d:r=%d" width height rate

let ordinal =
  Printf.sprintf
    "drawtext=text='F %%{n}':fontsize=24:fontcolor=white:x=10:y=10:box=1:boxcolor=black@0.7"

let drawbox x_expr colour =
  Printf.sprintf "drawbox=x='%s':y=%d:w=%d:h=%d:color=%s:t=fill" x_expr track_y box box colour

(* drawbox has NO frame-number variable on ffmpeg 7.1.1 — only `t`.
   Measured: an `n` expression fails with "Undefined constant". So the
   motion is expressed in seconds and the px-per-frame speed is scaled
   by the rate, which keeps the DECLARATION in frames where the ground
   truth lives. *)
let per_sec v = v * rate

let filter = function
  | Intrusion { start_x; speed_px_per_frame = v; boundary_x } ->
      (* the zone boundary drawn, so a human can see what the ground
         truth asserts *)
      Printf.sprintf "%s,%s,%s,%s" base
        (Printf.sprintf "drawbox=x=%d:y=0:w=2:h=%d:color=red:t=fill" boundary_x height)
        (drawbox (Printf.sprintf "%d+%d*t" start_x (per_sec v)) "white")
        ordinal
  | Loitering { enter_x; speed_px_per_frame = v; stop_x; _ } ->
      Printf.sprintf "%s,%s,%s" base
        (drawbox (Printf.sprintf "min(%d+%d*t\\,%d)" enter_x (per_sec v) stop_x) "white")
        ordinal
  | Abandoned { speed_px_per_frame = v; drop_x; _ } ->
      (* two objects: one stops at drop_x forever, the other keeps going *)
      Printf.sprintf "%s,%s,%s,%s" base
        (drawbox (Printf.sprintf "min(%d*t\\,%d)" (per_sec v) drop_x) "white")
        (drawbox (Printf.sprintf "%d*t" (per_sec v)) "yellow")
        ordinal

let argv s ~out ~frames =
  [ "ffmpeg"; "-hide_banner"; "-loglevel"; "error"; "-f"; "lavfi"; "-i"; filter s;
    "-frames:v"; string_of_int frames; "-c:v"; "libvpx"; "-b:v"; "1M"; "-pix_fmt"; "yuv420p";
    "-y"; out ]

let validate s ~frames =
  if frames <= 0 then Error "a scenario needs at least one frame"
  else
    match List.filter (fun e -> e.at_frame >= frames) (ground_truth s) with
    (* a video in which nothing happens is one that every broken
       detector also gets right *)
    | e :: _ ->
        Error
          (Printf.sprintf "%s occurs at frame %d, beyond the %d generated — the scenario would \
                           stage no event" e.label e.at_frame frames)
    | [] -> Ok s

let render s =
  let b = Buffer.create 256 in
  Buffer.add_string b (Printf.sprintf "scenario %s\n" (name s));
  List.iter
    (fun e ->
      Buffer.add_string b
        (Printf.sprintf "  %-24s frame %-4d at (%d,%d)\n" e.label e.at_frame e.at.x e.at.y))
    (ground_truth s);
  Buffer.contents b
