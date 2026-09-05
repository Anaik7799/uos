type decision =
  | Admitted
  | Rejected of Nix_error.t

let check_path_sandbox path =
  if String.contains path '\000' then
    Error (Nix_error.Policy_violation { rule = "R31-NULL-BYTE"; description = "Path contains forbidden null byte" })
  else if String.length path > 1024 then
    Error (Nix_error.Policy_violation { rule = "R31-MAX-PATH"; description = "Path exceeds 1024 bytes" })
  else if String.starts_with ~prefix:"/etc/shadow" path || String.starts_with ~prefix:"/root/.ssh" path then
    Error (Nix_error.Impure_access_blocked { attempted_path = path })
  else
    Ok ()

let check_flake_ref f =
  let s = Nix_id.Flake_ref.to_string f in
  if String.length s = 0 then
    Error (Nix_error.Policy_violation { rule = "R31-EMPTY-FLAKE"; description = "Empty flake reference" })
  else if String.contains s '\000' then
    Error (Nix_error.Policy_violation { rule = "R31-NULL-BYTE"; description = "Flake ref contains null byte" })
  else
    Ok ()

let evaluate_intent intent =
  match intent with
  | Nix_intent.Evaluate { target; budget; pure = _ } ->
      (match Nix_budget.validate budget with
       | Error msg -> Rejected (Nix_error.Policy_violation { rule = "R31-BUDGET-INVALID"; description = msg })
       | Ok () ->
           (match target with
            | Nix_intent.Flake_attribute { flake_ref; _ } ->
                (match check_flake_ref flake_ref with
                 | Error e -> Rejected e
                 | Ok () -> Admitted)
            | Nix_intent.Raw_expression { expr } ->
                if String.length expr > 64 * 1024 then
                  Rejected (Nix_error.Policy_violation { rule = "R31-EXPR-TOO-LARGE"; description = "Expression exceeds 64KB" })
                else Admitted
            | Nix_intent.File_expression { path } ->
                (match check_path_sandbox path with
                 | Error e -> Rejected e
                 | Ok () -> Admitted)))

  | Nix_intent.Build { target; budget; _ } ->
      (match Nix_budget.validate budget with
       | Error msg -> Rejected (Nix_error.Policy_violation { rule = "R31-BUDGET-INVALID"; description = msg })
       | Ok () ->
           (match target with
            | Nix_intent.Build_flake_attr { flake_ref; _ } ->
                (match check_flake_ref flake_ref with
                 | Error e -> Rejected e
                 | Ok () -> Admitted)
            | Nix_intent.Build_drv { drv_path } ->
                (match check_path_sandbox (Nix_id.Store_path.to_string drv_path) with
                 | Error e -> Rejected e
                 | Ok () -> Admitted)
            | Nix_intent.Build_store_path { path } ->
                (match check_path_sandbox (Nix_id.Store_path.to_string path) with
                 | Error e -> Rejected e
                 | Ok () -> Admitted)))

  | Nix_intent.Shell_environment { flake_ref; budget } ->
      (match Nix_budget.validate budget with
       | Error msg -> Rejected (Nix_error.Policy_violation { rule = "R31-BUDGET-INVALID"; description = msg })
       | Ok () ->
           (match check_flake_ref flake_ref with
            | Error e -> Rejected e
            | Ok () -> Admitted))

  | Nix_intent.Flake_lock { flake_ref; _ } ->
      (match check_flake_ref flake_ref with
       | Error e -> Rejected e
       | Ok () -> Admitted)

  | Nix_intent.Flake_security { flake_ref; _ } ->
      (match check_flake_ref flake_ref with
       | Error e -> Rejected e
       | Ok () -> Admitted)

  | Nix_intent.Store_verify { paths; _ } ->
      let check_all =
        List.fold_left
          (fun acc p ->
             match acc with
             | Error e -> Error e
             | Ok () -> check_path_sandbox (Nix_id.Store_path.to_string p))
          (Ok ()) paths
      in
      (match check_all with
       | Error e -> Rejected e
       | Ok () -> Admitted)

  | Nix_intent.Store_gc _ -> Admitted

  | Nix_intent.Devenv_execute { root; budget; _ } ->
      (match Nix_budget.validate budget with
       | Error msg -> Rejected (Nix_error.Policy_violation { rule = "R31-BUDGET-INVALID"; description = msg })
       | Ok () ->
           (match check_path_sandbox (Nix_id.Devenv_root.to_string root) with
            | Error e -> Rejected e
            | Ok () -> Admitted))
