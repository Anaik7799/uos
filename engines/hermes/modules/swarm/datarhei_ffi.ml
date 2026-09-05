(* OCaml FFI Bindings for Embedded Datarhei Core *)

external datarhei_start_transmuxer : string -> string -> int = "caml_datarhei_start_transmuxer"

let start ~source ~sink =
  let result = datarhei_start_transmuxer source sink in
  if result = 0 then
    Ok ()
  else
    Error "Datarhei Core FFI initialization failed"
