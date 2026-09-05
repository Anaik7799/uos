let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let () =
  check "OP-1 exact operation denominator"
    (List.length Nix_operation.all = 16);

  check "OP-2 all operations have distinct keys"
    (let keys = List.map (fun op -> (Nix_operation.declaration op).key) Nix_operation.all in
     List.length keys = List.length (List.sort_uniq String.compare keys));

  check "OP-3 find matches every declared key"
    (List.for_all
       (fun op ->
          let d = Nix_operation.declaration op in
          Nix_operation.find d.key = Some op)
       Nix_operation.all
     && Nix_operation.find "invalid-key" = None);

  check "OP-4 all operations are safe declarations"
    (List.for_all Nix_operation.declaration_is_safe Nix_operation.all);

  if !failures <> [] then begin
    List.iter (fun f -> Printf.eprintf "FAIL: %s\n" f) !failures;
    exit 1
  end else
    print_endline "PASS test_nix_operation"
