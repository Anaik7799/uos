(* Homeostasis controls for the convergence loop.

   Imported per R14 from the two prior control systems:
   - c3i stop_hook_lyapunov: windowed telemetry -> graduated P0/P1/P2/green
     alerts with a runbook hint, and the honesty rule that ABSENCE of
     telemetry is never a violation.
   - c3i hysteresis/circuit-breaker family + zigvm's cross-run monotone
     frontier discipline (the satisfied set never shrinks while the candidate
     only gains evidence; a shrink is a regression, never noise).

   Pure end to end -- the loop feeds real telemetry (the store's recorded
   frontier trajectory, per-scenario receipt history, oracle outcomes) and
   acts only by refusing, alerting, and naming runbook candidates. Nothing
   here grants or denies parity credit (R10). *)

type alert = Green | P2 of string | P1 of string | P0 of string

let severity = function Green -> 0 | P2 _ -> 1 | P1 _ -> 2 | P0 _ -> 3

(* Keep-worst join: the control plane composes exactly like the evidence
   plane's combine (higher severity absorbs). Empty is Green -- an empty
   alert list means nothing fired, not that nothing was watched. *)
let worst alerts =
  List.fold_left (fun acc alert -> if severity alert > severity acc then alert else acc)
    Green alerts

let describe = function
  | Green -> "green"
  | P2 detail -> "P2 -- " ^ detail
  | P1 detail -> "P1 -- " ^ detail
  | P0 detail -> "P0 -- " ^ detail

(* V = distance from the declared goal. Non-negative by construction. *)
let lyapunov ~total ~satisfied = max 0 (total - satisfied)

(* Cross-run descent gate. Shrink-detection on the satisfied COUNT rather than
   a raw V-rise so that legitimately growing the blueprint (total goes up, V
   goes up) never false-alarms: with a fixed candidate the satisfied set is
   monotone non-decreasing across runs, so any strict shrink between
   consecutive observations is a real regression (the cross-run twin of
   Converge's in-run monotone guard). *)
let frontier_alert ~satisfied_counts ~total =
  match satisfied_counts with
  | [] -> Green (* absence of telemetry is not a violation (c3i rule) *)
  | first :: rest ->
      let rec find_shrink previous = function
        | [] -> None
        | current :: remaining ->
            if current < previous then Some (previous, current)
            else find_shrink current remaining
      in
      (match find_shrink first rest with
      | Some (from_count, to_count) ->
          P0
            (Printf.sprintf
               "frontier regressed: satisfied intents fell %d -> %d across recorded runs \
                (a previously satisfied intent was lost) -- stop the line, find the \
                regressing slice before any new work"
               from_count to_count)
      | None ->
          let last = List.fold_left (fun _ current -> current) first rest in
          let observations = 1 + List.length rest in
          let stalled =
            observations >= 3
            && List.for_all (fun count -> count = first) rest
            && lyapunov ~total ~satisfied:last > 0
          in
          if stalled then
            P2
              (Printf.sprintf
                 "frontier stalled at %d/%d satisfied across %d recorded runs -- the \
                  runbook's residual work is not landing"
                 last total observations)
          else Green)

(* State changes across a chronological window. *)
let transitions window =
  match window with
  | [] -> 0
  | first :: rest ->
      snd
        (List.fold_left
           (fun (previous, count) current ->
             (current, if current <> previous then count + 1 else count))
           (first, 0) rest)

(* Hysteresis sensor. Instability (>= 2 transitions) is the finding here; a
   plain latest-state failure is the differential compare's finding, not ours
   -- one authority per signal, so a constant-fail window stays Green in THIS
   sensor. *)
let flap_alert ~scenario ~window =
  match transitions window with
  | 0 -> Green
  | 1 ->
      P2
        (scenario
        ^ " changed state once in the recorded window (a fix or a regression -- the \
           compare names which)")
  | n ->
      P1
        (Printf.sprintf
           "%s is flapping (%d transitions in the recorded window) -- quarantine \
            candidate: pin the nondeterminism before trusting its receipts"
           scenario n)

(* Regression sensor: a scenario that PASSED earlier and FAILS at the window's
   end regressed between runs -- jidoka territory, distinct from a first-time
   failure (which is a first measurement, the compare's finding) and from a
   recovery (latest passes). *)
let regressed ~window =
  let rec latest = function [] -> None | [ last ] -> Some last | _ :: tl -> latest tl in
  match latest window with
  | Some false -> List.exists (fun passed -> passed) window
  | Some true | None -> false

let regression_alert ~scenario ~window =
  if regressed ~window then
    P0
      (scenario
      ^ " regressed: previously passing, latest receipt fails -- stop the line and \
         find the regressing change before any new work")
  else Green

(* Circuit breaker. An open breaker never half-opens on its own: re-closing is
   a deliberate human act (an unattended retry of a possibly-destructive
   oracle is the L-09 incident class). *)
type breaker = { threshold : int; consecutive_failures : int; opened : bool }

let breaker ~threshold =
  { threshold = max 1 threshold; consecutive_failures = 0; opened = false }

let observe state ~ok =
  if state.opened then state
  else if ok then { state with consecutive_failures = 0 }
  else
    let consecutive_failures = state.consecutive_failures + 1 in
    { state with
      consecutive_failures;
      opened = consecutive_failures >= state.threshold }

let admits state = not state.opened
let failures state = state.consecutive_failures
