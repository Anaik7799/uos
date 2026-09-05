let fail message =
  Printf.eprintf "zellij-attach: %s\n" message;
  exit 64

let () =
  match Zellij_configurator.launcher_session Sys.argv.(0) with
  | Error message -> fail message
  | Ok session -> (
      match Zellij_intent.default () with
      | Error errors -> fail (String.concat "; " errors)
      | Ok intent -> (
          let zellij = Zellij_intent.zellij_bin intent in
          let name = Zellij_intent.session_name session in
          try Unix.execv zellij [| zellij; "attach"; "--create"; name |]
          with exn -> fail (Printexc.to_string exn)))
