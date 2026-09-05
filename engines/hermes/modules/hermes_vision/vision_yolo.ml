(* YOLO detection. See the .mli. *)

type capability = Detect | Track | Segment | Classify

let capabilities = [ Detect; Track; Segment; Classify ]

let name = function
  | Detect -> "detect" | Track -> "track" | Segment -> "segment" | Classify -> "classify"

let level = function
  | Detect -> Fractal_diagnostic.L5_trace
  | Track -> Fractal_diagnostic.L5_trace
  | Segment -> Fractal_diagnostic.L6_receipt
  | Classify -> Fractal_diagnostic.L2_capability

(* An oracle, never an author: a detector that cannot run says nothing
   about our stream. Evidence for the two that produce receipts,
   Environment for the rest (R5). *)
let origin = function
  | Segment | Detect -> Fractal_diagnostic.Evidence
  | Track | Classify -> Fractal_diagnostic.Environment

let law = function
  | Detect -> "objects present in the frame are reported with a confidence"
  | Track -> "an object keeps its identity across consecutive frames"
  | Segment -> "each detected object carries a mask covering its pixels"
  | Classify -> "the frame receives a whole-image label"

(* Every one is a detector that runs and tells you nothing while looking
   like it worked. *)
let hazard = function
  | Detect ->
      "an empty detection set is returned for a frame the model was never trained on, and \
       reads identically to a frame that genuinely contains nothing"
  | Track ->
      "identities are reassigned between frames, so the same object counted twice looks like \
       two objects"
  | Segment -> "masks are produced at a coarser resolution than the frame and silently upscaled"
  | Classify ->
      "the top-1 label is reported without its confidence, so a 0.02 guess reads like a finding"

let serves = function
  | Detect | Segment -> Vision_ontology.Observe
  | Track -> Vision_ontology.Play
  | Classify -> Vision_ontology.Encode

type detection = { label : string; confidence : float }
type detections = detection list

let labels ?(floor = 0.25) ds =
  List.filter (fun d -> d.confidence >= floor) ds
  |> List.map (fun d -> d.label)
  |> List.sort compare

(* Multiset Jaccard: two captures of one scene rarely agree on
   coordinates and usually agree on what is present. *)
let agreement ?(floor = 0.25) a b =
  let la = labels ~floor a and lb = labels ~floor b in
  match (la, lb) with
  | [], [] -> 1.0
  | _ ->
      let rec inter xs ys =
        match xs with
        | [] -> 0
        | x :: rest ->
            if List.mem x ys then 1 + inter rest (List.filter (fun y -> y <> x) ys)
            else inter rest ys
      in
      let i = inter la lb in
      let u = List.length la + List.length lb - i in
      if u = 0 then 1.0 else float_of_int i /. float_of_int u

(* NO EVIDENCE IS NOT AGREEMENT. Two empty detection sets are perfectly
   similar and prove nothing — a detector that found nothing in either
   image agrees with itself. *)
let agrees ?(floor = 0.25) ?(threshold = 0.6) a b =
  labels ~floor a <> [] && agreement ~floor a b >= threshold

type intent = { image : string; weights : string; confidence : float; capability : capability }

let validate i =
  if String.trim i.image = "" then Error "image path is empty"
  else if String.trim i.weights = "" then Error "weights are unspecified"
  else if i.confidence < 0.0 || i.confidence > 1.0 then Error "confidence must be in [0,1]"
  else Ok i

let argv i =
  (* MODE FIRST, THEN TASK. `yolo detect model=... source=...` does NOT
     detect: `detect` is a TASK and the default MODE is train, so that
     invocation silently starts a 100-epoch training run, writes weights
     into the working directory and burns the CPU. Measured the hard way.
     The mode must be given explicitly. *)
  [ "yolo"; name i.capability; "predict"; Printf.sprintf "model=%s" i.weights;
    Printf.sprintf "source=%s" i.image; Printf.sprintf "conf=%f" i.confidence;
    (* the CLI otherwise writes annotated images beside the source *)
    "save=False"; "verbose=True" ]

let yolo_bin = "venv/bin/yolo"

(* PRESENCE IS NOT AVAILABILITY — the same distinction every probe in
   this module is built on, and I had it wrong here first. Ultralytics
   installs a `yolo` binary that then fails at import when opencv cannot
   load libxcb, so a file-exists check reports a detector that cannot
   run. Measured on this host. The check therefore RUNS it. *)
let available =
  lazy
    (Sys.file_exists yolo_bin
     &&
     let ic =
       Unix.open_process_in (Printf.sprintf "timeout 120 %s checks 2>&1" (Filename.quote yolo_bin))
     in
     let b = Buffer.create 512 in
     (try while true do Buffer.add_channel b ic 1 done with End_of_file -> ());
     let st = try Unix.close_process_in ic with Unix.Unix_error _ -> Unix.WEXITED 127 in
     match st with Unix.WEXITED 0 -> true | _ -> false)

let available () = Lazy.force available

let integration =
  "Ultralytics is a Python package, not a shared library: there is no C ABI to bind. Binding it \
   'via FFI' would mean embedding a CPython interpreter in this process and calling into \
   torch — which imports a multi-hundred-megabyte runtime, brings its own allocator and signal \
   handlers into a harness whose libav probes already watch RSS, and makes any model fault a \
   segfault in OUR address space rather than an exit code we can read. The CLI boundary keeps \
   the detector in its own process where a crash is an observation, which is exactly why ffmpeg, \
   VLC, z3 and stanc are invoked the same way. If in-process detection is ever needed, the sound \
   route is ONNX Runtime's C API against an exported model, not embedding Python."

(* the CLI prints e.g. "384x640 2 persons, 1 tie, 51.0ms" *)
let parse_line line =
  match String.index_opt line ',' with
  | None -> []
  | Some _ ->
      String.split_on_char ',' line
      |> List.filter_map (fun part ->
             let t = String.trim part in
             match String.index_opt t ' ' with
             | None -> None
             | Some sp -> (
                 let n = String.sub t 0 sp in
                 let label = String.sub t (sp + 1) (String.length t - sp - 1) in
                 match int_of_string_opt n with
                 | Some k when k > 0 && label <> "" ->
                     Some (List.init k (fun _ -> { label; confidence = 1.0 }))
                 | _ -> None))
      |> List.concat

let detect i =
  match validate i with
  | Error e -> Error ("invalid intent: " ^ e)
  | Ok i ->
      if not (available ()) then
        (* an absent detector proves nothing about the stream *)
        Error
          ("ultralytics is not usable here: " ^ yolo_bin
          ^ " is absent or fails to start (a present binary that cannot import is not an \
             available detector)")
      else if not (Sys.file_exists i.image) then Error ("no such image: " ^ i.image)
      else
        let cmd =
          Printf.sprintf "timeout 300 %s 2>&1"
            (String.concat " " (List.map Filename.quote (yolo_bin :: List.tl (argv i))))
        in
        let ic = Unix.open_process_in cmd in
        let b = Buffer.create 4096 in
        (try while true do Buffer.add_channel b ic 1 done with End_of_file -> ());
        let st = try Unix.close_process_in ic with Unix.Unix_error _ -> Unix.WEXITED 127 in
        let out = Buffer.contents b in
        (match st with
         | Unix.WEXITED 0 ->
             let ds = List.concat_map parse_line (String.split_on_char '\n' out) in
             (* "found nothing" and "could not look" are different, and a
                run that produced no parsable summary is the second *)
             if ds = [] && not (String.length out > 0) then Error "yolo produced no output"
             else Ok ds
         | _ -> Error ("yolo failed: " ^ String.trim (String.sub out 0 (min 300 (String.length out)))))

let observe ~reference ~candidate ~weights =
  let started = Unix.gettimeofday () in
  let stage = Vision_ontology.Observe in
  let mk v d =
    { Vision_controller.stage; verdict = v;
      level = Vision_ontology.level stage; origin = Vision_ontology.origin stage;
      detail = d; elapsed_ms = (Unix.gettimeofday () -. started) *. 1000.0 }
  in
  let i img = { image = img; weights; confidence = 0.25; capability = Detect } in
  match (detect (i reference), detect (i candidate)) with
  | Error e, _ | _, Error e -> mk (Vision_controller.Unknown e) reference
  | Ok a, Ok b ->
      if labels a = [] then
        (* the reference contains nothing to find, so agreement would be
           vacuous — Unknown, not a pass *)
        mk (Vision_controller.Unknown "the reference frame contains no detectable object")
          reference
      else if agrees a b then
        mk (Vision_controller.Live
              (Printf.sprintf "the capture contains the same objects (%.2f agreement)"
                 (agreement a b)))
          (String.concat "," (labels b))
      else
        mk (Vision_controller.Absent
              (Printf.sprintf "the capture does not contain the reference's objects (%.2f)"
                 (agreement a b)))
          (String.concat "," (labels a) ^ " vs " ^ String.concat "," (labels b))
