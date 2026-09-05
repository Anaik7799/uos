type fixture = Exit_zero | Exit_nonzero | Timeout | Signal | Output_bound

type capability = { fixture : fixture }

let all_fixtures = [ Exit_zero; Exit_nonzero; Timeout; Signal; Output_bound ]

let key = function
  | Exit_zero -> "exit-zero"
  | Exit_nonzero -> "exit-nonzero"
  | Timeout -> "timeout"
  | Signal -> "signal"
  | Output_bound -> "output-bound"

let declare fixture = { fixture }
let fixture capability = capability.fixture

let unavailable_production_declaration () =
  let request_id =
    match Jj_id.Request.make "process-owner-production" with
    | Ok value -> value
    | Error _ -> failwith "fixed process-owner request identity is invalid"
  in
  Dependability_process_protocol.declare ~request_id
    (List.hd Dependability_process_protocol.all_kinds)
