(** L4 keystone: a digest-pinned session tying one request to its pinned provider
    response and to the reference's normalized decode of that response.

    Mirrors {!Reference_capture}'s discipline (R14 — the zigvm fixture-freshness
    law): a fixture is keyed by (session_id, snapshot_digest); {!load} re-derives
    the normalized digest from the stored reference decode and refuses a mismatch,
    so an edited session is rejected rather than trusted (HZ-FIX-01). It reuses
    {!Reference_capture.sha256} and {!Parity_normalizer} rather than reinventing
    them.

    A session binds the three things a deterministic replay needs together: the
    [request] the candidate sends, the [provider_response] the recorded executor
    replays offline, and the [reference_decode] (the reference's normalized
    decode of that response) — the oracle half a comparison rests on. *)

type request = { endpoint : string; body : Yojson.Safe.t }

type t = {
  session_id : string;
  snapshot_digest : string;
  reference_revision : string;
  request : request;
  provider_response : Yojson.Safe.t;
  reference_decode : Yojson.Safe.t;
  normalized_digest : string;
  normalization : string;
}

type error =
  | Missing of string
  | Unreadable of string
  | Digest_mismatch of string

val describe : error -> string

val make :
  normalizer:Parity_normalizer.t ->
  session_id:string ->
  snapshot_digest:string ->
  reference_revision:string ->
  request:request ->
  provider_response:Yojson.Safe.t ->
  reference_decode:Yojson.Safe.t ->
  t
(** Build a session, computing [normalized_digest] over the normalized reference
    decode. *)

val fixture_path : root:string -> string -> snapshot_digest:string -> string

val to_json : t -> Yojson.Safe.t
val of_json : Yojson.Safe.t -> (t, error) result

val save : root:string -> t -> string
(** Write the session under [hermes_harness/fixtures/sessions/]; returns the path. *)

val load :
  root:string -> normalizer:Parity_normalizer.t -> string -> snapshot_digest:string ->
  (t, error) result
(** Load and re-derive the digest from the stored reference decode; a fixture
    whose recorded digest does not match is rejected with [Digest_mismatch]. *)
