open Mirage

let boot_id : string Runtime_arg.arg =
  Runtime_arg.create ~pos:__POS__ "Unikernel.boot_id"

let run_id : string Runtime_arg.arg =
  Runtime_arg.create ~pos:__POS__ "Unikernel.run_id"

let main =
  main ~pos:__POS__
    ~packages:[package "cmdliner"; package "lwt"]
    ~runtime_args:[Runtime_arg.v boot_id; Runtime_arg.v run_id]
    "Unikernel.Make" (mtime @-> job)

let () =
  register "uos-mirage-metrics"
    ~sleep:default_sleep ~ptime:default_ptime ~random:no_random
    [main $ default_mtime]
