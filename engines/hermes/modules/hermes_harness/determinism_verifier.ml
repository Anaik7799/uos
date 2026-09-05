(* Determinacy gate: replay a producer twice and byte-compare the normalized
   renders. Any variance is a Control-origin defect (a non-reproducible apparatus
   proves nothing about parity; a flaky pass is false credit -- HZ-DET-01). This
   is the zigvm GATE-DETERMINACY principle: fix instability constructively, never
   hide it by re-running. Reuses Reference_capture.sha256 and Parity_normalizer. *)

type verdict = Stable of string | Unstable of { first : string; second : string }

let digest ~normalizer value =
  Reference_capture.sha256 (Parity_normalizer.render normalizer value)

let check ~normalizer producer =
  let first = digest ~normalizer (producer ()) in
  let second = digest ~normalizer (producer ()) in
  if String.equal first second then Stable first else Unstable { first; second }

let to_diagnostic ~scenario_id ~node = function
  | Stable _ -> None
  | Unstable { first; second } ->
      Some
        (Fractal_diagnostic.make ~hazard:"HZ-DET-01" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit ~node
           ~subject:scenario_id
           ~message:
             (Printf.sprintf "non-deterministic replay: %s vs %s across two runs" first second)
           ~cause:
             "the candidate producer rendered two different normalized traces for the same input"
           ~fix:
             "make the pipeline deterministic (no RNG, wall-clock, or hash-order dependence); \
              never hide it by re-running until it passes"
           ())
