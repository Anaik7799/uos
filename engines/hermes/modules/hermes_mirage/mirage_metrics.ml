type health = Healthy | Failed | Unknown

type probe = {
  name : string;
  checked_at_ns : int64;
  health : health;
}

type sample = {
  boot_id : string;
  run_id : string;
  started_at_ns : int64;
  sampled_at_ns : int64;
  heap_words : int;
  top_heap_words : int;
  minor_collections : int;
  major_collections : int;
  probes : probe list;
}

let schema = "UOS_MIRAGE_METRICS_V1"
let max_identifier_bytes = 64
let max_probe_name_bytes = 48
let max_probes = 16
let max_console_bytes = 4096
let max_prometheus_bytes = 16384
let ( let* ) = Result.bind

let safe_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | '_' | ':' | '-' -> true
  | _ -> false

let validate_token ~kind ~maximum value =
  let length = String.length value in
  if length = 0 then Error (kind ^ " must not be empty")
  else if length > maximum then Error (kind ^ " is too long")
  else if not (String.for_all safe_char value) then Error (kind ^ " contains an unsafe character")
  else Ok value

let make_probe ~name ~checked_at_ns health =
  let* name = validate_token ~kind:"probe name" ~maximum:max_probe_name_bytes name in
  if Int64.compare checked_at_ns 0L < 0 then Error "probe timestamp must be nonnegative"
  else Ok { name; checked_at_ns; health }

let rec duplicate_probe_name = function
  | [] | [_] -> false
  | a :: (b :: _ as rest) -> String.equal a.name b.name || duplicate_probe_name rest

let make_sample ~boot_id ~run_id ~started_at_ns ~sampled_at_ns ~heap_words
    ~top_heap_words ~minor_collections ~major_collections probes =
  let* boot_id = validate_token ~kind:"boot id" ~maximum:max_identifier_bytes boot_id in
  let* run_id = validate_token ~kind:"run id" ~maximum:max_identifier_bytes run_id in
  if Int64.compare started_at_ns 0L < 0 || Int64.compare sampled_at_ns 0L < 0 then
    Error "monotonic timestamps must be nonnegative"
  else if Int64.compare sampled_at_ns started_at_ns < 0 then
    Error "sample timestamp precedes startup"
  else if heap_words < 0 || top_heap_words < 0 || minor_collections < 0
          || major_collections < 0 then
    Error "GC observations must be nonnegative"
  else if top_heap_words < heap_words then Error "peak heap is smaller than current heap"
  else if List.length probes > max_probes then Error "too many probes"
  else if List.exists (fun probe -> Int64.compare probe.checked_at_ns started_at_ns < 0) probes then
    Error "probe timestamp precedes startup"
  else if List.exists (fun probe -> Int64.compare probe.checked_at_ns sampled_at_ns > 0) probes then
    Error "probe timestamp is in the future"
  else
    let probes = List.sort (fun a b -> String.compare a.name b.name) probes in
    if duplicate_probe_name probes then Error "duplicate probe name"
    else Ok { boot_id; run_id; started_at_ns; sampled_at_ns; heap_words;
              top_heap_words; minor_collections; major_collections; probes }

let boot_id sample = sample.boot_id
let run_id sample = sample.run_id
let started_at_ns sample = sample.started_at_ns
let sampled_at_ns sample = sample.sampled_at_ns
let uptime_ns sample = Int64.sub sample.sampled_at_ns sample.started_at_ns
let heap_words sample = sample.heap_words
let top_heap_words sample = sample.top_heap_words
let minor_collections sample = sample.minor_collections
let major_collections sample = sample.major_collections
let probes sample = sample.probes
let probe_name probe = probe.name
let probe_health probe = probe.health
let probe_checked_at_ns probe = probe.checked_at_ns

let health_code = function Healthy -> "healthy" | Failed -> "failed" | Unknown -> "unknown"

let encode_console sample =
  let fields = [schema; sample.boot_id; sample.run_id;
    Int64.to_string sample.started_at_ns; Int64.to_string sample.sampled_at_ns;
    string_of_int sample.heap_words; string_of_int sample.top_heap_words;
    string_of_int sample.minor_collections; string_of_int sample.major_collections;
    string_of_int (List.length sample.probes)] in
  let probe_fields = List.concat_map (fun probe ->
    [probe.name; health_code probe.health; Int64.to_string probe.checked_at_ns]) sample.probes in
  String.concat "\t" (fields @ probe_fields)

let decimal value =
  let length = String.length value in
  length > 0 && length <= 19 && String.for_all (function '0' .. '9' -> true | _ -> false) value

let parse_int64 kind value =
  if not (decimal value) then Error ("invalid " ^ kind)
  else match Int64.of_string_opt value with
    | Some value -> Ok value
    | None -> Error ("invalid " ^ kind)

let parse_int kind value =
  if not (decimal value) then Error ("invalid " ^ kind)
  else match int_of_string_opt value with
    | Some value -> Ok value
    | None -> Error ("invalid " ^ kind)

let health_of_code = function
  | "healthy" -> Ok Healthy
  | "failed" -> Ok Failed
  | "unknown" -> Ok Unknown
  | _ -> Error "invalid probe health"

let rec parse_probes count fields acc =
  if count = 0 then match fields with
    | [] -> Ok (List.rev acc)
    | _ -> Error "surplus probe fields"
  else match fields with
    | name :: health :: checked_at_ns :: rest ->
        let* health = health_of_code health in
        let* checked_at_ns = parse_int64 "probe timestamp" checked_at_ns in
        let* probe = make_probe ~name ~checked_at_ns health in
        parse_probes (count - 1) rest (probe :: acc)
    | _ -> Error "missing probe fields"

let decode_console line =
  if String.length line = 0 || String.length line > max_console_bytes then
    Error "console frame length is outside bounds"
  else if String.contains line '\n' || String.contains line '\r' then
    Error "console frame must be one line"
  else match String.split_on_char '\t' line with
    | actual_schema :: boot_id :: run_id :: started_at_ns :: sampled_at_ns ::
      heap_words :: top_heap_words :: minor_collections :: major_collections ::
      probe_count :: probe_fields when String.equal actual_schema schema ->
        let* started_at_ns = parse_int64 "startup timestamp" started_at_ns in
        let* sampled_at_ns = parse_int64 "sample timestamp" sampled_at_ns in
        let* heap_words = parse_int "heap words" heap_words in
        let* top_heap_words = parse_int "peak heap words" top_heap_words in
        let* minor_collections = parse_int "minor collection count" minor_collections in
        let* major_collections = parse_int "major collection count" major_collections in
        let* probe_count = parse_int "probe count" probe_count in
        if probe_count < 0 || probe_count > max_probes then Error "probe count is outside bounds"
        else
          let* probes = parse_probes probe_count probe_fields [] in
          let* sample = make_sample ~boot_id ~run_id ~started_at_ns ~sampled_at_ns
            ~heap_words ~top_heap_words ~minor_collections ~major_collections probes in
          if String.equal line (encode_console sample) then Ok sample
          else Error "console frame is not canonical"
    | _ -> Error "invalid console schema or field count"

let seconds_of_ns nanoseconds =
  let seconds = Int64.div nanoseconds 1_000_000_000L in
  let remainder = Int64.rem nanoseconds 1_000_000_000L in
  Printf.sprintf "%Ld.%09Ld" seconds remainder

let add_metric buffer name labels value =
  Printf.bprintf buffer "%s{%s} %s\n" name labels value

let render_prometheus sample =
    let buffer = Buffer.create 2048 in
    Buffer.add_string buffer "# UOS transport: guest_console; projection: host_http\n";
    Buffer.add_string buffer
      "# UOS identity: operator_supplied_untrusted; provenance: external_capture_required\n";
    Buffer.add_string buffer
      "# UOS freshness: unknown_without_host_receipt_clock\n";
    Buffer.add_string buffer "# TYPE uos_mirage_guest_uptime_seconds gauge\n";
    let identity = Printf.sprintf "boot_id=\"%s\",run_id=\"%s\"" sample.boot_id sample.run_id in
    add_metric buffer "uos_mirage_guest_uptime_seconds" identity (seconds_of_ns (uptime_ns sample));
    Buffer.add_string buffer
      "# HELP uos_mirage_guest_gc_observation_info Raw runtime snapshot; availability is unknown and values are not total or resident memory.\n";
    Buffer.add_string buffer "# TYPE uos_mirage_guest_gc_observation_info gauge\n";
    add_metric buffer "uos_mirage_guest_gc_observation_info"
      (identity ^ ",availability=\"unknown\"") "1";
    Buffer.add_string buffer "# TYPE uos_mirage_guest_gc_heap_words_raw gauge\n";
    add_metric buffer "uos_mirage_guest_gc_heap_words_raw" identity
      (string_of_int sample.heap_words);
    Buffer.add_string buffer "# TYPE uos_mirage_guest_gc_heap_peak_words_raw gauge\n";
    add_metric buffer "uos_mirage_guest_gc_heap_peak_words_raw" identity
      (string_of_int sample.top_heap_words);
    Buffer.add_string buffer "# TYPE uos_mirage_guest_gc_minor_collections_raw gauge\n";
    add_metric buffer "uos_mirage_guest_gc_minor_collections_raw" identity
      (string_of_int sample.minor_collections);
    Buffer.add_string buffer "# TYPE uos_mirage_guest_gc_major_collections_raw gauge\n";
    add_metric buffer "uos_mirage_guest_gc_major_collections_raw" identity
      (string_of_int sample.major_collections);
    Buffer.add_string buffer "# TYPE uos_mirage_guest_probe_health gauge\n";
    Buffer.add_string buffer "# TYPE uos_mirage_guest_probe_age_at_sample_seconds gauge\n";
    List.iter (fun probe ->
      let labels = Printf.sprintf "%s,probe=\"%s\"" identity probe.name in
      let health_value = match probe.health with Healthy -> "1" | Failed -> "0" | Unknown -> "-1" in
      let age = Int64.sub sample.sampled_at_ns probe.checked_at_ns in
      add_metric buffer "uos_mirage_guest_probe_health" labels health_value;
      add_metric buffer "uos_mirage_guest_probe_age_at_sample_seconds" labels
        (seconds_of_ns age)
    ) sample.probes;
    let output = Buffer.contents buffer in
    if String.length output > max_prometheus_bytes then Error "Prometheus projection exceeds bound"
    else Ok output

let decode_and_render line =
  let* sample = decode_console line in
  render_prometheus sample

let observationally_equal a b =
  String.equal a.boot_id b.boot_id && String.equal a.run_id b.run_id
  && Int64.equal a.started_at_ns b.started_at_ns
  && Int64.equal a.sampled_at_ns b.sampled_at_ns
  && a.heap_words = b.heap_words && a.top_heap_words = b.top_heap_words
  && a.minor_collections = b.minor_collections
  && a.major_collections = b.major_collections
  && List.equal (fun x y -> String.equal x.name y.name
    && Int64.equal x.checked_at_ns y.checked_at_ns && x.health = y.health) a.probes b.probes
