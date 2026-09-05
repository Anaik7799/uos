let command_keyexpr = "hermes/*/completion/*"

let handle ?dispatcher ~execute ~key ~payload () =
  match Ops_command.dispatch_zenoh ?dispatcher ~execute ~key ~payload () with
  | Error _ as error -> error
  | Ok observation -> Ok (Ops_command.receipt_json observation.receipt)

let serve ?dispatcher ~execute () =
  let callback key payload =
    match handle ?dispatcher ~execute ~key ~payload () with
    | Ok receipt -> receipt
    | Error message ->
        `Assoc [ ("verdict", `String "blocked"); ("error", `String message) ]
        |> Yojson.Safe.to_string
  in
  Hermes_zenoh.serve_queryable ~keyexpr:command_keyexpr ~callback
