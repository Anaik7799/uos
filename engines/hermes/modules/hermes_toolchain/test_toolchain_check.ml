(* The gate's derivation, tested against the SHIPPED functions.

   The first cut copied these functions into this file by value, with a
   comment saying a divergence would be "caught by T5, which runs the
   real tool". T5 ran the copy, not the tool, and the copies had already
   diverged on tab handling. Every check below now calls
   `Toolchain_core`, so a test passing here is evidence about the code
   that runs.

   Each law names the defect it exists for; all of them were found by
   adversarial review of the first cut, not by this suite. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

open Toolchain_core

let approval_crypto_manifest =
  "(\n\
  \  (package \"mirage-crypto-ec\")\n\
  \  (version \"2.2.0\")\n\
  \  (source-url \"https://github.com/mirage/mirage-crypto/releases/download/v2.2.0/mirage-crypto-2.2.0.tbz\")\n\
  \  (source-commit \"5f26ca1c9284fe9c93ab23768ff88ba345b360c5\")\n\
  \  (archive-sha256 \"4b87091b6a77843bf97a74aae2e7da21310307ff7d2105712c4369680122d80a\")\n\
  \  (archive-sha512 \"3361649703d0e391e5adc40770dcb4dcbee2ecd27a64962e28c7f8240a67131efe9226a5240ac7a019c1464f217abec9c71dbb8412ef2b4eafeb4ad8e3931805\")\n\
  \  (api \"Mirage_crypto_ec.Ed25519.verify ~key signature ~msg\")\n\
  )\n"

let replace_once ~needle ~replacement text =
  let text_length = String.length text in
  let needle_length = String.length needle in
  let rec find index =
    if index + needle_length > text_length then None
    else if String.sub text index needle_length = needle then Some index
    else find (index + 1)
  in
  match find 0 with
  | None -> failwith ("test fixture does not contain " ^ needle)
  | Some index ->
      String.sub text 0 index ^ replacement
      ^ String.sub text (index + needle_length)
          (text_length - index - needle_length)

let validate_approval_crypto ?(derived_packages = [ "mirage-crypto-ec" ])
    ?(installed_version = Some "2.2.0")
    ?(provenance_manifest = Some approval_crypto_manifest)
    ?(provider_self_test = Some true) () =
  validate_approval_crypto_supply_chain ~derived_packages ~installed_version
    ~provenance_manifest ~provider_self_test

let () =
  check "T1 a single-line stanza yields its libraries" (fun () ->
      libraries_of_dune "(executable (name x) (libraries unix tyxml))" = [ "tyxml"; "unix" ]);
  check "T2 a MULTI-LINE stanza is read whole" (fun () ->
      libraries_of_dune "(library\n (name a)\n (libraries hermes_wiki_core\n   yojson))"
      = [ "hermes_wiki_core"; "yojson" ]);
  check "T3 TABS separate tokens (the divergence the copied parser had)" (fun () ->
      libraries_of_dune "(libraries\tcore\tsqlite3)" = [ "core"; "sqlite3" ]);
  check "T4 (re_export x) IS a dependency, not a token to drop" (fun () ->
      (* the first cut dropped it AND its test asserted the drop was right *)
      libraries_of_dune "(libraries (re_export tyxml) unix)" = [ "tyxml"; "unix" ]);
  check "T5 (select f.ml from (bar -> a.ml) (-> b.ml)) contributes bar, not filenames"
    (fun () ->
      libraries_of_dune "(libraries (select f.ml from (bar -> a.ml) (-> b.ml)) unix)"
      = [ "bar"; "unix" ]);
  check "T6 a ';' comment inside a stanza is NOT a package list" (fun () ->
      (* unhandled, this refused a good switch with fabricated packages *)
      libraries_of_dune "(libraries yojson\n  ; smtml is only for the solver leg\n  smtml)"
      = [ "smtml"; "yojson" ]);
  check "T7 a commented-OUT stanza contributes nothing" (fun () ->
      libraries_of_dune "; (libraries notty ounit2)\n(library (name a) (libraries unix))"
      = [ "unix" ]);
  check "T8 PPX dependencies are derived — they are real opam packages" (fun () ->
      (* the entire (pps ...) class was invisible; ppx_jane was the
         comment's own worked example and the code could not see it *)
      pps_of_dune "(preprocess (pps ppx_jane js_of_ocaml-ppx bonsai.ppx_bonsai))"
      = [ "bonsai.ppx_bonsai"; "js_of_ocaml-ppx"; "ppx_jane" ]);
  check "T9 no stanza yields nothing, never an exception" (fun () ->
      libraries_of_dune "(rule (targets x))" = []
      && libraries_of_dune "" = []
      && pps_of_dune "" = []);
  check "T10 (names a b c) binds EVERY name, not one junk token" (fun () ->
      (* `(name` as a prefix captured `(names hde_stubs)` as "s hde_stubs" *)
      let d = defined_in_dune "(tests (names t1 t2 t3))" in
      List.mem "t1" d && List.mem "t2" d && List.mem "t3" d);
  check "T11 (public_name p.lib) binds both the package and the full name" (fun () ->
      let d = defined_in_dune "(library (name sa_plan) (public_name hermes_workspace.sa_plan))" in
      List.mem "sa_plan" d && List.mem "hermes_workspace" d
      && List.mem "hermes_workspace.sa_plan" d);
  check "T12 stdlib libraries are never opam requirements" (fun () ->
      external_libraries ~used:[ "unix"; "threads.posix"; "yojson" ] ~defined:[] = [ "yojson" ]);
  check "T13 a dotted library reduces to its opam PACKAGE" (fun () ->
      external_libraries ~used:[ "bonsai.ppx_bonsai" ] ~defined:[] = [ "bonsai" ]);
  check "T14 a library this tree defines is not required from the switch" (fun () ->
      external_libraries ~used:[ "hermes_wiki_core"; "tyxml" ] ~defined:[ "hermes_wiki_core" ]
      = [ "tyxml" ]);
  check "T15 meta-falsification: the derivation CAN report a missing package" (fun () ->
      external_libraries ~used:[ "definitely_not_installed" ] ~defined:[]
      = [ "definitely_not_installed" ]);
  check "T16 mirage-crypto-ec is derived from its literal Dune library" (fun () ->
      external_libraries ~used:[ "mirage-crypto-ec" ] ~defined:[]
      = [ "mirage-crypto-ec" ]);
  check "T17 exact approval-crypto supply-chain evidence is admitted" (fun () ->
      validate_approval_crypto () = Ok ());
  check "T18 a missing derived provider dependency refuses" (fun () ->
      validate_approval_crypto ~derived_packages:[] ()
      = Error [ Approval_crypto_dependency_not_derived ]);
  check "T19 an unavailable installed provider version refuses" (fun () ->
      validate_approval_crypto ~installed_version:None ()
      = Error [ Approval_crypto_version_unavailable ]);
  check "T20 a wrong installed provider version refuses" (fun () ->
      validate_approval_crypto ~installed_version:(Some "2.1.0") ()
      = Error
          [ Approval_crypto_version_mismatch
              { expected = "2.2.0"; observed = "2.1.0" } ]);
  check "T21 a missing provenance manifest refuses" (fun () ->
      validate_approval_crypto ~provenance_manifest:None ()
      = Error [ Approval_crypto_manifest_missing ]);
  check "T22 every frozen provenance-field mutant refuses" (fun () ->
      [ ("mirage-crypto-ec", "mirage-crypto");
        ("2.2.0", "2.2.1");
        ("https://github.com/", "https://example.invalid/");
        ("5f26ca1c9284fe9c93ab23768ff88ba345b360c5",
         "0f26ca1c9284fe9c93ab23768ff88ba345b360c5");
        ("4b87091b6a77843bf97a74aae2e7da21310307ff7d2105712c4369680122d80a",
         "0b87091b6a77843bf97a74aae2e7da21310307ff7d2105712c4369680122d80a");
        ("3361649703d0e391e5adc40770dcb4dcbee2ecd27a64962e28c7f8240a67131efe9226a5240ac7a019c1464f217abec9c71dbb8412ef2b4eafeb4ad8e3931805",
         "0361649703d0e391e5adc40770dcb4dcbee2ecd27a64962e28c7f8240a67131efe9226a5240ac7a019c1464f217abec9c71dbb8412ef2b4eafeb4ad8e3931805");
        ("Mirage_crypto_ec.Ed25519.verify ~key signature ~msg",
         "Mirage_crypto_ec.Ed25519.sign ~key message") ]
      |> List.for_all (fun (needle, replacement) ->
             let mutated =
               replace_once ~needle ~replacement approval_crypto_manifest
             in
             validate_approval_crypto ~provenance_manifest:(Some mutated) ()
             = Error [ Approval_crypto_manifest_mismatch ]));
  check "T23 an unavailable provider self-test refuses" (fun () ->
      validate_approval_crypto ~provider_self_test:None ()
      = Error [ Approval_crypto_self_test_unavailable ]);
  check "T24 a failed provider self-test refuses" (fun () ->
      validate_approval_crypto ~provider_self_test:(Some false) ()
      = Error [ Approval_crypto_self_test_failed ])

let () =
  Printf.printf "toolchain_core: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_toolchain_check" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.toolchain_core ]);
  exit (Suite_telemetry.exit_code self)
