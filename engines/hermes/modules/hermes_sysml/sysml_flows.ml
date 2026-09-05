(* modules/hermes_sysml/sysml_flows.ml *)

type _ Effect.t += 
  | Emit_flow : string * 'a -> unit Effect.t
  | Trace_sequence : string * string * string -> unit Effect.t

let emit_flow name value = Effect.perform (Emit_flow (name, value))
let trace_sequence src dst msg = Effect.perform (Trace_sequence (src, dst, msg))

let run_with_tracing f =
  let open Effect.Deep in
  let handler = {
    retc = (fun x -> x);
    exnc = (fun e -> raise e);
    effc = fun (type a) (eff : a Effect.t) ->
      match eff with
      | Emit_flow (name, _val) ->
          Some (fun (k : (a, _) continuation) ->
            Printf.printf "[Flow] Emitted on stream %s\n" name;
            continue k ())
      | Trace_sequence (src, dst, msg) ->
          Some (fun (k : (a, _) continuation) ->
            Printf.printf "[Sequence] %s -> %s : %s\n" src dst msg;
            continue k ())
      | _ -> None
  } in
  match_with f () handler
