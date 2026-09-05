let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let () =
  let flake_ref = Nix_id.Flake_ref.of_string_exn "nixpkgs" in
  let attr = Nix_id.Attribute_path.of_string_exn "hello" in
  let intent_eval =
    Nix_intent.Evaluate
      { target = Nix_intent.Flake_attribute { flake_ref; attr };
        budget = Nix_budget.default;
        pure = true }
  in
  match Nix_command_contract.synthesize intent_eval with
  | Error err ->
      failures := ("CC-1 synthesis failed: " ^ Nix_error.to_string err) :: !failures
  | Ok contract ->
      check "CC-1 executable is nix" (String.equal contract.executable "nix");
      check "CC-2 args contain eval, --json, and target"
        (List.mem "eval" contract.args && List.mem "--json" contract.args && List.mem "nixpkgs#hello" contract.args);
      check "CC-3 summary is generated" (String.length (Nix_command_contract.to_string_summary contract) > 0);

  let root = Nix_id.Devenv_root.of_string_exn "/home/an/NAS-setup/harness-bionic" in
  let intent_devenv =
    Nix_intent.Devenv_execute
      { root;
        action = Nix_intent.Up { detach = true; services = [] };
        budget = Nix_budget.default }
  in
  match Nix_command_contract.synthesize intent_devenv with
  | Error err ->
      failures := ("CC-4 devenv synthesis failed: " ^ Nix_error.to_string err) :: !failures
  | Ok contract ->
      check "CC-4 executable is devenv" (String.equal contract.executable "devenv");
      check "CC-5 args contain up and -d" (List.mem "up" contract.args && List.mem "-d" contract.args);
      check "CC-6 DEVENV_ROOT env is set" (List.assoc "DEVENV_ROOT" contract.env_overrides = "/home/an/NAS-setup/harness-bionic");

  if !failures <> [] then begin
    List.iter (fun f -> Printf.eprintf "FAIL: %s\n" f) !failures;
    exit 1
  end else
    print_endline "PASS test_nix_command_contract"
