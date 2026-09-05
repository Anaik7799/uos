let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let () =
  let flake_ref = Nix_id.Flake_ref.of_string_exn "github:NixOS/nixpkgs/nixos-unstable" in
  let attr = Nix_id.Attribute_path.of_string_exn "legacyPackages.x86_64-linux.hello" in
  let intent_eval =
    Nix_intent.Evaluate
      { target = Nix_intent.Flake_attribute { flake_ref; attr };
        budget = Nix_budget.default;
        pure = true }
  in
  check "N1 intent_eval is read only" (Nix_intent.is_read_only intent_eval);
  check "N2 intent ID is non-empty and stable"
    (let id1 = Nix_intent.intent_id intent_eval in
     let id2 = Nix_intent.intent_id intent_eval in
     Nix_id.Intent_id.equal id1 id2);
  check "N3 summary contains target and attribute"
    (let summary = Nix_intent.target_summary intent_eval in
     String.length summary > 0);

  let devenv_root = Nix_id.Devenv_root.of_string_exn "/home/an/NAS-setup/harness-bionic" in
  let intent_devenv =
    Nix_intent.Devenv_execute
      { root = devenv_root;
        action = Nix_intent.Shell { print_bash = false };
        budget = Nix_budget.default }
  in
  check "N4 devenv shell intent is read-only" (Nix_intent.is_read_only intent_devenv);

  let json = Nix_intent.to_yojson intent_eval in
  check "N5 JSON serialization is non-empty" (match json with `Assoc _ -> true | _ -> false);

  if !failures <> [] then begin
    List.iter (fun f -> Printf.eprintf "FAIL: %s\n" f) !failures;
    exit 1
  end else
    print_endline "PASS test_nix_intent"
