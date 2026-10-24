module Frame = Sa_plan.Cancel_frame
module Store = Sa_plan.Store

let rejected_error = "cancel_request_rejected"

let has_no_control_chars (s : string) : bool =
  let len = String.length s in
  let rec loop i =    if i >= len then true
    else
      let code = Char.code s.[i] in
      if code < 0x20 || code = 0x7f then false else loop (i + 1)
  in
  loop 0

let valid_db_path (path : string) : bool =
  let len = String.length path in
  if
    len < 2 || len > 4096
    || not (Stdlib.String.is_valid_utf_8 path)
    || path.[0] <> '/'
    || path.[len - 1] = '/'
    || not (has_no_control_chars path)
  then false
  else
    match String.split_on_char '/' path with
    | "" :: segs
      when segs <> []
           && List.for_all (fun s -> s <> "" && s <> "." && s <> "..") segs -> (
        try
          let st = Unix.lstat path in
          st.Unix.st_kind = Unix.S_REG && st.Unix.st_nlink = 1
        with _ -> false)
    | _ -> false

let respond_and_exit (outcome : (Yojson.Safe.t, string) result) : 'a =
  match Frame.write_frame Stdlib.stdout (Frame.response outcome) with
  | Ok () -> Stdlib.exit 0
  | Error _ -> Stdlib.exit 2

let () =
  match Frame.read_frame Stdlib.stdin with
  | Error _ -> Stdlib.exit 2
  | Ok raw_frame -> (
      match Frame.decode raw_frame with
      | Error _ -> respond_and_exit (Error rejected_error)
      | Ok command ->
          let outcome =
            if Array.length Stdlib.Sys.argv <> 2 then Error rejected_error
            else
              let db_path = Stdlib.Sys.argv.(1) in
              if not (valid_db_path db_path) then Error rejected_error
              else
                try
                  match Store.open_existing db_path with
                  | Error _ -> Error rejected_error
                  | Ok store ->
                      Fun.protect
                        ~finally:(fun () -> Store.close store)
                        (fun () ->
                          Frame.execute_observed store command
                            ~observe_now:(fun () ->
                              Core.Time_ns.now ()
                              |> Core.Time_ns.to_int_ns_since_epoch
                              |> Stdlib.Int64.of_int))
                with _ -> Error rejected_error
          in
          respond_and_exit outcome)
