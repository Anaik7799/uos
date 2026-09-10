(* Task-authority health: what the Sa-plan task table says about itself.

   Measured 2026-09-10: NINETEEN tasks across fourteen workers sit in state
   `executing` with leases that expired days ago, and one task is claimed by a
   worker literally named "--help" -- a flag that became an identity.

   Heijunka is a pull queue, and a pull queue is only as truthful as its task
   state. Nineteen tasks asserting they are being worked, by sessions that ended
   on 2026-09-07, is not a leveled queue; it is a queue lying about its depth.

   THE ONE THING THIS MODULE REFUSES TO SAY.

   There is no `Abandoned` constructor, and there will not be one. An expired
   lease is a POINT-IN-TIME OBSERVABLE; whether the worker is gone is a LIVENESS
   PROPERTY, and this review has already paid for confusing the two -- a source
   manifest standing for process quiescence, a reap receipt standing for
   descendant death. A lease can expire while its holder is mid-effect, and a
   sweeper that reclaimed on expiry alone would corrupt exactly the work it was
   meant to tidy.

   So the type says `Lease_expired`, which is a fact, and carries
   `quiescence = Unknown`, which is the truth. Reclaiming is a decision for the
   owner with evidence, never a consequence of this observation. *)

type quiescence =
  | Unknown  (** the only value this module can produce, and it says so *)

type finding =
  | Lease_expired of { plan : string; task : string; worker : string;
                       expired_seconds : int; quiescence : quiescence }
  | Worker_not_an_identity of { plan : string; task : string; worker : string;
                                reason : string }

type row = {
  plan : string;
  task : string;
  state : string;
  worker : string;
  lease_until_ns : int;
}

(* A worker name is an identity, not an argument. `--help` reached the worker
   column of a live task because nothing rejected a flag there. The bar is
   deliberately low -- this is a poka-yoke against a slip, not an authentication
   scheme, and saying so is part of the check. *)
let worker_is_identity (w : string) : (unit, string) result =
  let w' = String.trim w in
  if w' = "" then Error "empty"
  else if String.length w' >= 1 && w'.[0] = '-' then
    Error "begins with '-': a command-line flag is not a worker identity"
  else if String.length w' > 128 then Error "longer than 128 bytes"
  else
    let ok c =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      || (c >= '0' && c <= '9') || c = '-' || c = '_' || c = '.' || c = ':'
    in
    let rec scan i =
      if i >= String.length w' then Ok ()
      else if ok w'.[i] then scan (i + 1)
      else Error (Printf.sprintf "character %C is not admitted in a worker identity" w'.[i])
    in
    scan 0

(* Only `executing` rows are judged. An available or completed task holds no
   lease, so an old timestamp on one is history, not a finding -- reporting it
   would be noise that trains readers to ignore the real ones. *)
let inspect ~(now_ns : int) (r : row) : finding list =
  if r.state <> "executing" then []
  else
    let expiry =
      if r.lease_until_ns > 0 && r.lease_until_ns < now_ns then
        [ Lease_expired
            { plan = r.plan; task = r.task; worker = r.worker;
              expired_seconds = (now_ns - r.lease_until_ns) / 1_000_000_000;
              quiescence = Unknown } ]
      else []
    in
    let identity =
      match worker_is_identity r.worker with
      | Ok () -> []
      | Error reason ->
        [ Worker_not_an_identity
            { plan = r.plan; task = r.task; worker = r.worker; reason } ]
    in
    expiry @ identity

let scan ~(now_ns : int) (rows : row list) : finding list =
  List.concat_map (inspect ~now_ns) rows

let is_expiry = function Lease_expired _ -> true | _ -> false
let is_identity = function Worker_not_an_identity _ -> true | _ -> false

let describe = function
  | Lease_expired f ->
    Printf.sprintf
      "%s/%s held by %S: lease expired %ds ago, state still 'executing'. \
       Quiescence UNKNOWN -- expiry is not evidence the worker is gone."
      f.plan f.task f.worker f.expired_seconds
  | Worker_not_an_identity f ->
    Printf.sprintf "%s/%s: worker %S is not an identity (%s)"
      f.plan f.task f.worker f.reason

(* Reporting is the whole authority. Kept as an explicit function so a future
   caller that wants to reclaim has to write that decision itself, in the open,
   rather than inherit it from a helper that quietly did it. *)
let authority = "REPORT_ONLY"
let remediation_is_not_automatic = true
