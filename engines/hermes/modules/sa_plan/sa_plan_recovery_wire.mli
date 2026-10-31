(* Factual request serialization only. No store, authorization or effect.
   Closed <=32768-byte input object: request_id,plan,snapshot_sha256,members,
   deadline_utc_ms. Each of exactly3 distinct members has task_id,worker,
   old_attempt,old_lease_ns,lease_ms. All durations must equal; no member lost.
   Strings containing nanoseconds must be canonical positive Int64 decimals.
   UTC millisecond deadline must fit positive Int64 nanoseconds after multiply.
   Clock fields are supplied DATA, never observations. The native v1 request
   digest does NOT bind portfolio/review/proposal or capability. Future effect
   integration needs its own authenticated envelope and independent review.
   This parser is bounded by input bytes/depth/nodes, not a streaming allocator. *)
(* Closed integer JSON grammar rejects comments, unquoted object keys,
   duplicate keys, trailing commas and malformed string escapes. *)
type t
type error = Invalid_input
val decode : string -> (t,error) result
val canonical_bytes : t -> string
val request_sha256 : t -> string
val tagged_request_sha256 : t -> string
