(** High-level controller facade for intent-based Nix and Devenv operations.
    Complies strictly with R31 by verifying contracts and emitting immutable receipts. *)

let execute_intent intent =
  let t0 = Unix.gettimeofday () in
  match Nix_command_contract.synthesize intent with
  | Error err ->
      let duration_ms = int_of_float ((Unix.gettimeofday () -. t0) *. 1000.0) in
      Nix_receipt_core.make
        ~intent
        ~duration_ms
        ~output_paths:[]
        ~closure_digest:None
        ~summary:(Nix_error.to_string err)
        ~verdict:(Nix_receipt_core.Failed err)
  | Ok contract ->
      let summary = Nix_command_contract.to_string_summary contract in
      let duration_ms = int_of_float ((Unix.gettimeofday () -. t0) *. 1000.0) in
      Nix_receipt_core.make
        ~intent
        ~duration_ms
        ~output_paths:[]
        ~closure_digest:None
        ~summary:(Printf.sprintf "Admitted and prepared: %s" summary)
        ~verdict:Nix_receipt_core.Success
