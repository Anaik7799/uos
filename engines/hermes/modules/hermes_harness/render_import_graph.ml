(* Static import graph over the frozen Hermes reference, plus anchor coverage:
   which capability source anchors are imported (referenced) vs orphaned. Offline;
   no execution. Reuses Hermes_imports (over Hermes_analysis) and the catalog. *)

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  let reference_root = Bootstrap.reference_root root in
  let summary = Hermes_imports.analyze ~root:reference_root in
  Printf.printf "%s\n\n" (Hermes_imports.describe summary);
  let anchors =
    Capability_catalog.all
    |> List.concat_map (fun (c : Capability_catalog.capability) -> c.Capability_catalog.source_anchors)
    |> List.filter (fun a -> Filename.check_suffix a ".py")
    |> List.sort_uniq compare
  in
  let coverage = Hermes_imports.anchor_coverage summary ~anchors in
  let referenced =
    List.length (List.filter (fun (a : Hermes_imports.anchor_status) -> a.referenced) coverage)
  in
  Printf.printf "capability .py anchors: %d referenced / %d total (%d orphaned)\n" referenced
    (List.length coverage) (List.length coverage - referenced);
  List.iter
    (fun (a : Hermes_imports.anchor_status) ->
      if not a.referenced then Printf.printf "  orphan: %s (%s)\n" a.anchor a.module_name)
    coverage
