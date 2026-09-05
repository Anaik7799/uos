(* The Reference_capture -> Fractal_diagnostic adapter, split out of
   fractal_diagnostic so the diagnostic CORE carries no parity-harness
   dependency and can remain below the harness in hermes_wiki/src/fpp.
   Same behaviour, same hazards, one home. *)

open Fractal_diagnostic

(* Reference capture failures, classified. The distinction that matters is
   Environment versus Evidence: a missing interpreter proved nothing, while an
   edited fixture is corrupted evidence, and only the latter says something is
   wrong with what we have recorded. *)
let of_capture_failure ?(node = "") ?(subject = "") (failure : Reference_capture.failure) =
  let common ~hazard ~origin ~impact ~cause ~fix =
    make ~hazard ~level:L4_fixture ~origin ~impact ~node ~subject
      ~message:(Reference_capture.describe failure) ~cause ~fix ()
  in
  match failure with
  | Reference_capture.Interpreter_missing _ ->
      common ~hazard:"HZ-CAP-01" ~origin:Environment ~impact:Blocks_credit
        ~cause:"the reference interpreter is not provisioned, so the reference never ran"
        ~fix:"provision state/reference_env, or set HERMES_REFERENCE_PYTHON"
  | Reference_capture.Adapter_missing _ ->
      common ~hazard:"HZ-CAP-01" ~origin:Control ~impact:Blocks_credit
        ~cause:"the harness cannot find its own reference adapter"
        ~fix:"restore hermes_harness/reference_adapter/build_kwargs_adapter.py"
  | Reference_capture.Reference_missing _ ->
      common ~hazard:"HZ-CAP-01" ~origin:Environment ~impact:Blocks_credit
        ~cause:"the frozen reference snapshot is absent from this checkout"
        ~fix:"restore external/hermes_source at the pinned snapshot"
  | Reference_capture.Timed_out ->
      common ~hazard:"HZ-CAP-02" ~origin:Environment ~impact:Blocks_credit
        ~cause:"the reference did not terminate within the capture deadline"
        ~fix:"investigate the scenario; a reference that hangs is itself a finding"
  | Reference_capture.Exited _ ->
      common ~hazard:"HZ-CAP-02" ~origin:Environment ~impact:Blocks_credit
        ~cause:"the reference process failed before producing a trace"
        ~fix:"read the adapter output; a reference crash may be a real defect in the scenario"
  | Reference_capture.Unreadable _ ->
      common ~hazard:"HZ-CAP-03" ~origin:Evidence ~impact:Blocks_credit
        ~cause:"the adapter produced something that is not a reference trace"
        ~fix:"inspect the raw output; do not record it as a trace"
  | Reference_capture.Reference_error _ ->
      common ~hazard:"HZ-CAP-03" ~origin:Environment ~impact:Blocks_credit
        ~cause:"the reference itself reported an error for this scenario"
        ~fix:"the scenario may be invalid for the reference; fix the scenario, not the trace"
