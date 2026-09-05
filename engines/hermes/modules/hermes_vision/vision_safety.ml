(* STPA and FMEA, projected from the ontologies. See the .mli. *)

type severity = Negligible | Degraded | Stream_lost | Evidence_false

(* Evidence_false outranks Stream_lost deliberately: a dropped stream is
   visible and someone fixes it; a run reporting success it did not
   measure corrupts every decision downstream, and nobody looks. *)
let severity_rank = function
  | Negligible -> 0 | Degraded -> 1 | Stream_lost -> 2 | Evidence_false -> 3

let severity_name = function
  | Negligible -> "negligible" | Degraded -> "degraded"
  | Stream_lost -> "stream_lost" | Evidence_false -> "EVIDENCE_FALSE"

type detection = Probed of string | Undetected

let detection_name = function Probed p -> "probed:" ^ p | Undetected -> "UNDETECTED"

type mode = {
  component : string;
  failure : string;
  impact : severity;
  detected_by : detection;
  origin : Fractal_diagnostic.origin;
}

(* An Evidence-origin failure falsifies evidence by definition; a
   Control-origin one takes the service down; everything else degrades.
   Derived from the origin the ontology already declares, so the two
   cannot disagree. *)
let severity_of_origin = function
  | Fractal_diagnostic.Evidence -> Evidence_false
  | Fractal_diagnostic.Control -> Stream_lost
  | Fractal_diagnostic.Implementation -> Stream_lost
  | Fractal_diagnostic.Environment -> Degraded
  | Fractal_diagnostic.Specification -> Degraded

let modes () =
  let pipeline =
    List.map
      (fun s ->
        { component = "pipeline." ^ Vision_ontology.stage_name s;
          failure = Vision_ontology.hazard s;
          impact = severity_of_origin (Vision_ontology.origin s);
          (* every pipeline stage has a probe by construction — that is
             what Vision_controller.probe_all is *)
          detected_by = Probed ("probe_" ^ String.lowercase_ascii (Vision_ontology.stage_name s));
          origin = Vision_ontology.origin s })
      Vision_ontology.stages
  in
  let browser =
    List.map
      (fun c ->
        { component = "browser." ^ Vision_browser_api.name c;
          failure = Vision_browser_api.hazard c;
          impact = severity_of_origin (Vision_browser_api.origin c);
          detected_by = Probed ("browser_probe:" ^ Vision_browser_api.name c);
          origin = Vision_browser_api.origin c })
      Vision_browser_api.capabilities
  in
  let gst =
    List.map
      (fun e ->
        { component = "gstreamer." ^ Vision_gstreamer.element_name e;
          failure = Vision_gstreamer.hazard e;
          impact = severity_of_origin (Vision_gstreamer.origin e);
          (* Vision_tool_probe runs a BOUNDED pipeline and asks whether an
             artefact appeared, which is what distinguishes health from
             the silent-hang hazard. Presence of the plugin is not the
             question and never was. *)
          detected_by = Probed "gst_produces/gst_decodes";
          origin = Vision_gstreamer.origin e })
      Vision_gstreamer.elements
  in
  let vlc =
    List.map
      (fun c ->
        { component = "vlc." ^ Vision_vlc.capability_name c;
          failure = Vision_vlc.hazard c;
          impact = severity_of_origin (Vision_vlc.origin c);
          (* leniencies_in reads VLC's own verbose output for the moments
             it forgave something; "did it play" proves nothing. *)
          detected_by = Probed "vlc_decodes/leniencies_in";
          origin = Vision_vlc.origin c })
      Vision_vlc.capabilities
  in
  let obs =
    List.map
      (fun c ->
        { component = "obs." ^ Vision_obs.name c;
          failure = Vision_obs.hazard c;
          impact = severity_of_origin (Vision_obs.origin c);
          (* obs_log parses the three loss counters; obs_capability
             answers Unknown for the GL-bound ones on a host without a
             context, which is this one. *)
          detected_by = Probed "obs_log/obs_capability";
          origin = Vision_obs.origin c })
      Vision_obs.capabilities
  in
  let jm =
    List.map
      (fun e ->
        { component = "jmeter." ^ Vision_jmeter.name e;
          failure = Vision_jmeter.hazard e;
          impact = severity_of_origin (Vision_jmeter.origin e);
          (* contaminants_in_report reads what the report betrays about
             the generator; a green number is not a verdict until it
             does. *)
          detected_by = Probed "jmeter_report/contaminants_in_report";
          origin = Vision_jmeter.origin e })
      Vision_jmeter.elements
  in
  let libav =
    List.map
      (fun c ->
        { component = "libav." ^ Vision_libav_ontology.name c;
          failure = Vision_libav_ontology.hazard c;
          impact = severity_of_origin (Vision_libav_ontology.origin c);
          (* in-process, so these are probed by opening real media and
             watching RSS — a leak is invisible to the OCaml GC *)
          detected_by = Probed "libav_leaks/libav_codes/libav_version_skew";
          origin = Vision_libav_ontology.origin c })
      Vision_libav_ontology.calls
  in
  List.concat [ pipeline; browser; gst; vlc; obs; jm; libav ]

let undetected () = List.filter (fun m -> m.detected_by = Undetected) (modes ())

(* Detection is the cheapest mitigation there is, so an undetected
   failure ranks above a detected one of equal severity. *)
let priority m =
  (severity_rank m.impact * 2) + (match m.detected_by with Undetected -> 1 | Probed _ -> 0)

let ranked () =
  List.sort (fun a b -> compare (priority b) (priority a)) (modes ())

type uca_kind = Not_provided | Provided_unsafe | Wrong_timing | Stopped_too_soon

let uca_kinds = [ Not_provided; Provided_unsafe; Wrong_timing; Stopped_too_soon ]

let uca_kind_name = function
  | Not_provided -> "not_provided" | Provided_unsafe -> "provided_unsafe"
  | Wrong_timing -> "wrong_timing" | Stopped_too_soon -> "stopped_too_soon"

type uca = {
  action : string;
  kind : uca_kind;
  context : string;
  consequence : string;
  constraint_ : string;
  enforced_by : string;
}

(* Nothing has to BREAK for any of these. Each is a correctly executed
   control action producing an unsafe state. *)
let ucas =
  [ (* --- restart --- *)
    { action = "restart"; kind = Not_provided;
      context = "the running image differs from the built one and the pipeline is degraded";
      consequence = "the old image serves indefinitely and the fix never reaches production";
      constraint_ = "a digest change must eventually produce a restart";
      enforced_by = "Vision_restart.supervise_once (digest compared each tick)" };
    { action = "restart"; kind = Provided_unsafe;
      context = "the replacement image is broken";
      consequence = "the service is taken down and cannot come back";
      constraint_ = "the old instance must not be retired until the replacement passes a health gate";
      enforced_by = "Vision_restart.execute (law 1, chaos-tested over 7 failure modes)" };
    { action = "restart"; kind = Wrong_timing;
      context = "in-flight segment requests have not finished";
      consequence = "viewers see refused connections mid-stream";
      constraint_ = "accepting must stop and in-flight responses must finish before the swap";
      enforced_by = "Vision_restart.execute (Draining precedes Starting)" };
    { action = "restart"; kind = Stopped_too_soon;
      context = "the gate ran before the replacement had opened its listener";
      consequence = "a healthy replacement is rolled back, or a broken one is promoted";
      constraint_ = "the gate must ask what the stage probes ask, not whether the process exists";
      enforced_by = "Vision_control (ffmpeg gate is probe_package; server gate polls /whoami)" };
    (* --- start / stop the pipeline --- *)
    { action = "start_pipeline"; kind = Provided_unsafe;
      context = "a pipeline is already running against the same output directory";
      consequence = "two encoders write one playlist and the stream becomes undecodable";
      constraint_ = "starting must be refused while another pipeline owns the output";
      enforced_by = "Vision_controller.start (lock_holder checked BEFORE the spawn)" };
    { action = "start_pipeline"; kind = Not_provided;
      context = "the pipeline has died and nothing restarts it";
      consequence = "the stream ends silently while the server keeps serving a stale playlist";
      constraint_ = "a dead pipeline must be detected and reported";
      enforced_by = "Vision_controller.probe_source (Absent when the process exited)" };
    { action = "stop_pipeline"; kind = Stopped_too_soon;
      context = "SIGKILL before the muxer finalises";
      consequence = "an unfinalised container that most players still open, so corruption is invisible";
      constraint_ = "stopping must send SIGTERM and wait before escalating";
      enforced_by = "Vision_controller.stop (TERM, settle, then KILL)" };
    { action = "stop_pipeline"; kind = Wrong_timing;
      context = "stop is issued while a capture is being compared";
      consequence = "the comparison reads a truncated capture and reports a false divergence";
      constraint_ = "a capture in progress must complete or be discarded, never half-read";
      enforced_by = "Vision_serve POST /capture (reads to Content-Length; a short read is a 500 and nothing is written)" };
    (* These four were MISSING until incomplete_analysis reported them.
       That is the check earning its place: an analysis is not finished
       because it feels finished, and the phrase you skip is the one that
       would have found the defect. *)
    { action = "start_pipeline"; kind = Wrong_timing;
      context = "started before the output directory exists or is writable";
      consequence = "ffmpeg exits immediately and the failure looks like a bad intent";
      constraint_ = "the sink must be created and writable before the process is spawned";
      enforced_by = "Vision_controller.start (mkdir_p before create_process)" };
    { action = "start_pipeline"; kind = Stopped_too_soon;
      context = "probed before the first segment boundary";
      consequence = "a healthy pipeline reports Unknown and is treated as broken";
      constraint_ = "a pipeline must be given time to reach its first segment before judgement";
      enforced_by = "Vision_controller.probe_package (Unknown, not Absent, before the playlist)" };
    { action = "stop_pipeline"; kind = Not_provided;
      context = "a run ends without stopping the pipeline it started";
      consequence = "an orphan ffmpeg holds the output directory and corrupts the next run";
      constraint_ = "every started pipeline must be stopped on every exit path";
      enforced_by = "Vision_controller (at_exit walks started_pipelines)" };
    { action = "stop_pipeline"; kind = Provided_unsafe;
      context = "stop is issued to a pid that has been reused by another process";
      consequence = "an unrelated process is killed";
      constraint_ = "a pid must be validated as ours before a signal is sent to it";
      enforced_by = "Vision_controller.stop_pid (owns_pid gates every signal)" };
    (* --- telemetry --- *)
    { action = "publish_telemetry"; kind = Not_provided;
      context = "the router is unreachable";
      consequence = "the mesh view is incomplete and looks the same as a healthy quiet system";
      constraint_ = "an unpublished observation must be counted and disclosed";
      enforced_by = "Vision_telemetry.render (reports 'mesh view incomplete')" };
    { action = "publish_telemetry"; kind = Provided_unsafe;
      context = "a payload carries a credential or a private path";
      consequence = "secrets are broadcast to every subscriber on the mesh";
      constraint_ = "published payloads must contain only observations, never configuration";
      enforced_by = "Vision_telemetry.redact (applied to every payload before it goes out)" };
    { action = "publish_telemetry"; kind = Wrong_timing;
      context = "published before the probe completed";
      consequence = "a verdict is broadcast that the probe later contradicts";
      constraint_ = "telemetry must be published from a completed observation";
      enforced_by = "Vision_run (publishes after probe_all returns)" };
    { action = "publish_telemetry"; kind = Stopped_too_soon;
      context = "the run exits before the last observation is flushed";
      consequence = "the mesh's last view of a failing run is a healthy one";
      constraint_ = "the terminal observation must be published before exit";
      enforced_by = "Vision_telemetry (at_exit warns when a run published and never closed)" } ]

let unenforced () = List.filter (fun u -> u.enforced_by = "") ucas

let incomplete_analysis () =
  let actions = List.sort_uniq compare (List.map (fun u -> u.action) ucas) in
  List.concat_map
    (fun a ->
      List.filter_map
        (fun k ->
          if List.exists (fun u -> u.action = a && u.kind = k) ucas then None else Some (a, k))
        uca_kinds)
    actions

let render () =
  let b = Buffer.create 4096 in
  let ms = ranked () in
  Buffer.add_string b
    (Printf.sprintf "FMEA: %d failure modes, %d UNDETECTED\n" (List.length ms)
       (List.length (undetected ())));
  List.iter
    (fun m ->
      Buffer.add_string b
        (Printf.sprintf "  [%2d] %-34s %-14s %s\n       %s\n" (priority m) m.component
           (severity_name m.impact) (detection_name m.detected_by) m.failure))
    ms;
  Buffer.add_string b
    (Printf.sprintf "\nSTPA: %d unsafe control actions, %d with NOTHING enforcing the constraint\n"
       (List.length ucas) (List.length (unenforced ())));
  List.iter
    (fun u ->
      Buffer.add_string b
        (Printf.sprintf "  %-18s %-18s %s\n    when: %s\n    then: %s\n    must: %s\n    by:   %s\n"
           u.action (uca_kind_name u.kind)
           (if u.enforced_by = "" then "UNENFORCED" else "enforced")
           u.context u.consequence u.constraint_
           (if u.enforced_by = "" then "(nothing)" else u.enforced_by)))
    ucas;
  Buffer.contents b
