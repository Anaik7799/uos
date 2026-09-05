(* Print the canonical Figma design catalog (the OCaml-owned algebra's final
   interpretation) as JSON on stdout — the authoritative input for any
   external Figma projection. Report-only. *)

let () =
  Zigvm_harness_support.Figma_design.Final.default ()
  |> Zigvm_harness_support.Figma_design.to_yojson
  |> Yojson.Safe.pretty_to_string
  |> print_endline
