type eval_target =
  | Flake_attribute of { flake_ref : Nix_id.Flake_ref.t; attr : Nix_id.Attribute_path.t }
  | Raw_expression of { expr : string }
  | File_expression of { path : string }

type build_target =
  | Build_flake_attr of { flake_ref : Nix_id.Flake_ref.t; attr : Nix_id.Attribute_path.t }
  | Build_drv of { drv_path : Nix_id.Store_path.t }
  | Build_store_path of { path : Nix_id.Store_path.t }

type devenv_action =
  | Shell of { print_bash : bool }
  | Up of { detach : bool; services : Nix_id.Service_name.t list }
  | Test
  | Build
  | Gc of { max_freed_mb : int option }
  | Info

type flake_security_action =
  | Audit
  | Generate_bom
  | Verify_provenance of { expected_commit : string }

type t =
  | Evaluate of { target : eval_target; budget : Nix_budget.t; pure : bool }
  | Build of { target : build_target; budget : Nix_budget.t; keep_going : bool }
  | Shell_environment of { flake_ref : Nix_id.Flake_ref.t; budget : Nix_budget.t }
  | Flake_lock of { flake_ref : Nix_id.Flake_ref.t; update_all : bool }
  | Flake_security of { flake_ref : Nix_id.Flake_ref.t; action : flake_security_action }
  | Store_verify of { paths : Nix_id.Store_path.t list; repair : bool }
  | Store_gc of { max_freed_bytes : int64 option }
  | Devenv_execute of { root : Nix_id.Devenv_root.t; action : devenv_action; budget : Nix_budget.t }

let is_read_only = function
  | Evaluate _ -> true
  | Build _ -> false
  | Shell_environment _ -> true
  | Flake_lock _ -> false
  | Flake_security _ -> true
  | Store_verify { repair; _ } -> not repair
  | Store_gc _ -> false
  | Devenv_execute { action; _ } ->
      (match action with
       | Shell _ | Info | Test -> true
       | Up _ | Build | Gc _ -> false)

let target_summary = function
  | Evaluate { target; pure; _ } ->
      let pstr = if pure then "pure" else "impure" in
      (match target with
       | Flake_attribute { flake_ref; attr } ->
           Printf.sprintf "eval (%s) %s#%s" pstr (Nix_id.Flake_ref.to_string flake_ref) (Nix_id.Attribute_path.to_string attr)
       | Raw_expression { expr } -> Printf.sprintf "eval (%s) raw expr (length %d)" pstr (String.length expr)
       | File_expression { path } -> Printf.sprintf "eval (%s) file %s" pstr path)
  | Build { target; keep_going; _ } ->
      let kstr = if keep_going then "keep-going" else "strict" in
      (match target with
       | Build_flake_attr { flake_ref; attr } ->
           Printf.sprintf "build (%s) %s#%s" kstr (Nix_id.Flake_ref.to_string flake_ref) (Nix_id.Attribute_path.to_string attr)
       | Build_drv { drv_path } -> Printf.sprintf "build (%s) drv %s" kstr (Nix_id.Store_path.to_string drv_path)
       | Build_store_path { path } -> Printf.sprintf "build (%s) path %s" kstr (Nix_id.Store_path.to_string path))
  | Shell_environment { flake_ref; _ } ->
      Printf.sprintf "shell %s" (Nix_id.Flake_ref.to_string flake_ref)
  | Flake_lock { flake_ref; update_all } ->
      Printf.sprintf "flake-lock (update_all=%b) %s" update_all (Nix_id.Flake_ref.to_string flake_ref)
  | Flake_security { flake_ref; action } ->
      let act_str = match action with
        | Audit -> "audit"
        | Generate_bom -> "generate-bom"
        | Verify_provenance { expected_commit } -> Printf.sprintf "verify-provenance (%s)" expected_commit
      in
      Printf.sprintf "flake-security (%s) %s" act_str (Nix_id.Flake_ref.to_string flake_ref)
  | Store_verify { paths; repair } ->
      Printf.sprintf "store-verify (repair=%b) %d paths" repair (List.length paths)
  | Store_gc { max_freed_bytes } ->
      let limit = match max_freed_bytes with Some b -> Printf.sprintf "limit=%Ld" b | None -> "all" in
      Printf.sprintf "store-gc (%s)" limit
  | Devenv_execute { root; action; _ } ->
      let act_str = match action with
        | Shell _ -> "shell"
        | Up _ -> "up"
        | Test -> "test"
        | Build -> "build"
        | Gc _ -> "gc"
        | Info -> "info"
      in
      Printf.sprintf "devenv (%s) in %s" act_str (Nix_id.Devenv_root.to_string root)

let intent_id t =
  let summary = target_summary t in
  let digest = Digestif.SHA256.digest_string summary in
  Nix_id.Intent_id.of_string_exn ("nix-intent-" ^ (Digestif.SHA256.to_hex digest |> fun s -> String.sub s 0 16))

let to_yojson t =
  `Assoc
    [ ("intent_id", `String (Nix_id.Intent_id.to_string (intent_id t)));
      ("read_only", `Bool (is_read_only t));
      ("summary", `String (target_summary t)) ]
