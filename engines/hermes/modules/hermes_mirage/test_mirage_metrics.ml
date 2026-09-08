open Mirage_metrics

let require message condition = if not condition then failwith message
let unwrap = function Ok value -> value | Error message -> failwith message

let probe ?(at = 12_000_000_000L) name health =
  unwrap (make_probe ~name ~checked_at_ns:at health)

let sample ?(boot = "boot-7") ?(run = "run-3") ?(started = 10_000_000_000L)
    ?(sampled = 12_000_000_000L) probes =
  unwrap (make_sample ~boot_id:boot ~run_id:run ~started_at_ns:started
    ~sampled_at_ns:sampled ~heap_words:1024 ~top_heap_words:2048
    ~minor_collections:3 ~major_collections:1 probes)

let contains haystack needle =
  let h = String.length haystack and n = String.length needle in
  let rec loop i = i + n <= h &&
    (String.sub haystack i n = needle || loop (i + 1)) in
  n = 0 || loop 0

let read_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let run_bridge bridge frame =
  let input_path = Filename.temp_file "mirage-metrics-input-" ".txt" in
  let output_path = Filename.temp_file "mirage-metrics-output-" ".txt" in
  Fun.protect ~finally:(fun () -> Sys.remove input_path; Sys.remove output_path) (fun () ->
    let channel = open_out_bin input_path in
    Fun.protect ~finally:(fun () -> close_out channel) (fun () -> output_string channel frame);
    let input = Unix.openfile input_path [Unix.O_RDONLY] 0 in
    let output = Unix.openfile output_path [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
    let pid = Fun.protect ~finally:(fun () -> Unix.close input; Unix.close output) (fun () ->
      Unix.create_process bridge [|bridge|] input output output) in
    let _, status = Unix.waitpid [] pid in
    status, read_file output_path)

let run_bridge_with_open_pipe bridge frame =
  let output_path = Filename.temp_file "mirage-metrics-output-" ".txt" in
  Fun.protect ~finally:(fun () -> Sys.remove output_path) (fun () ->
    let input, writer = Unix.pipe ~cloexec:true () in
    let output = Unix.openfile output_path [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
    let pid = Fun.protect ~finally:(fun () -> Unix.close input; Unix.close output) (fun () ->
      Unix.create_process bridge [|bridge|] input output output) in
    let payload = Bytes.of_string frame in
    let rec write offset =
      if offset < Bytes.length payload then
        let count = Unix.write writer payload offset (Bytes.length payload - offset) in
        write (offset + count)
    in
    Fun.protect ~finally:(fun () -> Unix.close writer) (fun () ->
      write 0;
      let _, status = Unix.waitpid [] pid in
      status, read_file output_path))

let () =
  let original = sample [probe "zeta" Unknown; probe "alpha" Healthy;
                         probe ~at:11_000_000_000L "db" Failed] in
  let encoded = encode_console original in
  require "MM-01 console frame is bounded and one line"
    (String.length encoded <= max_console_bytes && not (String.contains encoded '\n'));
  let decoded = unwrap (decode_console encoded) in
  require "MM-02 canonical console roundtrip" (observationally_equal original decoded);
  require "MM-03 probes have deterministic order"
    (List.map probe_name (probes decoded) = ["alpha"; "db"; "zeta"]);
  let rendered = unwrap (render_prometheus decoded) in
  require "MM-04 measured uptime uses the declared monotonic origin"
    (uptime_ns decoded = 2_000_000_000L
     && contains rendered "uos_mirage_guest_uptime_seconds{boot_id=\"boot-7\",run_id=\"run-3\"} 2.000000000");
  require "MM-05 GC observations are raw gauges with unknown availability"
    (contains rendered "availability=\"unknown\"} 1"
     && contains rendered "uos_mirage_guest_gc_heap_words_raw{boot_id=\"boot-7\",run_id=\"run-3\"} 1024"
     && contains rendered "# TYPE uos_mirage_guest_gc_major_collections_raw gauge"
     && not (contains rendered "collections_total"));
  require "MM-06 unknown and failed probes preserve non-green health"
    (contains rendered "probe=\"zeta\"} -1"
     && contains rendered "probe=\"db\"} 0");
  require "MM-07 projection reports sample-relative age without current freshness"
    (let stale = sample [probe ~at:10_000_000_000L "clock" Healthy] in
     let text = unwrap (render_prometheus stale) in
     contains text "unknown_without_host_receipt_clock"
     && contains text "uos_mirage_guest_probe_age_at_sample_seconds"
     && contains text "probe=\"clock\"} 2.000000000"
     && not (contains text "probe_fresh"));
  List.iter (fun (message, result) -> require message (Result.is_error result)) [
    "MM-08 empty boot id rejected", make_sample ~boot_id:"" ~run_id:"run"
      ~started_at_ns:0L ~sampled_at_ns:0L ~heap_words:1 ~top_heap_words:1
      ~minor_collections:0 ~major_collections:0 [];
    "MM-08 unsafe run id rejected", make_sample ~boot_id:"boot" ~run_id:"../run"
      ~started_at_ns:0L ~sampled_at_ns:0L ~heap_words:1 ~top_heap_words:1
      ~minor_collections:0 ~major_collections:0 [];
    "MM-09 backwards monotonic clock rejected", make_sample ~boot_id:"boot" ~run_id:"run"
      ~started_at_ns:2L ~sampled_at_ns:1L ~heap_words:1 ~top_heap_words:1
      ~minor_collections:0 ~major_collections:0 [];
    "MM-09 future probe rejected", make_sample ~boot_id:"boot" ~run_id:"run"
      ~started_at_ns:0L ~sampled_at_ns:1L ~heap_words:1 ~top_heap_words:1
      ~minor_collections:0 ~major_collections:0 [probe ~at:2L "future" Healthy];
    "MM-09 pre-start probe rejected", make_sample ~boot_id:"boot" ~run_id:"run"
      ~started_at_ns:2L ~sampled_at_ns:3L ~heap_words:1 ~top_heap_words:1
      ~minor_collections:0 ~major_collections:0 [probe ~at:1L "prior" Healthy];
    "MM-10 peak smaller than heap rejected", make_sample ~boot_id:"boot" ~run_id:"run"
      ~started_at_ns:0L ~sampled_at_ns:1L ~heap_words:2 ~top_heap_words:1
      ~minor_collections:0 ~major_collections:0 [];
    "MM-11 duplicate probes rejected", make_sample ~boot_id:"boot" ~run_id:"run"
      ~started_at_ns:0L ~sampled_at_ns:12_000_000_000L ~heap_words:1 ~top_heap_words:1
      ~minor_collections:0 ~major_collections:0
      [probe "same" Healthy; probe "same" Failed];
  ];
  List.iter (fun malformed -> require "MM-12 malformed/noncanonical console rejected"
    (Result.is_error (decode_console malformed))) [
      ""; "UOS_MIRAGE_METRICS_V1"; encoded ^ "\textra";
      String.concat "\t" ("UOS_MIRAGE_METRICS_V1" :: "boot-7" :: "run-3" ::
        "010000000000" :: List.tl (List.tl (List.tl (String.split_on_char '\t' encoded))));
      String.make (max_console_bytes + 1) 'x'
    ];
  require "MM-13 operator identity and provenance are explicitly untrusted"
    (contains rendered "identity: operator_supplied_untrusted"
     && contains rendered "provenance: external_capture_required");
  let restarted = sample ~run:"run-4" [probe "alpha" Healthy] in
  require "MM-14 restart identity cannot alias prior run"
    (not (observationally_equal original restarted)
     && contains (encode_console restarted) "\trun-4\t");
  let too_many = List.init (max_probes + 1) (fun i -> probe ("p" ^ string_of_int i) Healthy) in
  require "MM-15 probe count is bounded"
    (Result.is_error (make_sample ~boot_id:"boot" ~run_id:"run" ~started_at_ns:0L
      ~sampled_at_ns:12_000_000_000L ~heap_words:1 ~top_heap_words:1
      ~minor_collections:0 ~major_collections:0 too_many));
  require "MM-16 Prometheus output is bounded" (String.length rendered <= max_prometheus_bytes);
  let bridge = if Array.length Sys.argv = 2 then Sys.argv.(1)
    else failwith "supply path to mirage_metrics_bridge.exe" in
  let bridge = if Filename.is_relative bridge then Filename.concat (Sys.getcwd ()) bridge else bridge in
  let status, bridge_output = run_bridge bridge (encoded ^ "\n") in
  require "MM-17 bridge decodes one guest console frame"
    (status = Unix.WEXITED 0 && String.equal bridge_output rendered);
  List.iter (fun frame ->
    let status, _ = run_bridge bridge frame in
    require "MM-18 bridge rejects malformed, surplus, and unbounded input"
      (status = Unix.WEXITED 2))
    [encoded ^ "\nextra\n"; String.make (max_console_bytes + 1) 'x'];
  let timeout_status, timeout_text = run_bridge_with_open_pipe bridge (encoded ^ "\n") in
  require "MM-18 bridge applies one monotonic input deadline"
    (timeout_status = Unix.WEXITED 2 && contains timeout_text "console input timed out");
  print_endline "Mirage metrics MM-01..18 PASS: strict boot snapshot, raw GC observations, no current-freshness claim, restart identity, bounded timed host bridge"
