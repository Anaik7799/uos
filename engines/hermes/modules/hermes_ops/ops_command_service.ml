let default_orientation_path = "state/hermes/orientation-history.sqlite3"
let default_history_location =
  Dependability_sqlite_location.registered
    Dependability_sqlite_location.Completion_history_store

let now_ns () = Unix.gettimeofday () *. 1e9 |> Int64.of_float

let surface_name = function
  | Ops_command.Ocaml_api -> "ocaml-api"
  | Cli -> "cli"
  | Mcp -> "mcp"
  | Zenoh -> "zenoh"

let request_body (request : Ops_command.request) =
  `Assoc
    [ ("request_id", `String request.request_id);
      ("action", `String (Ops_command.action_name request.action));
      ("scope", `String (Ops_command.scope_name request.scope)) ]
  |> Yojson.Safe.to_string

let sha256 text = text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let dispatch ?(root = ".") ?(history_location = default_history_location) ~execute ~surface request =
      begin match Ops_completion_history.open_store history_location with
      | Error _ as error -> error
      | Ok store ->
          Fun.protect
            ~finally:(fun () -> Ops_completion_history.close store)
            (fun () ->
              let started_ns = now_ns () in
              let body = request_body request in
              let surface_text = surface_name surface in
              let interaction_id =
                sha256
                  (String.concat "\000"
                     [ request.request_id; surface_text; Int64.to_string started_ns; body ])
              in
              let interaction : Ops_completion_history.interaction =
                { interaction_id; run_id = request.request_id;
                  actor = "command-surface:" ^ surface_text;
                  kind = Ops_completion_history.Command; body;
                  recorded_at_ns = started_ns }
              in
              match Ops_completion_history.append_interaction store interaction with
              | Error _ as error -> error
              | Ok () ->
                  let source = Ops_observability.source_context ~root in
                  let observation = Ops_command.dispatch ~execute ~surface request in
                  let finished_ns = now_ns () in
                  let event =
                    Ops_observability.event ~run_id:request.request_id ~started_ns
                      ~finished_ns ~source observation
                  in
                  begin match Ops_completion_history.record store event observation.receipt with
                  | Ok () -> Ok observation
                  | Error message -> Error ("command audit failed after execution: " ^ message)
                  end)
      end
