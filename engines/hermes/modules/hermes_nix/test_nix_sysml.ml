let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let () =
  check "SYS-1 all 7 architectural blocks defined"
    (List.length Nix_sysml.all_blocks = 7);

  check "SYS-2 each block defines non-empty ports and constraints"
    (List.for_all (fun b -> b.Nix_sysml.ports <> [] && b.constraints <> []) Nix_sysml.all_blocks);

  check "SYS-3 block lookup by kind succeeds"
    (match Nix_sysml.find_block Nix_sysml.Substrate_store_block with
     | Some b -> String.equal b.name "NixSubstrateStore"
     | None -> false);

  check "SYS-4 SysML v2 DSL generation produces valid part def syntax"
    (let b = List.hd Nix_sysml.all_blocks in
     let dsl = Nix_sysml.to_sysml_v2_dsl b in
     String.starts_with ~prefix:"part def NixSubstrateStore" dsl);

  if !failures <> [] then begin
    List.iter (fun f -> Printf.eprintf "FAIL: %s\n" f) !failures;
    exit 1
  end else
    print_endline "PASS test_nix_sysml"
