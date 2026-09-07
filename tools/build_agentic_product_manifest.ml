#!/usr/bin/env -S opam exec -- ocaml
#use "product_catalog.ml";;
(* The initial file-based catalog builder is retired after SQLite import.
   Export the exact immutable database revision to stdout. New specifications
   use the versioned catalog import API; this command never rewrites JSON files
   or silently resamples a moving source tree under a historical revision. *)
let () =
  try
    require (Array.length Sys.argv = 1) "usage: ocaml tools/build_agentic_product_manifest.ml";
    with_db ~readonly:true "data/sqlite/uos_verification_tracking.sqlite3" (fun db ->
      match query db "SELECT manifest,manifest_sha256 FROM product_imports WHERE spec_id=? AND revision=?"
        [s "uos-agentic-infrastructure-and-product-management"; s "20260907-1837"] with
      | [[Sqlite3.Data.TEXT body; Sqlite3.Data.TEXT digest]] ->
          require (sha body = digest) "stored manifest digest mismatch";
          validate (Yojson.Basic.from_string body);
          print_endline body
      | _ -> fail "canonical SQLite product revision is missing")
  with e -> prerr_endline ("product-export: " ^ Printexc.to_string e); exit 1
