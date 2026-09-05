let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let () =
  let p1 = Nix_id.Store_path.of_string_exn "/nix/store/abc-hello-1.0" in
  let p2 = Nix_id.Store_path.of_string_exn "/nix/store/def-glibc-2.38" in
  let p3 = Nix_id.Store_path.of_string_exn "/nix/store/ghi-gcc-13" in

  let set1 = Nix_algebra.Closure_set.singleton p1 in
  let set2 = Nix_algebra.Closure_set.singleton p2 in
  let set3 = Nix_algebra.Closure_set.singleton p3 in

  check "ALG-1 closure set satisfies join-semilattice laws"
    (Nix_algebra.Laws.verify_closure_join_semilattice set1 set2 set3);

  let lock1 = [ { Nix_algebra.Flake_lock_composition.name = "nixpkgs"; locked_rev = "rev1"; nar_hash = "sha256-a" } ] in
  let lock2 = [ { Nix_algebra.Flake_lock_composition.name = "devenv"; locked_rev = "rev2"; nar_hash = "sha256-b" } ] in

  check "ALG-2 flake lock composition satisfies monoid laws"
    (Nix_algebra.Laws.verify_flake_lock_monoid lock1 lock2);

  check "ALG-3 flake lock is idempotent"
    (Nix_algebra.Flake_lock_composition.is_idempotent lock1);

  let layer1 = { Nix_algebra.Devenv_module_overlay.env_vars = [ ("FOO", "1") ]; packages = [ "git" ]; services = [] } in
  let layer2 = { Nix_algebra.Devenv_module_overlay.env_vars = [ ("BAR", "2") ]; packages = [ "z3" ]; services = [ "postgres" ] } in
  let layer3 = { Nix_algebra.Devenv_module_overlay.env_vars = [ ("FOO", "override") ]; packages = [ "opam" ]; services = [] } in

  check "ALG-4 devenv overlay composition is associative"
    (Nix_algebra.Laws.verify_devenv_overlay_associativity layer1 layer2 layer3);

  let composed = Nix_algebra.Devenv_module_overlay.compose_all [ layer1; layer2; layer3 ] in
  check "ALG-5 composed layer preserves override precedence"
    (List.assoc "FOO" composed.env_vars = "override"
     && List.mem "git" composed.packages
     && List.mem "z3" composed.packages
     && List.mem "opam" composed.packages
     && List.mem "postgres" composed.services);

  if !failures <> [] then begin
    List.iter (fun f -> Printf.eprintf "FAIL: %s\n" f) !failures;
    exit 1
  end else
    print_endline "PASS test_nix_algebra"
