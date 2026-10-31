(** Native recovery verification PREREQUISITE. No issuer, signer, executor or
    production trust anchor exists here. Public configuration values are DATA,
    even when their bytes match a caller-provided digest. They do not admit a
    launcher, prove custody/independence, or authorize Store mutation. *)
type configuration_data
type verified_evidence
type historical_evidence
type clock = { utc_ns:int64; mono_ns:int64; host:string; boot:string; domain:string }
val profile : string
val fixed_plan : string
val fixed_members : (string * string) list
val sha256 : string -> string
val configuration_data : string -> (configuration_data,string) result
val configuration_sha256 : configuration_data -> string

(** Cooperative, single-owner regular-file capture only. A supplied expected
    SHA is not independently authenticated launcher authority. *)
val read_pinned_data : path:string -> sha256:string -> (configuration_data,string) result

(** Linux Mtime_clock.now_ns is CLOCK_MONOTONIC. It is NOT elapsed_ns (whose
    Linux origin/clock differs), BEAM monotonic time, or synchronized UTC proof. *)
val native_clock : unit -> (clock,string) result
val review_message : string -> string
val issuer_message : string -> reviewer_signature:string -> string
val verify : configuration_data -> request_bytes:string -> capability_bytes:string ->
  reviewer_signature:string -> issuer_signature:string -> (verified_evidence,string) result

(** Signature/fixed-scope authentication only, including expired signed bytes.
    This disjoint type has NO conversion to [verified_evidence]. It proves no
    current permission, time validity, trusted custody or committed history.
    Only exact durable receipt lookup can establish a historical commit fact. *)
val verify_history : configuration_data -> request_bytes:string -> capability_bytes:string ->
  reviewer_signature:string -> issuer_signature:string -> (historical_evidence,string) result
val historical_request_bytes : historical_evidence -> string
val historical_capability_sha256 : historical_evidence -> string
val historical_evidence_sha256 : historical_evidence -> string
val still_valid : verified_evidence -> (clock,string) result
val request_bytes : verified_evidence -> string
val capability_sha256 : verified_evidence -> string
val evidence_sha256 : verified_evidence -> string
val expires_utc_ns : verified_evidence -> int64
val authority : verified_evidence -> string
val production_owner_status : unit -> string
