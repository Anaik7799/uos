(* Stage observations published over Zenoh.

   -------------------------------------------------------------------
   WHICH ZENOH, AND WHY IT MATTERS

   There are two Zenoh modules in this repository and only one of them
   is a client. `Swarm_zenoh.publish_telemetry` — which owns the
   `swarm/sensorium/telemetry` key the handover directive names — is a
   `Printf.printf` that returns `true` unconditionally; nothing it is
   given reaches a mesh, and it cannot fail. This module uses
   {!Hermes_zenoh}, which opens a real session against the router
   (`z_open`/`z_put` over vendored zenoh-c) and returns a named error
   when it cannot.

   -------------------------------------------------------------------
   FAIL-OPEN FOR THE PIPELINE, NEVER FAIL-SILENT FOR THE OPERATOR

   A missing router must not fail a video pipeline: telemetry is an
   observation, never authority. But a publish that did not happen must
   not look like one that did, so every attempt returns an {!outcome}
   the caller is expected to disclose. That is R2 applied to telemetry —
   the run continues, and the skip is counted and shown. *)

type outcome =
  | Published of string   (* key it went to *)
  | Refused of string     (* the router or the key said no; reason kept verbatim *)
  | Disabled of string    (* HERMES_ZENOH=0: an explicit opt-out, not a failure *)

val outcome_name : outcome -> string
val is_published : outcome -> bool

(* `hermes/vision/<stage>` — concrete, no wildcards. Publishers never
   use wildcards; those belong to subscribers. *)
val key_for : Vision_ontology.stage -> string

(* The observation as JSON: run id, stage, verdict, fractal level, RCA
   origin, elapsed. Derived from the observation, so a field cannot
   drift from what was measured. *)
val payload : run_id:string -> Vision_controller.observation -> string

val publish : run_id:string -> Vision_controller.observation -> outcome
val publish_all : run_id:string -> Vision_controller.observation list -> outcome list

(* One line per attempt, plus the count that did NOT publish — the
   number an operator needs to know the mesh view is incomplete. *)
val render : outcome list -> string

(* PUBLISHED PAYLOADS CARRY OBSERVATIONS ONLY (publish_telemetry /
   Provided_unsafe). Everything on the mesh reaches every subscriber, so
   a payload that picked up a credential or a private path broadcasts
   it. [redact] replaces anything that looks like configuration rather
   than observation, and [publishable] is the check: false means the
   payload must not go out as it stands. *)
val redact : string -> string
val publishable : string -> bool

(* THE TERMINAL OBSERVATION MUST BE PUBLISHED BEFORE EXIT
   (publish_telemetry / Stopped_too_soon). Otherwise the mesh's last
   view of a failing run is a healthy one. [note_terminal] records that
   it happened; [terminal_published] answers whether it did, and the
   process warns on exit if a run published observations and never
   closed. *)
val note_terminal : unit -> unit
val terminal_published : unit -> bool
