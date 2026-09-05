let fail code errors =
  List.iter (fun error -> Printf.eprintf "zellij-harness: %s\n" error) errors;
  exit code

let intent () =
  match Zellij_intent.default () with
  | Ok value -> value
  | Error errors -> fail 1 errors

let launcher_source () =
  Filename.concat (Filename.dirname Sys.executable_name) "zellij_attach.exe"

let print_fact render = function
  | Zellij_observe.Known value -> render value
  | Zellij_observe.Unknown reason -> "Unavailable_observed(" ^ reason ^ ")"

let show_status observation =
  Printf.printf "version: %s\n"
    (print_fact (fun value -> value) (Zellij_observe.version observation));
  Printf.printf "sessions: %s\n"
    (print_fact
       (fun sessions ->
         sessions |> List.map Zellij_intent.session_name |> String.concat ",")
       (Zellij_observe.sessions observation));
  Printf.printf "config: %s\n"
    (print_fact
       (function None -> "missing" | Some value -> value)
       (Zellij_observe.config_digest observation))

let () =
  match Zellij_configurator.command_of_argv Sys.argv with
  | Error message -> fail 64 [ message ]
  | Ok command -> (
      let intent = intent () in
      match command with
      | Zellij_configurator.Plan -> (
          match
            Zellij_configurator.plan intent (Zellij_observe.observe intent)
          with
          | Error errors -> fail 1 errors
          | Ok [] -> print_endline "plan: current; no changes"
          | Ok changes ->
              List.iter
                (fun change ->
                  Printf.printf "plan: %s\n"
                    (Zellij_configurator.render_change change))
                changes)
      | Check -> (
          match Zellij_configurator.preflight intent with
          | Ok () -> print_endline "check: all declared resources satisfied"
          | Error errors -> fail 1 errors)
      | Apply -> (
          let observation = Zellij_observe.observe intent in
          match Zellij_configurator.plan intent observation with
          | Error errors -> fail 1 errors
          | Ok changes -> (
              match
                Zellij_configurator.apply ~launcher_source:(launcher_source ())
                  intent changes
              with
              | Error errors -> fail 1 errors
              | Ok receipt ->
                  Printf.printf "apply: %d changes; intent=%s config=%s\n"
                    (List.length receipt.applied)
                    receipt.intent_digest receipt.config_digest))
      | Ensure -> (
          let observation = Zellij_observe.observe intent in
          match Zellij_configurator.plan intent observation with
          | Error errors -> fail 1 errors
          | Ok changes -> (
              let changes =
                List.filter
                  (function
                    | Zellij_configurator.Ensure_session _ -> true | _ -> false)
                  changes
              in
              match
                Zellij_configurator.apply ~launcher_source:(launcher_source ())
                  intent changes
              with
              | Error errors -> fail 1 errors
              | Ok receipt ->
                  Printf.printf "ensure: %d sessions created\n"
                    (List.length receipt.applied)))
      | Status -> show_status (Zellij_observe.observe intent)
      | Docs_audit ->
          let errors = Zellij_atlas.validate () in
          if errors = [] then
            Printf.printf
              "docs-audit: %d official pages classified \
               Documented_only/No_credit\n"
              (List.length Zellij_atlas.documentation_pages)
          else fail 1 errors)
