(* Standalone driver for the route-algebra laws. The laws themselves live in
   route_laws.ml so the harness's formal stage runs the SAME code — a second
   copy of a specification is a specification that will disagree with itself. *)

let () =
  let root =
    match Sys.getenv_opt "ZIGVM_ROOT" with
    | Some r -> r
    | None -> Sys.getcwd ()
  in
  let n = Route_laws.run ~root in
  Printf.printf "route-algebra: %d law(s) passed\n" n
