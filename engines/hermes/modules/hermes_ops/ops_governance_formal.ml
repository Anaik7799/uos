type verdict = Proved | Refuted of string | Unavailable of string

let normalized_lines output =
  output
  |> String.split_on_char '\n'
  |> List.map String.trim
  |> List.filter (fun line -> not (String.equal line ""))

let render_lines lines = String.concat ", " lines

let validate_output output =
  match normalized_lines output with
  | [ "unsat"; "unsat"; "sat" ] -> Proved
  | ([ first; second; control ] as lines)
    when List.for_all
           (fun line -> String.equal line "sat" || String.equal line "unsat")
           lines ->
      Refuted
        (Printf.sprintf
           "expected theorem negations [unsat, unsat] and non-vacuity control sat; got [%s]"
           (render_lines [ first; second; control ]))
  | lines when List.exists (String.equal "unknown") lines ->
      Unavailable
        (Printf.sprintf "solver returned unknown: [%s]" (render_lines lines))
  | lines ->
      Unavailable
        (Printf.sprintf "expected exactly three solver verdicts; got [%s]"
           (render_lines lines))

let run () =
  try
    let stdout_channel, stdin_channel, stderr_channel =
      Unix.open_process_full "z3 -in" (Unix.environment ())
    in
    output_string stdin_channel (Ops_governance_model.formal_smt2 ());
    flush stdin_channel;
    close_out stdin_channel;
    let stdout = In_channel.input_all stdout_channel in
    let stderr = In_channel.input_all stderr_channel |> String.trim in
    match Unix.close_process_full (stdout_channel, stdin_channel, stderr_channel) with
    | Unix.WEXITED 0 -> validate_output stdout
    | Unix.WEXITED 127 -> Unavailable "z3 executable is unavailable"
    | Unix.WEXITED code ->
        Refuted
          (Printf.sprintf "z3 exited %d%s" code
             (if String.equal stderr "" then "" else ": " ^ stderr))
    | Unix.WSIGNALED signal ->
        Unavailable (Printf.sprintf "z3 was signalled (%d)" signal)
    | Unix.WSTOPPED signal ->
        Unavailable (Printf.sprintf "z3 was stopped (%d)" signal)
  with
  | Sys_error message -> Unavailable ("z3 invocation failed: " ^ message)
  | Unix.Unix_error (error, function_name, argument) ->
      Unavailable
        (Printf.sprintf "z3 invocation failed in %s(%s): %s" function_name
           argument (Unix.error_message error))

let string_of_verdict = function Proved -> "proved" | Refuted text -> "refuted: " ^ text | Unavailable text -> "unavailable: " ^ text
