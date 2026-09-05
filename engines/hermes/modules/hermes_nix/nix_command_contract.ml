type t = {
  executable : string;
  args : string list;
  env_overrides : (string * string) list;
  timeout_ms : int;
}

let synthesize intent =
  match Nix_policy.evaluate_intent intent with
  | Nix_policy.Rejected err -> Error err
  | Nix_policy.Admitted ->
      (match intent with
       | Nix_intent.Evaluate { target; budget; pure } ->
           let base_args = [ "eval"; "--json" ] in
           let pure_flag = if pure then [] else [ "--impure" ] in
           (match target with
            | Nix_intent.Flake_attribute { flake_ref; attr } ->
                let target_str =
                  Printf.sprintf "%s#%s" (Nix_id.Flake_ref.to_string flake_ref) (Nix_id.Attribute_path.to_string attr)
                in
                Ok { executable = "nix"; args = base_args @ pure_flag @ [ target_str ]; env_overrides = []; timeout_ms = budget.timeout_ms }
            | Nix_intent.Raw_expression { expr } ->
                Ok { executable = "nix"; args = base_args @ pure_flag @ [ "--expr"; expr ]; env_overrides = []; timeout_ms = budget.timeout_ms }
            | Nix_intent.File_expression { path } ->
                Ok { executable = "nix"; args = base_args @ pure_flag @ [ "--file"; path ]; env_overrides = []; timeout_ms = budget.timeout_ms })

       | Nix_intent.Build { target; budget; keep_going } ->
           let kg_flag = if keep_going then [ "--keep-going" ] else [] in
           (match target with
            | Nix_intent.Build_flake_attr { flake_ref; attr } ->
                let target_str =
                  Printf.sprintf "%s#%s" (Nix_id.Flake_ref.to_string flake_ref) (Nix_id.Attribute_path.to_string attr)
                in
                Ok { executable = "nix"; args = [ "build"; "--no-link" ] @ kg_flag @ [ target_str ]; env_overrides = []; timeout_ms = budget.timeout_ms }
            | Nix_intent.Build_drv { drv_path } ->
                Ok { executable = "nix"; args = [ "build"; "--no-link" ] @ kg_flag @ [ Nix_id.Store_path.to_string drv_path ]; env_overrides = []; timeout_ms = budget.timeout_ms }
            | Nix_intent.Build_store_path { path } ->
                Ok { executable = "nix"; args = [ "build"; "--no-link" ] @ kg_flag @ [ Nix_id.Store_path.to_string path ]; env_overrides = []; timeout_ms = budget.timeout_ms })

       | Nix_intent.Shell_environment { flake_ref; budget } ->
           Ok { executable = "nix";
                args = [ "develop"; "--command"; "true"; Nix_id.Flake_ref.to_string flake_ref ];
                env_overrides = [];
                timeout_ms = budget.timeout_ms }

       | Nix_intent.Flake_lock { flake_ref; update_all } ->
           let u_flag = if update_all then [ "--update-input"; "nixpkgs" ] else [] in
           Ok { executable = "nix";
                args = [ "flake"; "lock" ] @ u_flag @ [ Nix_id.Flake_ref.to_string flake_ref ];
                env_overrides = [];
                timeout_ms = 120_000 }

       | Nix_intent.Flake_security { flake_ref; action } ->
           (match action with
            | Audit ->
                Ok { executable = "nix";
                     args = [ "flake"; "metadata"; "--json"; Nix_id.Flake_ref.to_string flake_ref ];
                     env_overrides = [];
                     timeout_ms = 60_000 }
            | Generate_bom ->
                Ok { executable = "nix";
                     args = [ "flake"; "show"; "--json"; Nix_id.Flake_ref.to_string flake_ref ];
                     env_overrides = [];
                     timeout_ms = 60_000 }
            | Verify_provenance { expected_commit = _ } ->
                Ok { executable = "nix";
                     args = [ "flake"; "metadata"; "--json"; Nix_id.Flake_ref.to_string flake_ref ];
                     env_overrides = [];
                     timeout_ms = 60_000 })

       | Nix_intent.Store_verify { paths; repair } ->
           let r_flag = if repair then [ "--repair" ] else [] in
           let path_strs = List.map Nix_id.Store_path.to_string paths in
           Ok { executable = "nix-store";
                args = [ "--verify"; "--check-contents" ] @ r_flag @ path_strs;
                env_overrides = [];
                timeout_ms = 300_000 }

       | Nix_intent.Store_gc { max_freed_bytes } ->
           let max_flag =
             match max_freed_bytes with
             | Some bytes -> [ "--max-freed"; Int64.to_string bytes ]
             | None -> []
           in
           Ok { executable = "nix-collect-garbage";
                args = [ "-d" ] @ max_flag;
                env_overrides = [];
                timeout_ms = 600_000 }

       | Nix_intent.Devenv_execute { root; action; budget } ->
           let root_str = Nix_id.Devenv_root.to_string root in
           let sub_args =
             match action with
             | Shell { print_bash } -> if print_bash then [ "print-dev-env" ] else [ "shell" ]
             | Up { detach; services } ->
                 let d_flag = if detach then [ "-d" ] else [] in
                 let s_flags = List.map Nix_id.Service_name.to_string services in
                 [ "up" ] @ d_flag @ s_flags
             | Test -> [ "test" ]
             | Build -> [ "build" ]
             | Gc { max_freed_mb = _ } -> [ "gc" ]
             | Info -> [ "info" ]
           in
           Ok { executable = "devenv";
                args = sub_args;
                env_overrides = [ ("DEVENV_ROOT", root_str) ];
                timeout_ms = budget.timeout_ms })

let to_string_summary t =
  Printf.sprintf "%s %s (timeout: %dms)" t.executable (String.concat " " t.args) t.timeout_ms
