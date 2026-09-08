(** Canonical bounded one-shot boot snapshot for the MIG-08 Solo5 console
    guest. [boot_id] and [run_id] are untrusted operator declarations; an
    external capture receipt must bind the frame to guest and tender artifact
    digests. No network listener or current-host freshness claim is implemented
    here. *)

type health = Healthy | Failed | Unknown

type probe
type sample

val schema : string
val max_identifier_bytes : int
val max_probe_name_bytes : int
val max_probes : int
val max_console_bytes : int
val max_prometheus_bytes : int

val make_probe :
  name:string -> checked_at_ns:int64 -> health -> (probe, string) result

val make_sample :
  boot_id:string ->
  run_id:string ->
  started_at_ns:int64 ->
  sampled_at_ns:int64 ->
  heap_words:int ->
  top_heap_words:int ->
  minor_collections:int ->
  major_collections:int ->
  probe list ->
  (sample, string) result

val boot_id : sample -> string
val run_id : sample -> string
val started_at_ns : sample -> int64
val sampled_at_ns : sample -> int64
val uptime_ns : sample -> int64
(* Raw values returned by the runtime's [Gc.quick_stat]. They are not a
   resident-memory measurement, and this schema does not assert that the
   platform implements the counters. *)
val heap_words : sample -> int
val top_heap_words : sample -> int
val minor_collections : sample -> int
val major_collections : sample -> int
val probes : sample -> probe list
val probe_name : probe -> string
val probe_health : probe -> health
val probe_checked_at_ns : probe -> int64

(** A canonical single-line, tab-delimited console frame. *)
val encode_console : sample -> string
val decode_console : string -> (sample, string) result

(** Render a Prometheus text projection of observations at guest sample time.
    Current freshness requires a separately bound host receipt clock. *)
val render_prometheus : sample -> (string, string) result
val decode_and_render : string -> (string, string) result

val observationally_equal : sample -> sample -> bool
